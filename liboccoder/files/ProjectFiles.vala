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
	 * Manages project files with tree structure and hashmap.
	 * 
	 * Handles all async file I/O operations, directory scanning, and synchronization.
	 * Provides both hierarchical tree structure (for UI tree views) and flat hashmap
	 * (for fast lookups by full path).
	 * Implements ListModel interface using Gee.ArrayList as backing store.
	 */
	public class ProjectFiles : Object, GLib.ListModel
	{
		/**
		 * Backing store: ArrayList containing files and folders (hierarchical, with children).
		 * The tree structure reflects the folder hierarchy using Folder.children for parent-child relationships.
		 */
		private Gee.ArrayList<FileBase> items = new Gee.ArrayList<FileBase>();
		
		/**
		 * Hashmap of full path (full name) => File object for all files in project (for O(1) quick lookup by full path).
		 */
		public Gee.HashMap<string, File> file_map { get; private set;
			default = new Gee.HashMap<string, File>(); }
		
		/**
		 * Reference to the project folder (folder with is_project = true).
		 */
		public Folder project { get; construct; }
		
		/**
		 * Constructor.
		 * 
		 * @param project The project folder (must have is_project = true)
		 */
		public ProjectFiles(Folder project)
		{
			Object(project: project);
			if (!project.is_project) {
				GLib.warning("ProjectFiles created for non-project folder: %s", project.path);
			}
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
		 * Scan the entire project directory asynchronously.
		 * Populates Folder.children and updates tree structure and hashmap.
		 * Excludes .git directories and other hidden/system folders.
		 */
		public async void scan_project()
		{
			try {
				var check_time = new DateTime.now_local().to_unix();
				yield this.read_dir(this.project, check_time, true);
				
				// After scanning, populate tree structure and hashmap from folder hierarchy
				this.populate_from_folder();
			} catch (Error e) {
				GLib.warning("Failed to scan project files for %s: %s", this.project.path, e.message);
			}
		}
		
		/**
		 * Load children from filesystem for a folder.
		 * Handles async file enumeration, symlink resolution, and updates Folder.children.
		 * Excludes .git directories and other hidden/system folders.
		 * 
		 * @param folder The folder to read
		 * @param check_time Timestamp for this check operation (prevents re-checking during recursion)
		 * @param recurse Whether to recursively read subdirectories (default: false)
		 * @throws Error if directory cannot be read
		 */
		public async void read_dir(Folder folder, int64 check_time, bool recurse = false) throws Error
		{
			// If this folder was already checked in this scan, skip it
			if (folder.last_check_time == check_time) {
				return;
			}
			
			// Mark this folder as checked
			folder.last_check_time = check_time;
			
			var dir = GLib.File.new_for_path(folder.path);
			if (!dir.query_exists()) {
				throw new GLib.IOError.NOT_FOUND("Directory does not exist: " + folder.path);
			}
			
			// Keep a copy of old children to detect removals
			var old_children = new Gee.ArrayList<FileBase>();
			foreach (var child in folder.children) {
				old_children.add(child);
			}
			var old_child_map = new Gee.HashMap<string, FileBase>();
			foreach (var entry in folder.child_map.entries) {
				old_child_map[entry.key] = entry.value;
			}
			
			// Track which children we've seen from filesystem (to detect removals)
			var seen_children = new Gee.HashSet<FileBase>();
			
			var enumerator = yield dir.enumerate_children_async(
				GLib.FileAttribute.STANDARD_NAME + "," + 
				GLib.FileAttribute.STANDARD_TYPE + "," +
				GLib.FileAttribute.STANDARD_IS_SYMLINK + "," +
				GLib.FileAttribute.STANDARD_SYMLINK_TARGET,
				GLib.FileQueryInfoFlags.NONE,
				GLib.Priority.DEFAULT,
				null
			);
			
			var info_list = yield enumerator.next_files_async(100, GLib.Priority.DEFAULT, null);
			
			foreach (var info in info_list) {
				var name = info.get_name();
				
				// Skip .git directories and other hidden/system folders
				if (name == ".git")) {
					continue;
				}
				
				var file_type = info.get_file_type();
				var cpath = GLib.Path.build_filename(folder.path, name);
				
				var is_symlink = info.get_is_symlink();
				var symlink_target = info.get_symlink_target();
				
				// Check if child already exists in old map by name (reuse existing object)
				FileBase? existing_child = null;
				if (old_child_map.has_key(name)) {
					existing_child = old_child_map.get(name);
					if (!is_symlink) {
						// Regular file/folder, reuse existing object
						seen_children.add(existing_child);
						// Ensure it's in children list (might have been removed)
						if (!folder.children.contains(existing_child)) {
							folder.children.add(existing_child);
						}
						// child_map already has it, no need to update
						continue;
					}
					if (existing_child.path == symlink_target) {
						// Symlink not changed, reuse existing object
						seen_children.add(existing_child);
						// Ensure it's in children list
						if (!folder.children.contains(existing_child)) {
							folder.children.add(existing_child);
						}
						continue;
					}
					// it's a symlink and it's changed - need to create new alias object
					// Remove old one from children if present
					folder.children.remove(existing_child);
					folder.child_map.unset(name);
				}
				
				// Check if this realpath already exists in manager (softlink to existing file)
				if (is_symlink && folder.manager.path_map.has_key(symlink_target)) {
					// This is a softlink to an existing file - create FileAlias or FolderAlias wrapper
					var target = folder.manager.path_map[symlink_target];
					
					FileBase alias_obj;
					if (target is File) {
						var file_alias = new FileAlias(folder.manager);
						file_alias.points_to = target;
						file_alias.points_to_id = target.id;
						file_alias.path = cpath; // Alias path (where the symlink exists)
						file_alias.parent = folder;
						file_alias.parent_id = folder.id;
						alias_obj = file_alias;
					} else if (target is Folder) {
						var folder_alias = new FolderAlias(folder.manager);
						folder_alias.points_to = target;
						folder_alias.points_to_id = target.id;
						folder_alias.path = cpath; // Alias path (where the symlink exists)
						folder_alias.parent = folder;
						folder_alias.parent_id = folder.id;
						alias_obj = folder_alias;
					} else {
						// Fallback: just reuse the object
						alias_obj = target;
					}
					
					folder.manager.add_path(cpath, alias_obj, true);
					if (!folder.children.contains(alias_obj)) {
						folder.children.add(alias_obj);
					}
					folder.child_map[name] = alias_obj;
					seen_children.add(alias_obj);
					continue;
				}
				
				// Create new child
				if (file_type == GLib.FileType.DIRECTORY) {
					FileBase tchild;
					
					if (is_symlink) {
						// Check if target folder already exists
						var target_folder = folder.manager.path_map.get(symlink_target) as Folder;
						if (target_folder != null) {
							// Create FolderAlias wrapper
							var folder_alias = new FolderAlias(folder.manager);
							folder_alias.points_to = target_folder;
							folder_alias.points_to_id = target_folder.id;
							folder_alias.path = cpath; // Alias path
							folder_alias.parent = folder;
							folder_alias.parent_id = folder.id;
							tchild = folder_alias;
						} else {
						// Target doesn't exist yet, create FolderAlias with null target
						// We'll set points_to later when target is found
						// Note: Can't create FolderAlias without target, so create regular Folder
						// and we'll need to convert it to FolderAlias later, or just track it differently
						// For now, create regular Folder - we can't use FolderAlias without a target
						var new_folder = new Folder(folder.manager);
						new_folder.path = symlink_target; // Target path
						new_folder.points_to = null; // Will be set when target is found
						new_folder.points_to_id = 0;
						// Note: is_alias is computed, so this won't be an alias until we create FolderAlias
							new_folder.parent = folder;
							new_folder.parent_id = folder.id;
							tchild = new_folder;
							
							// Find the real parent of the target folder by looking up its path
							var target_folder_file = GLib.File.new_for_path(symlink_target);
							var target_parent_file = target_folder_file.get_parent();
							if (target_parent_file != null) {
								var target_parent_path = target_parent_file.get_path();
								// Look up the real parent in path_map
								if (folder.manager.path_map.has_key(target_parent_path)) {
									var real_parent = folder.manager.path_map[target_parent_path] as Folder;
									if (real_parent != null) {
										new_folder.parent = real_parent;
										new_folder.parent_id = real_parent.id;
									}
								}
							}
						}
					} else {
						// Regular folder (not a symlink)
						tchild = new Folder(folder.manager);
						tchild.path = cpath;
						tchild.parent = folder;
						tchild.parent_id = folder.id;
					}
					
					folder.manager.add_path(cpath, tchild, is_symlink);
					if (!folder.children.contains(tchild)) {
						folder.children.add(tchild);
					}
					folder.child_map[name] = tchild;
					seen_children.add(tchild);
					
					continue;
				}
				
				// Create new file
				FileBase child;
				
				if (is_symlink) {
					// Check if target file already exists
					var target_file = folder.manager.path_map.get(symlink_target) as File;
					if (target_file != null) {
						// Create FileAlias wrapper
						var file_alias = new FileAlias(folder.manager);
						file_alias.points_to = target_file;
						file_alias.points_to_id = target_file.id;
						file_alias.path = cpath; // Alias path
						file_alias.parent = folder;
						file_alias.parent_id = folder.id;
						child = file_alias;
					} else {
						// Target doesn't exist yet, create regular File
						// We'll set points_to later when target is found and convert to FileAlias
						// Note: Can't create FileAlias without target, so create regular File for now
						var new_file = new File(folder.manager);
						new_file.path = symlink_target; // Target path
						new_file.points_to = null; // Will be set when target is found
						new_file.points_to_id = 0;
						// Note: is_alias is computed, so this won't be an alias until we create FileAlias
						new_file.parent = folder;
						new_file.parent_id = folder.id;
						child = new_file;
					}
				} else {
					// Regular file (not a symlink)
					child = new File(folder.manager);
					child.path = cpath;
					child.parent = folder;
					child.parent_id = folder.id;
				}
				
				folder.manager.add_path(cpath, child, is_symlink);
				if (!folder.children.contains(child)) {
					folder.children.add(child);
				}
				folder.child_map[name] = child;
				seen_children.add(child);
				
				// Add to file_map if it's a file (not an alias wrapper)
				if (child is File && !(child is FileAlias)) {
					this.file_map[child.path] = (File)child;
				} else if (child is FileAlias) {
					// For FileAlias, add the target file to file_map
					var file_alias = (FileAlias)child;
					if (file_alias.points_to != null && file_alias.points_to is File) {
						this.file_map[((File)file_alias.points_to).path] = (File)file_alias.points_to;
					}
				}
			}
			
			// Find and remove children that no longer exist in filesystem
			foreach (var old_child in old_children) {
				if (seen_children.contains(old_child)) {
					continue; // Still exists in filesystem
				}
				// Remove from children list and map
				folder.children.remove(old_child);
				// Find and remove from child_map by iterating (since we don't have reverse lookup)
				var keys_to_remove = new Gee.ArrayList<string>();
				foreach (var entry in folder.child_map.entries) {
					if (entry.value == old_child) {
						keys_to_remove.add(entry.key);
					}
				}
				foreach (var key in keys_to_remove) {
					folder.child_map.unset(key);
				}
				// Remove from manager
				folder.manager.remove_path(old_child.path);
				folder.child_removed(old_child);
			}
			
			yield enumerator.close_async(GLib.Priority.DEFAULT, null);
			
			// If recurse is true, recursively read all subdirectories
			if (recurse) {
				foreach (var child in folder.children) {
					if (child is Folder) {
						yield this.read_dir((Folder)child, check_time, true);
					}
				}
			}
		}
		
		/**
		 * Add file to both tree structure (at appropriate parent location) and hashmap.
		 * 
		 * @param file The file to add
		 * @param full_path The full path of the file
		 */
		public void add_file(File file, string full_path)
		{
			this.file_map[full_path] = file;
			// Tree structure is maintained via Folder.children, so we don't need to update items here
			// The items list will be rebuilt from Folder.children when needed via populate_from_folder()
		}
		
		/**
		 * Remove file from both tree structure and hashmap.
		 * 
		 * @param full_path The full path of the file to remove
		 */
		public void remove_file(string full_path)
		{
			this.file_map.unset(full_path);
			// Tree structure is maintained via Folder.children, removal happens there
		}
		
		/**
		 * Get file by full path from hashmap (O(1) lookup).
		 * 
		 * @param full_path The full path of the file
		 * @return The file, or null if not found
		 */
		public File? get_file(string full_path)
		{
			return this.file_map.get(full_path);
		}
		
		/**
		 * Get the tree-structured list (for UI binding to tree views).
		 * This ProjectFiles object itself implements ListModel.
		 * 
		 * @return This ProjectFiles object (implements ListModel)
		 */
		public ProjectFiles get_tree_model()
		{
			// Rebuild items from Folder.children hierarchy
			this.populate_from_folder();
			return this;
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
		 * Populate tree structure and hashmap from project folder's children hierarchy.
		 */
		public void populate_from_folder()
		{
			// Clear existing
			this.items.clear();
			this.file_map.clear();
			
			// Emit items_changed signal for ListModel
			var old_n_items = this.items.size;
			
			// Recursively collect all files and folders from project's children
			this.collect_recursive(this.project);
			
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
		 * Synchronize project files with filesystem (detect changes, additions, removals).
		 */
		public async void sync_with_filesystem()
		{
			try {
				yield this.scan_project();
			} catch (Error e) {
				GLib.warning("Failed to sync project files with filesystem: %s", e.message);
			}
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
		
		/**
		 * Get the currently active file in this project.
		 * 
		 * @return The active file, or null if none is active
		 */
		public File? get_active_file()
		{
			// Search through file_map hashmap for active file
			foreach (var file in this.file_map.values) {
				if (file.is_active) {
					return file;
				}
			}
			return null;
		}
	}
}
