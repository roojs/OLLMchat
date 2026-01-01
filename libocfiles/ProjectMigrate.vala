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
		private ProjectManager manager;
		
		/**
		 * Constructor.
		 * 
		 * @param manager The ProjectManager instance to import data into
		 */
		public ProjectMigrate(ProjectManager manager)
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
			
			GLib.debug("=== Starting Cursor Migration ===");
			GLib.debug("Checking Cursor database at: %s", cursor_db_path);
			
			if (!GLib.File.new_for_path(cursor_db_path).query_exists()) {
				GLib.debug("Cursor database not found at %s", cursor_db_path);
				return;
			}
			
			GLib.debug("✓ Cursor database file exists");
			
			try {
				// Open Cursor database
				GLib.debug("Opening Cursor database...");
				var cursor_db = new SQ.Database(cursor_db_path);
				GLib.debug("✓ Database opened successfully");
				
				// Use SQ.Query to read from ItemTable
				GLib.debug("Running SQL query on ItemTable...");
				GLib.debug("SQL: SELECT * FROM ItemTable WHERE key = 'history.recentlyOpenedPathsList'");
				
				var results = new Gee.ArrayList<ItemTable>();
				new SQ.Query<ItemTable>(cursor_db, "ItemTable")
					.select("WHERE key = 'history.recentlyOpenedPathsList'", results);
				
				GLib.debug("✓ Query executed");
				GLib.debug("Results found: %u", results.size);
				
				if (results.size == 0) {
					GLib.debug("No recently opened paths found in Cursor database");
					return;
				}
				
				// Show the raw data
				GLib.debug("=== Raw Data Retrieved ===");
				for (int i = 0; i < (int)results.size; i++) {
					var item = results[i];
					GLib.debug("Item %d: key=%s, value length=%zu bytes", i + 1, item.key, item.value.length);
					if (item.value.length < 500) {
						GLib.debug("  value: %s", item.value);
					} else {
						GLib.debug("  value (first 500 chars): %s...", item.value.substring(0, 500));
					}
				}
				
				// Extract JSON from the value field
				GLib.debug("=== Parsing JSON ===");
				var parser = new Json.Parser();
				parser.load_from_data(results[0].value, -1);
				var root = parser.get_root();
				GLib.debug("✓ JSON parsed successfully");
				GLib.debug("Root node type: %s", root.get_node_type().to_string());
				
				Json.Array? array = null;
				
				// Handle both formats: direct array or object with "entries" key
				if (root.get_node_type() == Json.NodeType.ARRAY) {
					array = root.get_array();
					GLib.debug("Root is a direct array");
				} else if (root.get_node_type() == Json.NodeType.OBJECT) {
					var root_obj = root.get_object();
					if (root_obj.has_member("entries")) {
						var entries_node = root_obj.get_member("entries");
						if (entries_node.get_node_type() == Json.NodeType.ARRAY) {
							array = entries_node.get_array();
							GLib.debug("Found 'entries' array in root object");
						} else {
							GLib.debug("ERROR: 'entries' member is not an array, got: %s", entries_node.get_node_type().to_string());
							return;
						}
					} else {
						GLib.debug("ERROR: Root is an object but has no 'entries' member");
						return;
					}
				} else {
					GLib.debug("ERROR: Root is not an array or object, got: %s", root.get_node_type().to_string());
					return;
				}
				
				if (array == null) {
					GLib.debug("ERROR: Failed to extract array from JSON");
					return;
				}
				
				GLib.debug("Array length: %u", array.get_length());
				
				// Process each element
				GLib.debug("=== Processing Paths ===");
				uint paths_found = 0;
				
				for (uint i = 0; i < array.get_length(); i++) {
					var element = array.get_element(i);
					GLib.debug("Element %u: type=%s", i + 1, element.get_node_type().to_string());
					
					if (element.get_node_type() == Json.NodeType.VALUE) {
						var path = element.get_string();
						GLib.debug("  Path (direct value): %s", path);
						this.create_project_from_path(path);
						paths_found++;
						continue;
					}
					
					if (element.get_node_type() != Json.NodeType.OBJECT) {
						GLib.debug("  Skipping (not object or value)");
						continue;
					}
					
					var obj = element.get_object();
					string? path = null;
					
					// Check for "folderUri" (Cursor format) first, then "folder" (VS Code format)
					if (obj.has_member("folderUri")) {
						var folder_uri_node = obj.get_member("folderUri");
						if (folder_uri_node.get_node_type() == Json.NodeType.VALUE) {
							var folder_uri = folder_uri_node.get_string();
							// Convert file:// URI to path
							if (folder_uri.has_prefix("file://")) {
								path = folder_uri.substring(7); // Remove "file://" prefix
								GLib.debug("  Path (from folderUri): %s", path);
							} else {
								path = folder_uri;
								GLib.debug("  Path (from folderUri, no file:// prefix): %s", path);
							}
						}
					} else if (obj.has_member("folder")) {
						var folder_node = obj.get_member("folder");
						if (folder_node.get_node_type() == Json.NodeType.VALUE) {
							path = folder_node.get_string();
							GLib.debug("  Path (from folder): %s", path);
						}
					}
					
					if (path == null) {
						GLib.debug("  Skipping (no 'folderUri' or 'folder' member)");
						continue;
					}
					
					this.create_project_from_path(path);
					paths_found++;
				}
				
				GLib.debug("Total paths processed: %u", paths_found);
			} catch (GLib.Error e) {
				GLib.warning("Failed to migrate from Cursor: %s", e.message);
				GLib.debug("Error code: %d", e.code);
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
			GLib.debug("create_project_from_path: %s", folder_path);
			
			if (folder_path == null || folder_path == "") {
				GLib.debug("  Skipping (empty path)");
				return;
			}
			
			// Skip "." and ".." paths explicitly
			if (folder_path == "." || folder_path == "..") {
				GLib.debug("  Skipping (invalid path: '%s')", folder_path);
				return;
			}
			
			// Resolve to absolute path
			string path = GLib.Path.is_absolute(folder_path) 
				? folder_path 
				: GLib.Path.build_filename(GLib.Environment.get_current_dir(), folder_path);
			GLib.debug("  Resolved path: %s", path);
			
			// Normalize the path (remove redundant components)
			try {
				path = GLib.File.new_for_path(path).get_path();
				GLib.debug("  Normalized path: %s", path);
			} catch (GLib.Error e) {
				GLib.debug("  Warning: Failed to normalize path: %s", e.message);
			}
			
			// Check again after normalization (might have become "." or "..")
			if (path == "." || path == ".." || !GLib.Path.is_absolute(path)) {
				GLib.debug("  Skipping (invalid normalized path: '%s')", path);
				return;
			}
			
			// Check if path exists and is a directory (IS_DIR implies EXISTS)
			if (!GLib.FileUtils.test(path, GLib.FileTest.IS_DIR)) {
				GLib.debug("  Skipping (does not exist or is not a directory)");
				return;
			}
			GLib.debug("  ✓ Path exists and is a directory");
			
			// Check if project already exists in projects list
			if (this.manager.projects.path_map.has_key(path)) {
				GLib.debug("  Skipping (project already exists)");
				return;
			}
			
			// Create new Project
			GLib.debug("  Creating project...");
			var project = new Folder(this.manager);
			project.is_project = true;
			project.path = path;
			project.display_name = GLib.Path.get_basename(path);
			GLib.debug("  ✓ Project created: %s (%s)", project.display_name, project.path);
			
			// Add to manager
			this.manager.projects.append(project);
			
			// Save to database (without syncing, we'll sync at the end)
			if (this.manager.db != null) {
				project.saveToDB(this.manager.db, null, false);
				GLib.debug("  ✓ Project saved to database");
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
