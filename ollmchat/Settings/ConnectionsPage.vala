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

namespace OLLMchat.Settings
{
	/**
	 * Connections tab content for settings dialog.
	 * 
	 * Manages server connections (add, remove, edit connection details).
	 * Uses Adw.PreferencesGroup with Gtk.ListBox for connection list.
	 * Editing is inline - no separate edit/update methods needed.
	 * 
	 * @since 1.0
	 */
	public class ConnectionsPage : SettingsPage
	{
		/**
		 * Reference to parent SettingsDialog (which has the config object)
		 */
		public SettingsDialog dialog { get; construct; }

		// Widget indices in widgets HashMap:
		// [0] = Adw.ExpanderRow
		// [1] = Gtk.Entry (name)
		// [2] = Gtk.Entry (url)
		// [3] = Gtk.PasswordEntry (api_key)
		// [4] = Gtk.Switch (default)
		// [5] = Gtk.Button (remove)

		private Gtk.Box action_box;
		private Gtk.Button add_btn;
		private Adw.PreferencesGroup group;
		private Gtk.ListBox list;
		private Gee.HashMap<string, Gee.ArrayList<Gtk.Widget>> widgets = new Gee.HashMap<string, Gee.ArrayList<Gtk.Widget>>();
		private ConnectionAdd add_dialog;

		/**
		 * Creates a new ConnectionsPage.
		 * 
		 * @param dialog Parent SettingsDialog (which has the config object)
		 */
		public ConnectionsPage(SettingsDialog dialog)
		{
			Object(
				dialog: dialog,
				page_name: "connections",
				page_title: "Connections",
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0
			);
			
			// Add proper margins to the page
			this.margin_start = 12;
			this.margin_end = 12;
			this.margin_top = 12;
			this.margin_bottom = 12;

			// Create horizontal action bar
			this.action_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				margin_start = 12,
				margin_end = 12,
				margin_top = 12,
				margin_bottom = 12
			};

			// Create Add Connection button
			this.add_btn = new Gtk.Button.with_label("Add Connection") {
				css_classes = {"suggested-action"}
			};
			this.add_btn.clicked.connect(this.add_connection);
			this.action_box.append(this.add_btn);

			// Create preferences group
			this.group = new Adw.PreferencesGroup() {
				title = this.page_title
			};

			// Create list box for connections
			this.list = new Gtk.ListBox();
			this.group.add(this.list);

			// Add action bar and preferences group to page
			var action_group = new Adw.PreferencesGroup();
			action_group.add(this.action_box);
			this.append(action_group);
			this.append(this.group);

			// Create ConnectionAdd dialog
			this.add_dialog = new ConnectionAdd();
			this.add_dialog.dialog_closed.connect(this.on_add_closed);

			// Initial render of connections
			this.render_connections();
		}

		/**
		 * Opens ConnectionAdd dialog for adding new connection.
		 */
		private void add_connection()
		{
			this.add_dialog.show_add();
			this.add_dialog.present(this.dialog);
		}

		/**
		 * Called when ConnectionAdd dialog closes.
		 * Checks if connection was verified and adds it to config if successful.
		 */
		private void on_add_closed()
		{
			if (this.add_dialog.verified_connection != null) {
				this.dialog.config.connections.set(
					this.add_dialog.verified_connection.url,
					this.add_dialog.verified_connection
				);
				this.render_connections();
				this.dialog.config.save();
			}
		}

		/**
		 * Tests connection and saves to config on success.
		 * 
		 * @param url Connection URL to verify
		 */
		private async void verify_connection(string url)
		{
			var new_url = (this.widgets.get(url).get(2) as Gtk.Entry).text.strip();
			var new_name = (this.widgets.get(url).get(1) as Gtk.Entry).text.strip();
			var new_api_key = (this.widgets.get(url).get(3) as Gtk.PasswordEntry).text.strip();
			var new_default = (this.widgets.get(url).get(4) as Gtk.Switch).active;

			if (new_url == "") {
				return;
			}

			try {
				// Create Connection object with current values
				var test_connection = new Connection() {
					name = new_name != "" ? new_name : new_url,
					url = new_url,
					api_key = new_api_key,
					is_default = new_default
				};

				// NOTE: Client doesn't accept Connection yet - this will fail to compile until Client is updated
				// TODO: Update Client to accept Connection directly
				var test_client = new OLLMchat.Client(test_connection);

				// Test connection by calling version endpoint
				GLib.debug("Server version: %s", yield test_client.version());

				// Update connection in config
				// If URL changed, remove old entry and add new one
				var widgets = this.widgets.get(url);
				var expander = widgets.get(0) as Adw.ExpanderRow;
				if (new_url != url) {
					this.dialog.config.connections.unset(url);
					this.dialog.config.connections.set(new_url, test_connection);
					// Update expander row title/subtitle
					expander.title = test_connection.name;
					expander.subtitle = new_url;
					// Update tracking map
					this.widgets.set(new_url, widgets);
					this.widgets.unset(url);
				} else {
					this.dialog.config.connections.set(url, test_connection);
					// Update expander row title
					expander.title = test_connection.name;
				}

				// Remove unverified CSS class from all fields
				foreach (int i in new int[] {1, 2, 3, 4}) {
					this.widgets.get(url).get(i).remove_css_class("oc-settings-unverified");
				}

				// Save config
				this.dialog.config.save();

			} catch (Error e) {
				// Show error message
				GLib.warning("Failed to verify connection: " + e.message);
			}
		}

