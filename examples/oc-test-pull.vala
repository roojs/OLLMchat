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

class TestPullApp : Application
{
	private static bool opt_debug = false;
	private static string? opt_url = null;
	private static string? opt_api_key = null;
	private static string? opt_model = null;
	
	const OptionEntry[] options = {
		{ "debug", 'd', 0, OptionArg.NONE, ref opt_debug, "Enable debug output", null },
		{ "url", 0, 0, OptionArg.STRING, ref opt_url, "Ollama server URL", "URL" },
		{ "api-key", 0, 0, OptionArg.STRING, ref opt_api_key, "API key (optional)", "KEY" },
		{ "model", 'm', 0, OptionArg.STRING, ref opt_model, "Model name to pull", "MODEL" },
		{ null }
	};
	
	public TestPullApp()
	{
		Object(
			application_id: "org.roojs.oc-test-pull",
			flags: GLib.ApplicationFlags.HANDLES_COMMAND_LINE
		);
	}
	
	protected override int command_line(ApplicationCommandLine command_line)
	{
		// Reset static option variables at start of each command line invocation
		opt_debug = false;
		opt_url = null;
		opt_api_key = null;
		opt_model = null;
		
		string[] args = command_line.get_arguments();
		var opt_context = new OptionContext("OLLMchat Test Pull Tool");
		opt_context.set_help_enabled(true);
		opt_context.add_main_entries(options, null);
		
		try {
			unowned string[] unowned_args = args;
			opt_context.parse(ref unowned_args);
		} catch (OptionError e) {
			command_line.printerr("error: %s\n", e.message);
			command_line.printerr("Run '%s --help' to see a full list of available command line options.\n", args[0]);
			return 1;
		}
		
		if (opt_debug) {
			GLib.Log.set_default_handler((dom, lvl, msg) => {
				command_line.printerr("%s [%s] %s\n",
					(new DateTime.now_local()).format("%H:%M:%S.%f"),
					lvl.to_string(),
					msg);
			});
		}
		
		if (opt_model == null || opt_model == "") {
			var usage = @"Usage: $(args[0]) [OPTIONS] --model=MODEL

Test tool for ollama pull with streaming enabled.

Options:
  -d, --debug          Enable debug output
  --url=URL           Ollama server URL (required if config not found)
  --api-key=KEY       API key (optional)
  -m, --model=MODEL    Model name to pull (required)

Examples:
  $(args[0]) --model llama2
  $(args[0]) --debug --url http://localhost:11434/api --model llama2
";
			command_line.printerr("%s", usage);
			return 1;
		}
		
		// Hold the application to keep main loop running during async operations
		this.hold();
		
		this.run_test.begin(opt_model, command_line, (obj, res) => {
			try {
				this.run_test.end(res);
			} catch (Error e) {
				command_line.printerr("Error: %s\n", e.message);
			} finally {
				// Release hold and quit when done
				this.release();
				this.quit();
			}
		});
		
		return 0;
	}
	
	private async void run_test(string model_name, ApplicationCommandLine command_line) throws Error
	{
		// Load Config2
		var config_dir = GLib.Path.build_filename(
			GLib.Environment.get_home_dir(), ".config", "ollmchat"
		);
		OLLMchat.Settings.Config2.config_path = GLib.Path.build_filename(config_dir, "config.2.json");
		
		var config = OLLMchat.Settings.Config2.load();
		
		OLLMchat.Client client;
		
		// Shortest if first - config loaded
		if (config.loaded) {
			client = config.create_client("default_model");
			if (client == null) {
				throw new GLib.IOError.NOT_FOUND("default_model not configured in config.2.json");
			}
		} else {
			// Config not loaded - check if URL provided
			if (opt_url == null || opt_url == "") {
				command_line.printerr("Error: Config not found and --url not provided.\n");
				command_line.printerr("Please set up the server first or provide --url option.\n");
				throw new GLib.IOError.NOT_FOUND("Config not found and --url not provided");
			}
		 
			// Create connection from command line args
			var connection = new OLLMchat.Settings.Connection() {
				name = "CLI",
				url = opt_url,
				api_key = opt_api_key ?? "",
				is_default = true
			};
			
			// Add connection to config
			config.connections.set(opt_url, connection);
			
			// Test connection
			stdout.printf("Testing connection to %s...\n", opt_url);
			var test_client = new OLLMchat.Client(connection);
			try {
				yield test_client.version();
				stdout.printf("Connection successful.\n");
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("Failed to connect to server: %s", e.message);
			}
		 
			// Create client from connection
			client = new OLLMchat.Client(connection);
			
			// Save config since we created it
			try {
				config.save();
				GLib.debug("Saved config to %s", OLLMchat.Settings.Config2.config_path);
			} catch (GLib.Error e) {
				GLib.warning("Failed to save config: %s", e.message);
			}
		}
		
		stdout.printf("Pulling model: %s\n", model_name);
		stdout.printf("Streaming progress updates:\n\n");
		
		// Create Pull call
		var pull_call = new OLLMchat.Call.Pull(client, model_name) {
			stream = true
		};
		
		// Connect to progress signal to display chunks
		pull_call.progress_chunk.connect((chunk) => {
			// Parse and display progress information
			var generator = new Json.Generator();
			var chunk_node = new Json.Node(Json.NodeType.OBJECT);
			chunk_node.set_object(chunk);
			generator.set_root(chunk_node);
			var json_str = generator.to_data(null);
			
			// Extract key fields for display
			string status = "";
			if (chunk.has_member("status")) {
				status = chunk.get_string_member("status");
			}
			
			string digest = "";
			if (chunk.has_member("digest")) {
				digest = chunk.get_string_member("digest");
			}
			
			int64 completed = -1;
			if (chunk.has_member("completed")) {
				completed = chunk.get_int_member("completed");
			}
			
			int64 total = -1;
			if (chunk.has_member("total")) {
				total = chunk.get_int_member("total");
			}
			
			// Display progress information
			stdout.printf("Status: %s", status);
			if (digest != "") {
				stdout.printf(" | Digest: %s", digest);
			}
			if (completed >= 0 && total >= 0) {
				double percent = ((double)completed / (double)total) * 100.0;
				stdout.printf(" | Progress: %lld/%lld (%.1f%%)", completed, total, percent);
			}
			stdout.printf("\n");
			
			// Also print full JSON for debugging
			if (opt_debug) {
				stdout.printf("  Full JSON: %s\n", json_str);
			}
		});
		
		// Execute pull
		try {
			yield pull_call.exec_pull();
			
			stdout.printf("\nPull completed successfully!\n");
		} catch (GLib.IOError e) {
			if (e.code == GLib.IOError.CANCELLED) {
				stdout.printf("\nPull cancelled by user.\n");
			} else {
				throw e;
			}
		}
	}
}

int main(string[] args)
{
	var app = new TestPullApp();
	return app.run(args);
}

