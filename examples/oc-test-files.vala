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
	 * Recursively output all files and folders with their flags.
	 * Format: %y %Ts %p is_ignored is_repo\n
	 * where %y = file type (f for file, d for directory)
	 *       %Ts = modification time in seconds since epoch
	 *       %p = relative pathname
	 *       is_ignored = whether file/folder is ignored by git (0 or 1)
	 *       is_repo = whether folder is a repo (-1, 0, or 1, -1 for files)
	 * 
	 * @param folder The folder to output recursively
	 * @param base_path Base path for relative path calculation
	 */
	void output_folder_recursive(OLLMfiles.Folder folder, string base_path)
	{
		// Output this folder
		string relpath = folder.path;
		if (relpath.has_prefix(base_path)) {
			relpath = relpath.substring(base_path.length);
			if (relpath.has_prefix("/")) {
				relpath = relpath.substring(1);
			}
		}
		if (relpath == "") {
			relpath = ".";
		}
		
		stdout.printf(
			"d  %s   --- %lld  %s %s\n",
			relpath,
			folder.last_modified,
			folder.is_ignored ? " IGNORED " : "",
			folder.is_repo == 1 ? " REPO " : ""
		);
		
		// Output all children
		for (uint i = 0; i < folder.children.get_n_items(); i++) {
			var child = folder.children.get_item(i) as OLLMfiles.FileBase;
			if (child == null) {
				continue;
			}
			
			string child_relpath = child.path;
			if (child_relpath.has_prefix(base_path)) {
				child_relpath = child_relpath.substring(base_path.length);
				if (child_relpath.has_prefix("/")) {
					child_relpath = child_relpath.substring(1);
				}
			}
			
			if (child is OLLMfiles.Folder) {
				var child_folder = child as OLLMfiles.Folder;
				output_folder_recursive(child_folder, base_path);
			} else if (child is OLLMfiles.File) {
				var child_file = child as OLLMfiles.File;
				stdout.printf(
					"f  %s   --- %lld  %s\n",
					child_relpath,
					child_file.mtime_on_disk(),
					child_file.is_ignored ? " IGNORED " : ""
				);
			} else {
				// Debug: output other types
				stderr.printf("DEBUG: Skipping child type %s: %s\n", child.get_type().name(), child_relpath);
			}
		}
	}
	
	/**
	 * Output project files in the format: %y %Ts %p is_ignored is_repo\n
	 * where %y = file type (f for file)
	 *       %Ts = modification time in seconds since epoch
	 *       %p = pathname from ProjectFile
	 *       is_ignored = whether file is ignored by git (0 or 1)
	 *       is_repo = whether parent folder is a repo (-1, 0, or 1)
	 * 
	 * @param project The project folder containing project_files
	 */
	void output_project_files(OLLMfiles.Folder project)
	{
		// Output all files and folders recursively
		output_folder_recursive(project, project.path);
	}

	MainLoop? main_loop_ref = null;

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
		var manager = new OLLMfiles.ProjectManager(db);
		// Set providers
		manager.buffer_provider = new OLLMcoder.BufferProvider();
		manager.git_provider = new OLLMcoder.GitProvider();
		
		// Create a Folder with is_project = true for the current directory
		var project = new OLLMfiles.Folder(manager);
		project.path = cwd;
		project.is_project = true;
		project.display_name = GLib.Path.get_basename(cwd);
		
		// Disable background recursion for testing - ensures all scans complete before returning
		OLLMfiles.Folder.background_recurse = false;
		
		// Save project to database
		project.saveToDB(db, null, false);
		manager.projects.append(project);
		
		// Scan the directory recursively (this will complete when all folders are processed)
		yield project.read_dir(new DateTime.now_local().to_unix(), true);
		
		// Output project_files in the same format as: find . -printf "%y %Ts %p\n"
		// This tests what project_files contains (only files, not folders or symlinks)
		output_project_files(project);
		
		// Quit main loop to exit
		if (main_loop_ref != null) {
			main_loop_ref.quit();
		}
	}

	int main(string[] args)
	{
		GLib.Log.set_default_handler((dom, lvl, msg) => {
			stderr.printf("%s: %s : %s\n", (new DateTime.now_local()).format("%H:%M:%S.%f"), lvl.to_string(), msg);
		});

		var main_loop = new MainLoop();
		main_loop_ref = main_loop;

		run_scan.begin((obj, res) => {
			try {
				run_scan.end(res);
			} catch (Error e) {
				stderr.printf("Error: %s\n", e.message);
				main_loop.quit();
				Posix.exit(1);
			}
			// Don't quit here - wait for scan_complete signal
		});

		main_loop.run();

		return 0;
	}
}
