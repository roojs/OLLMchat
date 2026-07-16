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
	 /* Main application window for OLLMchat.
	 * 
	 * This is the primary window that provides the chat interface.
	 * 
	 * @since 1.0
	 */
	public class OllmchatWindow : Adw.Window, OLLMapp.ChatUserInterface, OLLMchat.ChatDesktopInterface
	{
		public OLLMchatGtk.ChatWidget chat_widget { get; set; default = null; }
		public OLLMchat.History.Manager history_manager { get; set; default = null; }
		private Adw.OverlaySplitView split_view;
		private OLLMchatGtk.HistoryBrowser? history_browser = null;
		private Gtk.Button new_chat_button;
		public OLLMchat.ApplicationInterface app;
		public WindowPane window_pane { get; private set; }
		public AgentDropdown agent_dropdown { get; set; }
		private Adw.HeaderBar header_bar;
		private Gtk.ToggleButton history_toggle_button;
		private uint history_leave_ignore_timeout_id = 0;
		private SettingsDialog.ConnectionAdd? bootstrap_dialog = null;
		internal SettingsDialog.MainDialog? settings_dialog = null;
		private Gtk.Button settings_button;
		private Gtk.Spinner settings_spinner;
		private Gtk.Image settings_icon;
		private Adw.Banner tool_error_banner;
		private FileChangeBanner file_change_banner;
		private ActivityBanner activity_banner;
		public OLLMfiles.ProjectManager? project_manager { get; private set; default = null; }
		internal BusyDialog? busy_dialog = null;

		public OLLMchat.Agent.Base? session_agent()
		{
			return this.history_manager.session.agent;
		}

		public GLib.Object above_input_widget()
		{
			return this.chat_widget.above_input;
		}

		public GLib.Object tab_view()
		{
			return this.window_pane.tab_view;
		}

		public void schedule_pane_update(bool visible)
		{
			this.window_pane.schedule_pane_update(visible);
		}

		public void scroll_to_message(int idx)
		{
			if (idx < 0) {
				return;
			}
			this.chat_widget.chat_view.scroll_to_idx(idx);
		}

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
				this.chat_widget.chat_bar.sync_models.begin();
			});

			// Create toolbar view to manage header bar and content
			var toolbar_view = new Adw.ToolbarView();
			
			// Create header bar with toggle button and new chat button
			this.header_bar = new Adw.HeaderBar();
			this.history_toggle_button = new Gtk.ToggleButton() {
				icon_name = "sidebar-show-symbolic",
				tooltip_text = "Toggle History",
				visible = false
			};
			this.header_bar.pack_start(this.history_toggle_button);
			
			this.new_chat_button = new Gtk.Button() {
				icon_name = "list-add-symbolic",
				tooltip_text = "New Chat",
				sensitive = false
			};
			this.header_bar.pack_start(this.new_chat_button);
			
			// Connect new chat button to create new session
			this.new_chat_button.clicked.connect(() => {
				var new_session = this.history_manager.create_new_session();
				if (this.project_manager != null && this.project_manager.active_project != null) {
					new_session.project_path = this.project_manager.active_project.path;
				}
				this.chat_widget.switch_to_session.begin(new_session);
			});
			
			this.agent_dropdown = new AgentDropdown(this);
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
				this.settings_dialog.show_dialog.begin("");
			});
			this.header_bar.pack_start(this.settings_button);
			
			// Create about button
			var about_button = new About();
			this.header_bar.pack_start(about_button);
			
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
			this.activity_banner = new ActivityBanner();

			this.notification.connect((notif) => {
				this.activity_banner.notification(notif);
			});
				
			// Add header bar to toolbar view's top slot
			toolbar_view.add_top_bar(this.header_bar);
			
			// Add tool error banner below header bar
			toolbar_view.add_top_bar(this.tool_error_banner);
			
			// Add file change banner below tool error banner
			toolbar_view.add_top_bar(this.file_change_banner.revealer);
			
			// Add vector scan banner below file change banner
			toolbar_view.add_top_bar(this.activity_banner.revealer);

			// Create overlay split view
			this.split_view = new Adw.OverlaySplitView();
			this.split_view.show_sidebar = false; // Hidden at start
			// Set sidebar width as fraction of total width (0.25 = 25% of window width)
			this.split_view.set_sidebar_width_fraction(0.25);
			
			// Connect toggle button to show/hide sidebar
			this.history_toggle_button.toggled.connect(() => {
				this.split_view.show_sidebar = this.history_toggle_button.active;
				this.history_toggle_button.icon_name = this.history_toggle_button.active ? "sidebar-hide-symbolic" : "sidebar-show-symbolic";
				if (this.history_toggle_button.active) {
					// Ignore mouse leave for 1s after expanding so movements don't immediately close it
					if (this.history_leave_ignore_timeout_id != 0) {
						GLib.Source.remove(this.history_leave_ignore_timeout_id);
						this.history_leave_ignore_timeout_id = 0;
					}
					this.history_leave_ignore_timeout_id = GLib.Timeout.add_seconds(1, () => {
						this.history_leave_ignore_timeout_id = 0;
						return false;
					});
					// Scroll to top and focus search when expanding history sidebar
					// in theroy history browse might not exist but its so unlikely we dont check
					GLib.Idle.add(() => {
						this.history_browser.scrolled_window.vadjustment.value = 0;
						this.history_browser.search_entry.grab_focus();
						return false;
					});
				} else {
					if (this.history_leave_ignore_timeout_id != 0) {
						GLib.Source.remove(this.history_leave_ignore_timeout_id);
						this.history_leave_ignore_timeout_id = 0;
					}
				}
			});

			// Set split view as toolbar view content
			toolbar_view.content = this.split_view;
			
			// Set toolbar view as window content
			this.set_content(toolbar_view);

			// Defer resuming interrupted model pulls by 1 minute so startup (network, UI) settles first
			(this as Gtk.Widget).realize.connect(() => {
				GLib.Timeout.add_seconds(60, () => {
					this.settings_dialog.pull_manager.restart();
					// Update button state after restart (in case there are active pulls)
					this.update_settings_button();
					return false;
				});
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
				//GLib.debug("Config not loaded, showing bootstrap dialog");
				yield this.show_bootstrap_dialog("");
				return;
			}

			if (this.busy_dialog == null) {
				this.busy_dialog =
					new BusyDialog(this);
			}
			this.busy_dialog.status_label.label =
				"Connecting to LLM server…";
			this.busy_dialog.present(this);
			
			//GLib.debug("Config loaded successfully, initializing client");
			var initializer = new Initialize(this);
			initializer.reinitialize.connect(() => {
				this.load_config_and_initialize.begin();
			});
			
			if (yield initializer.run(this.app.config)) {
				// Both connection and model verified, proceed with initialization
				yield this.initialize_client(this.app.config);
			}
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

				var app = this.app as OllmchatApplication;
				config.connections.set(this.bootstrap_dialog.verified_connection.url,
					this.bootstrap_dialog.verified_connection);
				app.tools_registry.setup_config_defaults(config);
				
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
				// Update app config to match bootstrap config
				this.app.config = config;
				// Connection verified in bootstrap dialog, but model still needs verification
				// Use Initialize to handle model verification
				this.initialize_after_bootstrap.begin(config);
			});
			
			this.bootstrap_dialog.present(this);
		}
		
		/**
		 * Initializes after bootstrap dialog completes.
		 * 
		 * @param config The Config2 instance
		 */
		private async void initialize_after_bootstrap(OLLMchat.Settings.Config2 config)
		{
			if (this.busy_dialog == null) {
				this.busy_dialog =
					new BusyDialog(this);
			}
			this.busy_dialog.status_label.label =
				"Connecting to LLM server…";
			this.busy_dialog.present(this);

			var initializer = new Initialize(this);
			initializer.reinitialize.connect(() => {
				this.load_config_and_initialize.begin();
			});
			
			if (yield initializer.run(config)) {
				// Both connection and model verified, proceed with initialization
				yield this.initialize_client(config);
			}
		}
		

		/**
		 * Initializes the client and sets up the UI.
		 * Assumes connection and model have already been verified.
		 * 
		 * @param config The Config2 instance (contains connection and model configuration)
		 */
		private async void initialize_client(OLLMchat.Settings.Config2 config)
		{
			// History manager already created in initialize_unverified_client
			// (model verification creates it)
			
			// Check all connections and set is_working flags before refreshing models
			
			// Refresh connection models after connection validation (version tests completed)
			yield this.history_manager.connection_models.refresh();
			
			this.project_manager = new OLLMfiles.ProjectManager();
			this.project_manager.buffer_provider = new OLLMcoder.BufferProvider();

			if (this.busy_dialog != null) {
				this.busy_dialog.status_label.label =
					"Connecting to filesystem daemon…";
			}

			var hello = new OLLMrpc.Request() {
				method = "Daemon.hello",
				param = new OLLMfilesd.DaemonParams() {
					protocol = 1,
					client = "ollmchat"
				}
			};
			if (!yield this.project_manager.rpc.connect(hello)) {
				if (this.busy_dialog != null) {
					this.busy_dialog.close();
				}
				var msg = this.project_manager.rpc.connect_error;
				if (msg == "") {
					msg = "could not start or reach the filesystem daemon (ollmfilesd)";
				}
				GLib.warning("ollmchat: %s", msg);
				this.tool_error_banner.title = "Filesystem daemon: " + msg;
				this.tool_error_banner.revealed = true;
				return;
			}

			if (this.busy_dialog != null) {
				this.busy_dialog.status_label.label =
					"Preparing agents…";
			}

			this.project_manager.rpc.notification.connect((notif) => {
				GLib.Idle.add(() => {
					this.notification(notif);
					return false;
				});
			});

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
			
			// Register all tools with proper initialization (passing project_manager to constructors)
			// Use library-level registries from Application to register tools
			var app = this.app as OllmchatApplication;
			app.tools_registry.fill_tools(this.history_manager, this.project_manager);
			app.mcp_registry.fill_tools(this.history_manager, this.project_manager);

			// Register CodeAssistant agent
			var code_assistant = new OLLMcoder.AgentFactory(this.project_manager);
			this.history_manager.agent_factories.set(code_assistant.name, code_assistant);

			// Register SkillRunner (Conductor) agent: factory creates SkillManager from directories
			// big FIXME - we will need t change this.
			var skills_dirs = new Gee.ArrayList<string>();
			skills_dirs.add(
				GLib.Path.build_filename(
					GLib.Environment.get_home_dir(), "gitlive", "OLLMchat", "resources", "skills"));
					
			var skill_runner = new OLLMcoder.Skill.Factory(this.project_manager, skills_dirs, "");
			this.history_manager.agent_factories.set(skill_runner.name, skill_runner);

			this.register_default_agents();

			// Set up agent dropdown now that agents are registered
			this.agent_dropdown.session_selection.connect(
				(session, agent_index) => {
					if (session.project_path == "") {
						return false;
					}
					var project = this.project_manager.projects.path_map.get(
						session.project_path);
					if (project != null) {
						this.project_manager.activate_project(project);
						this.agent_dropdown.selected = agent_index;
						return true;
					}
					this.notification(new OLLMrpc.Notification() {
						method = "client.project.load_start",
					});
					this.project_manager.load_projects_from_db.begin((obj, res) => {
						this.project_manager.load_projects_from_db.end(res);
						this.notification(new OLLMrpc.Notification() {
							method = "client.project.load_end",
						});
						project = this.project_manager.projects.path_map.get(
							session.project_path);
						if (project == null) {
							GLib.warning(
								"Session project_path '%s' not found in project list",
								session.project_path);
							return;
						}
						this.project_manager.activate_project(project);
						this.agent_dropdown.selected = agent_index;
					});
					return true;
				});
			this.agent_dropdown.wire();

			this.new_chat_button.sensitive = true;

			if (this.busy_dialog != null) {
				this.busy_dialog.close();
			}
			
			// Create history browser and add to split view sidebar
			this.history_browser = new OLLMchatGtk.HistoryBrowser(this.history_manager);
			this.split_view.sidebar = this.history_browser;
			this.history_toggle_button.visible = true;
			
			// Hide sidebar when mouse leaves the history panel (e.g. after selecting a history item to restore).
			// Ignore leave during the 1s after expanding (history_leave_ignore_timeout_id != 0).
			var sidebar_motion = new Gtk.EventControllerMotion();
			sidebar_motion.leave.connect(() => {
				if (this.split_view.show_sidebar && this.history_leave_ignore_timeout_id == 0) {
					//GLib.debug("Window: hiding sidebar (mouse leave)");
					this.history_toggle_button.active = false;
				}
			});
			this.history_browser.add_controller(sidebar_motion);
			
			// Connect history browser to load sessions
			this.history_browser.session_selected.connect((session) => {
				// switch_to_session() handles loading internally via load()
				this.chat_widget.switch_to_session.begin(session);
			});

			// Create chat widget with manager
			this.setup_chat_widget(
				this.app as Gtk.Application,
				GLib.Path.build_filename(
					GLib.Environment.get_home_dir(), ".config", "ollmchat"
				));

			// Create WindowPane to manage chat widget and agent widgets
			this.window_pane = new WindowPane();
			
			// Set chat widget as start child (left pane)
			this.window_pane.paned.set_start_child(this.chat_widget);
			this.window_pane.paned.set_resize_start_child(true);
			
			// Agent UI: factories receive this window as ChatDesktopInterface (§3b)
			this.connect_agent_factory_signals();

			// Set WindowPane as main content
			this.split_view.content = this.window_pane;

			/* Loading UI finished — focus composer entry (not after streaming). */
			GLib.Idle.add(this.chat_widget.chat_input.focus_idle);
		}
		
		/**
		 * Updates the settings button icon and tooltip based on active pulls.
		 */
		private void update_settings_button()
		{
			// Count active pulls
			var active_count = 0;
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
		 * Shows a warning dialog when initialization fails, with option to configure settings.
		 *
		 * @param error_message The error message to display
		 * @param dialog_title Alert title (e.g. connection, chat model, or required-models failure)
		 * @return The response string ("settings" or "cancel")
		 */
		internal async string show_connection_error_dialog(
			string error_message,
			string dialog_title
		) {
			var alert = new Adw.AlertDialog(
				dialog_title,
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
