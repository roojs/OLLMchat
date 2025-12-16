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
	 * Emulates the ItemTable structure from Cursor's SQLite database.
	 * Used to read data from Cursor's state.vscdb file.
	 */
	internal class ItemTable : Object
	{
		public string key { get; set; default = ""; }
		public string value { get; set; default = ""; }
	}
	
	/**
	 * Migrates project data from existing sources (Cursor, roobuilder, VS Code).
	 * 
	 * Reads project and file data from bootstrap sources and imports them
	 * into the ProjectManager system.
	 */
	public class ProjectMigrate : Object
	{
		private OLLMcoder.ProjectManager manager;
		
		/**
		 * Constructor.
		 * 
		 * @param manager The ProjectManager instance to import data into
		 */
		public ProjectMigrate(OLLMcoder.ProjectManager manager)
		{
			this.manager = manager;
		}
		
		/**
		 * Migrate projects from Cursor SQLite database.
		 * 
		 * Reads from ~/.config/Cursor/User/globalStorage/state.vscdb
		 * and extracts recently opened paths.
		 */
		public void migrate_from_cursor()
		{
			var cursor_db_path = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), ".config", "Cursor", "User", "globalStorage", "state.vscdb"
			);
			
			if (!GLib.File.new_for_path(cursor_db_path).query_exists()) {
				GLib.debug("Cursor database not found at %s", cursor_db_path);
				return;
			}
			
			try {
				// Use SQ.Query to read from ItemTable
				var results = new Gee.ArrayList<ItemTable>();
				new SQ.Query<ItemTable>(new SQ.Database(cursor_db_path), "ItemTable")
					.select("WHERE key = 'history.recentlyOpenedPathsList'", results);
				
				if (results.size == 0) {
					GLib.debug("No recently opened paths found in Cursor database");
					return;
				}
				
				// Extract JSON from the value field
				var parser = new Json.Parser();
				parser.load_from_data(results[0].value, -1);
				var root = parser.get_root();
				
				if (root.get_node_type() != Json.NodeType.ARRAY) {
					return;
				}
				
				var array = root.get_array();
				
				for (uint i = 0; i < array.get_length(); i++) {
					var element = array.get_element(i);
					
					if (element.get_node_type() == Json.NodeType.VALUE) {
						this.create_project_from_path(element.get_string());
						continue;
					}
					
					if (element.get_node_type() != Json.NodeType.OBJECT) {
						continue;
					}
					
					var obj = element.get_object();
					if (!obj.has_member("folder")) {
						continue;
					}
					
					var folder_node = obj.get_member("folder");
					if (folder_node.get_node_type() != Json.NodeType.VALUE) {
						continue;
					}
					
					this.create_project_from_path(folder_node.get_string());
				}
			} catch (GLib.Error e) {
				GLib.warning("Failed to migrate from Cursor: %s", e.message);
			}
		}
		
		/**
		 * Migrate projects from roobuilder Projects.list file.
		 * 
		 * Reads from ~/.config/roobuilder/Projects.list
		 * 
		 * Format is a JSON object with paths as keys:
		 * {{{
		 * {
		 *     "/path/to/project" : "Roo",
		 *     "/path/to/file.xml" : "Roo",
		 * }
		 * }}}
		 * Extracts project paths from the keys.
		 */
		public void migrate_from_roobuilder()
		{
			var projects_list_path = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), ".config", "roobuilder", "Projects.list"
			);
			
			if (!GLib.File.new_for_path(projects_list_path).query_exists()) {
				GLib.debug("roobuilder Projects.list not found at %s", projects_list_path);
				return;
			}
			
			try {
				string content;
				GLib.FileUtils.get_contents(projects_list_path, out content);
				
				// Parse JSON object
				var parser = new Json.Parser();
				parser.load_from_data(content, -1);
				var root = parser.get_root();
				
				if (root.get_node_type() != Json.NodeType.OBJECT) {
					return;
				}
				
				var obj = root.get_object();
				obj.foreach_member((object, member_name, member_node) => {
					// Keys are the paths, values are "Roo" (we ignore the value)
					this.create_project_from_path(member_name);
				});
			} catch (GLib.Error e) {
				GLib.warning("Failed to migrate from roobuilder: %s", e.message);
			}
		}
		
		/**
		 * Migrate projects from VS Code storage.json file.
		 * 
		 * NOT tested as I dont have VS Code installed in many places..
		 * Reads from ~/.config/Code/storage.json
		 * and extracts workspace and file history.
		 */
		public void migrate_from_vscode()
		{
			var storage_json_path = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), ".config", "Code", "storage.json"
			);
			
			if (!GLib.File.new_for_path(storage_json_path).query_exists()) {
				GLib.debug("VS Code storage.json not found at %s", storage_json_path);
				return;
			}
			
			try {
				string content;
				GLib.FileUtils.get_contents(storage_json_path, out content);
				
				// Parse JSON object
				var parser = new Json.Parser();
				parser.load_from_data(content, -1);
				var root = parser.get_root();
				
				if (root.get_node_type() != Json.NodeType.OBJECT) {
					return;
				}
				
				var obj = root.get_object();
				if (!obj.has_member("history.recentlyOpenedPathsList")) {
					return;
				}
				
				var paths_node = obj.get_member("history.recentlyOpenedPathsList");
				if (paths_node.get_node_type() != Json.NodeType.ARRAY) {
					return;
				}
				
				var array = paths_node.get_array();
				
				for (uint i = 0; i < array.get_length(); i++) {
					var element = array.get_element(i);
					
					if (element.get_node_type() == Json.NodeType.VALUE) {
						this.create_project_from_path(element.get_string());
						continue;
					}
					
					if (element.get_node_type() != Json.NodeType.OBJECT) {
						continue;
					}
					
					var path_obj = element.get_object();
					if (!path_obj.has_member("folder")) {
						continue;
					}
					
					var folder_node = path_obj.get_member("folder");
					if (folder_node.get_node_type() != Json.NodeType.VALUE) {
						continue;
					}
					
					this.create_project_from_path(folder_node.get_string());
				}
			} catch (GLib.Error e) {
				GLib.warning("Failed to migrate from VS Code: %s", e.message);
			}
		}
		
		/**
		 * Create a Project from a folder path and save it to the database.
		 * 
		 * @param folder_path The path to the folder to create as a project
		 */
		private void create_project_from_path(string folder_path)
		{
			if (folder_path == null || folder_path == "") {
				return;
			}
			
			// Resolve to absolute path
			string path = GLib.Path.is_absolute(folder_path) 
				? folder_path 
				: GLib.Path.build_filename(GLib.Environment.get_current_dir(), folder_path);
			
			// Normalize the path (remove redundant components)
			try {
				path = GLib.File.new_for_path(path).get_path();
			} catch (GLib.Error e) {
				GLib.debug("Failed to normalize path %s: %s", path, e.message);
			}
			
			// Check if path exists and is a directory (IS_DIR implies EXISTS)
			if (!GLib.FileUtils.test(path, GLib.FileTest.IS_DIR)) {
				GLib.debug("Path does not exist or is not a directory: %s", path);
				return;
			}
			
			// Check if project already exists in projects list
			if (this.manager.projects.contains_path(path)) {
				GLib.debug("Project already exists in projects list: %s", path);
				return;
			}
			
			// Create new Project
			var project = new OLLMcoder.Files.Folder(this.manager);
			project.is_project = true;
			project.path = path;
			project.display_name = GLib.Path.get_basename(path);
			
			// Add to manager
			this.manager.projects.append(project);
			
			// Save to database (without syncing, we'll sync at the end)
			if (this.manager.db != null) {
				project.saveToDB(this.manager.db, null, false);
			}
		}
		
		/**
		 * Run all migration methods and sync database at the end.
		 */
		public void migrate_all()
		{
			this.migrate_from_cursor();
			this.migrate_from_roobuilder();
			this.migrate_from_vscode();
			
			// Sync database after all migrations
			if (this.manager.db != null) {
				this.manager.db.backupDB();
			}
		}
	}
}
