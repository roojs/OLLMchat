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

class TestCliApp : Application, OLLMchat.ApplicationInterface
{
	private static bool opt_debug = false;
	private static bool opt_legacy = false;
	private static string? opt_url = null;
	private static string? opt_api_key = null;
	private static string? opt_model = null;
	private static string? opt_stats = null;
	private static bool opt_list_models = false;
	private static int opt_ctx_num = -1;

	private OLLMchat.History.Manager? cli_manager;
	private bool cli_configure_on_activate;
	private bool cli_legacy_flag;
	private OLLMtools.Registry tools_registry { get; set; }
	private OLLMvector.Registry vector_registry { get; set; }
	private OLLMmcp.Registry mcp_registry { get; set; }
	
	public OLLMchat.Settings.Config2 config { get; set; }
	public string data_dir { get; set; }
	
	const OptionEntry[] options = {
		{ "debug", 'd', 0, OptionArg.NONE, ref opt_debug, "Enable debug output", null },
		{ "legacy", 0, 0, OptionArg.NONE, ref opt_legacy,
			"Use native /api/chat (Call.Chat) instead of v1 ChatCompletions", null },
		{ "url", 0, 0, OptionArg.STRING, ref opt_url, "Ollama server URL", "URL" },
		{ "api-key", 0, 0, OptionArg.STRING, ref opt_api_key, "API key (optional)", "KEY" },
		{ "model", 'm', 0, OptionArg.STRING, ref opt_model, "Model name", "MODEL" },
		{ "stats", 0, 0, OptionArg.STRING, ref opt_stats, "Output statistics from last message to file", "FILE" },
		{ "list-models", 0, 0, OptionArg.NONE, ref opt_list_models, "List available models and exit", null },
		{ "ctx-num", 0, 0, OptionArg.INT, ref opt_ctx_num, "Context window size in tokens (1K = 1024)", "NUM" },
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
		
		this.tools_registry = new OLLMtools.Registry();
		this.vector_registry = new OLLMvector.Registry();
		this.mcp_registry = new OLLMmcp.Registry();
		this.tools_registry.init_config();
		this.vector_registry.init_config();
		this.mcp_registry.init_config();
		
		this.config = this.load_config();
		this.tools_registry.setup_config_defaults(this.config);
		this.vector_registry.setup_config_defaults(this.config);
		this.mcp_registry.setup_config_defaults(this.config);
	}
	
	public OLLMchat.Settings.Config2 load_config()
	{
		return base_load_config();
	}
	
