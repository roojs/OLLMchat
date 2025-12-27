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
	 * Background thread that executes model pull operations.
	 * 
	 * Manages a single background thread with MainLoop to handle
	 * concurrent async pull operations. All pull execution happens
	 * in this thread context.
	 * 
	 * @since 1.3.4
	 */
	internal class ModelPullManagerThread : Object
	{
		/**
		 * Signal emitted when status updates from pull operations.
		 * 
		 * @param model_name Model name
		 * @param status Status string
		 * @param progress Progress percentage
		 * @param last_chunk_status Last chunk status from API
		 * @param retry_count Current retry count (updated by background thread)
		 */
		public signal void status_updated(string model_name, string status, int progress, string last_chunk_status, int retry_count);
		
		/**
		 * Signal emitted for progress updates (rate-limited UI updates).
		 * 
		 * @param model_name Model name
		 * @param status Status string
		 * @param progress Progress percentage
		 */
		public signal void progress_updated(string model_name, string status, int progress);
		
		/**
		 * Application interface (provides config)
		 */
		public OLLMchat.ApplicationInterface app { get; construct; }
		
		/**
		 * Background thread
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
		 * Maximum number of retries for failed pulls
		 */
		private const int MAX_RETRIES = 5;
		
		/**
		 * Creates a new ModelPullManagerThread.
		 * 
		 * @param app ApplicationInterface instance (provides config)
		 */
		public ModelPullManagerThread(OLLMchat.ApplicationInterface app)
		{
			Object(app: app);
		}
		
		/**
		 * Ensures the background thread is running.
		 */
		public void ensure_thread()
		{
			if (this.background_thread != null) {
				return; // Already running
			}
			
			// Create MainContext for background thread
			this.background_context = new MainContext();
			
			// Start background thread
			try {
				this.background_thread = new Thread<bool>.try("model-pull-thread", () => {
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
				GLib.warning("Failed to start background thread: " + e.message);
				this.background_thread = null;
				this.background_context = null;
			}
		}
		
		/**
		 * Starts a pull operation asynchronously in the background thread.
		 * 
		 * @param model_name Model name to pull
		 * @param connection Connection to use
		 * @param initial_retry_count Initial retry count (from main thread status)
		 */
		public void start_pull(string model_name, OLLMchat.Settings.Connection connection, int initial_retry_count)
		{
			// Schedule the pull operation in the background thread's context
			var source = new IdleSource();
			source.set_callback(() => {
				this.execute_pull(model_name, connection, initial_retry_count);
				return false;
			});
			source.attach(this.background_context);
		}
		
		/**
		 * Executes a pull operation asynchronously in the background thread.
		 * 
		 * @param model_name Model name to pull
		 * @param connection Connection to use
		 * @param initial_retry_count Initial retry count
		 */
		private void execute_pull(string model_name, OLLMchat.Settings.Connection connection, int initial_retry_count)
		{
			// Create client for this connection
			var client = new OLLMchat.Client(connection) {
				config = this.app.config
			};
			
			// Track retry count locally in this thread
			int retry_count = initial_retry_count;
			
			// Notify start
			this.status_updated(model_name, "pulling", 0, "pulling", retry_count);
			
			// Create Pull call
			var pull_call = new OLLMchat.Call.Pull(client, model_name) {
				stream = true
			};
			
			// Track progress
			int progress = 0;
			string status = "pulling";
			string last_chunk_status = "pulling";
			int64 completed = 0;
			int64 total = 0;
			bool saw_success = false;
			
			// Connect to progress signal
			pull_call.progress_chunk.connect((response) => {
				// Reset retry count if we received data (means retry is working)
				if (retry_count > 0) {
					retry_count = 0;
				}
				
				// Get status from response object
				last_chunk_status = response.status;
				
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
				
				// Get progress from response object
				completed = response.completed;
				total = response.total;
				
				if (total > 0) {
					progress = (int)(((double)completed / (double)total) * 100.0);
				}
				
				// Notify status update
				this.status_updated(model_name, status, progress, last_chunk_status, retry_count);
				
				// Notify progress update (for rate-limited UI updates)
				this.progress_updated(model_name, status, progress);
			});
			
			// Execute pull asynchronously
			pull_call.exec_pull.begin((obj, res) => {
				try {
					pull_call.exec_pull.end(res);
				} catch (GLib.IOError e) {
					// Treat all IO errors as errors (including CANCELLED - could be network issue)
					status = "error";
					GLib.warning("Pull failed for " + model_name + ": " + e.message);
				} catch (Error e) {
					status = "error";
					GLib.warning("Pull failed for " + model_name + ": " + e.message);
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
					retry_count++;
					
					if (retry_count <= MAX_RETRIES) {
						// Schedule retry
						status = "pending-retry";
						this.status_updated(model_name, status, progress, last_chunk_status, retry_count);
						this.progress_updated(model_name, status, progress);
						return;
					}
					
					// All retries exhausted - mark as failed
					status = "failed";
				}
				
				// Notify final status update
				this.status_updated(model_name, status, progress, last_chunk_status, retry_count);
				
				// Notify final progress update
				this.progress_updated(model_name, status, progress);
			});
		}
	}
}

