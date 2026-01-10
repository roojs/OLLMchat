// libocvector/BackgroundScan.vala
//
// BackgroundScan – a helper that runs a dedicated thread with its own MainLoop
// and processes a queue of file paths to be indexed.  It integrates with the
// OLLMvector indexing pipeline (Indexer) and emits signals so the UI can
// react to scan progress.
//
// The implementation follows the description in the project plan (Phase 7).

namespace OLLMvector {

    /**
     * BackgroundScan manages a background thread that continuously processes
     * file‑indexing jobs.  The thread is started on first use and lives for the
     * lifetime of the application.
     */
    public class BackgroundScan : GLib.Object {

        // ============================================================================
        // MAIN THREAD SECTION
        // ============================================================================
        // All code and properties in this section are accessed from the main thread.
        // Methods here are called from the UI thread and dispatch work to the
        // background thread via IdleSource callbacks attached to worker_context.
        // ============================================================================

        /**
         * Emitted at the start of each file scan and when queue becomes empty.
         *
         * @param queue_size Current size of the file queue (number of files remaining).
         * @param current_file Path of the file currently being scanned (empty string "" when queue is empty).
         */
        public signal void scan_update (int queue_size, string current_file);

        // Shared resources (accessed from both threads)
        // Note: sql_db is thread-safe (SQLite configured for SERIALIZED mode)
        // Note: vector_db (FAISS) is thread-safe via mutex in Index class
        private OLLMchat.Client embedding_client;          // OLLMchat.Client for LLM calls
        private Database vector_db;               // OLLMvector.Database (FAISS) - thread-safe via mutex in Index class
        private SQ.Database sql_db;               // SQ.Database for metadata - thread-safe (SERIALIZED mode)
        private OLLMfiles.GitProviderBase git_provider;     // Git provider instance (each thread needs its own instance for thread safety)
        private OLLMchat.Settings.Config2 config;             // Cloned Config2 instance for Indexer creation (thread-safe copy)
        private OLLMchat.Settings.Config2 original_config;     // Original config (for monitoring changes on main thread)

        // Thread management (main thread creates/manages, background thread uses)
        private GLib.Thread<void*>? worker_thread = null;
        private GLib.MainLoop? worker_loop = null;
        private GLib.MainContext? worker_context = null;
        private GLib.MainContext main_context;

        /**
         * Creates a new BackgroundScan instance.
         *
         * @param tool The CodebaseSearchTool instance (provides embedding_client, vector_db, and project_manager.db).
         * @param git_provider The Git provider instance (each thread needs its own instance for thread safety).
         * @param config Config2 instance for Indexer creation. A deep copy is made for thread safety.
         *                Changes to config (when preferences dialog closes) will trigger thread restart.
         */
        public BackgroundScan (Tool.CodebaseSearchTool tool,
                               OLLMfiles.GitProviderBase git_provider,
                               OLLMchat.Settings.Config2 config) 
		{
            // Extract dependencies from tool instance
            var embedding_client = tool.embedding_client;
            var vector_db = tool.vector_db;
            var project_manager = tool.project_manager;
            
            if (embedding_client == null) {
                GLib.error("BackgroundScan: CodebaseSearchTool.embedding_client is null");
            }
            if (vector_db == null) {
                GLib.error("BackgroundScan: CodebaseSearchTool.vector_db is null");
            }
            if (project_manager == null) {
                GLib.error("BackgroundScan: CodebaseSearchTool.project_manager is null");
            }
            if (project_manager.db == null) {
                GLib.error("BackgroundScan: CodebaseSearchTool.project_manager.db is null");
            }
            
            // GLib.error() never returns, so these are guaranteed non-null after the checks above
            this.embedding_client = embedding_client;
            this.vector_db = vector_db;
            this.sql_db = project_manager.db;
            this.git_provider = git_provider;
            
            // Store original config and clone it for thread-safe use in background thread
            this.original_config = config;
            this.config = config.clone();
            
            // Connect to config changed signal (emitted when preferences dialog closes)
            this.original_config.changed.connect(this.on_config_changed);
            
            this.main_context = GLib.MainContext.default ();

        }
        
