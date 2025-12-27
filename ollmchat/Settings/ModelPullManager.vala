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
		 * @param status LoadingStatus object with all status information (including model_name)
		 */
		public signal void progress_updated(LoadingStatus status);
		
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
			this.pull_thread.status_updated.connect(this.handle_status_update);
			
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
			var existing_status = this.get_or_create_status(model_name);
			if (existing_status.active) {
				GLib.debug("Pull already in progress for model: " + model_name);
				return false;
			}
			
			// Ensure background thread is running
			this.pull_thread.ensure_thread();
			
			// Configure status for new pull
			existing_status.model_name = model_name;
			existing_status.active = true;
			existing_status.connection_url = connection.url;
			existing_status.connection = connection;
			
			// ⚠️ THREAD SAFETY WARNING: Passing Connection object to background thread.
			// This may be a cause of failure if Connection is modified concurrently.
			// Consider cloning: var connection_copy = connection.clone();
			// Start pull operation in background thread (pass only primitive data)
			this.pull_thread.start_pull(model_name, connection, existing_status.retry_count);
			
			return true;
		}
		
		/**
		 * Gets or creates a LoadingStatus object for a model.
		 * 
		 * @param model_name Model name
		 * @return LoadingStatus object (always non-null)
		 */
		private LoadingStatus get_or_create_status(string model_name)
		{
			if (this.loading_status_cache.has_key(model_name)) {
				var status_obj = this.loading_status_cache.get(model_name);
				// Ensure model_name is set (for backwards compatibility with loaded data)
				if (status_obj.model_name == "") {
					status_obj.model_name = model_name;
				}
				return status_obj;
			}
			
			var status_obj = new LoadingStatus();
			status_obj.model_name = model_name;
			this.loading_status_cache.set(model_name, status_obj);
			return status_obj;
		}
		
		/**
		 * Handles status updates from the background thread.
		 * 
		 * This single handler manages both state updates and rate-limited UI updates.
		 * 
		 * @param model_name Model name
		 * @param status Status string
		 * @param completed Bytes completed
		 * @param total Total bytes
		 * @param last_chunk_status Last chunk status from API
		 * @param retry_count Current retry count (from background thread)
		 */
		private void handle_status_update(
			string model_name,
			string status,
			int64 completed,
			int64 total,
			string last_chunk_status,
			int retry_count
		)
		{
			// Update status object in main thread (thread-safe)
			var status_obj = this.get_or_create_status(model_name);
			var old_status = status_obj.status;
			status_obj.model_name = model_name;
			status_obj.status = status;
			status_obj.retry_count = retry_count;
			status_obj.completed = completed;
			status_obj.total = total;
			if (last_chunk_status != "") {
				status_obj.last_chunk_status = last_chunk_status;
			}
			
			// Update active flag based on status
			if (status == "complete" || status == "failed" || status == "pending-retry") {
				status_obj.active = false;
			}
			
			// Set started timestamp if not already set
			if (status_obj.started == "") {
				status_obj.started = (GLib.get_real_time() / 1000000).to_string();
			}
			
			// Add error message if status is error
			if (status == "error" && status_obj.error == "") {
				status_obj.error = "Pull operation failed";
			}
			
			// Write to file if needed
			bool force_write = (status == "pulling" && total == 0) || 
			                   status == "complete" || 
			                   status == "failed" || 
			                   status == "pending-retry";
			this.write_to_file_rate_limited(force_write);
			
			// Schedule progress update with rate limiting (for UI)
			this.schedule_progress_update(status_obj, old_status);
			
			// Handle retry scheduling for pending-retry status
			if (status == "pending-retry") {
				this.schedule_retry(model_name);
				return;
			}
			
			// Handle completion/failure
			if (status == "complete" || status == "failed") {
				this.finish_pull(model_name, status);
			}
		}
		
		/**
		 * Finalizes a pull operation (complete or failed).
		 * 
		 * @param model_name Model name
		 * @param status Final status ("complete" or "failed")
		 */
		private void finish_pull(string model_name, string status)
		{
			Idle.add(() => {
				if (status == "complete") {
					this.model_complete(model_name);
				} else {
					this.model_failed(model_name);
				}
				
				this.loading_status_cache.unset(model_name);
				this.write_to_file();
				return false;
			});
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
		private void schedule_retry(string model_name)
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
						this.write_to_file();
						this.progress_updated(check_status);
						this.finish_pull(model_name, "failed");
						return false;
					}
					
					// ⚠️ THREAD SAFETY WARNING: Passing Connection object to background thread.
					// This may be a cause of failure if Connection is modified concurrently.
					// Consider cloning: var connection_copy = check_status.connection.clone();
					// Retry the pull (pass only primitive data)
					check_status.active = true;
					this.pull_thread.start_pull(model_name, check_status.connection, check_status.retry_count);
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
		 * @param status_obj LoadingStatus object with current status (includes model_name)
		 * @param old_status Previous status (to detect changes)
		 */
		private void schedule_progress_update(LoadingStatus status_obj, string old_status)
		{
			var now = GLib.get_real_time() / 1000000;
			
			// Check if we should NOT emit (negative test)
			bool is_final = status_obj.status == "complete" || status_obj.status == "error" || status_obj.status == "failed";
			bool status_changed = status_obj.status != old_status;
			bool time_passed = (now - status_obj.last_update_time) >= UPDATE_RATE_LIMIT_SECONDS;
			
			// Don't emit if not final, status unchanged, and not enough time passed
			if (!is_final && !status_changed && !time_passed) {
				return;
			}
			
			// Emit update
			Idle.add(() => {
				this.progress_updated(status_obj);
				return false;
			});
			status_obj.last_update_time = now;
		}
		
		/**
		 * Writes to file with rate limiting.
		 * 
		 * @param force_write If true, write immediately; if false, rate-limit to 5 minutes
		 */
		private void write_to_file_rate_limited(bool force_write)
		{
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
				
				var root_array = parser.get_root().get_array();
				for (uint i = 0; i < root_array.get_length(); i++) {
					var node = root_array.get_element(i);
					
					var status_obj = Json.gobject_deserialize(
						typeof(LoadingStatus),
						node
					) as LoadingStatus;
					
					this.loading_status_cache.set(status_obj.model_name, status_obj);
				}
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
				string[] json_parts ={};
				
				// Serialize each status object to JSON string
				foreach (var entry in this.loading_status_cache.entries) {
					json_parts += Json.gobject_to_data(entry.value, null);
				}
				
				// Join with commas and wrap in array brackets
				
				GLib.FileUtils.set_contents(this.loading_json_path, 
					"[" + string.joinv(",", json_parts) + "]";);
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
