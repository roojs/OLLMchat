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

namespace OLLMcoder
{
	/**
	 * Base class for searchable dropdown widgets.
	 * 
	 * Provides common functionality for searchable dropdowns with text entry
	 * and arrow button, similar to Gtk.SuggestionEntry.
	 * Follows the exact pattern from the GTK suggestion entry example.
	 */
	public abstract class SearchableDropdown : Gtk.Widget
	{
		protected Gtk.Entry entry;
		protected Gtk.Image? arrow;
		protected Gtk.Popover popup;
		protected Gtk.ListView list;
		protected GLib.ListStore item_store;
		protected Gtk.FilterListModel filtered_items;
		protected Gtk.StringFilter? string_filter;
		protected Gtk.SingleSelection selection;
		
		// Track last search text to avoid unnecessary filter updates
		private string last_search_text = "";
		
		/**
		 * Set the item store (allows using external store like project.all_files).
		 */
		protected virtual void set_item_store(GLib.ListStore store)
		{
			this.item_store = store;
			// Recreate filtered model with new store
			this.filtered_items = new Gtk.FilterListModel(
				this.item_store, this.string_filter);
			// Recreate selection model with new filtered model
			this.selection = new Gtk.SingleSelection(this.filtered_items) {
				autoselect = false,
				can_unselect = true,
				selected = Gtk.INVALID_LIST_POSITION
			};
			// Disabled: Don't monitor selection changes - only trigger actions when popup closes
			// this.selection.notify["selected"].connect(() => {
			// 	this.on_selection_changed();
			// });
			// Update list view with new selection model
			this.list.model = this.selection;
		}
		
		/**
		 * Placeholder text for the entry.
		 */
		public string placeholder_text { get; set; default = ""; }
		
		/**
		 * Whether to show the arrow button.
		 */
		public bool show_arrow { get; set; default = true; }
		
		/**
		 * Get the property name to filter on (e.g., "display_name").
		 */
		protected abstract string get_filter_property();
		
		/**
		 * Handle when an item is selected in dropdown (via click or Enter key).
		 */
		protected abstract void on_selected();
		
		/**
		 * Get the property name to bind for label text (e.g., "path_basename", "display_name").
		 */
		protected abstract string get_label_property();
		
		/**
		 * Get the property name to bind for tooltip text (e.g., "path", "tooltip").
		 */
		protected abstract string get_tooltip_property();
		
		/**
		 * Constructor.
		 */
		protected SearchableDropdown()
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
			
			// Create item store
			this.item_store = new GLib.ListStore(typeof(OLLMfiles.FileBase));
			
			// Create string filter for search
			this.string_filter = new Gtk.StringFilter(
				new Gtk.PropertyExpression(typeof(OLLMfiles.FileBase), 
				null, this.get_filter_property())
			) {
				match_mode = Gtk.StringFilterMatchMode.SUBSTRING,
				ignore_case = true
			};
			
			// Create filtered model
			this.filtered_items = new Gtk.FilterListModel(
				this.item_store, this.string_filter);
			
			// Create selection model
			this.selection = new Gtk.SingleSelection(this.filtered_items) {
				autoselect = false,
				can_unselect = true,
				selected = Gtk.INVALID_LIST_POSITION
			};
			// Monitor selection changes to update entry text (but don't trigger actions)
			// Actions are only triggered when popup closes (via activate signal or Enter key)
			this.selection.notify["selected"].connect(() => {
				// Update entry text to show selected item (like the example's accept_current_selection)
				// But don't call on_selected() - that's only called when popup closes via user action
			});
			
			// Create factory for list items
			var factory = this.create_factory();
			
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
			
