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

namespace OLLMchat
{
	/**
	 * Bootstrap dialog for initial client setup.
	 * 
	 * Shows a preferences dialog to configure the first client connection.
	 * Uses AdwPreferencesDialog with a single header for setup.
	 * 
	 * @since 1.0
	 */
	public class BootstrapDialog : Adw.PreferencesDialog
	{
		private Gtk.Entry host_entry;
		private Gtk.Entry api_key_entry;
		private Gtk.Button next_button;
		private Adw.ActionRow host_row;
		private Adw.ActionRow api_key_row;
		private Gtk.Spinner spinner;
		private Gtk.Box button_box;
		private string config_path;

		/**
		 * Emitted when configuration is successfully saved.
		 * 
		 * @param config The saved configuration
		 */
		public signal void config_saved(OLLMchat.Config config);

		/**
		 * Emitted when an error occurs during connection test or save.
		 * 
		 * @param error_message The error message to display
		 */
		public signal void error_occurred(string error_message);

		/**
		 * Creates a new BootstrapDialog.
		 * 
		 * @param config_path Path to the configuration file to save
		 */
		public BootstrapDialog(string config_path)
		{
			this.config_path = config_path;
			this.title = "Set up initial connect";
			this.set_content_height(400);
			this.set_content_width(800);

			// Create preferences page
			var page = new Adw.PreferencesPage();
			
			// Create preferences group
			var group = new Adw.PreferencesGroup();
			group.title = "Set up initial connect";
			group.description = "First step is to connect to a ollama or openai server (this is really designed for locally hosted LLMs, however you should be able to use online LLMs if you have an account)";

			// Host entry row
			this.host_entry = new Gtk.Entry() {
				placeholder_text = "http://127.0.0.1:11434/api",
				text = "http://127.0.0.1:11434/api",
				width_request = 250
			};
			this.host_row = new Adw.ActionRow() {
				title = "Host",
				subtitle = "URL of the Ollama or OpenAI API server"
			};
			this.host_row.add_suffix(this.host_entry);
			group.add(this.host_row);

			// API Key entry row
			this.api_key_entry = new Gtk.Entry() {
				placeholder_text = "(optional)",
				width_request = 250
			};
			this.api_key_row = new Adw.ActionRow() {
				title = "API Key",
				subtitle = "(optional) only need for online services or if you serve via nginx proxy"
			};
			this.api_key_row.add_suffix(this.api_key_entry);
			group.add(this.api_key_row);

			// Add group to page
			page.add(group);

			// Create Next button with spinner
			this.button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
			this.spinner = new Gtk.Spinner() {
				spinning = false,
				visible = false
			};
			var button_label = new Gtk.Label("Next");
			this.button_box.append(this.spinner);
			this.button_box.append(button_label);
			
			this.next_button = new Gtk.Button() {
				child = this.button_box,
				css_classes = {"suggested-action"}
			};

			// Add Next button to page footer
			var footer = new Adw.PreferencesGroup();
			footer.add(this.next_button);
			page.add(footer);

			// Add page to dialog
			this.add(page);

			// Update button state when entries change
			this.host_entry.changed.connect(() => {
				this.update_button_state();
			});
			
			// Connect Next button click handler
			this.next_button.clicked.connect(() => {
				this.test_and_save.begin();
			});
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
				// Create temporary config and client to test connection
				var test_config = new Config() {
					url = host,
					api_key = api_key 
				};
				var test_client = new Client(test_config);

				// Test connection by calling version endpoint
				var version = yield test_client.version();
				GLib.debug("BootstrapDialog: Server version: %s", version);

				// Connection successful - save configuration
				var config = new Config();
				config.config_path = this.config_path;
				config.url = host;
				config.api_key = api_key;
				config.save();

				// Emit success signal
				this.config_saved(config);

				// Close dialog
				this.close();

			} catch (Error e) {
				// Unlock button and hide spinner
				this.next_button.sensitive = true;
				this.spinner.spinning = false;
				this.spinner.visible = false;

				// Show error
				this.error_occurred(@"Failed to connect: $(e.message)");
			}
		}
	}
}
