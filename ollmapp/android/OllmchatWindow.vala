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

// Normally no using. FilesdClient.State.* without this is
// OLLMchat.Settings.FilesdClient.State.* at every site.
using OLLMchat.Settings;

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
	public class OllmchatWindow : Adw.ApplicationWindow, ChatUserInterface, OLLMchat.ChatDesktopInterface
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
		private Adw.Banner tool_error_banner;
		private Adw.ViewStack pane_stack;
		private bool is_tablet = false;
		private Gtk.Button chat_picker;
		private Gtk.Button browser_picker;
		private Gtk.Button editor_picker;
		private uint fog_source = 0;
		public OLLMfiles.ProjectManager? project_manager { 
			get; private set; default = null; }
		/**
		 * UUID key into {@link OLLMchat.Settings.Config2.windows}.
		 */
		public string uuid { get; private set; default = ""; }

		public OLLMchat.Settings.Window window_config()
		{
			if (this.uuid != "") {
				return this.app.config.windows.get(this.uuid);
			}
			if (this.app.config.windows.size == 0) {
				this.uuid = GLib.Uuid.string_random();
				this.app.config.windows.set(
					this.uuid,
					new OLLMchat.Settings.Window()
				);
				this.app.config.save();
				return this.app.config.windows.get(this.uuid);
			}
			foreach (var entry in this.app.config.windows.entries) {
				this.uuid = entry.key;
				return entry.value;
			}
			GLib.error("windows map non-empty but no entries");
		}

		public OLLMchat.Agent.Base? session_agent()
		{
			return this.history_manager.session.agent;
		}

		public GLib.Object above_input_widget()
		{
			return this.chat_widget.above_input;
		}

		public OLLMchat.MessageQueue chat_message_queue()
		{
			return this.chat_widget.queue_view.queue;
		}

		public GLib.Object tab_view()
		{
			return this.pane_stack;
		}

		public void schedule_pane_update(bool visible)
		{
			if (this.is_tablet) {
				this.pane_stack.visible = visible;
			}
			if (!this.is_tablet) {
				this.chat_widget.view_stack.visible_child_name = visible ? "pane" : "chat";
			}
			this.browser_picker.remove_css_class("picker-on");
			this.editor_picker.remove_css_class("picker-on");
			this.chat_picker.remove_css_class("picker-on");
			if (!visible) {
				this.chat_picker.add_css_class("picker-on");
				return;
			}
			if (this.pane_stack.visible_child_name == "browser") {
				this.browser_picker.add_css_class("picker-on");
				return;
			}
			this.editor_picker.add_css_class("picker-on");
		}

		public void scroll_to_message(int idx)
		{
			if (idx < 0) {
				return;
			}
			this.chat_widget.chat_view.scroll_to_idx(idx);
		}

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
				if (this.history_manager == null) {
					return;
				}
				foreach (var entry in this.app.config.tools.entries) {
					if (!this.history_manager.tools.has_key(entry.key)) {
						continue;
					}
					this.history_manager.tools.get(entry.key).active = entry.value.enabled;
				}
			});
			this.tool_error_banner = new Adw.Banner("") {
				button_label = "Dismiss",
				revealed = false
			};
			this.tool_error_banner.button_clicked.connect(() => {
				this.tool_error_banner.revealed = false;
			});
			this.notification.connect((notif) => {
				if (notif.method == "Banner.show") {
					this.tool_error_banner.title = notif.message;
					this.tool_error_banner.revealed = true;
					return;
				}
				if (notif.method != "Alert.show") {
					return;
				}
				var alert = new Adw.AlertDialog("Alert", notif.message);
				alert.add_response("ok", "OK");
				alert.choose.begin(this, null);
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
			toolbar_view.add_top_bar(this.tool_error_banner);

			this.chat_container = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = true,
			};
			this.pane_stack = new Adw.ViewStack() {
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

			this.is_tablet = android_is_tablet(this);
			if (this.is_tablet) {
				android_lock_landscape(this);
			}

			this.project_manager = new OLLMfiles.ProjectManager();
			this.project_manager.buffer_provider = new OLLMcoder.BufferProvider();
			var desktop_checked = false;
			var desktop_reached = false;
			if (config.filesd_client.url != ""
				&& (config.filesd_client.state == FilesdClient.State.ENABLED
					|| config.filesd_client.state == FilesdClient.State.LIVE
					|| config.filesd_client.state == FilesdClient.State.UNREACHABLE
					|| config.filesd_client.state == FilesdClient.State.SOCKET)) {
				desktop_checked = true;
				this.startup_status_label.label = "Checking desktop environment…";
				var tls = new OLLMrpc.Transport.Cert() {
					dir = GLib.Path.build_filename(
						GLib.Environment.get_user_data_dir(), "ollmchat"),
					cert_pem = "client.pem",
					key_pem = "client-key.pem",
					cn = "ollmchat-device",
					product_ca_resource = true,
				};
				tls.ensure();
				var http = new OLLMrpc.Transport.HttpClient(config.filesd_client.url) {
					bin_body = true,
					tls_certificate = tls.certificate,
					tls_database = tls.trust
				};
				http.soup.timeout = 15;
				this.project_manager.replace_rpc(
					new OLLMrpc.Client("", "", config.filesd_client.url) { 
						http = http 
					}
				);
				var hello = new OLLMrpc.Request() {
					method = "RPC-Daemon.hello",
					args = OLLMrpc.args("is", 1, "ollmchat")
				};
				desktop_reached = yield this.project_manager.rpc.connect(hello);
				http.soup.timeout = 0;
				if (!desktop_reached) {
					var msg = this.project_manager.rpc.connect_error;
					if (msg == "") {
						msg = "could not reach the file server";
					}
					GLib.warning("%s", msg);
				}
				this.startup_status_label.label = "Opening chat…";
			}
			this.project_manager.notification.connect((notif) => {
				GLib.Idle.add(() => {
					this.notification(notif);
					return false;
				});
			});

			this.register_default_agents();

			if (!this.history_manager.tools.has_key("write")) {
				this.history_manager.register_tool(
					new OLLMtools.EditMode.Write(this.project_manager));
			}
			if (!this.history_manager.tools.has_key("read")) {
				this.history_manager.register_tool(
					new OLLMtools.ReadFile.Read(this.project_manager));
			}
			if (!this.history_manager.agent_factories.has_key("agent-pi")) {
				var agent_pi = new OLLMcoder.AgentPi.Factory(this.project_manager);
				this.history_manager.agent_factories.set(agent_pi.name, agent_pi);
			}

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

			// avoid async vala ctor bug
			this.browser_picker = new Gtk.Button();
			this.browser_picker.icon_name = "web-browser-symbolic";
			this.browser_picker.tooltip_text = "Browser";
			this.editor_picker = new Gtk.Button();
			this.editor_picker.icon_name = "document-edit-symbolic";
			this.editor_picker.tooltip_text = "Text editor";
			this.chat_picker = new Gtk.Button();
			this.chat_picker.icon_name = "chat-message-new-symbolic";
			this.chat_picker.tooltip_text = "Chat";
			this.chat_picker.visible = !this.is_tablet;
			this.chat_picker.add_css_class("picker-on");
			this.chat_widget.chat_bar.end_box.append(this.browser_picker);
			this.chat_widget.chat_bar.end_box.append(this.editor_picker);
			this.chat_widget.chat_bar.end_box.append(this.chat_picker);
			this.chat_widget.chat_bar.end_box.visible = true;
			this.chat_widget.chat_bar.tool_button_box.visible = false;
			this.chat_picker.clicked.connect(() => {
				this.schedule_pane_update(false);
			});
			this.browser_picker.clicked.connect(() => {
				var ui = this.history_manager.tools.get("browser") as OLLMchat.Tool.UiWidgets;
				var view = (Gtk.Widget) ui.view_widget;
				if (this.pane_stack.get_child_by_name("browser") == null) {
					this.pane_stack.add_named(view, "browser");
				}
				this.pane_stack.set_visible_child_name("browser");
				this.schedule_pane_update(true);
			});
			this.editor_picker.clicked.connect(() => {
				var factory = this.history_manager.agent_factories.get("agent-pi");
				factory.activate.begin(this, (obj, res) => {
					factory.activate.end(res);
				});
			});

			this.history_browser.session_selected.connect((session) => {
				this.history_toggle_button.active = false;
				this.chat_widget.switch_to_session.begin(session);
			});

			this.connect_agent_factory_signals();

			if (desktop_checked && desktop_reached) {
				var empty = this.history_manager.create_new_session();
				empty.project_path = this.history_manager.session.project_path;
				empty.agent_name = "agent-pi";
				yield this.chat_widget.switch_to_session(empty);
				config.filesd_client.state = FilesdClient.State.LIVE;
				this.app.config.save();
			}
			if (desktop_checked && !desktop_reached) {
				config.filesd_client.state = FilesdClient.State.UNREACHABLE;
				this.app.config.save();
				this.notification(new OLLMrpc.Notification() {
					method = "Banner.show",
					message = "The desktop environment is unavailable."
				});
				var empty = this.history_manager.create_new_session();
				empty.project_path = this.history_manager.session.project_path;
				empty.agent_name = "chatter";
				yield this.chat_widget.switch_to_session(empty);
			}

			this.history_manager.agent_status_change.connect(() => {
				var running = this.history_manager.session.is_running;
				android_set_partial_wake_lock(this, running);
				android_set_streaming_foreground(this, running);
				if (this.fog_source != 0) {
					GLib.Source.remove(this.fog_source);
					this.fog_source = 0;
				}
				var image = (Gtk.Image) this.chat_picker.child;
				if (!running) {
					image.set_from_icon_name("chat-message-new-symbolic");
					return;
				}
				string[] frames = {
					"/icons/ollm-fog-1-symbolic.svg",
					"/icons/ollm-fog-2-symbolic.svg",
					"/icons/ollm-fog-3-symbolic.svg"
				};
				var frame = 0;
				image.set_from_resource(frames[frame]);
				this.fog_source = GLib.Timeout.add(400, () => {
					frame++;
					frame = frame > 2 ? 0 : frame;
					image.set_from_resource(frames[frame]);
					return true;
				});
			});
			android_set_partial_wake_lock(
				this, this.history_manager.session.is_running);
			android_set_streaming_foreground(
				this, this.history_manager.session.is_running);

			if (this.is_tablet) {
				var columns = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
					hexpand = true,
					vexpand = true,
				};
				this.chat_widget.hexpand = true;
				this.chat_widget.vexpand = true;
				columns.append(this.chat_widget);
				this.pane_stack.visible = false;
				columns.append(this.pane_stack);
				this.chat_container.append(columns);
			} else {
				this.chat_widget.view_stack.add_named(this.pane_stack, "pane");
				this.chat_container.append(this.chat_widget);
			}
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

	[CCode (cname = "ollmapp_android_is_tablet", cheader_filename = "android-partial-wake-lock.h")]
	private extern bool android_is_tablet(Gtk.Window window);

	[CCode (cname = "ollmapp_android_lock_landscape", cheader_filename = "android-partial-wake-lock.h")]
	private extern void android_lock_landscape(Gtk.Window window);

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
		OLLMwebkit.WebDriver.instance = new OLLMwebkit.WebDriver();
		try {
			OLLMwebkit.WebDriver.instance.prepare();
		} catch (GLib.Error e) {
			GLib.warning("%s", e.message);
		}
		var app = new AndroidApplication();
		return app.run(args);
	}
}
