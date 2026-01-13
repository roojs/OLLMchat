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

class TestBubble : TestAppBase
{
	private static string? opt_project = null;
	private static bool opt_allow_network = false;

	protected const string help = """
Usage: {ARG} --project=DIR <command>

Test tool for Bubble class (bubblewrap sandboxing).

Options:
  --project=DIR              Project directory path (required)
  --allow-network            Allow network access (default: false)

Arguments:
  command                    Command to execute in sandbox

Examples:
  {ARG} --project=/path/to/project "ls -la"
  {ARG} --project=/path/to/project "echo hello"
  {ARG} --project=/path/to/project --allow-network "curl https://example.com"
""";

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
		{ null }
	};

	protected override int run()
	{
		// Check if bubblewrap is available
		if (!OLLMtools.RunCommand.Bubble.can_wrap()) {
			stdout.printf("ERROR: bubblewrap is not available on this system.\n");
			stdout.printf("  - Make sure bwrap is installed and in PATH\n");
			stdout.printf("  - Note: bubblewrap is disabled when running inside Flatpak\n");
			return 1;
		}

		// Validate required arguments
		if (opt_project == null || opt_project == "") {
			stdout.printf("ERROR: --project is required\n");
			this.print_help();
			return 1;
		}

		// Get command from remaining arguments
		if (this.unowned_args.length < 2) {
			stdout.printf("ERROR: command argument is required\n");
			this.print_help();
			return 1;
		}

		var command = string.joinv(" ", this.unowned_args[1:this.unowned_args.length]);

		// Check if project directory exists
		if (!GLib.FileUtils.test(opt_project, GLib.FileTest.IS_DIR)) {
			stdout.printf("ERROR: Project directory does not exist: %s\n", opt_project);
			return 1;
		}

		// Create ProjectManager and load project
		var db = new SQ.Database(null); // In-memory database for testing
		var project_manager = new OLLMfiles.ProjectManager(db);
		
		// Create project folder
		var project = new OLLMfiles.Folder(project_manager);
		project.path = opt_project;
		project.is_project = true;
		
		// Load project files
		try {
			yield project.read_dir(new GLib.DateTime.now_local().to_unix(), true);
			yield project.load_files_from_db();
		} catch (GLib.Error e) {
			stdout.printf("ERROR: Failed to load project: %s\n", e.message);
			return 1;
		}

		// Create Bubble instance
		OLLMtools.RunCommand.Bubble bubble;
		try {
			bubble = new OLLMtools.RunCommand.Bubble(project, opt_allow_network);
		} catch (GLib.Error e) {
			stdout.printf("ERROR: Failed to create Bubble instance: %s\n", e.message);
			return 1;
		}

		// Execute command
		stdout.printf("Executing command in sandbox: %s\n", command);
		stdout.printf("Project: %s\n", opt_project);
		stdout.printf("Allow network: %s\n", opt_allow_network.to_string());
		stdout.printf("\n--- Output ---\n");

		string output;
		try {
			output = yield bubble.exec(command);
		} catch (GLib.Error e) {
			stdout.printf("ERROR: Command execution failed: %s\n", e.message);
			return 1;
		}

		// Print output
		stdout.printf("%s", output);
		stdout.printf("\n--- End Output ---\n");

		// Print property values for debugging
		stdout.printf("\n--- Debug Info ---\n");
		stdout.printf("ret_str length: %zu\n", bubble.ret_str.length);
		stdout.printf("fail_str length: %zu\n", bubble.fail_str.length);

		return 0;
	}

	private static int main(string[] args)
	{
		var app = new TestBubble();
		return app.run_with_args(args);
	}
}

