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
		 * List of all projects.
		 */
		public Gee.ArrayList<OLLMcoder.Files.Project> projects { get; private set;
			default = new Gee.ArrayList<OLLMcoder.Files.Project>(); }
		
		/**
		 * Currently active project.
		 */
		private OLLMcoder.Files.Project? _active_project = null;
		
		/**
		 * Currently active file.
		 */
		private OLLMcoder.Files.File? _active_file = null;
		
		/**
		 * Emitted when active file changes.
		 */
		public signal void active_file_changed(OLLMcoder.Files.File? file);
		
		/**
		 * Emitted when active project changes.
		 */
		public signal void active_project_changed(OLLMcoder.Files.Project? project);
		
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
			if (this._active_file != null && this._active_file != file) {
				this._active_file.is_active = false;
				if (this.db != null) {
					this._active_file.saveToDB(this.db, false);
				}
			}
			
			// Activate new file
			this._active_file = file;
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
		 * 
		 * @param project The project to activate
		 */
		public void activate_project(OLLMcoder.Files.Project? project)
		{
			// Deactivate previous active project
			if (this._active_project != null && this._active_project != project) {
				this._active_project.is_active = false;
				if (this.db != null) {
					this._active_project.saveToDB(this.db, false);
				}
			}
			
			// Activate new project
			this._active_project = project;
			if (project != null) {
				project.is_active = true;
				if (this.db != null) {
					project.saveToDB(this.db, false);
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
		 * 
		 * @param project The project that changed
		 */
		public void notify_project_changed(OLLMcoder.Files.Project project)
		{
			if (this.db != null) {
				project.saveToDB(this.db, false);
			}
		}
		
		/**
		 * Get active project.
		 * 
		 * @return The currently active project, or null if none
		 */
		public OLLMcoder.Files.Project? get_active_project()
		{
			return this._active_project;
		}
		
		/**
		 * Get active file.
		 * 
		 * @return The currently active file, or null if none
		 */
		public OLLMcoder.Files.File? get_active_file()
		{
			return this._active_file;
		}
	}
}
