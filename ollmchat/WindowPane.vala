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
	 * Window pane utility class that manages a split view with special resizing behavior.
	 * 
	 * Handles pane adjustment, visibility, and window resizing behavior.
	 * 
	 * @since 1.0
	 */
	public class WindowPane : Gtk.Box
	{
		public Gtk.Paned paned;
		public Adw.ViewStack tab_view;
		private bool right_pane_visible = false;
		private int saved_start_width = 0;
		private int source_view_min_width = 400;
		
		/**
		 * Creates a new WindowPane instance.
		 * 
		 * @since 1.0
		 */
		public WindowPane()
		{
			Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
			
			// Create horizontal paned widget
			this.paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL) {
				hexpand = true,
				vexpand = true
			};
			
			this.paned.set_resize_start_child(true);
			
			// Create tabbed container for right pane
			this.tab_view = new Adw.ViewStack() {
				hexpand = true,
				vexpand = true
			};
			
			// Create a container for the tab view (needed for hiding)
			var right_pane_container = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true,
				vexpand = true
			};
			right_pane_container.append(this.tab_view);
			
			// Set right pane container as end child (right pane)
			this.paned.set_end_child(right_pane_container);
			this.paned.set_resize_end_child(true);
			
			// Initially hide right pane
			this.hide_right_pane();
			
			// Append paned to this box
			this.append(this.paned);
		}
		
		/**
		 * Shows the right pane with window resizing strategy.
		 * 
		 * Captures current start pane width, sets minimum widths, unhides pane,
		 * then removes constraints in idle callback.
		 * 
		 * @since 1.0
		 */
		public void show_right_pane()
		{
			if (this.right_pane_visible) {
				return;
			}
			
			// Capture current start pane width
			var start_child = this.paned.get_start_child();
			if (start_child != null) {
				var start_allocation = start_child.get_allocation();
				this.saved_start_width = start_allocation.width;
				
				// Set minimum width of start pane to its current width
				start_child.set_size_request(this.saved_start_width, -1);
			}
			
			// Set minimum width of source view
			var right_pane = this.paned.get_end_child();
			if (right_pane != null) {
				right_pane.set_size_request(this.source_view_min_width, -1);
			}
			
			// Unhide right pane
			var end_child = this.paned.get_end_child();
			if (end_child != null) {
				end_child.set_visible(true);
			}
			this.right_pane_visible = true;
			
			// In idle callback, remove the minimum width constraints
			GLib.Idle.add(() => {
				if (start_child != null) {
					start_child.set_size_request(-1, -1);
				}
				if (right_pane != null) {
					right_pane.set_size_request(-1, -1);
				}
				return false;
			});
		}
		
		/**
		 * Hides the right pane and adjusts window size.
		 * 
		 * Start pane remains the same size, window shrinks to accommodate.
		 * 
		 * @since 1.0
		 */
		public void hide_right_pane()
		{
			if (!this.right_pane_visible) {
				return;
			}
			
			// Capture current start pane width before hiding
			var start_child = this.paned.get_start_child();
			if (start_child != null) {
				var start_allocation = start_child.get_allocation();
				this.saved_start_width = start_allocation.width;
			}
			
			// Hide right pane
			var end_child = this.paned.get_end_child();
			if (end_child != null) {
				end_child.set_visible(false);
			}
			this.right_pane_visible = false;
			
			// Set minimum width of start pane to its current width
			// This prevents start pane from expanding when pane is hidden
			if (start_child != null) {
				start_child.set_size_request(this.saved_start_width, -1);
			}
			
			// In idle callback, remove the minimum width constraint
			GLib.Idle.add(() => {
				if (start_child != null) {
					start_child.set_size_request(-1, -1);
				}
				return false;
			});
		}
		
		/**
		 * Sets the minimum width for the source view pane.
		 * 
		 * @param width Minimum width in pixels
		 * @since 1.0
		 */
		public void set_source_view_min_width(int width)
		{
			this.source_view_min_width = width;
		}
	}
}
