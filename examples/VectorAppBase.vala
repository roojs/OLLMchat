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

/**
 * Base class for OLLMchat vector applications (index and search).
 * 
 * Handles common functionality for vector tools including config verification,
 * usage client creation, and model availability checking.
 */
public abstract class VectorAppBase : TestAppBase
{
	protected VectorAppBase(string application_id)
	{
		base(application_id);
	}
	
	/**
	 * Ensures config exists and is loaded.
	 * Creates config if it doesn't exist, and sets up connection from CLI args if needed.
	 * Tests the connection but doesn't save config until after all checks are complete.
	 * 
	 * @param opt_url Optional URL from command line (required if config not loaded)
	 * @param opt_api_key Optional API key from command line
	 * @throws Error if config not loaded and URL not provided, or connection test fails
	 */
	protected async void ensure_config(string? opt_url = null, string? opt_api_key = null) throws GLib.Error
	{
		// If config not loaded, create connection from CLI args
		if (!this.config.loaded) {
			if (opt_url == null || opt_url == "") {
				stderr.printf("Error: Config not found and --url not provided.\n" +
				              "Please set up the server first or provide --url option.\n");
				throw new GLib.IOError.NOT_FOUND("Config not found and --url not provided");
			}
			
			// Create connection from command line args
			var connection = new OLLMchat.Settings.Connection() {
				name = "CLI",
				url = opt_url,
				api_key = opt_api_key ?? "",
				is_default = true
			};
			
			// Add connection to config (needed for setup methods)
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
		}
	}
	
	/**
	 * Gets or creates a client from the codebase search tool config and verifies the model is available.
	 * 
	 * Uses the tool config system (not the usage map). Ensures tool config exists, applies CLI model override
	 * if provided, verifies the model is available on the server, but doesn't save config until after
	 * all checks are complete.
	 * 
	 * Note: `opt_url` and `opt_api_key` only affect defaults if config is not already loaded.
	 * If config is loaded, they are ignored and existing defaults are used.
	 * 
	 * @param model_type "embed" for embed model, "analysis" for analysis model
	 * @param opt_url Optional URL from command line (required if config not loaded; creates default connection if provided)
	 * @param opt_api_key Optional API key from command line (only used if config not loaded)
	 * @param cli_model_override Optional model name override from command line (overrides the model in tool config)
	 * @return Client instance for the model
	 * @throws Error if client cannot be created or model is not available
	 */
	protected async OLLMchat.Client tool_config_client(string model_type, string? opt_url = null, string? opt_api_key = null, string? cli_model_override = null) throws GLib.Error
	{
		yield this.ensure_config(opt_url, opt_api_key);
		
		// Ensure tool config exists
		new OLLMvector.Tool.CodebaseSearchTool(null).setup_tool_config_default(this.config);
		
		// Inline tool config access and validation
		if (!this.config.tools.has_key("codebase_search")) {
			throw new GLib.IOError.FAILED("Codebase search tool config not found");
		}
		var tool_config = this.config.tools.get("codebase_search") as OLLMvector.Tool.CodebaseSearchToolConfig;
		if (!tool_config.enabled) {
			throw new GLib.IOError.FAILED("Codebase search tool is disabled");
		}
		
		OLLMchat.Settings.ModelUsage usage;
		switch (model_type) {
			case "embed":
				usage = tool_config.embed;
				break;
			case "analysis":
				usage = tool_config.analysis;
				break;
			default:
				GLib.error("Unknown model type: %s (must be 'embed' or 'analysis')", model_type);
		}
		
		// Apply command-line model override if provided
		if (cli_model_override != null) {
			usage.model = cli_model_override;
		}
		
		// Verify model is available on the server (verify_model checks connection and model availability)
		stdout.printf("Verifying %s model '%s'...\n", model_type, usage.model);
		if (!(yield usage.verify_model(this.config))) {
			GLib.error("Error: %s model '%s' not found on server.\n" +
			           "  Please ensure this model is available on your Ollama server.",
			           model_type, usage.model);
		}
		stdout.printf("%s model found.\n", model_type);
		
		// Get connection (already validated by verify_model)
		var connection = this.config.connections.get(usage.connection);
		
		// Create client directly from ModelUsage
		// Phase 3: model is not on Client, it's on Session/Chat
		var client = new OLLMchat.Client(connection);
		
		return client;
	}
	
	/**
	 * Saves the config after all checks are complete.
	 * Should be called after verifying models and creating clients.
	 */
	protected void save_config()
	{
		try {
			this.config.save();
			GLib.debug("Saved config to %s", OLLMchat.Settings.Config2.config_path);
		} catch (GLib.Error e) {
			GLib.warning("Failed to save config: %s", e.message);
		}
	}
}

