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
	 * Manages project list with deduplication.
	 * 
	 * Implements ListModel interface using Gee.ArrayList as backing store.
	 * Provides ListStore-compatible methods that update the backing store and emit items_changed signals.
	 * Projects are Folders with is_project = true.
	 */
	public class ProjectList : Object, GLib.ListModel
	{
		/**
		 * Backing store: ArrayList containing Folder objects (projects).
		 * Uses id-based comparison for equality checks (since projects come from database).
		 */
		private Gee.ArrayList<Folder> items { get; set; 
			default = new Gee.ArrayList<Folder>((a, b) => {
				return a.id == b.id;
			});
		}
		
		/**
		 * Hashmap of project id (as string) => Folder object for quick lookup.
		 */
		public Gee.HashMap<string, Folder> project_map { get; private set;
			default = new Gee.HashMap<string, Folder>(); }
		
		/**
		 * Hashmap of project path => Folder object for quick path lookup.
		 */
		public Gee.HashMap<string, Folder> path_map { get; private set;
			default = new Gee.HashMap<string, Folder>(); }
		
		/**
		 * Constructor.
		 */
		public ProjectList()
		{
			Object();
		}
		
		/**
		 * ListModel interface implementation: Get the item type.
		 */
		public Type get_item_type()
		{
			return typeof(Folder);
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
		 * Checks for duplicates by both id and path before adding.
		 * 
		 * @param item The Folder (project) item to append
		 */
		public void append(Folder item)
		{
			// Check for duplicates by id
			if (this.contains(item)) {
				return;
			}
			
			// Check for duplicates by path (prevent same path with different IDs)
			if (item.path != "" && this.path_map.has_key(item.path)) {
				GLib.debug("ProjectList.append: Skipping duplicate path '%s' (existing id=%lld, new id=%lld)", 
					item.path, this.path_map.get(item.path).id, item.id);
				return;
			}
			
			this.items.add(item);
			this.project_map.set(item.id.to_string(), item);
			this.path_map.set(item.path, item);
			
			// Emit items_changed signal
			this.items_changed(this.items.size - 1, 0, 1);
		}
		
		/**
		 * Check if an item exists in the list.
		 * 
		 * @param item The Folder item to check
		 * @return true if item exists, false otherwise
		 */
		private bool contains(Folder item)
		{
			return this.project_map.has_key(item.id.to_string());
		}
		
		/**
		 * Remove an item from the list by item reference.
		 * 
		 * @param item The Folder item to remove
		 */
		public void remove(Folder item)
		{
			var position = this.items.index_of(item);
			if (position < 0) {
				return; // Not found
			}
			
			// Set is_project to false when removing from projects list
			item.is_project = false;
			
			this.items.remove_at((int)position);
			
			// Remove from project_map and path_map
			this.project_map.unset(item.id.to_string());
			this.path_map.unset(item.path);
			
			// Emit items_changed signal
			this.items_changed((uint)position, 1, 0);
		}
		
		/**
		 * Get the active project from the projects list.
		 * 
		 * @return The active Folder (project), or null if no project is active
		 */
		public Folder? get_active_project()
		{
			// Count how many projects have is_active = true
			int active_count = 0;
			Folder? result = null;
			foreach (var project in this.items) {
				if (!(project.is_active && project.is_project)) {
					continue;
				}
				active_count++;
				if (result == null) {
					result = project;
				}
				GLib.debug("ProjectList.get_active_project: Found active project '%s' (count=%d)", 
					project.path, active_count);
			}
			GLib.debug("ProjectList.get_active_project: Total active projects found: %d", active_count);
			GLib.debug("ProjectList.get_active_project: Returning project '%s'", 
				result != null ? result.path : "null");
			return result;
		}
		
	}
}
