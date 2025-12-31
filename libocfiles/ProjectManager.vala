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
		 * List of all projects (folders where is_project = true).
		 */
		public ProjectList projects { get; private set;
			default = new ProjectList(); }
		
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
		 * Constructor.
		 * 
		 * @param db Optional database instance for persistence
		 */
		public ProjectManager(SQ.Database? db = null)
		{
			this.db = db;
			if (this.db != null) {
				// Initialize database tables
				FileBase.initDB(this.db);
			}
			// Initialize git provider if set
			this.git_provider.initialize();
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
			GLib.debug("ProjectManager.activate_project: Called with project=%s (path=%s)", 
				project != null ? project.get_type().name() : "null",
				project != null ? project.path : "null");
			
			// Skip if this project is already active (avoid redundant scans)
			if (this.active_project == project && project != null && project.is_active) {
				GLib.debug("ProjectManager.activate_project: Project '%s' is already active, skipping scan", project.path);
				return;
			}
			
			// Reset is_active for ALL other projects (ensure only one project is active)
			foreach (var other_project in this.projects.project_map.values) {
				if (other_project != project && other_project.is_project && other_project.is_active) {
					GLib.debug("ProjectManager.activate_project: Deactivating project '%s'", other_project.path);
					other_project.is_active = false;
					if (this.db != null) {
						other_project.saveToDB(this.db, null, false);
						this.db.is_dirty = true;
					}
				}
			}
			
			// Deactivate previous active project (if different from the one being activated)
			if (this.active_project != null && this.active_project != project) {
				GLib.debug("ProjectManager.activate_project: Deactivating previous active_project '%s'", this.active_project.path);
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
				
				// Start async directory scan (don't await - runs in background)
 			 
				yield project.read_dir( new DateTime.now_local().to_unix() , true);
				
			}
			
			this.active_project_changed(project);
		}
		
		
		/**
		 * Notify that a file's state has changed (save to database).
		 * 
		 * @param file The file that changed
		 */
		public void notify_file_changed(File file)
		{
			if (this.db != null) {
				file.saveToDB(this.db, null, false);
				this.db.is_dirty = true;
			}
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
			if (this.db == null) {
				GLib.debug("ProjectManager.load_projects_from_db: db is null, skipping");
				return;
			}
			
			// Query database for projects
			var query = FileBase.query(this.db, this);
			var projects_list = new Gee.ArrayList<Folder>();
			yield query.select_async("WHERE is_project = 1", projects_list);
			
			//GLib.debug("ProjectManager.load_projects_from_db: Found %d projects in database", projects_list.size);
			
			// Add to manager.projects list (ProjectList handles deduplication)
			foreach (var project in projects_list) {
				// Projects use property binding: path_basename for label, path for tooltip
				// No need to manually set display_name or tooltip - they're bound directly
				//GLib.debug("ProjectManager.load_projects_from_db: Adding project path='%s' (path_basename='%s')", 
				//	project.path, project.path_basename);
				this.projects.append(project);
			}
			
			//GLib.debug("ProjectManager.load_projects_from_db: After append, projects.get_n_items() = %u", 
			//	this.projects.get_n_items());
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
		 * Restore active project and file from in-memory data structures.
		 * Note: Projects are Folders with is_project = true.
		 * This will set this.active_project and this.active_file, deactivate previous items,
		 * update the database, and emit signals.
		 */
		public async void restore_active_state()
		{
			GLib.debug("ProjectManager.restore_active_state: Starting");
			// Find active project using ProjectList internal method
			var project = this.projects.get_active_project();
			if (project == null) {
				GLib.debug("ProjectManager.restore_active_state: No active project found, resetting all projects");
				// Reset is_active for all projects if no active project found
				// (in case multiple projects were marked active in database)
				foreach (var other_project in this.projects.project_map.values) {
					if (other_project.is_project && other_project.is_active) {
						GLib.debug("ProjectManager.restore_active_state: Resetting is_active for project '%s'", other_project.path);
						other_project.is_active = false;
						if (this.db != null) {
							other_project.saveToDB(this.db, null, false);
							this.db.is_dirty = true;
						}
					}
				}
				return;
			}
			
			GLib.debug("ProjectManager.restore_active_state: Found active project '%s', calling activate_project()", project.path);
			// This will set this.active_project, deactivate all other projects, update DB, emit signal
			yield this.activate_project(project);
			GLib.debug("ProjectManager.restore_active_state: Completed");
			
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
		private static int64 last_cleanup_timestamp = 0;
		
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
				GLib.debug("Wrote buffer to disk: %s", this.active_file.path);
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
				GLib.debug("Reloaded file from disk: %s", this.active_file.path);
			} catch (GLib.Error e) {
				GLib.warning("Failed to reload file from disk %s: %s", this.active_file.path, e.message);
			}
		}
		
		/**
		 * Cleanup old backup files from the backup directory.
		 * 
		 * Removes backup files older than 7 days from ~/.cache/ollmchat/edited/.
		 * This should be called on startup or periodically to prevent backup directory
		 * from growing indefinitely.
		 * 
		 * Only runs once per day to avoid excessive file system operations.
		 */
		public static async void cleanup_old_backups()
		{
			var now = new GLib.DateTime.now_local().to_unix();
			
			if (last_cleanup_timestamp > now - (24 * 60 * 60)) {
				return;
			}
			
			last_cleanup_timestamp = now;
			
			try {
				var cache_dir = GLib.Path.build_filename(
					GLib.Environment.get_home_dir(),
					".cache",
					"ollmchat",
					"edited"
				);
				
				var cache_dir_file = GLib.File.new_for_path(cache_dir);
				if (!cache_dir_file.query_exists()) {
					return;
				}
				
				var cutoff_timestamp = new GLib.DateTime.now_local().add_days(-7).to_unix();
				
				var enumerator = yield cache_dir_file.enumerate_children_async(
					GLib.FileAttribute.STANDARD_NAME + "," + 
					GLib.FileAttribute.TIME_MODIFIED + "," +
					GLib.FileAttribute.STANDARD_TYPE,
					GLib.FileQueryInfoFlags.NONE,
					GLib.Priority.DEFAULT,
					null
				);
				
				var files_to_delete = new Gee.ArrayList<string>();
				
				GLib.FileInfo? info;
				while ((info = enumerator.next_file(null)) != null) {
					if (info.get_file_type() == GLib.FileType.DIRECTORY) {
						continue;
					}
					
					var file_path = GLib.Path.build_filename(cache_dir, info.get_name());
					
					if (info.get_modification_date_time().to_unix() < cutoff_timestamp) {
						files_to_delete.add(file_path);
					}
				}
				
				enumerator.close(null);
				
				int deleted_count = 0;
				foreach (var file_path in files_to_delete) {
					try {
						yield GLib.File.new_for_path(file_path).delete_async(
							GLib.Priority.DEFAULT,
							null
						);
						deleted_count++;
					} catch (GLib.Error e) {
						GLib.warning(
							"Failed to delete backup file %s: %s",
							file_path,
							e.message
						);
					}
				}
				
				if (deleted_count > 0) {
					GLib.debug("Deleted %d old backup file(s)", deleted_count);
				}
			} catch (GLib.Error e) {
				GLib.warning("Failed to cleanup old backups: %s", e.message);
			}
		}
		
	}
}
