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

namespace OLLMchat 
{
	/**
	 * Main application window for OLLMchat.
	 * 
	 * This is the primary window that provides the chat interface.
	 * 
	 * @since 1.0
	 */
	public class OllmchatWindow : Adw.Window
	{
		private OLLMchatGtk.ChatWidget chat_widget;
		private OLLMchat.History.Manager? history_manager = null;
		private Adw.OverlaySplitView split_view;
		private OLLMchatGtk.HistoryBrowser? history_browser = null;
		private Gtk.Button new_chat_button;
		private Gtk.Application app;

		/**
		 * Creates a new OllmchatWindow instance.
		 * 
		 * @param app The Gtk.Application instance
		 * @since 1.0
		 */
		public OllmchatWindow(Gtk.Application app)
		{
			this.app = app;
			this.title = "OLLMchat";
			this.set_default_size(800, 600);

			// Create toolbar view to manage header bar and content
			var toolbar_view = new Adw.ToolbarView();
			
			// Create header bar with toggle button and new chat button
			var header_bar = new Adw.HeaderBar();
			var toggle_button = new Gtk.ToggleButton() {
				icon_name = "sidebar-show-symbolic",
				tooltip_text = "Toggle History"
			};
			header_bar.pack_start(toggle_button);
			
			this.new_chat_button = new Gtk.Button() {
				icon_name = "list-add-symbolic",
				tooltip_text = "New Chat",
				sensitive = false
			};
			header_bar.pack_start(this.new_chat_button);
			
			// Connect new chat button to create new session
			this.new_chat_button.clicked.connect(() => {
				var new_session = this.history_manager.create_new_session();
				this.chat_widget.switch_to_session.begin(new_session);
			});
			
			// Add header bar to toolbar view's top slot
			toolbar_view.add_top_bar(header_bar);

			// Create overlay split view
			this.split_view = new Adw.OverlaySplitView();
			this.split_view.show_sidebar = false; // Hidden at start
			// Set sidebar width as fraction of total width (0.25 = 25% of window width)
			this.split_view.set_sidebar_width_fraction(0.25);
			
			// Connect toggle button to show/hide sidebar
			toggle_button.toggled.connect(() => {
				this.split_view.show_sidebar = toggle_button.active;
				toggle_button.icon_name = toggle_button.active ? "sidebar-hide-symbolic" : "sidebar-show-symbolic";
			});

			// Set split view as toolbar view content
			toolbar_view.content = this.split_view;
			
			// Set toolbar view as window content
			this.set_content(toolbar_view);

			// Load configuration and initialize
			this.load_config_and_initialize.begin();
		}

		/**
		 * Loads configuration and initializes the client.
		 * Shows bootstrap dialog if config is missing or connection fails.
		 */
		private async void load_config_and_initialize()
		{
			// Load configuration from ~/.config/ollmchat/config.json
			var config_path = Path.build_filename(
				GLib.Environment.get_home_dir(), ".config", "ollmchat", "config.json"
			);
			
			GLib.debug("Loading config from %s", config_path);
			var config = new OLLMchat.Config();
			config.load(config_path);
			GLib.debug("After loading config.json - loaded=%s, url=%s", config.loaded.to_string(), config.url);
			
			// Show bootstrap dialog if config was not loaded
			if (!config.loaded) {
				GLib.debug("Config not loaded, showing bootstrap dialog");
				this.show_bootstrap_dialog.begin(config_path, null);
				return;
			}
			
			GLib.debug("Config loaded successfully, initializing client");
			// Initialize client and test connection
			yield this.initialize_client(config);
		}

