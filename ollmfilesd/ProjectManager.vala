/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
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

namespace OLLMfilesd
{
	/**
	 * Central coordinator for all file system operations.
	 * 
	 * ProjectManager is the entry point for all file system operations. It manages
	 * file cache, tracks active project and active file, provides buffer and git
	 * providers, handles database persistence, and emits signals for state changes.
	 * 
	 * The file_cache provides O(1) lookup by path. Projects are folders with
	 * is_project = true (no separate Project class). Database operations are optional
	 * (can work without database).
	 */
	public class ProjectManager : Object
	{
		/**
		 * Provider instances (default to base class with no-op implementations).
		 */
		public BufferProviderBase buffer_provider { get; set; default = new BufferProviderBase(); }
		public GitProviderBase git_provider { get; set; default = new GitProviderBase(); }
		
		/**
		 * Database instance for persistence.
		 * Set this to enable database operations.
		 */
		public SQ.Database? db { get; set; default = null; }
		
		public Gee.HashMap<string,FileBase> file_cache {
			get; set;
			default = new Gee.HashMap<string,FileBase>(); 
		}
		
		/**
		 * Cache of Tree instances for AST path lookup.
		 * Maps file path to Tree instance.
		 */
		public Gee.HashMap<string,Tree> tree_cache {
			get; private set;
			default = new Gee.HashMap<string,Tree>(); 
		}
		
		/**
		 * List of all projects (folders where is_project = true).
		 */
		public ProjectList projects { get; private set;
			default = new ProjectList(); }
		
		/**
		 * Folder paths currently inside a {@link Folder.read_dir} pass (main thread only).
		 * Callers add/remove entries; replace the map to clear.
		 * {@link Gee.HashMap.unset} on a missing key is safe (returns false, does not throw).
		 */
		public Gee.HashMap<string, Folder> scanning {
			get; set;
			default = new Gee.HashMap<string, Folder> ();
		}
		
		/**
		 * Currently active project (folder with is_project = true).
		 */
		public Folder? active_project { get; private set; default = null; }
		
		/**
		 * Currently active file.
		 */
		public File? active_file { get; private set; default = null; }
		
		/**
		 * Emitted when active file changes.
		 */
		public signal void active_file_changed(File? file);
		
		/**
		 * Emitted when active project changes.
		 * Note: Projects are Folders with is_project = true.
		 */
		public signal void active_project_changed(Folder? project);
		
		/**
		 * Emitted when file metadata changes (cursor, scroll, last_viewed, etc.).
		 * This signal is emitted for metadata-only updates that don't require background scanning.
		 */
		public signal void file_metadata_changed(File file);
		
		/**
		 * Emitted when file content changes (saved, edited, etc.).
		 * This signal is emitted when file content is written to disk and triggers background scanning.
		 */
		public signal void file_contents_changed(File file);

		public signal void rpc_load_projects_from_db(OLLMrpc.Request request);
		public signal void rpc_create_project(OLLMrpc.Request request);
		public signal void rpc_remove_project(OLLMrpc.Request request);
		public signal void rpc_activate_project(OLLMrpc.Request request);
		
		/**
		 * DeleteManager instance for handling file deletions.
		 */
		public DeleteManager delete_manager { get; private set; }

		/**
		 * When true, {@link activate_project} skips the initial directory scan (read_dir).
		 * Off by default. Once the scan is skipped, this is set to true so it stays disabled.
		 * Use for tests or lightweight setups that rely on DB state only.
		 */
		public bool disable_initial_scan { get; set; default = false; }
		
		/**
		 * Constructor.
		 * 
		 * @param db Optional database instance for persistence
		 */
		public ProjectManager(SQ.Database? db = null)
		{
			this.db = db;
			if (this.db != null) {
				// Initialize database tables
				FileBase.init_db(this.db);
				FileHistory.init_db(this.db);
			}
			// Initialize git provider if set
			this.git_provider.initialize();
			
			// Create DeleteManager instance
			this.delete_manager = new DeleteManager(this);
		}

