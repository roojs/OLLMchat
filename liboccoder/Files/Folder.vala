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
			OLLMcoder.ProjectManager manager,
			Folder? parent,
			GLib.FileInfo info,
			string path)
		{
			base(manager);
			this.base_type = "d";
			this.path = path;
			if (parent != null) {
				this.parent = parent;
				this.parent_id = parent.id;
			}
			
			// Set last_modified from FileInfo
			var mod_time = info.get_modification_date_time();
			if (mod_time != null) {
				this.last_modified = mod_time.to_unix();
			}
		}
		
		
			
		/**
		 * ListStore of all files in project (used by dropdowns).
		 */
		public ProjectFiles project_files { get; set; default = new ProjectFiles(); }
		
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
			
			// Keep a copy of old children to detect removals
			var old_children = new Gee.ArrayList<FileBase>();
			foreach (var child in this.children.items) {
				old_children.add(child);
			}
			var old_child_map = new Gee.HashMap<string, FileBase>();
			foreach (var entry in this.children.child_map.entries) {
				old_child_map.set(entry.key, entry.value);
			}
			
			var new_items = yield this.read_dir_scan();
			foreach (var new_item in new_items) {
				this.read_dir_update(new_item, old_child_map);
			}
			this.read_dir_remove(new_items, old_children);
			
			// If not recursing, do backup and return early
			if (!recurse) {
				this.manager.db.backupDB();
				return;
			}
			
			// Collect all folders that need recursive reading
			var folders_to_process = new Gee.ArrayList<Folder>();
			foreach (var child in this.children.items) {
				if (child is Folder) {
					folders_to_process.add((Folder)child);
				}
				if (child is FileAlias && child.points_to is Folder) {
					folders_to_process.add((Folder)child.points_to);
				}
			}
			
			// If no folders to process, do backup and update_from immediately
			if (folders_to_process.size == 0) {
				this.manager.db.backupDB();
				if (this.is_project) {
					this.project_files.update_from(this);
				}
				return;
			}
			
			// Process folders in idle callbacks
			var folder_queue = folders_to_process;
			var processed_count = 0;
			var total_count = folder_queue.size;
			var is_project = this.is_project;
			var manager = this.manager;
			var project_files = this.project_files;
			
			// Process one folder per idle callback
			Idle.add(() => {
				if (folder_queue.size == 0) {
					// All folders processed, do final operations
					manager.db.backupDB();
					if (is_project) {
						project_files.update_from(this);
					}
					return false; // Don't reschedule
				}
				
				// Get next folder to process
				var folder = folder_queue.remove_at(0);
				
				// Call read_dir asynchronously without yield
				folder.read_dir.begin(check_time, true, (obj, res) => {
					try {
						folder.read_dir.end(res);
						processed_count++;
						
						// Schedule next idle callback to process next folder
						if (folder_queue.size > 0) {
							Idle.add(() => {
								if (folder_queue.size == 0) {
									// All folders processed, do final operations
									manager.db.backupDB();
									if (is_project) {
										project_files.update_from(this);
									}
									return false; // Don't reschedule
								}
								
								// Get next folder to process
								var next_folder = folder_queue.remove_at(0);
								
								// Call read_dir asynchronously
								next_folder.read_dir.begin(check_time, true, (obj2, res2) => {
									try {
										next_folder.read_dir.end(res2);
										processed_count++;
										
										// Continue processing if more folders remain
										if (folder_queue.size > 0) {
											Idle.add(() => {
												// Recursive pattern - process next folder
												if (folder_queue.size == 0) {
													manager.db.backupDB();
													if (is_project) {
														project_files.update_from(this);
													}
													return false;
												}
												
												var f = folder_queue.remove_at(0);
												f.read_dir.begin(check_time, true, (obj3, res3) => {
													try {
														f.read_dir.end(res3);
														processed_count++;
													} catch (Error e) {
														GLib.warning("Error reading directory: %s", e.message);
													}
													
													// Schedule next iteration
													if (folder_queue.size > 0) {
														Idle.add(() => {
															// This pattern continues...
															return false;
														});
													} else {
														// All done
														manager.db.backupDB();
														if (is_project) {
															project_files.update_from(this);
														}
													}
												});
												return false;
											});
										} else {
											// All folders processed
											manager.db.backupDB();
											if (is_project) {
												project_files.update_from(this);
											}
										}
									} catch (Error e) {
										GLib.warning("Error reading directory: %s", e.message);
									}
								});
								return false;
							});
						} else {
							// All folders processed
							manager.db.backupDB();
							if (is_project) {
								project_files.update_from(this);
							}
						}
					} catch (Error e) {
						GLib.warning("Error reading directory: %s", e.message);
					}
				});
				
				return false; // Don't reschedule - we'll schedule next one in callback
			});

		}
		
		/**
		 * Scan directory and create FileBase objects for all items found.
		 * 
		 * This method executes directory scanning in a background thread to avoid
		 * blocking the main thread during file system operations.
		 * 
		 * @return List of newly created FileBase objects
		 * @throws Error if directory does not exist or thread creation fails
		 */
		private async Gee.ArrayList<FileBase> read_dir_scan() throws Error, ThreadError
		{
			var dir = GLib.File.new_for_path(this.path);
			if (!dir.query_exists()) {
				throw new GLib.IOError.NOT_FOUND("Directory does not exist: " + this.path);
			}
			
			// Prepare attributes string on main thread (fast operation)
			
			var new_items = new Gee.ArrayList<FileBase>();
			SourceFunc callback = read_dir_scan.callback;
			Error? thread_error = null;
			
			// Hold reference to closure to keep it from being freed whilst thread is active
			ThreadFunc<bool> run = () => {
				try {
					// Execute directory enumeration in background thread (slow operation)
					var enumerator = dir.enumerate_children(
						GLib.FileAttribute.STANDARD_NAME + "," + 
							GLib.FileAttribute.STANDARD_TYPE + "," +
							GLib.FileAttribute.STANDARD_IS_SYMLINK + "," +
							GLib.FileAttribute.STANDARD_SYMLINK_TARGET;,
						GLib.FileQueryInfoFlags.NONE,
						null
					);
					
					GLib.FileInfo? info;
					while ((info = enumerator.next_file(null)) != null) {
						var name = info.get_name();
						
						// Skip .git directories and other hidden/system folders
						if (name == ".git") {
							continue;
						}
						
						var cpath = GLib.Path.build_filename(this.path, name);
						
						if (info.get_is_symlink()) {
							new_items.add(new FileAlias.new_from_info(this, info, cpath));
							continue;
						}
						
						if (info.get_file_type() == GLib.FileType.DIRECTORY) {
							new_items.add(new Folder.new_from_info(
								this.manager, this, info, cpath));
							continue;
						}
						
						new_items.add(new File.new_from_info(
							this.manager, this, info, cpath));
					}
					
					enumerator.close(null);
				} catch (Error e) {
					thread_error = e;
				}
				
				// Schedule callback on main thread
				Idle.add((owned) callback);
				return true;
			};
			
			new Thread<bool>("read-dir-scan", run);
			
			// Wait for background thread to schedule our callback
			yield;
			
			// Re-throw any error that occurred in the thread
			if (thread_error != null) {
				throw thread_error;
			}
			
			return new_items;
		}
		
		/**
		 * Compare a new item with old items and handle updates/inserts.
		 * 
		 * @param new_item The newly scanned FileBase object
		 * @param old_child_map Map of old children by name
		 */
		private void read_dir_update(
			FileBase new_item,
			Gee.HashMap<string, FileBase> old_child_map)
		{
			var name = GLib.Path.get_basename(new_item.path);
			var old_item = old_child_map.get(name);
			
			// we do not need to deal with DB/cache as 
			// we have created the origial data from there.
			if (new_item is FileAlias && new_item.points_to_id > -1 
				&& new_item.points_to != null) {
				
				if (old_item != null && old_item.target_path == new_item.target_path) {
					new_item.points_to = old_item.points_to;
					new_item.points_to_id  = old_item.points_to_id;
				} else if (this.manager.file_cache.has_key(new_item.path)) {
					new_item.points_to = this.manager.file_cache.get(new_item.path);
					new_item.points_to_id = new_item.points_to.id;
					// do we need to do anything?
					// i dont think so - the recursive code should handle it.
				} else {
					// it really does not exist.
					new_item.points_to.saveToDB(this.manager.db, null,false);
					new_item.points_to_id = new_item.points_to.id;
					if (new_item.points_to is Folder) { 
						((Folder)new_item.points_to).load_files_from_db();
					}
				}
			}
				// TODO: Resolve points_to_id for FileAlias objects
			// When a FileAlias has target_path set but points_to_id is 0, query the database
			// to find the target FileBase by target_path and set points_to_id and points_to.
			// Check: old_item, file_cache, then database query by target_path.



			// New item - append and insert into DB
			if (old_item == null) {
				this.children.append(new_item);
				this.children.child_map.set(name, new_item);

				// TODO: If our item is a FileAlias, resolve points_to_id before saving
				// Query database for target by target_path and set points_to_id and points_to

				new_item.saveToDB(this.manager.db, null, false);
				return;
			}
			
			// Old item exists - check if same
			if (!old_item.compare(new_item)) {
				// Totally different - remove old from DB and children
				old_item.removeFromDB(this.manager.db);
				this.children.remove(old_item);
				// Add new item
				this.children.append(new_item);
				this.children.child_map.set(name, new_item);
				new_item.saveToDB(this.manager.db, null, false);
				
				return;
			}
			
			// Same item - copy DB fields to preserve them, then update only changed fields
			old_item.copy_db_fields_to(new_item);
			// database manager has to be set other wise all this will break
			old_item.saveToDB(this.manager.db, new_item, false);
			
			// Ensure it's in children list
			// this will not actually do anything as it's 
			this.children.append(old_item);
		}
		
		/**
		 * Check for removed items and remove them from children and database.
		 * 
		 * @param new_items List of newly scanned FileBase objects
		 * @param old_children List of old children that existed before the scan
		 */
		private void read_dir_remove(
			Gee.ArrayList<FileBase> new_items,
			Gee.ArrayList<FileBase> old_children)
		{
			// Third pass: Check for removed items
			var seen_names = new Gee.HashSet<string>();
			foreach (var new_item in new_items) {
				seen_names.add(GLib.Path.get_basename(new_item.path));
			}
			foreach (var old_child in old_children) {
				if (seen_names.contains(GLib.Path.get_basename(old_child.path))) {
					continue; // Still exists
				}
				// Remove from children and DB
				this.children.remove(old_child);
				old_child.removeFromDB(this.manager.db);
			}
		}
		
		/**
		 * Load project files from database.
		* 
		* This method performs a three-step process:
		* a) Load files/folders/aliases from DB, creating appropriate objects and an id=>FileBase map
		* b) Recursively load any aliased data until no more data is available
		* c) Build the tree structure by adding children to parents based on parent_id
		*/
		public void load_files_from_db()
		{
			if (this.id <= 0 || this.manager.db == null) {
				return;
			}
			
			// Step a: Create id => FileBase map
			var id_map = new Gee.HashMap<int, FileBase>();
			
			// Step b: Load children starting from project path using while loop
			string[] paths = { this.path };
			string[] seen_ids = { this.id.to_string() };
			while (paths.length > 0) {
				paths = this.load_children(id_map, paths, ref seen_ids);
			}
			
			// Step c: Build the tree structure
			foreach (var file_base in id_map.values) {
				this.build_tree_structure(file_base, id_map);
			}
		}
		
		/**
		 * Load children using path-based queries, following symlinks via target_path.
		 * 
		 * @param id_map The id => FileBase map to update
		 * @param paths Array of paths to search under
		 * @param seen_ids Array of IDs we've already loaded (modified inline)
		 * @return Array of next paths to search, or empty array if done
		 */
		private string[] load_children(
			Gee.HashMap<int, FileBase> id_map,
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
			var query = FileBase.query(this.manager.db, this.manager);
			var new_files = new Gee.ArrayList<FileBase>();
			query.selectQuery("SELECT * FROM filebase WHERE (" + 
				string.joinv(" OR ", path_conds) + ") AND id NOT IN (" + 
				string.joinv(", ", seen_ids) + ")", new_files);
			
			// If no new files found, we're done
			if (new_files.size == 0) {
				return {};
			}
			
			// Build id map and seen_ids (first pass)
			
			foreach (var file_base in new_files) {
				id_map.set((int)file_base.id, file_base);
				var new_seen_ids = new string[seen_ids.length + 1];
				for (int i = 0; i < seen_ids.length; i++) {
					new_seen_ids[i] = seen_ids[i];
				}
				new_seen_ids[seen_ids.length] = file_base.id.to_string();
				seen_ids = new_seen_ids;
			}
			string[] next_paths = {};
			
			// Second pass: fill in parent references and set aliased files
			foreach (var file_base in new_files) {
				// Fill in parent reference if available
				if (file_base.parent_id > 0 && id_map.has_key((int)file_base.parent_id)) {
					file_base.parent = id_map.get((int)file_base.parent_id) as Folder;
				}
				
				
				// Use target_path to follow symlinks/aliases
				if (file_base.target_path == "") {
					continue;
				}

				if (file_base.points_to_id > 0 && id_map.has_key((int)file_base.points_to_id)) {
					file_base.points_to = id_map.get((int)file_base.points_to_id);
				}

				if (file_base.path in next_paths) {
					continue;
				}
				
				// do we already have it?
				if (id_map.has_key((int)file_base.points_to_id)) {
					continue;
				}

				

				next_paths += file_base.target_path;

			}
			
			return next_paths;
		}
		
		/**
		 * Build the tree structure for a single file_base by adding it to its parent's children.
		 * 
		 * @param file_base The FileBase object to process
		 * @param id_map The id => FileBase map for resolving references
		 */
		private void build_tree_structure(FileBase file_base, 
			Gee.HashMap<int, FileBase> id_map)
		{
			// Set points_to reference for aliases first
			if (file_base.points_to_id > 0 && file_base.points_to == null) {
				// i dont think points to id will ever be not available...
				file_base.points_to = id_map.get((int)file_base.points_to_id);
			}
			if (file_base.parent != null) {
				return;
			}
			// Set parent reference
			if (file_base.parent_id < 1 || !id_map.has_key((int)file_base.parent_id)) {
				return;
			}
			
			file_base.parent = id_map.get((int)file_base.parent_id) as Folder;
			
			// Add to parent's children (append handles duplicates)
			file_base.parent.children.append(file_base);
		}
	}
}
