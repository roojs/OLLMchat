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

namespace OLLMchat
{
	/**
	 * Banner widget that displays semantic search analysis progress.
	 */
	public class VectorScanBanner : Gtk.Box
	{
		public Gtk.Label label { get; private set; }
		public Gtk.ProgressBar progress_bar { get; private set; }
		public Gtk.Revealer revealer { get; private set; }
		
		private int total_scan = 0;
		
		/**
		 * Creates a new VectorScanBanner.
		 */
		public VectorScanBanner()
		{
			Object(
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0,
				margin_start: 0,
				margin_end: 0,
				margin_top: 2,
				margin_bottom: 2
			);
			
			this.css_classes = {"banner"};
			
			// Create revealer and set this banner as its child
			this.revealer = new Gtk.Revealer() {
				child = this,
				reveal_child = false,
				transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN
			};
			
			// Create label - centered above progress bar
			this.label = new Gtk.Label("") {
				hexpand = true,
				halign = Gtk.Align.CENTER,
				wrap = true,
				wrap_mode = Pango.WrapMode.WORD_CHAR,
				margin_bottom = 0
			};
			this.append(this.label);
			
			// Create progress bar - full width
			this.progress_bar = new Gtk.ProgressBar() {
				show_text = false,
				fraction = 0.0,
				hexpand = true,
				height_request = 6
			};
			this.append(this.progress_bar);
		}
		
		/**
		 * Updates the banner with scan progress information.
		 * 
		 * @param queue_size Current size of the file queue (number of files remaining).
		 * @param current_file Path of the file currently being scanned (empty string "" when queue is empty).
		 */
		public void update_scan_status(int queue_size, string current_file)
		{
			// Update total_scan to max of current total_scan and queue_size
			// On first update, total_scan is 0, so this sets it to queue_size
			this.total_scan = int.max(this.total_scan, queue_size);
			
			// Ensure total_scan is at least 1 to avoid division by zero
			if (this.total_scan == 0) {
				this.total_scan = 1;
			}
			
			// Calculate progress: 1 - queue_size/total_scan
			// Percentage starts at 0 when queue_size = total_scan, goes to 100% when queue_size = 0
			double fraction = 1.0 - ((double)queue_size / (double)this.total_scan);
			this.progress_bar.fraction = fraction;
			
			// Calculate files scanned: total_scan - queue_size
			int files_scanned = this.total_scan - queue_size;
			
			// Get basename of current file
			string basename = GLib.Path.get_basename(current_file);
			
			if (queue_size == 0) {
				// Queue is empty - show completion then hide immediately
				this.progress_bar.fraction = 1.0;
				this.label.label = "Semantic Search Scanning: %s - %d/%d files completed".printf(basename, this.total_scan, this.total_scan);
				
				// Hide immediately (Revealer will animate the hide)
				this.hide();
				return;
			}
			
			// Show current file and progress: "filename - X/Y files scanned"
			this.label.label = "Semantic Search Scanning: %s - %d/%d files completed".printf(basename, files_scanned, this.total_scan);
			
			
			// Show the banner
			this.revealer.reveal_child = true;
		
		}
		
		/**
		 * Hides the banner.
		 */
		public new void hide()
		{
			this.revealer.reveal_child = false;
			// Reset total_scan when hiding so it recalculates on next scan
			this.total_scan = 0;
		}
	}
}