		/**
		 * Removes connection from config.connections map and updates visibility of Remove buttons.
		 * Hides Remove button if only one connection left.
		 * 
		 * @param url Connection URL to remove
		 */
		private void remove_connection(string url)
		{
			if (this.dialog.config.connections.size <= 1) {
				return; // Cannot remove last connection
			}

			this.dialog.config.connections.unset(url);
			this.render_connections();
			this.dialog.config.save();
		}

		/**
		 * Creates UI entries from config.connections map.
		 * 
		 * Does initial render when page is created.
		 * Can be called after connections are added/removed to update the UI incrementally.
		 * Updates Remove button visibility based on number of connections.
		 */
		private void render_connections()
		{
			bool can_remove = this.dialog.config.connections.size > 1;

			// Find and remove connections that no longer exist in config
			var urls_to_remove = new Gee.ArrayList<string>();
			foreach (var entry in this.widgets.entries) {
				if (!this.dialog.config.connections.has_key(entry.key)) {
					urls_to_remove.add(entry.key);
				}
			}

			foreach (var url in urls_to_remove) {
				this.list.remove((this.widgets.get(url).get(0) as Adw.ExpanderRow));
				this.widgets.unset(url);
			}

			// Add new connections that don't have rows yet
			foreach (var entry in this.dialog.config.connections.entries) {
				if (!this.widgets.has_key(entry.key)) {
					this.add_connection_row(entry.key, entry.value, can_remove);
					continue;
				}
				// Update Remove button visibility for existing row
				this.update_remove_button_visibility(entry.key, can_remove);
			}
		}

		/**
		 * Adds a single connection row to the UI.
		 * 
		 * @param url Connection URL (key in config.connections map)
		 * @param connection Connection object
		 * @param can_remove Whether Remove button should be visible
		 */
		private void add_connection_row(string url, OLLMchat.Settings.Connection connection, bool can_remove)
		{
			var expander_row = new Adw.ExpanderRow() {
				title = connection.name,
				subtitle = url
			};

			// Create form fields
			var name_entry = new Gtk.Entry() {
				text = connection.name
			};
			name_entry.changed.connect(() => {
				name_entry.add_css_class("oc-settings-unverified");
			});

			var url_entry = new Gtk.Entry() {
				text = connection.url
			};
			url_entry.changed.connect(() => {
				url_entry.add_css_class("oc-settings-unverified");
			});

			var api_key_entry = new Gtk.PasswordEntry() {
				text = connection.api_key
			};
			api_key_entry.changed.connect(() => {
				api_key_entry.add_css_class("oc-settings-unverified");
			});

			var default_switch = new Gtk.Switch() {
				active = connection.is_default
			};
			default_switch.activate.connect(() => {
				default_switch.add_css_class("oc-settings-unverified");
			});

			// Add form fields to expander row
			var name_row = new Adw.ActionRow() {
				title = "Name"
			};
			name_row.add_suffix(name_entry);
			expander_row.add_row(name_row);

			var url_row = new Adw.ActionRow() {
				title = "URL"
			};
			url_row.add_suffix(url_entry);
			expander_row.add_row(url_row);

			var api_key_row = new Adw.ActionRow() {
				title = "API Key"
			};
			api_key_row.add_suffix(api_key_entry);
			expander_row.add_row(api_key_row);

			var default_row = new Adw.ActionRow() {
				title = "Default"
			};
			default_row.add_suffix(default_switch);
			expander_row.add_row(default_row);

			// Create action buttons at bottom
			var button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				margin_start = 12,
				margin_end = 12,
				margin_top = 6,
				margin_bottom = 6
			};

			// Remove button (red, left)
			var remove_button = new Gtk.Button.with_label("Remove") {
				css_classes = {"destructive-action"},
				visible = can_remove
			};
			remove_button.clicked.connect(() => {
				this.remove_connection(url);
			});
			button_box.append(remove_button);

			// Verify button (green/blue, right)
			var verify_button = new Gtk.Button.with_label("Verify") {
				css_classes = {"suggested-action"}
			};
			verify_button.clicked.connect(() => {
				this.verify_connection.begin(url);
			});
			button_box.append(verify_button);

			// Add button box as last row
			var button_row = new Adw.ActionRow();
			button_row.add_suffix(button_box);
			expander_row.add_row(button_row);

			// Store all widgets in ArrayList: [0]=expander_row, [1]=name_entry, [2]=url_entry, [3]=api_key_entry, [4]=default_switch, [5]=remove_button
			var widgets = new Gee.ArrayList<Gtk.Widget>();
			widgets.add(expander_row);
			widgets.add(name_entry);
			widgets.add(url_entry);
			widgets.add(api_key_entry);
			widgets.add(default_switch);
			widgets.add(remove_button);
			this.widgets.set(url, widgets);

			// Add expander row to connection list
			this.list.append(expander_row);
		}

		/**
		 * Updates Remove button visibility for a specific connection row.
		 * 
		 * @param url Connection URL
		 * @param can_remove Whether Remove button should be visible
		 */
		private void update_remove_button_visibility(string url, bool can_remove)
		{
			(this.widgets.get(url).get(5) as Gtk.Button).visible = can_remove;
		}

	}
}