	protected override int command_line(ApplicationCommandLine command_line)
	{
		// Reset static option variables at start of each command line invocation
		opt_debug = false;
		opt_legacy = false;
		opt_url = null;
		opt_api_key = null;
		opt_model = null;
		opt_stats = null;
		opt_list_models = false;
		opt_ctx_num = -1;
		this.cli_manager = null;
		this.cli_configure_on_activate = false;
		this.cli_legacy_flag = false;
		
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
		
		// Handle --list-models early (before query processing)
		if (opt_list_models) {
			this.hold();
			this.list_models.begin(command_line, (obj, res) => {
				try {
					this.list_models.end(res);
				} catch (Error e) {
					command_line.printerr("Error: %s\n", e.message);
				} finally {
					this.release();
					this.quit();
				}
			});
			return 0;
		}
		
		if (query == "") {
			var usage = @"Usage: $(args[0]) [OPTIONS] <query>

Send a query to the LLM and display the response.

Options:
  -d, --debug          Enable debug output
  --legacy             Native Ollama /api/chat (Call.Chat); default is v1 ChatCompletions
  --url=URL           Ollama server URL (required if config not found)
  --api-key=KEY       API key (optional)
  -m, --model=MODEL    Model name (overrides config)
  --stats=FILE         Output statistics from last message to file
  --list-models        List available models and exit
  --ctx-num=NUM        Context window size in tokens (1K = 1024)

Examples:
  $(args[0]) \"What is the capital of France?\"
  $(args[0]) --model llama2 \"Write a hello world program\"
  $(args[0]) --debug --url http://127.0.0.1:11434/api \"Tell me a joke\"
  $(args[0]) --legacy --debug --url http://127.0.0.1:11434/api -m MODEL \"hi\"

Default (no --legacy): same hooks as the app — ChatCompletions → Agent → Session →
Manager.stream_chunk (CLI emulates ChatWidget). --legacy uses Call.Chat (/api/chat)
with the same Manager/Session/UI-hook path for A/B comparison.
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

	/**
	 * Emulates {@link OLLMchatGtk.ChatWidget} stream_chunk handling (no GTK):
	 * same is_running / done gate, stdout for visible output, GLib.debug when --debug.
	 */
	private void cli_emulate_chat_widget_stream(
		string new_text,
		bool is_thinking,
		OLLMchat.Response.Chat response,
		OLLMchat.History.SessionBase session
	)
	{
		if (!session.is_running && !response.done) {
			// GLib.debug(
			// 	"cli emulate ui: dropped is_running=false new_text.len=%u done=%s",
			// 	new_text.length,
			// 	response.done.to_string()
			// );
			return;
		}
		if (new_text.length > 0) {
			// GLib.debug(
			// 	"cli emulate ui: append len=%u is_thinking=%s done=%s",
			// 	new_text.length,
			// 	is_thinking.to_string(),
			// 	response.done.to_string()
			// );
			if (is_thinking) {
				stderr.write("[think] ".data);
			}
			stdout.write(new_text.data);
			stdout.flush();
		} else if (response.done) {
			// GLib.debug("cli emulate ui: done packet (new_text empty)");
		}
	}

	/**
	 * Swaps the session agent's chat call for legacy {@link Call.Chat} or v1
	 * {@link Call.ChatCompletions} while keeping the same Agent → Session → Manager path.
	 */
	private void cli_configure_chat_api(OLLMchat.History.Manager manager, bool legacy)
	{
		manager.session.ensure_agent_handler();
		var agent = manager.session.agent;
		var usage = manager.session.model_usage;
		var connection = manager.config.connections.get(usage.connection);
		bool supports_thinking = usage.model_obj != null && usage.model_obj.is_thinking;

		OLLMchat.Call.ChatBase chat;
		if (legacy) {
			chat = new OLLMchat.Call.Chat(connection, usage.model) {
				stream = true,
				think = supports_thinking,
				options = usage.options,
				agent = agent
			};
		} else {
			chat = new OLLMchat.Call.ChatCompletions(connection, usage.model) {
				stream = true,
				think = supports_thinking,
				options = usage.options,
				agent = agent
			};
		}

		if (usage.model_obj == null || usage.model_obj.can_call) {
			foreach (var entry in manager.tools.entries) {
				chat.tools.set(entry.key, entry.value);
			}
			var agent_name = manager.session.agent_name == "" ?
				"just-ask" : manager.session.agent_name;
			var factory = manager.agent_factories.get(agent_name);
			if (factory == null) {
				factory = manager.agent_factories.get("just-ask");
			}
			factory.configure_tools(chat);
		}

		agent.replace_chat(chat);
		// GLib.debug("cli_configure_chat_api: legacy=%s", legacy.to_string());
	}

	private void on_session_activated_configure(OLLMchat.History.SessionBase session)
	{
		if (!this.cli_configure_on_activate || this.cli_manager == null) {
			return;
		}
		this.cli_configure_on_activate = false;
		this.cli_manager.session_activated.disconnect(this.on_session_activated_configure);
		this.cli_configure_chat_api(this.cli_manager, this.cli_legacy_flag);
	}

	/** Prints session message roles/lengths for comparing legacy vs v1 runs. */
	private void cli_print_session_messages(
		OLLMchat.History.SessionBase session,
		string api_label
	)
	{
		// stdout.printf("\n--- Session messages (%s) ---\n", api_label);
		// stdout.printf("%-18s %7s %7s %s\n", "role", "content", "think", "preview");
		// foreach (var m in session.messages) {
		// 	string preview = m.content;
		// 	if (preview.length > 72) {
		// 		preview = preview.substring(0, 72).replace("\n", "\\n") + "...";
		// 	} else {
		// 		preview = preview.replace("\n", "\\n");
		// 	}
		// 	stdout.printf(
		// 		"%-18s %7u %7u %s\n",
		// 		m.role,
		// 		m.content.length,
		// 		m.thinking.length,
		// 		preview
		// 	);
		// }
	}

	private async void run_test(string query, ApplicationCommandLine command_line) throws Error
	{
		// Use config from base class
		
		// Shortest if first - config loaded
		if (this.config.loaded) {
			var model_usage = this.config.usage.get("default_model") as OLLMchat.Settings.ModelUsage;
			if (model_usage == null || model_usage.connection == "" || 
				!this.config.connections.has_key(model_usage.connection)) {
				throw new GLib.IOError.NOT_FOUND("default_model not configured in config.2.json");
			}
			
			// Override model if provided (set on default_usage)
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
			var original_timeout = connection.timeout;
			connection.timeout = 5;  // 5 seconds - connection check should be quick
			try {
				var models_call = new OLLMchat.Call.Models(connection);
				var models = yield models_call.exec_models();
				stdout.printf("Connection successful (found %d models).\n", models.size);
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("Failed to connect to server: %s", e.message);
			} finally {
				connection.timeout = original_timeout;
			}
			
			// Mark connection as working so ConnectionModels will process it
			connection.is_working = true;
			
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
					var show_call = new OLLMchat.Call.ShowModel(connection, default_usage.model);
					yield show_call.exec_show();
					stdout.printf("Model found.\n");
				} catch (GLib.Error e) {
					throw new GLib.IOError.FAILED("Model '%s' not found: %s", default_usage.model, e.message);
				}
			}
		 
			// Save config since we created it
			try {
				this.config.save();
				GLib.debug("Saved config to %s", OLLMchat.Settings.Config2.config_path);
			} catch (GLib.Error e) {
				GLib.warning("Failed to save config: %s", e.message);
			}
		}

		// --url overrides default_model.connection (even when config loaded) for local repro
		if (opt_url != null && opt_url.strip() != "") {
			var url = opt_url.strip();
			if (!this.config.connections.has_key(url)) {
				this.config.connections.set(url, new OLLMchat.Settings.Connection() {
					name = "CLI",
					url = url,
					api_key = opt_api_key ?? "",
					is_default = true,
					is_working = true
				});
			} else {
				this.config.connections.get(url).is_working = true;
			}
			var usage_override = this.config.usage.get("default_model")
				as OLLMchat.Settings.ModelUsage;
			if (usage_override == null) {
				throw new GLib.IOError.NOT_FOUND("default_model not configured");
			}
			usage_override.connection = url;
			if (opt_model != null) {
				usage_override.model = opt_model;
			}
		}
		
		// Manager → Session → Agent → ChatBase (ChatCompletions or Call.Chat with --legacy).
		var manager = new OLLMchat.History.Manager(this);
		this.tools_registry.fill_tools(manager, null);
		this.vector_registry.fill_tools(manager, null);
		this.mcp_registry.fill_tools(manager, null);
		if (opt_debug) {
			GLib.debug("registered %u tools on manager", manager.tools.size);
		}
		try {
			yield manager.connection_models.refresh();
		} catch (GLib.Error e) {
			GLib.warning("Failed to refresh connection models: %s", e.message);
		}
		yield manager.ensure_model_usage();

		if (opt_ctx_num >= 0 && manager.session.model_usage != null) {
			if (manager.session.model_usage.options == null) {
				manager.session.model_usage.options = new OLLMchat.Call.Options();
			}
			manager.session.model_usage.options.num_ctx = opt_ctx_num;
		}

		// manager.stream_start.connect(() => {
		// 	GLib.debug("cli emulate ui: manager stream_start");
		// });
		manager.stream_chunk.connect((new_text, is_thinking, response) => {
			this.cli_emulate_chat_widget_stream(
				new_text,
				is_thinking,
				response,
				manager.session
			);
		});

		this.cli_manager = manager;
		this.cli_legacy_flag = opt_legacy;
		if (manager.session is OLLMchat.History.EmptySession) {
			this.cli_configure_on_activate = true;
			manager.session_activated.connect(this.on_session_activated_configure);
		} else {
			this.cli_configure_chat_api(manager, opt_legacy);
		}

		// var api_label = opt_legacy ?
		// 	"legacy /api/chat (Call.Chat)" :
		// 	"v1 /chat/completions (ChatCompletions, app default)";

		// stdout.printf("API mode: %s\n", api_label);
		stdout.printf("Query: %s\n\n", query);
		stdout.printf("Response:\n");

		yield manager.send(manager.session, new OLLMchat.Message("user", query));

		var content = "";
		var thinking = "";
		foreach (var m in manager.session.messages) {
			if (m.role == "content-stream") {
				content += m.content;
			} else if (m.role == "think-stream") {
				thinking += m.content;
			}
		}

		stdout.printf("\n\n--- Complete Response ---\n");
		if (thinking != "") {
			stdout.printf("Thinking: %s\n", thinking);
		}
		stdout.printf("Content: %s\n", content);

		// this.cli_print_session_messages(manager.session, api_label);

		if (opt_stats != null && opt_stats != "") {
			var stats_response = new OLLMchat.Response.Chat(null, null);
			stats_response.message = new OLLMchat.Message("assistant", content);
			stats_response.thinking = thinking;
			stats_response.done = true;
			this.write_stats(stats_response, opt_stats);
		}
	}
	
