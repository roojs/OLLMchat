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

		private Gtk.Box action_box;
		private Gtk.Button add_btn;
		private Adw.PreferencesGroup group;
		private Gtk.ListBox list;
		private Gee.HashMap<string, ConnectionRow> rows = new Gee.HashMap<string, ConnectionRow>();
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
			var row = this.rows.get(url);
			var newUrl = row.urlEntry.text.strip();

			if (newUrl == "") {
				return;
			}

			try {
				// Create Connection object with current values
				var newName = row.nameEntry.text.strip();
				var test_connection = new Connection() {
					name = newName != "" ? newName : newUrl,
					url = newUrl,
					api_key = row.apiKeyEntry.text.strip(),
					is_default = row.defaultSwitch.active
				};

				// NOTE: Client doesn't accept Connection yet - this will fail to compile until Client is updated
				// TODO: Update Client to accept Connection directly
				var test_client = new OLLMchat.Client(test_connection);

				// Test connection by calling version endpoint
				GLib.debug("Server version: %s", yield test_client.version());

				// Update connection in config
				// If URL changed, remove old entry and add new one
				if (newUrl != url) {
					this.dialog.config.connections.unset(url);
					this.dialog.config.connections.set(newUrl, test_connection);
					// Update expander row title/subtitle
					row.expander.title = test_connection.name;
					row.expander.subtitle = newUrl;
					// Update tracking map
					this.rows.set(newUrl, row);
					this.rows.unset(url);
				} else {
					this.dialog.config.connections.set(url, test_connection);
					// Update expander row title
					row.expander.title = test_connection.name;
					row.expander.subtitle = newUrl;
				}

				// Remove unverified CSS class from all fields
				row.clearUnverified();

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
			foreach (var entry in this.rows.entries) {
				if (!this.dialog.config.connections.has_key(entry.key)) {
					urls_to_remove.add(entry.key);
				}
			}

			foreach (var url in urls_to_remove) {
				this.list.remove(this.rows.get(url).expander);
				this.rows.unset(url);
			}

			// Add new connections that don't have rows yet
			foreach (var entry in this.dialog.config.connections.entries) {
				if (!this.rows.has_key(entry.key)) {
					this.add_connection_row(entry.key, entry.value, can_remove);
					continue;
				}
				// Update Remove button visibility for existing row
				this.rows.get(entry.key).removeButton.visible = can_remove;
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
			var row = new ConnectionRow(
				connection,
				url,
				can_remove,
				() => { this.remove_connection(url); },
				() => { this.verify_connection.begin(url); }
			);

			this.rows.set(url, row);
			this.list.append(row.expander);
		}


	}
}

