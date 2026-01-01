// libocvector/BackgroundScan.vala
//
// BackgroundScan – a helper that runs a dedicated thread with its own MainLoop
// and processes a queue of file paths to be indexed.  It integrates with the
// OLLMvector indexing pipeline (Indexer) and emits signals so the UI can
// react to scan progress.
//
// The implementation follows the description in the project plan (Phase 7).

namespace OLLMvector {

    using Gee;
    using OLLMfiles;
    using OLLMchat;
    using SQ;

    /**
     * BackgroundScan manages a background thread that continuously processes
     * file‑indexing jobs.  The thread is started on first use and lives for the
     * lifetime of the application.
     *
     * Public API:
     *   - scanProject(Project project) : enqueue all files of a project that need scanning.
     *   - scanFile(File file)          : enqueue a single file (e.g. after a save).
     *
     * Signals:
     *   - file_scanned(string file_path)
     *   - project_scan_started(string project_path)
     *   - project_scan_completed(string project_path, int files_indexed)
     */
    public class BackgroundScan : GLib.Object {

        /*--------------------------------------------------------------------
         *  Signals
         *-------------------------------------------------------------------*/
        public signal void file_scanned (string file_path);
        public signal void project_scan_started (string project_path);
        public signal void project_scan_completed (string project_path, int files_indexed);

        /*--------------------------------------------------------------------
         *  Dependencies – injected by the UI or the main application.
         *-------------------------------------------------------------------*/
        private Client embedding_client;          // OLLMchat.Client for LLM calls
        private Database vector_db;               // OLLMvector.Database (FAISS)
        private SQ.Database sql_db;               // SQ.Database for metadata
        private ProjectManager project_manager;   // OLLMfiles.ProjectManager

        /*--------------------------------------------------------------------
         *  Thread management
         *-------------------------------------------------------------------*/
        private GLib.Thread<void*>? worker_thread = null;
        private GLib.MainLoop? worker_loop = null;
        private GLib.MainContext? worker_context = null;
        private GLib.MainContext main_context;

        /*--------------------------------------------------------------------
         *  Queue – a thread‑safe list of file paths awaiting processing.
         *-------------------------------------------------------------------*/
        private ArrayDeque<string> file_queue;
        private GLib.Mutex queue_mutex;

        /*--------------------------------------------------------------------
         *  Indexer reuse – an Indexer instance can be reused for multiple files.
         *-------------------------------------------------------------------*/
        private Indexer? indexer = null;

        /*--------------------------------------------------------------------
         *  Constructor
         *-------------------------------------------------------------------*/
        public BackgroundScan (Client embedding_client,
                               Database vector_db,
                               SQ.Database sql_db,
                               ProjectManager project_manager) {
            GLib.Object ();

            this.embedding_client = embedding_client;
            this.vector_db       = vector_db;
            this.sql_db          = sql_db;
            this.project_manager = project_manager;

            this.file_queue = new ArrayDeque<string> ();
            this.queue_mutex = new GLib.Mutex ();
            this.main_context = GLib.MainContext.default ();
        }

        /*--------------------------------------------------------------------
         *  Public API – called from the UI (main thread)
         *-------------------------------------------------------------------*/

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
         * Queue an entire project for scanning.  This method is safe to call
         * from the UI thread.
         *
         * @param project The Project object representing the active project.
         */
        public void scanProject (Project project) {
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
         * Queue a single file for scanning (e.g. after a save).
         *
         * @param file The File object that was modified.
         */
        public void scanFile (File file) {
            this.ensure_thread ();

            // Dispatch to background thread.
            var source = new GLib.IdleSource ();
            source.set_callback (() => {
                this.queueFile (file.path);
                return false;
            });
            source.attach (this.worker_context);
        }

        /*--------------------------------------------------------------------
         *  Internal helpers – executed inside the background thread.
         *-------------------------------------------------------------------*/

        /**
         * Process a project: load its files, check timestamps, and enqueue any
         * that need (re)scanning.
         */
        private void queueProject (Project project) {
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
                if (child is File) {
                    var f = child as File;
                    // Compare last_scan timestamp with file modification time.
                    // If the file has never been scanned or changed, queue it.
                    if (f.last_scan < f.mtime_on_disk ()) {
                        this.queueFile (f.path);
                        files_indexed++;
                    }
                } else if (child is Folder) {
                    // For folders we only need to avoid re‑processing the same folder
                    // during the same run – the plan suggests checking folder.last_scan.
                    var folder = child as Folder;
                    if (folder.last_scan < folder.mtime_on_disk ()) {
                        // Recurse into sub‑folder.
                        this.queueProject (folder as Project); // Folder is also a Project‑like node
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
                queue_mutex.lock ();
                if (!file_queue.is_empty) {
                    next_path = file_queue.poll_head ();
                }
                queue_mutex.unlock ();

                if (next_path == null) {
                    // Queue empty – exit loop.
                    break;
                }

                // Load the File object from the database.
                var file_obj = project_manager.get_file_by_path (next_path);
                if (file_obj == null) {
                    warning ("BackgroundScan: could not locate file %s in DB", next_path);
                    continue;
                }

                // Lazily create/reuse the Indexer.
                if (indexer == null) {
                    indexer = new Indexer (vector_db, sql_db, embedding_client);
                }

                // Perform indexing.  Indexer.index_file() is expected to be async
                // but for simplicity we call it synchronously here.
                try {
                    indexer.index_file (file_obj);
                } catch (Error e) {
                    warning ("BackgroundScan: indexing error for %s – %s", next_path, e.message);
                }

                // Emit per‑file signal.
                file_scanned (next_path);
            }
        }

        /*--------------------------------------------------------------------
         *  Cleanup – not strictly required because the thread lives for the
         *  lifetime of the application, but we provide a method for graceful
         *  shutdown if the host wishes to stop it.
         *-------------------------------------------------------------------*/
        public void stop () {
            if (worker_loop != null) {
                worker_loop.quit ();
                worker_loop = null;
            }
            if (worker_thread != null) {
                worker_thread.join ();
                worker_thread = null;
            }
        }
    }
}
