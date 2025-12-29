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
			var test_client = new OLLMchat.Client(connection);
			try {
				yield test_client.version();
				stdout.printf("Connection successful.\n");
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("Failed to connect to server: %s", e.message);
			}
		}
	}
	
	/**
	 * Gets or creates a client for a specific usage type and verifies the model is available.
	 * 
	 * Checks if the usage exists in config, creates it if it doesn't,
	 * applies CLI model override if provided, verifies the model is available on the server,
	 * but doesn't save config until after all checks are complete.
	 * 
	 * @param usage_name The usage name (e.g., "ocvector.embed", "ocvector.analysis")
	 * @param opt_url Optional URL from command line (required if config not loaded)
	 * @param opt_api_key Optional API key from command line
	 * @param cli_model_override Optional model name override from command line
	 * @return Client instance for the usage
	 * @throws Error if client cannot be created or model is not available
	 */
	protected async OLLMchat.Client usage_client(string usage_name, string? opt_url = null, string? opt_api_key = null, string? cli_model_override = null) throws GLib.Error
	{
		yield this.ensure_config(opt_url, opt_api_key);
		
		// Check if usage exists, create if it doesn't
		if (!this.config.usage.has_key(usage_name)) {
			if (usage_name == "ocvector.embed") {
				OLLMvector.Database.setup_embed_usage(this.config);
			} else if (usage_name == "ocvector.analysis") {
				OLLMvector.Indexing.Analysis.setup_analysis_usage(this.config);
			} else {
				throw new GLib.IOError.NOT_FOUND("Unknown usage type: " + usage_name);
			}
		}
		
		var usage = this.config.usage.get(usage_name) as OLLMchat.Settings.ModelUsage;
		if (usage == null) {
			throw new GLib.IOError.NOT_FOUND(usage_name + " usage not found in config");
		}
		
		// Apply command-line model override if provided
		if (cli_model_override != null) {
			usage.model = cli_model_override;
		}
		
		var connection = this.config.connections.get(usage.connection);
		if (connection == null) {
			throw new GLib.IOError.NOT_FOUND("Connection '%s' not found for %s", usage.connection, usage_name);
		}
		
		// Verify model is available on the server
		stdout.printf("Verifying %s model '%s'...\n", usage_name, usage.model);
		var test_client = new OLLMchat.Client(connection);
		try {
			yield test_client.models();
		} catch (GLib.Error e) {
			stderr.printf("Error: Failed to fetch models from server: %s\n", e.message);
			throw new GLib.IOError.FAILED("Failed to fetch models from server: %s", e.message);
		}
		
		if (!test_client.available_models.has_key(usage.model)) {
			stderr.printf("Error: %s model '%s' not found on server.\n" +
			              "  Please ensure this model is available on your Ollama server.\n",
			              usage_name, usage.model);
			throw new GLib.IOError.NOT_FOUND("%s model '%s' not found on server", usage_name, usage.model);
		}
		stdout.printf("%s model found.\n", usage_name);
		
		var client = this.config.create_client(usage_name);
		if (client == null) {
			throw new GLib.IOError.NOT_FOUND(usage_name + " not configured");
		}
		
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

