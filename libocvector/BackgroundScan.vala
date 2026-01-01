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
         * Emitted when a project scan completes.
         *
         * @param project_path The path of the project that was scanned.
         * @param files_indexed The number of files that were indexed.
         */
        public signal void project_scan_completed (string project_path, int files_indexed);

        private OLLMchat.Client embedding_client;          // OLLMchat.Client for LLM calls
        private Database vector_db;               // OLLMvector.Database (FAISS)
        private SQ.Database sql_db;               // SQ.Database for metadata
        private OLLMfiles.ProjectManager project_manager;   // OLLMfiles.ProjectManager

        private GLib.Thread<void*>? worker_thread = null;
        private GLib.MainLoop? worker_loop = null;
        private GLib.MainContext? worker_context = null;
        private GLib.MainContext main_context;

        private Gee.ArrayDeque<string> file_queue;
        private GLib.Mutex queue_mutex;

        private Indexer? indexer = null;

        public BackgroundScan (OLLMchat.Client embedding_client,
                               Database vector_db,
                               SQ.Database sql_db,
                               OLLMfiles.ProjectManager project_manager) {
            GLib.Object ();

            this.embedding_client = embedding_client;
            this.vector_db       = vector_db;
            this.sql_db          = sql_db;
            this.project_manager = project_manager;

            this.file_queue = new Gee.ArrayDeque<string> ();
            this.queue_mutex = GLib.Mutex ();
            this.main_context = GLib.MainContext.default ();
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

            // Emit start signal on main thread.
            this.emit_project_scan_started (project.path);

            // Dispatch the heavy work to the background thread via idle source.
            // The background thread will call queueProject().
            var source = new GLib.IdleSource ();
            source.set_callback (() => {
                this.queueProject (project);
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
         */
        public void scanFile (OLLMfiles.File file) {
            this.ensure_thread ();

            // Dispatch to background thread.
            var source = new GLib.IdleSource ();
            source.set_callback (() => {
                this.queueFile (file.path);
                return false;
            });
            source.attach (this.worker_context);
        }

        /**
         * Process a project: load its files, check timestamps, and enqueue any
         * that need (re)scanning.
         */
        private void queueProject (OLLMfiles.Project project) {
            // Load project from DB – ProjectManager already has it.
            // Ensure we have the latest representation.
            var proj = this.project_manager.get_project_by_path (project.path);
            if (proj == null) {
                // If the project cannot be loaded, abort silently.
                GLib.warning ("BackgroundScan: could not load project %s", project.path);
                return;
            }

            int files_indexed = 0;

            // Iterate over all children; we only care about File objects.
            foreach (var child in proj.children.values) {
                if (child is OLLMfiles.File) {
                    var f = child as OLLMfiles.File;
                    // Compare last_scan timestamp with file modification time.
                    // If the file has never been scanned or changed, queue it.
                    if (f.last_scan < f.mtime_on_disk ()) {
                        this.queueFile (f.path);
                        files_indexed++;
                    }
                } else if (child is OLLMfiles.Folder) {
                    // For folders we only need to avoid re‑processing the same folder
                    // during the same run – the plan suggests checking folder.last_scan.
                    var folder = child as OLLMfiles.Folder;
                    if (folder.last_scan < folder.mtime_on_disk ()) {
                        // Recurse into sub‑folder.
                        this.queueProject (folder as OLLMfiles.Project); // Folder is also a Project‑like node
                    }
                }
            }

            // Emit completion signal (after all files have been queued).
            this.emit_project_scan_completed (project.path, files_indexed);
        }

        /**
         * Add a file path to the queue in a thread‑safe way and ensure the queue
         * processing loop is running.
         */
        private void queueFile (string path) {
            // Guard the queue with the mutex.
            this.queue_mutex.lock ();
            this.file_queue.offer_tail (path);
            this.queue_mutex.unlock ();

            // Ensure the queue processing source is active.
            // If not already running, start it via an idle source.
            // The idle source will keep pulling items until the queue is empty.
            var source = new GLib.IdleSource ();
            source.set_callback (() => {
                this.startQueue ();
                return false;
            });
            source.attach (this.worker_context);
        }

        /**
         * Pull items from the queue and index them.  Runs in the background
         * thread's main context.
         */
        private void startQueue () {
            while (true) {
                string? next_path = null;

                // Critical section – fetch one item.
                this.queue_mutex.lock ();
                if (!this.file_queue.is_empty) {
                    next_path = this.file_queue.poll_head ();
                }
                this.queue_mutex.unlock ();

                if (next_path == null) {
                    // Queue empty – exit loop.
                    break;
                }

                // Load the File object from the database.
                var file_obj = this.project_manager.get_file_by_path (next_path);
                if (file_obj == null) {
                    GLib.warning ("BackgroundScan: could not locate file %s in DB", next_path);
                    continue;
                }

                // Lazily create/reuse the Indexer.
                if (this.indexer == null) {
                    this.indexer = new Indexer (this.vector_db, this.sql_db, this.embedding_client);
                }

                // Perform indexing.  Indexer.index_file() is expected to be async
                // but for simplicity we call it synchronously here.
                try {
                    this.indexer.index_file (file_obj);
                } catch (GLib.Error e) {
                    GLib.warning ("BackgroundScan: indexing error for %s – %s", next_path, e.message);
                }

                // Emit per‑file signal.
                this.emit_file_scanned (next_path);
            }
        }

        /*--------------------------------------------------------------------
         *  Signal emission helpers – dispatch signals to main thread.
         *-------------------------------------------------------------------*/

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
         * Emits project_scan_completed signal on the main thread.
         */
        private void emit_project_scan_completed (string project_path, int files_indexed)
        {
            this.main_context.invoke (() => {
                this.project_scan_completed (project_path, files_indexed);
                return false;
            });
        }

        /*--------------------------------------------------------------------
         *  Cleanup – not strictly required because the thread lives for the
         *  lifetime of the application, but we provide a method for graceful
         *  shutdown if the host wishes to stop it.
         *-------------------------------------------------------------------*/
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
