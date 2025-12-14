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
	 * where %y = file type (f for file, d for directory)
	 *       %Ts = modification time in seconds since epoch
	 *       %p = full pathname
	 */
	void output_file_tree(OLLMcoder.Files.FileBase item)
	{
		// Get file type: "f" for file, "d" for directory
		string file_type = item.base_type;
		if (file_type == "fa" || file_type == "da") {
			// For aliases, use the type of what they point to
			if (item.points_to != null) {
				file_type = item.points_to.base_type;
			} else {
				// If alias doesn't point to anything, treat as file
				file_type = "f";
			}
		}
		// Normalize: "d" for directory, "f" for file
		if (file_type != "d") {
			file_type = "f";
		}
		
		// Get modification time
		int64 mtime = item.mtime_on_disk();
		
		// Output in format: %y %Ts %p\n
		stdout.printf("%s %lld %s\n", file_type, mtime, item.path);
		
		// If this is a folder, recursively process children
		if (item is OLLMcoder.Files.Folder) {
			var folder = (OLLMcoder.Files.Folder)item;
			foreach (var child in folder.children.items) {
				output_file_tree(child);
			}
		}
	}

	async void run_scan() throws Error
	{
		// Get current working directory
		string cwd = GLib.Environment.get_current_dir();
		stdout.printf("Scanning directory: %s\n", cwd);
		
		// Create database at /tmp/test.sqlite
		var db = new SQ.Database("/tmp/test.sqlite", false);
		
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
		int64 check_time = new DateTime.now_local().to_unix();
		yield project.read_dir(check_time, true);
		
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