        /**
         * Handler for config changed signal (emitted when preferences dialog closes).
         * Updates cloned config and restarts background thread if it's running.
         */
        private void on_config_changed()
        {
            // Only restart if thread is currently running
            if (this.worker_thread != null) {
                GLib.debug("BackgroundScan: Config changed, restarting background thread");
                this.restart_thread.begin();
                return;
            }
            
            // Thread not running - safe to update config immediately
            this.config = this.original_config.clone();
            GLib.debug("BackgroundScan: Config changed, config updated (thread not running)");
        }
        
        /**
         * Restarts the background thread by stopping it and starting it again.
         * This is called when config changes are detected and thread is running.
         * Config is cloned after thread stops to ensure thread safety.
         */
        private async void restart_thread()
        {
            // Stop the current thread
            if (this.worker_loop != null) {
                this.worker_loop.quit();
            }
            
            // Wait for thread to finish
            if (this.worker_thread != null) {
                this.worker_thread.join();
                this.worker_thread = null;
            }
            
            // Clear worker context
            this.worker_context = null;
            
            // Now that thread has stopped, safe to clone config
            this.config = this.original_config.clone();
            
            // Clear background thread state so it will be recreated with new config
            this.indexer = null;
            
            // Restart the thread immediately
            this.ensure_thread();
            
            GLib.debug("BackgroundScan: Thread restarted with new config");
        }