	private async void list_models(ApplicationCommandLine command_line) throws Error
	{
		OLLMchat.Settings.Connection connection;
		
		// Get connection
		if (this.config.loaded) {
			var model_usage = this.config.usage.get("default_model") as OLLMchat.Settings.ModelUsage;
			if (model_usage == null || model_usage.connection == "" || 
				!this.config.connections.has_key(model_usage.connection)) {
				throw new GLib.IOError.NOT_FOUND("default_model not configured in config.2.json");
			}
			connection = this.config.connections.get(model_usage.connection);
		} else {
			// Config not loaded - check if URL provided
			if (opt_url == null || opt_url == "") {
				command_line.printerr("Error: Config not found and --url not provided.\n");
				command_line.printerr("Please set up the server first or provide --url option.\n");
				throw new GLib.IOError.NOT_FOUND("Config not found and --url not provided");
			}
			
			// Create connection from command line args
			connection = new OLLMchat.Settings.Connection() {
				name = "CLI",
				url = opt_url,
				api_key = opt_api_key ?? "",
				is_default = true
			};
			
			// Add connection to config
			this.config.connections.set(opt_url, connection);
			
			// Test connection
			var original_timeout = connection.timeout;
			connection.timeout = 5;  // 5 seconds - connection check should be quick
			try {
				var models_call = new OLLMchat.Call.Models(connection);
				yield models_call.exec_models();
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("Failed to connect to server: %s", e.message);
			} finally {
				connection.timeout = original_timeout;
			}
		}
		
		// List models
		var models_call = new OLLMchat.Call.Models(connection);
		var models = yield models_call.exec_models();
		foreach (var model in models) {
			stdout.printf("%s\n", model.name);
		}
	}
	
	private void write_stats(OLLMchat.Response.Chat response, string file_path) throws Error
	{
		var file = GLib.File.new_for_path(file_path);
		
		// Serialize response to JSON (no pretty printing)
		var json_node = Json.gobject_serialize(response);
		var generator = new Json.Generator();
		generator.pretty = false;  // No pretty printing
		generator.set_root(json_node);
		var json_str = generator.to_data(null);
		
		try {
			file.replace_contents(
				json_str.data,
				null,
				false,
				GLib.FileCreateFlags.NONE,
				null
			);
		} catch (GLib.Error e) {
			throw new GLib.IOError.FAILED("Failed to write stats to file: %s", e.message);
		}
	}
}

int main(string[] args)
{
	var app = new TestCliApp();
	return app.run(args);
}
