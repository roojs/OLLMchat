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
	 * Manages projects, files, and folders.
	 * 
	 * Provides project discovery, indexing, and file management capabilities.
	 * Database persistence and sync will be added in Phase 2B.
	 */
	public class ProjectManager : Object
	{
		/**
		 * Hashmap of path => FileBase for quick lookup.
		 */
		public Gee.HashMap<string, OLLMcoder.Files.FileBase> path_map { get; private set;
			default = new Gee.HashMap<string, OLLMcoder.Files.FileBase>(); }
		
		/**
		 * Hashmap of pretend path => real path (for symlinks/aliases).
		 */
		public Gee.HashMap<string, string> alias_map { get; private set;
			default = new Gee.HashMap<string, string>(); }
		
		/**
		 * List of all projects.
		 */
		public Gee.ArrayList<OLLMcoder.Files.Project> projects { get; private set;
			default = new Gee.ArrayList<OLLMcoder.Files.Project>(); }
		
		/**
		 * Constructor.
		 */
		public ProjectManager()
		{
		}
		
		/**
		 * Add a path to the path_map and alias_map.
		 * 
		 * @param path The path to add
		 * @param file_base The FileBase object for this path
		 */
		public void add_path(string path, OLLMcoder.Files.FileBase file_base, bool is_symlink = false)
		{
			this.path_map[path] = file_base;
			if (is_symlink) {
				this.alias_map[path] = file_base.path;
			}
		}
		
	 
		
		
		/**
		 * Remove a path from the path_map.
		 * 
		 * @param path The path to remove
		 */
		public void remove_path(string path)
		{
			if (!this.path_map.has_key(path)) {
				return;
			}
			this.path_map.unset(path);
			
			// we should probably remove both sides of alias_map 
			if (this.alias_map.has_key(path)) {
				this.alias_map.unset(path);
			}
			var ar = new Gee.ArrayList<string>();
			foreach (var entry in this.alias_map.keys) {
				if (this.alias_map.get(entry) == path) {
					ar.add(entry);
				}
			}
			foreach(var entry in ar) {
				this.alias_map.unset(entry);
			}
		}
		
		
		/**
		 * Handle file changes (rename, move) and update all alias references.
		 * 
		 * @param old_path The old path
		 * @param new_path The new path
		 */
		public void handle_file_renamed(string old_path, OLLMcoder.Files.FileBase new_file, bool is_symlink = false)
		{
			this.remove_path(old_path);
			this.add_path(new_file.path, new_file, is_symlink);
		}
	}
}
