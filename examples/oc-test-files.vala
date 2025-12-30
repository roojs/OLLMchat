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

class TestFiles : TestAppBase
{
	private static string? opt_test_db = null;
	private static bool opt_ls = false;
	private static string? opt_read = null;
	private static int opt_start_line = 0;
	private static int opt_end_line = 0;
	private static string? opt_output = null;
	private static string? opt_backend = null;
	private static string? opt_write = null;
	private static string? opt_content = null;
	private static string? opt_content_file = null;
	private static string? opt_backup_dir = null;
	private static string? opt_create_fake = null;
	private static string? opt_check_project = null;
	private static bool opt_cleanup_backups = false;
	private static int opt_age_days = 7;
	private static bool opt_list_buffers = false;
	private static int opt_max_buffers = 0;
	private static string? opt_create_project = null;
	private static string? opt_info = null;
	private static string? opt_ls_path = null;

	public TestFiles()
	{
		base("com.roojs.ollmchat.test-files");
	}

	protected override string get_app_name()
	{
		return "oc-test-files";
	}

	private const OptionEntry[] local_options = {
		{ "test-db", 0, 0, OptionArg.STRING, ref opt_test_db, "Specify test database path (optional, for testing only)", "PATH" },
		{ "ls", 0, 0, OptionArg.NONE, ref opt_ls, "List files in directory (scan/print functionality)", null },
		{ "ls-path", 0, 0, OptionArg.STRING, ref opt_ls_path, "Path to scan for --ls (default: current directory)", "PATH" },
		{ "read", 0, 0, OptionArg.STRING, ref opt_read, "Read file with optional line ranges", "PATH" },
		{ "start-line", 0, 0, OptionArg.INT, ref opt_start_line, "Start line number (1-based)", "N" },
		{ "end-line", 0, 0, OptionArg.INT, ref opt_end_line, "End line number (1-based)", "M" },
		{ "output", 0, 0, OptionArg.STRING, ref opt_output, "Output file path (default: stdout)", "FILE" },
		{ "backend", 0, 0, OptionArg.STRING, ref opt_backend, "Buffer backend (sourceview|dummy, default: dummy)", "BACKEND" },
		{ "write", 0, 0, OptionArg.STRING, ref opt_write, "Write file with backups", "PATH" },
		{ "content", 0, 0, OptionArg.STRING, ref opt_content, "Content to write", "TEXT" },
		{ "content-file", 0, 0, OptionArg.STRING, ref opt_content_file, "File containing content to write", "FILE" },
		{ "create-fake", 0, 0, OptionArg.STRING, ref opt_create_fake, "Create fake file", "PATH" },
		{ "check-project", 0, 0, OptionArg.STRING, ref opt_check_project, "Check if file is in active project", "PATH" },
		{ "cleanup-backups", 0, 0, OptionArg.NONE, ref opt_cleanup_backups, "Cleanup old backups", null },
		{ "age-days", 0, 0, OptionArg.INT, ref opt_age_days, "Age threshold in days (default: 7)", "N" },
		{ "list-buffers", 0, 0, OptionArg.NONE, ref opt_list_buffers, "List current buffers", null },
		{ "max-buffers", 0, 0, OptionArg.INT, ref opt_max_buffers, "Maximum number of buffers to list", "N" },
		{ "create-project", 0, 0, OptionArg.STRING, ref opt_create_project, "Create test project", "PATH" },
		{ "info", 0, 0, OptionArg.STRING, ref opt_info, "Show file information", "PATH" },
		{ null }
	};

	protected override OptionEntry[] get_options()
	{
		var options = new OptionEntry[base_options.length + local_options.length];
		int i = 0;
		
		// Copy base options
		foreach (var opt in base_options) {
			options[i++] = opt;
		}
		
		// Copy local options
		foreach (var opt in local_options) {
			options[i++] = opt;
		}
		
		return options;
	}

