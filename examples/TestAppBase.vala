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

/**
 * Base class for OLLMchat test applications.
 * 
 * Handles common functionality like command-line options, config loading,
 * and client setup. Subclasses implement run_test() to perform the actual test.
 */
	public abstract class TestAppBase : Application, OLLMchat.ApplicationInterface
	{
		protected static bool opt_debug = false;
		protected static bool opt_debug_critical = false;
		protected static string? opt_url = null;
		protected static string? opt_api_key = null;
		protected static string? opt_model = null;
		
		public OLLMchat.Settings.Config2 config { get; set; }
		public string data_dir { get; set; }
		
		protected const OptionEntry[] base_options = {
			{ "debug", 'd', 0, OptionArg.NONE, ref opt_debug, "Enable debug output", null },
			{ "debug-critical", 0, 0, OptionArg.NONE, ref opt_debug_critical, "Treat critical warnings as errors", null },
			{ "url", 0, 0, OptionArg.STRING, ref opt_url, "Ollama server URL", "URL" },
			{ "api-key", 0, 0, OptionArg.STRING, ref opt_api_key, "API key (optional)", "KEY" },
			{ "model", 'm', 0, OptionArg.STRING, ref opt_model, "Model name", "MODEL" },
			{ null }
		};
		
		protected TestAppBase(string application_id)
		{
			Object(
				application_id: application_id,
				flags: GLib.ApplicationFlags.HANDLES_COMMAND_LINE
			);
			
			// Set up data_dir
			this.data_dir = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), ".local", "share", "ollmchat"
			);
			
			// Load config after any type registrations (subclasses can override load_config)
			this.config = this.load_config();
		}
		
		public virtual OLLMchat.Settings.Config2 load_config()
		{
			return base_load_config();
		}
		
		
		protected override int command_line(ApplicationCommandLine command_line)
		{
			// Reset static option variables at start of each command line invocation
			opt_debug = false;
			opt_debug_critical = false;
			opt_url = null;
			opt_api_key = null;
			opt_model = null;
			
			string[] args = command_line.get_arguments();
			var opt_context = new OptionContext(this.get_app_name());
			opt_context.set_help_enabled(true);
			opt_context.add_main_entries(this.get_options(), null);
			
			// Parse options - this modifies the array in place to remove parsed options
			unowned string[] remaining_args = args;
			try {
				opt_context.parse(ref remaining_args);
			} catch (OptionError e) {
				command_line.printerr("error: %s\n", e.message);
				command_line.printerr("Run '%s --help' to see a full list of available command line options.\n", args[0]);
				return 1;
			}
			
			// remaining_args now contains only the positional arguments (excluding parsed options)
			// Create a copy to pass to run_test
			string[] remaining_args_copy = {};
			foreach (var arg in remaining_args) {
				remaining_args_copy += arg;
			}
			
			// Set debug flags and let ApplicationInterface.debug_log handle everything
			OLLMchat.debug_on = opt_debug;
			OLLMchat.debug_critical_enabled = opt_debug_critical;
			
			// Set up log handler - ApplicationInterface.debug_log will decide what to output
			GLib.Log.set_default_handler((dom, lvl, msg) => {
				OLLMchat.ApplicationInterface.debug_log(this.get_application_id(), dom, lvl, msg);
			});
			
			// Validate arguments
			string? validation_error = this.validate_args(args);
			if (validation_error != null) {
				command_line.printerr("%s", validation_error);
				return 1;
			}
			
			// Hold the application to keep main loop running during async operations
			this.hold();
			
			this.run_test.begin(command_line, remaining_args_copy, (obj, res) => {
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
		 * Returns the application name for help text.
		 * Override to customize.
		 */
		protected virtual string get_app_name()
		{
			return "OLLMchat Test Tool";
		}
		
		/**
		 * Returns the command-line options for this application.
		 * Override to add additional options beyond the base ones.
		 */
		protected virtual OptionEntry[] get_options()
		{
			return base_options;
		}
		
		/**
		 * Validates command-line arguments.
		 * Override to add custom validation.
		 * 
		 * @return Error message string if validation fails, null if valid
		 */
		protected virtual string? validate_args(string[] args)
		{
			return null;
		}
		
		/**
		 * Sets up and returns a Client instance.
		 * 
		 * Handles loading config, creating connections from command-line args,
		 * and testing the connection.
		 * 
		 * @param command_line The ApplicationCommandLine for output
		 * @return Configured Client instance
		 * @throws Error if setup fails
		 */
		protected async OLLMchat.Client setup_client(ApplicationCommandLine command_line) throws Error
		{
			// Use config from interface
			var config = this.config;
			
			OLLMchat.Client client;
			
			// Shortest if first - config loaded
			if (config.loaded) {
				var model_usage = config.usage.get("default_model") as OLLMchat.Settings.ModelUsage;
				if (model_usage == null || model_usage.connection == "" || 
					!config.connections.has_key(model_usage.connection)) {
					throw new GLib.IOError.NOT_FOUND("default_model not configured in config.2.json");
				}
				client = new OLLMchat.Client(config.connections.get(model_usage.connection));
				
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
				config.connections.set(opt_url, connection);
				
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
			 
				// Check if default_model exists
				if (!config.usage.has_key("default_model")) {
					command_line.printerr("Error: default_model not configured in config.2.json.\n");
					command_line.printerr("Please configure default_model in the config file.\n");
					throw new GLib.IOError.NOT_FOUND("default_model not configured");
				}
				
				// Get usage object and apply command-line overrides if provided
				var default_usage = config.usage.get("default_model") as OLLMchat.Settings.ModelUsage;
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
				var model_usage = config.usage.get("default_model") as OLLMchat.Settings.ModelUsage;
				if (model_usage == null || model_usage.connection == "" || 
					!config.connections.has_key(model_usage.connection)) {
					throw new GLib.IOError.FAILED("Failed to create client: default_model not configured");
				}
				client = new OLLMchat.Client(config.connections.get(model_usage.connection));
				
				// Save config since we created it
				try {
					config.save();
					GLib.debug("Saved config to %s", OLLMchat.Settings.Config2.config_path);
				} catch (GLib.Error e) {
					GLib.warning("Failed to save config: %s", e.message);
				}
			}
			
			return client;
		}
		
		/**
		 * Abstract method that subclasses implement to perform the actual test.
		 * 
		 * @param command_line The ApplicationCommandLine for output
		 * @throws Error if the test fails
		 */
		protected abstract async void run_test(ApplicationCommandLine command_line, string[] remaining_args) throws Error;
	}

