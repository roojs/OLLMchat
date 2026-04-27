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
	/** Same grammar as run_command allow_write (colon-separated on Unix). Default project when omitted. */
	private static string? opt_allow_write = null;
	/** Optional: fs | no-fs | net | no-net — assert on Bubble.exec output (seccomp appendices). */
	private static string? opt_expect = null;

	/**
	 * Build write_array for Bubble (keep in sync with Request.execute allow_write parse).
	 */
	static string[] bubble_write_array_from_allow_write (string spec, bool have_project) throws GLib.Error
	{
		string[] wa = {};
		var aw_line = spec.strip ();
		aw_line = (aw_line == "") ? (have_project ? "project" : "no") : aw_line;
		var ar = aw_line.split (":");
		for (var i = 0; i < ar.length; i++) {
			var piece = ar[i].strip ();
			if (i == 0 && (piece.down () == "no" || piece.down () == "project")) {
				wa += piece.down ();
				break;
			}
			if (piece == "") {
				continue;
			}
			if (!GLib.Path.is_absolute (piece)) {
				throw new GLib.IOError.INVALID_ARGUMENT (
					"allow_write path must be absolute: " + piece);
			}
			wa += piece;
		}
		if (wa.length < 1) {
			throw new GLib.IOError.INVALID_ARGUMENT (
				"allow_write must be project/no or a list of absolute paths");
		}
		return wa;
	}

	static void assert_expect_on_output (string output, string expect, ApplicationCommandLine command_line) throws GLib.Error
	{
		switch (expect) {
		case "fs":
			if (!output.contains ("file operations were restricted")) {
				command_line.printerr (
					"EXPECT fs: output should contain seccomp file appendix (file operations were restricted)\n");
				throw new GLib.IOError.FAILED ("expectation fs failed");
			}
			break;
		case "no-fs":
			if (output.contains ("file operations were restricted")) {
				command_line.printerr ("EXPECT no-fs: unexpected seccomp file appendix in output\n");
				throw new GLib.IOError.FAILED ("expectation no-fs failed");
			}
			break;
		case "net":
			if (!output.contains ("Sandbox: networking was disabled")) {
				command_line.printerr (
					"EXPECT net: output should contain seccomp network appendix\n");
				throw new GLib.IOError.FAILED ("expectation net failed");
			}
			break;
		case "no-net":
			if (output.contains ("Sandbox: networking was disabled")) {
				command_line.printerr ("EXPECT no-net: unexpected network appendix in output\n");
				throw new GLib.IOError.FAILED ("expectation no-net failed");
			}
			break;
		default:
			command_line.printerr ("EXPECT: internal error unknown mode %s\n", expect);
			throw new GLib.IOError.FAILED ("expectation internal");
		}
	}

	protected override string help { get; set; default = """
Usage: {ARG} --project=DIR <command>

Test tool for Bubble class (bubblewrap sandboxing).

Arguments:
  command                    Command to execute in sandbox

Options:
  --allow-write=SPEC         Same as run_command allow_write (default project). Examples: project, no, /tmp, /tmp:/var/tmp
  --expect=MODE              After run, assert on output: fs | no-fs | net | no-net (seccomp appendices)

Examples:
  {ARG} --project=/path/to/project "ls -la"
  {ARG} --project=/path/to/project "echo hello"
  {ARG} --project=/path/to/project --allow-network "curl https://example.com"
  {ARG} --project=/path/to/project --test-db=/tmp/test.db "ls -la"
  {ARG} --project=/path --allow-write=project --expect=no-fs "echo ok"
  {ARG} --project=/path --allow-write=project --expect=fs "touch /etc/.oc-test-bubble-deleteme"
  {ARG} --project=/path --expect=net "curl -s -o /dev/null --connect-timeout 2 https://example.com"
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
		{ "allow-write", 0, 0, OptionArg.STRING, ref opt_allow_write, "allow_write token list (see --help)", "SPEC" },
		{ "expect", 0, 0, OptionArg.STRING, ref opt_expect, "Assert output: fs|no-fs|net|no-net", "MODE" },
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

		if (opt_expect != null && opt_expect != "") {
			if (!(opt_expect == "fs" || opt_expect == "no-fs" || opt_expect == "net" || opt_expect == "no-net")) {
				return "ERROR: --expect must be fs, no-fs, net, or no-net\n";
			}
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

		var write_spec = (opt_allow_write != null && opt_allow_write != "") ? opt_allow_write : "project";
		string[] write_array;
		try {
			write_array = bubble_write_array_from_allow_write (write_spec, true);
		} catch (GLib.Error pe) {
			command_line.printerr ("ERROR: --allow-write: %s\n", pe.message);
			throw pe;
		}

		// Create Bubble instance
		var bubble = new OLLMtools.RunCommand.Bubble (project, opt_allow_network, write_array);

		// Execute command
		stdout.printf ("Executing command in sandbox: %s\n", command);
		stdout.printf ("Project: %s\n", opt_project);
		stdout.printf ("Allow network: %s\n", opt_allow_network.to_string ());
		stdout.printf ("allow_write: %s\n", write_spec);
		if (opt_expect != null && opt_expect != "") {
			stdout.printf ("expect: %s\n", opt_expect);
		}
		stdout.printf ("\n--- Output ---\n");

		// Execute command
		var output = yield bubble.exec (command);

		// Print output
		stdout.printf ("%s", output);
		stdout.printf ("\n--- End Output ---\n");

		if (opt_expect != null && opt_expect != "") {
			assert_expect_on_output (output, (!) opt_expect, command_line);
			stdout.printf ("\n--- Expect ok (%s) ---\n", opt_expect);
		}

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