	protected override string? validate_args(string[] args)
	{
		// Count how many actions are specified
		int action_count = 0;
		if (opt_ls) {
			action_count++;
		}
		if (opt_read != null) {
			action_count++;
		}
		if (opt_write != null) {
			action_count++;
		}
		if (opt_create_fake != null) {
			action_count++;
		}
		if (opt_check_project != null) {
			action_count++;
		}
		if (opt_cleanup_backups) {
			action_count++;
		}
		if (opt_list_buffers) {
			action_count++;
		}
		if (opt_create_project != null) {
			action_count++;
		}
		if (opt_info != null) {
			action_count++;
		}
		
		if (action_count == 0) {
			return "Error: No action specified. Use --help to see available options.\n";
		}
		if (action_count > 1) {
			return "Error: Multiple actions specified. Only one action is allowed at a time.\n";
		}
		
		return null;
	}

	protected override async void run_test(ApplicationCommandLine command_line) throws Error
	{
		// Determine database path
		string db_path;
		if (opt_test_db != null && opt_test_db != "") {
			db_path = opt_test_db;
		} else {
			// Use main database (normal operation)
			db_path = GLib.Path.build_filename(this.data_dir, "files.sqlite");
		}
		
		// Create database
		var db = new SQ.Database(db_path, false);
		
		// Create ProjectManager
		var manager = new OLLMfiles.ProjectManager(db);
		
		// Set buffer provider based on backend option
		if (opt_backend == "sourceview") {
			manager.buffer_provider = new OLLMcoder.BufferProvider();
		} else {
			// Default to dummy backend
			manager.buffer_provider = new OLLMfiles.BufferProviderBase();
		}
		
		// Load projects from database
		yield manager.load_projects_from_db();
		
		// Set active project if available
		if (manager.projects.get_n_items() > 0) {
			var project = manager.projects.get_item(0) as OLLMfiles.Folder;
			if (project != null) {
				yield manager.activate_project(project);
			}
		}
		
		// Execute the requested action
		if (opt_ls) {
			yield this.run_ls(manager);
		} else if (opt_read != null) {
			yield this.run_read(manager);
		} else if (opt_write != null) {
			yield this.run_write(manager);
		} else if (opt_create_fake != null) {
			yield this.run_create_fake(manager);
		} else if (opt_check_project != null) {
			yield this.run_check_project(manager);
		} else if (opt_cleanup_backups) {
			yield this.run_cleanup_backups();
		} else if (opt_list_buffers) {
			yield this.run_list_buffers(manager);
		} else if (opt_create_project != null) {
			yield this.run_create_project(manager, db);
		} else if (opt_info != null) {
			yield this.run_info(manager);
		}
	}

	private async void run_ls(OLLMfiles.ProjectManager manager) throws Error
	{
		string scan_path = opt_ls_path ?? GLib.Environment.get_current_dir();
		
		// Create a Folder with is_project = true for the scan path
		var project = new OLLMfiles.Folder(manager);
		project.path = scan_path;
		project.is_project = true;
		project.display_name = GLib.Path.get_basename(scan_path);
		
		// Disable background recursion for testing
		OLLMfiles.Folder.background_recurse = false;
		
		// Save project to database
		if (manager.db != null) {
			project.saveToDB(manager.db, null, false);
		}
		manager.projects.append(project);
		
		// Scan the directory recursively
		yield project.read_dir(new GLib.DateTime.now_local().to_unix(), true);
		
		// Output project files
		this.output_project_files(project);
	}

