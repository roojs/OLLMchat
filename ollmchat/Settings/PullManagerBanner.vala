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
	 * Banner widget that displays pull progress information.
	 * 
	 * Connects to PullManager signals and displays progress for active
	 * pull operations using progress bars.
	 * 
	 * @since 1.3.4
	 */
	public class PullManagerBanner : Gtk.Box
	{
		/**
		 * Pull manager instance
		 */
		public PullManager pull_manager { get; construct; }
		
		/**
		 * Internal status tracking map (updated via progress_updated signal)
		 */
		private Gee.HashMap<string, PullStatus> status_tracking = new Gee.HashMap<string, PullStatus>();
		
		/**
		 * Map of model_name => widget container (box with progress bar)
		 */
		private Gee.HashMap<string, Gtk.Box> progress_widgets = new Gee.HashMap<string, Gtk.Box>();
		
		
		
		/**
		 * Creates a new PullManagerBanner.
		 * 
		 * @param pull_manager PullManager instance to connect to
		 */
		public PullManagerBanner(PullManager pull_manager)
		{
			Object(
				pull_manager: pull_manager,
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 6
			);
			
			// Connect to pull manager signals
			this.pull_manager.progress_updated.connect(this.on_progress_updated);
			this.pull_manager.model_failed.connect(this.on_model_failed);
		}
		
		/**
		 * Initializes progress bars for any existing active pulls.
		 * Should be called when the dialog is shown.
		 */
		public void initialize_existing_pulls()
		{
			var active_pulls = this.pull_manager.get_active_pulls();
			foreach (var model_name in active_pulls) {
				var status = this.pull_manager.get_status(model_name);
				if (status != null) {
					this.status_tracking.set(model_name, status);
					this.update_progress_bar(status);
				}
			}
		}
		
		/**
		 * Handles progress updates from PullManager.
		 */
		private void on_progress_updated(PullStatus status)
		{
			// Update tracking map (keep even if complete/failed for 15 second delay)
			this.status_tracking.set(status.model_name, status);
			
			// Update progress bar for this model
			this.update_progress_bar(status);
			
			// Handle completion with delay
			if (status.status == "complete" || status.status == "failed") {
				// Only schedule if not already scheduled
				if (status.completion_timer_id == 0) {
					this.schedule_hide_after_completion(status);
				}
			} else {
				// Cancel any pending hide timer if status changed back to active
				this.cancel_hide_timer(status);
			}
		}
		
		/**
		 * Handles model pull failure after all retries are exhausted.
		 */
		private void on_model_failed(string model_name)
		{
			// Update banner will handle the failed status
			this.update_banner_visibility();
		}
		
		/**
		 * Updates or creates progress bar for a model.
		 */
		private void update_progress_bar(PullStatus status)
		{
			var model_name = status.model_name;
			
			// Get or create widget container for this model
			Gtk.Box? container = null;
			
			if (this.progress_widgets.has_key(model_name)) {
				container = this.progress_widgets.get(model_name);
			} else {
				// Create new container with progress bar
				container = new Gtk.Box(Gtk.Orientation.VERTICAL, 4) {
					margin_bottom = 4
				};
				
				var progress_bar = new Gtk.ProgressBar() {
					show_text = true,
					fraction = 0.0
				};
				
				container.append(progress_bar);
				this.progress_widgets.set(model_name, container);
				this.append(container);
			}
			
			// Get progress bar from container and update it
			var progress_bar = container.get_first_child() as Gtk.ProgressBar;
			if (progress_bar != null) {
				// Use status methods for all calculations
				progress_bar.fraction = status.get_fraction();
				progress_bar.text = status.get_progress_text();
			}
			
			this.update_banner_visibility();
		}
		
		/**
		 * Schedules hiding a progress bar 15 seconds after completion.
		 */
		private void schedule_hide_after_completion(PullStatus status)
		{
			// Cancel any existing timer
			this.cancel_hide_timer(status);
			
			// Schedule hide after 15 seconds
			var model_name = status.model_name;
			var timer_id = GLib.Timeout.add_seconds(15, () => {
				this.remove_progress_bar(model_name);
				status.completion_timer_id = 0;
				return false;
			});
			status.completion_timer_id = timer_id;
		}
		
		/**
		 * Cancels the hide timer for a model.
		 */
		private void cancel_hide_timer(PullStatus status)
		{
			if (status.completion_timer_id != 0) {
				GLib.Source.remove(status.completion_timer_id);
				status.completion_timer_id = 0;
			}
		}
		
		/**
		 * Removes progress bar widget for a model.
		 */
		private void remove_progress_bar(string model_name)
		{
			if (this.progress_widgets.has_key(model_name)) {
				var container = this.progress_widgets.get(model_name);
				container.unparent();
				this.progress_widgets.unset(model_name);
				this.status_tracking.unset(model_name);
			}
			this.update_banner_visibility();
		}
		
		/**
		 * Updates banner visibility based on whether there are any active progress bars.
		 */
		private void update_banner_visibility()
		{
			this.visible = (this.progress_widgets.size > 0);
		}
	}
}

