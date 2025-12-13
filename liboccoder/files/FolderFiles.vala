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
	 * Similar to ProjectFiles but for regular folders (not just projects).
	 * Implements ListModel interface using Gee.ArrayList as backing store.
	 */
	public class FolderFiles : Object, GLib.ListModel
	{
		/**
		 * Backing store: ArrayList containing files and folders (hierarchical, with children).
		 * The tree structure reflects the folder hierarchy using Folder.children for parent-child relationships.
		 */
		private Gee.ArrayList<FileBase> items = new Gee.ArrayList<FileBase>();
		
		/**
		 * Hashmap of full path (full name) => File object for all files in folder (for O(1) quick lookup by full path).
		 */
		public Gee.HashMap<string, File> file_map { get; private set;
			default = new Gee.HashMap<string, File>(); }
		
		/**
		 * Reference to the folder.
		 */
		public Folder folder { get; construct; }
		
		/**
		 * Children list from the folder (delegates to folder.children).
		 */
		public Gee.ArrayList<FileBase> children {
			get { return this.folder.children; }
			set { this.folder.children = value; }
		}
		
		/**
		 * Constructor.
		 * 
		 * @param folder The folder to manage
		 */
		public FolderFiles(Folder folder)
		{
			Object(folder: folder);
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
		 * Populate tree structure and hashmap from folder's children hierarchy.
		 */
		public void populate_from_folder()
		{
			// Clear existing
			var old_n_items = this.items.size;
			this.items.clear();
			this.file_map.clear();
			
			// Recursively collect all files and folders from folder's children
			this.collect_recursive(this.folder);
			
			// Emit items_changed signal if items changed
			if (old_n_items != this.items.size) {
				this.items_changed(0, old_n_items, this.items.size);
			}
		}
		
		/**
		 * Recursively collect files and folders from a folder and its children.
		 * 
		 * @param folder The folder to collect from
		 */
		private void collect_recursive(Folder folder)
		{
			// Add the folder itself
			this.items.add(folder);
			
			// Add all children
			foreach (var child in folder.children) {
				if (child is File) {
					this.items.add(child);
					// Add to file_map
					this.file_map[child.path] = (File)child;
				} else if (child is Folder) {
					this.collect_recursive((Folder)child);
				}
			}
		}
		
		/**
		 * Get a flat ListStore of all files (for dropdowns, derived from hashmap).
		 * 
		 * @return A flat ListStore of all files
		 */
		public GLib.ListStore get_flat_file_list()
		{
			var flat_store = new GLib.ListStore(typeof(FileBase));
			foreach (var file in this.file_map.values) {
				flat_store.append(file);
			}
			return flat_store;
		}
		
		/**
		 * Clear both tree structure and hashmap.
		 */
		public void clear()
		{
			var old_n_items = this.items.size;
			this.items.clear();
			this.file_map.clear();
			
			// Emit items_changed signal for ListModel
			if (old_n_items > 0) {
				this.items_changed(0, old_n_items, 0);
			}
		}
	}
}
