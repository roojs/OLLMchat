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
		 * Map of model_name -> whether pull is active
		 */
		private Gee.HashMap<string, bool> active_pulls;
		
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
		 * @param app ApplicationInterface instance (provides config and data_dir)
		 */
		public ModelPullManager(OLLMchat.ApplicationInterface app)
		{
			Object(app: app);
			
			this.loading_json_path = GLib.Path.build_filename(app.data_dir, "loading.json");
			this.active_pulls = new Gee.HashMap<string, bool>();
			this.last_update_time = new Gee.HashMap<string, int64>();
			this.last_status = new Gee.HashMap<string, string>();
			
			// Ensure data directory exists
			try {
				app.ensure_data_dir();
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
			if (this.active_pulls.has_key(model_name) && 
			    this.active_pulls.get(model_name)) {
				GLib.debug("Pull already in progress for model: %s", model_name);
				return false;
			}
			
			// Get connection from config
			if (!this.app.config.connections.has_key(connection_url)) {
				GLib.warning("Connection not found: %s", connection_url);
				return false;
			}
			
			// Ensure background thread is running
			this.ensure_background_thread();
			
			// Mark pull as active
			this.active_pulls.set(model_name, true);
			
			// Start pull operation in background thread
			this.start_pull_async(model_name, this.app.config.connections.get(connection_url));
			
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
			
			// Execute pull asynchronously
			pull_call.exec_pull.begin((obj, res) => {
				var cancelled = false;
				
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
					return false;
				});
				
				// Clean up
				this.active_pulls.unset(model_name);
				this.last_update_time.unset(model_name);
				this.last_status.unset(model_name);
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
			var now = GLib.get_real_time() / 1000000;
			var last_update = this.last_update_time.get(model_name) ?? 0;
			var last_status_value = this.last_status.get(model_name) ?? "";
			
			// Always emit final status updates
			if (status == "complete" || status == "error" || status == "cancelled") {
				Idle.add(() => {
					this.progress_updated(model_name, status, progress);
					return false;
				});
				this.last_update_time.set(model_name, now);
				this.last_status.set(model_name, status);
				return;
			}
			
			// Emit if status changed
			if (status != last_status_value) {
				Idle.add(() => {
					this.progress_updated(model_name, status, progress);
					return false;
				});
				this.last_update_time.set(model_name, now);
				this.last_status.set(model_name, status);
				return;
			}
			
			// Emit if enough time has passed
			if ((now - last_update) >= UPDATE_RATE_LIMIT_SECONDS) {
				Idle.add(() => {
					this.progress_updated(model_name, status, progress);
					return false;
				});
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
				
				if (GLib.File.new_for_path(this.loading_json_path).query_exists()) {
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
					model_obj.set_string_member("started", (GLib.get_real_time() / 1000000).to_string());
				}
				
				// Add error message if status is error
				if (status == "error" && !model_obj.has_member("error")) {
					model_obj.set_string_member("error", "Pull operation failed");
				}
				
				// Update root object
				var model_node = new Json.Node(Json.NodeType.OBJECT);
				model_node.set_object(model_obj);
				root_obj.set_member(model_name, model_node);
				
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
			return this.active_pulls.has_key(model_name) && 
			       this.active_pulls.get(model_name);
		}
		
		/**
		 * Gets all models that are currently being pulled.
		 * 
		 * @return Set of model names that are being pulled
		 */
		public Gee.Set<string> get_active_pulls()
		{
			var result = new Gee.HashSet<string>();
			foreach (var entry in this.active_pulls.entries) {
				if (entry.value) {
					result.add(entry.key);
				}
			}
			return result;
		}
		
	}
}

