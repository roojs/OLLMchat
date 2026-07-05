// ollmfilesd/Vector/BackgroundScan.vala
//
// BackgroundScan – async file-index queue on the daemon MainLoop.
// Integrates with Indexer and emits event.vector.scan_update RPC notifications.
//
namespace OLLMfilesd.Vector {

    /**
     * Processes a queue of file paths to be indexed on the daemon default MainLoop.
     */
    public class BackgroundScan : GLib.Object {

        private OllmfilesdApplication app;
        private OLLMfilesd.ProjectManager project_manager;
        private OLLMchat.Settings.Config2 config;

        private Gee.ArrayQueue<BackgroundScanItem>? file_queue = null;
        private bool queue_processing = false;
        private bool stop_requested = false;
        private Indexer? indexer = null;

        /**
         * @param project_manager Daemon ProjectManager (db, vector_db_path)
         * @param config Application config
         */
        public BackgroundScan (OllmfilesdApplication app,
                               OLLMfilesd.ProjectManager project_manager,
                               OLLMchat.Settings.Config2 config)
        {
            this.app = app;
            this.project_manager = project_manager;
            this.config = config;
        }

        /**
         * Probe embed dimension and set {@link OLLMfilesd.ProjectManager.vector_db}.
         * Uses dimension 0 when codebase_search is not configured.
         * Clears cached {@link Indexer} so reopen picks up a fresh FAISS handle.
         */
        public async void open_vector_db ()
        {
            this.indexer = null;
            var dimension = 0;
            try {
                if (yield OLLMvector2.Database.check_required_models_available (
                    this.config)) {
                    var probe = new OLLMvector2.Database (
                        this.config,
                        this.project_manager.vector_db_path,
                        0);
                    yield probe.connection ("analysis", true);
                    dimension = yield probe.embed_dimension ();
                }
            } catch (GLib.Error e) {
                GLib.warning (
                    "vector index: " + e.message);
            }
            this.project_manager.vector_db = new OLLMvector2.Database (
                this.config,
                this.project_manager.vector_db_path,
                dimension);
        }

        /**
         * Pause indexing after the current file finishes.
         *
         * Pending queue entries are preserved. The loop emits
         * {{{event.vector.scan_update}}} with remaining queue size when idle.
         */
        public void stop ()
        {
            this.stop_requested = true;
        }

        /**
         * Append a file to the index queue when not already queued.
         *
         * @param project_path Project root path
         * @param file_path Absolute file path to index
         */
        public void append_file (string project_path, string file_path)
        {
            this.queueFile (new BackgroundScanItem (project_path, file_path));
        }

        /**
         * Enqueue all files of a project that need scanning.
         *
         * @param project The active project folder, or null to skip.
         */
        public void scanProject (OLLMfilesd.Folder? project)
        {
            if (project == null
                || this.project_manager.vector_db.dimension == 0) {
                return;
            }

            var project_path = project.path;
            var pm = project.manager;
            GLib.Timeout.add (1000, () => {
                if (pm.scanning.size > 0) {
                    GLib.debug ("semantic index waiting filesystem scan active=%u",
                        pm.scanning.size);
                    return true;
                }
                this.queueProject.begin (project_path);
                return false;
            });
        }

        /**
         * Enqueue a single file for scanning (e.g. after a save).
         *
         * @param file The File object that was modified.
         * @param project The project folder containing this file, or null to skip.
         */
        public void scanFile (OLLMfilesd.File file, OLLMfilesd.Folder? project)
        {
            if (project == null
                || this.project_manager.vector_db.dimension == 0) {
                return;
            }

            var file_path = file.path;
            var project_path = project.path;
            var pm = project.manager;
            GLib.Timeout.add (1000, () => {
                if (pm.scanning.size > 0) {
                    GLib.debug ("semantic index waiting filesystem scan active=%u",
                        pm.scanning.size);
                    return true;
                }
                this.queueFile (new BackgroundScanItem (project_path, file_path));
                return false;
            });
        }

        private void emit_scan_update (int queue_size, string current_file)
        {
            GLib.debug ("scan banner update queue_size=%d file=%s",
                queue_size, GLib.Path.get_basename (current_file));
            this.app.broadcast (new OLLMrpc.Notification () {
                method = "event.vector.scan_update",
                object_type = "Vector",
                message = "%d %s".printf (queue_size, current_file),
            });
        }

        private class BackgroundScanItem {
            public string project_path;
            public string file_path;

            public BackgroundScanItem (string project_path, string file_path)
            {
                this.project_path = project_path;
                this.file_path = file_path;
            }
        }

        private async void queueProject (string path)
        {
            GLib.debug ("semantic index queue project path=%s", path);

            yield this.project_manager.load_projects_from_db ();

            var project = this.project_manager.projects.path_map.get (path);
            if (project == null) {
                GLib.warning ("could not find project %s", path);
                return;
            }

            yield project.load_files_from_db ();
            project.project_files.update_from (project);

            int queued_count = 0;
            foreach (var project_file in project.project_files) {
                if (project_file.file.delete_id > 0) {
                    continue;
                }
                if (project_file.file.last_vector_scan >= project_file.file.mtime_on_disk ()) {
                    continue;
                }
                this.queueFile (new BackgroundScanItem (project.path, project_file.file.path));
                queued_count++;
            }

            GLib.debug ("queued %d files for project %s", queued_count, path);
        }

        private void queueFile (BackgroundScanItem item)
        {
            if (this.file_queue == null) {
                this.file_queue = new Gee.ArrayQueue<BackgroundScanItem> ();
            }
            this.file_queue.offer (item);
            this.startQueue.begin ();
        }

        private async void startQueue ()
        {
            if (this.queue_processing) {
                return;
            }
            this.queue_processing = true;

            if (this.file_queue == null) {
                this.file_queue = new Gee.ArrayQueue<BackgroundScanItem> ();
            }

            while (true) {
                var next_item = this.file_queue.poll ();

                if (next_item == null) {
                    this.queue_processing = false;
                    GLib.debug ("semantic index queue empty");
                    this.emit_scan_update (0, "");
                    break;
                }

                var project = this.project_manager.projects.path_map.get (next_item.project_path);
                if (project == null) {
                    GLib.warning ("could not find project %s for file %s",
                        next_item.project_path, next_item.file_path);
                    continue;
                }

                yield project.load_files_from_db ();
                project.project_files.update_from (project);

                var project_file = project.project_files.child_map.get (next_item.file_path);
                if (project_file == null) {
                    continue;
                }

                this.emit_scan_update ((int) this.file_queue.size, next_item.file_path);

                GLib.debug ("semantic index file=%s queue=%u",
                    next_item.file_path, this.file_queue.size);

                if (this.indexer == null) {
                    this.indexer = new Indexer (
                        this.config,
                        this.project_manager.vector_db,
                        this.project_manager.db,
                        this.project_manager);
                    this.indexer.progress.connect ((_c, _t, _p, success) => {
                        if (!success) {
                            return;
                        }
                        GLib.debug ("persisting db after indexed file");
                        this.project_manager.db.backupDB ();
                    });
                }

                try {
                    yield this.indexer.index_filebase (project_file.file, false, false);
                } catch (GLib.Error e) {
                    GLib.warning ("semantic index error file=%s: %s",
                        next_item.file_path, e.message);
                }
                GLib.debug ("indexed file=%s queue=%u",
                    next_item.file_path, this.file_queue.size);
            }
        }
    }
}
