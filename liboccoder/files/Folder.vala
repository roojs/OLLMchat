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
	 * Represents a folder/directory in the project.
	 * 
	 * Folders maintain a list of their children and a hashmap for quick lookup by filename.
	 * Emits signals when children are added/removed.
	 */
	public class Folder : FileBase
	{
		/**
		 * Constructor.
		 * 
		 * @param manager The ProjectManager instance (required)
		 */
		public Folder(OLLMcoder.ProjectManager manager)
		{
			base(manager);
			this.base_type = "d";
		}
		/**
		 * List of children (files and subfolders).
		 */
		public Gee.ArrayList<FileBase> children { get; set; 
			default = new Gee.ArrayList<FileBase>((a, b) => {
				return a.path == b.path ? 0 : (a.path < b.path ? -1 : 1);
			}); }
		
		/**
		 * Hashmap of [name in dir] => file object.
		 */
		public Gee.HashMap<string, FileBase> child_map { get; set; 
				default = new Gee.HashMap<string, FileBase>(); }
		
		/**
		 * Last check time for this folder (prevents re-checking during recursive scans).
		 */
		public int64 last_check_time { get; set; default = 0; }
		
		/**
		 * Emitted when a child is added.
		 */
		public signal void child_added(FileBase child);
		
		/**
		 * Emitted when a child is removed.
		 */
		public signal void child_removed(FileBase child);
		
		
		/**
		 * Load children from filesystem.
		 * 
		 * @param check_time Timestamp for this check operation (prevents re-checking during recursion)
		 * @param recurse Whether to recursively read subdirectories (default: false)
		 * @throws Error if directory cannot be read
		 */
		public async void read_dir(int64 check_time, bool recurse = false) throws Error
		{
			// If this folder was already checked in this scan, skip it
			if (this.last_check_time == check_time) {
				return;
			}
			
			// Mark this folder as checked
			this.last_check_time = check_time;
			
			var dir = GLib.File.new_for_path(this.path);
			if (!dir.query_exists()) {
				throw new GLib.IOError.NOT_FOUND("Directory does not exist: " + this.path);
			}
			
			// Keep a copy of old children to detect removals
			var old_children = new Gee.ArrayList<FileBase>();
			foreach (var child in this.children) {
				old_children.add(child);
			}
			var old_child_map = new Gee.HashMap<string, FileBase>();
			foreach (var entry in this.child_map.entries) {
				old_child_map[entry.key] = entry.value;
			}
			
			// Clear current children to rebuild from filesystem
			this.children.clear();
			this.child_map.clear();
			
			var enumerator = yield dir.enumerate_children_async(
				GLib.FileAttribute.STANDARD_NAME + "," + 
				GLib.FileAttribute.FILE_TYPE + "," +
				GLib.FileAttribute.STANDARD_IS_SYMLINK + "," +
				GLib.FileAttribute.STANDARD_SYMLINK_TARGET,
				GLib.FileQueryInfoFlags.NONE,
				GLib.Priority.DEFAULT,
				null
			);
			
			var info_list = yield enumerator.next_files_async(100, GLib.Priority.DEFAULT, null);
			
			foreach (var info in info_list) {
				var name = info.get_name();
				var file_type = info.get_file_type();
				var child_path = GLib.Path.build_filename(this.path, name);
				
				// Get realpath (resolves symlinks)
				var child_file = GLib.File.new_for_path(child_path);
				
				var is_symlink = info.get_is_symlink();
				var symlink_target = info.get_symlink_target();
				
				var is_new = false;				
				// Check if child already exists in old map by name (reuse existing object)
				if (old_child_map.has_key(name)) {
					if (!is_symlink) {
						this.children.add(old_child_map.get(name));
						this.child_map[name] = old_child_map.get(name);
						continue;
					}
					if (old_child_map.get(name).path == symlink_target) {
						// not changed..
						this.children.add(old_child_map.get(name));
						this.child_map[name] = old_child_map.get(name);
						continue;
					}
					// it's a symlink and it's changed..
				} 
				// it's new 


				// Get realpath only if it's a symlink
				string real_path = child_path;
				if (is_symlink) {
					var child_file = GLib.File.new_for_path(child_path);
					try {
						real_path = child_file.resolve_relative_path(".").get_path();
					} catch (GLib.Error e) {
						real_path = child_path; // Fallback to original path if resolution fails
					}
				}
				
 				
				// Check if this realpath already exists in manager (softlink to existing file)
				if (is_symlink && this.manager.path_map.has_key(real_path)) {
					// This is a softlink to an existing file - reuse that File object
					var child = this.manager.path_map[real_path];
					// Add this path as an alias (pretend path => real path)
					this.manager.add_path(child_path, child, true);
					this.children.add(child);
					this.child_map[name] = child;
					// this.child_added(child);
					continue;
				}


				
				// Create new child
				if (file_type == GLib.FileType.DIRECTORY) {
					child = new Folder(this.manager);
					child.parent = this;
					child.parent_id = this.id;
					child.path = is_symlink ? real_path : child_path;
					this.manager.add_path(child_path, child, is_symlink);
					this.children.add(child);
					this.child_map[name] = child;
					// this.child_added(child);
					continue;
									
				} 
				child = new File(this.manager);
				child.parent = this;
				child.parent_id = this.id;
				this.manager.add_path(child_path, child, is_symlink);
				this.children.add(child);
				this.child_map[name] = child;
				// this.child_added(child);
				
				 
				 
			}
			
			// Find and remove children that no longer exist
			foreach (var old_child in old_children) {
				if (this.children.contains(old_child)) {
					continue;
				}
					// Remove from manager
				this.manager.remove_path(old_child.path);
				this.child_removed(old_child);
				
			}
			
			enumerator.close_async(GLib.Priority.DEFAULT, null);
			
			// If recurse is true, recursively read all subdirectories
			if (recurse) {
				foreach (var child in this.children) {
					if (child is Folder) {
						yield ((Folder) child).read_dir(check_time, true);
					}
				}
			}
		}
	}
}