		/**
		 * Shows the bootstrap dialog for initial setup.
		 * 
		 * @param config_path Path to the configuration file
		 * @param error_message Optional error message to display if connection failed
		 */
		private async void show_bootstrap_dialog(string config_path, string? error_message)
		{
			var dialog = new BootstrapDialog(config_path);
			
			if (error_message != null) {
				// Show error alert before dialog
				var alert_message = error_message + " Please configure your connection settings.";
				var alert = new Adw.AlertDialog(
					"Connection Failed",
					alert_message
				);
				alert.add_response("ok", "Configure");
				yield alert.choose(this, null);
			}
			
			dialog.config_saved.connect((config) => {
				this.initialize_client.begin(config);
			});
			
			dialog.error_occurred.connect((error_msg) => {
				var alert = new Adw.AlertDialog(
					"Configuration Error",
					error_msg
				);
				alert.add_response("ok", "OK");
				alert.choose.begin(this, null);
			});
			
			// Close application when dialog is closed via 'x' button
			((Gtk.Window) dialog).close_request.connect(() => {
				this.app.quit();
				return true; // Prevent default close behavior
			});
			
			dialog.present(this);
		}
		
		/**
		 * Initializes the client and sets up the UI.
		 * Tests connection and shows bootstrap dialog if connection fails.
		 * 
		 * @param config The configuration object
		 */
		private async void initialize_client(OLLMchat.Config config)
		{
			var client = new OLLMchat.Client(config) {
				stream = true,
				keep_alive = "5m",
				prompt_assistant = new OLLMchat.Prompt.JustAsk()  // Default to Just Ask
			};
			
			// Test connection
			try {
				yield client.version();
			} catch (Error e) {
				// Connection failed - show bootstrap dialog with error
				var error_msg = "Failed to connect to server: " + e.message;
				this.show_bootstrap_dialog.begin(config.config_path, error_msg);
				return;
			}
			
			// Try to set model from running models on server
			client.set_model_from_ps();
			
			// Set up history manager
			var data_dir = Path.build_filename(
				GLib.Environment.get_home_dir(), ".local", "share", "ollmchat"
			);
			// Ensure directory exists
			var data_dir_file = File.new_for_path(data_dir);
			if (!data_dir_file.query_exists()) {
				try {
					data_dir_file.make_directory_with_parents(null);
				} catch (GLib.Error e) {
					GLib.warning("Failed to create data directory %s: %s", data_dir, e.message);
				}
			}
			
			// Create history manager with base client (JustAsk is registered in constructor)
			this.history_manager = new OLLMchat.History.Manager(client, data_dir);
			
			// Register CodeAssistant agent
			var code_assistant = new OLLMchat.Prompt.CodeAssistant(
				new OLLMchat.Prompt.CodeAssistantDummy()
			) {
				shell = GLib.Environment.get_variable("SHELL") ?? "/usr/bin/bash",
			};
			this.history_manager.agents.set(code_assistant.name, code_assistant);
			
			// Enable new chat button now that history manager is ready
			this.new_chat_button.sensitive = true;
			
			// Create history browser and add to split view sidebar
			this.history_browser = new OLLMchatGtk.HistoryBrowser(this.history_manager);
			this.split_view.sidebar = this.history_browser;
			
			// Connect history browser to load sessions
			this.history_browser.session_selected.connect((session) => {
				// switch_to_session() handles loading internally via load()
				this.chat_widget.switch_to_session.begin(session);
			});
			
			// Add tools to the client
			client.addTool(new OLLMchat.Tools.ReadFile(client));
			client.addTool(new OLLMchat.Tools.EditMode(client));
			client.addTool(new OLLMchatGtk.Tools.RunCommand(client, GLib.Environment.get_home_dir()));

			// Create chat widget with manager
			this.chat_widget = new OLLMchatGtk.ChatWidget(this.history_manager);
			
			// Create ChatView permission provider and set it on the base client
			var permission_provider = new OLLMchatGtk.Tools.Permission(
				this.chat_widget,
				Path.build_filename(
					GLib.Environment.get_home_dir(), ".config", "ollmchat"
				)) {
				application = this.app as GLib.Application,
			};
			client.permission_provider = permission_provider;
			
			this.chat_widget.error_occurred.connect((error) => {
				stderr.printf("Error: %s\n", error);
			});

			// Set chat widget as main content
			this.split_view.content = this.chat_widget;
		}
		
	}
}
