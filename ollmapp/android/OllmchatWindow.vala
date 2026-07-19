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
	 * Android main window — chat-first shell with overlay history and modal settings.
	 *
	 * Same class name as desktop {@link OllmchatWindow} ({@code Window.vala}); Android
	 * builds this file instead of the desktop window.
	 *
	 * @since 1.0
	 */
	public class OllmchatWindow : Adw.ApplicationWindow, ChatUserInterface
	{
		public OLLMchat.ApplicationInterface app { get; construct; }
		public SettingsDialog.MainDialog settings_dialog { get; private set; }
		public OLLMchat.History.Manager history_manager { get; set; default = null; }

		public OLLMchatGtk.ChatWidget chat_widget { get; set; default = null; }

		private Gtk.Stack view_stack;
		private Gtk.Box chat_container;
		private Gtk.Box startup_panel;
		private Adw.HeaderBar header_bar;
		private Gtk.ToggleButton history_toggle_button;
		private Gtk.Button new_chat_button;
		public AgentDropdown agent_dropdown { get; set; }
		private OLLMchatGtk.HistoryBrowser? history_browser = null;
		private AndroidBootstrapConnectionAdd? bootstrap_dialog = null;
		public Gtk.Label startup_status_label;

		public OllmchatWindow(AndroidApplication app)
		{
			Object(application: app, app: app);
			AndroidTouchDebug.try_enable_from_storage ();
			if (OLLMchat.debug_on) {
				GLib.Log.set_default_handler ((dom, lvl, msg) => {
					GLib.stderr.printf (
						"%s: %s\n", dom ?? "", msg);
				});
			}
			this.title = "OLLMchat";
			this.set_default_size(420, 720);

			this.settings_dialog = new SettingsDialog.MainDialog(this);
			this.settings_dialog.closed.connect(() => {
				if (this.chat_widget != null) {
					this.chat_widget.chat_bar.sync_models.begin();
				}
			});

			var toolbar_view = new Adw.ToolbarView();
			this.header_bar = new Adw.HeaderBar();

			this.history_toggle_button = new Gtk.ToggleButton() {
				icon_name = "sidebar-show-symbolic",
				tooltip_text = "History",
				visible = false
			};
			this.header_bar.pack_start(this.history_toggle_button);

			this.new_chat_button = new Gtk.Button() {
				icon_name = "list-add-symbolic",
				tooltip_text = "New Chat",
				sensitive = false,
				visible = false
			};
			this.new_chat_button.clicked.connect(() => {
				if (this.history_manager == null || this.chat_widget == null) {
					return;
				}
				this.history_toggle_button.active = false;
				var new_session = this.history_manager.create_new_session();
				this.chat_widget.switch_to_session.begin(new_session);
			});
			this.header_bar.pack_start(this.new_chat_button);

			this.agent_dropdown = new AndroidAgentDropdown(this);
			this.header_bar.set_title_widget(this.agent_dropdown);

			var settings_button = new Gtk.Button() {
				icon_name = "applications-system-symbolic",
				tooltip_text = "Settings"
			};
			settings_button.clicked.connect(() => {
				this.settings_dialog.show_dialog.begin();
			});
			this.header_bar.pack_end(settings_button);

			this.header_bar.pack_end(new About());

			toolbar_view.add_top_bar(this.header_bar);

			this.chat_container = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = true,
			};
			this.startup_status_label = new Gtk.Label ("Connecting…") {
				margin_top = 8,
				halign = Gtk.Align.CENTER,
				wrap = true,
				wrap_mode = Pango.WrapMode.WORD,
				max_width_chars = 40,
			};
			var startup_spinner = new Gtk.Spinner () {
				halign = Gtk.Align.CENTER,
			};
			startup_spinner.start ();
			this.startup_panel = new Gtk.Box (
				Gtk.Orientation.VERTICAL, 12) {
				margin_top = 24,
				margin_bottom = 24,
				margin_start = 24,
				margin_end = 24,
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER,
				vexpand = true,
			};
			this.startup_panel.append (startup_spinner);
			this.startup_panel.append (this.startup_status_label);

			this.view_stack = new Gtk.Stack () {
				hexpand = true,
				vexpand = true,
				transition_type = Gtk.StackTransitionType.NONE,
				visible_child_name = "startup",
			};
			this.view_stack.add_named (this.startup_panel, "startup");
			this.view_stack.add_named (this.chat_container, "chat");

			this.history_toggle_button.toggled.connect(() => {
				var showing = this.history_toggle_button.active;
				if (showing) {
					this.view_stack.visible_child_name = "history";
					this.history_toggle_button.icon_name =
						"sidebar-hide-symbolic";
					if (this.history_browser == null) {
						return;
					}
					GLib.Idle.add(() => {
						this.history_browser.scrolled_window.vadjustment.value = 0;
						this.history_browser.search_entry.grab_focus();
						return false;
					});
					return;
				}
				this.view_stack.visible_child_name = "chat";
				this.history_toggle_button.icon_name =
					"sidebar-show-symbolic";
			});

			if (AndroidTouchDebug.enabled) {
				var touch_hud = new Gtk.Label ("") {
					halign = Gtk.Align.FILL,
					valign = Gtk.Align.END,
					margin_bottom = 8,
					margin_start = 8,
					margin_end = 8,
					wrap = true,
					selectable = true,
					css_classes = { "dim-label" },
				};
				var content_overlay = new Gtk.Overlay ();
				content_overlay.set_child (this.view_stack);
				content_overlay.add_overlay (touch_hud);
				toolbar_view.content = content_overlay;
				new AndroidTouchDebug (this, touch_hud);
			} else {
				toolbar_view.content = this.view_stack;
			}
			this.content = toolbar_view;

			(this as Gtk.Widget).realize.connect(() => {
				this.load_config_and_initialize.begin();
			});
		}

		private async void load_config_and_initialize()
		{
			this.app.config = (this.app as AndroidApplication).load_config();
			AndroidConnectionConfigTls.apply_to_config(this.app.config);
			AndroidToolsRegistration.setup_config_defaults(this.app.config);

			if (this.app.config.connections.size == 0) {
				GLib.message (
					"OllmchatWindow: connections=0 showing bootstrap");
				yield this.show_bootstrap_dialog("");
				return;
			}

			var startup = new AndroidStartup(this);
			startup.reinitialize.connect(() => {
				this.load_config_and_initialize.begin();
			});

			this.view_stack.visible_child_name = "startup";
			this.startup_status_label.label = "Connecting…";

			if (yield startup.run(this.app.config)) {
				this.startup_status_label.label = "Opening chat…";
				this.app.config = (this.app as AndroidApplication).load_config();
				AndroidConnectionConfigTls.apply_to_config(this.app.config);
				yield this.initialize_client(this.app.config);
				return;
			}

			this.chat_container.append (new Gtk.Label(
				"Could not start chat. Open Settings to verify your connection and model."
			) {
				margin_top = 24,
				margin_bottom = 24,
				margin_start = 24,
				margin_end = 24,
				wrap = true,
				vexpand = true,
			});
			this.view_stack.visible_child_name = "chat";
		}

		private async void show_bootstrap_dialog(string error_message)
		{
			if (this.bootstrap_dialog == null) {
				this.bootstrap_dialog = new AndroidBootstrapConnectionAdd();
			}
			this.bootstrap_dialog.show_bootstrap();

			if (error_message != "") {
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

			this.bootstrap_dialog.closed.connect(() => {
				if (this.bootstrap_dialog.verified_connection == null) {
					(this.app as Gtk.Application).quit();
					return;
				}

				this.bootstrap_dialog.verified_connection.is_default = true;
				this.bootstrap_dialog.verified_connection.name = "Default";

				var config = new OLLMchat.Settings.Config2();
				config.connections.set(
					this.bootstrap_dialog.verified_connection.url,
					this.bootstrap_dialog.verified_connection
				);
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

				this.app.config = config;
				AndroidToolsRegistration.setup_config_defaults(config);
				(this.app as AndroidApplication).persist_config (config);
				this.initialize_after_bootstrap.begin(config);
			});

			this.bootstrap_dialog.present(this);
		}

		private async void initialize_after_bootstrap(OLLMchat.Settings.Config2 config)
		{
			var startup = new AndroidStartup(this);
			startup.reinitialize.connect(() => {
				this.load_config_and_initialize.begin();
			});

			this.view_stack.visible_child_name = "startup";
			this.startup_status_label.label = "Connecting…";

			if (yield startup.run(config)) {
				this.startup_status_label.label = "Opening chat…";
				yield this.initialize_client(config);
				return;
			}

			this.chat_container.append (new Gtk.Label(
				"Could not start chat. Open Settings to verify your connection and model."
			) {
				margin_top = 24,
				margin_bottom = 24,
				margin_start = 24,
				margin_end = 24,
				wrap = true,
				vexpand = true,
			});
			this.view_stack.visible_child_name = "chat";
		}

		private async void initialize_client(OLLMchat.Settings.Config2 config)
		{
			if (this.history_manager == null) {
				return;
			}

			this.startup_status_label.label = "Loading models…";
			yield this.history_manager.connection_models.refresh();

			this.register_default_agents();

			this.agent_dropdown.wire();

			this.new_chat_button.sensitive = true;
			this.new_chat_button.visible = true;

			this.history_browser = new OLLMchatGtk.HistoryBrowser(this.history_manager) {
				hexpand = true,
				vexpand = true,
			};
			this.view_stack.add_named (this.history_browser, "history");
			this.history_toggle_button.visible = true;

			this.setup_chat_widget(
				this.app as Gtk.Application,
				GLib.Path.build_filename(this.app.data_dir, "config"));

			this.history_browser.session_selected.connect((session) => {
				this.history_toggle_button.active = false;
				this.chat_widget.switch_to_session.begin(session);
			});

			this.connect_agent_factory_signals();

			this.history_manager.agent_status_change.connect(() => {
				var running = this.history_manager.session.is_running;
				android_set_partial_wake_lock(this, running);
				android_set_streaming_foreground(this, running);
			});
			android_set_partial_wake_lock(
				this, this.history_manager.session.is_running);
			android_set_streaming_foreground(
				this, this.history_manager.session.is_running);

			this.chat_container.append (this.chat_widget);
			this.view_stack.visible_child_name = "chat";

			GLib.message (
				"OllmchatWindow: initialize_client agents=%u",
				this.history_manager.agent_factories.size);

			yield this.activate_session_and_sync_ui();
		}
	}

	[CCode (cname = "ollmapp_configure_android_gio_tls_modules", cheader_filename = "android-gio-tls.h")]
	private extern bool configure_android_gio_tls_modules();

	[CCode (cname = "ollmapp_android_set_partial_wake_lock", cheader_filename = "android-partial-wake-lock.h")]
	private extern void android_set_partial_wake_lock(Gtk.Window window, bool enable);

	[CCode (cname = "ollmapp_android_set_streaming_foreground", cheader_filename = "android-partial-wake-lock.h")]
	private extern void android_set_streaming_foreground(Gtk.Window window, bool enable);

	int main(string[] args)
	{
		AndroidTouchDebug.parse_args (args);
		if (OLLMchat.debug_on) {
			GLib.Log.set_default_handler ((dom, lvl, msg) => {
				GLib.stderr.printf (
					"%s: %s\n", dom ?? "", msg);
			});
		}

		configure_android_gio_tls_modules();
		var app = new AndroidApplication();
		return app.run(args);
	}
}
