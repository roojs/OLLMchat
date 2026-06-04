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

namespace OLLMfiles
{
	/**
	 * V2 client {@link ProjectManager} — RPC to {@code ollmfilesd}, local UI state only.
	 *
	 * Filesystem, SQLite, and scan work stay on the daemon. This class keeps
	 * {@link active_project}, {@link active_file}, signals, and thin project rows.
	 */
	public class ProjectManager : Object
	{
		public RpcClient rpc { get; private set; default = new RpcClient(); }

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
		 * V2 client constructor (ignores {@code db}; persistence is on the daemon).
		 */
		public ProjectManager(SQ.Database? db = null)
		{
			this.db = null;
			this.git_provider.initialize();
			this.delete_manager = new DeleteManager(this);
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
		public async void activate_project(Folder? project)
		{
			if (this.active_project == project && project != null && project.is_active) {
				GLib.debug ("opening project skipped already active path=%s", project.path);
				return;
			}

			var response = yield this.rpc.call(new Rpc.Request() {
				method = "ProjectManager.activate_project",
				param = new Rpc.CallParam() {
					skip_scan = this.disable_initial_scan,
					path = project != null ? project.path : ""
				}
			});
			if (response.error != null) {
				GLib.critical (
					"ProjectManager.activate_project path=%s: %s",
					project != null ? project.path : "(none)",
					response.error.message
				);
				return;
			}

			foreach (var other_project in this.projects.project_map.values) {
				if (other_project != project && other_project.is_active) {
					other_project.is_active = false;
				}
			}
			if (this.active_project != null && this.active_project != project) {
				this.active_project.is_active = false;
			}

			this.active_project = project;
			if (project != null && project.is_project) {
				GLib.debug ("opening project path=%s", project.path);
				project.is_active = true;
			}
			this.disable_initial_scan = false;
			this.active_project_changed(project);
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
		public async void load_projects_from_db()
		{
			var response = yield this.rpc.call(new Rpc.Request() {
				method = "ProjectManager.load_projects_from_db",
				param = new Rpc.CallParam()
			});
			if (response.error != null) {
				GLib.critical (
					"ProjectManager.load_projects_from_db: %s",
					response.error.message
				);
				return;
			}
			foreach (var folder in (Gee.ArrayList<Folder>) response.result) {
				folder.manager = this;
				this.projects.append(folder);
			}
		}
		
		/**
		 * Find a Folder at the given path (e.g. subfolder of a project, or in DB).
		 * Daemon is authoritative; does not use local {@link projects} / folder_map.
		 *
		 * @param path Normalized absolute path
		 * @return The Folder if found, null otherwise
		 */
		public async Folder? get_folder_at_path(string path)
		{
			var response = yield this.rpc.call(new Rpc.Request() {
				method = "ProjectManager.get_folder_at_path",
				param = new Rpc.CallParam() { path = path }
			});
			if (response.error != null) {
				GLib.critical (
					"ProjectManager.get_folder_at_path path=%s: %s",
					path,
					response.error.message
				);
				return null;
			}
			var folder = (Folder) response.result;
			folder.manager = this;
			return folder;
		}

		/**
		 * Ensure a project exists at the given path.
		 * Caller must have verified the path is not already a project (path_map).
		 * If we have a Folder at this path (folder_map or DB), promote it; otherwise create new.
		 *
		 * @param path Normalized absolute path to the folder
		 * @return The Folder that is the project at that path (existing or new)
		 */
		public async Folder create_project(string path)
		{
			var response = yield this.rpc.call(new Rpc.Request() {
				method = "ProjectManager.create_project",
				param = new Rpc.CallParam() { path = path }
			});
			if (response.error != null) {
				GLib.critical (
					"ProjectManager.create_project path=%s: %s",
					path,
					response.error.message
				);
				return new Folder(this) {
					is_project = true,
					path = path
				};
			}
			var project = (Folder) response.result;
			project.manager = this;
			project.is_project = true;
			this.file_cache.set(project.path, project);
			this.projects.append(project);
			return project;
		}

		/**
		 * Remove a project from the projects list by clearing the is_project flag.
		 * Does not delete any filebase or file_history data.
		 *
		 * @param project The project folder to remove
		 */
		public async void remove_project(Folder project)
		{
			var response = yield this.rpc.call(new Rpc.Request() {
				method = "ProjectManager.remove_project",
				param = new Rpc.CallParam() { path = project.path }
			});
			if (response.error != null) {
				GLib.critical (
					"ProjectManager.remove_project path=%s: %s",
					project.path,
					response.error.message
				);
				return;
			}
			if (this.active_project == project) {
				this.active_project = null;
				this.active_project_changed(null);
			}
			this.projects.remove(project);
			project.is_project = false;
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
		 * Restore active project and file from in-memory data structures.
		 * Note: Projects are Folders with is_project = true.
		 * This will set this.active_project and this.active_file, deactivate previous items,
		 * update the database, and emit signals.
		 */
		public async void restore_active_state()
		{
			//GLib.debug("ProjectManager.restore_active_state: Starting");
			// Find active project using ProjectList internal method
			var project = this.projects.get_active_project();
			if (project == null) {
				//GLib.debug("ProjectManager.restore_active_state: No active project found, resetting all projects");
				// Reset is_active for all projects if no active project found
				// (in case multiple projects were marked active in database)
				foreach (var other_project in this.projects.project_map.values) {
					if (other_project.is_project && other_project.is_active) {
						//GLib.debug("ProjectManager.restore_active_state: Resetting is_active for project '%s'", other_project.path);
						other_project.is_active = false;
						if (this.db != null) {
							other_project.saveToDB(this.db, null, false);
							this.db.is_dirty = true;
						}
					}
				}
				return;
			}
			
			//GLib.debug("ProjectManager.restore_active_state: Found active project '%s'", project.path);
			// Reset is_active to false in memory to force fresh activation
			// activate_project() will set it back to true and save it, so no need to save here
			if (project.is_active) {
				project.is_active = false;
			}
			
			GLib.debug ("restoring session project path=%s", project.path);
			yield this.activate_project(project);
			//GLib.debug("ProjectManager.restore_active_state: Completed");
			
			// Find active file using ProjectFiles internal method
			var file = project.project_files.get_active_file();
			if (file != null) {
				// This will set this.active_file, deactivate previous, update DB, emit signal
				this.activate_file(file);
			}
		}
		
		/**
		 * Timestamp of last backup cleanup run (Unix timestamp).
		 * Used to ensure cleanup only runs once per day.
		 */
		
		/**
		 * Check if the active file has been modified on disk and differs from the buffer.
		 * 
		 * Delegates to the active file's check_updated() method.
		 * This should be called when the window gains focus to detect external file changes.
		 * 
		 * @return FileUpdateStatus indicating what action should be taken
		 */
		public async FileUpdateStatus check_active_file_changed()
		{
			if (this.active_file == null) {
				return FileUpdateStatus.NO_CHANGE;
			}
			
			return yield this.active_file.check_updated();
		}
		
		/**
		 * Writes current buffer contents of active file to disk.
		 */
		public async void write_buffer_to_disk()
		{
			if (this.active_file == null || this.active_file.buffer == null) {
				return;
			}
			
			try {
				yield this.active_file.buffer.sync_to_file();
				//GLib.debug("Wrote buffer to disk: %s", this.active_file.path);
			} catch (GLib.Error e) {
				GLib.warning("Failed to write buffer to disk %s: %s", this.active_file.path, e.message);
			}
		}
		
		/**
		 * Reloads active file from disk into buffer, discarding unsaved changes.
		 */
		public async void reload_file_from_disk()
		{
			if (this.active_file == null || this.active_file.buffer == null) {
				return;
			}
			
			try {
				yield this.active_file.buffer.read_async();
				//GLib.debug("Reloaded file from disk: %s", this.active_file.path);
			} catch (GLib.Error e) {
				GLib.warning("Failed to reload file from disk %s: %s", this.active_file.path, e.message);
			}
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
