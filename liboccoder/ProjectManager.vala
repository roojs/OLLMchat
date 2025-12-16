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
			// Deactivate previous active project
			if (this.active_project != null && this.active_project != project) {
				this.active_project.is_active = false;
				if (this.db != null) {
					this.active_project.saveToDB(this.db, null, false);
					this.db.is_dirty = true;
				}
			}
			
			// Activate new project
			this.active_project = project;
			if (project != null && project.is_project) {
				project.is_active = true;
				
				if (this.db != null) {
					project.saveToDB(this.db, null, false);
					this.db.is_dirty = true;
					
					// Project files loading is now handled by ProjectFiles
					// No need to call load_files_from_db() - ProjectFiles manages its own state
				}
				
				// Start async directory scan (don't await - runs in background)
				yield project.read_dir(new DateTime.now_local().to_unix(), true);
				
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
		public void load_projects_from_db()
		{
			if (this.db == null) {
				return;
			}
			
			// Query database for projects
			var query = OLLMcoder.Files.FileBase.query(this.db, this);
			var projects_list = new Gee.ArrayList<OLLMcoder.Files.Folder>();
			query.select("WHERE is_project = 1", projects_list);
			
			// Add to manager.projects list (ProjectList handles deduplication)
			foreach (var project in projects_list) {
				this.projects.append(project);
			}
		}
		
		/**
		 * Restore active project and file from in-memory data structures.
		 * Note: Projects are Folders with is_project = true.
		 * This will set this.active_project and this.active_file, deactivate previous items,
		 * update the database, and emit signals.
		 */
		public async void restore_active_state()
		{
			// Find active project using ProjectList internal method
			var project = this.projects.get_active_project();
			if (project == null) {
				return;
			}
			
			// This will set this.active_project, deactivate previous, update DB, emit signal
			yield this.activate_project(project);
			
			// Find active file using ProjectFiles internal method
			var file = project.project_files.get_active_file();
			if (file != null) {
				// This will set this.active_file, deactivate previous, update DB, emit signal
				this.activate_file(file);
			}
		}
		
	}
}
