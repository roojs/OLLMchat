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

namespace OLLMapp.SettingsDialog
{
	/**
	 * Dialog for adding connections.
	 * 
	 * Can be used for both initial bootstrap setup and adding new connections.
	 * Uses AdwPreferencesDialog with a single header for setup.
	 * 
	 * @since 1.0
	 */
	public class ConnectionAdd : Adw.PreferencesDialog
	{
		private Gtk.Entry host_entry;
		private Gtk.Entry api_key_entry;
		private Gtk.Button next_button;
		private Adw.ActionRow host_row;
		private Adw.ActionRow api_key_row;
		private Gtk.Spinner spinner;
		private Gtk.Box button_box;
		private Adw.PreferencesGroup group;

		/**
		 * The verified connection object (set after successful verification).
		 * 
		 * This will be null if verification failed or dialog was cancelled.
		 */
		public OLLMchat.Settings.Connection? verified_connection { get; private set; }

		/**
		 * Emitted when an error occurs during connection test.
		 * 
		 * @param error_message The error message to display
		 */
		public signal void error_occurred(string error_message);
		
		/**
		 * Emitted when the dialog is closed.
		 * 
		 * This signal is emitted when the dialog is closed, allowing the caller
		 * to check verified_connection and handle cleanup.
		 */
		public signal void dialog_closed();

		/**
		 * Creates a new ConnectionAdd dialog.
		 */
		public ConnectionAdd()
		{
			this.set_content_height(400);
			this.set_content_width(800);

			// Create preferences page
			var page = new Adw.PreferencesPage();
			
			// Create preferences group
			this.group = new Adw.PreferencesGroup();

			// Host entry row
			this.host_entry = new Gtk.Entry() {
				placeholder_text = "http://127.0.0.1:11434/api",
				text = "http://127.0.0.1:11434/api",
				width_request = 250,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.host_row = new Adw.ActionRow() {
				title = "Host",
				subtitle = "URL of the Ollama or OpenAI API server"
			};
			this.host_row.add_suffix(this.host_entry);
			this.group.add(this.host_row);

			// API Key entry row
			this.api_key_entry = new Gtk.Entry() {
				placeholder_text = "(optional)",
				width_request = 250,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.api_key_row = new Adw.ActionRow() {
				title = "API Key",
				subtitle = "(optional) only need for online services or if you serve via nginx proxy"
			};
			this.api_key_row.add_suffix(this.api_key_entry);
			this.group.add(this.api_key_row);

			// Add group to page
			page.add(this.group);

			// Create Add Connection button with spinner
			this.button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
			this.spinner = new Gtk.Spinner() {
				spinning = false,
				visible = false
			};
			var button_label = new Gtk.Label("Add Connection");
			this.button_box.append(this.spinner);
			this.button_box.append(button_label);
			
			this.next_button = new Gtk.Button() {
				child = this.button_box,
				css_classes = {"suggested-action"}
			};

			// Add Add Connection button to page footer
			var footer = new Adw.PreferencesGroup();
			footer.add(this.next_button);
			page.add(footer);

			// Add page to dialog
			this.add(page);

			// Update button state when entries change
			this.host_entry.changed.connect(() => {
				this.update_button_state();
			});
			
			// Connect Add Connection button click handler
			this.next_button.clicked.connect(() => {
				this.test_and_save.begin();
			});
			
			// Connect closed signal to emit dialog_closed signal
			this.closed.connect(() => {
				this.dialog_closed();
			});
		}

		/**
		 * Configures the dialog for bootstrap mode (initial setup).
		 */
		public void show_bootstrap()
		{
			this.verified_connection = null;
			this.title = "Set up initial connect";
			this.group.title = "Set up initial connect";
			this.group.description = "First step is to connect to a ollama or openai server (this is really designed for locally hosted LLMs, however you should be able to use online LLMs if you have an account)";
			this.next_button.sensitive = this.host_entry.text.strip() != "";
		}

		/**
		 * Configures the dialog for adding a new connection.
		 */
		public void show_add()
		{
			this.verified_connection = null;
			this.title = "Add Connection";
			this.group.title = "Add Connection";
			this.group.description = "Add a new server connection. Enter the URL and optional API key for your Ollama or OpenAI server.";
			this.host_entry.text = "";
			this.api_key_entry.text = "";
			this.next_button.sensitive = false;
		}

		private void update_button_state()
		{
			var host = this.host_entry.text.strip();
			this.next_button.sensitive = host != "";
		}

		private async void test_and_save()
		{
			var host = this.host_entry.text.strip();
			var api_key = this.api_key_entry.text.strip();
			
			if (host == "") {
				this.error_occurred("Host is required");
				return;
			}

			// Lock button and show spinner
			this.next_button.sensitive = false;
			this.spinner.spinning = true;
			this.spinner.visible = true;

			try {
				// Create Connection object
				var connection = new OLLMchat.Settings.Connection() {
					name = host, // Default name to URL, user can edit later
					url = host,
					api_key = api_key
				};

				// Create temporary client from Connection for testing
				var test_client = new OLLMchat.Client(connection);

				// Test connection by calling version endpoint
				var version = yield test_client.version();
				GLib.debug("Server version: %s", version);

				// Store verified connection
				this.verified_connection = connection;

				// Close dialog (will emit closed signal which triggers dialog_closed)
				this.force_close();

			} catch (Error e) {
				// Unlock button and hide spinner
				this.next_button.sensitive = true;
				this.spinner.spinning = false;
				this.spinner.visible = false;

				// Show error
				this.error_occurred("Failed to connect: " + e.message);
			}
		}
	}
}

