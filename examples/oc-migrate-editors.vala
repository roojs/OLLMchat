


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
	async void run_migrate() throws Error
	{
		// Set up database path
		string db_path = "/tmp/migrate-test.sqlite";
		var db_file = GLib.File.new_for_path(db_path);
		
		// Delete existing database if it exists
		if (db_file.query_exists()) {
			try {
				db_file.delete(null);
				GLib.debug("Deleted existing database: %s", db_path);
			} catch (GLib.Error e) {
				GLib.debug("Warning: Failed to delete existing database: %s", e.message);
			}
		}
		
		// Create database
		var db = new SQ.Database(db_path, false);
		GLib.debug("Created database: %s", db_path);
		
 
		// Uses default BufferProviderBase and GitProviderBase from ocfiles (no GTK dependencies)
		var manager = new OLLMfiles.ProjectManager(db);
 		GLib.debug("Created ProjectManager");
		
		// Create ProjectMigrate instance
		var migrator = new OLLMfiles.ProjectMigrate(manager);
		GLib.debug("Created ProjectMigrate");
		
		// Run migration from Cursor (debug output will come from ProjectMigrate)
		migrator.migrate_from_cursor();
		
		// Output results
		GLib.debug("=== Migration Summary ===");
		GLib.debug("Total projects in manager: %u", manager.projects.get_n_items());
		for (uint i = 0; i < manager.projects.get_n_items(); i++) {
			var project = manager.projects.get_item(i) as OLLMfiles.Folder;
			if (project != null) {
				stdout.printf("Project %u: %s (%s)\n", i + 1, project.display_name, project.path);
			}
		}
		
		// Sync database
		db.backupDB();
		GLib.debug("Database synced");
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
