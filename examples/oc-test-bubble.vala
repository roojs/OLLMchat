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

	protected override OptionEntry[] get_options()
	{
		// Only include debug and debug-critical from base_options, skip url/api-key/model since we don't need LLM connection
		// debug + debug-critical + all local options (which includes null)
		var options = new OptionEntry[2 + local_options.length];
		options[0] = base_options[0];  // debug option
		options[1] = base_options[1];  // debug-critical option
		
		// Copy all local options (includes null terminator)
		for (int j = 0; j < local_options.length; j++) {
			options[2 + j] = local_options[j];
		}
		
		return options;
	}

	protected override string? validate_args(string[] args)
	{
		// Validate required arguments
		if (opt_project == null || opt_project == "") {
			return "ERROR: --project is required\n";
		}

		// Get command from remaining arguments (skip program name)
		if (args.length < 2) {
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

		// Create ProjectManager and load project
		var db = new SQ.Database(null); // In-memory database for testing
		var project_manager = new OLLMfiles.ProjectManager(db);
		
		// Create project folder
		var project = new OLLMfiles.Folder(project_manager);
		project.path = opt_project;
		project.is_project = true;
		
		// Load project files
		yield project.read_dir(new GLib.DateTime.now_local().to_unix(), true);
		yield project.load_files_from_db();

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
	}
}

int main(string[] args)
{
	var app = new TestBubble();
	return app.run(args);
}

