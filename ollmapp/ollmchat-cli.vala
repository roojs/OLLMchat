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
		private OLLMtools.Registry tools_registry { get; set; }
		private OLLMvector.Registry vector_registry { get; set; }
		
		protected string help { get; set; default = """
Usage: {ARG} [OPTIONS] [QUERY]

Send a query to the LLM or execute an agent tool.

Query Input:
  QUERY can be provided as leftover arguments, or:
  - If stdin has data (pipe/file): reads from stdin until EOF
  - If stdin is empty (interactive): prompts "Talk to me:" and reads one line

Examples:
  {ARG} "What is the capital of France?"
  {ARG} --model llama2 "Write a hello world program"
  {ARG} --agent-tool=codebase-locator --project=/path/to/project "Find all files related to authentication"
  {ARG} --agent-tool=codebase-analyzer --project=/path/to/project "Explain how the database connection is established"
  echo "Find files that handle user login" | {ARG} --agent-tool=codebase-locator --project=/path/to/project
"""; }
		
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
			this.tools_registry = new OLLMtools.Registry();
			this.vector_registry = new OLLMvector.Registry();
			this.tools_registry.init_config();
			this.vector_registry.init_config();
			
			// Load config (no vector types needed for simple CLI)
			this.config = this.load_config();
			if (this.config.loaded) {
				this.tools_registry.setup_config_defaults(this.config);
				this.vector_registry.setup_config_defaults(this.config);
			}
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
			
			// Check for help flag before parsing (to show custom help if available)
			if (this.check_help_arg(args)) {
				var custom_help = this.build_help_text(args[0]);
				command_line.print("%s", custom_help != null ? custom_help : "No help available");
				return 0;
			}
			
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
			
			// Get query from leftover arguments (current behavior), stdin, or interactive mode
			var query = args.length > 1 ? string.joinv(" ", args[1:args.length]).strip() : ""; 
			
			// If no query from args, try stdin or interactive mode
			if (query.length == 0) {
				// No leftover arguments: smart stdin detection (non-blocking check using GLib.IOChannel)
				try {
					var stdin_channel = new GLib.IOChannel.unix_new(Posix.STDIN_FILENO);
					stdin_channel.set_flags(GLib.IOFlags.NONBLOCK);
					if ((stdin_channel.get_buffer_condition() & GLib.IOCondition.IN) != 0) {
						// Stdin has data available (pipe/file) → read immediately and execute
						query = this.read_query_from_stdin();
					} else {
						// Stdin is empty → wait briefly (100ms), then prompt for interactive mode
						query = this.read_query_interactive();
					}
				} catch (Error e) {
					command_line.printerr("Error: %s\n", e.message);
					return 1;
				}
			}
			if (query == "") {
				command_line.printerr("Error: No query provided.\n");
				return 1;
			}
			
			// Validate --create-project is only used with --project
			if (opt_create_project && opt_project == "") {
				command_line.printerr("Error: --create-project can only be used with --project.\n");
				return 1;
			}
			
			// Validate --project is provided when using --agent-tool
			// Most agent tools require ProjectManager for tools like ReadFile, RunCommand, EditMode, CodebaseSearchTool
			bool use_agent_tool = (opt_agent_tool != "");
			if (use_agent_tool && opt_project == "") {
				command_line.printerr("Error: --project is required when using --agent-tool.\n");
				command_line.printerr("  Most agent tools require ProjectManager for file operations, codebase search, etc.\n");
				command_line.printerr("  Use --project=PATH or --project=PATH --create-project to specify a project.\n");
				return 1;
			}
			
			// Hold application and execute
			this.hold();
			if (use_agent_tool) {
				// Agent tool mode
				this.run_agent_tool.begin(opt_agent_tool, query, command_line, (obj, res) => {
					try {
						this.run_agent_tool.end(res);
					} catch (Error e) {
						command_line.printerr("Error: %s\n", e.message);
					} finally {
						this.release();
						this.quit();
					}
				});
				return 0;
			}
			
			// Standard agent mode (existing behavior)
			this.run_test.begin(query, command_line, (obj, res) => {
				try {
					this.run_test.end(res);
				} catch (Error e) {
					command_line.printerr("Error: %s\n", e.message);
				} finally {
					this.release();
					this.quit();
				}
			});
			return 0;
		}
		
		/**
		 * Returns custom help text for this application.
		 * If 'help' property is set, outputs it (with {ARG} replaced) followed by
		 * auto-generated options from GLib's OptionContext.
		 * 
		 * @param program_name The program name (args[0]) to use in help text
		 * @return Custom help text string, or null to use default auto-generated help
		 */
		private string? build_help_text(string program_name)
		{
			// Build OptionContext to get auto-generated options text
			var opt_context = new OptionContext("OLLMchat Test CLI - Test LLM interactions and agent tools");
			opt_context.set_help_enabled(true);
			opt_context.add_main_entries(options, null);
			
			// Use the method from ApplicationInterface
			return this.get_help_text(this.help, program_name, opt_context);
		}
		
		private string read_query_from_stdin() throws Error
		{
			// Read all lines from stdin (data is available)
			// Use plain string concatenation - building array just to join it is unnecessary
			string query = "";
			string? line;
			while ((line = GLib.stdin.read_line()) != null) {
				query += line + "\n";
			}
			
			query = query.strip();
			if (query == "") {
				throw new GLib.IOError.INVALID_ARGUMENT("No query provided");
			}
			
			return query;
		}
		
		private string read_query_interactive() throws Error
		{
			// Wait briefly (100ms) to see if data arrives (e.g., from pipe that hasn't started yet)
			Posix.usleep(100000); // 100ms wait (100000 microseconds)
			
			// Check if stdin has data available using GLib.IOChannel (non-blocking)
			var stdin_channel = new GLib.IOChannel.unix_new(Posix.STDIN_FILENO);
			stdin_channel.set_flags(GLib.IOFlags.NONBLOCK);
			if ((stdin_channel.get_buffer_condition() & GLib.IOCondition.IN) != 0) {
				// Data arrived during wait - use stdin mode instead
				return this.read_query_from_stdin();
			}
			
			// Still no data - enter interactive mode
			stdout.printf("Talk to me:\n");
			stdout.flush();
			
			// Use blocking IOChannel to read one line (will block until user presses Enter)
			var blocking_channel = new GLib.IOChannel.unix_new(Posix.STDIN_FILENO);
			// Don't set NONBLOCK flag - this makes it blocking
			blocking_channel.set_flags(GLib.IOFlags.NONE);
			
			string? line = null;
			size_t length = 0;
			var status = blocking_channel.read_line(out line, out length, null);
			
			if (status != GLib.IOStatus.NORMAL || line == null) {
				throw new GLib.IOError.INVALID_ARGUMENT("No query provided");
			}
			
			// Remove trailing newline if present
			string query = line.strip();
			if (query == "") {
				throw new GLib.IOError.INVALID_ARGUMENT("No query provided");
			}
			
			return query;
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
			// Phase 4: Use Manager's just-ask agent instead of creating Chat directly
			
			// Setup manager (creates Manager with session that has just-ask agent)
			yield this.setup_manager();
		
		// Register tools with manager (so agent has access to them)
		// For standard agent mode, project_manager can be null (tools will work in limited mode)
		this.tools_registry.fill_tools(this.manager, this.project_manager);
		this.vector_registry.fill_tools(this.manager, this.project_manager);
				
			// Ensure Manager's session has just-ask agent activated
			// Manager already registers "just-ask" agent in constructor and creates EmptySession
			// EmptySession is already activated in Manager constructor, but ensure agent_name is set
			if (this.manager.session.agent_name != "just-ask") {
				this.manager.session.agent_name = "just-ask";
			}
			this.manager.session.activate(); // Creates agent handler if needed
			
			// Override num_ctx if provided via command line
			// This needs to be set on the session's model_usage options
			if (opt_ctx_num != -1 && this.manager.session.model_usage != null) {
				if (this.manager.session.model_usage.options == null) {
					this.manager.session.model_usage.options = new OLLMchat.Call.Options();
				}
				this.manager.session.model_usage.options.num_ctx = opt_ctx_num;
			}
			
			stdout.printf("Query: %s\n\n", query);
			stdout.printf("Response:\n");
			
			// Create user message and send through Manager's session
			// Manager signals are already connected in setup_manager() for streaming output
			var user_message = new OLLMchat.Message("user", query);
			yield this.manager.send(this.manager.session, user_message, null);
			
			// Get final response from session messages
			// The agent will have added assistant message to session.messages
			// Get the last assistant message (most recent response)
			string result = "";
			for (int i = this.manager.session.messages.size - 1; i >= 0; i--) {
				var msg = this.manager.session.messages.get(i);
				if (msg.role == "assistant") {
					result = msg.content;
					break;
				}
			}
			
			stdout.printf("\n\n--- Complete Response ---\n");
			stdout.printf("Content: %s\n", result);
			
			// Handle --stats option
			// FIXME?  - stats are output at end of chat?
			// Note: For Manager-based flow, we don't have direct access to Chat response
			// Stats would need to be extracted from session messages or agent handler
			if (opt_stats != null && opt_stats != "") {
				GLib.warning("--stats option not yet supported with Manager-based flow");
			}
		}
		
		private async void run_agent_tool(string tool_name, string query, ApplicationCommandLine command_line) throws Error
		{
			// Setup manager
			yield this.setup_manager();
			
			// Setup project manager if needed (uses opt_project and opt_create_project from static variables)
			if (opt_project != "") {
				// Create database for ProjectManager
				yield this.setup_project_manager(
					new SQ.Database(
						GLib.Path.build_filename(this.data_dir, "files.sqlite")
					));
			}
			
		// Fill manager with tools (after project manager is set up)
		this.tools_registry.fill_tools(this.manager, this.project_manager);
		this.vector_registry.fill_tools(this.manager, this.project_manager);
			
			// Verify tool exists
			if (!this.manager.tools.has_key(tool_name)) {
				throw new GLib.IOError.NOT_FOUND(
					"Agent tool '%s' not found. Available tools: %s", 
					tool_name,
					string.joinv(", ", this.manager.tools.keys.to_array())
				);
			}
			
			// Ensure Manager's session has just-ask agent activated
			// Manager already registers "just-ask" agent in constructor
			if (this.manager.session.agent_name != "just-ask") {
				this.manager.session.agent_name = "just-ask";
			}
			this.manager.session.activate(); // Creates agent handler if needed
			
			// Override num_ctx if provided via command line
			// This needs to be set on the session's model_usage options
			if (opt_ctx_num != -1 && this.manager.session.model_usage != null) {
				if (this.manager.session.model_usage.options == null) {
					this.manager.session.model_usage.options = new OLLMchat.Call.Options();
				}
				this.manager.session.model_usage.options.num_ctx = opt_ctx_num;
			}
			
			// Get agent from Manager's session
			// Agent's chat() already has all tools from Manager copied (done in Agent.Base constructor)
			// Factory.configure_tools() is called but JustAsk doesn't filter, so all tools are available
			if (this.manager.session.agent == null) {
				throw new GLib.IOError.FAILED("Agent not available on session after activation");
			}
			
			// Manager signals are already connected in setup_manager()
			// No need to connect again here - Manager relays from active session automatically
			
			// Emulate calling the tool on the agent (same as if LLM requested it)
			stdout.printf("Executing agent tool: %s\n", tool_name);
			stdout.printf("Query: %s\n\n", query);
			stdout.printf("Response:\n");
			
			// Create ToolCall and execute via agent (emulates LLM tool call)
			var arguments = new Json.Object();
			arguments.set_string_member("query", query);
			var tool_call = new OLLMchat.Response.ToolCall() {
				id = "call_" + GLib.Uuid.string_random(),
				function = new OLLMchat.Response.CallFunction() {
					name = tool_name,
					arguments = arguments
				}
			};
			var tool_calls = new Gee.ArrayList<OLLMchat.Response.ToolCall>();
			tool_calls.add(tool_call);
			
			// Execute tool via agent (same flow as when LLM requests a tool)
			var tool_reply_messages = yield this.manager.session.agent.execute_tools(
				tool_calls);
			
			// Get result from tool reply message
			string result = "";
			if (tool_reply_messages.size > 0) {
				result = tool_reply_messages.get(0).content;
			}
			
			stdout.printf("\n\n--- Complete Response ---\n");
			stdout.printf("Result: %s\n", result);
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