        /**
         * Ensure the background thread is running.
         */
        private void ensure_thread () 
		{
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

                    GLib.debug ("BackgroundScan: background thread started");
                    
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
         * @param project The Folder object representing the active project (is_project = true), or null if no active project.
         */
        public void scanProject (OLLMfiles.Folder? project) {
            // If no active project, skip scanning
            if (project == null) {
                return;
            }
            
            // Start thread if not already running.
            this.ensure_thread ();

            // Extract path before creating callback to avoid capturing object in closure.
            // This is required for thread safety - we pass only the path string (thread-safe)
            // rather than the object itself, which may not be thread-safe.
            var project_path = project.path;

            // Dispatch the heavy work to the background thread via idle source.
            // The background thread will load the project from the database.
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
         * @param project The Folder object that contains this file (is_project = true), or null if no active project.
         */
        public void scanFile (OLLMfiles.File file, OLLMfiles.Folder? project) 
		{
            // If no active project, skip scanning (file may be outside any project)
            if (project == null) {
                return;
            }
            
            this.ensure_thread ();

            // Extract paths before creating callback to avoid capturing object in closure.
            // This is required for thread safety - we pass only the path strings (thread-safe)
            // rather than the objects themselves, which may not be thread-safe.
            var file_path = file.path;
            var project_path = project.path;

            // Dispatch to background thread.
            var source = new GLib.IdleSource ();
            source.set_callback (() => {
                this.queueFile (new BackgroundScanItem (project_path, file_path));
                return false;
            });
            source.attach (this.worker_context);
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

        // ============================================================================
        // BACKGROUND THREAD SECTION
        // ============================================================================
        // All code and properties in this section are accessed ONLY from the
        // background thread. These methods are called via IdleSource callbacks
        // attached to worker_context, ensuring they run in the background thread.
        // ============================================================================

        /**
         * Class to track both project_path and file_path when queuing files.
         */
        private class BackgroundScanItem {
            public string project_path;
            public string file_path;
            
            public BackgroundScanItem (string project_path, string file_path) {
                this.project_path = project_path;
                this.file_path = file_path;
            }
        }

        // Background thread state (accessed only from background thread)
        private OLLMfiles.ProjectManager? worker_project_manager = null;   // ProjectManager instance for background thread
        private OLLMfiles.Folder? active_project = null;   // Track currently active project in background thread (for memory management)
        private Gee.ArrayQueue<BackgroundScanItem>? file_queue = null;
        private bool queue_processing = false;
        private Indexing.Indexer? indexer = null;

        /**
         * Ensure ProjectManager exists in background thread context.
         */
        private void ensure_project_manager () 
		{
            if (this.worker_project_manager == null) {
                // Create ProjectManager in background thread context
                // Use same sql_db (thread-safe in serialized mode)
                this.worker_project_manager = new OLLMfiles.ProjectManager(this.sql_db);
                // Use the git_provider instance passed to constructor (each thread needs its own instance for thread safety)
                this.worker_project_manager.git_provider = this.git_provider;
            }
        }

        /**
         * Set active project and clear files from previous active project to free memory.
         * 
         * Note: This does NOT update database (is_active flag) - that's main thread's responsibility.
         * The background worker only manages memory, not database state.
         */
        private void set_active_project (OLLMfiles.Folder? project) 
		{
            // If switching to a different project, clear files from previous project
            if (this.active_project != null && this.active_project != project) {
                // Clear all in-memory data (children, project_files)
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
        private async void set_active_project_and_load (OLLMfiles.Folder project) 
		{
            this.set_active_project (project);
            yield project.load_files_from_db ();
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
            
            // Ensure project_files is populated (load_files_from_db may skip update_from if needs_reload() is false)
            project.project_files.update_from(project);

            int queued_count = 0;
            // Iterate through project_files (flat list, not hierarchical)
            // ProjectFiles implements Gee.Iterable<ProjectFile>, so we can iterate directly
            foreach (var project_file in project.project_files) {
                // Skip if file doesn't need scanning (negative test)
                if (project_file.file.last_vector_scan >= project_file.file.mtime_on_disk ()) {
                    continue;
                }
                // Create BackgroundScanItem and queue it
                this.queueFile (new BackgroundScanItem (project.path, project_file.file.path));
                queued_count++;
            }
            
            GLib.debug ("BackgroundScan: queued %d files from project '%s'", queued_count, path);

            // Do NOT emit project_scan_completed - project scan just queues files,
            // completion is handled by file queue via scan_update signal
        }

        /**
         * Add a file item to the queue and ensure the queue processing loop is running.
         */
        private void queueFile (BackgroundScanItem item) {
            // Initialize queue if needed (lazy initialization in background thread)
            if (this.file_queue == null) {
                this.file_queue = new Gee.ArrayQueue<BackgroundScanItem> ();
            }
            // All queue operations happen in the background thread context, so no mutex needed
            this.file_queue.offer (item);
            
            GLib.debug ("BackgroundScan: queued file '%s' (queue size: %u)", item.file_path, this.file_queue.size);

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

            // Initialize queue if needed (lazy initialization in background thread)
            if (this.file_queue == null) {
                this.file_queue = new Gee.ArrayQueue<BackgroundScanItem> ();
            }

            while (true) {
                // All queue operations happen in the background thread context, so no mutex needed
                var next_item = this.file_queue.poll ();

                if (next_item == null) {
                    // Queue empty – emit completion signal and exit loop.
                    this.queue_processing = false;
                    GLib.debug ("BackgroundScan: queue empty, processing complete");
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
                yield this.set_active_project_and_load (project);
                
                // Ensure project_files is populated (load_files_from_db may skip update_from if needs_reload() is false)
                project.project_files.update_from(project);

                // Find file in that project's project_files.child_map
                var project_file = project.project_files.child_map.get (next_item.file_path);
                if (project_file == null) {
                    // File doesn't exist in project - may have been deleted or moved
                    continue;
                }

                // Emit scan_update signal at start of scan (before indexing)
                this.emit_scan_update ((int)this.file_queue.size, next_item.file_path);
                
                GLib.debug ("BackgroundScan: processing file '%s' (queue size: %u)", next_item.file_path, this.file_queue.size);

                // Lazily create/reuse the Indexer.
                if (this.indexer == null) {
                    this.indexer = new Indexing.Indexer (this.config, this.vector_db, this.sql_db, this.worker_project_manager);
                }

                // Perform indexing.  Indexer.index_file() is async.
                try {
                    yield this.indexer.index_file (project_file.file);
                } catch (GLib.Error e) {
                    GLib.warning ("BackgroundScan: indexing error for %s – %s", next_item.file_path, e.message);
                }

            }
        }
    }
}
