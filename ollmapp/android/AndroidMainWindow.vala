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
		public OLLMchat.ApplicationInterface app { get; construct; }
		public AndroidSettingsDialog settings_dialog { get; private set; }
		public OLLMchat.History.Manager? history_manager { get; set; default = null; }

		public OLLMchatGtk.ChatWidget? chat_widget { get; private set; }

		private Adw.OverlaySplitView split_view;
		private Adw.HeaderBar header_bar;
		private Gtk.ToggleButton history_toggle_button;
		private Gtk.Button new_chat_button;
		private Gtk.DropDown agent_dropdown;
		private OLLMchatGtk.HistoryBrowser? history_browser = null;
		private SettingsDialog.ConnectionAdd? bootstrap_dialog = null;
		private uint history_leave_ignore_timeout_id = 0;

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

			this.agent_dropdown = new Gtk.DropDown(null,
				new Gtk.PropertyExpression(typeof(OLLMchat.Agent.Factory),
				                           null, "title")) {
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
			if (!this.app.config.loaded) {
				yield this.show_bootstrap_dialog("");
				return;
			}

			var startup = new AndroidStartup(this);
			startup.reinitialize.connect(() => {
				this.load_config_and_initialize.begin();
			});

			if (yield startup.run(this.app.config)) {
				yield this.initialize_client(this.app.config);
			}
		}

		private async void show_bootstrap_dialog(string error_message)
		{
			if (this.bootstrap_dialog == null) {
				this.bootstrap_dialog = new SettingsDialog.ConnectionAdd();
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

				config.save();
				this.app.config = config;
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

			if (yield startup.run(config)) {
				yield this.initialize_client(config);
			}
		}

		private async void initialize_client(OLLMchat.Settings.Config2 config)
		{
			if (this.history_manager == null) {
				return;
			}

			yield this.history_manager.connection_models.refresh();

			this.setup_agent_dropdown();

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
		}

		private void setup_agent_dropdown()
		{
			if (this.history_manager == null) {
				return;
			}

			var agent_store = new GLib.ListStore(typeof(OLLMchat.Agent.Factory));
			var selected_index = 0u;
			var i = 0u;
			foreach (var factory in this.history_manager.agent_factories.values) {
				agent_store.append(factory);
				if (factory.name == this.history_manager.session.agent_name) {
					selected_index = i;
				}
				i++;
			}

			var list_factory = new Gtk.SignalListItemFactory();
			list_factory.setup.connect((item) => {
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
			list_factory.bind.connect((item) => {
				var list_item = item as Gtk.ListItem;
				if (list_item == null || list_item.item == null) {
					return;
				}
				var agent_factory = list_item.item as OLLMchat.Agent.Factory;
				var label = list_item.get_data<Gtk.Label>("label");
				if (label == null) {
					return;
				}
				label.label = agent_factory.title;
				label.tooltip_text = agent_factory.long_title;
			});

			this.agent_dropdown.model = agent_store;
			this.agent_dropdown.set_factory(list_factory);
			this.agent_dropdown.set_list_factory(list_factory);

			this.agent_dropdown.notify["selected"].connect(() => {
				if (this.agent_dropdown.selected == Gtk.INVALID_LIST_POSITION) {
					return;
				}
				var store = this.agent_dropdown.model as GLib.ListStore;
				var factory = store.get_item(this.agent_dropdown.selected)
					as OLLMchat.Agent.Factory;
				this.agent_dropdown.tooltip_text = factory.long_title;
				try {
					if (this.history_manager.session.fid == null
					    || this.history_manager.session.fid == "") {
						this.history_manager.session.activate_agent(factory.name);
						return;
					}
					this.history_manager.activate_agent(
						this.history_manager.session.fid, factory.name);
				} catch (GLib.Error e) {
					GLib.warning(
						"Failed to activate agent '%s': %s",
						factory.name, e.message);
				}
			});

			this.agent_dropdown.selected = selected_index;

			this.history_manager.session_activated.connect((session) => {
				var store = this.agent_dropdown.model as GLib.ListStore;
				if (store == null) {
					return;
				}
				var factory = this.history_manager.get_active_agent();
				factory.activate.begin(this, (obj, res) => {
					factory.activate.end(res);
				});
				var agent_index = 0u;
				for (var j = 0; j < store.get_n_items(); j++) {
					if (((OLLMchat.Agent.Factory)store.get_item(j)).name
					    == session.agent_name) {
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
