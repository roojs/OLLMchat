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
	 * Loading status information for a model pull operation.
	 * 
	 * Combines both runtime tracking and persistence data.
	 * 
	 * @since 1.3.4
	 */
	private class LoadingStatus : GLib.Object, Json.Serializable
	{
		// Persistence fields (saved to JSON)
		public string status { get; set; default = ""; }
		public int progress { get; set; default = 0; }
		public string started { get; set; default = ""; }
		public string error { get; set; default = ""; }
		public string last_chunk_status { get; set; default = ""; }
		public int retry_count { get; set; default = 0; }
		
		// Runtime fields (not serialized)
		public bool active = false;
		public int64 last_update_time = 0;
		
		public unowned ParamSpec? find_property(string name)
		{
			return this.get_class().find_property(name);
		}
		
		public new void Json.Serializable.set_property(ParamSpec pspec, Value value)
		{
			base.set_property(pspec.get_name(), value);
		}
		
		public new Value Json.Serializable.get_property(ParamSpec pspec)
		{
			Value val = Value(pspec.value_type);
			base.get_property(pspec.get_name(), ref val);
			return val;
		}
		
		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			
			return default_serialize_property(property_name, value, pspec);
		}
	}
	
	/**
	 * Manages background pull operations for models.
	 * 
	 * Handles concurrent model pulls with progress tracking, rate-limited
	 * UI updates, and persistence to loading.json file.
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
		 * Single background thread that handles all pull operations
		 */
		private Thread<bool>? background_thread = null;
		
		/**
		 * MainLoop for the background thread
		 */
		private MainLoop? background_loop = null;
		
		/**
		 * MainContext for the background thread
		 */
		private MainContext? background_context = null;
		
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
		 * Maximum number of retries for failed pulls
		 */
		private const int MAX_RETRIES = 5;
		
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
			
			// Ensure data directory exists
			try {
				app.ensure_data_dir();
			} catch (GLib.Error e) {
				GLib.warning("Failed to ensure data directory exists: %s", e.message);
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
				GLib.debug("Pull already in progress for model: %s", model_name);
				return false;
			}
			
			// Ensure background thread is running
			this.ensure_background_thread();
			
			// Get or create status
			LoadingStatus status_obj;
			if (this.loading_status_cache.has_key(model_name)) {
				status_obj = this.loading_status_cache.get(model_name);
			} else {
				status_obj = new LoadingStatus();
				this.loading_status_cache.set(model_name, status_obj);
			}
			
			status_obj.active = true;
			
			// Start pull operation in background thread
			this.start_pull_async(model_name, connection);
			
			return true;
		}
		
		/**
		 * Ensures the background thread is running.
		 */
		private void ensure_background_thread()
		{
			if (this.background_thread != null) {
				return; // Already running
			}
			
			// Create MainContext for background thread
			this.background_context = new MainContext();
			
			// Start background thread
			try {
				this.background_thread = new Thread<bool>.try("model-pull-manager", () => {
					// Set this context as thread default
					this.background_context.push_thread_default();
					
					// Create and run MainLoop
					this.background_loop = new MainLoop(this.background_context);
					this.background_loop.run();
					
					// Clean up
					this.background_context.pop_thread_default();
					this.background_loop = null;
					this.background_context = null;
					
					return true;
				});
			} catch (Error e) {
				GLib.warning("Failed to start background thread: %s", e.message);
				this.background_thread = null;
				this.background_context = null;
			}
		}
		
		/**
		 * Starts a pull operation asynchronously in the background thread.
		 * 
		 * @param model_name Model name to pull
		 * @param connection Connection to use
		 */
		private void start_pull_async(string model_name, OLLMchat.Settings.Connection connection)
		{
			// Schedule the pull operation in the background thread's context
			var source = new IdleSource();
			source.set_callback(() => {
				this.execute_pull(model_name, connection);
				return false;
			});
			source.attach(this.background_context);
		}
		
		/**
		 * Executes a pull operation asynchronously in the background thread.
		 * 
		 * @param model_name Model name to pull
		 * @param connection Connection to use
		 */
		private void execute_pull(string model_name, OLLMchat.Settings.Connection connection)
		{
			// Create client for this connection
			var client = new OLLMchat.Client(connection) {
				config = this.app.config
			};
			
			// Update status in memory and write to file (start event)
			this.update_loading_status(model_name, "pulling", 0, "pulling", true);
			
			// Create Pull call
			var pull_call = new OLLMchat.Call.Pull(client, model_name) {
				stream = true
			};
			
			// Get status object to track retry count
			LoadingStatus status_obj;
			if (this.loading_status_cache.has_key(model_name)) {
				status_obj = this.loading_status_cache.get(model_name);
			} else {
				status_obj = new LoadingStatus();
				this.loading_status_cache.set(model_name, status_obj);
			}
			
			// Track progress
			int progress = 0;
			string status = "pulling";
			string last_chunk_status = "pulling";
			int64 completed = 0;
			int64 total = 0;
			bool saw_success = false;
			
			// Connect to progress signal
			pull_call.progress_chunk.connect((chunk) => {
				// Reset retry count if we received data (means retry is working)
				if (status_obj.retry_count > 0) {
					status_obj.retry_count = 0;
				}
				
				// Parse status from chunk
				if (chunk.has_member("status")) {
					last_chunk_status = chunk.get_string_member("status");
					
					// Track if we saw success status
					if (last_chunk_status == "success") {
						saw_success = true;
						status = "complete";
						progress = 100;
					} else if (last_chunk_status.has_prefix("error") || last_chunk_status == "failed") {
						status = "error";
					} else {
						// Keep pulling status for other statuses
						status = "pulling";
					}
				}
				
				// Parse progress (completed/total)
				if (chunk.has_member("completed") && chunk.has_member("total")) {
					completed = chunk.get_int_member("completed");
					total = chunk.get_int_member("total");
					
					if (total > 0) {
						progress = (int)(((double)completed / (double)total) * 100.0);
					}
				}
				
				// Update status in memory (rate-limited file write)
				this.update_loading_status(model_name, status, progress, last_chunk_status, false);
				
				// Emit progress update (rate-limited via Idle.add)
				this.schedule_progress_update(model_name, status, progress);
			});
			
			// Execute pull asynchronously
			pull_call.exec_pull.begin((obj, res) => {
				try {
					pull_call.exec_pull.end(res);
				} catch (GLib.IOError e) {
					// Treat all IO errors as errors (including CANCELLED - could be network issue)
					status = "error";
					GLib.warning("Pull failed for %s: %s", model_name, e.message);
				} catch (Error e) {
					status = "error";
					GLib.warning("Pull failed for %s: %s", model_name, e.message);
				}
				
				// Final status update - only complete if we saw success in chunks
				if (status != "error" && saw_success) {
					status = "complete";
					progress = 100;
				} else if (status != "error") {
					// If we didn't see success and no error was set, treat as error
					status = "error";
				}
				
				// Handle errors with retry logic
				if (status == "error") {
					status_obj.retry_count++;
					
					if (status_obj.retry_count <= MAX_RETRIES) {
						// Schedule retry
						status = "pending-retry";
						this.update_loading_status(model_name, status, progress, last_chunk_status, true);
						
						// Emit progress update for pending-retry (just progress indicator update)
						Idle.add(() => {
							this.progress_updated(model_name, status, progress);
							return false;
						});
						
						// Schedule retry after delay
						var timeout_source = new TimeoutSource(RETRY_DELAY_SECONDS * 1000);
						timeout_source.set_callback(() => {
							// Check if still active and not completed
							if (this.loading_status_cache.has_key(model_name)) {
								var check_status = this.loading_status_cache.get(model_name);
								if (check_status.active && check_status.status == "pending-retry") {
									// Retry the pull
									this.start_pull_async(model_name, connection);
								}
							}
							return false;
						});
						timeout_source.attach(this.background_context);
						
						// Clean up active flag (will be set again on retry)
						status_obj.active = false;
						return;
					} else {
						// All retries exhausted - mark as failed
						status = "failed";
					}
				}
				
				// Update final status in memory and write to file (finish event)
				this.update_loading_status(model_name, status, progress, last_chunk_status, true);
				
				// Emit final update immediately (not rate-limited)
				Idle.add(() => {
					this.progress_updated(model_name, status, progress);
					
					// If complete, notify client and remove from cache
					if (status == "complete") {
						this.model_complete(model_name);
						this.loading_status_cache.unset(model_name);
						// Write to file to remove completed entry
						this.write_to_file();
					}
					// If failed, notify client and remove from cache
					else if (status == "failed") {
						this.model_failed(model_name);
						this.loading_status_cache.unset(model_name);
						// Write to file to remove failed entry
						this.write_to_file();
					}
					
					return false;
				});
				
				// Clean up active flag
				status_obj.active = false;
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
			} else {
				var now = GLib.get_real_time() / 1000000;
				if ((now - this.last_file_write_time) >= FILE_WRITE_RATE_LIMIT_SECONDS) {
					this.write_to_file();
				}
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
					if (node.get_node_type() == Json.NodeType.OBJECT) {
						var status_obj = Json.gobject_deserialize(
							typeof(LoadingStatus),
							node
						) as LoadingStatus;
						if (status_obj != null) {
							this.loading_status_cache.set(key, status_obj);
						}
					}
				});
			} catch (Error e) {
				GLib.debug("Failed to load loading.json: %s", e.message);
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
				GLib.warning("Failed to write loading.json: %s", e.message);
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
			return this.loading_status_cache.has_key(model_name) && 
			       this.loading_status_cache.get(model_name).active;
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

