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

namespace OLLMapp
{

class OllmchatCliApp : Application, OLLMchat.ApplicationInterface
{
	private static bool opt_debug = false;
	private static string? opt_url = null;
	private static string? opt_api_key = null;
	private static string? opt_model = null;
	private static string? opt_stats = null;
	private static bool opt_list_models = false;
	private static int opt_ctx_num = -1;
	private static string? opt_agent_tool = null;
	private static string? opt_project = null;
	private static bool opt_create_project = false;
	
	public OLLMchat.Settings.Config2 config { get; set; }
	public string data_dir { get; set; }
	
	private OLLMchat.History.Manager? manager { get; set; default = null; }
	private OLLMfiles.ProjectManager? project_manager { get; set; default = null; }
	private ToolRegistry tools_registry { get; set; }
	
	const OptionEntry[] options = {
		{ "debug", 'd', 0, OptionArg.NONE, ref opt_debug, "Enable debug output", null },
		{ "url", 0, 0, OptionArg.STRING, ref opt_url, "Ollama server URL", "URL" },
		{ "api-key", 0, 0, OptionArg.STRING, ref opt_api_key, "API key (optional)", "KEY" },
		{ "model", 'm', 0, OptionArg.STRING, ref opt_model, "Model name", "MODEL" },
		{ "stats", 0, 0, OptionArg.STRING, ref opt_stats, "Output statistics from last message to file", "FILE" },
		{ "list-models", 0, 0, OptionArg.NONE, ref opt_list_models, "List available models and exit", null },
		{ "ctx-num", 0, 0, OptionArg.INT, ref opt_ctx_num, "Context window size in tokens (1K = 1024)", "NUM" },
		{ "agent-tool", 0, 0, OptionArg.STRING, ref opt_agent_tool, "Agent tool name to execute (optional)", "NAME" },
		{ "project", 'p', 0, OptionArg.STRING, ref opt_project, "Project directory path (REQUIRED with --agent-tool)", "PATH" },
		{ "create-project", 0, 0, OptionArg.NONE, ref opt_create_project, "Allow creating project if it doesn't exist (use with --project)", null },
		{ null }
	};
	