		construct
		{
			this.rpc_load_projects_from_db.connect((request) => {
				this.load_projects_from_db.begin(request);
			});
			this.rpc_create_project.connect((request) => {
				var project = this.create_project(
					((CallParam) request.param).path
				);
				request.session.reply(request, new OLLMrpc.Response(request.id) {
					result = project,
					result_type = typeof(Folder).name()
				});
			});
			this.rpc_remove_project.connect((request) => {
				this.remove_project(
					this.projects.path_map.get(
						((CallParam) request.param).path
					)
				);
				request.session.reply(request, new OLLMrpc.Response(request.id) {
					msg = "ok"
				});
			});
			this.rpc_activate_project.connect((request) => {
				var p = (CallParam) request.param;
				this.disable_initial_scan = p.skip_scan;
				this.activate_project.begin(
					request,
					p.path.length > 0
						? this.projects.path_map.get(p.path)
						: null
				);
			});
		}
		
		
		/**
		 * Activate a file (deactivates previous active file).
		 * 
		 * @param file The file to activate
		 */
		public void activate_file(File? file)
		{
			// Deactivate previous active file
			if (this.active_file != null && this.active_file != file) {
				this.active_file.is_active = false;
				if (this.db != null) {
					this.active_file.saveToDB(this.db, null, false);
					this.db.is_dirty = true;
				}
			}
			
			// Activate new file
			this.active_file = file;
			if (file != null) {
				file.is_active = true;
				if (this.db != null) {
					file.saveToDB(this.db, null, false);
					this.db.is_dirty = true;
				}
			}
			
			this.active_file_changed(file);
		}
		
		/**
		 * Activate a project (deactivates previous active project).
		 * Note: Projects are Folders with is_project = true.
		 * 
		 * @param project The project folder to activate (must have is_project = true)
		 */
		public async void activate_project(
			OLLMrpc.Request request,
			Folder? project
		)
		{
			// Skip if this project is already active (avoid redundant scans)
			if (this.active_project == project && project != null && project.is_active) {
				GLib.debug ("opening project skipped already active path=%s", project.path);
				request.session.reply(request, new OLLMrpc.Response(request.id) {
					msg = "ok"
				});
				return;
			}

			// Reset is_active for ALL other projects (ensure only one project is active)
			foreach (var other_project in this.projects.project_map.values) {
				if (other_project != project && other_project.is_project && other_project.is_active) {
					//GLib.debug("ProjectManager.activate_project: Deactivating project '%s'", other_project.path);
					other_project.is_active = false;
					if (this.db != null) {
						other_project.saveToDB(this.db, null, false);
						this.db.is_dirty = true;
					}
				}
			}
			
			// Deactivate previous active project (if different from the one being activated)
			if (this.active_project != null && this.active_project != project) {
				//GLib.debug("ProjectManager.activate_project: Deactivating previous active_project '%s'", this.active_project.path);
				// Note: is_active may already be false from the loop above, but ensure it's saved
				if (this.active_project.is_active) {
					this.active_project.is_active = false;
					if (this.db != null) {
						this.active_project.saveToDB(this.db, null, false);
						this.db.is_dirty = true;
					}
				}
			}
			
			// Activate new project
			this.active_project = project;
			if (project != null && project.is_project) {
				GLib.debug ("opening project path=%s", project.path);
				project.is_active = true;
				
				if (this.db != null) {
					project.saveToDB(this.db, null, false);
					this.db.is_dirty = true;
					
					// Load project file tree from DB if not already loaded (for fast initial display)
					if (project.children.items.size == 0) {
						yield project.load_files_from_db();
						project.project_files.update_from(project);
					}
				}

				if (!this.disable_initial_scan) {
					if (this.scanning.has_key (project.path)) {
						GLib.debug ("filesystem scan already active path=%s", project.path);
					} else {
						GLib.debug ("filesystem scan queued path=%s", project.path);
						yield project.read_dir(new DateTime.now_local().to_unix(), true);
						GLib.debug ("filesystem scan returned path=%s", project.path);
					}
				}
				this.disable_initial_scan = false;
			}
			
			this.active_project_changed(project);

		
			request.session.reply(request, new OLLMrpc.Response(request.id) {
				msg = "ok"
			});
		
		}
		
		
		/**
		 * Notify that a file's metadata has changed (save to database and emit signal).
		 * 
		 * This method is used for metadata-only updates such as cursor position, scroll position,
		 * or last_viewed timestamp. It does NOT trigger background scanning.
		 * 
		 * @param file The file whose metadata changed
		 */
		public void on_file_metadata_change(File file)
		{
			if (this.db != null) {
				file.saveToDB(this.db, null, false);
				this.db.is_dirty = true;
			}
			this.file_metadata_changed(file);
		}
		