	private async void run_read(OLLMfiles.ProjectManager manager) throws Error
	{
		string file_path = opt_read;
		
		// Get or create file
		OLLMfiles.File? file = null;
		
		// Try to get from active project first
		if (manager.active_project != null) {
			file = manager.get_file_from_active_project(file_path);
		}
		
		// If not in project, create fake file
		if (file == null) {
			file = new OLLMfiles.File.new_fake(manager, file_path);
		}
		
		// Ensure buffer is created
		if (file.buffer == null) {
			manager.buffer_provider.create_buffer(file);
		}
		
		string content;
		int line_count = 0;
		
		// Read file or get line range
		if (opt_start_line > 0 || opt_end_line > 0) {
			// Read entire file first to load buffer
			content = yield file.buffer.read_async();
			line_count = file.buffer.get_line_count();
			
			// Convert 1-based to 0-based
			int start = opt_start_line > 0 ? opt_start_line - 1 : 0;
			int end = opt_end_line > 0 ? opt_end_line - 1 : line_count - 1;
			
			// Get text range
			content = file.buffer.get_text(start, end);
		} else {
			// Read entire file
			content = yield file.buffer.read_async();
			line_count = file.buffer.get_line_count();
		}
		
		// Output metadata and content
		string line_range = "";
		if (opt_start_line > 0 || opt_end_line > 0) {
			line_range = @"LINE_RANGE: $(opt_start_line > 0 ? opt_start_line : 1)-$(opt_end_line > 0 ? opt_end_line : line_count)
";
		}
		
		if (opt_output != null && opt_output != "") {
			var output_file = GLib.File.new_for_path(opt_output);
			yield output_file.replace_contents_async(content.data, null, false, GLib.FileCreateFlags.NONE, null, null);
			print(@"FILE: $(file_path)
$(line_range)LINE_COUNT: $(line_count)
BUFFER_TYPE: $(file.buffer.get_type().name())
BACKEND: $(opt_backend ?? "dummy")
---
Content written to: $(opt_output)
");
		} else {
			print(@"FILE: $(file_path)
$(line_range)LINE_COUNT: $(line_count)
BUFFER_TYPE: $(file.buffer.get_type().name())
BACKEND: $(opt_backend ?? "dummy")
---
$(content)
");
		}
	}

	private async void run_write(OLLMfiles.ProjectManager manager) throws Error
	{
		string file_path = opt_write;
		
		// Get content from priority: content-file > content > stdin
		string content = "";
		
		if (opt_content_file != null && opt_content_file != "") {
			var content_file = GLib.File.new_for_path(opt_content_file);
			if (!content_file.query_exists()) {
				throw new GLib.FileError.NOENT("Content file not found: " + opt_content_file);
			}
			uint8[] data;
			string etag;
			yield content_file.load_contents_async(null, out data, out etag);
			content = (string)data;
		} else if (opt_content != null && opt_content != "") {
			content = opt_content;
		} else {
			// Read from stdin
			var lines = new GLib.StringBuilder();
			string? line;
			while ((line = GLib.stdin.read_line()) != null) {
				if (lines.len > 0) {
					lines.append_c('\n');
				}
				lines.append(line);
			}
			content = lines.str;
		}
		
		// Get or create file
		OLLMfiles.File? file = null;
		
		// Try to get from active project first
		if (manager.active_project != null) {
			file = manager.get_file_from_active_project(file_path);
		}
		
		// If not in project, create fake file
		if (file == null) {
			file = new OLLMfiles.File.new_fake(manager, file_path);
		}
		
		// Ensure buffer is created
		if (file.buffer == null) {
			manager.buffer_provider.create_buffer(file);
		}
		
		// Write content
		yield file.buffer.write(content);
		
		// Output results
		string backup_info = file.last_approved_copy_path != null && file.last_approved_copy_path != "" 
			? @"BACKUP: $(file.last_approved_copy_path)
" 
			: @"NO_BACKUP: $(file.id < 0 ? "fake_file" : "no_backup_created")
";
		print(@"$(backup_info)FILE: $(file_path)
FILE_ID: $(file.id)
BACKEND: $(opt_backend ?? "dummy")
");
	}

	private async void run_create_fake(OLLMfiles.ProjectManager manager) throws Error
	{
		string file_path = opt_create_fake;
		
		var file = new OLLMfiles.File.new_fake(manager, file_path);
		
		print(@"FILE: $(file_path)
FILE_ID: $(file.id)
BUFFER_STATUS: $(file.buffer != null ? "created" : "null")
IS_FAKE: true
");
	}

	private async void run_check_project(OLLMfiles.ProjectManager manager) throws Error
	{
		string file_path = opt_check_project;
		
		if (manager.active_project == null) {
			print(@"FILE: $(file_path)
STATUS: NOT_IN_PROJECT
PROJECT_PATH: (no active project)
");
			return;
		}
		
		bool in_project = manager.active_project.project_files.child_map.has_key(file_path);
		
		print(@"FILE: $(file_path)
STATUS: $(in_project ? "IN_PROJECT" : "NOT_IN_PROJECT")
PROJECT_PATH: $(manager.active_project.path)
");
	}

	private async void run_cleanup_backups() throws Error
	{
		// Note: cleanup_old_backups is static and uses hardcoded 7 days
		// We can't override the age, but we can call it
		yield OLLMfiles.ProjectManager.cleanup_old_backups();
		
		var cache_dir = GLib.Path.build_filename(
			GLib.Environment.get_home_dir(),
			".cache",
			"ollmchat",
			"edited"
		);
		
		print(@"BACKUP_DIR: $(cache_dir)
AGE_THRESHOLD: 7 days
Cleanup completed (check logs for deleted files)
");
	}

	private async void run_list_buffers(OLLMfiles.ProjectManager manager) throws Error
	{
		int count = 0;
		foreach (var entry in manager.file_cache.entries) {
			if (opt_max_buffers > 0 && count >= opt_max_buffers) {
				break;
			}
			
			var file_base = entry.value;
			if (file_base is OLLMfiles.File) {
				var file = file_base as OLLMfiles.File;
				if (file.buffer != null) {
					print(@"BUFFER: $(file.path) TIMESTAMP: $(file.last_viewed) OPEN: true\n");
					count++;
				}
			}
		}
		
		if (count == 0) {
			print("No buffers found\n");
		}
	}

	private async void run_create_project(OLLMfiles.ProjectManager manager, SQ.Database db) throws Error
	{
		string project_path = opt_create_project;
		
		// Create a Folder with is_project = true
		var project = new OLLMfiles.Folder(manager);
		project.path = project_path;
		project.is_project = true;
		project.display_name = GLib.Path.get_basename(project_path);
		
		// Disable background recursion for testing
		OLLMfiles.Folder.background_recurse = false;
		
		// Save project to database
		project.saveToDB(db, null, false);
		manager.projects.append(project);
		
		// Scan directory and populate project files
		yield project.read_dir(new GLib.DateTime.now_local().to_unix(), true);
		
		// Count files
		int file_count = 0;
		foreach (var entry in project.project_files.child_map.entries) {
			file_count++;
		}
		
		stdout.printf("PROJECT_PATH: %s\n", project_path);
		stdout.printf("DATABASE_PATH: %s\n", db.filename);
		stdout.printf("FILE_COUNT: %d\n", file_count);
		stdout.printf("PROJECT_ID: %lld\n", project.id);
	}

	private async void run_info(OLLMfiles.ProjectManager manager) throws Error
	{
		string file_path = opt_info;
		
		// Try to get from active project first
		OLLMfiles.File? file = null;
		bool in_project = false;
		
		if (manager.active_project != null) {
			file = manager.get_file_from_active_project(file_path);
			in_project = (file != null);
		}
		
		// If not in project, try to create fake file
		if (file == null) {
			file = new OLLMfiles.File.new_fake(manager, file_path);
		}
		
		string backup_path = file.last_approved_copy_path != null && file.last_approved_copy_path != "" 
			? file.last_approved_copy_path 
			: "(none)";
		print(@"FILE: $(file_path)
FILE_ID: $(file.id)
IS_FAKE: $(file.id < 0 ? "true" : "false")
BUFFER_STATUS: $(file.buffer != null ? "exists" : "null")
IN_PROJECT: $(in_project ? "true" : "false")
BACKUP_PATH: $(backup_path)
");
	}

	/**
	 * Output project files in the format: %y %Ts %p is_ignored is_repo\n
	 * where %y = file type (f for file)
	 *       %Ts = modification time in seconds since epoch
	 *       %p = pathname from ProjectFile
	 *       is_ignored = whether file is ignored by git (0 or 1)
	 *       is_repo = whether parent folder is a repo (-1, 0, or 1)
	 */
	private void output_project_files(OLLMfiles.Folder project)
	{
		this.output_folder_recursive(project, project.path);
	}

	/**
	 * Recursively output all files and folders with their flags.
	 */
	private void output_folder_recursive(OLLMfiles.Folder folder, string base_path)
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
		
		print(@"d  $(relpath)   --- $(folder.last_modified)  $(folder.is_ignored ? " IGNORED " : "")$(folder.is_repo == 1 ? " REPO " : "")\n");
		
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
				this.output_folder_recursive(child_folder, base_path);
			} else if (child is OLLMfiles.File) {
				var child_file = child as OLLMfiles.File;
				print(@"f  $(child_relpath)   --- $(child_file.mtime_on_disk())  $(child_file.is_ignored ? " IGNORED " : "")\n");
			}
		}
	}
}

int main(string[] args)
{
	var app = new TestFiles();
	return app.run(args);
}











