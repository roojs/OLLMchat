/*
 * Copyright (C) 2025 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMchat.Settings
{
	/**
	 * Manages background pull operations for models.
	 * 
	 * Handles status tracking, persistence, rate-limited UI updates,
	 * and retry scheduling. Delegates actual pull execution to
	 * ModelPullManagerThread.
	 * 
	 * @since 1.3.4
	 */
	public class ModelPullManager : Object
	{
		/**
		 * Signal emitted when pull progress updates.
		 * 
		 * @param model_name The model being pulled
		 * @param status Current status (e.g., "pulling", "complete", "error")
		 * @param progress Progress percentage (0-100)
		 */
		public signal void progress_updated(string model_name, string status, int progress);
		
		/**
		 * Signal emitted when a model pull completes successfully.
		 * 
		 * @param model_name The model that was pulled
		 */
		public signal void model_complete(string model_name);
		
		/**
		 * Signal emitted when a model pull fails after all retries are exhausted.
		 * 
		 * @param model_name The model that failed to pull
		 */
		public signal void model_failed(string model_name);
		
		/**
		 * Application interface (provides config and data_dir)
		 */
		public OLLMchat.ApplicationInterface app { get; construct; }
		
		/**
		 * Path to loading.json file
		 */
		private string loading_json_path;
		
		/**
		 * Background thread manager
		 */
		private ModelPullManagerThread pull_thread;
		
		/**
		 * Map of model_name -> loading status (runtime tracking and persistence)
		 */
		private Gee.HashMap<string, LoadingStatus> loading_status_cache;
		
		/**
		 * Timestamp of last file write
		 */
		private int64 last_file_write_time = 0;
		
		/**
		 * Rate limit: minimum seconds between UI updates (except for status changes and final updates)
		 */
		private const int64 UPDATE_RATE_LIMIT_SECONDS = 2;
		
		/**
		 * Rate limit: minimum seconds between file writes (except for start/finish)
		 */
		private const int64 FILE_WRITE_RATE_LIMIT_SECONDS = 300; // 5 minutes
		
		/**
		 * Delay between retries in seconds
		 */
		private const int64 RETRY_DELAY_SECONDS = 60; // 1 minute
		
		/**
		 * Creates a new ModelPullManager.
		 * 
		 * @param app ApplicationInterface instance (provides config and data_dir)
		 */
		public ModelPullManager(OLLMchat.ApplicationInterface app)
		{
			Object(app: app);
			
			this.loading_json_path = GLib.Path.build_filename(app.data_dir, "loading.json");
			this.loading_status_cache = new Gee.HashMap<string, LoadingStatus>();
			
			// Create background thread manager
			this.pull_thread = new ModelPullManagerThread(app);
			this.pull_thread.on_status_update = this.handle_status_update;
			this.pull_thread.on_progress_update = this.handle_progress_update;
			
			// Ensure data directory exists
			try {
				app.ensure_data_dir();
			} catch (GLib.Error e) {
				GLib.warning("Failed to ensure data directory exists: " + e.message);
			}
			
			// Load existing status from file
			this.load_from_file();
		}
		
		/**
		 * Starts a background pull operation for a model.
		 * 
		 * If a pull is already in progress for this model, does nothing.
		 * 
		 * @param model_name Full model name (e.g., "llama2" or "llama2:7b")
		 * @param connection Connection to use for the pull
		 * @return true if pull was started, false if already in progress
		 */
		public bool start_pull(string model_name, OLLMchat.Settings.Connection connection)
		{
			// Check if already pulling
			if (this.loading_status_cache.has_key(model_name) && 
			    this.loading_status_cache.get(model_name).active) {
				GLib.debug("Pull already in progress for model: " + model_name);
				return false;
			}
			
			// Ensure background thread is running
			this.pull_thread.ensure_thread();
			
			// Get or create status
			LoadingStatus status_obj;
			if (this.loading_status_cache.has_key(model_name)) {
				status_obj = this.loading_status_cache.get(model_name);
			} else {
				status_obj = new LoadingStatus();
				this.loading_status_cache.set(model_name, status_obj);
			}
			
			status_obj.active = true;
			status_obj.connection_url = connection.url;
			status_obj.connection = connection;
			
			// Start pull operation in background thread
			this.pull_thread.start_pull(model_name, connection, status_obj);
			
			return true;
		}
		
		/**
		 * Handles status updates from the background thread.
		 * 
		 * @param model_name Model name
		 * @param status Status string
		 * @param progress Progress percentage
		 * @param last_chunk_status Last chunk status from API
		 */
		private void handle_status_update(string model_name, string status, int progress, string last_chunk_status)
		{
			// Update status in memory and optionally write to file
			bool force_write = (status == "pulling" && progress == 0) || 
			                   status == "complete" || 
			                   status == "failed" || 
			                   status == "pending-retry";
			this.update_loading_status(model_name, status, progress, last_chunk_status, force_write);
			
			// Handle retry scheduling for pending-retry status
			if (status == "pending-retry") {
				this.schedule_retry(model_name, progress, last_chunk_status);
				return;
			}
			
			// Handle completion/failure
			if (status == "complete" || status == "failed") {
				Idle.add(() => {
					if (status == "complete") {
						this.model_complete(model_name);
						this.loading_status_cache.unset(model_name);
						this.write_to_file();
						return false;
					}
					
					if (status == "failed") {
						this.model_failed(model_name);
						this.loading_status_cache.unset(model_name);
						this.write_to_file();
					}
					
					return false;
				});
			}
		}
		
		/**
		 * Handles progress updates from the background thread.
		 * 
		 * @param model_name Model name
		 * @param status Status string
		 * @param progress Progress percentage
		 */
		private void handle_progress_update(string model_name, string status, int progress)
		{
			// Schedule progress update with rate limiting
			this.schedule_progress_update(model_name, status, progress);
		}
		
		/**
		 * Schedules a retry for a failed pull operation.
		 * 
		 * Schedules the retry on the main thread after RETRY_DELAY_SECONDS.
		 * 
		 * @param model_name Model name to retry
		 * @param progress Current progress percentage
		 * @param last_chunk_status Last chunk status from API
		 */
		private void schedule_retry(string model_name, int progress, string last_chunk_status)
		{
			// Schedule retry from main thread (not background thread)
			// Use Idle.add to schedule on main thread, then use Timeout.add_seconds
			Idle.add(() => {
				GLib.Timeout.add_seconds((uint)RETRY_DELAY_SECONDS, () => {
					// Check if still in pending-retry status (not completed or failed)
					if (!this.loading_status_cache.has_key(model_name)) {
						return false;
					}
					
					var check_status = this.loading_status_cache.get(model_name);
					if (check_status.status != "pending-retry") {
						return false;
					}
					
					// Use stored connection object
					if (check_status.connection == null) {
						// Connection not found - mark as failed
						check_status.status = "failed";
						check_status.error = "Connection not found for retry";
						this.update_loading_status(model_name, "failed", progress, last_chunk_status, true);
						this.progress_updated(model_name, "failed", progress);
						this.model_failed(model_name);
						this.loading_status_cache.unset(model_name);
						this.write_to_file();
						return false;
					}
					
					// Retry the pull
					check_status.active = true;
					this.pull_thread.start_pull(model_name, check_status.connection, check_status);
					return false; // Don't repeat
				});
				return false;
			});
		}
		
		/**
		 * Schedules a progress update with rate limiting.
		 * 
		 * Only emits update if:
		 * - 2+ seconds have passed since last update, OR
		 * - Status has changed, OR
		 * - This is a final update (complete/error)
		 * 
		 * @param model_name Model name
		 * @param status Current status
		 * @param progress Progress percentage
		 */
		private void schedule_progress_update(string model_name, string status, int progress)
		{
			// Get or create status
			LoadingStatus status_obj;
			if (this.loading_status_cache.has_key(model_name)) {
				status_obj = this.loading_status_cache.get(model_name);
			} else {
				status_obj = new LoadingStatus();
				this.loading_status_cache.set(model_name, status_obj);
			}
			
			var now = GLib.get_real_time() / 1000000;
			
			// Always emit final status updates
			if (status == "complete" || status == "error" || status == "failed") {
				Idle.add(() => {
					this.progress_updated(model_name, status, progress);
					return false;
				});
				status_obj.last_update_time = now;
				status_obj.status = status;
				return;
			}
			
			// Emit if status changed
			if (status != status_obj.status) {
				Idle.add(() => {
					this.progress_updated(model_name, status, progress);
					return false;
				});
				status_obj.last_update_time = now;
				status_obj.status = status;
				return;
			}
			
			// Emit if enough time has passed
			if ((now - status_obj.last_update_time) >= UPDATE_RATE_LIMIT_SECONDS) {
				Idle.add(() => {
					this.progress_updated(model_name, status, progress);
					return false;
				});
				status_obj.last_update_time = now;
				status_obj.status = status;
			}
		}
		
		/**
		 * Updates loading status in memory and optionally writes to file.
		 * 
		 * @param model_name Model name
		 * @param status Status string
		 * @param progress Progress percentage (0-100)
		 * @param last_chunk_status Last chunk status from API
		 * @param force_write If true, write immediately; if false, rate-limit to 5 minutes
		 */
		private void update_loading_status(string model_name, string status, int progress, string last_chunk_status, bool force_write)
		{
			// Get or create status object
			LoadingStatus status_obj;
			if (this.loading_status_cache.has_key(model_name)) {
				status_obj = this.loading_status_cache.get(model_name);
			} else {
				status_obj = new LoadingStatus();
				this.loading_status_cache.set(model_name, status_obj);
			}
			
			// Update fields
			status_obj.status = status;
			status_obj.progress = progress;
			if (last_chunk_status != "") {
				status_obj.last_chunk_status = last_chunk_status;
			}
			
			// Set started timestamp if not already set
			if (status_obj.started == "") {
				status_obj.started = (GLib.get_real_time() / 1000000).to_string();
			}
			
			// Add error message if status is error
			if (status == "error" && status_obj.error == "") {
				status_obj.error = "Pull operation failed";
			}
			
			// Write to file if forced or rate limit expired
			if (force_write) {
				this.write_to_file();
				return;
			}
			
			var now = GLib.get_real_time() / 1000000;
			if ((now - this.last_file_write_time) >= FILE_WRITE_RATE_LIMIT_SECONDS) {
				this.write_to_file();
			}
		}
		
		/**
		 * Loads loading status from file into memory cache.
		 */
		private void load_from_file()
		{
			if (!GLib.File.new_for_path(this.loading_json_path).query_exists()) {
				return;
			}
			
			try {
				var parser = new Json.Parser();
				parser.load_from_file(this.loading_json_path);
				var root = parser.get_root();
				if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
					return;
				}
				
				var root_obj = root.get_object();
				root_obj.foreach_member((obj, key, node) => {
					if (node.get_node_type() != Json.NodeType.OBJECT) {
						return;
					}
					
					var status_obj = Json.gobject_deserialize(
						typeof(LoadingStatus),
						node
					) as LoadingStatus;
					if (status_obj == null) {
						return;
					}
					
					this.loading_status_cache.set(key, status_obj);
				});
			} catch (Error e) {
				GLib.debug("Failed to load loading.json: " + e.message);
			}
		}
		
		/**
		 * Writes all loading status from memory cache to file.
		 */
		private void write_to_file()
		{
			try {
				var root_obj = new Json.Object();
				
				// Serialize all status objects
				foreach (var entry in this.loading_status_cache.entries) {
					var status_node = Json.gobject_serialize(entry.value);
					root_obj.set_member(entry.key, status_node);
				}
				
				// Create root node
				var root = new Json.Node(Json.NodeType.OBJECT);
				root.set_object(root_obj);
				
				// Write to file
				var generator = new Json.Generator();
				generator.set_root(root);
				generator.set_pretty(true);
				var json_str = generator.to_data(null);
				
				GLib.FileUtils.set_contents(this.loading_json_path, json_str);
				this.last_file_write_time = GLib.get_real_time() / 1000000;
			} catch (Error e) {
				GLib.warning("Failed to write loading.json: " + e.message);
			}
		}
		
		/**
		 * Checks if a pull is currently in progress for a model.
		 * 
		 * @param model_name Model name to check
		 * @return true if pull is in progress, false otherwise
		 */
		public bool is_pulling(string model_name)
		{
			if (!this.loading_status_cache.has_key(model_name)) {
				return false;
			}
			
			return this.loading_status_cache.get(model_name).active;
		}
		
		/**
		 * Gets all models that are currently being pulled.
		 * 
		 * @return Set of model names that are being pulled
		 */
		public Gee.Set<string> get_active_pulls()
		{
			var result = new Gee.HashSet<string>();
			foreach (var entry in this.loading_status_cache.entries) {
				if (entry.value.active) {
					result.add(entry.key);
				}
			}
			return result;
		}
		
	}
}
