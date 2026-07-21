// ollmfilesd/Vector/BackgroundScan.vala
//
// BackgroundScan – semantic (FAISS) index queue on the daemon MainLoop.
// Separate from filesystem read_dir; emits event.vector.* RPC notifications.
//
namespace OLLMfilesd.Vector {

    /**
     * Queues and runs per-file vector indexing after filesystem scan completes.
     */
    public class BackgroundScan : GLib.Object {

        private OllmfilesdApplication app;
        private OLLMfilesd.ProjectManager project_manager;
        private OLLMchat.Settings.Config2 config;

        private Gee.ArrayQueue<BackgroundScanItem>? file_queue = null;
        internal bool queue_processing { get; private set; default = false; }
        /**
         * When true, {@link startQueue} exits after the current file; queue entries
         * are preserved. Set by ''Codebase.stop''; cleared by ''Codebase.start''.
         */
        public bool stop_requested { get; set; default = false; }
        private Indexer? indexer = null;
        private string queued_project = "";

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

            this.project_manager.scan_idle.connect (() => {
                if (this.queued_project != "") {
                    this.queueProject.begin (this.queued_project);
                    this.queued_project = "";
                    return;
                }
                if (this.file_queue != null
                    && this.file_queue.size > 0
                    && !this.queue_processing) {
                    this.startQueue.begin ();
                }
            });
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
         * Enqueue all project files that need vector indexing.
         *
         * @param project The active project folder, or null to skip.
         */
        public void queue_project (OLLMfilesd.Folder? project)
        {
            if (project == null
                || this.project_manager.vector_db == null
                || this.project_manager.vector_db.dimension == 0) {
                return;
            }

            if (project.manager.scanning.size > 0) {
                GLib.debug ("vector index defer path=%s scanning_active=%u",
                    project.path, project.manager.scanning.size);
                this.queued_project = project.path;
                return;
            }
            this.queueProject.begin (project.path);
        }

        /**
         * Enqueue one file for vector indexing (e.g. after a save).
         *
         * @param file The File object that was modified.
         * @param project The project folder containing this file, or null to skip.
         */
        public void queue_file (OLLMfilesd.File file, OLLMfilesd.Folder? project)
        {
            if (project == null
                || this.project_manager.vector_db == null
                || this.project_manager.vector_db.dimension == 0) {
                return;
            }

            var item = new BackgroundScanItem (project.path, file.path);
            if (project.manager.scanning.size > 0) {
                this.queueFile (item, false);
                return;
            }
            this.queueFile (item);
        }

        private void emit_scan_update (int queue_size, string current_file)
        {
            GLib.debug ("vector index progress queue_size=%d file=%s",
                queue_size, GLib.Path.get_basename (current_file));
            var notif = new OLLMrpc.Notification () {
                method = "event.vector.scan_update",
                object_type = "Vector",
                message = "%d %s".printf (queue_size, current_file),
            };
            if (this.stop_requested) {
                notif.action = "rpc.Codebase.start";
                notif.action_label = "Resume";
                this.broadcast (notif);
                return;
            }
            if (queue_size > 0) {
                notif.action = "rpc.Codebase.stop";
                notif.action_label = "Pause";
            }
            this.broadcast (notif);
        }

        /**
         * Push an out-of-band vector RPC notification to all connected clients.
         */
        public void broadcast (OLLMrpc.Notification notification)
        {
            this.app.broadcast (notification);
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

        internal async int queueProject (
            string path,
            string only_file = "",
            bool auto_start = true
        )
        {
            GLib.debug ("vector index queue project path=%s", path);

            yield this.project_manager.load_projects_from_db ();

            var project = this.project_manager.projects.path_map.get (path);
            if (project == null) {
                GLib.warning ("could not find project %s", path);
                return 0;
            }

            yield project.load_files_from_db ();
            project.project_files.update_from (project);

            var queued_count = 0;
            if (only_file != "") {
                var only_file_path = GLib.Path.is_absolute (only_file)
                    ? only_file
                    : GLib.Path.build_filename (project.path, only_file);
                var project_file = project.project_files.child_map.get (
                    only_file_path
                );
                if (project_file.file.delete_id > 0) {
                    return 0;
                }
                if (project_file.file.is_ignored || !project_file.file.is_text) {
                    return 0;
                }
                if (project_file.file.last_vector_scan
                    >= project_file.file.mtime_on_disk ()) {
                    return 0;
                }
                this.queueFile (
                    new BackgroundScanItem (
                        project.path,
                        project_file.file.path
                    ),
                    false
                );
                GLib.debug ("vector index queued 1 file for project %s", path);
                if (auto_start) {
                    this.startQueue.begin ();
                }
                return 1;
            }

            foreach (var project_file in project.project_files) {
                if (project_file.file.delete_id > 0) {
                    continue;
                }
                if (project_file.file.is_ignored || !project_file.file.is_text) {
                    continue;
                }
                if (project_file.file.last_vector_scan
                    >= project_file.file.mtime_on_disk ()) {
                    continue;
                }
                this.queueFile (
                    new BackgroundScanItem (
                        project.path,
                        project_file.file.path
                    ),
                    false
                );
                queued_count++;
            }

            GLib.debug ("vector index queued %d files for project %s",
                queued_count, path);
            if (auto_start && queued_count > 0) {
                this.startQueue.begin ();
            }
            return queued_count;
        }

        private void queueFile (
            BackgroundScanItem item,
            bool auto_start = true
        )
        {
            if (this.file_queue == null) {
                this.file_queue = new Gee.ArrayQueue<BackgroundScanItem> ();
            }
            foreach (var queued in this.file_queue) {
                if (queued.project_path == item.project_path
                    && queued.file_path == item.file_path) {
                    return;
                }
            }
            this.file_queue.offer (item);
            if (auto_start) {
                this.startQueue.begin ();
            }
        }

        internal async void startQueue ()
        {
            if (this.queue_processing) {
                return;
            }

            if (this.file_queue == null) {
                this.file_queue = new Gee.ArrayQueue<BackgroundScanItem> ();
            }

            if (this.file_queue.size == 0) {
                return;
            }

            this.queue_processing = true;
            this.broadcast (new OLLMrpc.Notification () {
                method = "event.vector.scan_start",
                object_type = "Vector",
                message = "",
                action = "rpc.Codebase.stop",
                action_label = "Pause",
            });

            while (true) {
                if (this.stop_requested) {
                    this.queue_processing = false;
                    GLib.debug (
                        "vector index paused queue=%u",
                        this.file_queue.size
                    );
                    this.emit_scan_update ((int) this.file_queue.size, "");
                    break;
                }

                var next_item = this.file_queue.poll ();

                if (next_item == null) {
                    this.queue_processing = false;
                    GLib.debug ("vector index queue empty");
                    this.emit_scan_update (0, "");
                    this.broadcast (new OLLMrpc.Notification () {
                        method = "event.vector.scan_end",
                        object_type = "Vector",
                        message = "",
                    });
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

                GLib.debug ("vector index file=%s queue=%u",
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
                    GLib.warning ("vector index error file=%s: %s",
                        next_item.file_path, e.message);
                }
                GLib.debug ("vector index done file=%s queue=%u",
                    next_item.file_path, this.file_queue.size);

                if (this.stop_requested) {
                    this.queue_processing = false;
                    GLib.debug (
                        "vector index paused queue=%u",
                        this.file_queue.size
                    );
                    this.emit_scan_update ((int) this.file_queue.size, "");
                    break;
                }
            }
        }
    }
}
