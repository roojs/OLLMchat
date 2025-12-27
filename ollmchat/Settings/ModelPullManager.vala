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
		 * Data directory path for storing loading.json
		 */
		public string data_dir { get; construct; }
		
		/**
		 * Configuration for creating clients
		 */
		public OLLMchat.Settings.Config2 config { get; construct; }
		
		/**
		 * Path to loading.json file
		 */
		private string loading_json_path;
		
		/**
		 * Map of model_name -> active thread
		 */
		private Gee.HashMap<string, Thread<bool>?> active_threads;
		
		/**
		 * Map of model_name -> last update timestamp (for rate limiting)
		 */
		private Gee.HashMap<string, int64> last_update_time;
		
		/**
		 * Map of model_name -> last status (to detect status changes)
		 */
		private Gee.HashMap<string, string> last_status;
		
		/**
		 * Rate limit: minimum seconds between UI updates (except for status changes and final updates)
		 */
		private const int64 UPDATE_RATE_LIMIT_SECONDS = 2;
		
		/**
		 * Creates a new ModelPullManager.
		 * 
		 * @param data_dir Data directory path (for loading.json)
		 * @param config Configuration for creating clients
		 */
		public ModelPullManager(string data_dir, OLLMchat.Settings.Config2 config)
		{
			Object(
				data_dir: data_dir,
				config: config
			);
			
			this.loading_json_path = GLib.Path.build_filename(data_dir, "loading.json");
			this.active_threads = new Gee.HashMap<string, Thread<bool>?>();
			this.last_update_time = new Gee.HashMap<string, int64>();
			this.last_status = new Gee.HashMap<string, string>();
			
			// Ensure data directory exists
			try {
				var app_interface = new ApplicationInterfaceImpl(data_dir);
				app_interface.ensure_data_dir();
			} catch (GLib.Error e) {
				GLib.warning("Failed to ensure data directory exists: %s", e.message);
			}
		}
		
		/**
		 * Starts a background pull operation for a model.
		 * 
		 * If a pull is already in progress for this model, does nothing.
		 * 
		 * @param model_name Full model name (e.g., "llama2" or "llama2:7b")
		 * @param connection_url Connection URL to use for the pull
		 * @return true if pull was started, false if already in progress
		 */
		public bool start_pull(string model_name, string connection_url)
		{
			// Check if already pulling
			if (this.active_threads.has_key(model_name) && 
			    this.active_threads.get(model_name) != null) {
				GLib.debug("Pull already in progress for model: %s", model_name);
				return false;
			}
			
			// Get connection from config
			if (!this.config.connections.has_key(connection_url)) {
				GLib.warning("Connection not found: %s", connection_url);
				return false;
			}
			var connection = this.config.connections.get(connection_url);
			
			// Mark thread as starting (null means starting, non-null means running)
			this.active_threads.set(model_name, null);
			
			// Start background thread
			try {
				var thread = new Thread<bool>.try("pull-%s".printf(model_name), () => {
					return this.pull_thread_func(model_name, connection);
				});
				this.active_threads.set(model_name, thread);
			} catch (Error e) {
				GLib.warning("Failed to start pull thread for %s: %s", model_name, e.message);
				this.active_threads.unset(model_name);
				return false;
			}
			
			return true;
		}
		
		/**
		 * Background thread function that performs the pull operation.
		 * 
		 * @param model_name Model name to pull
		 * @param connection Connection to use
		 * @return true on success, false on error
		 */
		private bool pull_thread_func(string model_name, OLLMchat.Settings.Connection connection)
		{
			// Create client for this connection
			var client = new OLLMchat.Client(connection) {
				config = this.config
			};
			
			// Write initial status to loading.json
			this.write_loading_status(model_name, "pulling", 0);
			
			// Create Pull call
			var pull_call = new OLLMchat.Call.Pull(client, model_name) {
				stream = true
			};
			
			// Track progress
			int progress = 0;
			string status = "pulling";
			int64 completed = 0;
			int64 total = 0;
			
			// Connect to progress signal
			pull_call.progress_chunk.connect((chunk) => {
				// Parse status
				if (chunk.has_member("status")) {
					status = chunk.get_string_member("status");
				}
				
				// Parse progress (completed/total)
				if (chunk.has_member("completed") && chunk.has_member("total")) {
					completed = chunk.get_int_member("completed");
					total = chunk.get_int_member("total");
					
					if (total > 0) {
						progress = (int)(((double)completed / (double)total) * 100.0);
					}
				}
				
				// Update loading.json with progress
				this.write_loading_status(model_name, status, progress);
				
				// Emit progress update (rate-limited via Idle.add)
				this.schedule_progress_update(model_name, status, progress);
				
				// Check for completion or error
				if (chunk.has_member("status")) {
					var chunk_status = chunk.get_string_member("status");
					if (chunk_status == "success") {
						status = "complete";
						progress = 100;
					} else if (chunk_status.has_prefix("error") || chunk_status == "failed") {
						status = "error";
					}
				}
			});
			
			// Execute pull (this blocks until complete)
			try {
				// Create a MainContext for this thread
				var context = new MainContext();
				var loop = new MainLoop(context);
				var cancelled = false;
				
				// Run async operation in thread
				pull_call.exec_pull.begin((obj, res) => {
					try {
						pull_call.exec_pull.end(res);
					} catch (GLib.IOError e) {
						if (e.code == GLib.IOError.CANCELLED) {
							cancelled = true;
						} else {
							status = "error";
							GLib.warning("Pull failed for %s: %s", model_name, e.message);
						}
					} catch (Error e) {
						status = "error";
						GLib.warning("Pull failed for %s: %s", model_name, e.message);
					}
					loop.quit();
				});
				
				// Process events in this thread's context
				while (!loop.is_running()) {
					context.iteration(false);
				}
				loop.run();
				
				// Final status update
				if (cancelled) {
					status = "cancelled";
				} else if (status != "error") {
					status = "complete";
					progress = 100;
				}
				
				// Write final status
				this.write_loading_status(model_name, status, progress);
				
				// Emit final update immediately (not rate-limited)
				Idle.add(() => {
					this.progress_updated(model_name, status, progress);
					return false; // Don't repeat
				});
				
			} catch (Error e) {
				status = "error";
				progress = 0;
				this.write_loading_status(model_name, status, progress);
				
				// Emit error update immediately
				Idle.add(() => {
					this.progress_updated(model_name, status, progress);
					return false;
				});
				
				GLib.warning("Pull thread error for %s: %s", model_name, e.message);
				return false;
			}
			
			// Clean up thread reference
			this.active_threads.unset(model_name);
			this.last_update_time.unset(model_name);
			this.last_status.unset(model_name);
			
			return status == "complete";
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
			var now = GLib.get_real_time() / 1000000; // Convert to seconds
			var last_update = this.last_update_time.get(model_name) ?? 0;
			var last_status_value = this.last_status.get(model_name) ?? "";
			
			// Check if we should emit update
			bool should_emit = false;
			
			// Always emit final status updates
			if (status == "complete" || status == "error" || status == "cancelled") {
				should_emit = true;
			}
			// Emit if status changed
			else if (status != last_status_value) {
				should_emit = true;
			}
			// Emit if enough time has passed
			else if ((now - last_update) >= UPDATE_RATE_LIMIT_SECONDS) {
				should_emit = true;
			}
			
			if (should_emit) {
				// Schedule UI update via Idle.add
				Idle.add(() => {
					this.progress_updated(model_name, status, progress);
					return false; // Don't repeat
				});
				
				// Update tracking
				this.last_update_time.set(model_name, now);
				this.last_status.set(model_name, status);
			}
		}
		
		/**
		 * Writes pull status to loading.json file.
		 * 
		 * @param model_name Model name
		 * @param status Status string
		 * @param progress Progress percentage (0-100)
		 */
		private void write_loading_status(string model_name, string status, int progress)
		{
			try {
				// Read existing data
				var root = new Json.Node(Json.NodeType.OBJECT);
				Json.Object? root_obj = null;
				
				var file = GLib.File.new_for_path(this.loading_json_path);
				if (file.query_exists()) {
					try {
						var parser = new Json.Parser();
						parser.load_from_file(this.loading_json_path);
						var existing_root = parser.get_root();
						if (existing_root != null && existing_root.get_node_type() == Json.NodeType.OBJECT) {
							root_obj = existing_root.get_object();
							root = existing_root;
						}
					} catch (Error e) {
						GLib.debug("Failed to parse existing loading.json: %s", e.message);
					}
				}
				
				// Create new object if needed
				if (root_obj == null) {
					root_obj = new Json.Object();
					root.set_object(root_obj);
				}
				
				// Create or update model entry
				Json.Object model_obj;
				if (root_obj.has_member(model_name)) {
					var model_node = root_obj.get_member(model_name);
					if (model_node.get_node_type() == Json.NodeType.OBJECT) {
						model_obj = model_node.get_object();
					} else {
						model_obj = new Json.Object();
					}
				} else {
					model_obj = new Json.Object();
				}
				
				// Update fields
				model_obj.set_string_member("status", status);
				model_obj.set_int_member("progress", progress);
				
				// Set started timestamp if not already set
				if (!model_obj.has_member("started")) {
					var timestamp = GLib.get_real_time() / 1000000; // Convert to seconds
					model_obj.set_string_member("started", timestamp.to_string());
				}
				
				// Add error message if status is error
				if (status == "error" && !model_obj.has_member("error")) {
					model_obj.set_string_member("error", "Pull operation failed");
				}
				
				// Update root object
				root_obj.set_member(model_name, new Json.Node.alloc().init_object(model_obj));
				
				// Write to file
				var generator = new Json.Generator();
				generator.set_root(root);
				generator.set_pretty(true);
				var json_str = generator.to_data(null);
				
				GLib.FileUtils.set_contents(this.loading_json_path, json_str);
				
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
			return this.active_threads.has_key(model_name) && 
			       this.active_threads.get(model_name) != null;
		}
		
		/**
		 * Gets all models that are currently being pulled.
		 * 
		 * @return Set of model names that are being pulled
		 */
		public Gee.Set<string> get_active_pulls()
		{
			var result = new Gee.HashSet<string>();
			foreach (var entry in this.active_threads.entries) {
				if (entry.value != null) {
					result.add(entry.key);
				}
			}
			return result;
		}
		
		/**
		 * Helper class to implement ApplicationInterface for ensure_data_dir()
		 */
		private class ApplicationInterfaceImpl : Object, OLLMchat.ApplicationInterface
		{
			public string data_dir { get; set; }
			public OLLMchat.Settings.Config2 config { get; set; }
			
			public ApplicationInterfaceImpl(string data_dir)
			{
				this.data_dir = data_dir;
			}
		}
	}
}

