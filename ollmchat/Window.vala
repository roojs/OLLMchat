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
	 /* Main application window for OLLMchat.
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
		private WindowPane? window_pane = null;
		private Gtk.Widget? current_agent_widget = null;
		private string data_dir;
		private Gtk.DropDown agent_dropdown;
		private Adw.HeaderBar header_bar;
		private OLLMchat.Settings.ConnectionAdd? bootstrap_dialog = null;

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
			// Start window 20% smaller (640x480 instead of 800x600)
			this.set_default_size(640, 600);
			
			// Set up data directory
			this.data_dir = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), ".local", "share", "ollmchat"
			);
			
			// Ensure data directory exists
			var data_dir_file = GLib.File.new_for_path(this.data_dir);
			if (!data_dir_file.query_exists()) {
				try {
					data_dir_file.make_directory_with_parents(null);
				} catch (GLib.Error e) {
					GLib.warning("Failed to create data directory %s: %s", this.data_dir, e.message);
				}
			}

			// Create toolbar view to manage header bar and content
			var toolbar_view = new Adw.ToolbarView();
			
			// Create header bar with toggle button and new chat button
			this.header_bar = new Adw.HeaderBar();
			var toggle_button = new Gtk.ToggleButton() {
				icon_name = "sidebar-show-symbolic",
				tooltip_text = "Toggle History"
			};
			this.header_bar.pack_start(toggle_button);
			
			this.new_chat_button = new Gtk.Button() {
				icon_name = "list-add-symbolic",
				tooltip_text = "New Chat",
				sensitive = false
			};
			this.header_bar.pack_start(this.new_chat_button);
			
			// Connect new chat button to create new session
			this.new_chat_button.clicked.connect(() => {
				var new_session = this.history_manager.create_new_session();
				this.chat_widget.switch_to_session.begin(new_session);
			});
			
			// Create agent dropdown (will be set up in setup_agent_dropdown)
			this.agent_dropdown = new Gtk.DropDown(null, null) {
				hexpand = false
			};
			this.header_bar.pack_start(this.agent_dropdown);
			
			// Create settings button
			var settings_button = new Gtk.Button() {
				icon_name = "applications-system-symbolic",
				tooltip_text = "Settings"
			};
			settings_button.clicked.connect(() => {
				this.show_settings_dialog();
			});
			this.header_bar.pack_start(settings_button);
				
			// Add header bar to toolbar view's top slot
			toolbar_view.add_top_bar(this.header_bar);

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
		 * Loads configuration from file system.
		 * 
		 * Checks for config.2.json first, then falls back to config.json and converts it.
		 * Sets static config_path on Config1 and Config2 classes.
		 * 
		 * @return Config2 instance (check loaded property to determine if successfully loaded)
		 */
		private Settings.Config2 load_config()
		{
			var config_dir = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), ".config", "ollmchat"
			);
			
			// Create instances first to ensure static properties are initialized
			var dummy1 = new Settings.Config1();
			var dummy2 = new Settings.Config2();
			
			// Set static config_path for both Config1 and Config2
			Settings.Config2.config_path = GLib.Path.build_filename(config_dir, "config.2.json");
			Settings.Config1.config_path = GLib.Path.build_filename(config_dir, "config.json");
			
			// Register ocvector types before loading config (static registration)
			OLLMvector.Database.register_config();
			OLLMvector.Indexing.Analysis.register_config();
			
			// Check for config.2.json first
			if (GLib.FileUtils.test(Settings.Config2.config_path, GLib.FileTest.EXISTS)) {
				// Load config.2.json
				GLib.debug("Loading config from %s", Settings.Config2.config_path);
				var config = Settings.Config2.load();
				return config;
			}
			
			// Check for config.json and convert to config.2.json
			if (!GLib.FileUtils.test(Settings.Config1.config_path, GLib.FileTest.EXISTS)) {
				return new Settings.Config2();
			}
			
			GLib.debug("Loading config.json and converting to config.2.json");
			var config1 = Settings.Config1.load();
			if (!config1.loaded) {
				return new Settings.Config2();
			}
			var config = config1.toV2();
			
			// Save as config.2.json if conversion was successful
			if (config.loaded) {
				try {
					config.save();
					GLib.debug("Saved converted config as %s", Settings.Config2.config_path);
				} catch (GLib.Error e) {
					GLib.warning("Failed to save config.2.json: %s", e.message);
				}
			}
			
			return config;
		}

		/**
		 * Loads configuration and initializes the client.
		 * Shows bootstrap dialog if config is missing or connection fails.
		 */
		private async void load_config_and_initialize()
		{
			var config = this.load_config();
			
			// Show bootstrap dialog if no config was loaded
			if (!config.loaded) {
				GLib.debug("Config not loaded, showing bootstrap dialog");
				yield this.show_bootstrap_dialog("");
				return;
			}
			
			GLib.debug("Config loaded successfully, initializing client");
			// Initialize client and test connection (will check for default connection internally)
			yield this.initialize_unverified_client(config);
		}

		/**
		 * Shows the bootstrap dialog for initial setup.
		 * 
		 * @param error_message Error message to display if connection failed (empty string if none)
		 */
		private async void show_bootstrap_dialog(string error_message)
		{
			if (this.bootstrap_dialog == null) {
				this.bootstrap_dialog = new OLLMchat.Settings.ConnectionAdd();
			}
			this.bootstrap_dialog.show_bootstrap();
			 
			
			if (error_message != "") {
				// Show error alert before dialog
				var alert = new Adw.AlertDialog(
					"Connection Failed",
					error_message + " Please configure your connection settings."
				);
				alert.add_response("ok", "Configure");
				yield alert.choose(this, null);
			}
			
			this.bootstrap_dialog.error_occurred.connect((error_msg) => {
				var alert = new Adw.AlertDialog(
					"Configuration Error",
					error_msg
				);
				alert.add_response("ok", "OK");
				alert.choose.begin(this, null);
			});
			
			// Handle dialog close - check verified_connection and save config
			// Adw.PreferencesDialog uses closed signal (not close_request)
			this.bootstrap_dialog.closed.connect(() => {
				if (this.bootstrap_dialog.verified_connection == null) {
					// No connection verified - close application
					this.app.quit();
					return;
				}
				
				// Create Config2 and save it
				// Ensure connection is marked as default for bootstrap
				this.bootstrap_dialog.verified_connection.is_default = true;
				this.bootstrap_dialog.verified_connection.name = "Default";
				var config = new Settings.Config2();
				config.connections.set(this.bootstrap_dialog.verified_connection.url, 
					this.bootstrap_dialog.verified_connection);
				
				// Create empty ModelUsage objects for default_model and title_model
				config.usage.set("default_model", new Settings.ModelUsage() {
					connection = this.bootstrap_dialog.verified_connection.url,
					model = "",
					options = new OLLMchat.Call.Options()
				});
				
				config.usage.set("title_model", new Settings.ModelUsage() {
					connection = this.bootstrap_dialog.verified_connection.url,
					model = "",
					options = new OLLMchat.Call.Options()
				});
				
				// Save config
				try {
					config.save();
					// Connection already verified in bootstrap dialog, so call initialize_client directly
					this.initialize_client.begin(config);
				} catch (GLib.Error e) {
					var alert = new Adw.AlertDialog(
						"Configuration Error",
						"Failed to save configuration: " + e.message
					);
					alert.add_response("ok", "OK");
					alert.choose.begin(this, null);
				}
			});
			
			this.bootstrap_dialog.present(this);
		}
		
		/**
		 * Initializes the client and sets up the UI.
		 * Tests connection first, then calls initialize_client.
		 * Shows bootstrap dialog if connection fails.
		 * 
		 * @param config The Config2 instance (contains connection and model configuration)
		 */
		private async void initialize_unverified_client(Settings.Config2 config)
		{
			// Get default connection from config for testing
			var default_connection = config.get_default_connection();
			if (default_connection == null) {
				yield this.show_bootstrap_dialog("No default connection found in config");
				return;
			}
			
			// Test connection first
			try {
				var test_client = new OLLMchat.Client(default_connection);
				yield test_client.version();
			} catch (GLib.Error e) {
				// Connection failed - show bootstrap dialog with error
				yield this.show_bootstrap_dialog("Failed to connect to server: " + e.message);
				return;
			}
			
			// Connection verified, proceed with initialization
			yield this.initialize_client(config);
		}

		/**
		 * Initializes the client and sets up the UI.
		 * Assumes connection has already been verified.
		 * 
		 * @param config The Config2 instance (contains connection and model configuration)
		 */
		private async void initialize_client(Settings.Config2 config)
		{
			// Create history manager (it will create base_client from config)
			this.history_manager = new OLLMchat.History.Manager(config, this.data_dir);
			
			// Add tools to base client (Manager creates base_client, so we access it via history_manager)
			this.history_manager.base_client.addTool(
					new OLLMchat.Tools.ReadFile(this.history_manager.base_client));
			this.history_manager.base_client.addTool(
					new OLLMchat.Tools.EditMode(this.history_manager.base_client));
			this.history_manager.base_client.addTool(
					new OLLMchatGtk.Tools.RunCommand(this.history_manager.base_client, 
						GLib.Environment.get_home_dir()));

			
			// Register CodeAssistant agent
			// Create ProjectManager first to share with tools
			var project_manager = new OLLMfiles.ProjectManager(
				new SQ.Database(GLib.Path.build_filename(this.data_dir, "files.sqlite"))
			);
			project_manager.buffer_provider = new OLLMcoder.BufferProvider();
			project_manager.git_provider = new OLLMcoder.GitProvider();
			
			var code_assistant = new OLLMcoder.Prompt.CodeAssistant(project_manager) {
				shell = GLib.Environment.get_variable("SHELL") ?? "/usr/bin/bash"
			};
			this.history_manager.agents.set(code_assistant.name, code_assistant);
			
			// TODO: Clipboard feature needs proper design - see TODO.md
			// Register clipboard metadata for file reference paste support
			// OLLMchatGtk.ClipboardManager.metadata = new OLLMcoder.ClipboardMetadata();
			
			// Set up agent dropdown now that agents are registered
			this.setup_agent_dropdown();
			
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
			
			// Register CodebaseSearchTool (only available when CodeAssistant agent is active)
			// Use same ProjectManager instance as CodeAssistant
			// Initialize codebase search tool asynchronously
			this.initialize_codebase_search_tool.begin(
				this.history_manager.base_client,
				project_manager
			);

			// Create chat widget with manager
			this.chat_widget = new OLLMchatGtk.ChatWidget(this.history_manager);
			
			// Create ChatView permission provider and set it on the base client
			var permission_provider = new OLLMchatGtk.Tools.Permission(
				this.chat_widget,
				GLib.Path.build_filename(
					GLib.Environment.get_home_dir(), ".config", "ollmchat"
				)) {
				application = this.app as GLib.Application,
			};
			this.history_manager.base_client.permission_provider = permission_provider;
			
			this.chat_widget.error_occurred.connect((error) => {
				stderr.printf("Error: %s\n", error);
			});

			// Create WindowPane to manage chat widget and agent widgets
			this.window_pane = new WindowPane();
			
			// Set chat widget as start child (left pane)
			this.window_pane.paned.set_start_child(this.chat_widget);
			this.window_pane.paned.set_resize_start_child(true);
			
			// Connect to agent_activated signal to manage agent widgets
			this.history_manager.agent_activated.connect(this.on_agent_activated);
			
			// Set WindowPane as main content
			this.split_view.content = this.window_pane;
		}
		
		/**
		 * Initializes the codebase search tool asynchronously.
		 * 
		 * Auto-creates embed and analysis ModelUsage entries in Config2 if they don't exist,
		 * then creates vector database and registers the tool.
		 */
		private async void initialize_codebase_search_tool(
			OLLMchat.Client client,
			OLLMfiles.ProjectManager project_manager
		)
		{
			// Get config from history manager (it has the Config2 instance)
			var config = this.history_manager.config;
			
			// Auto-create embed and analysis ModelUsage entries if they don't exist
			// These use the default connection with hardcoded models
			OLLMvector.Database.setup_embed_usage(config);
			OLLMvector.Indexing.Analysis.setup_analysis_usage(config);
			
			// Try to get embed client from config
			var embed_client = config.create_client("ocvector.embed");
			if (embed_client == null) {
				// No embed configuration - tool won't be available
				return;
			}
			
			try {
				// Get dimension and create vector database
				var vector_db_path = GLib.Path.build_filename(this.data_dir, "codedb.faiss.vectors");
				var dimension = yield OLLMvector.Database.get_embedding_dimension(embed_client);
				var vector_db = new OLLMvector.Database(embed_client, vector_db_path, dimension);
				
				// Register the tool
				client.addTool(new OLLMvector.Tool.CodebaseSearchTool(
					client,
					project_manager,
					vector_db,
					embed_client
				));
			} catch (GLib.Error e) {
				GLib.warning("Failed to initialize codebase search tool: %s", e.message);
			}
		}
		
		/**
		 * Handles agent activation signal.
		 * 
		 * Manages agent widgets in WindowPane.tab_view:
		 * - Hides previous agent's widget (if any)
		 * - Gets widget from agent via async get_widget()
		 * - Adds widget to tab_view if not already present
		 * - Shows widget and updates WindowPane visibility
		 */
		private void on_agent_activated(OLLMagent.BaseAgent agent)
		{
			if (this.window_pane == null) {
				return;
			}
			
			// Hide previous agent's widget (if any)
			if (this.current_agent_widget != null) {
				this.current_agent_widget.visible = false;
				this.current_agent_widget = null;
			}
			
			// Get widget from agent asynchronously
			agent.get_widget.begin((obj, res) => {
				var widget_obj = agent.get_widget.end(res);
				this.handle_agent_widget(agent, widget_obj);
			});
		}
		
		/**
		 * Handles the agent widget after it's been retrieved.
		 * 
		 * @param agent The agent that provided the widget
		 * @param widget_obj The widget object (may be null)
		 */
		private void handle_agent_widget(OLLMagent.BaseAgent agent, Object? widget_obj)
		{
			if (this.window_pane == null) {
				return;
			}
			
			if (widget_obj == null) {
				// Agent has no UI - hide pane
				this.window_pane.intended_pane_visible = false;
				this.window_pane.schedule_pane_update();
				return;
			}
			
			// Cast to Gtk.Widget
			var widget = widget_obj as Gtk.Widget;
			if (widget == null) {
				GLib.warning("Agent %s returned non-widget object from get_widget()", agent.name);
				this.window_pane.intended_pane_visible = false;
				this.window_pane.schedule_pane_update();
				return;
			}
			
			// Widget ID management
			var widget_id = agent.name + "-widget";
			
			// Set widget name if not already set (before calling WindowPane method)
			if (widget.name == null || widget.name == "") {
				widget.name = widget_id;
			}
			
			// Add or show widget in WindowPane (handles showing and setting visible child)
			widget = this.window_pane.add_or_show_agent_widget(widget, widget_id);
			this.current_agent_widget = widget;
			
			// Set intended state and schedule update
			this.window_pane.intended_pane_visible = true;
			this.window_pane.schedule_pane_update();
		}
		
		/**
		 * Sets up the agent dropdown widget.
		 * 
		 * @since 1.0
		 */
		private void setup_agent_dropdown()
		{
			if (this.history_manager == null) {
				return;
			}
			
			// Create ListStore for agents
			var agent_store = new GLib.ListStore(typeof(OLLMagent.BaseAgent));
			
			// Add all registered agents to the store and set selection during load
			uint selected_index = 0;
			uint i = 0;
			foreach (var agent in this.history_manager.agents.values) {
				agent_store.append(agent);
				if (agent.name == this.history_manager.session.agent_name) {
					selected_index = i;
				}
				i++;
			}
			
			// Create factory for agent dropdown
			var factory = new Gtk.SignalListItemFactory();
			factory.setup.connect((item) => {
				var list_item = item as Gtk.ListItem;
				if (list_item == null) {
					return;
				}
				
				var label = new Gtk.Label("") {
					halign = Gtk.Align.START
				};
				list_item.set_data<Gtk.Label>("label", label);
				list_item.child = label;
			});
			
			factory.bind.connect((item) => {
				var list_item = item as Gtk.ListItem;
				if (list_item == null || list_item.item == null) {
					return;
				}
				
				var agent = list_item.item as OLLMagent.BaseAgent;
				var label = list_item.get_data<Gtk.Label>("label");
				
				if (label != null && agent != null) {
					label.label = agent.title;
				}
			});
			
			// Set up dropdown with agents
			this.agent_dropdown.model = agent_store;
			this.agent_dropdown.set_factory(factory);
			this.agent_dropdown.set_list_factory(factory);
			this.agent_dropdown.selected = selected_index;
			
			// Connect selection change to update session's agent_name and client
			this.agent_dropdown.notify["selected"].connect(() => {
				if (this.agent_dropdown.selected == Gtk.INVALID_LIST_POSITION) {
					return;
				}
				
				var agent = (this.agent_dropdown.model as GLib.ListStore).get_item(this.agent_dropdown.selected) as OLLMagent.BaseAgent;
				  
				this.history_manager.session.agent_name = agent.name;
				// Update current session's client prompt_assistant (direct assignment, agents are stateless)
				this.history_manager.session.client.prompt_assistant = agent;
				
				// Emit agent_activated signal for UI updates (Window listens to this)
				this.history_manager.agent_activated(agent);
			});
			
			// Connect to session_activated signal to update when session changes
			this.history_manager.session_activated.connect((session) => {
				// Update agent selection to match session's agent
				var store = this.agent_dropdown.model as GLib.ListStore;
				if (store == null) {
					return;
				}
				
				for (uint j = 0; j < store.get_n_items(); j++) {
					if (((OLLMagent.BaseAgent)store.get_item(j)).name != session.agent_name) {
						continue;
					}
					this.agent_dropdown.selected = j;
					break;
				}
			});
		}
		
		/**
		 * Shows the settings dialog.
		 * 
		 * @since 1.0
		 */
		private void show_settings_dialog()
		{
			if (this.history_manager == null) {
				return;
			}
			
			// Get config from history manager
			var config = this.history_manager.config;
			
			// Create and show settings dialog
			var dialog = new OLLMchat.Settings.SettingsDialog(config);
			dialog.show_dialog(this);
		}
		
	}
}
