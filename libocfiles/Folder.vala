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
	 * Represents a directory/folder in the project.
	 * 
	 * Can also represent a project when is_project = true. Projects are folders with
	 * is_project = true (no separate Project class).
	 * 
	 * == Project Management ==
	 * 
	 * The project_files property provides a flat list of all files in the project (for
	 * dropdowns/search), while the children property provides the hierarchical tree
	 * structure (for tree views).
	 * 
	 * == Git Integration ==
	 * 
	 * Automatically discovers git repositories and checks if paths are ignored by git.
	 * Uses manager.git_provider for git operations.
	 */
	public class Folder : FileBase
	{
		/**
		 * Whether to use background (idle callback) processing for recursive folder scanning.
		 * Default: true (use background processing for better UI responsiveness)
		 */
		public static bool background_recurse { get; set; default = true; }
		
		/**
		 * Constructor.
		 * 
		 * @param manager The ProjectManager instance (required)
		 */
		public Folder(ProjectManager manager)
		{
			base(manager);
			this.base_type = "d";
			// Initialize review_files when project_files is set
			this.review_files = new ReviewFiles(this.project_files);
		}
		
		/**
		 * Named constructor: Create a Folder from FileInfo.
		 * 
		 * @param parent The parent Folder (required)
		 * @param info The FileInfo object from directory enumeration
		 * @param path The full path to the folder
		 */
		public Folder.new_from_info(
			ProjectManager manager,
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
		 * List of files that need approval (only for projects).
		 * Initialized in constructor when is_project is true.
		 */
		public ReviewFiles review_files { get; private set; }
		
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
		 * Check if a path is ignored by git.
		 * 
		 * @param path The full path to check
		 * @return true if the path is ignored, false otherwise
		 */
		private bool check_path_ignored(string path)
		{
			// If parent is already ignored, child is also ignored
			if (this.is_ignored) {
				return true;
			}
			
			// Check if repository exists
			if (!this.manager.git_provider.repository_exists(this)) {
				return false;
			}
			
			var workdir_path = this.manager.git_provider.get_workdir_path(this);
			if (workdir_path == null || !path.has_prefix(workdir_path)) {
				return false;
			}
			
			// Get relative path from repository workdir
			var relative_path = path.substring(workdir_path.length);
			// Remove leading slash if present
			if (relative_path.has_prefix("/")) {
				relative_path = relative_path.substring(1);
			}
			
			// Check if path is ignored using provider
			return this.manager.git_provider.path_is_ignored(this, relative_path);
		}
		
		/**
		 * Discover and open git repository for this folder.
		 * Checks if folder is a git repository and opens it if found.
		 */
		private void discover_repository()
		{
			// If already ignored, no need to discover repository
			if (this.is_ignored) {
				// Reset repo status when ignored (we don't care about repo status for ignored folders)
				this.is_repo = -1;
				return;
			}
			
			switch (this.is_repo) {
				case 0:
					// Already checked and not a repo
					return;
				
				case 1:
					// Already checked and is a repo
					if (this.manager.git_provider.repository_exists(this)) {
						// Check if .git directory still exists
						var git_dir = GLib.File.new_for_path(GLib.Path.build_filename(this.path, ".git"));
						if (git_dir.query_exists()) {
							// .git exists, we're all good
							return;
						}
					}
					// repo is null or .git doesn't exist, fall through to rediscover
					break;
				
				default: // -1 (not checked)
					break;
			}
			
			// Try to discover repository from this folder (for case 1 when repo is null/.git missing, or default -1)
			this.manager.git_provider.discover_repository(this);
			
			// Update is_repo based on whether repository exists
			this.is_repo = this.manager.git_provider.repository_exists(this) ? 1 : 0;
		}
		
		
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
			GLib.debug("Folder.read_dir: Starting scan for path='%s', is_project=%s, check_time=%lld, recurse=%s, last_check_time=%lld", 
				this.path, this.is_project.to_string(), check_time, recurse.to_string(), this.last_check_time);
			
			// If this folder was already checked in this scan, skip it
			if (this.last_check_time == check_time) {
				GLib.debug("Folder.read_dir: Already checked in this scan (check_time=%lld), skipping path='%s'", 
					check_time, this.path);
				return;
			}
			
			// Mark this folder as checked
			this.last_check_time = check_time;
			
			// Check if folder contains .generated file - if so, ignore this folder and all children
			var generated_path = GLib.Path.build_filename(this.path, ".generated");
			if (GLib.FileUtils.test(generated_path, GLib.FileTest.EXISTS)) {
				this.is_ignored = true;
				// Reset repo status when ignored (we don't care about repo status for ignored folders)
				this.is_repo = -1;
				// Don't need to discover repository or scan children if folder is ignored
 			}
			
			// Discover repository for this folder
			this.discover_repository();
			
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
				yield this.read_dir_update(new_item, old_child_map);
			}
			this.read_dir_remove(new_items, old_children);
			
			// If not recursing, do backup and return early
			if (!recurse) {
				this.manager.db.backupDB();
				return;
			}
			

			// Collect all folders that need recursive reading (skip ignored folders)
			var folders_to_process = new Gee.ArrayList<Folder>();
			foreach (var child in this.children.items) {
				if (child.is_ignored) {
					continue;
				}
				
				if (child is Folder) {
					folders_to_process.add((Folder)child);
					continue;
				}
				if (!(child is FileAlias && child.points_to is Folder)) {
					continue;
				}
				var target_folder = (Folder)child.points_to;
				if (target_folder.is_ignored) {
					continue;
				}
				folders_to_process.add(target_folder);
			}

			if (!background_recurse) {
				// Process folders synchronously using yield
				foreach (var folder in folders_to_process) {
					yield folder.read_dir(check_time, true);
				}
				// All folders processed
				this.manager.db.backupDB();
				if (this.is_project) {
					this.project_files.update_from(this);
				}
				this.review_files.refresh();
				return;
			} 
				// Start processing folders in idle callback (non-blocking)
			Idle.add(() => {
				this.process_folders(folders_to_process, check_time);
				return false;
			});

		}
		
		/**
		 * Process one folder from the queue and schedule the next one.
		 * 
		 * @param folders_to_process Queue of folders to process recursively
		 * @param check_time Timestamp for this check operation
		 */
		private void process_folders(Gee.ArrayList<Folder> folders_to_process, int64 check_time)
		{
			if (folders_to_process.size == 0) {
				// All folders processed, do final operations
				this.manager.db.backupDB();
				if (this.is_project) {
					this.project_files.update_from(this);
				}
				this.review_files.refresh();
				return;
			}
			
			// Get next folder to process
			var folder = folders_to_process.remove_at(0);
			
			// Call read_dir asynchronously without yield
			folder.read_dir.begin(check_time, true, (obj, res) => {
				try {
					folder.read_dir.end(res);
				} catch (Error e) {
					GLib.warning("Error reading directory: %s", e.message);
				}
				
				if (!background_recurse) {
					this.process_folders(folders_to_process, check_time);
					return;
				} 
					// Start processing folders in idle callback (non-blocking)
				Idle.add(() => {
					this.process_folders(folders_to_process, check_time);
					return false;
				});
			});
		}
		
		/**
		 * Enumerate directory contents and create FileBase objects for all items found.
		 * 
		 * @param dir The GLib.File object for the directory to enumerate
		 * @param new_items List to populate with newly created FileBase objects
		 * @throws Error if directory enumeration fails
		 */
		public void enumerate_directory_contents(GLib.File dir, Gee.ArrayList<FileBase> new_items) throws Error
		{
			// Execute directory enumeration
			var enumerator = dir.enumerate_children(
				GLib.FileAttribute.STANDARD_NAME + "," + 
					GLib.FileAttribute.STANDARD_TYPE + "," +
					GLib.FileAttribute.STANDARD_IS_SYMLINK + "," +
					GLib.FileAttribute.STANDARD_SYMLINK_TARGET + "," +
					GLib.FileAttribute.STANDARD_CONTENT_TYPE,
				GLib.FileQueryInfoFlags.NONE,
				null
			);
			
			GLib.FileInfo? info;
			while ((info = enumerator.next_file(null)) != null) {
				var name = info.get_name();
				
				// Skip "." and ".." entries explicitly (shouldn't appear, but be safe)
				if (name == "." || name == "..") {
					continue;
				}
				
				// Skip .git directories and other hidden/system folders
				if (name == ".git") {
					continue;
				}
				
				var cpath = GLib.Path.build_filename(this.path, name);
				
				// Check if this file/folder is ignored
				
				if (info.get_is_symlink()) {
					new_items.add(new FileAlias.new_from_info(this, info, cpath) {
						is_ignored = this.check_path_ignored(cpath)
					});
					continue;
				}
				
				if (info.get_file_type() == GLib.FileType.DIRECTORY) {
					var is_ignored_flag = this.check_path_ignored(cpath);
					var new_folder = new Folder.new_from_info( this.manager, this, info, cpath) {
						is_ignored = is_ignored_flag,
						is_repo = is_ignored_flag ? -1 : this.is_repo
					};
					new_items.add(new_folder);
					continue;
				}
				
				new_items.add(new File.new_from_info( this.manager, this, info, cpath) {
					is_ignored = this.check_path_ignored(cpath)
				});
			}
			
			enumerator.close(null);
		}
		
		/**
		 * Scan directory and create FileBase objects for all items found.
		 * 
		 * When background_recurse is false, this executes synchronously on the main thread.
		 * When background_recurse is true, this executes in a background thread to avoid
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
			
			var new_items = new Gee.ArrayList<FileBase>();
			
			// If background_recurse is false, execute synchronously
			if (!background_recurse) {
				this.enumerate_directory_contents(dir, new_items);
				return new_items;
			}
			
			// Otherwise, execute in background thread
			SourceFunc callback = read_dir_scan.callback;
			Error? thread_error = null;
			
			// Hold reference to closure to keep it from being freed whilst thread is active
			ThreadFunc<bool> run = () => {
				try {
					this.enumerate_directory_contents(dir, new_items);
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
		private async void read_dir_update(
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
						yield ((Folder)new_item.points_to).load_files_from_db();
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
		 * Timestamp of last database load (in-memory only, not stored in database).
		 * Used to determine if we need to reload from database.
		 */
		private int64 last_db_load = 0;
		
		/**
		 * Check if this folder needs to be reloaded from the database.
		 * 
		 * Compares the project's last_db_load timestamp with the maximum last_modified
		 * timestamp in the database. If any file in the database has been modified
		 * more recently than the last load, a reload is needed.
		 * 
		 * @return true if reload is needed, false otherwise
		 */
		private bool needs_reload()
		{
			if (this.manager.db == null) {
				return false; // No DB, can't check
			}
			
			// If last_db_load is 0, we've never loaded - always reload
			if (this.last_db_load == 0) {
				return true;
			}
			
			// Query: SELECT MAX(last_modified) FROM filebase
			var query = FileBase.query(this.manager.db, this.manager);
			var stmt = query.selectPrepare("SELECT MAX(last_modified) FROM filebase");
			var results = query.fetchAllInt64(stmt);
			
			int64 max_mtime = 0;
			if (results.size > 0) {
				max_mtime = results.get(0);
			}
			
			// If max mtime in DB is greater than last_db_load, reload needed
			return max_mtime > this.last_db_load;
		}

		/**
		 * Load project files from database.
		* 
		* This method performs a three-step process:
		* a) Load files/folders/aliases from DB, creating appropriate objects and an id=>FileBase map
		* b) Recursively load any aliased data until no more data is available
		* c) Build the tree structure by adding children to parents based on parent_id
		*/
		public async void load_files_from_db()
		{
			if (this.id <= 0 || this.manager.db == null) {
				GLib.debug("Folder.load_files_from_db: Skipping (id=%lld or db=null)", this.id);
				return;
			}
			
			// Check if reload is needed (optimization: skip if database hasn't changed)
			if (!this.needs_reload()) {
				GLib.debug("Folder.load_files_from_db: Skipping reload (no changes detected) for '%s'", this.path);
				return;
			}
			
			// Step a: Create id => FileBase map and add self (root folder) to it
			var id_map = new Gee.HashMap<int, FileBase>();
			id_map.set((int)this.id, this);
			GLib.debug("Folder.load_files_from_db: Starting for '%s' (id=%lld)", this.path, this.id);
			
		// Step b: Load children starting from project path using while loop
			string[] paths = { this.path };
			var seen_ids = new Gee.ArrayList<string>();
			seen_ids.add(this.id.to_string());
			int iteration = 0;
			while (paths.length > 0) {
				iteration++;
				GLib.debug("Folder.load_files_from_db: Iteration %d, loading %d paths", iteration, paths.length);
				paths = yield this.load_children(id_map, paths, seen_ids);
				GLib.debug("Folder.load_files_from_db: After iteration %d, id_map has %d items, next_paths=%d", iteration, id_map.size, paths.length);
			}
			
			GLib.debug("Folder.load_files_from_db: Loaded %d items total, building tree structure", id_map.size);
			// Step c: Build the tree structure
			// Skip the root folder itself (it's already in the tree, doesn't need to be added to a parent)
			foreach (var file_base in id_map.values) {
				// Root folder (this) doesn't need tree building - it's already the root
				if (file_base.id == this.id) {
					continue;
				}
				this.build_tree_structure(file_base, id_map);
			}
			
			// Populate project_files from children
			this.project_files.update_from(this);
			
			// Refresh review_files
			this.review_files.refresh();
			
			// Update last_db_load timestamp to current time
			this.last_db_load = new GLib.DateTime.now_local().to_unix();
		}
		
	/**
	 * Load children using path-based queries, following symlinks via target_path.
	 * 
	 * @param id_map The id => FileBase map to update
	 * @param paths Array of paths to search under
	 * @param seen_ids ArrayList of IDs we've already loaded (modified inline)
	 * @return Array of next paths to search, or empty array if done
	 */
	private async string[] load_children(
		Gee.HashMap<int, FileBase> id_map,
		string[] paths,
		Gee.ArrayList<string> seen_ids)
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
			yield query.select_async("WHERE (" + 
				string.joinv(" OR ", path_conds) + ") AND id NOT IN (" + 
				string.joinv(", ", seen_ids.to_array()) + ") AND delete_id = 0", new_files);
				
			// If no new files found, we're done
			if (new_files.size == 0) {
				return {};
			}
			
		// Build id map and seen_ids (first pass)
		
			foreach (var file_base in new_files) {
				id_map.set((int)file_base.id, file_base);
				seen_ids.add(file_base.id.to_string());
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
			
			// Get or set parent reference
 			if (file_base.parent != null) {
				file_base.parent.children.append(file_base);
				return;
			} 
			// Set parent reference if not already set
			if (file_base.parent_id < 1 || !id_map.has_key((int)file_base.parent_id)) {
				return;
			}
				
			var	parent = id_map.get((int)file_base.parent_id) as Folder;
			if (parent == null) {
				return;
			}
				
			file_base.parent = parent;
			
			// Add to parent's children (append handles duplicates)
			parent.children.append(file_base);
		}
		
		/**
		 * Creates child folders recursively until reaching the target file path.
		 * 
		 * Starting from this folder, creates any missing intermediate folders
		 * needed to reach the parent directory of the target file path. Returns
		 * the final folder (the parent directory of the file).
		 * 
		 * @param file_path The target file path
		 * @return The Folder object for the parent directory of the file, or null on error
		 */
		public async Folder? make_children(string file_path) throws Error
		{
			// Get the parent directory of the file
			var target_dir = GLib.Path.get_dirname(file_path);
			
			// If target_dir is this folder's path, return this folder
			if (target_dir == this.path) {
				return this;
			}
			
			// Check if target_dir is within this folder
			if (!target_dir.has_prefix(this.path)) {
				GLib.warning("Folder.make_children: Target path %s is not within folder %s", target_dir, this.path);
				return null;
			}
			
			// Get relative path from this folder to target directory
			var relative_path = target_dir.substring(this.path.length);
			if (relative_path.has_prefix("/")) {
				relative_path = relative_path.substring(1);
			}
			if (relative_path == "") {
				return this;
			}
			
			// Get the first component of the relative path
			var components = relative_path.split("/");
			var first_component = components[0];
			if (first_component == "") {
				return this;
			}
			
			// Check if folder exists in children
			Folder? child_folder = null;
			if (this.children.child_map.has_key(first_component)) {
				var child = this.children.child_map.get(first_component);
				if (child is Folder) {
					child_folder = child as Folder;
				}
			}
			
			// If folder exists, recursively call make_children on it
			if (child_folder != null) {
				return yield child_folder.make_children(file_path);
			}
			
			// Folder doesn't exist, create it
			var child_path = GLib.Path.build_filename(this.path, first_component);
			
			// Query folder info from disk
			var gfile = GLib.File.new_for_path(child_path);
			if (!gfile.query_exists()) {
				GLib.warning("Folder.make_children: Folder does not exist on disk: %s", child_path);
				return null;
			}
			
			GLib.FileInfo folder_info;
			try {
				folder_info = gfile.query_info(
					GLib.FileAttribute.TIME_MODIFIED,
					GLib.FileQueryInfoFlags.NONE,
					null
				);
			} catch (GLib.Error e) {
				GLib.warning("Folder.make_children: Could not query folder info for %s: %s", child_path, e.message);
				return null;
			}
			
			// Create new folder
			child_folder = new Folder.new_from_info(
				this.manager,
				this,
				folder_info,
				child_path
			);
			
			// Add to parent's children
			this.children.append(child_folder);
			
			// Add to project's folder_map if this is a project folder
			var project_root = this.is_project ? this : this.find_project_root();
			if (project_root != null && project_root.project_files != null) {
				project_root.project_files.folder_map.set(child_folder.path, child_folder);
			}
			
			// Save to DB (this will also add to file_cache automatically)
			if (this.manager.db != null) {
				child_folder.saveToDB(this.manager.db, null, false);
			} else {
				// If no DB, manually add to file_cache for immediate lookup
				this.manager.file_cache.set(child_folder.path, child_folder);
			}
			
			// Recursively call make_children on the newly created child folder
			return yield child_folder.make_children(file_path);
		}
		
		/**
		 * Finds the project root folder by walking up the parent chain.
		 * 
		 * @return The project root folder, or null if not found
		 */
		private Folder? find_project_root()
		{
			var current = this;
			while (current != null) {
				if (current.is_project) {
					return current;
				}
				current = current.parent;
			}
			return null;
		}
		
		/**
		 * Clears all in-memory data for this folder to free memory.
		 * 
		 * This method:
		 * - Clears the hierarchical tree structure (children)
		 * - Clears the flat file list (project_files)
		 * - Clears the in-memory tree structure
		 * 
		 * After calling this method, the folder will appear as if it has never been
		 * loaded. The next call to load_files_from_db() will reload all data from the
		 * database (since needs_reload() will return true).
		 * 
		 * This is useful for memory management when switching between projects or
		 * when you want to force a reload on the next access.
		 * 
		 * Note: This does NOT update the database - it only clears in-memory state.
		 */
		public void clear_data()
		{
			// Clear hierarchical tree structure
			this.children.remove_all();
			
			// Clear flat file list (for projects)
			this.project_files.remove_all();
			
			// Reset last_db_load so that needs_reload() will return true on next access
			this.last_db_load = 0;
		}
		
		/**
		 * Refresh review_files list.
		 * 
		 * Wrapper method that calls review_files.refresh().
		 * Only works for projects (folders with is_project = true).
		 */
		public void refresh_review()
		{
			if (!this.is_project) {
				return;
			}
			this.review_files.refresh();
		}
		
		/**
		 * Build list of root directories that need write access for bubblewrap sandboxing.
		 * 
		 * Returns an ArrayList of Folder objects that need to be writable in the sandbox. Follows symlinks
		 * within the project to find all directories that need write access. For Phase 1,
		 * returns folders with realpaths (actual filesystem paths with symlinks resolved). In later phases,
		 * will return folders with overlay mount points instead of realpaths.
		 * 
		 * Algorithm:
		 * 1. Collect all Folder objects from project_files.folder_map (paths are already realpaths)
		 * 2. Sort folders by path
		 * 3. Add first folder, then iterate through and add if next folder doesn't start with last added (this avoids duplicates where one folder is a parent of another)
		 * 
		 * @return ArrayList of Folder objects that need write access
		 */
		public Gee.ArrayList<Folder> build_roots() throws Error
		{
			var folders = new Gee.ArrayList<Folder>();
			
			// Add project root itself
			folders.add(this);
			
			// Get all Folder objects from project_files.folder_map (paths are already realpaths)
			foreach (var folder in this.project_files.folder_map.values) {
				// Only add if not already in list
				if (!folders.contains(folder)) {
					folders.add(folder);
				}
			}
			
			// Sort folders by path
			folders.sort((a, b) => {
				return strcmp(a.path, b.path);
			});
			
			// Apply algorithm: add first folder, then iterate and add if next doesn't start with last added
			var distinct_roots = new Gee.ArrayList<Folder>();
			// Add first folder
			distinct_roots.add(folders.get(0));
			
			// Iterate through remaining folders
			for (int i = 1; i < folders.size; i++) {
				// If current folder path starts with last added folder path (plus "/"), skip it (it's a subdirectory)
				if (folders.get(i).path.has_prefix(distinct_roots.get(distinct_roots.size - 1).path + "/")) {
					continue;
				}
				distinct_roots.add(folders.get(i));
			}
			
			return distinct_roots;
		}
	}
}
