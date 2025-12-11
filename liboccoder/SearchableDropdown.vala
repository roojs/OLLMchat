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
			this.selection.notify["selected"].connect(() => {
				this.on_selection_changed();
			});
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
		 * Handle selection changes in dropdown.
		 */
		protected abstract void on_selection_changed();
		
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
			
			// Create item store
			this.item_store = new GLib.ListStore(typeof(Files.FileBase));
			
			// Create string filter for search
			this.string_filter = new Gtk.StringFilter(
				new Gtk.PropertyExpression(typeof(Files.FileBase), 
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
			this.selection.notify["selected"].connect(() => {
				this.on_selection_changed();
			});
			
			// Create factory for list items
			var factory = this.create_factory();
			
			// Create popover
			this.popup = new Gtk.Popover() {
				position = Gtk.PositionType.BOTTOM,
				autohide = false,
				has_arrow = false,
				halign = Gtk.Align.START
			};
			this.popup.set_parent(this);
			this.popup.add_css_class("menu");
			
			// Create scrolled window for list
			var sw = new Gtk.ScrolledWindow() {
				hscrollbar_policy = Gtk.PolicyType.NEVER,
				vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
				max_content_height = 400,
				propagate_natural_height = true
			};
			
			// Create list view
			this.list = new Gtk.ListView(this.selection, factory) {
				single_click_activate = true
			};
			this.list.activate.connect((position) => {
				this.selection.selected = position;
				this.set_popup_visible(false);
			});
			
			sw.child = this.list;
			this.popup.child = sw;
			
			// Update arrow visibility when show_arrow changes
			this.notify["show-arrow"].connect(() => {
				this.update_arrow();
			});
			
			// Update placeholder when it changes
			this.notify["placeholder-text"].connect(() => {
				this.entry.placeholder_text = this.placeholder_text;
			});
			
			this.update_arrow();
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
			
			// Allocate entry: x=0, y=0, width=width-arrow_nat, height=height
			var entry_alloc = Gtk.Allocation() {
				x = 0,
				y = 0,
				width = width - arrow_nat,
				height = height
			};
			this.entry.allocate(entry_alloc.width, entry_alloc.height, 
				baseline, null);
			
			// Allocate arrow: x=width-arrow_nat, y=0, width=arrow_nat, height=height
			if (this.arrow != null && this.arrow.visible) {
				var arrow_alloc = Gtk.Allocation() {
					x = width - arrow_nat,
					y = 0,
					width = arrow_nat,
					height = height
				};
				this.arrow.allocate(arrow_alloc.width, arrow_alloc.height, 
					baseline, null);
			}
			
			// Update popover width to match widget width
			this.popup.set_size_request(width, -1);
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
					halign = Gtk.Align.START
				};
				list_item.set_data<Gtk.Label>("label", label);
				list_item.child = label;
			});
			
			factory.bind.connect((item) => {
				var list_item = item as Gtk.ListItem;
				if (list_item == null || list_item.item == null) {
					return;
				}
				
				var item_obj = list_item.item as Files.FileBase;
				var label = list_item.get_data<Gtk.Label>("label");
				
				if (label != null && item_obj != null) {
					label.label = item_obj.display_name;
				}
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
		protected void set_popup_visible(bool visible)
		{
			if (this.popup.visible == visible) {
				return;
			}
			
			if (this.filtered_items.get_n_items() == 0) {
				return;
			}
			
			if (visible) {
				if (!this.entry.has_focus) {
					this.entry.grab_focus();
				}
				this.selection.selected = Gtk.INVALID_LIST_POSITION;
				this.popup.popup();
				return;
			} 
			this.popup.popdown();
			
		}
		
		/**
		 * Handle entry text changes.
		 */
		protected virtual void on_entry_changed()
		{
			var search_text = this.entry.text;
			this.string_filter.search = search_text;
			
			// Show popover if there are matches
			if (this.filtered_items.get_n_items() > 0) {
				this.set_popup_visible(true);
			}
		}
		
		/**
		 * Find a FileBase in a list model by path.
		 * 
		 * @param list The list model to search
		 * @param filebase The FileBase to find
		 * @return Position if found, -1 otherwise
		 */
		protected int find_in_list(GLib.ListModel list,  Files.FileBase filebase)
		{
			var n_items = list.get_n_items();
			for (uint i = 0; i < n_items; i++) {
				var item = list.get_item(i) as Files.FileBase;
				if (item != null && item.path == filebase.path) {
					return (int)i;
				}
			}
			return -1;
		}
		
		/**
		 * Set selected item by finding it in the filtered model.
		 */
		protected bool set_selected_item_internal(Files.FileBase? value)
		{
			if (value == null) {
				this.selection.selected = Gtk.INVALID_LIST_POSITION;
				this.entry.text = "";
				return true;
			}
			
			// Check filtered model first
			var position = this.find_in_list(this.filtered_items, value);
			if (position != -1) {
				this.selection.selected = (uint)position;
				this.entry.text = value.display_name;
				return true;
			}
			
			// Not in filtered model, clear search and try again
			this.entry.text = "";
			position = this.find_in_list(this.filtered_items, value);
			if (position != -1) {
				this.selection.selected = (uint)position;
				this.entry.text = value.display_name;
				return true;
			}
			
			return false;
		}
	}
}
