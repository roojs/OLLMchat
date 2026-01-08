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

namespace OLLMapp 
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
		public OLLMchat.History.Manager? history_manager = null;
		private Adw.OverlaySplitView split_view;
		private OLLMchatGtk.HistoryBrowser? history_browser = null;
		private Gtk.Button new_chat_button;
		public OLLMchat.ApplicationInterface app;
		private WindowPane? window_pane = null;
		private Gtk.Widget? current_agent_widget = null;
		private Gtk.DropDown agent_dropdown;
		private Adw.HeaderBar header_bar;
		private SettingsDialog.ConnectionAdd? bootstrap_dialog = null;
		private SettingsDialog.MainDialog? settings_dialog = null;
		private Gtk.Button settings_button;
		private Gtk.Spinner settings_spinner;
		private Gtk.Image settings_icon;
		private Adw.Banner tool_error_banner;
		private FileChangeBanner file_change_banner;
		private VectorScanBanner vector_scan_banner;
		private OLLMfiles.ProjectManager project_manager;
		private OLLMvector.BackgroundScan? background_scan = null;

		/**
		 * Creates a new OllmchatWindow instance.
		 * 
		 * @param app The ApplicationInterface instance
		 * @since 1.0
		 */
		public OllmchatWindow(OLLMchat.ApplicationInterface app)
		{
			this.app = app;
			this.title = "OLLMchat";
			// Start window 20% smaller (640x480 instead of 800x600)
			this.set_default_size(640, 800);
			
			// Ensure data directory exists (using interface)
			app.ensure_data_dir();
			
			// Create settings dialog (creates PullManager which loads status from file)
			this.settings_dialog = new SettingsDialog.MainDialog(this);
			
			// Connect to PullManager signals to update settings button icon
			this.settings_dialog.pull_manager.pulls_changed.connect(this.update_settings_button);
			
			// Update model list when settings dialog closes
			this.settings_dialog.closed.connect(() => {
				this.chat_widget.update_models.begin();
			});

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
		// Use expression for BaseAgent.title (will be replaced in setup_agent_dropdown)
		this.agent_dropdown = new Gtk.DropDown(null, 
			new Gtk.PropertyExpression(typeof(OLLMchat.Prompt.BaseAgent), null, "title")) {
			hexpand = false
		};
			this.header_bar.pack_start(this.agent_dropdown);
			
			// Create settings button with spinner
			var settings_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
			this.settings_icon = new Gtk.Image() {
				icon_name = "applications-system-symbolic"
			};
			this.settings_spinner = new Gtk.Spinner() {
				spinning = false,
				visible = false
			};
			settings_box.append(this.settings_spinner);
			settings_box.append(this.settings_icon);
			this.settings_button = new Gtk.Button() {
				child = settings_box,
				tooltip_text = "Settings"
			};
			this.settings_button.clicked.connect(() => {
				this.show_settings_dialog();
			});
			this.header_bar.pack_start(this.settings_button);
			
			// Create tool error banner
			this.tool_error_banner = new Adw.Banner("") {
				button_label = "Dismiss",
				revealed = false
			};
			this.tool_error_banner.button_clicked.connect(() => {
				this.tool_error_banner.revealed = false;
			});
			
			// Create file change banner (creates revealer internally)
			this.file_change_banner = new FileChangeBanner(this);
			
			// Create vector scan banner (creates revealer internally)
			this.vector_scan_banner = new VectorScanBanner();
				
			// Add header bar to toolbar view's top slot
			toolbar_view.add_top_bar(this.header_bar);
			
			// Add tool error banner below header bar
			toolbar_view.add_top_bar(this.tool_error_banner);
			
			// Add file change banner below tool error banner
			toolbar_view.add_top_bar(this.file_change_banner.revealer);
			
			// Add vector scan banner below file change banner
			toolbar_view.add_top_bar(this.vector_scan_banner.revealer);

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

			// Connect to realize signal to restart incomplete pulls when window is shown
			(this as Gtk.Widget).realize.connect(() => {
				this.settings_dialog.pull_manager.restart();
				// Update button state after restart (in case there are active pulls)
				this.update_settings_button();
			});

			// Load configuration and initialize
			this.load_config_and_initialize.begin();
		}

		/**
		 * Loads configuration and initializes the client.
		 * Shows bootstrap dialog if config is missing or connection fails.
		 */
		private async void load_config_and_initialize()
		{
			// Show bootstrap dialog if no config was loaded
			if (!this.app.config.loaded) {
				GLib.debug("Config not loaded, showing bootstrap dialog");
				yield this.show_bootstrap_dialog("");
				return;
			}
			
			GLib.debug("Config loaded successfully, initializing client");
			// Initialize client and test connection (will check for default connection internally)
			yield this.initialize_unverified_client(this.app.config);
		}

		/**
		 * Shows the bootstrap dialog for initial setup.
		 * 
		 * @param error_message Error message to display if connection failed (empty string if none)
		 */
		private async void show_bootstrap_dialog(string error_message)
		{
			if (this.bootstrap_dialog == null) {
				this.bootstrap_dialog = new SettingsDialog.ConnectionAdd();
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
					(this.app as Gtk.Application).quit();
					return;
				}
				
				// Create Config2 and save it
				// Ensure connection is marked as default for bootstrap
				this.bootstrap_dialog.verified_connection.is_default = true;
				this.bootstrap_dialog.verified_connection.name = "Default";
				var config = new OLLMchat.Settings.Config2();
				config.connections.set(this.bootstrap_dialog.verified_connection.url, 
					this.bootstrap_dialog.verified_connection);
				
				// Create empty ModelUsage objects for default_model and title_model
				config.usage.set("default_model", new OLLMchat.Settings.ModelUsage() {
					connection = this.bootstrap_dialog.verified_connection.url,
					model = "",
					options = new OLLMchat.Call.Options()
				});
				
				config.usage.set("title_model", new OLLMchat.Settings.ModelUsage() {
					connection = this.bootstrap_dialog.verified_connection.url,
					model = "",
					options = new OLLMchat.Call.Options()
				});
				
				// Save config
				config.save();
				// Connection already verified in bootstrap dialog, so call initialize_client directly
				this.initialize_client.begin(config);
			});
			
			this.bootstrap_dialog.present(this);
		}
		
		/**
		 * Initializes the client and sets up the UI.
		 * Tests connection first, then calls initialize_client.
		 * Shows warning dialog if connection fails (with option to configure).
		 * Loops until connection succeeds or user cancels.
		 * 
		 * @param config The Config2 instance (contains connection and model configuration)
		 */
		private async void initialize_unverified_client(OLLMchat.Settings.Config2 config)
		{
			// Loop until connection succeeds
			while (true) {
				// Check all connections and get first working one
				var checking_dialog = new SettingsDialog.CheckingConnectionDialog(this);
				checking_dialog.show_dialog();
				yield config.check_connections();
				checking_dialog.hide_dialog();
				
				var working_conn = config.working_connection();
				if (working_conn == null) {
					// No working connection found - show warning dialog with option to configure
					var response = yield this.show_connection_error_dialog("No working connection found. Please check your connection settings.");
					
					if (response != "settings") {
						// User closed dialog without configuring - exit
						return;
					}
					
					// User clicked Configure - show settings dialog
					// Connect to closed signal to re-check connection after settings dialog closes
					ulong signal_id = 0;
					signal_id = this.settings_dialog.closed.connect(() => {
						// Disconnect signal to avoid multiple connections
						this.settings_dialog.disconnect(signal_id);
						// Re-check connection after settings dialog closes
						this.initialize_unverified_client.begin(config);
					});
					
					// Show settings dialog and switch to connections tab
					this.show_settings_dialog("connections");
					
					// Wait for settings dialog to close (will trigger re-check via signal)
					return;
				}
				
				// Found a working connection - break out of loop
				break;
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
		private async void initialize_client(OLLMchat.Settings.Config2 config)
		{
			// Create history manager (it will create base_client from config)
			this.history_manager = new OLLMchat.History.Manager(this.app);
			
			// Check all connections and set is_working flags before refreshing models
			
			// Refresh connection models after connection validation (version tests completed)
			yield this.history_manager.connection_models.refresh();
			
			// Create ProjectManager first to share with tools
			this.project_manager = new OLLMfiles.ProjectManager(
				new SQ.Database(GLib.Path.build_filename(this.app.data_dir, "files.sqlite"))
			);
			this.project_manager.buffer_provider = new OLLMcoder.BufferProvider();
			this.project_manager.git_provider = new OLLMcoder.GitProvider();
			
			// Bind file change banner button signals to project manager methods
			this.file_change_banner.overwrite_button.clicked.connect(() => {
				this.file_change_banner.hide();
				this.project_manager.write_buffer_to_disk.begin();
			});
			
			this.file_change_banner.refresh_button.clicked.connect(() => {
				this.file_change_banner.hide();
				this.project_manager.reload_file_from_disk.begin();
			});
			
			// Connect window focus notification to check for file changes
			this.notify["is-active"].connect(() => {
				if (!this.is_active) {
					return;
				}
				
				// Window gained focus - check if active file has changed on disk
				this.project_manager.check_active_file_changed.begin((obj, res) => {
					var status = this.project_manager.check_active_file_changed.end(res);
					
					if (status == OLLMfiles.FileUpdateStatus.CHANGED_HAS_UNSAVED) {
						// File changed on disk but buffer has unsaved changes - show warning banner
						var filename = this.project_manager.active_file != null 
							? GLib.Path.get_basename(this.project_manager.active_file.path) 
							: "file";
						this.file_change_banner.show(filename);
					}
				});
			});
			
			// Register all tools (Phase 3: tools stored on Manager, added to Chat by agents)
			// This is a temporary method - will be fixed properly later
			this.history_manager.register_all_tools(this.project_manager);

			
			// Register CodeAssistant agent
			var code_assistant = new OLLMcoder.Prompt.CodeAssistant(this.project_manager);
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

			// Create chat widget with manager
			this.chat_widget = new OLLMchatGtk.ChatWidget(this.history_manager);
			
			// Create ChatView permission provider and set it on the session (Phase 3: permission_provider on Session, not Client)
			var permission_provider = new OLLMchatGtk.Tools.Permission(
				this.chat_widget,
				GLib.Path.build_filename(
					GLib.Environment.get_home_dir(), ".config", "ollmchat"
				)) {
				application = this.app as GLib.Application,
			};
			// Set on session (will be set on Chat when Chat is created)
			this.history_manager.session.permission_provider = permission_provider;
			
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
			
			// Register CodebaseSearchTool (only available when CodeAssistant agent is active)
			// Use same ProjectManager instance as CodeAssistant
			// Initialize codebase search tool asynchronously AFTER everything else is set up
			// Use idle add to ensure initialization happens after the current call stack completes
			// This ensures config is fully loaded and ready
			GLib.Idle.add(() => {
				this.initialize_codebase_search_tool.begin(
					this.history_manager.base_client,
					this.project_manager
				);
				return false; // Don't repeat
			});
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
			
			// Ensure config is loaded before proceeding
			if (config == null || !config.loaded) {
				string error_msg = "Config not loaded, skipping codebase search tool initialization";
				GLib.warning("%s", error_msg);
				this.tool_error_banner.title = "Tool Error: Codebase Search - " + error_msg;
				this.tool_error_banner.revealed = true;
				return;
			}
			
			// Setup tool configs with default values if they don't exist (saves automatically if created)
			// This discovers all tools and calls setup_tool_config() on each
			// Simple tools use the default implementation, complex tools use their overrides
			OLLMchat.Tool.BaseTool.setup_all_tool_configs(config);
			
			// Inline enabled check
			if (!config.tools.has_key("codebase_search")) {
				// tool disabled
				return;
			}
			var tool_config = config.tools.get("codebase_search") as OLLMvector.Tool.CodebaseSearchToolConfig;
			if (!tool_config.enabled) {
				// tool disabled
				return;
			}
			
			// Get the tool from Manager (Phase 3: tools stored on Manager, not Client)
			var tool = this.history_manager.tools.get("codebase_search") as OLLMvector.Tool.CodebaseSearchTool;
			
			// Initialize vector database (embedding_client should already be set up in constructor)
			try {
				yield tool.init_databases(this.app.data_dir);
			} catch (GLib.Error e) {
				string error_msg = "Failed to initialize vector database: " + e.message;
				GLib.warning("Codebase search tool disabled: %s", error_msg);
				this.tool_error_banner.title = "Tool Error: Codebase Search - " + error_msg;
				this.tool_error_banner.revealed = true;
				return;
			}
			
			// Create BackgroundScan instance for background file indexing
			// Uses the tool instance which provides embedding_client, vector_db, and project_manager.db
			// Pass a new GitProvider instance (libgit2 is not thread-safe, each thread needs its own instance)
			// Check if indexer is disabled via command-line option
			if (!OllmchatApplication.opt_disable_indexer) {
				this.background_scan = new OLLMvector.BackgroundScan(
					tool,
					new OLLMcoder.GitProvider()
				);
				
				// Connect to scan_update signal to update banner
				this.background_scan.scan_update.connect((queue_size, current_file) => {
					this.vector_scan_banner.update_scan_status(queue_size, current_file);
				});
				
				// Connect to file_contents_changed signal to trigger background scanning
				// Only connect when background_scan is available
				// scanFile handles null project internally
				this.project_manager.file_contents_changed.connect((file) => {
					this.background_scan.scanFile(file, this.project_manager.active_project);
				});
				
				// Connect to active_project_changed signal to trigger project scanning
				// When project changes, scan all files in the project
				// scanProject handles null project internally
				this.project_manager.active_project_changed.connect((project) => {
					this.background_scan.scanProject(project);
				});
			} else {
				GLib.debug("Background semantic search indexing disabled via --disable-indexer");
			}
			
			GLib.debug("Codebase search tool initialized successfully (name: %s, active: %s)", 
				tool.name, tool.active.to_string());
			
			// Phase 3: Tools are stored on Manager
			// Add tool to Manager - it will be copied to Chat when Chat is created in Session
			this.history_manager.tools.set(tool.name, tool);
			GLib.debug("Codebase search tool added to Manager (total tools: %d)", 
				this.history_manager.tools.size);
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
		private void on_agent_activated(OLLMchat.Prompt.BaseAgent agent)
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
		private void handle_agent_widget(OLLMchat.Prompt.BaseAgent agent, Object? widget_obj)
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
			var agent_store = new GLib.ListStore(typeof(OLLMchat.Prompt.BaseAgent));
			
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
				
				var agent = list_item.item as OLLMchat.Prompt.BaseAgent;
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
			
			// Connect selection change to activate agent via Manager
			this.agent_dropdown.notify["selected"].connect(() => {
				if (this.agent_dropdown.selected == Gtk.INVALID_LIST_POSITION) {
					return;
				}
				
				var agent = (this.agent_dropdown.model as GLib.ListStore).get_item(this.agent_dropdown.selected) as OLLMchat.Prompt.BaseAgent;
				
				// Use Manager.activate_agent() to handle agent change
				// This routes to session.activate_agent() which handles AgentHandler creation/copying
				// and then triggers agent_activated signal for UI updates
				try {
					this.history_manager.activate_agent(this.history_manager.session.fid, agent.name);
				} catch (Error e) {
					GLib.warning("Failed to activate agent '%s': %s", agent.name, e.message);
				}
			});
			
			// Connect to session_activated signal to update when session changes
			this.history_manager.session_activated.connect((session) => {
				// Update agent selection to match session's agent
				var store = this.agent_dropdown.model as GLib.ListStore;
				if (store == null) {
					return;
				}
				
				for (uint j = 0; j < store.get_n_items(); j++) {
					if (((OLLMchat.Prompt.BaseAgent)store.get_item(j)).name != session.agent_name) {
						continue;
					}
					this.agent_dropdown.selected = j;
					break;
				}
			});
		}
		
		/**
		 * Updates the settings button icon and tooltip based on active pulls.
		 */
		private void update_settings_button()
		{
			// Count active pulls
			int active_count = 0;
			foreach (var entry in this.settings_dialog.pull_manager.models.entries) {
				if (entry.value.active) {
					active_count++;
				}
			}
			
			if (active_count > 0) {
				// Show spinner and hide icon when downloading
				this.settings_spinner.spinning = true;
				this.settings_spinner.visible = true;
				this.settings_icon.visible = false;
				this.settings_button.tooltip_text = "Settings - Downloading model";
				return;
			}
			
			// Hide spinner and show icon when not downloading
			this.settings_spinner.spinning = false;
			this.settings_spinner.visible = false;
			this.settings_icon.visible = true;
			this.settings_button.tooltip_text = "Settings";
		}
		
		/**
		 * Shows the settings dialog.
		 * 
		 * @param page_name Optional page name to switch to (e.g., "connections", "models")
		 * @since 1.0
		 */
		private void show_settings_dialog(string? page_name = null)
		{
			// Show settings dialog (already created in constructor)
			// Note: settings_dialog doesn't require history_manager, so we can show it anytime
			this.settings_dialog.show_dialog.begin(page_name);
		}
		/**
		 * Shows a warning dialog when connection fails, with option to configure settings.
		 * 
		 * @param error_message The error message to display
		 * @return The response string ("settings" or "cancel")
		 */
		private async string show_connection_error_dialog(string error_message)
		{
			var alert = new Adw.AlertDialog(
				"Connection Failed",
				error_message + "\n\nPlease check your connection settings and try again."
			);
			alert.add_response("cancel", "Close");
			alert.add_response("settings", "Configure");
			alert.set_response_appearance("settings", Adw.ResponseAppearance.SUGGESTED);
			
			var response = yield alert.choose(this, null);
			return response;
		}
		
	}
}
