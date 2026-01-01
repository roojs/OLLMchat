// libocvector/BackgroundScan.vala
//
// BackgroundScan – a helper that runs a dedicated thread with its own MainLoop
// and processes a queue of file paths to be indexed.  It integrates with the
// OLLMvector indexing pipeline (Indexer) and emits signals so the UI can
// react to scan progress.
//
// The implementation follows the description in the project plan (Phase 7).

namespace OLLMvector {

    /**
     * BackgroundScan manages a background thread that continuously processes
     * file‑indexing jobs.  The thread is started on first use and lives for the
     * lifetime of the application.
     */
    public class BackgroundScan : GLib.Object {

        /**
         * Struct to track both project_path and file_path when queuing files.
         */
        private struct BackgroundScanItem {
            string project_path;
            string file_path;
        }

        /**
         * Emitted when a file scan completes.
         *
         * @param file_path The path of the file that was scanned.
         */
        public signal void file_scanned (string file_path);

        /**
         * Emitted when a project scan starts.
         *
         * @param project_path The path of the project being scanned.
         */
        public signal void project_scan_started (string project_path);

        /**
         * Emitted at the start of each file scan and when queue becomes empty.
         *
         * @param queue_size Current size of the file queue (number of files remaining).
         * @param current_file Path of the file currently being scanned (empty string "" when queue is empty).
         */
        public signal void scan_update (int queue_size, string current_file);

        private OLLMchat.Client embedding_client;          // OLLMchat.Client for LLM calls
        private Database vector_db;               // OLLMvector.Database (FAISS)
        private SQ.Database sql_db;               // SQ.Database for metadata
        private OLLMfiles.ProjectManager? worker_project_manager = null;   // ProjectManager instance for background thread
        private OLLMfiles.Folder? active_project = null;   // Track currently active project in background thread (for memory management)

        private GLib.Thread<void*>? worker_thread = null;
        private GLib.MainLoop? worker_loop = null;
        private GLib.MainContext? worker_context = null;
        private GLib.MainContext main_context;

        private Gee.ArrayQueue<BackgroundScanItem> file_queue;
        private bool queue_processing = false;

        private Indexer? indexer = null;

        /**
         * Creates a new BackgroundScan instance.
         *
         * @param embedding_client The OLLMchat.Client instance for LLM calls and embeddings.
         * @param vector_db The OLLMvector.Database instance for vector storage (FAISS).
         * @param sql_db The SQ.Database instance for metadata storage.
         */
        public BackgroundScan (OLLMchat.Client embedding_client,
                               Database vector_db,
                               SQ.Database sql_db) {
            this.embedding_client = embedding_client;
            this.vector_db = vector_db;
            this.sql_db = sql_db;

            this.file_queue = new Gee.ArrayQueue<BackgroundScanItem> ();
            this.main_context = GLib.MainContext.default ();
        }

        /**
         * Ensure ProjectManager exists in background thread context.
         */
        private void ensure_project_manager () {
            if (this.worker_project_manager == null) {
                // Create ProjectManager in background thread context
                // Use same sql_db (thread-safe in serialized mode)
                this.worker_project_manager = new OLLMfiles.ProjectManager(this.sql_db);
                // Default providers are fine - we only need to read from DB
            }
        }

        /**
         * Set active project and clear files from previous active project to free memory.
         * 
         * Note: This does NOT update database (is_active flag) - that's main thread's responsibility.
         * The background worker only manages memory, not database state.
         */
        private void set_active_project (OLLMfiles.Folder? project) {
            // If switching to a different project, clear files from previous project
            if (this.active_project != null && this.active_project != project) {
                // Clear all in-memory data (children, project_files, and resets last_scan to 0)
                // This will cause needs_reload() to return true on next access, forcing a reload
                this.active_project.clear_data();
                // Note: We do NOT update database (is_active flag) - that's the main thread's responsibility
                // The background worker only manages memory, not database state
            }
            this.active_project = project;
        }

