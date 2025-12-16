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
	 * Output project files in the format: %y %Ts %p\n
	 * where %y = file type (f for file)
	 *       %Ts = modification time in seconds since epoch
	 *       %p = pathname from ProjectFile
	 * 
	 * @param project The project folder containing project_files
	 */
	void output_project_files(OLLMcoder.Files.Folder project)
	{
		// Iterate through all ProjectFile objects in project_files
		for (uint i = 0; i < project.project_files.get_n_items(); i++) {
			var project_file = project.project_files.get_item(i) as OLLMcoder.Files.ProjectFile;
			if (project_file == null) {
				continue;
			}
			
			// Get the wrapped File object
			var file = project_file.file;
			
			// Output in format: %y %Ts %p\n
			// ProjectFile only contains files (type "f")
			// Use display_relpath which handles symlink paths correctly
			stdout.printf(
				"f %lld %s\n",
				file.mtime_on_disk(),
				project_file.display_relpath
			);
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
		manager.projects.append(project);
		
		// Scan the directory recursively
		yield project.read_dir(new DateTime.now_local().to_unix(), true);
		
		// Ensure database is synced
		db.backupDB();
		
		// Output project_files in the same format as: find . -printf "%y %Ts %p\n"
		// This tests what project_files contains (only files, not folders or symlinks)
		output_project_files(project);
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