			// Add scroll event controller to popup to stop scroll events from propagating to background
			var popup_scroll_controller = new Gtk.EventControllerScroll(
				Gtk.EventControllerScrollFlags.BOTH_AXES |
				Gtk.EventControllerScrollFlags.DISCRETE
			);
			popup_scroll_controller.scroll.connect((dx, dy) => {
				// Allow the scrolled window to handle scrolling, but stop propagation to background
				// Return false to allow default scrolling behavior in the scrolled window
				return false;
			});
			popup_scroll_controller.scroll_begin.connect((event) => {
				// Stop propagation when scroll begins on the popup
				event.stop_propagation();
			});
			popup_scroll_controller.scroll_end.connect((event) => {
				// Stop propagation when scroll ends on the popup
				event.stop_propagation();
			});
			this.popup.add_controller(popup_scroll_controller);
			
			// Create scrolled window for list
			var sw = new Gtk.ScrolledWindow() {
				hscrollbar_policy = Gtk.PolicyType.NEVER,
				vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
				max_content_height = 400,
				propagate_natural_height = true,
				propagate_natural_width = false,  // Prevent horizontal expansion
				can_focus = false  // Don't allow scrolled window to receive focus
			};
			
			// Add scroll event controller to stop scroll events from propagating to background
			var scroll_controller = new Gtk.EventControllerScroll(
				Gtk.EventControllerScrollFlags.BOTH_AXES |
				Gtk.EventControllerScrollFlags.DISCRETE
			);
			scroll_controller.scroll.connect((dx, dy) => {
				// Let the scrolled window handle the scroll, but stop propagation
				// This prevents scroll events from reaching the background SourceView
				return false; // Return false to allow default scrolling behavior
			});
			scroll_controller.scroll_begin.connect((event) => {
				// Stop propagation when scroll begins
				event.stop_propagation();
			});
			scroll_controller.scroll_end.connect((event) => {
				// Stop propagation when scroll ends
				event.stop_propagation();
			});
			sw.add_controller(scroll_controller);
			
			// Create list view
			// Enable single_click_activate so clicking activates items
			// This follows the GTK suggestion entry pattern
			this.list = new Gtk.ListView(this.selection, factory) {
				single_click_activate = true,  // Click activates item
				can_focus = false  // Don't allow list view to receive focus - keep focus on entry
			};
			// Connect to activate signal - this is called when user clicks an item
			this.list.activate.connect((position) => {
				this.set_popup_visible(false);
				this.on_selected();
			});
			
			// Add scroll event controller to list view to stop scroll events from propagating
			var list_scroll_controller = new Gtk.EventControllerScroll(
				Gtk.EventControllerScrollFlags.BOTH_AXES |
				Gtk.EventControllerScrollFlags.DISCRETE
			);
			list_scroll_controller.scroll_begin.connect((event) => {
				// Stop propagation when scroll begins on the list
				event.stop_propagation();
			});
			list_scroll_controller.scroll_end.connect((event) => {
				// Stop propagation when scroll ends on the list
				event.stop_propagation();
			});
			this.list.add_controller(list_scroll_controller);
			
			
			sw.child = this.list;
			this.popup.child = sw;
			
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
		}
		
		public override bool grab_focus()
		{
			// Delegate focus to entry (like the example)
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
			// Entry gets full width so arrow can be overlaid
			this.entry.allocate(width, height, baseline, null);
			
			// Add right padding to entry to prevent text from going under the arrow
			if (this.arrow != null && this.arrow.visible && arrow_nat > 0) {
				// Set right margin/padding on entry to make room for arrow
				// This prevents text from overlapping the arrow
				this.entry.set_margin_end(arrow_nat);
			} else {
				this.entry.set_margin_end(0);
			}
			
			// Allocate arrow overlaid on top of entry at the right side
			if (this.arrow != null && this.arrow.visible) {
				// Create transform to translate arrow to overlay position
				// Arrow is positioned at x = width - arrow_nat, overlaying on top of entry
				var arrow_point = new Graphene.Point() { 
					x = (float)(width - arrow_nat), 
					y = 0.0f 
				};
				var arrow_transform = new Gsk.Transform();
				arrow_transform = arrow_transform.translate(arrow_point);
				this.arrow.allocate(arrow_nat, height, baseline, arrow_transform);
			}
			
			// Update popover width to match widget width (fixed width to prevent resizing)
			// Set both min and max to same value to prevent resizing based on content
			this.popup.set_size_request(width, -1);
			// Also set max width to prevent expansion beyond widget width
			this.popup.set_max_content_width(width);
		}
		
