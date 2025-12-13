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
		
		/**
		 * Hashmap of path => FileBase for quick lookup.
		 */
		public Gee.HashMap<string, OLLMcoder.Files.FileBase> path_map { get; private set;
			default = new Gee.HashMap<string, OLLMcoder.Files.FileBase>(); }
		
		/**
		 * Hashmap of pretend path => real path (for symlinks/aliases).
		 */
		public Gee.HashMap<string, string> alias_map { get; private set;
			default = new Gee.HashMap<string, string>(); }
		
		/**
		 * List of all projects (folders where is_project = true).
		 */
		public Gee.ArrayList<OLLMcoder.Files.Folder> projects { get; private set;
			default = new Gee.ArrayList<OLLMcoder.Files.Folder>(); }
		
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
		 * Add a path to the path_map and alias_map.
		 * 
		 * @param path The path to add
		 * @param file_base The FileBase object for this path
		 */
		public void add_path(string path, OLLMcoder.Files.FileBase file_base, bool is_symlink = false)
		{
			this.path_map[path] = file_base;
			if (is_symlink) {
				this.alias_map[path] = file_base.path;
			}
		}
		
	 
		
		
		/**
		 * Remove a path from the path_map.
		 * 
		 * @param path The path to remove
		 */
		public void remove_path(string path)
		{
			if (!this.path_map.has_key(path)) {
				return;
			}
			this.path_map.unset(path);
			
			// we should probably remove both sides of alias_map 
			if (this.alias_map.has_key(path)) {
				this.alias_map.unset(path);
			}
			var ar = new Gee.ArrayList<string>();
			foreach (var entry in this.alias_map.keys) {
				if (this.alias_map.get(entry) == path) {
					ar.add(entry);
				}
			}
			foreach(var entry in ar) {
				this.alias_map.unset(entry);
			}
		}
		
		
		/**
		 * Handle file changes (rename, move) and update all alias references.
		 * 
		 * @param old_path The old path
		 * @param new_path The new path
		 */
		public void handle_file_renamed(string old_path, OLLMcoder.Files.FileBase new_file, bool is_symlink = false)
		{
			this.remove_path(old_path);
			this.add_path(new_file.path, new_file, is_symlink);
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
					this.active_file.saveToDB(this.db, false);
				}
			}
			
			// Activate new file
			this.active_file = file;
			if (file != null) {
				file.is_active = true;
				if (this.db != null) {
					file.saveToDB(this.db, false);
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
					this.active_project.saveToDB(this.db, false);
				}
			}
			
			// Activate new project
			this.active_project = project;
			if (project != null && project.is_project) {
				project.is_active = true;
				
				// Initialize ProjectFiles if not already set
				if (project.project_files == null) {
					project.project_files = new OLLMcoder.Files.ProjectFiles(project);
				}
				
				if (this.db != null) {
					project.saveToDB(this.db, false);
					
					// Project files loading is now handled by ProjectFiles
					// No need to call load_files_from_db() - ProjectFiles manages its own state
				}
				
				// Start async directory scan (don't await - runs in background)
				if (project.project_files != null) {
					project.project_files.scan_project.begin();
				} else {
					// Fallback to deprecated method
					project.scan_files.begin();
				}
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
				file.saveToDB(this.db, false);
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
				project.saveToDB(this.db, false);
			}
		}
		
		/**
		 * Restore session (active project and file) from in-memory data structures.
		 * Note: Projects are Folders with is_project = true.
		 * 
		 * @return Tuple of (active_project, active_file) or (null, null) if none found
		 */
		public void restore_session(out OLLMcoder.Files.Folder? project, out OLLMcoder.Files.File? file)
		{
			project = null;
			file = null;
			
			// Find active project in memory (folders where is_project = true)
			project = this.projects.first_match((p) => p.is_active && p.is_project);
			
			if (project == null) {
				return;
			}
			
			// Find active file - try project_files first, then fallback to all_files
			if (project.project_files != null) {
				file = project.project_files.file_map.values.first_match((f) => f.is_active);
			}
			
			// Fallback to deprecated all_files
			if (file == null) {
				for (uint i = 0; i < project.all_files.get_n_items(); i++) {
					var item = project.all_files.get_item(i);
					var f = item as Files.File;
					if (f != null && f.is_active) {
						file = f;
						break;
					}
				}
			}
		}
		
	}
}
