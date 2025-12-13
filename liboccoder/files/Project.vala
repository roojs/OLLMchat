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
	 * Represents a project in the system.
	 * 
	 * Projects are folders with special project management capabilities.
	 * Maintains a flat list of all files for efficient dropdown population.
	 */
	public class Project : Folder
	{
		/**
		 * ListStore of all files in project (used by dropdowns).
		 */
		public GLib.ListStore all_files { get; set; 
			default = new GLib.ListStore(typeof(FileBase)); }
		
		/**
		 * Constructor.
		 * 
		 * @param manager The ProjectManager instance (required)
		 */
		public Project(OLLMcoder.ProjectManager manager)
		{
			base(manager);
			this.base_type = "p";
		}
		
		/**
		 * Get the currently active file in this project.
		 * 
		 * @return The active file, or null if none is active
		 */
		public File? get_active_file()
		{
			for (uint i = 0; i < this.all_files.get_n_items(); i++) {
				var item = this.all_files.get_item(i);
				var file = item as File;
				if (file != null && file.is_active) {
					return file;
				}
			}
			return null;
		}
		
		/**
		 * Load project files from database into project's all_files ListStore.
		 * 
		 * @param db The database instance to load from
		 */
		public void load_files_from_db(SQ.Database db)
		{
			if (this.id <= 0) {
				return;
			}
			
			var query = FileBase.query(db);
			var file_list = new Gee.ArrayList<FileBase>();
			
			// Load files where parent_id matches project id, or path starts with project path
			query.selectQuery("WHERE parent_id = " + this.id.to_string() + " OR path LIKE '" + this.path + "%'", file_list);
			
			// Add files to project's all_files ListStore
			foreach (var file_base in file_list) {
				// Only add files (not folders or projects)
				if (file_base is File) {
					this.all_files.append(file_base);
				}
			}
		}
		
		/**
		 * Populate project's all_files ListStore from project's children.
		 * Recursively collects all files from the folder hierarchy.
		 */
		public void populate_all_files_from_children()
		{
			// Clear existing files THIS IS WRONG _ NEEDS FIXING
			this.all_files.remove_all();
			
			// Recursively collect all files from children
			this.collect_files_recursive(this, this.all_files);
		}
		
		/**
		 * Recursively collect all files from a folder and its children.
		 * 
		 * @param folder The folder to collect files from
		 * @param file_list The ListStore to add files to
		 */
		private void collect_files_recursive(Folder folder, GLib.ListStore file_list)
		{
			foreach (var child in folder.children) {
				if (child is File) {
					file_list.append(child);
				} else if (child is Folder) {
					this.collect_files_recursive((Folder)child, file_list);
				}
			}
		}
		
		/**
		 * Scan project directory for files asynchronously.
		 * Updates project's all_files ListStore as files are discovered.
		 */
		public async void scan_files()
		{
			try {
				var check_time = new DateTime.now_local().to_unix();
				yield this.read_dir(check_time, true);
				
				// After scanning, update all_files ListStore with discovered files
				// Files are already in project.children, need to add them to all_files
				this.populate_all_files_from_children();
			} catch (Error e) {
				GLib.warning("Failed to scan project files for %s: %s", this.path, e.message);
			}
		}
	}
}
