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
	 * @since 1.0
	 */
	public class AndroidMainWindow : Adw.ApplicationWindow
	{
		public AndroidApplication app { get; construct; }
		public AndroidSettingsDialog settings_dialog { get; private set; }
		public OLLMchat.History.Manager? history_manager { get; set; default = null; }

		public OLLMchatGtk.ChatWidget? chat_widget { get; private set; }

		private Adw.OverlaySplitView split_view;
		private Adw.HeaderBar header_bar;
		private Gtk.ToggleButton history_toggle_button;
		private Gtk.Button new_chat_button;
		private Gtk.DropDown agent_dropdown;
		private OLLMchatGtk.HistoryBrowser? history_browser = null;
		private AndroidBootstrapConnectionAdd? bootstrap_dialog = null;
		private uint history_leave_ignore_timeout_id = 0;
		private string[] agent_picker_names = {};
		private Gtk.Label? startup_status_label = null;

		/**
		 * Updates the startup progress label shown while connecting.
		 *
		 * @param message Status text for the user
		 */
		public void set_startup_status (string message)
		{
			if (this.startup_status_label != null) {
				this.startup_status_label.label = message;
			}
		}

		private void show_startup_panel (string message)
		{
			this.startup_status_label = new Gtk.Label (message) {
				margin_top = 8,
				halign = Gtk.Align.CENTER,
				wrap = true,
				wrap_mode = Pango.WrapMode.WORD,
				max_width_chars = 40,
			};
			var spinner = new Gtk.Spinner () {
				halign = Gtk.Align.CENTER,
			};
			spinner.start ();
			var panel = new Gtk.Box (
				Gtk.Orientation.VERTICAL, 12) {
				margin_top = 24,
				margin_bottom = 24,
				margin_start = 24,
				margin_end = 24,
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER,
				vexpand = true,
			};
			panel.append (spinner);
			panel.append (this.startup_status_label);
			this.split_view.content = panel;
		}

		public AndroidMainWindow(AndroidApplication app)
		{
			Object(application: app, app: app);
			this.title = "OLLMchat";
			this.set_default_size(420, 720);

			this.settings_dialog = new AndroidSettingsDialog(this.app, this);
			this.settings_dialog.closed.connect(() => {
				if (this.chat_widget != null) {
					this.chat_widget.update_models.begin();
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
				var new_session = this.history_manager.create_new_session();
				this.chat_widget.switch_to_session.begin(new_session);
			});
			this.header_bar.pack_start(this.new_chat_button);

			this.agent_dropdown = new Gtk.DropDown (null, null) {
				hexpand = false
			};
			this.header_bar.pack_start(this.agent_dropdown);

			var settings_button = new Gtk.Button() {
				icon_name = "applications-system-symbolic",
				tooltip_text = "Settings"
			};
			settings_button.clicked.connect(() => {
				this.settings_dialog.show_dialog.begin("");
			});
			this.header_bar.pack_end(settings_button);

			this.header_bar.pack_end(new About());

			toolbar_view.add_top_bar(this.header_bar);

			this.split_view = new Adw.OverlaySplitView() {
				show_sidebar = false
			};
			this.split_view.set_sidebar_width_fraction(0.85);

			this.history_toggle_button.toggled.connect(() => {
				this.split_view.show_sidebar = this.history_toggle_button.active;
				this.history_toggle_button.icon_name =
					this.history_toggle_button.active
						? "sidebar-hide-symbolic"
						: "sidebar-show-symbolic";
				if (this.history_toggle_button.active) {
					if (this.history_leave_ignore_timeout_id != 0) {
						GLib.Source.remove(this.history_leave_ignore_timeout_id);
						this.history_leave_ignore_timeout_id = 0;
					}
					this.history_leave_ignore_timeout_id =
						GLib.Timeout.add_seconds(1, () => {
							this.history_leave_ignore_timeout_id = 0;
							return false;
						});
					if (this.history_browser != null) {
						GLib.Idle.add(() => {
							this.history_browser.scrolled_window.vadjustment.value = 0;
							this.history_browser.search_entry.grab_focus();
							return false;
						});
					}
					return;
				}
				if (this.history_leave_ignore_timeout_id != 0) {
					GLib.Source.remove(this.history_leave_ignore_timeout_id);
					this.history_leave_ignore_timeout_id = 0;
				}
			});

			toolbar_view.content = this.split_view;
			this.content = toolbar_view;

			(this as Gtk.Widget).realize.connect(() => {
				this.load_config_and_initialize.begin();
			});
		}

		private async void load_config_and_initialize()
		{
			this.app.config = this.app.load_config();
			AndroidConnectionConfigTls.apply_to_config(this.app.config);

			if (this.app.config.connections.size == 0) {
				GLib.message (
					"AndroidMainWindow: connections=0 showing bootstrap");
				yield this.show_bootstrap_dialog("");
				return;
			}

			var startup = new AndroidStartup(this);
			startup.reinitialize.connect(() => {
				this.load_config_and_initialize.begin();
			});

			this.show_startup_panel ("Connecting…");

			if (yield startup.run(this.app.config)) {
				this.set_startup_status ("Opening chat…");
				this.app.config = this.app.load_config();
				AndroidConnectionConfigTls.apply_to_config(this.app.config);
				yield this.initialize_client(this.app.config);
				return;
			}

			if (this.chat_widget == null) {
				this.split_view.content = new Gtk.Label(
					"Could not start chat. Open Settings to verify your connection and model."
				) {
					margin_top = 24,
					margin_bottom = 24,
					margin_start = 24,
					margin_end = 24,
					wrap = true,
					vexpand = true,
				};
			}
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
				this.app.persist_config (config);
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

			this.show_startup_panel ("Connecting…");

			if (yield startup.run(config)) {
				this.set_startup_status ("Opening chat…");
				yield this.initialize_client(config);
				return;
			}

			if (this.chat_widget == null) {
				this.split_view.content = new Gtk.Label(
					"Could not start chat. Open Settings to verify your connection and model."
				) {
					margin_top = 24,
					margin_bottom = 24,
					margin_start = 24,
					margin_end = 24,
					wrap = true,
					vexpand = true,
				};
			}
		}

		private async void initialize_client(OLLMchat.Settings.Config2 config)
		{
			if (this.history_manager == null) {
				return;
			}

			// Default model cached during AndroidStartup; full refresh loads
			// /api/show for every model and blocks the UI for minutes.

			if (!this.history_manager.agent_factories.has_key ("chatter")) {
				this.history_manager.agent_factories.set (
					"chatter", new OLLMchat.Chatter.Factory ());
			}

			this.setup_agent_dropdown ();

			this.new_chat_button.sensitive = true;
			this.new_chat_button.visible = true;

			this.history_browser = new OLLMchatGtk.HistoryBrowser(this.history_manager);
			this.split_view.sidebar = this.history_browser;
			this.history_toggle_button.visible = true;

			var sidebar_motion = new Gtk.EventControllerMotion();
			sidebar_motion.leave.connect(() => {
				if (this.split_view.show_sidebar
				    && this.history_leave_ignore_timeout_id == 0) {
					this.history_toggle_button.active = false;
				}
			});
			this.history_browser.add_controller(sidebar_motion);

			this.chat_widget = new OLLMchatGtk.ChatWidget(this.history_manager);

			this.history_browser.session_selected.connect((session) => {
				this.chat_widget.switch_to_session.begin(session);
			});

			var config_dir = GLib.Path.build_filename(this.app.data_dir, "config");
			this.history_manager.permission_provider =
				new OLLMchatGtk.Tools.Permission(
					this.chat_widget,
					config_dir) {
					application = this.app as GLib.Application,
				};

			this.chat_widget.error_occurred.connect((error) => {
				GLib.stderr.printf("Error: %s\n", error);
			});

			this.history_manager.agent_activated.connect((factory) => {
				factory.activate.begin(this, (obj, res) => {
					factory.activate.end(res);
				});
			});
			this.history_manager.agent_deactivated.connect((factory) => {
				factory.deactivate.begin(this, (obj, res) => {
					factory.deactivate.end(res);
				});
			});
			this.history_manager.session_restored.connect((_session) => {
				var factory = this.history_manager.get_active_agent();
				factory.activate.begin(this, (obj, res) => {
					factory.activate.end(res);
				});
			});

			this.split_view.content = this.chat_widget;
			this.startup_status_label = null;

			var active_factory = this.history_manager.get_active_agent ();
			active_factory.activate.begin (this, (obj, res) => {
				active_factory.activate.end (res);
			});

			GLib.message (
				"AndroidMainWindow: initialize_client agents=%u",
				this.history_manager.agent_factories.size);

			yield this.chat_widget.switch_to_session (
				this.history_manager.session);

			GLib.Idle.add (() => {
				if (this.history_manager != null) {
					this.history_manager.agent_status_change ();
				}
				return false;
			});
		}

		private void setup_agent_dropdown()
		{
			if (this.history_manager == null) {
				return;
			}

			var string_list = new Gtk.StringList (null);
			string[] picker_names = {};
			var selected_index = 0u;
			var i = 0u;
			foreach (var entry in this.history_manager.agent_factories.entries) {
				string_list.append (entry.value.title);
				picker_names += entry.key;
				if (entry.key == this.history_manager.session.agent_name) {
					selected_index = i;
				}
				i++;
			}
			this.agent_picker_names = picker_names;

			this.agent_dropdown.model = string_list;

			this.agent_dropdown.notify["selected"].connect (() => {
				if (this.agent_dropdown.selected == Gtk.INVALID_LIST_POSITION) {
					return;
				}
				if (this.agent_dropdown.selected >= this.agent_picker_names.length) {
					return;
				}
				var agent_name = this.agent_picker_names[
					this.agent_dropdown.selected];
				try {
					if (this.history_manager.session.fid == null
					    || this.history_manager.session.fid == "") {
						this.history_manager.session.activate_agent (
							agent_name);
						return;
					}
					this.history_manager.activate_agent (
						this.history_manager.session.fid, agent_name);
				} catch (GLib.Error e) {
					GLib.warning (
						"Failed to activate agent '%s': %s",
						agent_name, e.message);
				}
			});

			this.agent_dropdown.selected = selected_index;

			this.history_manager.session_activated.connect ((session) => {
				var factory = this.history_manager.get_active_agent ();
				factory.activate.begin (this, (obj, res) => {
					factory.activate.end (res);
				});
				var agent_index = 0u;
				for (var j = 0; j < this.agent_picker_names.length; j++) {
					if (this.agent_picker_names[j] == session.agent_name) {
						agent_index = (uint) j;
						break;
					}
				}
				this.agent_dropdown.selected = agent_index;
			});
		}
	}

	[CCode (cname = "ollmapp_configure_android_gio_tls_modules", cheader_filename = "android-gio-tls.h")]
	private extern bool configure_android_gio_tls_modules();

	int main(string[] args)
	{
		configure_android_gio_tls_modules();
		var app = new AndroidApplication();
		return app.run(args);
	}
}
