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
	 * Widget group for a single connection row in the connections page.
	 * 
	 * Responsible for creating and managing all widgets for a connection row.
	 * 
	 * @since 1.0
	 */
	public class ConnectionRow : Object
	{
		/**
		 * The expander row containing all connection fields
		 */
		public Adw.ExpanderRow expander { get; private set; }

		/**
		 * Name entry field
		 */
		public Gtk.Entry nameEntry { get; set; }

		/**
		 * URL entry field
		 */
		public Gtk.Entry urlEntry { get; set; }

		/**
		 * API key entry field
		 */
		public Gtk.PasswordEntry apiKeyEntry { get; set; }

		/**
		 * Default switch
		 */
		public Gtk.Switch defaultSwitch { get; set; }

		/**
		 * Remove button
		 */
		public Gtk.Button removeButton { get; set; }

		/**
		 * Creates a new ConnectionRow with all widgets.
		 * 
		 * @param connection Connection object to initialize widgets from
		 * @param url Connection URL
		 * @param canRemove Whether Remove button should be visible
		 * @param onRemove Callback when Remove button is clicked
		 * @param onVerify Callback when Verify button is clicked
		 */
		public ConnectionRow(
			OLLMchat.Settings.Connection connection,
			string url,
			bool canRemove,
			owned GLib.Callback onRemove,
			owned GLib.Callback onVerify
		)
		{
			this.expander = new Adw.ExpanderRow() {
				title = connection.name,
				subtitle = url
			};

			// Create form fields
			this.nameEntry = new Gtk.Entry() {
				text = connection.name
			};
			this.nameEntry.changed.connect(() => {
				this.nameEntry.add_css_class("oc-settings-unverified");
			});

			this.urlEntry = new Gtk.Entry() {
				text = connection.url
			};
			this.urlEntry.changed.connect(() => {
				this.urlEntry.add_css_class("oc-settings-unverified");
			});

			this.apiKeyEntry = new Gtk.PasswordEntry() {
				text = connection.api_key
			};
			this.apiKeyEntry.changed.connect(() => {
				this.apiKeyEntry.add_css_class("oc-settings-unverified");
			});

			this.defaultSwitch = new Gtk.Switch() {
				active = connection.is_default
			};
			this.defaultSwitch.activate.connect(() => {
				this.defaultSwitch.add_css_class("oc-settings-unverified");
			});

			// Add form fields to expander row
			var nameRow = new Adw.ActionRow() {
				title = "Name"
			};
			nameRow.add_suffix(this.nameEntry);
			this.expander.add_row(nameRow);

			var urlRow = new Adw.ActionRow() {
				title = "URL"
			};
			urlRow.add_suffix(this.urlEntry);
			this.expander.add_row(urlRow);

			var apiKeyRow = new Adw.ActionRow() {
				title = "API Key"
			};
			apiKeyRow.add_suffix(this.apiKeyEntry);
			this.expander.add_row(apiKeyRow);

			var defaultRow = new Adw.ActionRow() {
				title = "Default"
			};
			defaultRow.add_suffix(this.defaultSwitch);
			this.expander.add_row(defaultRow);

			// Create action buttons at bottom
			var buttonBox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				margin_start = 12,
				margin_end = 12,
				margin_top = 6,
				margin_bottom = 6
			};

			// Remove button (red, left)
			this.removeButton = new Gtk.Button.with_label("Remove") {
				css_classes = {"destructive-action"},
				visible = canRemove
			};
			this.removeButton.clicked.connect(() => {
				onRemove();
			});
			buttonBox.append(this.removeButton);

			// Verify button (green/blue, right)
			var verifyButton = new Gtk.Button.with_label("Verify") {
				css_classes = {"suggested-action"}
			};
			verifyButton.clicked.connect(() => {
				onVerify();
			});
			buttonBox.append(verifyButton);

			// Add button box as last row
			var buttonRow = new Adw.ActionRow();
			buttonRow.add_suffix(buttonBox);
			this.expander.add_row(buttonRow);
		}

		/**
		 * Updates the expander row title and subtitle.
		 */
		public void updateTitle(string name, string url)
		{
			this.expander.title = name;
			this.expander.subtitle = url;
		}

		/**
		 * Removes the unverified CSS class from all fields.
		 */
		public void clearUnverified()
		{
			this.nameEntry.remove_css_class("oc-settings-unverified");
			this.urlEntry.remove_css_class("oc-settings-unverified");
			this.apiKeyEntry.remove_css_class("oc-settings-unverified");
			this.defaultSwitch.remove_css_class("oc-settings-unverified");
		}

	}
}

