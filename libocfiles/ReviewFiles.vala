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

namespace OLLMfiles
{
	/**
	 * Manages files in a project that need approval (flat list for approvals UI).
	 * 
	 * Provides flat list of all files in project that need approval (is_need_approval == true).
	 * Implements ListModel interface. Uses database ID for equality comparison.
	 * Extracts File objects from ProjectFiles, doesn't store ProjectFiles.
	 */
	public class ReviewFiles : Object, GLib.ListModel
	{
		/**
		 * The ProjectFiles collection to extract files from.
		 */
		private ProjectFiles project_files;
		
		/**
		 * Backing store: ArrayList containing File objects.
		 * Uses database ID for equality checks.
		 */
		private Gee.ArrayList<File> items { get; set; 
			default = new Gee.ArrayList<File>((a, b) => {
				return a.id == b.id;
			});
		}
		
		/**
		 * Hashmap of file path => File object for quick lookup.
		 */
		public Gee.HashMap<string, File> file_map { get; private set;
			default = new Gee.HashMap<string, File>(); }
		
		/**
		 * Constructor.
		 * 
		 * @param project_files The ProjectFiles collection to extract files from
		 */
		public ReviewFiles(ProjectFiles project_files)
		{
			this.project_files = project_files;
		}
		
		/**
		 * ListModel interface implementation: Get the item type.
		 */
		public Type get_item_type()
		{
			return typeof(File);
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
			return this.items.get((int)position);
		}
		
		/**
		 * Refresh the list by extracting files from project_files where is_need_approval == true.
		 * 
		 * Scans project_files and updates ReviewFiles:
		 * - Extracts File objects from project_files where is_need_approval == true
		 * - Adds files not already in ReviewFiles
		 * - Removes files where is_need_approval == false or no longer in project_files
		 * - Emits items_changed signal when items are added/removed (via append/remove_at)
		 */
		public void refresh()
		{
			// First loop: Add any new files from project_files that need approval
			foreach (var project_file in this.project_files) {
				if (project_file.file.is_need_approval && !this.file_map.has_key(project_file.file.path)) {
					this.append(project_file.file);
				}
			}
			
			// Second loop: Remove files that no longer need approval (iterate backwards)
			for (var i = (int)this.items.size - 1; i >= 0; i--) {
				var file = this.items.get(i);
				if (!file.is_need_approval) {
					this.remove_at((uint)i);
				}
			}
		}
		
		/**
		 * Clear all items from the list.
		 */
		public void clear()
		{
			var old_n_items = this.items.size;
			this.items.clear();
			this.file_map.clear();
			
			// Emit items_changed signal for ListModel
			if (old_n_items > 0) {
				this.items_changed(0, (uint)old_n_items, 0);
			}
		}
		
		/**
		 * Check if a file is in the list.
		 * 
		 * @param file The File object to check
		 * @return true if file is in list, false otherwise
		 */
		public bool contains(File file)
		{
			return this.items.contains(file);
		}
		
		/**
		 * Append an item to the list (ListStore-compatible).
		 * 
		 * @param item The File item to append
		 */
		public void append(File item)
		{
			var position = this.items.size;
			this.items.add(item);
			this.file_map.set(item.path, item);
			
			// Emit items_changed signal
			this.items_changed(position, 0, 1);
		}
		
		/**
		 * Remove an item from the list by item reference.
		 * 
		 * @param item The File item to remove
		 */
		public void remove(File item)
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
			
			var item = this.items.get((int)position);
			this.items.remove_at((int)position);
			
			// Remove from file_map based on file path
			this.file_map.unset(item.path);
			
			// Emit items_changed signal
			this.items_changed(position, 1, 0);
		}
	}
}
