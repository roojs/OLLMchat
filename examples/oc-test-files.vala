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
	private static string? opt_summarize = null;
	private static string? opt_edit = null;
	private static bool opt_edit_complete_file = false;
	private static bool opt_overwrite = false;

	protected override string help { get; set; default = """
Usage: {ARG} [OPTIONS] <action>

Test tool for file operations using libocfiles.

Actions (specify one):
  --ls [--ls-path=PATH]              List files in directory
  --read=PATH [--start-line=N] [--end-line=M] [--output=FILE]
                                      Read file with optional line ranges
  --write=PATH [--content=TEXT] [--content-file=FILE]
                                      Write file with backups
  --create-fake=PATH                  Create fake file (not in database)
  --check-project=PATH                Check if file is in active project
  --cleanup-backups                   Cleanup old backup files
  --list-buffers [--max-buffers=N]    List current file buffers
  --create-project=PATH               Create test project from directory
  --info=PATH                         Show file information
  --summarize=PATH                    Show file structure summary (tree-sitter based)
  --edit=PATH [--edit-complete-file] [--overwrite]
                                      Edit file (reads from stdin)

Examples:
  {ARG} --read=/path/to/file.txt --start-line=10 --end-line=20
  {ARG} --write=/path/to/file.txt --content="new content" --test-db=/tmp/test.db
  {ARG} --create-fake=/tmp/fake.txt --test-db=/tmp/test.db
  {ARG} --check-project=/path/to/file.txt --test-db=/tmp/test.db
  {ARG} --create-project=/path/to/project --test-db=/tmp/test.db
"""; }

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
		{ "summarize", 0, 0, OptionArg.STRING, ref opt_summarize, "Show file structure summary", "PATH" },
		{ "edit", 0, 0, OptionArg.STRING, ref opt_edit, "Edit file (reads from stdin)", "PATH" },
		{ "edit-complete-file", 0, 0, OptionArg.NONE, ref opt_edit_complete_file, "Enable complete file mode", null },
		{ "overwrite", 0, 0, OptionArg.NONE, ref opt_overwrite, "Allow overwriting existing files", null },
		{ null }
	};

	protected override OptionContext app_options()
	{
		var opt_context = new OptionContext(this.get_app_name());
		// Only include debug and debug-critical from base_options
		var base_opts = new OptionEntry[3];
		base_opts[0] = base_options[0];  // debug option
		base_opts[1] = base_options[1];  // debug-critical option
		base_opts[2] = { null };
		opt_context.add_main_entries(base_opts, null);
		
		var app_group = new OptionGroup("oc-test-files", "Test Files Options", "Show Test Files options");
		app_group.add_entries(local_options);
		opt_context.add_group(app_group);
		
		return opt_context;
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
		if (opt_summarize != null) {
			action_count++;
		}
		if (opt_edit != null) {
			action_count++;
		}
		
		if (action_count == 0) {
			return help.replace("{ARG}", args[0]);
		}
		if (action_count > 1) {
			return "Error: Multiple actions specified. Only one action is allowed at a time.\n";
		}
		
		return null;
	}

	protected override async void run_test(ApplicationCommandLine command_line, string[] remaining_args) throws Error
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
		
		// Set git provider to enable gitignore checking
		manager.git_provider = new OLLMcoder.GitProvider();
		
		// Load projects from database
		yield manager.load_projects_from_db();
		
		// Don't activate projects in test code - it triggers filesystem scanning
		// and database updates which are unwanted side effects. Operations can
		// work without active_project (they fall back to fake files or require explicit paths).
		
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
		} else if (opt_summarize != null) {
			yield this.run_summarize(manager);
		} else if (opt_edit != null) {
			yield this.run_edit(manager);
		}
	}

	private async void run_ls(OLLMfiles.ProjectManager manager) throws Error
	{
		OLLMfiles.Folder? project = null;
		var scan_path = GLib.Environment.get_current_dir();
		
		
		// Determine scan path
		if (opt_ls_path != null && opt_ls_path != "") {
			// Use provided path
			scan_path = GLib.Path.is_absolute(opt_ls_path) 
				? opt_ls_path 
				: GLib.Path.build_filename(GLib.Environment.get_current_dir(), opt_ls_path);
		} 
		
		// Normalize the path
		try {
			scan_path = GLib.File.new_for_path(scan_path).get_path();
		} catch (GLib.Error e) {
			throw new GLib.IOError.INVALID_ARGUMENT("Invalid path: " + scan_path);
		}
		
		// Try to find existing project in database
		project = manager.projects.path_map.get(scan_path);
		
		// Project must exist in database
		if (project == null) {
			throw new GLib.IOError.NOT_FOUND("Project not found in database: " + scan_path);
		}
		
		// Load existing project files from database first
		// This populates project.children so read_dir() can compare filesystem with database
		yield project.load_files_from_db();
		
		// Disable background recursion for testing (ensure it's off)
		var was_background = OLLMfiles.Folder.background_recurse;
		OLLMfiles.Folder.background_recurse = false;
		
		// Scan the filesystem to update project files
		// read_dir() automatically updates project_files when recursion completes
		yield project.read_dir(new GLib.DateTime.now_local().to_unix(), true);
		
		// Restore previous background setting
		OLLMfiles.Folder.background_recurse = was_background;
		
		// Output project files
		this.output_project_files(project);
		
		// Sync database to filesystem
		if (manager.db != null) {
			manager.db.backupDB();
		}
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
		// Note: Backups are now tracked in FileHistory table, not in file.last_approved_copy_path
		string backup_info = file.id < 0 
			? @"NO_BACKUP: fake_file
" 
			: @"BACKUP: tracked_in_file_history
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
		
		// Call cleanup with db and default max_deleted_days (30)
		yield OLLMfiles.FileHistory.cleanup_old_backups(db, 30);
		
		var cache_dir = GLib.Path.build_filename(
			GLib.Environment.get_home_dir(),
			".cache",
			"ollmchat",
			"edited"
		);
		
		print("BACKUP_DIR: " + cache_dir + "\n" +
			"AGE_THRESHOLD: 30 days\n" +
			"Cleanup completed (check logs for deleted files)\n");
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
		
		// Load existing projects from database first
		yield manager.load_projects_from_db();
		
		// Check if project already exists
		var existing_project = manager.projects.path_map.get(project_path);
		OLLMfiles.Folder project;
		if (existing_project != null) {
			// Project exists - use it
			project = existing_project;
			GLib.debug("oc-test-files: Using existing project '%s' (id=%lld)", project_path, project.id);
		} else {
			// Create a new Folder with is_project = true
			project = new OLLMfiles.Folder(manager);
			project.path = project_path;
			project.is_project = true;
			project.display_name = GLib.Path.get_basename(project_path);
			
			// Save project to database
			project.saveToDB(db, null, false);
			manager.projects.append(project);
		}
		
		// Disable background recursion for testing
		OLLMfiles.Folder.background_recurse = false;
		
		// Scan directory and populate project files
		yield project.read_dir(new GLib.DateTime.now_local().to_unix(), true);
		
		// Activate the project so it becomes the active project
		yield manager.activate_project(project);
		
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
		
		// Note: Backups are now tracked in FileHistory table, not in file.last_approved_copy_path
		print(@"FILE: $(file_path)
FILE_ID: $(file.id)
IS_FAKE: $(file.id < 0 ? "true" : "false")
BUFFER_STATUS: $(file.buffer != null ? "exists" : "null")
IN_PROJECT: $(in_project ? "true" : "false")
BACKUP_PATH: (tracked_in_file_history)
");
	}

	private async void run_summarize(OLLMfiles.ProjectManager manager) throws Error
	{
		string file_path = opt_summarize;
		
		// Try to get from active project first
		OLLMfiles.File? file = null;
		
		if (manager.active_project != null) {
			file = manager.get_file_from_active_project(file_path);
		}
		
		// If not in project, create fake file
		if (file == null) {
			file = new OLLMfiles.File.new_fake(manager, file_path);
		}
		
		// Create Summarize instance
		var summarizer = new OLLMtools.ReadFile.Summarize(file);
		
		// Generate summary
		var summary = yield summarizer.summarize();
		
		// Output summary
		print(summary);
	}

	private async void run_edit(OLLMfiles.ProjectManager manager) throws Error
	{
		string file_path = opt_edit;
		bool complete_file = opt_edit_complete_file;
		bool overwrite = opt_overwrite;
		
		// Read from stdin
		var lines = new GLib.StringBuilder();
		string? line;
		while ((line = GLib.stdin.read_line()) != null) {
			if (lines.len > 0) {
				lines.append_c('\n');
			}
			lines.append(line);
		}
		string stdin_content = lines.str;
		
		// Validate stdin is not empty
		if (stdin_content.length == 0) {
			throw new GLib.IOError.INVALID_ARGUMENT("Stdin is empty. Edit operations require input from stdin.");
		}
		
		// Get or create file
		OLLMfiles.File? file = null;
		if (manager.active_project != null) {
			file = manager.get_file_from_active_project(file_path);
		}
		if (file == null) {
			file = new OLLMfiles.File.new_fake(manager, file_path);
		}
		
		// Ensure buffer is created
		if (file.buffer == null) {
			manager.buffer_provider.create_buffer(file);
		}
		
		// Handle complete_file mode (early return)
		if (complete_file) {
			var file_exists = GLib.FileUtils.test(file_path, GLib.FileTest.IS_REGULAR);
			if (file_exists && !overwrite) {
				throw new GLib.IOError.EXISTS("File already exists: " + file_path + ". Use --overwrite to overwrite it.");
			}
			
			yield file.buffer.write(stdin_content);
			
			int line_count = file.buffer.get_line_count();
			// Note: Backups are now tracked in FileHistory table, not in file.last_approved_copy_path
			print("BACKUP: tracked_in_file_history\n" +
				"FILE: " + file_path + "\n" +
				"FILE_ID: " + file.id.to_string() + "\n" +
				"LINE_COUNT: " + line_count.to_string() + "\n" +
				"MODE: complete_file\n");
			return;
		}
		
		// Edit mode: parse JSON array of FileChange objects
		var changes = new Gee.ArrayList<OLLMfiles.FileChange>();
		
		try {
			var parser = new Json.Parser();
			parser.load_from_data(stdin_content, -1);
			var root = parser.get_root();
			
			if (root == null || root.get_node_type() != Json.NodeType.ARRAY) {
				throw new GLib.IOError.INVALID_ARGUMENT("Stdin must contain a JSON array of FileChange objects");
			}
			
			var array = root.get_array();
			for (uint i = 0; i < array.get_length(); i++) {
				var element_node = array.get_element(i);
				
				var change = Json.gobject_deserialize(typeof(OLLMfiles.FileChange), element_node) as OLLMfiles.FileChange;
				if (change == null) {
					throw new GLib.IOError.INVALID_ARGUMENT("Array element " + i.to_string() + " could not be deserialized as FileChange");
				}
				
				if (change.start < 1 || change.end < 1 || change.start > change.end) {
					throw new GLib.IOError.INVALID_ARGUMENT(
						"Invalid line range in element " + i.to_string() + ": start=" + change.start.to_string() +
						", end=" + change.end.to_string() + " (start must be >= 1, end must be >= start)"
					);
				}
				
				changes.add(change);
			}
		} catch (Error e) {
			throw new GLib.IOError.INVALID_ARGUMENT("Failed to parse JSON: " + e.message);
		}
		
		if (changes.size == 0) {
			throw new GLib.IOError.INVALID_ARGUMENT("No changes found in JSON array");
		}
		
		var file_exists = GLib.FileUtils.test(file_path, GLib.FileTest.IS_REGULAR);
		if (!file_exists) {
			throw new GLib.IOError.NOT_FOUND("File does not exist: " + file_path + ". Use --edit-complete-file to create a new file.");
		}
		
		if (!file.buffer.is_loaded) {
			yield file.buffer.read_async();
		}
		
		changes.sort((a, b) => {
			if (a.start < b.start) return 1;
			if (a.start > b.start) return -1;
			return 0;
		});
		
		yield file.buffer.apply_edits(changes);
		
		int line_count = file.buffer.get_line_count();
		// Note: Backups are now tracked in FileHistory table, not in file.last_approved_copy_path
		print("BACKUP: tracked_in_file_history\n" +
			"FILE: " + file_path + "\n" +
			"FILE_ID: " + file.id.to_string() + "\n" +
			"LINE_COUNT: " + line_count.to_string() + "\n" +
			"CHANGES_APPLIED: " + changes.size.to_string() + "\n" +
			"MODE: edit\n");
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











