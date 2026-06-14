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

		private Adw.OverlaySplitView split_view;
		private Gtk.ToggleButton history_toggle_button;
		private Gtk.Button new_chat_button;
		private SettingsDialog.ConnectionAdd? bootstrap_dialog = null;

		public AndroidMainWindow(AndroidApplication app)
		{
			Object(application: app, app: app);
			this.title = "OLLMchat";
			this.set_default_size(420, 720);

			this.settings_dialog = new AndroidSettingsDialog(this.app, this);

			var toolbar_view = new Adw.ToolbarView();
			var header_bar = new Adw.HeaderBar();

			this.history_toggle_button = new Gtk.ToggleButton() {
				icon_name = "sidebar-show-symbolic",
				tooltip_text = "History",
				visible = false
			};
			header_bar.pack_start(this.history_toggle_button);

			this.new_chat_button = new Gtk.Button() {
				icon_name = "list-add-symbolic",
				tooltip_text = "New Chat",
				sensitive = false,
				visible = false
			};
			header_bar.pack_start(this.new_chat_button);

			var settings_button = new Gtk.Button() {
				icon_name = "applications-system-symbolic",
				tooltip_text = "Settings"
			};
			settings_button.clicked.connect(() => {
				this.settings_dialog.show_dialog.begin("");
			});
			header_bar.pack_start(settings_button);

			toolbar_view.add_top_bar(header_bar);

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

			// Phase 2: HistoryBrowser sidebar, ChatWidget content, Chatter agent.
			var default_model = config.usage.get("default_model")
				as OLLMchat.Settings.ModelUsage;
			var model_label = default_model != null && default_model.model != ""
				? default_model.model
				: "(none)";
			var ready_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12) {
				margin_top = 24,
				margin_bottom = 24,
				margin_start = 24,
				margin_end = 24,
				valign = Gtk.Align.CENTER
			};
			var title = new Gtk.Label("OLLMchat") {
				wrap = true
			};
			title.add_css_class("title-1");
			ready_box.append(title);
			ready_box.append(new Gtk.Label(
				"Connected. Default model: " + model_label
				+ "\n\nChat UI ships in Phase 2."
			) {
				wrap = true,
				justify = Gtk.Justification.CENTER
			});
			this.split_view.content = ready_box;
		}
	}

	int main(string[] args)
	{
		var app = new AndroidApplication();
		return app.run(args);
	}
}
