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
	 * Manages files in a project (flat list for dropdowns/search).
	 * 
	 * Provides flat list of all files in project (not hierarchical). Used for file
	 * dropdowns and search functionality. Implements ListModel and Gee.Iterable
	 * interfaces. Uses database ID for equality comparison.
	 */
	public class ProjectFiles : Object, GLib.ListModel, Gee.Traversable<ProjectFile>, Gee.Iterable<ProjectFile>
	{
		/**
		 * Backing store: ArrayList containing ProjectFile objects.
		 * Uses path-based comparison for equality checks.
		 * since project files is only updated after DB it should use the database ids
		 * to do comparisons
		 */
		private Gee.ArrayList<ProjectFile> items { get; set; 
			default = new Gee.ArrayList<ProjectFile>((a, b) => {
				return a.file.id == b.file.id;
			});
		}
		
		/**
		 * Gee.Traversable interface implementation: Execute function for each item.
		 * 
		 * @param f Function to execute for each ProjectFile
		 * @return true if all items were processed, false if iteration was stopped early
		 */
		public bool foreach(Gee.ForallFunc<ProjectFile> f)
		{
			return this.items.foreach(f);
		}
		
		/**
		 * Gee.Iterable interface implementation: Get iterator over items.
		 * 
		 * @return Iterator over ProjectFile items
		 */
		public Gee.Iterator<ProjectFile> iterator()
		{
			return this.items.iterator();
		}
		
		/**
		 * Hashmap of file path => ProjectFile object for quick lookup.
		 */
		public Gee.HashMap<string, ProjectFile> child_map { get; private set;
			default = new Gee.HashMap<string, ProjectFile>(); }
		
		/**
		 * Hashmap of folder path => Folder object for quick lookup.
		 * Includes both direct folders and folders accessed through aliases.
		 */
		public Gee.HashMap<string, Folder> folder_map { get; private set;
			default = new Gee.HashMap<string, Folder>(); }
		
		/**
		 * Hashmap of path => FileBase object for quick lookup of all items.
		 * Includes files, folders, and FileAlias symlinks - everything in the project.
		 */
		public Gee.HashMap<string, FileBase> all_files { get; private set;
			default = new Gee.HashMap<string, FileBase>(); }
		
		/**
		 * Emitted when a new file is explicitly added to the project (not during scans).
		 * This signal is only emitted when a new file is created, not when files are
		 * discovered during directory scans. Use this to react to new file creation.
		 * 
		 * @param file The newly created File object
		 */
		public signal void new_file_added(File file);
		
		/**
		 * Constructor.
		 */
		public ProjectFiles()
		{
			Object();
		}
		
		/**
		 * Lookup File by file_id using index_of with a temporary ProjectFile.
		 * 
		 * @param file_id The file ID to lookup
		 * @return File object, or null if not found
		 */
		public File? get_by_id(int64 file_id)
		{
			if (file_id <= 0 || this.items.size == 0) {
				return null;
			}
			
			var index = this.items.index_of(
				new ProjectFile(
					this.items[0].file.manager,
					new File(this.items[0].file.manager) {
						id = file_id
					},
					this.items[0].project,
					"",
					""
				)
			);
			if (index < 0) {
				return null;
			}
			
			return this.items[index].file;
		}
		
		/**
		 * ListModel interface implementation: Get the item type.
		 */
		public Type get_item_type()
		{
			return typeof(ProjectFile);
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
		 * 
		 * @param item The ProjectFile item to append
		 */
		public void append(ProjectFile item)
		{
			var position = this.items.size;
			this.items.add(item);
			this.child_map.set(item.file.path, item);
			
			// Emit items_changed signal
			this.items_changed(position, 0, 1);
		}
		
		/**
		 * Find an item in the list and return its position.
		 * 
		 * @param item The ProjectFile item to find
		 * @param position Output parameter for the position if found
		 * @return true if item was found, false otherwise
		 */
		public bool find(ProjectFile item, out uint position)
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
		 * @param item The ProjectFile item to insert
		 */
		public void insert(uint position, ProjectFile item)
		{
			if (position > this.items.size) {
				position = this.items.size;
			}
			
			this.items.insert((int)position, item);
			this.child_map.set(item.file.path, item);
			
			// Emit items_changed signal
			this.items_changed(position, 0, 1);
		}
		
		/**
		 * Check if an item exists in the list.
		 * 
		 * @param item The ProjectFile item to check
		 * @return true if item exists, false otherwise
		 */
		public bool contains(ProjectFile item)
		{
			return this.items.contains(item);
		}
		
		/**
		 * Remove an item from the list by item reference.
		 * 
		 * @param item The ProjectFile item to remove
		 */
		public void remove(ProjectFile item)
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
			
			// Remove from child_map based on file path
			this.child_map.unset(item.file.path);
			
			// Remove from all_files for consistency (may not be in there, but remove if present)
			this.all_files.unset(item.file.path);
			
			// Emit items_changed signal
			this.items_changed(position, 1, 0);
		}
		
		/**
		 * Remove all items from the list (ListStore-compatible).
		 */
		public void remove_all()
		{
			var old_n_items = this.items.size;
			this.items.clear();
			this.child_map.clear();
			this.folder_map.clear();
			
			// Emit items_changed signal for ListModel
			if (old_n_items > 0) {
				this.items_changed(0, old_n_items, 0);
			}
		}
		
		/**
		 * Recursively update project files from a folder tree.
		 * 
		 * Scans the folder and its children recursively, adding only real files
		 * (not aliases) to the project files list. Handles FileAliases by following
		 * them to their target files. Prevents recursing the same folder more than
		 * once by tracking scanned folders using a HashSet of folder IDs.
		 * Also builds a hashmap of folder paths => Folder objects for quick lookup.
		 * 
		 * @param folder The folder to start scanning from (should be a project folder)
		 */
		public void update_from(Folder folder)
		{
			// Track scanned folders to prevent duplicate recursion
			var scanned_folders = new Gee.HashSet<int>();
			
			// Track files found in this scan
			var found_files = new Gee.HashSet<string>();
			
			// Track folders found in this scan
			var found_folders = new Gee.HashSet<string>();
			
			// Clear maps before rebuilding
			this.folder_map.clear();
			this.all_files.clear();
			
			// Recursively process the folder (folder is the project root)
			this.update_from_recursive(
				folder,
				folder,
				scanned_folders,
				found_files,
				found_folders,
				""); // Not inside a symlink at the root
			
			// Remove files that are no longer in the project
			// Note: this.remove() triggers ListModel signals for UI updates
			var to_remove = new Gee.ArrayList<ProjectFile>();
			foreach (var project_file in this.items) {
				if (!found_files.contains(project_file.file.path)) {
					to_remove.add(project_file);
				}
			}
			foreach (var project_file in to_remove) {
				this.remove(project_file);
			}
			
			// Note: folder_map and all_files are cleared and rebuilt by update_from_recursive(),
			// so no cleanup is needed - they only contain items that exist in the current hierarchy
		}
		
		/**
		 * Internal recursive method to scan folders and add files.
		 * 
		 * @param folder The folder to scan
		 * @param project_folder The root project folder (for creating ProjectFile objects)
		 * @param scanned_folders Set of folder IDs that have already been scanned
		 * @param found_files Set of file paths found during this scan
		 * @param found_folders Set of folder paths found during this scan
		 * @param symlink_path The accumulated relative path through symlinks (empty string if not in a symlink)
		 */
		private void update_from_recursive(
			Folder folder,
			Folder project_folder,
			Gee.HashSet<int> scanned_folders,
			Gee.HashSet<string> found_files,
			Gee.HashSet<string> found_folders,
			string symlink_path = "")
		{
			// Prevent recursing the same folder more than once
			if (scanned_folders.contains((int)folder.id)) {
				return;
			}
			
			// Skip ignored folders (e.g., folders with .generated file)
			if (folder.is_ignored) {
				return;
			}
			
			// Mark this folder as scanned
			scanned_folders.add((int)folder.id);
			
			// Add folder to folder_map, all_files, and found_folders
			found_folders.add(folder.path);
			this.folder_map.set(folder.path, folder);
			this.all_files.set(folder.path, folder);
			
			// Loop through children of this folder
			// GLib.debug("DEBUG update_from_recursive: folder.path=%s, symlink_path='%s', children.count=%u", folder.path, symlink_path, folder.children.items.size);
			foreach (var child in folder.children.items) {
				// GLib.debug("DEBUG update_from_recursive: child.path=%s, child type=%s", child.path, child.get_type().name());
				// Handle File objects - add real files to project_files
				if (child is File) {
					var file = child as File;
					// Add all files to all_files (even non-text files)
					this.all_files.set(file.path, file);
				 
					// Only add text files to ProjectFile list (via add_file_if_new)
					// GLib.debug("DEBUG update_from_recursive: child is File (not FileAlias)");
					this.add_file_if_new(
						file,
						project_folder,
						found_files,
						symlink_path);
					continue;
				}
				
				// Handle FileAlias - follow to the real file
				if (child is FileAlias) {
					// GLib.debug("DEBUG update_from_recursive: child is FileAlias");
					// Add FileAlias to all_files (symlinks are included in all_files)
					this.all_files.set(child.path, child);
					this.handle_file_alias(
						child as FileAlias,
						project_folder,
						scanned_folders,
						found_files,
						found_folders,
						symlink_path);
					continue;
				}
				
				// Handle Folder objects - recursively process them
				if (child is Folder) {
					// If we're inside a symlink, append the folder name to symlink_path
					this.update_from_recursive(
						(Folder)child,
						project_folder,
						scanned_folders,
						found_files,
						found_folders,
						(symlink_path != "") ? 
							(symlink_path + "/" + GLib.Path.get_basename(child.path)) :
							 symlink_path);
				}
			}
		}
		
		/**
		 * Add a file to project files if it's not already present.
		 * 
		 * @param file The file to add
		 * @param project_folder The root project folder
		 * @param found_files Set of file paths found during this scan
		 * @param symlink_path The accumulated relative path through symlinks (empty string if not in a symlink)
		 */
		private void add_file_if_new(
			File file,
			Folder project_folder,
			Gee.HashSet<string> found_files,
			string symlink_path = "")
		{
			// Skip ignored files and non-text files
			if (file.is_ignored || !file.is_text) {
				return;
			}
			
			// GLib.debug("DEBUG add_file_if_new: file.path=%s, symlink_path='%s'", file.path, symlink_path);
			found_files.add(file.path);
			
			// Check if this file is already in project_files
			if (this.child_map.has_key(file.path)) {
				var existing = this.child_map.get(file.path);
				if (existing.file.id == file.id) {
					// Same file, no update needed
					return;
				}
				// Different file with same path - remove the old one
				this.remove(existing);
			}
			
			// Calculate relpath using same simple rules as handle_file_alias
			// GLib.debug("DEBUG add_file_if_new: calculated relpath='%s', final relpath='%s'", relpath, symlink_path == "" ? "" : relpath);
			
			// Note: file is already added to all_files in update_from_recursive before calling this method
			// (all_files contains all files, not just text files)
			
			// Create ProjectFile wrapper and add it
			this.append(new ProjectFile(
				project_folder.manager,
				file,
				project_folder,
				"",
				symlink_path == "" ? symlink_path : 
					(symlink_path + "/" + GLib.Path.get_basename(file.path))

			));
			// GLib.debug("DEBUG add_file_if_new: ProjectFile created and appended");
		}
		
		/**
		 * Handle a FileAlias by following it to the real file or folder.
		 * 
		 * @param alias The FileAlias to handle
		 * @param project_folder The root project folder
		 * @param scanned_folders Set of folder IDs that have already been scanned
		 * @param found_files Set of file paths found during this scan
		 * @param found_folders Set of folder paths found during this scan
		 * @param parent_symlink_path The accumulated relative path through parent symlinks (empty string if none)
		 */
		private void handle_file_alias(
			FileAlias alias,
			Folder project_folder,
			Gee.HashSet<int> scanned_folders,
			Gee.HashSet<string> found_files,
			Gee.HashSet<string> found_folders,
			string parent_symlink_path = "")
		{
			// GLib.debug("DEBUG handle_file_alias: alias.path=%s, parent_symlink_path='%s'", alias.path, parent_symlink_path);
			
			// Follow the alias to get the real file
			if (alias.points_to == null) {
				// GLib.debug("DEBUG handle_file_alias: alias.points_to is null, returning");
				return;
			}
			
			var target = alias.points_to;
			// GLib.debug("DEBUG handle_file_alias: target.path=%s, target type=%s", target.path, target.get_type().name());
			
			// Build the accumulated symlink path using simple rules
			string new_symlink_path = alias.path.substring(project_folder.path.length);
			if (parent_symlink_path != "") {
				// Already in a symlink chain - append basename of this symlink
				new_symlink_path = parent_symlink_path + "/" + GLib.Path.get_basename(alias.path);
			}
			// GLib.debug("DEBUG handle_file_alias: new_symlink_path='%s'", new_symlink_path);
			
			// If target is a File, add it with the accumulated symlink path
			if (target is File && !(target is FileAlias)) {
				// GLib.debug("DEBUG handle_file_alias: target is File, calling add_file_if_new");
				this.add_file_if_new(
					(File)target,
					project_folder,
					found_files,
					new_symlink_path);
				return;
			}
			
			// If target is a Folder, recursively process it, passing the accumulated symlink path
			if (target is Folder) {
				// GLib.debug("DEBUG handle_file_alias: target is Folder, calling update_from_recursive");
				this.update_from_recursive(
					(Folder)target,
					project_folder,
					scanned_folders,
					found_files,
					found_folders,
					new_symlink_path);
			} else {
				// GLib.debug("DEBUG handle_file_alias: target is neither File nor Folder, type=%s", target.get_type().name());
			}
		}
		
		/**
		 * Get the active file from the project files list.
		 * FIXME -  how do we determin active files for a project
		 * since a file could be active in another project
		 *
		 * @return The active File, or null if no file is active
		 */
		public File? get_active_file()
		{
			for (uint i = 0; i < this.get_n_items(); i++) {
				var item = this.get_item(i) as ProjectFile;
				if (item != null && item.file.is_active) {
					return item.file;
				}
			}
			return null;
		}
		
		/**
		 * Gets a list of recently modified open files, sorted by modification time (most recent first).
		 * Files older than the specified number of days are ignored.
		 * 
		 * @param days Number of days to look back (files older than this are ignored)
		 * @return A list of File objects
		 */
		public Gee.ArrayList<File> get_recent_list(int days)
		{
			var cutoff_time = new DateTime.now_local().add_days(-days);
			var filtered_files = new Gee.ArrayList<File>();
			
			// Filter files to only those that are open and modified within the specified days
			foreach (var project_file in this.items) {
				if (!project_file.file.is_open || project_file.file.last_modified < 1) {
					continue;
				}
				var file_time = new DateTime.from_unix_local(project_file.file.last_modified);

				if ((new DateTime.from_unix_local(project_file.file.last_modified)).compare(cutoff_time) < 1) {
					continue;
				}
				filtered_files.add(project_file.file);
				
			}
			 
			
			// Sort files by last_modified (most recent first)
			filtered_files.sort((a, b) => {
				if (a.last_modified == b.last_modified) { // unlikely..
					return 0;
				}
				return a.last_modified < b.last_modified ? 1 : -1;
			});
			
			return filtered_files;
		}
		
		/**
		 * Gets a list of file IDs as strings, optionally filtered by language.
		 * 
		 * @param language Optional language filter (e.g., "vala", "python"). If empty string, all files are included.
		 * @return ArrayList of file IDs as strings
		 */
		public Gee.ArrayList<string> get_ids(string language = "")
		{
			var file_ids = new Gee.ArrayList<string>();
			
			foreach (var project_file in this.items) {
				// Apply language filter if specified
				if (language != "" && project_file.file.language != language) {
					continue;
				}
				
				file_ids.add(project_file.file.id.to_string());
			}
			
			return file_ids;
		}
		
		/**
		 * Finds the container folder of a given path by walking up the directory tree.
		 * 
		 * Starting from the given path, walks up using dirname and checks if each
		 * path exists in the folder_map. Returns the first matching folder found,
		 * or null if no folder in the path exists in the project.
		 * 
		 * @param folder_path The path to find the container folder for
		 * @return The Folder object if found, null otherwise
		 */
		public Folder? find_container_of(string folder_path)
		{
			var current_path = folder_path;
			
			// Walk up the directory tree using dirname
			while (current_path != "" && current_path != "/") {
				// Check if this path exists in folder_map
				if (this.folder_map.has_key(current_path)) {
					return this.folder_map.get(current_path);
				}
				
				// Go up one level using dirname
				var parent = GLib.Path.get_dirname(current_path);
				if (parent == current_path) {
					// Reached root, stop
					break;
				}
				current_path = parent;
			}
			
			return null;
		}
		
		/**
		 * Cleanup deleted files from ProjectFiles list and child_map.
		 * 
		 * This is a list-level cleanup operation that removes items from a single list.
		 * Iterates through items and removes any ProjectFile where file.delete_id > 0.
		 * Batches removals to minimize signal emissions. Since GLib.ListModel.items_changed
		 * only supports one contiguous range per signal, this emits one broad signal
		 * indicating all items from the first deletion position changed.
		 * 
		 * This should be called after files are flagged as deleted (during cleanup phase).
		 */
		public async void cleanup_deleted()
		{
			var lowest_removed_index = -1;
			var removed_count = 0;
			
			// Iterate backwards for safe removal (highest to lowest index)
			for (var i = (int)this.items.size - 1; i >= 0; i--) {
				var project_file = this.items.get(i);
				if (project_file.file.delete_id == 0) {
					continue;  // Skip non-deleted files
				}
				
				// Remove from array and child_map immediately
				this.items.remove_at(i);
				this.child_map.unset(project_file.file.path);
				removed_count++;
				lowest_removed_index = i;  // Track lowest index (will be last one found)
			}
			
			if (removed_count == 0) {
				return; // Nothing to remove
			}
			
			// Emit single items_changed signal for the range
			// GLib.ListModel.items_changed only supports one contiguous range per signal
			// For sparse (non-contiguous) deletions, we emit one broad signal:
			// "from lowest_removed_index, removed N items" 
			// This tells UI to refresh from that position onwards
			// Less precise than multiple signals but correct and efficient
			this.items_changed((uint)lowest_removed_index, (uint)removed_count, 0);
			
			// Note: VectorMetadata cleanup happens via ProjectManager.on_cleanup signal
			// (emitted by DeleteManager.cleanup() after all cleanup is complete)
		}
	}
}
