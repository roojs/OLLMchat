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

namespace OLLMchatGtk.List
{
	/**
	 * A sorted and filtered list model for any type of object.
	 * 
	 * Implements GLib.ListModel directly with sorting and filtering.
	 * Provides a method to find the position of an object in the sorted list.
	 * 
	 * To create a filter that matches all items (no filtering), use:
	 * `new Gtk.CustomFilter((item) => { return true; })`
	 * 
	 * @since 1.0
	 */
	public class SortedList<T> : GLib.Object, GLib.ListModel
	{
		private GLib.ListModel source_model;
		private Gtk.Filter filter;
		private Gtk.Sorter sorter;
		private Gee.ArrayList<Object> sorted_items;
		private ulong source_changed_id;
		private ulong filter_changed_id;
		private Gee.ArrayList<Object> got_list;
		private Gee.ArrayList<Object> pre_update;
		
		/**
		 * Constructor.
		 * 
		 * @param source_model The source ListModel
		 * @param sorter The sorter to apply (used to derive equality function: items are equal if sorter.compare(a, b) == Gtk.Ordering.EQUAL)
		 * @param filter The filter to apply. To match all items, use `new Gtk.CustomFilter((item) => { return true; })`
		 */
		public SortedList(GLib.ListModel source_model, Gtk.Sorter sorter, Gtk.Filter filter)
		{
			this.source_model = source_model;
			this.sorter = sorter;
			this.model_filter = filter;
			this.filter = filter;
			
			// Derive equality function from sorter: items are equal if sorter.compare returns EQUAL
			this.sorted_items = new Gee.ArrayList<Object>((a, b) => {
				return this.sorter.compare(a, b) == Gtk.Ordering.EQUAL;
			});
			this.got_list = new Gee.ArrayList<Object>((a, b) => {
				return this.sorter.compare(a, b) == Gtk.Ordering.EQUAL;
			});
			this.pre_update = new Gee.ArrayList<Object>((a, b) => {
				return this.sorter.compare(a, b) == Gtk.Ordering.EQUAL;
			});
			
			// Connect to source model changes
			this.source_changed_id = this.source_model.items_changed.connect(this.on_source_changed);
			
			// Connect to filter changes
			this.filter_changed_id = this.filter.changed.connect(this.on_filter_changed);
			
			// Initial build of sorted list
			this.rebuild();
		}
		
		~SortedList()
		{
			if (this.source_changed_id != 0) {
				this.source_model.disconnect(this.source_changed_id);
			}
			if (this.filter_changed_id != 0) {
				this.filter.disconnect(this.filter_changed_id);
			}
		}
		
		/**
		 * The filter being used.
		 */
		public Gtk.Filter model_filter { get; private set; }
		
		/**
		 * ListModel interface implementation: Get the item type.
		 */
		public Type get_item_type()
		{
			return this.source_model.get_item_type();
		}
		
		/**
		 * ListModel interface implementation: Get the number of items.
		 */
		public uint get_n_items()
		{
			return this.sorted_items.size;
		}
		
		/**
		 * ListModel interface implementation: Get item at position.
		 */
		public Object? get_item(uint position)
		{
			if (position >= this.sorted_items.size) {
				return null;
			}
			return this.sorted_items.get((int)position);
		}
		
		/**
		 * Find the position of an object in the sorted list.
		 * 
		 * Uses object reference comparison for efficiency.
		 * 
		 * @param item The object to find
		 * @return The position if found, Gtk.INVALID_LIST_POSITION otherwise
		 */
		public uint find_position(T item)
		{
			var item_obj = item as Object;
			var pos = this.sorted_items.index_of(item_obj);
			if (pos < 0) {
				return Gtk.INVALID_LIST_POSITION;
			}
			return (uint)pos;
		}
		
		/**
		 * Get the item at the specified position as the generic type.
		 * 
		 * @param position The position in the sorted list
		 * @return The object, or null if position is invalid
		 */
		public T? get_item_typed(uint position)
		{
			var item = this.get_item(position);
			return (T) item;
		}
		
		private void on_source_changed(uint position, uint removed, uint added)
		{
			this.rebuild();
		}
		
		private void on_filter_changed(Gtk.FilterChange change)
		{
			this.rebuild();
		}
		
		private void rebuild()
		{
			// Save current state for comparison
			this.pre_update.clear();
			this.pre_update.add_all(this.sorted_items);
			
			// Build new sorted list in a separate list first
			var new_sorted_items = new Gee.ArrayList<Object>((a, b) => {
				return this.sorter.compare(a, b) == Gtk.Ordering.EQUAL;
			});
			
			// Process filtered items from source
			for (uint i = 0; i < this.source_model.get_n_items(); i++) {
				var item_obj = this.source_model.get_item(i);
			
				// Apply filter
				if (!this.filter.match(item_obj)) {
					continue;
				}
				
				// Add to new list
				new_sorted_items.add(item_obj);
			}
			
			// Sort the new list using the sorter
			new_sorted_items.sort((a, b) => {
				return (int)this.sorter.compare(a, b);
			});
			
			// Replace old list with new list atomically
			var old_size = this.sorted_items.size;
			this.sorted_items = new_sorted_items;
			var new_size = this.sorted_items.size;
			
			// Emit a single items_changed signal for the entire change
			// This is safer than emitting multiple signals during rebuild
			if (old_size != new_size || old_size == 0) {
				// Size changed or was empty - emit signal for entire range
				this.items_changed(0, old_size, new_size);
			} else {
				// Same size - check if items actually changed
				bool items_changed = false;
				for (uint i = 0; i < old_size; i++) {
					var old_item = this.pre_update.get((int)i);
					var new_item = this.sorted_items.get((int)i);
					if (old_item != new_item) {
						items_changed = true;
						break;
					}
				}
				if (items_changed) {
					// Items changed - emit signal for entire range
					this.items_changed(0, old_size, new_size);
				}
			}
		}
	}
}

