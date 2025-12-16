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

namespace OLLMcoder.Files
{
	/**
	 * Manages folder files with tree structure and hashmap.
	 * 
	 * Implements ListModel interface using Gee.ArrayList as backing store.
	 * Provides ListStore-compatible methods that update the backing store and emit items_changed signals.
	 */
	public class FolderFiles : Object, GLib.ListModel
	{
		/**
		 * Backing store: ArrayList containing files and folders (hierarchical, with children).
		 * Uses path-based comparison for equality checks.
		 */
		public Gee.ArrayList<FileBase> items { 
			get; set; default = new Gee.ArrayList<FileBase>((a, b) => {
				return a.path == b.path;
			});
		}
		
		
		/**
		 * Hashmap of [name in dir] => file object for quick lookup by basename.
		 */
		public Gee.HashMap<string, FileBase> child_map { get; private set;
			default = new Gee.HashMap<string, FileBase>(); }
		
		/**
		 * Constructor.
		 */
		public FolderFiles()
		{
			Object();
		}
		
		/**
		 * ListModel interface implementation: Get the item type.
		 */
		public Type get_item_type()
		{
			return typeof(FileBase);
		}
		
		/**
		 * ListModel interface implementation: Get the number of items.
		 */
		public uint get_n_items()
		{
			return this.items.size;
		}
		
		/**
		 * ListModel interface implementation: Get item at position.
		 */
		public Object? get_item(uint position)
		{
			if (position >= this.items.size) {
				return null;
			}
			return this.items[(int)position];
		}
		
		/**
		 * Append an item to the list (ListStore-compatible).
		 * Checks for duplicates before adding.
		 * 
		 * @param item The FileBase item to append
		 */
		public void append(FileBase item)
		{
			// Check for duplicates
			if (this.contains(item)) {
				return;
			}
			
			var position = this.items.size;
			this.items.add(item);
			this.child_map.set( GLib.Path.get_basename(item.path), item);
			// Emit items_changed signal
			this.items_changed(position, 0, 1);
		}
		
		/**
		 * Find an item in the list and return its position.
		 * 
		 * @param item The FileBase item to find
		 * @param position Output parameter for the position if found
		 * @return true if item was found, false otherwise
		 */
		public bool find(FileBase item, out uint position)
		{
			var index = this.items.index_of(item);
			if (index >= 0) {
				position = (uint)index;
				return true;
			}
			position = 0;
			return false;
		}
	 
		
		/**
		 * Insert an item at a specific position.
		 * 
		 * @param position The position to insert at
		 * @param item The FileBase item to insert
		 */
		public void insert(uint position, FileBase item)
		{
			if (position > this.items.size) {
				position = this.items.size;
			}
			
			this.items.insert((int)position, item);
			this.child_map.set(GLib.Path.get_basename(item.path), item);
			
			// Emit items_changed signal
			this.items_changed(position, 0, 1);
		}
		
		
		
		/**
		 * Check if an item exists in the list.
		 * 
		 * @param item The FileBase item to check
		 * @return true if item exists, false otherwise
		 */
		public bool contains(FileBase item)
		{
			return this.child_map.has_key(GLib.Path.get_basename(item.path));
		}
		
		/**
		 * Remove an item from the list by item reference.
		 * 
		 * @param item The FileBase item to remove
		 */
		public void remove(FileBase item)
		{
			var position = this.items.index_of(item);
			if (position < 0) {
				return; // Not found
			}
			
			this.remove_at((uint)position);
		}
		
		/**
		 * Remove an item at a specific position (ListStore-compatible).
		 * 
		 * @param position The position of the item to remove
		 */
		public void remove_at(uint position)
		{
			if (position >= this.items.size) {
				return; // Invalid position
			}
			
			var item = this.items[(int)position];
			this.items.remove_at((int)position);
			
			// Remove from child_map based on basename
			this.child_map.unset(GLib.Path.get_basename(item.path));
			
			// Emit items_changed signal
			this.items_changed(position, 1, 0);
		}
		
		/**
		 * Remove all items from the list (ListStore-compatible, alias for clear).
		 */
		public void remove_all()
		{
			var old_n_items = this.items.size;
			this.items.clear();
			this.child_map.clear();
			
			// Emit items_changed signal for ListModel
			if (old_n_items > 0) {
				this.items_changed(0, old_n_items, 0);
			}
		}
		
		
		
		
	}
}