	public OllmchatCliApp()
	{
		Object(
			application_id: "org.roojs.ollmchat-cli",
			flags: GLib.ApplicationFlags.HANDLES_COMMAND_LINE
		);
		
		// Set up data_dir
		this.data_dir = GLib.Path.build_filename(
			GLib.Environment.get_home_dir(), ".local", "share", "ollmchat"
		);
		
		// Phase 1: Initialize tool config types (before loading config)
		this.tools_registry = new ToolRegistry();
		this.tools_registry.init_config();
		
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
		opt_stats = null;
		opt_list_models = false;
		opt_ctx_num = -1;
		opt_agent_tool = null;
		opt_project = null;
		opt_create_project = false;
		
		string[] args = command_line.get_arguments();
		var opt_context = new OptionContext("OLLMchat Test CLI - Test LLM interactions and agent tools");
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
		
		// Convert nullable options to empty strings to avoid null checks
		opt_model = opt_model == null ? "" : opt_model;
		opt_agent_tool = opt_agent_tool == null ? "" : opt_agent_tool;
		opt_project = opt_project == null ? "" : opt_project;
		
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
  --url=URL           Ollama server URL (required if config not found)
  --api-key=KEY       API key (optional)
  -m, --model=MODEL    Model name (overrides config)
  --stats=FILE         Output statistics from last message to file
  --list-models        List available models and exit
  --ctx-num=NUM        Context window size in tokens (1K = 1024)

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
	
	private async void setup_manager() throws Error
	{
		// Create Manager instance
		this.manager = new OLLMchat.History.Manager(this);
		
		// Connect to Manager signals for streaming output (works for both agent tool and standard agent modes)
		this.manager.stream_chunk.connect((new_text, is_thinking, response) => {
			if (!is_thinking) {  // Only output content, not thinking
				stdout.write(new_text.data);
				stdout.flush();
			}
		});
		
		// Connect to tool_message signal for tool status messages
		this.manager.tool_message.connect((message) => {
			stdout.printf("[Tool] %s\n", message.content);
			stdout.flush();
		});
		
		// Override model if --model option was provided (must be done before ensure_model_usage)
		// This ensures ensure_model_usage() verifies the command-line model, not the config model
		// Note: opt_model is converted to "" if null early in command_line() processing
		if (opt_model != "") {
			if (this.manager.default_model_usage != null) {
				this.manager.default_model_usage.model = opt_model;
			}
		}
		
		// Ensure model usage is valid
		// What it does:
		//   - Verifies that default_model_usage.model exists on the server connection
		//   - Calls verify_model() which checks if the model is available via API call
		// Error handling:
		//   - Throws GLib.IOError.FAILED if default_model_usage is null
		//   - Throws GLib.IOError.FAILED if model doesn't exist on the connection
		//   - Error message includes model name and connection URL for debugging
		yield this.manager.ensure_model_usage();
	}
	
	private async void setup_project_manager(SQ.Database db) throws Error
	{
		if (opt_project == "") {
			return; // No project manager needed
		}
		
		// Verify project directory exists
		if (!GLib.FileUtils.test(opt_project, GLib.FileTest.IS_DIR)) {
			throw new GLib.IOError.NOT_FOUND("Project directory does not exist: %s", opt_project);
		}
		
		// Create ProjectManager
		this.project_manager = new OLLMfiles.ProjectManager(db);
		
		// Load existing projects from database
		yield this.project_manager.load_projects_from_db();
		
		// Get project from database (if it exists)
		var project = this.project_manager.projects.path_map.get(opt_project);
		
		// Error: --create-project cannot be used with existing projects
		if (opt_create_project && project != null) {
			throw new GLib.IOError.EXISTS(
				"Project already exists: %s (id=%lld). " +
				"Cannot use --create-project with existing projects. " +
				"Remove --create-project flag to use the existing project.",
				opt_project,
				project.id
			);
		}
		
		// Error: Project doesn't exist and --create-project not provided
		if (project == null && !opt_create_project) {
			throw new GLib.IOError.NOT_FOUND(
				"Project not found in database: %s\n" +
				"  Projects must be created using the main application or use --create-project flag",
				opt_project
			);
		}
		
		// Create new project if it doesn't exist
		if (project == null) {
			project = new OLLMfiles.Folder(this.project_manager);
			project.path = opt_project;
			project.is_project = true;
			project.display_name = GLib.Path.get_basename(opt_project);
			
			// Save project to database
			project.saveToDB(db, null, false);
			this.project_manager.projects.append(project);
		}
		
		// Load existing project files from database first
		yield project.load_files_from_db();
		
		// Disable background recursion for CLI (faster, but may miss some files)
		OLLMfiles.Folder.background_recurse = false;
		
		// Scan directory and populate project files
		yield project.read_dir(new GLib.DateTime.now_local().to_unix(), true);
		
		// Activate the project so it becomes the active project
		yield this.project_manager.activate_project(project);
	}
	
	private async void run_test(string query, ApplicationCommandLine command_line) throws Error
	{
		// Use config from base class
		
		OLLMchat.Client client;
		
		// Shortest if first - config loaded
		if (this.config.loaded) {
			var model_usage = this.config.usage.get("default_model") as OLLMchat.Settings.ModelUsage;
			if (model_usage == null || model_usage.connection == "" || 
				!this.config.connections.has_key(model_usage.connection)) {
				throw new GLib.IOError.NOT_FOUND("default_model not configured in config.2.json");
			}
			client = new OLLMchat.Client(this.config.connections.get(model_usage.connection));
			
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
		 
			// Create client from usage
			var model_usage = this.config.usage.get("default_model") as OLLMchat.Settings.ModelUsage;
			if (model_usage == null || model_usage.connection == "" || 
				!this.config.connections.has_key(model_usage.connection)) {
				throw new GLib.IOError.FAILED("Failed to create client: default_model not configured");
			}
			client = new OLLMchat.Client(this.config.connections.get(model_usage.connection));
			
			// Save config since we created it
			try {
				this.config.save();
				GLib.debug("Saved config to %s", OLLMchat.Settings.Config2.config_path);
			} catch (GLib.Error e) {
				GLib.warning("Failed to save config: %s", e.message);
			}
		}
		
		// Create and initialize ConnectionModels for model information lookup
		var connection_models = new OLLMchat.Settings.ConnectionModels(this.config);
		// Refresh to load model details (needed for tool capability checks)
		try {
			yield connection_models.refresh();
		} catch (GLib.Error e) {
			GLib.warning("Failed to refresh connection models: %s", e.message);
		}
		
		// Get model from config
		var default_usage = this.config.usage.get("default_model") as OLLMchat.Settings.ModelUsage;
		if (default_usage == null || default_usage.model == "") {
			throw new GLib.IOError.NOT_FOUND("default_model not configured");
		}
		
		// Get options from config
		
		// Create Chat object with streaming enabled
		var chat = new OLLMchat.Call.Chat(client.connection, default_usage.model) {
			stream = true
		};
		chat.options = default_usage.options == null ?  new OLLMchat.Call.Options() : default_usage.options;
		
		// Override num_ctx if provided via command line
		chat.options.num_ctx = opt_ctx_num;
		
		// Phase 4: Customize model
		// Get model_obj from connection and call customize() to create temp model if needed
		var model_obj = client.connection.models.get(default_usage.model);
		try {
			chat.model = yield model_obj.customize(client.connection, chat.options);
		} catch (Error e) {
			GLib.warning("Failed to customize model '%s': %s. Using base model.", default_usage.model, e.message);
			// chat.model remains as the base model name
		}
		
		// Connect to chat signals for streaming output
		chat.stream_chunk.connect((new_text, is_thinking, response) => {
			stdout.write(new_text.data);
			stdout.flush();
		});
		
		// Add ReadFile tool to Chat
		chat.add_tool(new OLLMtools.ReadFile.Tool());
		
		stdout.printf("Query: %s\n\n", query);
		stdout.printf("Response:\n");
		
		// Add user message and execute chat
		chat.messages.add(new OLLMchat.Message("user", query));
		var response = yield chat.send(chat.messages, null);
		
		stdout.printf("\n\n--- Complete Response ---\n");
		if (response.thinking != "") {
			stdout.printf("Thinking: %s\n", response.thinking);
		}
		stdout.printf("Content: %s\n", response.message.content);
		stdout.printf("Done: %s\n", response.done.to_string());
		if (response.done_reason != null) {
			stdout.printf("Done Reason: %s\n", response.done_reason);
		}
		
		// Handle --stats option
		if (opt_stats != null && opt_stats != "") {
			this.write_stats(response, opt_stats);
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

} // namespace OLLMapp

int main(string[] args)
{
	var app = new OLLMapp.OllmchatCliApp();
	return app.run(args);
}
