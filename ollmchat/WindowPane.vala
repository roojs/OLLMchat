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
		private int source_view_min_width = 520;  // 30% wider than 400
		private int saved_space_from_smaller_window = 160;  // 20% of 800px original width
		
		/**
		 * Intended visibility state for the right pane.
		 * Use schedule_pane_update() to apply changes.
		 */
		public bool intended_pane_visible { get; set; default = false; }
		
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
		 * then resizes window to accommodate the new pane.
		 * 
		 * @since 1.0
		 */
		public void show_right_pane()
		{
			if (this.right_pane_visible) {
				GLib.debug("WindowPane: show_right_pane() called but right pane already visible");
				return;
			}
			
			GLib.debug("WindowPane: show_right_pane() starting");
			
			// Get window first to check current size
			var window = this.get_root() as Gtk.Window;
			if (window == null) {
				GLib.debug("WindowPane: show_right_pane() - window is null");
				return;
			}
			
			// Capture current window size
			int current_width = window.default_width;
			int current_height = window.default_height;
			
			// If window is realized, get actual size
			if (window.get_realized()) {
				current_width = window.get_width();
				current_height = window.get_height();
				GLib.debug("WindowPane: window is realized, size=%dx%d", current_width, current_height);
			} else {
				GLib.debug("WindowPane: window not realized, default_size=%dx%d", current_width, current_height);
			}
			
			// Capture current start pane width
			var start_child = this.paned.get_start_child();
			if (start_child != null) {
				this.saved_start_width = start_child.get_width();
				GLib.debug("WindowPane: start_child width=%d", this.saved_start_width);
				if (this.saved_start_width <= 0) {
					// If width not available yet, use a reasonable default
					this.saved_start_width = current_width > 0 ? current_width - this.source_view_min_width : 400;
					GLib.debug("WindowPane: start_child width was 0, using calculated=%d", this.saved_start_width);
				}
				
				// Set minimum width of start pane to its current width
				start_child.set_size_request(this.saved_start_width, -1);
				GLib.debug("WindowPane: set start_child size_request to %d", this.saved_start_width);
			}
			
			// Set minimum width of source view (add saved space from smaller initial window)
			var right_pane = this.paned.get_end_child();
			if (right_pane != null) {
				int editor_width = this.source_view_min_width + this.saved_space_from_smaller_window;
				right_pane.set_size_request(editor_width, -1);
				GLib.debug("WindowPane: set right_pane size_request to %d (base %d + saved space %d)", 
					editor_width, this.source_view_min_width, this.saved_space_from_smaller_window);
			}
			
			// Unhide right pane
			var end_child = this.paned.get_end_child();
			if (end_child != null) {
				end_child.set_visible(true);
				GLib.debug("WindowPane: right pane made visible");
			}
			this.right_pane_visible = true;
			
			// Calculate new window size: add width for right pane (including saved space)
			int editor_width = this.source_view_min_width + this.saved_space_from_smaller_window;
			int new_width = current_width + editor_width;
			if (new_width < this.saved_start_width + editor_width) {
				new_width = this.saved_start_width + editor_width;
			}
			
			// Make window 30% taller when showing right pane
			int new_height = (int)(current_height * 1.3);
			GLib.debug("WindowPane: calculated new_width=%d (current=%d + editor_width=%d), new_height=%d (30%% taller than %d)", 
				new_width, current_width, editor_width, new_height, current_height);
			
			// Temporarily disable resize on start child to prevent expansion
			this.paned.set_resize_start_child(false);
			GLib.debug("WindowPane: disabled resize on start child");
			
			// Resize window to accommodate both panes
			window.set_default_size(new_width, new_height);
			window.queue_resize();
			this.queue_resize();  // Also queue resize on WindowPane itself
			window.present();
			GLib.debug("WindowPane: set window size to %dx%d and queued resize", new_width, new_height);
			
			// Poll repeatedly until window has actually resized
			// This is necessary because set_default_size() doesn't resize immediately
			GLib.Idle.add(() => {
				var check_window = this.get_root() as Gtk.Window;
				int actual_width = check_window != null && check_window.get_realized() ? check_window.get_width() : 0;
				GLib.debug("WindowPane: polling for resize - window width=%d, target=%d (editor will be %d)", 
					actual_width, new_width, editor_width);
				
				// Keep checking until window has resized (with 10px tolerance)
				if (actual_width < new_width - 10) {
					return true;  // Keep polling
				}
				
				GLib.debug("WindowPane: window has resized to %d, setting paned position", actual_width);
				
				int current_pos = this.paned.get_position();
				GLib.debug("WindowPane: setting paned position to %d (current=%d)", this.saved_start_width, current_pos);
				
				// Set paned position to keep left pane at its current width
				// This ensures the right pane gets the new space
				this.paned.set_position(this.saved_start_width);
				
				int new_pos = this.paned.get_position();
				GLib.debug("WindowPane: paned position set to %d (requested %d)", new_pos, this.saved_start_width);
				
				// In a second idle callback, remove the minimum width constraints
				// and re-enable resize on start child
				GLib.Idle.add(() => {
					GLib.debug("WindowPane: second idle callback - removing constraints");
					
					if (start_child != null) {
						int before_width = start_child.get_width();
						start_child.set_size_request(-1, -1);
						GLib.debug("WindowPane: removed start_child size_request (was %d)", before_width);
					}
					if (right_pane != null) {
						int before_width = right_pane.get_width();
						right_pane.set_size_request(-1, -1);
						GLib.debug("WindowPane: removed right_pane size_request (was %d)", before_width);
					}
					
					int pos_before = this.paned.get_position();
					
					// Get current window width to calculate expected right pane width
					var check_win = this.get_root() as Gtk.Window;
					int window_width = check_win != null && check_win.get_realized() ? check_win.get_width() : 0;
					GLib.debug("WindowPane: window_width=%d, saved_start_width=%d, expected_right_width=%d", 
						window_width, this.saved_start_width, window_width > 0 ? window_width - this.saved_start_width : 0);
					
					// Re-assert position after removing constraints
					this.paned.set_position(this.saved_start_width);
					int pos_after = this.paned.get_position();
					GLib.debug("WindowPane: re-asserted paned position: %d -> %d (target %d)", pos_before, pos_after, this.saved_start_width);
					
					// Re-enable resize on start child so user can adjust
					this.paned.set_resize_start_child(true);
					GLib.debug("WindowPane: re-enabled resize on start child");
					
					// Immediately re-check and fix position after re-enabling resize
					GLib.Idle.add(() => {
						int check_pos = this.paned.get_position();
						if (check_pos != this.saved_start_width) {
							GLib.debug("WindowPane: position changed after re-enabling resize: %d -> %d, fixing", check_pos, this.saved_start_width);
							this.paned.set_position(this.saved_start_width);
							GLib.debug("WindowPane: fixed position to %d", this.paned.get_position());
						}
						return false;
					});
					
					// Use a third idle callback to check final state after paned has allocated
					GLib.Idle.add(() => {
						// Final state check
						if (start_child != null) {
							GLib.debug("WindowPane: final start_child width=%d", start_child.get_width());
						}
						if (right_pane != null) {
							GLib.debug("WindowPane: final right_pane width=%d", right_pane.get_width());
						}
						int final_pos = this.paned.get_position();
						GLib.debug("WindowPane: final paned position=%d", final_pos);
						
						// If position drifted, fix it one more time
						if (final_pos != this.saved_start_width) {
							GLib.debug("WindowPane: position drifted to %d, correcting to %d", final_pos, this.saved_start_width);
							this.paned.set_position(this.saved_start_width);
							GLib.debug("WindowPane: corrected position=%d", this.paned.get_position());
						}
						
						return false;
					});
					
					return false;
				});
				
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
				GLib.debug("WindowPane: hide_right_pane() called but right pane already hidden");
				return;
			}
			
			GLib.debug("WindowPane: hide_right_pane() starting");
			
			// Get window first to check current size
			var window = this.get_root() as Gtk.Window;
			if (window == null) {
				GLib.debug("WindowPane: hide_right_pane() - window is null");
				return;
			}
			
			// Capture current window size
			int current_width = window.default_width;
			int current_height = window.default_height;
			
			// If window is realized, get actual size
			if (window.get_realized()) {
				current_width = window.get_width();
				current_height = window.get_height();
				GLib.debug("WindowPane: hide - window is realized, size=%dx%d", current_width, current_height);
			} else {
				GLib.debug("WindowPane: hide - window not realized, default_size=%dx%d", current_width, current_height);
			}
			
			// Capture current start pane width before hiding
			var start_child = this.paned.get_start_child();
			if (start_child != null) {
				this.saved_start_width = start_child.get_width();
				GLib.debug("WindowPane: hide - start_child width=%d", this.saved_start_width);
				if (this.saved_start_width <= 0) {
					// If width not available yet, estimate from window size
					this.saved_start_width = current_width > 0 ? current_width - this.source_view_min_width : 400;
					GLib.debug("WindowPane: hide - start_child width was 0, using calculated=%d", this.saved_start_width);
				}
			}
			
			// Hide right pane
			var end_child = this.paned.get_end_child();
			if (end_child != null) {
				end_child.set_visible(false);
				GLib.debug("WindowPane: hide - right pane hidden");
			}
			this.right_pane_visible = false;
			
			// Set minimum width of start pane to its current width
			// This prevents start pane from expanding when pane is hidden
			if (start_child != null) {
				start_child.set_size_request(this.saved_start_width, -1);
				GLib.debug("WindowPane: hide - set start_child size_request to %d", this.saved_start_width);
			}
			
			// Calculate new window size: subtract width for hidden right pane
			int new_width = current_width - this.source_view_min_width;
			if (new_width < this.saved_start_width) {
				new_width = this.saved_start_width;
			}
			GLib.debug("WindowPane: hide - calculated new_width=%d (current=%d - min_right=%d)", new_width, current_width, this.source_view_min_width);
			
			// Resize window to match start pane width
			window.set_default_size(new_width, current_height);
			window.queue_resize();
			GLib.debug("WindowPane: hide - set window size to %dx%d and queued resize", new_width, current_height);
			
			// In idle callback, remove the minimum width constraint
			GLib.Idle.add(() => {
				GLib.debug("WindowPane: hide - idle callback removing constraint");
				if (start_child != null) {
					int before_width = start_child.get_width();
					start_child.set_size_request(-1, -1);
					GLib.debug("WindowPane: hide - removed start_child size_request (was %d, now %d)", before_width, start_child.get_width());
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
		
		/**
		 * Schedules a visibility update using Idle.add().
		 * 
		 * Applies the current intended_pane_visible state.
		 */
		public void schedule_pane_update()
		{
			GLib.Idle.add(() => {
				// Apply intended state
				if (this.intended_pane_visible) {
					this.show_right_pane();
				} else {
					this.hide_right_pane();
				}
				return false;  // Remove from idle queue (one-time callback)
			});
		}
		
		/**
		 * Adds or shows an agent widget in the tab view.
		 * 
		 * If the widget already exists in tab_view (by name), it's shown.
		 * Otherwise, the widget is added to tab_view (only if not already parented).
		 * The widget is made visible and set as the visible child.
		 * 
		 * @param widget The widget to add or show
		 * @param widget_id The ID/name for the widget in the ViewStack
		 * @return The widget that should be shown (may be the existing one)
		 */
		public Gtk.Widget add_or_show_agent_widget(Gtk.Widget widget, string widget_id)
		{
			// Check if widget already exists in tab_view (by name)
			var existing_widget = this.tab_view.get_child_by_name(widget_id);

			if ( this.tab_view.get_child_by_name(widget_id) == null) {
				this.tab_view.add_named(widget, widget_id);
			} 
			// if ti exists it will be the same object - no need to check..
			// Show widget and set as visible child
			widget.visible = true;
			this.tab_view.set_visible_child_name(widget.name);
			
			return widget;
		}
	}
}
