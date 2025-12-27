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
	 * Simple string-based searchable dropdown widget.
	 * 
	 * Provides text entry with filtering and popover list for selecting
	 * from a list of strings. Similar to Gtk.SuggestionEntry but simpler.
	 * Extracted generic parts from liboccoder/SearchableDropdown.vala.
	 */
	public class SearchablePulldown : Gtk.Widget
	{
		protected Gtk.Entry entry;
		protected Gtk.Image? arrow;
		public Gtk.Popover popup { get; private set; }
		public Gtk.ListView list { get; private set; }
		
		// Track last search text
		private string last_search_text = "";
		
		/**
		 * Signal emitted when an item is selected.
		 */l
		public signal void item_selected(string? item);
		
		/**
		 * Placeholder text for the entry.
		 */
		public string placeholder_text { get; set; default = ""; }
		
		/**
		 * Whether to show the arrow button.
		 */
		public bool show_arrow { get; set; default = true; }
		
		/**
		 * Get the current entry text.
		 */
		public string get_search_text()
		{
			return this.entry.text;
		}
		
		/**
		 * Signal emitted when search text changes.
		 */
		public signal void search_changed(string search_text);
		
		/**
		 * Get the selected object from the list's selection model.
		 */
		public Object? get_selected_object()
		{
			var model = this.list.model;
			if (model == null || !(model is Gtk.SelectionModel)) {
				return null;
			}
			
			var selection = model as Gtk.SelectionModel;
			var selected_pos = selection.selected;
			if (selected_pos == Gtk.INVALID_LIST_POSITION) {
				return null;
			}
			
			return selection.get_item(selected_pos);
		}
		
		/**
		 * Get the current entry text.
		 */
		public string get_text()
		{
			return this.entry.text;
		}
		
		/**
		 * Set the entry text.
		 */
		public void set_text(string text)
		{
			this.entry.text = text;
		}
		
		/**
		 * Constructor.
		 */
		public SearchablePulldown()
		{
			Object();
			
			// Create entry (text input)
			this.entry = new Gtk.Entry() {
				hexpand = true
			};
			this.entry.set_parent(this);
			this.entry.placeholder_text = this.placeholder_text;
			this.entry.changed.connect(this.on_entry_changed);
			// Add CSS class for styling
			this.entry.add_css_class("suggestion");
			
			// Handle keyboard input - Enter, Escape, arrow keys, etc.
			var key_controller = new Gtk.EventControllerKey();
			key_controller.key_pressed.connect((keyval, keycode, state) => {
				return this.on_key_pressed(keyval, keycode, state);
			});
			this.entry.add_controller(key_controller);
			
			// Handle focus loss - close popup when entry loses focus (but don't trigger selection)
			var focus_controller = new Gtk.EventControllerFocus();
			focus_controller.leave.connect(() => {
				if (this.popup.visible) {
					this.set_popup_visible(false);
				}
			});
			this.entry.add_controller(focus_controller);
			
			// Create popover
			this.popup = new Gtk.Popover() {
				position = Gtk.PositionType.BOTTOM,
				autohide = false,  // Don't auto-hide - we handle closing manually
				has_arrow = false,
				halign = Gtk.Align.START,
				can_focus = false  // Don't allow popover to receive focus - keep focus on entry
			};
			this.popup.set_parent(this);
			this.popup.add_css_class("menu");
			
			// Create scrolled window for list
			var sw = new Gtk.ScrolledWindow() {
				hscrollbar_policy = Gtk.PolicyType.NEVER,
				vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
				max_content_height = 400,
				propagate_natural_height = true,
				propagate_natural_width = false,  // Prevent horizontal expansion
				can_focus = false  // Don't allow scrolled window to receive focus
			};
			
			// Create list view (model and factory must be set by caller)
			// Enable single_click_activate so clicking activates items
			this.list = new Gtk.ListView() {
				single_click_activate = true,  // Click activates item
				can_focus = false  // Don't allow list view to receive focus - keep focus on entry
			};
			// Connect to activate signal - this is called when user clicks an item
			this.list.activate.connect((position) => {
				this.set_popup_visible(false);
				this.on_selected();
			});
			
			sw.child = this.list;
			
			// Wrap scrolled window in a box that fills the popup to catch all scroll events
			var popup_wrapper = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = true
			};
			popup_wrapper.append(sw);
			
			// Add scroll controller to wrapper to catch scroll events over popup area
			var wrapper_scroll_controller = new Gtk.EventControllerScroll(
				Gtk.EventControllerScrollFlags.BOTH_AXES |
				Gtk.EventControllerScrollFlags.DISCRETE |
				Gtk.EventControllerScrollFlags.KINETIC
			);
			wrapper_scroll_controller.scroll.connect((dx, dy) => {
				// Forward scroll to scrolled window if it has room to scroll
				var vadjustment = sw.vadjustment;
				if (vadjustment != null && dy != 0) {
					var current_value = vadjustment.value;
					var new_value = current_value + dy * vadjustment.step_increment * 3;
					vadjustment.value = new_value.clamp(vadjustment.lower, vadjustment.upper - vadjustment.page_size);
				}
				// Always stop propagation to prevent background scrolling
				return true;
			});
			popup_wrapper.add_controller(wrapper_scroll_controller);
			
			this.popup.child = popup_wrapper;
			
			// Update arrow visibility when show_arrow changes
			this.notify["show-arrow"].connect(() => {
				this.update_arrow();
			});
			
			// Update placeholder when it changes
			this.notify["placeholder-text"].connect(() => {
				// Only update placeholder if entry text is empty (don't override user input)
				if (this.entry.text == "") {
					this.entry.placeholder_text = this.placeholder_text;
				}
			});
			
			this.update_arrow();
			
			// Add scroll event controller at widget level to catch and stop scroll events when popup is visible
			var widget_scroll_controller = new Gtk.EventControllerScroll(
				Gtk.EventControllerScrollFlags.BOTH_AXES |
				Gtk.EventControllerScrollFlags.DISCRETE |
				Gtk.EventControllerScrollFlags.KINETIC
			);
			widget_scroll_controller.scroll.connect((dx, dy) => {
				// If popup is visible, stop scroll events from propagating to parent widgets
				if (this.popup.visible) {
					return true;
				}
				return false;
			});
			// Use BUBBLE phase to catch events after children have handled them
			widget_scroll_controller.propagation_phase = Gtk.PropagationPhase.BUBBLE;
			this.add_controller(widget_scroll_controller);
		}
		
		public override bool grab_focus()
		{
			// Delegate focus to entry
			return this.entry.grab_focus();
		}
		
		public override void dispose()
		{
			if (this.entry != null) {
				this.entry.unparent();
			}
			if (this.arrow != null) {
				this.arrow.unparent();
			}
			if (this.popup != null) {
				this.popup.unparent();
			}
			base.dispose();
		}
		
		public override void measure(Gtk.Orientation orientation, 
			int for_size, out int minimum,
			out int natural, out int minimum_baseline, 
			out int natural_baseline)
		{
			int arrow_min = 0, arrow_nat = 0;
			
			this.entry.measure(orientation, for_size, 
				out minimum, out natural, 
				out minimum_baseline, out natural_baseline);
			
			if (this.arrow != null && this.arrow.visible) {
				this.arrow.measure(orientation, for_size, 
					out arrow_min, out arrow_nat, null, null);
			}
			
			if (orientation == Gtk.Orientation.HORIZONTAL) {
				minimum += arrow_nat;
				natural += arrow_nat;
			}
		}
		
		public override void size_allocate(int width, int height, int baseline)
		{
			int arrow_min = 0, arrow_nat = 0;
			
			if (this.arrow != null && this.arrow.visible) {
				this.arrow.measure(Gtk.Orientation.HORIZONTAL, -1, 
					out arrow_min, out arrow_nat, null, null);
			}
			
			// Allocate entry with full width (arrow will overlay on top)
			this.entry.allocate(width, height, baseline, null);
			
			// Add right padding to entry to prevent text from going under the arrow
			if (this.arrow != null && this.arrow.visible && arrow_nat > 0) {
				this.entry.set_margin_end(arrow_nat);
			} else {
				this.entry.set_margin_end(0);
			}
			
			// Allocate arrow overlaid on top of entry at the right side
			if (this.arrow != null && this.arrow.visible) {
				var arrow_point = new Graphene.Point() { 
					x = (float)(width - arrow_nat), 
					y = 0.0f 
				};
				var arrow_transform = new Gsk.Transform();
				arrow_transform = arrow_transform.translate(arrow_point);
				this.arrow.allocate(arrow_nat, height, baseline, arrow_transform);
			}
			
			// Update popover width to be 2x widget width
			this.popup.set_size_request(width * 2, -1);
		}
		
		
		/**
		 * Update arrow button visibility.
		 */
		protected virtual void update_arrow()
		{
			if (this.show_arrow && this.arrow == null) {
				this.arrow = new Gtk.Image.from_icon_name("pan-down-symbolic") {
					tooltip_text = "Show suggestions"
				};
				this.arrow.set_parent(this);
				
				// Make arrow clickable to open popover
				var gesture = new Gtk.GestureClick();
				gesture.released.connect(() => {
					this.set_popup_visible(!this.popup.visible);
				});
				this.arrow.add_controller(gesture);
				return;
			} 
			if (!this.show_arrow && this.arrow != null) {
				this.arrow.unparent();
				this.arrow = null;
			}
		}
		
		/**
		 * Set popover visibility.
		 */
		public void set_popup_visible(bool visible)
		{
			if (this.popup.visible == visible) {
				return;
			}
			
			if (!visible) {
				this.popup.popdown();
				return;
			}
			
			// Check if list has a model with items
			if (this.list.model == null) {
				return;
			}
			if (this.list.model.get_n_items() == 0) {
				return;
			}
			
			// Check if widget is in a toplevel window before showing popup
			var root = this.get_root();
			if (root == null || !(root is Gtk.Window)) {
				return;
			}
			
			// Ensure entry has focus before showing popup
			if (!this.entry.has_focus) {
				this.entry.grab_focus();
			}
			// Always ensure cursor is at end and no text is selected when showing popup
			this.entry.set_position(-1);
			this.entry.select_region(-1, -1);
			this.popup.popup();
			
			// Scroll to top after popup is shown
			GLib.Idle.add(() => {
				var scrolled = this.popup.child as Gtk.ScrolledWindow;
				if (scrolled != null) {
					scrolled.vadjustment.value = scrolled.vadjustment.lower;
				}
				return false;
			});
		}
		
		/**
		 * Handle entry text changes.
		 */
		protected virtual void on_entry_changed()
		{
			var search_text = this.entry.text;
			
			// Only emit signal if search text actually changed
			if (search_text == this.last_search_text) {
				return;
			}
			
			this.last_search_text = search_text;
			
			// Emit signal for caller to handle filtering
			this.search_changed(search_text);
		}
		
		/**
		 * Handle key press events.
		 */
		protected virtual bool on_key_pressed(uint keyval, uint keycode, Gdk.ModifierType state)
		{
			// Ignore if modifier keys are pressed
			if ((state & (Gdk.ModifierType.SHIFT_MASK | Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.CONTROL_MASK)) != 0) {
				return false;
			}
			
			// Handle Enter key - accept current selection and close popup
			if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter || keyval == Gdk.Key.ISO_Enter) {
				if (this.popup.visible) {
					this.set_popup_visible(false);
					this.on_selected();
					return true; // Consume the event
				}
				return false; // Let default behavior handle it
			}
			
			// Handle Escape key - cancel and close popup
			if (keyval == Gdk.Key.Escape) {
				if (this.popup.visible) {
					this.set_popup_visible(false);
					return true; // Consume the event
				}
				return false;
			}
			
			// Handle Tab key - close popup but don't disrupt focus handling
			if (keyval == Gdk.Key.Tab || keyval == Gdk.Key.KP_Tab || keyval == Gdk.Key.ISO_Left_Tab) {
				if (this.popup.visible) {
					this.set_popup_visible(false);
					return false; // Don't disrupt normal focus handling
				}
				return false;
			}
			
			// Handle arrow keys for navigation (caller's selection model handles this)
			if (keyval == Gdk.Key.Up || keyval == Gdk.Key.KP_Up || 
			    keyval == Gdk.Key.Down || keyval == Gdk.Key.KP_Down) {
				// Let the list view handle arrow key navigation
				// If popup not visible and Down key, show it
				if (!this.popup.visible && (keyval == Gdk.Key.Down || keyval == Gdk.Key.KP_Down)) {
					var model = this.list.model;
					if (model != null && model.get_n_items() > 0) {
						this.set_popup_visible(true);
						return true;
					}
				}
				return false; // Let list view handle navigation
			}
			
			return false; // Let default behavior handle other keys
		}
		
		/**
		 * Handle when an item is selected in dropdown (via click or Enter key).
		 */
		protected virtual void on_selected()
		{
			// Emit signal - caller handles getting selected item
			this.item_selected(null);
		}
	}
}