		/**
		 * Create the factory for list items.
		 */
		protected virtual Gtk.ListItemFactory create_factory()
		{
			var factory = new Gtk.SignalListItemFactory();
			factory.setup.connect((item) => {
				var list_item = item as Gtk.ListItem;
				if (list_item == null) {
					return;
				}
				
				var label = new Gtk.Label("") {
					halign = Gtk.Align.START,
					use_markup = true  // Enable markup support for labels that contain Pango markup
				};
				list_item.set_data<Gtk.Label>("label", label);
				list_item.child = label;
			});
			
			factory.bind.connect((item) => {
				var list_item = item as Gtk.ListItem;
				if (list_item == null || list_item.item == null) {
					return;
				}
				
				var item_obj = list_item.item;
				var label = list_item.get_data<Gtk.Label>("label");
				
				if (label == null || item_obj == null) {
					return;
				}
				
				// Use property binding for label and tooltip
				item_obj.bind_property(this.get_label_property(), 
					label, "label", BindingFlags.SYNC_CREATE);
				item_obj.bind_property(this.get_tooltip_property(), 
					label, "tooltip-text", BindingFlags.SYNC_CREATE);
			});
			
		 
			
			return factory;
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
		/**
		 * Set popover visibility.
		 * Follows GTK suggestion entry pattern: show popup when typing, hide when selection made.
		 */
		protected void set_popup_visible(bool visible)
		{
			if (this.popup.visible == visible) {
				return;
			}
			
			if (visible) {
				// Don't show if no items to display
				if (this.filtered_items.get_n_items() == 0) {
					return;
				}
				
				// Check if widget is in a toplevel window before showing popup
				var root = this.get_root();
				if (root == null || !(root is Gtk.Window)) {
					return;
				}
				
				// Clear selection before showing popup (like the example)
				this.selection.selected = Gtk.INVALID_LIST_POSITION;
				
				// Ensure entry has focus before showing popup
				// Only grab focus if entry doesn't already have it to avoid selecting text
				if (!this.entry.has_focus) {
					this.entry.grab_focus();
				}
				// Always ensure cursor is at end and no text is selected when showing popup
				this.entry.set_position(-1);
				this.entry.select_region(-1, -1);
				this.popup.popup();
				
				// Scroll to top after popup is shown (use idle to ensure layout is complete)
				GLib.Idle.add(() => {
					var scrolled = this.popup.child as Gtk.ScrolledWindow;
					if (scrolled != null) {
						scrolled.vadjustment.value = scrolled.vadjustment.lower;
					}
					return false;
				});
			} else {
				this.popup.popdown();
			}
		}
		
		/**
		 * Handle entry text changes.
		 * Only updates the filter when search text actually changes.
		 * Popup should only be shown when explicitly requested (e.g., clicking arrow).
		 * However, if text becomes empty and popup is visible, hide it.
		 */
		protected virtual void on_entry_changed()
		{
			var search_text = this.entry.text;
			
			// Only update filter if search text actually changed
			if (search_text == this.last_search_text) {
				return;
			}
			
			this.last_search_text = search_text;
			
			// Don't update filter if text is empty - keep existing filter (shows all items)
			if (search_text == "") {
				// Clear filter to show all items when text is empty
				this.string_filter.search = "";
				// Restore placeholder when text is cleared
				this.entry.placeholder_text = this.placeholder_text;
				// If text is empty and popup is visible, hide it
				if (this.popup.visible) {
					this.set_popup_visible(false);
				}
				return;
			}
			
			// Update filter only when text changed and is not empty
			this.string_filter.search = search_text;
			// Clear placeholder when user starts typing
			this.entry.placeholder_text = "";
			
			// Show popup when user types (if there are filtered items)
			if (this.filtered_items.get_n_items() > 0) {
				this.set_popup_visible(true);
			}
		}
		
		/**
		 * Handle key press events.
		 * Follows GTK suggestion entry pattern from sample code.
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
			
			// Handle Escape key - cancel and restore search text
			if (keyval == Gdk.Key.Escape) {
				if (this.popup.visible) {
					this.set_popup_visible(false);
					// Restore previous search text (if we track it)
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
			
			// Handle arrow keys for navigation
			uint matches = this.filtered_items.get_n_items();
			uint selected = (uint)this.selection.selected;
			
			if (keyval == Gdk.Key.Up || keyval == Gdk.Key.KP_Up) {
				if (this.popup.visible && matches > 0) {
					if (selected == 0) {
						selected = Gtk.INVALID_LIST_POSITION;
					} else if (selected == Gtk.INVALID_LIST_POSITION) {
						selected = matches - 1;
					} else {
						selected--;
					}
					this.selection.selected = selected;
					if (selected != Gtk.INVALID_LIST_POSITION) {
						var scroll_info = new Gtk.ScrollInfo();
						this.list.scroll_to(selected, Gtk.ListScrollFlags.SELECT, scroll_info);
					}
					return true; // Consume the event
				}
				return false;
			}
			
			if (keyval == Gdk.Key.Down || keyval == Gdk.Key.KP_Down) {
				if (this.popup.visible && matches > 0) {
					if (selected == matches - 1) {
						selected = Gtk.INVALID_LIST_POSITION;
					} else if (selected == Gtk.INVALID_LIST_POSITION) {
						selected = 0;
					} else {
						selected++;
					}
					this.selection.selected = selected;
					if (selected != Gtk.INVALID_LIST_POSITION) {
						var scroll_info = new Gtk.ScrollInfo();
						this.list.scroll_to(selected, Gtk.ListScrollFlags.SELECT, scroll_info);
					}
					return true; // Consume the event
				}
				// If popup not visible, show it
				if (!this.popup.visible && matches > 0) {
					this.set_popup_visible(true);
					this.selection.selected = 0;
					return true;
				}
				return false;
			}
			
			return false; // Let default behavior handle other keys
		}
		
		/**
		 * Find a FileBase in a list model by path.
		 * 
		 * @param list The list model to search
		 * @param filebase The FileBase to find
		 * @return Position if found, -1 otherwise
		 */
		protected int find_in_list(GLib.ListModel list,  OLLMfiles.FileBase filebase)
		{
			var n_items = list.get_n_items();
			for (uint i = 0; i < n_items; i++) {
				var item = list.get_item(i) as OLLMfiles.FileBase;
				if (item != null && item.path == filebase.path) {
					return (int)i;
				}
			}
			return -1;
		}
		
		/**
		 * Set selected item by finding it in the filtered model.
		 * DISABLED: This method is disabled to prevent programmatic selection changes
		 * that trigger cascading activations. Selection should only be changed by user interaction.
		 */
		protected bool set_selected_item_internal(OLLMfiles.FileBase? value)
		{
			// Disabled: Don't set selection programmatically
			// if (value == null) {
			// 	this.selection.selected = Gtk.INVALID_LIST_POSITION;
			// 	this.entry.text = "";
			// 	return true;
			// }
			// 
			// // Check filtered model first
			// var position = this.find_in_list(this.filtered_items, value);
			// if (position != -1) {
			// 	this.selection.selected = (uint)position;
			// 	// Clear entry text (selected item will be shown via placeholder in subclasses)
			// 	this.entry.text = "";
			// 	return true;
			// }
			// 
			// // Not in filtered model, clear search and try again
			// this.entry.text = "";
			// position = this.find_in_list(this.filtered_items, value);
			// if (position != -1) {
			// 	this.selection.selected = (uint)position;
			// 	// Clear entry text (selected item will be shown via placeholder in subclasses)
			// 	this.entry.text = "";
			// 	return true;
			// }
			// 
			return false;
		}
	}
}