        /**
         * Set active project and load files from database.
         * 
         * This combines set_active_project() and load_files_from_db() into one operation.
         * The load will automatically check needs_reload() and skip if no changes.
         */
        private async void set_active_project_and_load (OLLMfiles.Folder project) {
            this.set_active_project (project);
            yield project.load_files_from_db ();
        }

        /**
         * Ensure the background thread is running.
         */
        private void ensure_thread () {
            if (this.worker_thread != null) {
                return;
            }

            // Create MainContext for background thread
            this.worker_context = new GLib.MainContext ();

            // Start background thread
            try {
                this.worker_thread = new GLib.Thread<void*>.try ("background-scan-thread", () => {
                    // Set this context as thread default
                    this.worker_context.push_thread_default ();

                    // Create and run MainLoop
                    this.worker_loop = new GLib.MainLoop (this.worker_context);
                    this.worker_loop.run ();

                    // Clean up
                    this.worker_context.pop_thread_default ();
                    this.worker_loop = null;
                    this.worker_context = null;

                    return null;
                });
            } catch (GLib.Error e) {
                GLib.warning ("Failed to start background thread: %s", e.message);
                this.worker_thread = null;
                this.worker_context = null;
            }
        }

        /**
         * Enqueue all files of a project that need scanning.
         *
         * This method is safe to call from the UI thread. It will start the
         * background thread if not already running and dispatch the project
         * scanning work to the background thread.
         *
         * @param project The Project object representing the active project.
         */
        public void scanProject (OLLMfiles.Project project) {
            // Start thread if not already running.
            this.ensure_thread ();

            // Extract path before creating callback to avoid capturing object in closure.
            var project_path = project.path;

            // Emit start signal on main thread.
            this.emit_project_scan_started (project_path);

            // Dispatch the heavy work to the background thread via idle source.
            // Pass only the path string (thread-safe) - the background thread will
            // load the project from the database.
            var source = new GLib.IdleSource ();
            source.set_callback (() => {
                this.queueProject.begin (project_path);
                return false;
            });
            source.attach (this.worker_context);
        }

        /**
         * Enqueue a single file for scanning (e.g. after a save).
         *
         * This method is safe to call from the UI thread. It will start the
         * background thread if not already running and dispatch the file
         * scanning work to the background thread.
         *
         * @param file The File object that was modified.
         * @param project The Project object that contains this file.
         */
        public void scanFile (OLLMfiles.File file, OLLMfiles.Project project) {
            this.ensure_thread ();

            // Extract paths before creating callback to avoid capturing object in closure.
            var file_path = file.path;
            var project_path = project.path;

            // Dispatch to background thread.
            var source = new GLib.IdleSource ();
            source.set_callback (() => {
                var item = BackgroundScanItem() {
                    project_path = project_path,
                    file_path = file_path
                };
                this.queueFile (item);
                return false;
            });
            source.attach (this.worker_context);
        }

        /**
         * Process a project: load its files, check timestamps, and enqueue any
         * that need (re)scanning.
         *
         * @param path The path of the project to process.
         */
        private async void queueProject (string path) {
            // Ensure worker_project_manager exists
            this.ensure_project_manager ();

            // Load projects from database
            yield this.worker_project_manager.load_projects_from_db ();

            // Find project by path (O(1) lookup using path_map)
            var project = this.worker_project_manager.projects.path_map.get (path);
            if (project == null) {
                GLib.warning ("BackgroundScan: could not find project %s", path);
                return;
            }

            // Set as active project and load files from DB (will check needs_reload() internally)
            yield this.set_active_project_and_load (project);

            // Iterate through project_files.items (flat list, not hierarchical)
            foreach (var project_file in project.project_files.items) {
                // Access file via project_file.file
                var file = project_file.file;
                // Check if file needs scanning
                if (file.last_scan < file.mtime_on_disk ()) {
                    // Create BackgroundScanItem with project_path and file_path
                    var item = BackgroundScanItem() {
                        project_path = project.path,
                        file_path = file.path
                    };
                    this.queueFile (item);
                }
            }

            // Do NOT emit project_scan_completed - project scan just queues files,
            // completion is handled by file queue via scan_update signal
        }

