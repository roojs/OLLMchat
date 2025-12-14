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
		 * Named constructor: Create a Folder from FileInfo.
		 * 
		 * @param parent The parent Folder (required)
		 * @param info The FileInfo object from directory enumeration
		 * @param path The full path to the folder
		 */
		public Folder.new_from_info(
			Folder parent,
			GLib.FileInfo info,
			string path)
		{
			base(parent.manager);
			this.path = path;
			this.parent = parent;
			this.parent_id = parent.id;
		}
		
		
			
		/**
		 * ListStore of all files in project (used by dropdowns).
		 * @deprecated Use project_files.get_flat_file_list() instead.
		 */
		public ProjectFiles? project_files { get; set; default = null; }
		
		/**
		 * Unix timestamp of last view (stored in database, default: 0, used for projects).
		 */
		public int64 last_viewed { get; set; default = 0; }
		
		/**
		 * List of children (files and subfolders) - used for tree view hierarchy.
		 * Implements ListModel interface with add/remove methods.
		 */
		public FolderFiles children { get; set; default = new FolderFiles(); }
			
	
		/**
		 * Last check time for this folder (prevents re-checking during recursive scans).
		 */
		public int64 last_check_time { get; set; default = 0; }
		
		
		/**
		 * Load children from filesystem for this folder.
		 * Handles async file enumeration, symlink resolution, and updates Folder.children.
		 * Excludes .git directories and other hidden/system folders.
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
			foreach (var child in this.children.items) {
				old_children.add(child);
			}
			var old_child_map = new Gee.HashMap<string, FileBase>();
			foreach (var entry in this.children.child_map.entries) {
				old_child_map.set(entry.key, entry.value);
			}
			
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
			
			// First pass: Create all new items
			var new_items = new Gee.ArrayList<FileBase>();
			foreach (var info in info_list) {
				var name = info.get_name();
				
				// Skip .git directories and other hidden/system folders
				if (name == ".git") {
					continue;
				}
				
				var cpath = GLib.Path.build_filename(this.path, name);
				var file_type = info.get_file_type();
				
				if (file_type == GLib.FileType.DIRECTORY && info.get_is_symlink()) {
					new_items.add(new FolderAlias.new_from_info(this, info, cpath));
// we need to make a new item of what it points to,
// and make sure it's in the database..
					continue;
				}
				if (file_type == GLib.FileType.DIRECTORY) {
					new_items.add(new Folder.new_from_info(this, info, cpath));
					continue;
				}
				
				if (info.get_is_symlink()) {
					new_items.add(new FileAlias.new_from_info(this, info, cpath));
					continue;
				}
				
				new_items.add(new File.new_from_info(this, info, cpath));
			}
			
			// Second pass: Compare with old items and handle updates/inserts
			foreach (var new_item in new_items) {
				var name = GLib.Path.get_basename(new_item.path);
				var old_item = old_child_map.get(name);
				
				// New item - append and insert into DB
				if (old_item == null) {
					this.children.append(new_item);
					this.children.child_map.set(name, new_item);
					if (this.manager.db != null) {
						new_item.saveToDB(this.manager.db, null, false);
					}
					continue;
				}
				
				// Old item exists - check if same
				if (!old_item.compare(new_item)) {
					// Totally different - remove old from DB and children
					if (this.manager.db != null) {
						old_item.removeFromDB(this.manager.db);
					}
					this.children.remove(old_item);
					// Add new item
					this.children.append(new_item);
					this.children.child_map.set(name, new_item);
					if (this.manager.db != null) {
						new_item.saveToDB(this.manager.db, null, false);
					}
					continue;
				}
				
				// Same item - copy DB fields to preserve them, then update only changed fields
				old_item.copy_db_fields_to(new_item);
				if (this.manager.db != null) {
					old_item.saveToDB(this.manager.db, new_item, false);
				}
				// Ensure it's in children list
				this.children.append(old_item);
				
			}
			
			// Third pass: Check for removed items
			var seen_names = new Gee.HashSet<string>();
			foreach (var new_item in new_items) {
				seen_names.add(GLib.Path.get_basename(new_item.path));
			}
			foreach (var old_child in old_children) {
				var name = GLib.Path.get_basename(old_child.path);
				if (seen_names.contains(name)) {
					continue; // Still exists
				}
				// Remove from children and DB
				this.children.remove(old_child);
				if (this.manager.db != null) {
					old_child.removeFromDB(this.manager.db);
				}
			}
			
			// Backup database after all changes
			if (this.manager.db != null) {
				this.manager.db.backupDB();
			}
			
			yield enumerator.close_async(GLib.Priority.DEFAULT, null);
			
			// If recurse is true, recursively read all subdirectories
			if (recurse) {
				foreach (var child in this.children.items) {
					if (child is Folder) {
						yield ((Folder)child).read_dir(check_time, true);
					}
				}
			}
		}
		
		/**
		 * Load project files from database.
		 * 
		 * This method performs a three-step process:
		 * a) Load files/folders/aliases from DB, creating appropriate objects and an id=>FileBase map
		 * b) Recursively load any aliased data until no more data is available
		 * c) Build the tree structure by adding children to parents based on parent_id
		 * 
		 * @param db The database instance to load from
		 */
		public void load_files_from_db(SQ.Database db)
		{
			if (this.id <= 0) {
				return;
			}
			
			// Step a: Create id => FileBase map
			var id_map = new Gee.HashMap<int64, FileBase>();
			
			// Step b: Load children starting from project path using while loop
			string[] paths = { this.path };
			string[] seen_ids = { this.id.to_string() };
			while (paths.length > 0) {
				paths = this.load_children(db, id_map, paths, ref seen_ids);
			}
			
			// Step c: Build the tree structure
			this.build_tree_structure(id_map);
		}
		
		/**
		 * Load children using path-based queries, following symlinks via target_path.
		 * 
		 * @param db The database instance
		 * @param id_map The id => FileBase map to update
		 * @param paths Array of paths to search under
		 * @param seen_ids Array of IDs we've already loaded (modified inline)
		 * @return Array of next paths to search, or empty array if done
		 */
		private string[] load_children(
			SQ.Database db, 
			Gee.HashMap<int64, FileBase> id_map,
			string[] paths,
			ref string[] seen_ids)
		{
			// Build path conditions using instr() to check if path column starts with path + "/"
			// or if path exactly matches (for files that are the path itself)
			// SQLite instr() syntax: instr(haystack, needle) - we want instr(path, 'prefix/') = 1
			string[] path_conds = {};
			foreach (var path in paths) {
				var escaped_path = path.replace("'", "''");
				path_conds += "(instr(path, '" + 
					escaped_path + "/') = 1 OR path = '" + 
					escaped_path + "')";
			}
			
			// Load files matching the path conditions
			var query = FileBase.query(db);
			var new_files = new Gee.ArrayList<FileBase>();
			query.selectQuery("WHERE (" + 
				string.joinv(" OR ", path_conds) + ") AND id NOT IN (" + 
				string.joinv(", ", seen_ids) + ")", new_files);
			
			// If no new files found, we're done
			if (new_files.size == 0) {
				return {};
			}
			
			// Build id map and seen_ids (first pass)
			
			foreach (var file_base in new_files) {
				id_map.set(file_base.id, file_base);
				seen_ids += file_base.id.to_string();
			
			}
			string[] next_paths = {};
			
			// Second pass: fill in parent references and set aliased files
			foreach (var file_base in new_files) {
				// Fill in parent reference if available
				if (file_base.parent_id > 0 && id_map.has_key(file_base.parent_id)) {
					file_base.parent = id_map.get(file_base.parent_id) as Folder;
				}
				
				
				// Use target_path to follow symlinks/aliases
				if (file_base.target_path == "") {
					continue;
				}

				if (file_base.points_to_id > 0 && id_map.has_key(file_base.points_to_id)) {
					file_base.points_to = id_map.get(file_base.points_to_id);
				}

				if (file_base.path in next_paths) {
					continue;
				}
				
				// do we already have it?
				if (id_map.has_key(file_base.target_id)) {
					continue;
				}

				

				next_paths += file_base.target_path;

			}
			
			return next_paths;
		}
		
		/**
		 * Build the tree structure by adding children to parents based on parent_id.
		 * 
		 * @param id_map The id => FileBase map
		 */
		private void build_tree_structure(Gee.HashMap<int64, FileBase> id_map)
		{
			foreach (var file_base in id_map.values) {
				// Set points_to reference for aliases first
				if (file_base.points_to_id > 0 && file_base.points_to == null) {
					// i dont think points to id will ever be not available...
					file_base.points_to = id_map.get(file_base.points_to_id);
				}
				if (file_base.parent != null) {
					continue;
				}
				// Set parent reference
				if (file_base.parent_id < 1 || !id_map.has_key(file_base.parent_id)) {
					continue;
				}
				
				file_base.parent = id_map.get(file_base.parent_id) as Folder;
				
				// Add to parent's children (append handles duplicates)
				file_base.parent.children.append(file_base);
			}
		}
	}
}
