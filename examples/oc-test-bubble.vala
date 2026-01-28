/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
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

class TestBubble : TestAppBase
{
	private static string? opt_project = null;
	private static bool opt_allow_network = false;
	private static string? opt_test_db = null;

	protected override string help { get; set; default = """
Usage: {ARG} --project=DIR <command>

Test tool for Bubble class (bubblewrap sandboxing).

Arguments:
  command                    Command to execute in sandbox

Examples:
  {ARG} --project=/path/to/project "ls -la"
  {ARG} --project=/path/to/project "echo hello"
  {ARG} --project=/path/to/project --allow-network "curl https://example.com"
  {ARG} --project=/path/to/project --test-db=/tmp/test.db "ls -la"
"""; }

	public TestBubble()
	{
		base("com.roojs.ollmchat.test-bubble");
	}

	protected override string get_app_name()
	{
		return "oc-test-bubble";
	}

	private const OptionEntry[] local_options = {
		{ "project", 'p', 0, OptionArg.STRING, ref opt_project, "Project directory path", "DIR" },
		{ "allow-network", 0, 0, OptionArg.NONE, ref opt_allow_network, "Allow network access", null },
		{ "test-db", 0, 0, OptionArg.STRING, ref opt_test_db, "Specify test database path instead of standard database (optional, for testing only)", "PATH" },
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
		
		var app_group = new OptionGroup("oc-test-bubble", "Test Bubble Options", "Show Test Bubble options");
		app_group.add_entries(local_options);
		opt_context.add_group(app_group);
		
		return opt_context;
	}

	protected override string? validate_args(string[] remaining_args)
	{
		// Validate required arguments
		if (opt_project == null || opt_project == "") {
			return "ERROR: --project is required\n";
		}

		// Get command from remaining arguments (skip program name)
		if (remaining_args.length < 2) {
			return "ERROR: command argument is required\n";
		}

		// Check if project directory exists
		if (!GLib.FileUtils.test(opt_project, GLib.FileTest.IS_DIR)) {
			return "ERROR: Project directory does not exist: %s\n".printf(opt_project);
		}

		return null;
	}

	protected override async void run_test(ApplicationCommandLine command_line, string[] remaining_args) throws Error
	{
		// Check if bubblewrap is available
		if (!OLLMtools.RunCommand.Bubble.can_wrap()) {
			command_line.printerr("ERROR: bubblewrap is not available on this system.\n");
			command_line.printerr("  - Make sure bwrap is installed and in PATH\n");
			command_line.printerr("  - Note: bubblewrap is disabled when running inside Flatpak\n");
			throw new GLib.IOError.NOT_FOUND("bubblewrap not available");
		}

		// Get command from remaining arguments (skip program name)
		var command = string.joinv(" ", remaining_args[1:remaining_args.length]);
		GLib.debug("oc-test-bubble: command to execute: %s", command);

		// Determine database path
		string db_path;
		if (opt_test_db != null && opt_test_db != "") {
			db_path = opt_test_db;
		} else {
			// Use main database (normal operation)
			db_path = GLib.Path.build_filename(this.data_dir, "files.sqlite");
		}

		// Create ProjectManager and load project
		var db = new SQ.Database(db_path, false);
		var project_manager = new OLLMfiles.ProjectManager(db);
		// Note: git_provider defaults to GitProviderBase (dummy implementation) - no need to set it
		
		// Load existing projects from database first
		yield project_manager.load_projects_from_db();
		
		// Check if project already exists in database
		var project = project_manager.projects.path_map.get(opt_project);
		
		// Error out first if using standard database and project doesn't exist
		if (project == null && (opt_test_db == null || opt_test_db == "")) {
			command_line.printerr("ERROR: Project not found in database: %s\n", opt_project);
			command_line.printerr("  Projects must be created using the main application or oc-test-files\n");
			throw new GLib.IOError.NOT_FOUND("Project not found in database: " + opt_project);
		}
		
		// Create project if it doesn't exist (only when using test database)
		if (project == null) {
			project = new OLLMfiles.Folder(project_manager);
			project.path = opt_project;
			project.is_project = true;
			project.display_name = GLib.Path.get_basename(opt_project);
			
			// Save project to database before scanning
			project.saveToDB(db, null, false);
			project_manager.projects.append(project);
		}
		
		// Load existing project files from database first
		// This populates project.children so read_dir() can compare filesystem with database
		yield project.load_files_from_db();
		
		// Disable background recursion for testing (ensure it's off)
		OLLMfiles.Folder.background_recurse = false;
		
		// Scan the filesystem to update project files
		// read_dir() automatically updates project_files when recursion completes
		yield project.read_dir(new GLib.DateTime.now_local().to_unix(), true);
		
		// Update ProjectFiles to ensure folder_map is populated with all folders
		// This is critical - Scan needs parent folders to exist in folder_map
		project.project_files.update_from(project);

		// Create Bubble instance
		var bubble = new OLLMtools.RunCommand.Bubble(project, opt_allow_network);

		// Execute command
		stdout.printf("Executing command in sandbox: %s\n", command);
		stdout.printf("Project: %s\n", opt_project);
		stdout.printf("Allow network: %s\n", opt_allow_network.to_string());
		stdout.printf("\n--- Output ---\n");

		// Execute command
		var output = yield bubble.exec(command);

		// Print output
		stdout.printf("%s", output);
		stdout.printf("\n--- End Output ---\n");

		// Print property values for debugging
		stdout.printf("\n--- Debug Info ---\n");
		stdout.printf("ret_str length: %zu\n", bubble.ret_str.length);
		stdout.printf("fail_str length: %zu\n", bubble.fail_str.length);
		if (bubble.fail_str.length > 0) {
			// Show content with visible representation
			stdout.printf("fail_str content (raw): [%s]\n", bubble.fail_str);
			// Show hex dump of first 100 bytes to see non-printable characters
			var preview_len = (int)int.min(bubble.fail_str.length, 100);
			stdout.printf("fail_str hex (first %d bytes): ", preview_len);
			unowned uint8[] data = bubble.fail_str.data;
			for (int i = 0; i < preview_len; i++) {
				stdout.printf("%02x ", data[i]);
				if ((i + 1) % 16 == 0) {
					stdout.printf("\n");
				}
			}
			if (preview_len % 16 != 0) {
				stdout.printf("\n");
			}
		}
	}
}

int main(string[] args)
{
	var app = new TestBubble();
	return app.run(args);
}

