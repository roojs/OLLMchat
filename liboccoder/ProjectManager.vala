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
		 * Database instance for persistence.
		 * Set this to enable database operations.
		 */
		public SQ.Database? db { get; set; default = null; }
		
		public Gee.HashMap<string,Files.FileBase> file_cache {
			get; set;
			default = new Gee.HashMap<string,Files.FileBase>(); 
		}
		
		/**
		 * List of all projects (folders where is_project = true).
		 */
		public OLLMcoder.Files.ProjectList projects { get; private set;
			default = new OLLMcoder.Files.ProjectList(); }
		
		/**
		 * Currently active project (folder with is_project = true).
		 */
		public OLLMcoder.Files.Folder? active_project { get; private set; default = null; }
		
		/**
		 * Currently active file.
		 */
		public OLLMcoder.Files.File? active_file { get; private set; default = null; }
		
		/**
		 * Emitted when active file changes.
		 */
		public signal void active_file_changed(OLLMcoder.Files.File? file);
		
		/**
		 * Emitted when active project changes.
		 * Note: Projects are Folders with is_project = true.
		 */
		public signal void active_project_changed(OLLMcoder.Files.Folder? project);
		
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
				OLLMcoder.Files.FileBase.initDB(this.db);
			}
		}
		
		
		/**
		 * Activate a file (deactivates previous active file).
		 * 
		 * @param file The file to activate
		 */
		public void activate_file(OLLMcoder.Files.File? file)
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
		public async void activate_project(OLLMcoder.Files.Folder? project)
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
				GLib.debug("ProjectManager.activate_project: Activating project '%s', starting directory scan", project.path);
				project.is_active = true;
				
				if (this.db != null) {
					project.saveToDB(this.db, null, false);
					this.db.is_dirty = true;
					
					// Project files loading is now handled by ProjectFiles
					// No need to call load_files_from_db() - ProjectFiles manages its own state
				}
				
				// Start async directory scan (don't await - runs in background)
				var check_time = new DateTime.now_local().to_unix();
				GLib.debug("ProjectManager.activate_project: Calling read_dir() for project '%s' with check_time=%lld, recurse=true", 
					project.path, check_time);
				yield project.read_dir(check_time, true);
				GLib.debug("ProjectManager.activate_project: read_dir() completed for project '%s'", project.path);
				
			}
			
			this.active_project_changed(project);
		}
		
		
		/**
		 * Notify that a file's state has changed (save to database).
		 * 
		 * @param file The file that changed
		 */
		public void notify_file_changed(OLLMcoder.Files.File file)
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
		public void notify_project_changed(OLLMcoder.Files.Folder project)
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
			var query = OLLMcoder.Files.FileBase.query(this.db, this);
			var projects_list = new Gee.ArrayList<OLLMcoder.Files.Folder>();
			yield query.select_async("WHERE is_project = 1", projects_list);
			
			GLib.debug("ProjectManager.load_projects_from_db: Found %d projects in database", projects_list.size);
			
			// Add to manager.projects list (ProjectList handles deduplication)
			foreach (var project in projects_list) {
				// Projects use property binding: path_basename for label, path for tooltip
				// No need to manually set display_name or tooltip - they're bound directly
				GLib.debug("ProjectManager.load_projects_from_db: Adding project path='%s' (path_basename='%s')", 
					project.path, project.path_basename);
				this.projects.append(project);
			}
			
			GLib.debug("ProjectManager.load_projects_from_db: After append, projects.get_n_items() = %u", 
				this.projects.get_n_items());
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
		
	}
}
