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

namespace OLLMchat
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

	async void run_migrate() throws Error
	{
		// Set up database path
		string db_path = "/tmp/migrate-test.sqlite";
		var db_file = GLib.File.new_for_path(db_path);
		
		// Delete existing database if it exists
		if (db_file.query_exists()) {
			try {
				db_file.delete(null);
				stderr.printf("Deleted existing database: %s\n", db_path);
			} catch (GLib.Error e) {
				stderr.printf("Warning: Failed to delete existing database: %s\n", e.message);
			}
		}
		
		// Create database
		var db = new SQ.Database(db_path, false);
		stderr.printf("Created database: %s\n", db_path);
		
		// Create ProjectManager with the database
		var manager = new OLLMcoder.ProjectManager(db);
		stderr.printf("Created ProjectManager\n");
		
		// Manually do the migration with detailed debugging
		stderr.printf("\n=== Starting Cursor Migration Debug ===\n");
		
		// Build Cursor database path
		var cursor_db_path = GLib.Path.build_filename(
			GLib.Environment.get_home_dir(), ".config", "Cursor", "User", "globalStorage", "state.vscdb"
		);
		stderr.printf("Checking Cursor database at: %s\n", cursor_db_path);
		
		var cursor_db_file = GLib.File.new_for_path(cursor_db_path);
		if (!cursor_db_file.query_exists()) {
			stderr.printf("ERROR: Cursor database not found at %s\n", cursor_db_path);
			return;
		}
		stderr.printf("✓ Cursor database file exists\n");
		
		try {
			// Open Cursor database
			stderr.printf("\nOpening Cursor database...\n");
			var cursor_db = new SQ.Database(cursor_db_path);
			stderr.printf("✓ Database opened successfully\n");
			
			// Query ItemTable
			stderr.printf("\nRunning SQL query on ItemTable...\n");
			stderr.printf("SQL: SELECT * FROM ItemTable WHERE key = 'history.recentlyOpenedPathsList'\n");
			
			var results = new Gee.ArrayList<ItemTable>();
			var query = new SQ.Query<ItemTable>(cursor_db, "ItemTable");
			query.select("WHERE key = 'history.recentlyOpenedPathsList'", results);
			
			stderr.printf("✓ Query executed\n");
			stderr.printf("Results found: %u\n", results.size);
			
			if (results.size == 0) {
				stderr.printf("ERROR: No recently opened paths found in Cursor database\n");
				return;
			}
			
			// Show the raw data
			stderr.printf("\n=== Raw Data Retrieved ===\n");
			for (uint i = 0; i < results.size; i++) {
				var item = results[i];
				stderr.printf("Item %u:\n", i + 1);
				stderr.printf("  key: %s\n", item.key);
				stderr.printf("  value length: %zu bytes\n", item.value.length);
				if (item.value.length < 500) {
					stderr.printf("  value: %s\n", item.value);
				} else {
					stderr.printf("  value (first 500 chars): %s...\n", item.value.substring(0, 500));
				}
			}
			
			// Parse JSON
			stderr.printf("\n=== Parsing JSON ===\n");
			var parser = new Json.Parser();
			parser.load_from_data(results[0].value, -1);
			var root = parser.get_root();
			stderr.printf("✓ JSON parsed successfully\n");
			stderr.printf("Root node type: %s\n", root.get_node_type().to_string());
			
			if (root.get_node_type() != Json.NodeType.ARRAY) {
				stderr.printf("ERROR: Root is not an array, got: %s\n", root.get_node_type().to_string());
				return;
			}
			
			var array = root.get_array();
			stderr.printf("Array length: %u\n", array.get_length());
			
			// Process each element
			stderr.printf("\n=== Processing Paths ===\n");
			var found_paths = new Gee.ArrayList<string>();
			
			for (uint i = 0; i < array.get_length(); i++) {
				var element = array.get_element(i);
				stderr.printf("\nElement %u:\n", i + 1);
				stderr.printf("  Type: %s\n", element.get_node_type().to_string());
				
				if (element.get_node_type() == Json.NodeType.VALUE) {
					var path = element.get_string();
					stderr.printf("  Path (direct value): %s\n", path);
					found_paths.add(path);
					continue;
				}
				
				if (element.get_node_type() != Json.NodeType.OBJECT) {
					stderr.printf("  Skipping (not object or value)\n");
					continue;
				}
				
				var obj = element.get_object();
				if (!obj.has_member("folder")) {
					stderr.printf("  Skipping (no 'folder' member)\n");
					continue;
				}
				
				var folder_node = obj.get_member("folder");
				if (folder_node.get_node_type() != Json.NodeType.VALUE) {
					stderr.printf("  Skipping (folder is not a value)\n");
					continue;
				}
				
				var path = folder_node.get_string();
				stderr.printf("  Path (from folder): %s\n", path);
				found_paths.add(path);
			}
			
			stderr.printf("\n=== Creating Projects ===\n");
			stderr.printf("Total paths found: %u\n", found_paths.size);
			
			// Create projects from paths
			for (uint i = 0; i < found_paths.size; i++) {
				var folder_path = found_paths[i];
				stderr.printf("\nProcessing path %u: %s\n", i + 1, folder_path);
				
				if (folder_path == null || folder_path == "") {
					stderr.printf("  Skipping (empty path)\n");
					continue;
				}
				
				// Resolve to absolute path
				string path = GLib.Path.is_absolute(folder_path) 
					? folder_path 
					: GLib.Path.build_filename(GLib.Environment.get_current_dir(), folder_path);
				stderr.printf("  Resolved path: %s\n", path);
				
				// Normalize the path
				try {
					path = GLib.File.new_for_path(path).get_path();
					stderr.printf("  Normalized path: %s\n", path);
				} catch (GLib.Error e) {
					stderr.printf("  Warning: Failed to normalize path: %s\n", e.message);
				}
				
				// Check if path exists and is a directory
				if (!GLib.FileUtils.test(path, GLib.FileTest.IS_DIR)) {
					stderr.printf("  Skipping (does not exist or is not a directory)\n");
					continue;
				}
				stderr.printf("  ✓ Path exists and is a directory\n");
				
				// Check if project already exists
				if (manager.projects.contains_path(path)) {
					stderr.printf("  Skipping (project already exists)\n");
					continue;
				}
				
				// Create new Project
				stderr.printf("  Creating project...\n");
				var project = new OLLMcoder.Files.Folder(manager);
				project.is_project = true;
				project.path = path;
				project.display_name = GLib.Path.get_basename(path);
				stderr.printf("  ✓ Project created: %s (%s)\n", project.display_name, project.path);
				
				// Add to manager
				manager.projects.append(project);
				
				// Save to database
				if (manager.db != null) {
					project.saveToDB(manager.db, null, false);
					stderr.printf("  ✓ Project saved to database\n");
				}
			}
			
		} catch (GLib.Error e) {
			stderr.printf("\nERROR: Failed to migrate from Cursor: %s\n", e.message);
			stderr.printf("Error type: %s\n", e.get_type().name());
			return;
		}
		
		// Output results
		stderr.printf("\n=== Migration Summary ===\n");
		stderr.printf("Total projects in manager: %u\n", manager.projects.get_n_items());
		for (uint i = 0; i < manager.projects.get_n_items(); i++) {
			var project = manager.projects.get_item(i) as OLLMcoder.Files.Folder;
			if (project != null) {
				stdout.printf("Project %u: %s (%s)\n", i + 1, project.display_name, project.path);
			}
		}
		
		// Sync database
		db.backupDB();
		stderr.printf("\n✓ Database synced\n");
	}

	int main(string[] args)
	{
		GLib.Log.set_default_handler((dom, lvl, msg) => {
			stderr.printf("%s: %s : %s\n", (new DateTime.now_local()).format("%H:%M:%S.%f"), lvl.to_string(), msg);
		});

		MainLoop main_loop = new MainLoop();

		run_migrate.begin((obj, res) => {
			try {
				run_migrate.end(res);
			} catch (Error e) {
				stderr.printf("Error: %s\n", e.message);
				Posix.exit(1);
			}
			main_loop.quit();
		});

		main_loop.run();

		return 0;
	}
}
