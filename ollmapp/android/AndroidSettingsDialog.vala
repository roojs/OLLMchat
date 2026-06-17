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
	 * Android settings dialog — connections and models only.
	 *
	 * @since 1.0
	 */
	public class AndroidSettingsDialog : Adw.Dialog
	{
		public AndroidApplication app { get; construct; }

		public Gtk.Window parent;

		private Adw.ViewStack view_stack;
		private SettingsDialog.ConnectionAdd add_dialog;
		private Adw.PreferencesGroup group;
		private Gtk.Box boxed_list;
		private Gtk.Button add_btn;
		private Gee.HashMap<string, SettingsDialog.ConnectionRow> rows =
			new Gee.HashMap<string, SettingsDialog.ConnectionRow>();
		private bool updating_defaults = false;
		private Gtk.DropDown connection_dropdown;
		private Gtk.Entry model_entry;
		private Gee.ArrayList<string> connection_urls = new Gee.ArrayList<string>();

		public AndroidSettingsDialog(
			AndroidApplication app,
			Gtk.Window parent
		) {
			Object(app: app);
			this.parent = parent;
			this.title = "Settings";
			this.set_content_width(400);
			this.set_content_height(576);

			var main_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			this.view_stack = new Adw.ViewStack();
			var header_bar = new Adw.HeaderBar();
			header_bar.set_title_widget(new Adw.ViewSwitcher() {
				stack = this.view_stack,
				policy = Adw.ViewSwitcherPolicy.NARROW
			});
			main_box.append(header_bar);

			var connections_page = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			var action_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				margin_start = 12,
				margin_end = 12,
				margin_top = 12,
				margin_bottom = 6
			};
			this.add_btn = new Gtk.Button.with_label("Add Connection") {
				css_classes = {"suggested-action"}
			};
			this.add_btn.clicked.connect(this.add_connection);
			action_bar.append(this.add_btn);
			connections_page.append(action_bar);

			this.group = new Adw.PreferencesGroup();
			this.boxed_list = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			this.group.add(this.boxed_list);
			var connections_scrolled = new Gtk.ScrolledWindow() {
				vexpand = true,
				hexpand = true,
				child = this.group
			};
			connections_scrolled.set_policy(
				Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC
			);
			connections_page.append(connections_scrolled);
			this.view_stack.add_titled(connections_page, "connections", "Connections");

			var models_page = new Adw.PreferencesPage();
			var models_group = new Adw.PreferencesGroup() {
				title = "Default chat model"
			};
			this.connection_dropdown = new Gtk.DropDown(null, null);
			var connection_row = new Adw.ActionRow() {
				title = "Connection",
				subtitle = "Server for the default chat model"
			};
			connection_row.add_suffix(this.connection_dropdown);
			models_group.add(connection_row);
			this.model_entry = new Gtk.Entry() {
				placeholder_text = "Model name"
			};
			var model_row = new Adw.ActionRow() {
				title = "Model",
				subtitle = "Name of the default chat model"
			};
			model_row.add_suffix(this.model_entry);
			models_group.add(model_row);
			models_page.add(models_group);
			var models_scrolled = new Gtk.ScrolledWindow() {
				vexpand = true,
				hexpand = true,
				child = models_page
			};
			this.view_stack.add_titled(models_scrolled, "models", "Models");

			this.view_stack.vexpand = true;
			main_box.append(this.view_stack);
			this.set_child(main_box);

			this.add_dialog = new SettingsDialog.ConnectionAdd();
			this.add_dialog.dialog_closed.connect(this.on_add_closed);

			this.closed.connect(this.on_closed);
		}

		/**
		 * Shows the settings dialog and initializes pages.
		 *
		 * @param page_name Optional page name to switch to (e.g., "connections", "models")
		 */
		public async void show_dialog(string? page_name = null)
		{
			var checking_dialog = new SettingsDialog.CheckingConnectionDialog(
				this.parent
			);
			checking_dialog.show_dialog();
			yield this.check_all_connections();
			checking_dialog.hide_dialog();

			this.render_connections();
			this.render_models();

			if (page_name != null) {
				this.view_stack.set_visible_child_name(page_name);
			}

			this.present(this.parent);
		}

		private void add_connection()
		{
			this.add_dialog.show_add();
			this.add_dialog.present(this.parent);
		}

		private void on_add_closed()
		{
			if (this.add_dialog.verified_connection == null) {
				return;
			}
			this.app.config.connections.set(
				this.add_dialog.verified_connection.url,
				this.add_dialog.verified_connection
			);
			this.render_connections();
			this.render_models();
			this.app.persist_config ();
		}

		private void render_connections()
		{
			var can_remove = this.app.config.connections.size > 1;

			var urls_to_remove = new Gee.ArrayList<string>();
			foreach (var entry in this.rows.entries) {
				if (!this.app.config.connections.has_key(entry.key)) {
					urls_to_remove.add(entry.key);
				}
			}
			foreach (var url in urls_to_remove) {
				this.rows.get(url).expander.unparent();
				this.rows.unset(url);
			}

			foreach (var entry in this.app.config.connections.entries) {
				if (!this.rows.has_key(entry.key)) {
					this.add_connection_row(entry.key, entry.value, can_remove);
					continue;
				}
				this.rows.get(entry.key).removeButton.visible = can_remove;
			}
		}

		private void add_connection_row(
			string url,
			OLLMchat.Settings.Connection connection,
			bool can_remove
		) {
			var row = new SettingsDialog.ConnectionRow(connection, url, can_remove);
			row.remove_requested.connect(() => {
				this.remove_connection(row.url);
			});
			row.verify_requested.connect(() => {
				this.verify_connection.begin(row.url);
			});
			row.defaultSwitch.notify["active"].connect(() => {
				this.on_default_changed(row.url, row.defaultSwitch.active);
			});
			this.rows.set(url, row);
			this.boxed_list.append(row.expander);
		}

		private async void verify_connection(string url)
		{
			var row = this.rows.get(url);
			var new_url = row.urlEntry.text.strip();
			if (new_url == "") {
				return;
			}

			var new_name = row.nameEntry.text.strip();
			var test_connection = new OLLMchat.Settings.Connection() {
				name = new_name != "" ? new_name : new_url,
				url = new_url
			};
			AndroidConnectionConfigTls.apply_to_connection (test_connection);
			row.apply_config(test_connection);

			try {
				var original_timeout = test_connection.timeout;
				test_connection.timeout = 5;
				try {
					var models_call = new OLLMchat.Call.Models(test_connection);
					yield models_call.exec_models();
				} finally {
					test_connection.timeout = original_timeout;
				}
			} catch (GLib.Error e) {
				GLib.warning("Failed to verify connection: " + e.message);
				return;
			}

			if (new_url != url) {
				this.app.config.connections.unset(url);
				this.app.config.connections.set(new_url, test_connection);
				this.rows.set(new_url, row);
				this.rows.unset(url);
			} else {
				this.app.config.connections.set(url, test_connection);
			}

			row.expander.title = test_connection.name;
			row.expander.subtitle = new_url;
			row.clearUnverified();
			this.app.persist_config ();
			this.render_models();
		}

		private void remove_connection(string url)
		{
			if (this.app.config.connections.size <= 1) {
				return;
			}
			this.app.config.connections.unset(url);
			this.render_connections();
			this.render_models();
			this.app.persist_config ();
		}

		private void on_default_changed(string url, bool is_default)
		{
			if (this.updating_defaults) {
				return;
			}

			var row = this.rows.get(url);
			var connection = this.app.config.connections.get(url);
			row.apply_config(connection);

			if (!is_default && this.app.config.connections.size == 1) {
				this.updating_defaults = true;
				connection.is_default = true;
				row.defaultSwitch.active = true;
				this.updating_defaults = false;
				return;
			}

			this.updating_defaults = true;
			var found_first = false;
			foreach (var entry in this.app.config.connections.entries) {
				if (entry.key == url) {
					continue;
				}
				if (is_default) {
					entry.value.is_default = false;
					if (this.rows.has_key(entry.key)) {
						this.rows.get(entry.key).defaultSwitch.active = false;
					}
					continue;
				}
				if (found_first) {
					continue;
				}
				entry.value.is_default = true;
				if (this.rows.has_key(entry.key)) {
					this.rows.get(entry.key).defaultSwitch.active = true;
				}
				found_first = true;
			}
			this.updating_defaults = false;
		}

		private void render_models()
		{
			this.connection_urls.clear();
			foreach (var entry in this.app.config.connections.entries) {
				this.connection_urls.add(entry.key);
			}

			var strings = new Gtk.StringList(null);
			foreach (var url in this.connection_urls) {
				strings.append(url);
			}
			this.connection_dropdown.model = strings;

			var default_model = this.app.config.usage.get("default_model")
				as OLLMchat.Settings.ModelUsage;
			if (default_model == null) {
				this.model_entry.text = "";
				return;
			}

			this.model_entry.text = default_model.model;
			var index = this.connection_urls.index_of(default_model.connection);
			if (index >= 0) {
				this.connection_dropdown.selected = (uint) index;
			}
		}

		public void save_all_options()
		{
			var default_model = this.app.config.usage.get("default_model")
				as OLLMchat.Settings.ModelUsage;
			if (default_model == null) {
				default_model = new OLLMchat.Settings.ModelUsage() {
					options = new OLLMchat.Call.Options()
				};
				this.app.config.usage.set("default_model", default_model);
			}

			var selected = (int) this.connection_dropdown.selected;
			if (selected >= 0 && selected < this.connection_urls.size) {
				default_model.connection = this.connection_urls.get(selected);
			}
			default_model.model = this.model_entry.text.strip();

			var title_model = this.app.config.usage.get("title_model")
				as OLLMchat.Settings.ModelUsage;
			if (title_model == null) {
				title_model = new OLLMchat.Settings.ModelUsage() {
					options = new OLLMchat.Call.Options()
				};
				this.app.config.usage.set("title_model", title_model);
			}
			if (title_model.connection == "") {
				title_model.connection = default_model.connection;
			}
		}

		public void apply_config()
		{
			foreach (var entry in this.rows.entries) {
				entry.value.apply_config(
					this.app.config.connections.get(entry.key)
				);
			}
		}

		private async void check_all_connections()
		{
			foreach (var entry in this.app.config.connections.entries) {
				var connection = entry.value;
				try {
					var original_timeout = connection.timeout;
					connection.timeout = 5;
					try {
						var models_call = new OLLMchat.Call.Models(connection);
						yield models_call.exec_models();
						connection.is_working = true;
					} finally {
						connection.timeout = original_timeout;
					}
				} catch (GLib.Error e) {
					connection.is_working = false;
					GLib.debug(
						"Connection %s is not working: %s",
						connection.url, e.message
					);
				}
			}
		}

		private void on_closed()
		{
			this.save_all_options();
			this.apply_config();
			this.check_all_connections.begin();
			this.app.persist_config ();
			this.app.config.changed();
		}
	}
}