		/**
		 * Notify that a file's content has changed (save to database and emit signal).
		 * 
		 * This method is used when file content is written to disk (saved, edited, etc.).
		 * It triggers background scanning via the file_contents_changed signal.
		 * 
		 * @param file The file whose content changed
		 */
		public void on_file_contents_change(File file)
		{
			if (this.db != null) {
				file.saveToDB(this.db, null, false);
				this.db.is_dirty = true;
			}
			this.file_contents_changed(file);
		}
		
		/**
		 * Notify that a project's state has changed (save to database).
		 * Note: Projects are Folders with is_project = true.
		 * 
		 * @param project The project folder that changed (must have is_project = true)
		 */
		public void notify_project_changed(Folder project)
		{
			if (this.db != null) {
				project.saveToDB(this.db,null, false);
				this.db.is_dirty = true;
			}
		}
		
		/**
		 * Load projects from database.
		 * 
		 * Queries database for all folders where is_project = 1 and loads them
		 * into the manager.projects list.
		 */
		public async void load_projects_from_db(OLLMrpc.Request request)
		{
			// Query database for projects
			var query = FileBase.query(this.db, this);
			var projects_list = new Gee.ArrayList<Folder>();
			yield query.select_async("WHERE is_project = 1 AND delete_id = 0", projects_list);
			
			////GLib.debug("ProjectManager.load_projects_from_db: Found %d projects in database", projects_list.size);
			
			// Add to manager.projects list (ProjectList handles deduplication)
			foreach (var project in projects_list) {
				// Projects use property binding: path_basename for label, path for tooltip
				// No need to manually set display_name or tooltip - they're bound directly
				////GLib.debug("ProjectManager.load_projects_from_db: Adding project path='%s' (path_basename='%s')", 
				//	project.path, project.path_basename);
				this.projects.append(project);
			}

			var list = new Gee.ArrayList<GLib.Object>();
			for (uint i = 0; i < this.projects.get_n_items(); i++) {
				list.add(this.projects.get_item(i));
			}
			request.session.reply(request, new OLLMrpc.Response(request.id) {
				result = list,
				result_type = typeof(Folder).name(),
				is_array = true
			});
		}
		
		/**
		 * Find a Folder at the given path (e.g. subfolder of a project, or in DB).
		 * Caller must have already verified the path is not already a project (path_map).
		 * Checks each project's folder_map, then the database. Does not check path_map or file_cache.
		 *
		 * @param path Normalized absolute path
		 * @return The Folder if found, null otherwise
		 */
		public Folder? get_folder_at_path(string path)
		{
			var folder = this.projects.get_folder_in_any_project(path);
			if (folder != null) {
				return folder;
			}
			if (this.db == null) {
				return null;
			}
			var query = FileBase.query(this.db, this);
			var list = new Gee.ArrayList<FileBase>();
			query.select(
				"WHERE path = '%s' AND base_type = 'd' AND delete_id = 0 LIMIT 1".printf(
					path.replace("'", "''")), list);
			return list.size == 0 ? null : list.get(0) as Folder;
		}

		/**
		 * Ensure a project exists at the given path.
		 * Caller must have verified the path is not already a project (path_map).
		 * If we have a Folder at this path (folder_map or DB), promote it; otherwise create new.
		 *
		 * @param path Normalized absolute path to the folder
		 * @return The Folder that is the project at that path (existing or new)
		 */
		public Folder create_project(string path)
		{
			var existing = this.get_folder_at_path(path);
			var project = existing != null
				? existing
				: new Folder(this) {
					is_project = true,
					path = path
				};
			project.is_project = true;
			this.file_cache.set(project.path, project);
			this.projects.append(project);
			project.saveToDB(this.db, null, false);
			this.db.is_dirty = true;
		
			return project;
		}

		/**
		 * Remove a project from the projects list by clearing the is_project flag.
		 * Does not delete any filebase or file_history data.
		 *
		 * @param project The project folder to remove
		 */
		public void remove_project(Folder project)
		{
			if (this.active_project == project) {
				this.active_project = null;
				this.active_project_changed(null);
			}
			this.projects.remove(project);
			project.saveToDB(this.db, null, false);
			this.db.is_dirty = true;
		
		}
		
		/**
		 * Check if a file path is in the active project.
		 * 
		 * @param file_path The normalized file path to check
		 * @return The File object if found in active project, null otherwise
		 */
		public File? get_file_from_active_project(string file_path)
		{
			if (this.active_project == null) {
				return null;
			}
			
			var project_file = this.active_project.project_files.child_map.get(file_path);
			return (project_file == null) ? null : project_file.file;
			
		}
		
