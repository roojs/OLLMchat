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

namespace OLLMcoder.List
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
			
			// Start with what we have
			this.got_list.clear();
			this.got_list.add_all(this.sorted_items);
			
			// Process filtered items from source
			for (uint i = 0; i < this.source_model.get_n_items(); i++) {
				var item_obj = this.source_model.get_item(i);
			
				// Apply filter
				if (!this.filter.match(item_obj)) {
					continue;
				}
				
				// Check if item is already in sorted_items using got_list (which has compare func)
				if (this.got_list.index_of(item_obj) >= 0) {
					// Already in sorted_items, remove from got_list
					this.got_list.remove(item_obj);
				} else {
					// Not in sorted_items, add directly
					this.sorted_items.add(item_obj);
					// Emit items_changed - position will be updated after sort
				}
			}
			
			// Anything left in got_list needs to be removed from sorted_items
			foreach (var item in this.got_list) {
				this.sorted_items.remove(item);
			}
			
			// Sort at the end using the sorter
			this.sorted_items.sort((a, b) => {
				return (int)this.sorter.compare(a, b);
			});
			
			// Compare pre_update and sorted_items to emit precise items_changed signals
			uint max_size = this.pre_update.size > this.sorted_items.size ? this.pre_update.size : this.sorted_items.size;
			for (uint i = 0; i < max_size; i++) {
				Object? pre_item = i < this.pre_update.size ? this.pre_update.get((int)i) : null;
				Object? sorted_item = i < this.sorted_items.size ? this.sorted_items.get((int)i) : null;
				
				// Check if item at position i changed
				if (pre_item == null || sorted_item == null) {
					// Either added or removed
					this.items_changed(i, pre_item != null ? 1 : 0, sorted_item != null ? 1 : 0);
					continue;
				}
				
				// Both exist, check if item moved using index_of
				int pre_index_in_sorted = this.sorted_items.index_of(pre_item);
				if (pre_index_in_sorted != (int)i) {
					// Item moved
					this.items_changed(i, 1, 1);
				}
			}
		}
	}
}
