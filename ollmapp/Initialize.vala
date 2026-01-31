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
	/**
	 * Handles application initialization and verification.
	 * 
	 * Manages connection checking, model verification, and required model
	 * bootstrapping before the application can be used.
	 */
	public class Initialize : Object
	{
		private OllmchatWindow window;
		
		/**
		 * Signal emitted when initialization needs to restart.
		 * 
		 * Emitted when settings dialog closes and initialization needs to restart.
		 */
		public signal void reinitialize();
		
		/**
		 * Constructor.
		 * 
		 * @param window The window instance (used for UI dialogs and app access)
		 */
		public Initialize(OllmchatWindow window)
		{
			this.window = window;
		}
		
		/**
		 * Runs the initialization process.
		 * 
		 * Tests connection, verifies models, ensures required models are available,
		 * and creates history manager. Shows dialogs for user interaction when needed.
		 * 
		 * @param config The Config2 instance (contains connection and model configuration)
		 * @return true if initialization succeeded, false if user cancelled
		 */
		public async bool run(OLLMchat.Settings.Config2 config)
		{
			// Loop until both connection and model succeed
			while (true) {
				// Check all connections and get first working one
				var checking_dialog = new SettingsDialog.CheckingConnectionDialog(this.window);
				checking_dialog.show_dialog();
				yield config.check_connections();
				checking_dialog.hide_dialog();
				
				var working_conn = config.working_connection();
				if (working_conn == null) {
					if (!(yield this.show_settings(
						"No working connection found. Please check your connection settings.",
						"connections"))) {
						return false;
					}
					continue;  // Restart loop after settings dialog closes
				}
				
				// Found a working connection - now ensure default model is set before creating history manager
				if (!(yield this.initialize_model(config, working_conn))) {
					if (!(yield this.show_settings(
						"No chat model found (only embedding models available). Please add or select a model.",
						"models"))) {
						return false;
					}
					continue;  // Restart loop after settings dialog closes
				}
				
				// Ensure all required models are available (early return on failure)
				if (!(yield this.ensure_required_models(config))) {
					if (!(yield this.show_settings(
						"Required models are not available. Please ensure models are downloaded.",
						"tools"))) {
						return false;
					}
					continue;  // Restart loop after settings dialog closes
				}
				
				this.window.history_manager = new OLLMchat.History.Manager(this.window.app);
				
				// Update default_model_usage to use the working connection if the current one is not working
				if (this.window.history_manager.default_model_usage != null) {
					var current_conn = config.connections.get(this.window.history_manager.default_model_usage.connection);
					if (current_conn == null || !current_conn.is_working) {
						this.window.history_manager.default_model_usage.connection = working_conn.url;
					}
				}
				
				// Try to verify model; if it fails, fix default in place with first non-embedding model
				try {
					yield this.window.history_manager.ensure_model_usage();
				} catch (GLib.Error e) {
					GLib.warning("Initialize.vala: Model verification failed: %s. Fixing default model.", e.message);
					if (!(yield this.initialize_model(config, working_conn))) {
						if (!(yield this.show_settings(
							"No chat model found (only embedding models available). Please add or select a model.",
							"models"))) {
							return false;
						}
						continue;
					}
				}
				
				break;
			}
			
			return true;  // Initialization succeeded
		}
		
		/**
		 * Initializes the default model if it's not set.
		 * Finds the first available non-embedding, non-hidden model from the working connection and sets it in config.
		 *
		 * @param config The Config2 instance (contains connection and model configuration)
		 * @param working_conn The working connection to use for finding models
		 * @return true if default model was set, false if no chat model available (e.g. only embedding models)
		 */
		private async bool initialize_model(OLLMchat.Settings.Config2 config, OLLMchat.Settings.Connection working_conn)
		{
			var default_model = config.usage.get("default_model") as OLLMchat.Settings.ModelUsage;

			// Load models from working connection first so we can check is_embedding
			var temp_connection_models = new OLLMchat.Settings.ConnectionModels(config);
			yield temp_connection_models.refresh();

			var connection_models = temp_connection_models.connection_map.get(working_conn.url);
			if (connection_models == null || connection_models.size == 0) {
				GLib.warning("Initialize.vala: No models found for working connection '%s'", working_conn.url);
				return false;
			}

			// If default model is set, check if it's embedding and unset it (chat default must not be embedding-only)
			if (default_model != null && default_model.model != "") {
				if (default_model.connection == "") {
					default_model.connection = working_conn.url;
				}
				var usage = temp_connection_models.find_model(default_model.connection, default_model.model);
				if (usage != null && usage.model_obj != null && usage.model_obj.is_embedding) {
					default_model.model = "";
				}
			}

			// If model is still set, verify it exists and is not embedding before keeping it
			if (default_model != null && default_model.model != "") {
				// Check if connection already has models loaded to avoid redundant API call
				var conn_obj = config.connections.get(default_model.connection);
				if (conn_obj != null && conn_obj.models.size > 0 && conn_obj.models.has_key(default_model.model)) {
					var usage = temp_connection_models.find_model(default_model.connection, default_model.model);
					if (usage == null || usage.model_obj == null || !usage.model_obj.is_embedding) {
						return true;
					}
					default_model.model = "";
				} else {
					// Models not loaded or model not found, verify (will load models if needed)
					if (yield default_model.verify_model(config)) {
						var usage = temp_connection_models.find_model(default_model.connection, default_model.model);
						if (usage == null || usage.model_obj == null || !usage.model_obj.is_embedding) {
							return true;
						}
						default_model.model = "";
					} else {
						// Model doesn't exist, clear it and find a new one
						default_model.model = "";
					}
				}
			}

			// Pick first non-embedding, non-hidden model (chat default)
			OLLMchat.Settings.ModelUsage? first_chat_model = null;
			foreach (var model_usage in connection_models.values) {
				if (model_usage.model_obj == null
					|| model_usage.model_obj.is_hidden
					|| model_usage.model_obj.is_embedding) {
					continue;
				}
				first_chat_model = model_usage;
				break;
			}
			if (first_chat_model == null) {
				GLib.warning("Initialize.vala: No non-embedding chat model found for connection '%s'", working_conn.url);
				return false;
			}
			
			if (default_model == null) {
				default_model = new OLLMchat.Settings.ModelUsage() {
					connection = first_chat_model.connection,
					model = first_chat_model.model,
					options = first_chat_model.options.clone()
				};
				config.usage.set("default_model", default_model);
			} else {
				default_model.connection = first_chat_model.connection;
				default_model.model = first_chat_model.model;
				default_model.options = first_chat_model.options.clone();
			}
			
			config.save();
			return true;
		}
		
		/**
		 * Waits for a model pull to complete (success or failure).
		 * 
		 * Connects to PullManager signals and waits until model_complete or model_failed
		 * is emitted for the specified model.
		 * 
		 * @param pull_manager The PullManager instance
		 * @param model_name The model name to wait for
		 * @return true if pull succeeded, false if failed
		 */
		private async bool wait_for_pull(SettingsDialog.PullManager pull_manager, string model_name)
		{
			GLib.SourceFunc callback = wait_for_pull.callback;
			bool pull_success = false;
			bool completed = false;
			
			// Declare signal IDs before lambdas so they can be captured
			ulong complete_id = 0;
			ulong failed_id = 0;
			
			complete_id = pull_manager.model_complete.connect((name) => {
				if (name == model_name && !completed) {
					completed = true;
					pull_success = true;
					pull_manager.disconnect(complete_id);
					pull_manager.disconnect(failed_id);
					callback();
				}
			});
			
			failed_id = pull_manager.model_failed.connect((name) => {
				if (name == model_name && !completed) {
					completed = true;
					pull_success = false;
					pull_manager.disconnect(complete_id);
					pull_manager.disconnect(failed_id);
					callback();
				}
			});
			
			// Wait for signal
			yield;
			
			return pull_success;
		}
		
		/**
		 * Checks and ensures all required models are available.
		 * 
		 * Iterates through all tool configs that implement RequiresModelsInterface interface,
		 * collects required models via required_models() method, verifies they're available,
		 * and auto-pulls them if missing. Shows progress in settings dialog.
		 * 
		 * @param config The Config2 instance
		 * @return true if all required models are available, false if user cancelled
		 */
		private async bool ensure_required_models(OLLMchat.Settings.Config2 config) throws GLib.Error
		{
			var required_models = new Gee.ArrayList<OLLMchat.Settings.ModelUsage>();
			
			// Collect required models from all tool configs that implement RequiresModelsInterface
			foreach (var tool_config_entry in config.tools.entries) {
				var tool_config = tool_config_entry.value;
				
				if (tool_config is OLLMchat.Settings.RequiresModelsInterface) {
					var requires_models = tool_config as OLLMchat.Settings.RequiresModelsInterface;
					required_models.add_all(requires_models.required_models());
				}
			}
			
			if (required_models.size == 0) {
				return true;  // No required models
			}
			
			// Check each required model
			foreach (var model_usage in required_models) {
				// Verify model is available
				if (yield model_usage.verify_model(config)) {
					continue;  // Model is available
				}
				
				// Model not available - need to pull it
				// Show settings dialog if not already shown
				if (!this.window.settings_dialog.visible) {
					this.window.settings_dialog.show_dialog.begin("tools");
				}
				
				// Get connection (early return on failure)
				if (!config.connections.has_key(model_usage.connection)) {
					GLib.warning("Connection not found for model: %s", model_usage.model);
					return false;
				}
				var connection = config.connections.get(model_usage.connection);
				
				// Start background pull operation
				if (!this.window.settings_dialog.pull_manager.start_pull(model_usage.model, connection)) {
					// Pull already in progress - wait for it to complete
					GLib.debug("Pull already in progress for model: %s", model_usage.model);
				}
				
				// Wait for pull to complete (early return on failure)
				if (!(yield this.wait_for_pull(this.window.settings_dialog.pull_manager, model_usage.model))) {
					GLib.warning("Model pull failed: %s", model_usage.model);
					return false;
				}
				
				// Verify model is now available (early return on failure)
				if (!(yield model_usage.verify_model(config))) {
					GLib.warning("Model %s still not available after pull", model_usage.model);
					return false;
				}
			}
			
			return true;  // All required models are available
		}
		
		/**
		 * Shows an error dialog and optionally shows settings dialog.
		 * 
		 * Shows an error dialog to the user. If the user clicks "Configure", shows the
		 * settings dialog on the specified page and connects to the closed signal to
		 * reinitialize. If the user closes the dialog without configuring, quits the app.
		 * 
		 * @param error_message The error message to display
		 * @param settings_page The settings page to show (e.g., "connections", "models", "tools")
		 * @return true if user clicked "Configure" (settings dialog shown), false if user cancelled
		 */
		private async bool show_settings(string error_message, string settings_page)
		{
			var response = yield this.window.show_connection_error_dialog(error_message);
			
			if (response != "settings") {
				// User closed dialog without configuring - quit application
				(this.window.app as Gtk.Application).quit();
				return false;
			}
			
			// User clicked Configure - show settings dialog
			// Connect to closed signal to re-check after settings dialog closes
			ulong signal_id = 0;
			signal_id = this.window.settings_dialog.closed.connect(() => {
				// Disconnect signal to avoid multiple connections
				this.window.settings_dialog.disconnect(signal_id);
				// Config already updated in memory by settings dialog, just re-check
				this.reinitialize();
			});
			
			// Show settings dialog and switch to specified tab
			this.window.settings_dialog.show_dialog.begin(settings_page);
			
			// Return true to indicate settings dialog was shown (will trigger re-check via signal)
			return true;
		}
	}
}