		/**
		 * Converts a fake file (id = -1) to a real File object if it's within the active project.
		 * 
		 * This method:
		 * - Checks if the file is within the active project
		 * - Finds or creates parent folder objects in the project tree
		 * - Queries file info from disk
		 * - Converts the fake file to a real File object
		 * - Saves the file to the database
		 * - Updates the ProjectFiles list
		 * - Emits the new_file_added signal
		 * 
		 * @param file The fake file to convert (must have id = -1)
		 * @param file_path The normalized file path
		 */
		public async void convert_fake_file_to_real(File file, string file_path) throws Error
		{
			var active_project = this.active_project;
			
			// Early return if no active project
			if (active_project == null) {
				// File is outside project - keep as fake file (id = -1)
				return;
			}
			
			// Get parent directory path
			// We may have created multiple subdirectories when creating the file,
			// so use find_container_of to find the closest existing folder in the project
			var parent_dir_path = GLib.Path.get_dirname(file_path);
			var found_base_folder = active_project.project_files.find_container_of(parent_dir_path);
			
			// If we didn't find any parent folder in the project, the file is outside the project
			if (found_base_folder == null) {
				// File is outside project - keep as fake file (id = -1)
				return;
			}
			
			// Create missing child folders from found_base_folder down to parent_dir_path
			var parent_folder = yield found_base_folder.make_children(file_path);
			if (parent_folder == null) {
				GLib.warning("ProjectManager.convert_fake_file_to_real: Could not create parent folder for %s", file_path);
				return;
			}
			
			// Query file info from disk
			var gfile = GLib.File.new_for_path(file_path);
			if (!gfile.query_exists()) {
				GLib.warning("ProjectManager.convert_fake_file_to_real: File does not exist on disk: %s", file_path);
				return;
			}
			
			GLib.FileInfo file_info;
			try {
				file_info = gfile.query_info(
					GLib.FileAttribute.STANDARD_CONTENT_TYPE + "," + GLib.FileAttribute.TIME_MODIFIED,
					GLib.FileQueryInfoFlags.NONE,
					null
				);
			} catch (GLib.Error e) {
				GLib.warning("ProjectManager.convert_fake_file_to_real: Could not query file info for %s: %s", file_path, e.message);
				return;
			}
			
			// Convert fake file to real File object
			// Create new File (not new_fake)
			var real_file = new File(this) {
				path = file_path,
				parent = parent_folder,
				parent_id = parent_folder.id,
				id = 0 // New file, will be inserted on save
			};
			
			// Set properties from FileInfo
			var content_type = file_info.get_content_type();
			real_file.is_text = content_type != null && content_type != "" && content_type.has_prefix("text/");
			
			var mod_time = file_info.get_modification_date_time();
			if (mod_time != null) {
				real_file.last_modified = mod_time.to_unix();
			}
			
			// Detect language from filename using buffer provider
			var detected_language = this.buffer_provider.detect_language(real_file);
			if (detected_language != "") {
				real_file.language = detected_language;
			}
			if (!real_file.is_text && real_file.language != "") {
				real_file.is_text = true;
			}
			
			// Add file to parent folder's children
			parent_folder.children.append(real_file);
			
			// Create buffer for new file object
			// The old buffer was associated with the fake file, so we create a new one
			// The file was just written to disk, so the buffer will read from disk when needed
			this.buffer_provider.create_buffer(real_file);
			
			// Save file to DB (gets id > 0, and adds to file_cache automatically)
			if (this.db != null) {
				real_file.saveToDB(this.db, null, false);
			} else {
				// If no DB, manually add to file_cache for immediate lookup
				this.file_cache.set(real_file.path, real_file);
			}
			
			// Update ProjectFiles list
			active_project.project_files.update_from(active_project);
			
			// Manually emit new_file_added signal
			active_project.project_files.new_file_added(real_file);
		}
		
		/**
		 * Get or create a Tree instance for the given file.
		 * 
		 * Returns cached Tree instance if available, otherwise creates a new one
		 * and adds it to the cache.
		 * 
		 * @param file The file to get/create Tree for
		 * @return Tree instance for the file
		 */
		public Tree tree_factory(File file)
		{
			// Check cache first
			if (this.tree_cache.has_key(file.path)) {
				return this.tree_cache.get(file.path);
			}
			
			// Create new Tree instance and cache it
			var tree = new Tree(file);
			this.tree_cache.set(file.path, tree);
			return tree;
		}
		
	}
}