        /**
         * Add a file item to the queue and ensure the queue processing loop is running.
         */
        private void queueFile (BackgroundScanItem item) {
            // All queue operations happen in the background thread context, so no mutex needed
            this.file_queue.offer (item);

            // Start queue processing (we're already in the background thread context)
            this.startQueue.begin ();
        }

        /**
         * Pull items from the queue and index them.  Runs in the background
         * thread's main context.
         */
        private async void startQueue () {
            // If already processing, just return (can be called multiple times safely)
            if (this.queue_processing) {
                return;
            }
            this.queue_processing = true;

            while (true) {
                // All queue operations happen in the background thread context, so no mutex needed
                var next_item = this.file_queue.poll ();
                var queue_size = (int)this.file_queue.size;

                if (next_item == null) {
                    // Queue empty – emit completion signal and exit loop.
                    this.queue_processing = false;
                    this.emit_scan_update (0, "");
                    break;
                }

                // Ensure worker_project_manager exists
                this.ensure_project_manager ();

                // Find the project by item.project_path (O(1) lookup using path_map)
                var project = this.worker_project_manager.projects.path_map.get (next_item.project_path);
                if (project == null) {
                    GLib.warning ("BackgroundScan: could not find project %s for file %s", next_item.project_path, next_item.file_path);
                    continue;
                }

                // Set as active project and reload files from database (state may have changed since queued)
                // This will automatically check needs_reload() and skip if no changes
                this.set_active_project (project);
                yield project.load_files_from_db ();

                // Find file in that project's project_files.child_map
                var project_file = project.project_files.child_map.get (next_item.file_path);
                if (project_file == null) {
                    // File doesn't exist in project - may have been deleted or moved
                    continue;
                }

                // Get File via project_file.file
                var file = project_file.file;

                // Emit scan_update signal at start of scan (before indexing)
                this.emit_scan_update (queue_size, next_item.file_path);

                // Lazily create/reuse the Indexer.
                if (this.indexer == null) {
                    this.indexer = new Indexer (this.vector_db, this.sql_db, this.embedding_client);
                }

                // Perform indexing.  Indexer.index_file() is expected to be async
                // but for simplicity we call it synchronously here.
                try {
                    this.indexer.index_file (file);
                } catch (GLib.Error e) {
                    GLib.warning ("BackgroundScan: indexing error for %s – %s", next_item.file_path, e.message);
                }

                // Emit per‑file signal.
                this.emit_file_scanned (next_item.file_path);
            }
        }

        /**
         * Emits file_scanned signal on the main thread.
         */
        private void emit_file_scanned (string file_path)
        {
            this.main_context.invoke (() => {
                this.file_scanned (file_path);
                return false;
            });
        }

        /**
         * Emits project_scan_started signal on the main thread.
         */
        private void emit_project_scan_started (string project_path)
        {
            this.main_context.invoke (() => {
                this.project_scan_started (project_path);
                return false;
            });
        }

        /**
         * Emits scan_update signal on the main thread.
         */
        private void emit_scan_update (int queue_size, string current_file)
        {
            this.main_context.invoke (() => {
                this.scan_update (queue_size, current_file);
                return false;
            });
        }

        /**
         * Stops the background thread gracefully.
         *
         * This method is not strictly required because the thread lives for the
         * lifetime of the application, but it provides a way for graceful shutdown
         * if the host wishes to stop it.
         */
        public void stop () {
            if (this.worker_loop != null) {
                this.worker_loop.quit ();
                this.worker_loop = null;
            }
            if (this.worker_thread != null) {
                this.worker_thread.join ();
                this.worker_thread = null;
            }
        }
    }
}
