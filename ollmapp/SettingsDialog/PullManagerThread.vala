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

namespace OLLMapp.SettingsDialog
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
	internal class PullManagerThread : Object
	{
		/**
		 * Signal emitted when status updates from pull operations.
		 * 
		 * Includes all status information needed for both state management
		 * and rate-limited UI updates.
		 * 
		 * @param model_name Model name
		 * @param status Status string
		 * @param completed Bytes completed
		 * @param total Total bytes
		 * @param last_chunk_status Last chunk status from API
		 * @param retry_count Current retry count (updated by background thread)
		 */
		public signal void status_updated(
			string model_name,
			string status,
			int64 completed,
			int64 total,
			string last_chunk_status,
			int retry_count
		);
		
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
		 * MainContext for the main thread (for dispatching signals)
		 */
		private MainContext main_context;
		
		/**
		 * Maximum number of retries for failed pulls
		 */
		private const int MAX_RETRIES = 5;
		
		/**
		 * Creates a new PullManagerThread.
		 * 
		 * @param app ApplicationInterface instance (provides config)
		 */
		public PullManagerThread(OLLMchat.ApplicationInterface app)
		{
			Object(app: app);
			// Store reference to main thread's MainContext for signal dispatch
			this.main_context = MainContext.default();
		}
		
		/**
		 * Emits status_updated signal on the main thread.
		 * 
		 * This ensures signal handlers run in the main thread context,
		 * which is required for UI updates and thread-safe data access.
		 * 
		 * Uses MainContext.invoke() to dispatch the signal emission to
		 * the main thread's event loop.
		 */
		private void emit_status_updated(
			string model_name,
			string status,
			int64 completed,
			int64 total,
			string last_chunk_status,
			int retry_count
		)
		{
			this.main_context.invoke(() => {
				this.status_updated(
					model_name,
					status,
					completed,
					total,
					last_chunk_status,
					retry_count
				);
				return false;
			});
		}
		
		
		/**
		 * Ensures the background thread is running.
		 * 
		 * ⚠️ NOTE: This method is called from the MAIN THREAD, not from within
		 * the background thread. It creates and starts the background thread
		 * if it doesn't already exist.
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
		 * ⚠️ NOTE: This method is called from the MAIN THREAD, not from within
		 * the background thread. It schedules the pull operation to be executed
		 * in the background thread's context via IdleSource.
		 * 
		 * ⚠️ THREAD SAFETY WARNING: This method passes a Connection object from
		 * the main thread to the background thread. While Connection objects are
		 * typically immutable configuration data, this could potentially cause
		 * thread safety issues if the Connection object is modified on the main
		 * thread while being used in the background thread. Consider cloning/copying
		 * the Connection object before passing it to ensure 100% thread safety.
		 * 
		 * @param model_name Model name to pull
		 * @param connection Connection to use (⚠️ passed from main thread - see warning above)
		 * @param initial_retry_count Initial retry count (from main thread status)
		 */
		public void start_pull(string model_name, OLLMchat.Settings.Connection connection, int initial_retry_count)
		{
			// ⚠️ THREAD SAFETY: Connection object is passed from main thread to background thread
			// This may be a cause of failure if Connection is modified concurrently.
			// Consider: var connection_copy = connection.clone(); and use connection_copy instead
			
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
			// Create local PullStatus object to track state in this thread
			// This is NOT shared with the main thread - it's local to this execution
			var local_status = new PullStatus();
			local_status.status = "pulling";
			local_status.last_chunk_status = "pulling";
			local_status.retry_count = initial_retry_count;
			local_status.completed = 0;
			local_status.total = 0;
			// progress is calculated from completed/total, so no need to set it
			
			// Create client for this connection
			var client = new OLLMchat.Client(connection) {
				config = this.app.config
			};
			
			// Notify start (dispatch to main thread)
			this.emit_status_updated(
				model_name,
				local_status.status,
				local_status.completed,
				local_status.total,
				local_status.last_chunk_status,
				local_status.retry_count
			);
			
			// Create Pull call
			var pull_call = new OLLMchat.Call.Pull(client, model_name) {
				stream = true
			};
			
			// Connect to progress signal
			pull_call.progress_chunk.connect((response) => {
				// Reset retry count if we received data (means retry is working)
				if (local_status.retry_count > 0) {
					local_status.retry_count = 0;
				}
				
				// Get status from response object
				local_status.last_chunk_status = response.status;
				
				// Get progress from response object
				local_status.completed = response.completed;
				local_status.total = response.total;
				
				// Update status based on chunk status
				if (local_status.last_chunk_status == "success") {
					local_status.status = "complete";
					// Set total = completed to ensure progress = 100
					local_status.completed = local_status.total;
				} else if (local_status.last_chunk_status.has_prefix("error") || local_status.last_chunk_status == "failed") {
					local_status.status = "error";
				} else {
					// Keep pulling status for other statuses
					local_status.status = "pulling";
				}
				
				// Notify status update (dispatch to main thread)
				// This single signal handles both state updates and rate-limited UI updates
				this.emit_status_updated(
					model_name,
					local_status.status,
					local_status.completed,
					local_status.total,
					local_status.last_chunk_status,
					local_status.retry_count
				);
			});
			
			// Execute pull asynchronously
			pull_call.exec_pull.begin((obj, res) => {
				try {
					pull_call.exec_pull.end(res);
				} catch (GLib.IOError e) {
					// Treat all IO errors as errors (including CANCELLED - could be network issue)
					local_status.status = "error";
					GLib.warning("Pull failed for " + model_name + ": " + e.message);
				} catch (Error e) {
					local_status.status = "error";
					GLib.warning("Pull failed for " + model_name + ": " + e.message);
				}
				
				// Final status update - only complete if we saw success in chunks
				if (local_status.status != "error" && local_status.last_chunk_status == "success") {
					local_status.status = "complete";
					// Ensure progress = 100 by setting completed = total
					if (local_status.total > 0) {
						local_status.completed = local_status.total;
					} else {
						// If total is 0, set both to 1 to represent 100%
						local_status.completed = 1;
						local_status.total = 1;
					}
				} else if (local_status.status != "error") {
					// If we didn't see success and no error was set, treat as error
					local_status.status = "error";
				}
				
				// Handle errors with retry logic
				if (local_status.status == "error") {
					local_status.retry_count++;
					
					if (local_status.retry_count <= MAX_RETRIES) {
						// Schedule retry
						local_status.status = "pending-retry";
						this.emit_status_updated(
							model_name,
							local_status.status,
							local_status.completed,
							local_status.total,
							local_status.last_chunk_status,
							local_status.retry_count
						);
						return;
					}
					
					// All retries exhausted - mark as failed
					local_status.status = "failed";
				}
				
				// Notify final status update (dispatch to main thread)
				// This single signal handles both state updates and rate-limited UI updates
				this.emit_status_updated(
					model_name,
					local_status.status,
					local_status.completed,
					local_status.total,
					local_status.last_chunk_status,
					local_status.retry_count
				);
			});
		}
	}
}

