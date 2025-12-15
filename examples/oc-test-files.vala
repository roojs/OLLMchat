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
	 * Recursively output all files and folders in the format: %y %Ts %p\n
	 * where %y = file type (f for file, d for directory, l for symlink)
	 *       %Ts = modification time in seconds since epoch
	 *       %p = full pathname
	 */
	void output_file_tree(OLLMcoder.Files.FileBase item)
	{
		// Output in format: %y %Ts %p\n
		// Handle symlinks (FileAlias with base_type "fa") - output "l" to match find
		// Note: For symlinks, we output the symlink's path (item.path), not the target path
		// Symlinks are stored and output as separate entries with type "l"
		stdout.printf(
			"%s %lld %s\n",
			item.base_type == "fa" ? "l" : item.base_type,
			item.mtime_on_disk(),
			item.path
		);
		
		// If this is a folder, recursively process children
		if (item is OLLMcoder.Files.Folder) {
			var folder = (OLLMcoder.Files.Folder)item;
			foreach (var child in folder.children.items) {
				output_file_tree(child);
			}
		}
		// If this is a symlink that points to a folder, also iterate the target folder's children
		if (item is OLLMcoder.Files.FileAlias && item.points_to is OLLMcoder.Files.Folder) {
			var folder = (OLLMcoder.Files.Folder)item.points_to;
			foreach (var child in folder.children.items) {
				output_file_tree(child);
			}
		}
	}

	async void run_scan() throws Error
	{
		// Get current working directory
		string cwd = GLib.Environment.get_current_dir();
		stderr.printf("Scanning directory: %s\n", cwd);
		
		// Check if database exists and delete it if necessary
		string db_path = "/tmp/test.sqlite";
		var db_file = GLib.File.new_for_path(db_path);
		if (db_file.query_exists()) {
			try {
				db_file.delete(null);
				stderr.printf("Deleted existing database: %s\n", db_path);
			} catch (GLib.Error e) {
				stderr.printf("Warning: Failed to delete existing database: %s\n", e.message);
			}
		}
		
		// Create database at /tmp/test.sqlite
		var db = new SQ.Database(db_path, false);
		
		// Create ProjectManager with the database
		var manager = new OLLMcoder.ProjectManager(db);
		
		// Create a Folder with is_project = true for the current directory
		var project = new OLLMcoder.Files.Folder(manager);
		project.path = cwd;
		project.is_project = true;
		project.display_name = GLib.Path.get_basename(cwd);
		
		// Save project to database
		project.saveToDB(db, null, false);
		manager.projects.add(project);
		
		// Scan the directory recursively
		yield project.read_dir(new DateTime.now_local().to_unix(), true);
		
		// Ensure database is synced
		db.backupDB();
		
		// Output results in the same format as: find . -printf "%y %Ts %p\n"
		// Start with the project root itself
		output_file_tree(project);
	}

	int main(string[] args)
	{
		GLib.Log.set_default_handler((dom, lvl, msg) => {
			stderr.printf("%s: %s : %s\n", (new DateTime.now_local()).format("%H:%M:%S.%f"), lvl.to_string(), msg);
		});

		MainLoop main_loop = new MainLoop();

		run_scan.begin((obj, res) => {
			try {
				run_scan.end(res);
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
