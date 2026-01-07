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

class TestCliApp : Application, OLLMchat.ApplicationInterface
{
	private static bool opt_debug = false;
	private static string? opt_url = null;
	private static string? opt_api_key = null;
	private static string? opt_model = null;
	
	public OLLMchat.Settings.Config2 config { get; set; }
	public string data_dir { get; set; }
	
	const OptionEntry[] options = {
		{ "debug", 'd', 0, OptionArg.NONE, ref opt_debug, "Enable debug output", null },
		{ "url", 0, 0, OptionArg.STRING, ref opt_url, "Ollama server URL", "URL" },
		{ "api-key", 0, 0, OptionArg.STRING, ref opt_api_key, "API key (optional)", "KEY" },
		{ "model", 'm', 0, OptionArg.STRING, ref opt_model, "Model name", "MODEL" },
		{ null }
	};
	
	public TestCliApp()
	{
		Object(
			application_id: "org.roojs.oc-test-cli",
			flags: GLib.ApplicationFlags.HANDLES_COMMAND_LINE
		);
		
		// Set up data_dir
		this.data_dir = GLib.Path.build_filename(
			GLib.Environment.get_home_dir(), ".local", "share", "ollmchat"
		);
		
		// Load config (no vector types needed for simple CLI)
		this.config = this.load_config();
	}
	
	public OLLMchat.Settings.Config2 load_config()
	{
		return base_load_config();
	}
	
	protected override int command_line(ApplicationCommandLine command_line)
	{
		// Reset static option variables at start of each command line invocation
		opt_debug = false;
		opt_url = null;
		opt_api_key = null;
		opt_model = null;
		
		string[] args = command_line.get_arguments();
		var opt_context = new OptionContext("OLLMchat Test CLI");
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
		
		// Get remaining arguments as the query
		string query = "";
		if (args.length > 1) {
			// Join all remaining arguments as the query
			var query_parts = new Gee.ArrayList<string>();
			for (int i = 1; i < args.length; i++) {
				query_parts.add(args[i]);
			}
			query = string.joinv(" ", query_parts.to_array());
		}
		
		if (query == "") {
			var usage = @"Usage: $(args[0]) [OPTIONS] <query>

Send a query to the LLM and display the response.

Options:
  -d, --debug          Enable debug output
  --url=URL           Ollama server URL (required if config not found)
  --api-key=KEY       API key (optional)
  -m, --model=MODEL    Model name (overrides config)

Examples:
  $(args[0]) \"What is the capital of France?\"
  $(args[0]) --model llama2 \"Write a hello world program\"
  $(args[0]) --debug --url http://localhost:11434/api \"Tell me a joke\"
";
			command_line.printerr("%s", usage);
			return 1;
		}
		
		// Hold the application to keep main loop running during async operations
		this.hold();
		
		this.run_test.begin(query, command_line, (obj, res) => {
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
	
	private async void run_test(string query, ApplicationCommandLine command_line) throws Error
	{
		// Use config from base class
		
		OLLMchat.Client client;
		
		// Shortest if first - config loaded
		if (this.config.loaded) {
			client = this.config.create_client("default_model");
			if (client == null) {
				throw new GLib.IOError.NOT_FOUND("default_model not configured in config.2.json");
			}
			
			// Override model if provided (set on default_usage, not client)
			// Phase 3: model is not on Client, it's on Session/Chat
			if (opt_model != null) {
				var default_usage = config.usage.get("default_model") as OLLMchat.Settings.ModelUsage;
				if (default_usage != null) {
					default_usage.model = opt_model;
				}
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
			this.config.connections.set(opt_url, connection);
			
			// Test connection
			stdout.printf("Testing connection to %s...\n", opt_url);
			var test_client = new OLLMchat.Client(connection);
			try {
				yield test_client.version();
				stdout.printf("Connection successful.\n");
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("Failed to connect to server: %s", e.message);
			}
			
			// Check if default_model exists
			if (!this.config.usage.has_key("default_model")) {
				command_line.printerr("Error: default_model not configured in config.2.json.\n");
				command_line.printerr("Please configure default_model in the config file.\n");
				throw new GLib.IOError.NOT_FOUND("default_model not configured");
			}
			
			// Get usage object and apply command-line overrides if provided
			var default_usage = this.config.usage.get("default_model") as OLLMchat.Settings.ModelUsage;
			if (opt_model != null) {
				default_usage.model = opt_model;
			}
			
			// Verify model exists if specified
			if (default_usage.model != "") {
				stdout.printf("Verifying model '%s'...\n", default_usage.model);
				try {
					yield test_client.show_model(default_usage.model);
					stdout.printf("Model found.\n");
				} catch (GLib.Error e) {
					throw new GLib.IOError.FAILED("Model '%s' not found: %s", default_usage.model, e.message);
				}
			}
		 
			// Create client from usage
			client = this.config.create_client("default_model");
			if (client == null) {
				throw new GLib.IOError.FAILED("Failed to create client");
			}
			
			// Save config since we created it
			try {
				this.config.save();
				GLib.debug("Saved config to %s", OLLMchat.Settings.Config2.config_path);
			} catch (GLib.Error e) {
				GLib.warning("Failed to save config: %s", e.message);
			}
		}
		
		// Get model from config
		var default_usage = this.config.usage.get("default_model") as OLLMchat.Settings.ModelUsage;
		if (default_usage == null || default_usage.model == "") {
			throw new GLib.IOError.NOT_FOUND("default_model not configured");
		}
		string model = default_usage.model;
		
		// Get options from config
		var options = default_usage.options ?? new OLLMchat.Call.Options();
		
		// Create Chat object with streaming enabled
		var chat = new OLLMchat.Call.Chat(client.connection, model, options) {
			stream = true,
			permission_provider = new OLLMchat.ChatPermission.Dummy()
		};
		
		// Connect to client signals for streaming output
		client.stream_chunk.connect((new_text, is_thinking, response) => {
			stdout.write(new_text.data);
			stdout.flush();
		});
		
		// Add ReadFile tool to Chat
		chat.add_tool(new OLLMtools.ReadFile(client));
		
		stdout.printf("Query: %s\n\n", query);
		stdout.printf("Response:\n");
		
		// Add user message and execute chat
		chat.messages.add(new OLLMchat.Message(chat, "user", query));
		var response = yield chat.exec_chat();
		
		stdout.printf("\n\n--- Complete Response ---\n");
		if (response.thinking != "") {
			stdout.printf("Thinking: %s\n", response.thinking);
		}
		stdout.printf("Content: %s\n", response.message.content);
		stdout.printf("Done: %s\n", response.done.to_string());
		if (response.done_reason != null) {
			stdout.printf("Done Reason: %s\n", response.done_reason);
		}
	}
}

int main(string[] args)
{
	var app = new TestCliApp();
	return app.run(args);
}
