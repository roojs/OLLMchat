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
	 * Android bootstrap connection dialog.
	 *
	 * Copy of {@link OLLMapp.SettingsDialog.ConnectionAdd} bootstrap behaviour
	 * with Android-specific defaults (empty host, masked API key) and
	 * {@link OLLMapp.SettingsDialog.CheckingConnectionDialog} during verify —
	 * same pattern as {@link OLLMapp.SettingsDialog.MainDialog.show_dialog}.
	 *
	 * @since 1.0
	 */
	public class AndroidBootstrapConnectionAdd : Adw.PreferencesDialog
	{
		private Gtk.Entry host_entry;
		private Gtk.Entry api_key_entry;
		private Gtk.Button next_button;
		private Gtk.Spinner spinner;
		private Gtk.Box button_box;
		private Adw.PreferencesGroup group;

		/**
		 * The verified connection object (set after successful verification).
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
		 */
		public signal void dialog_closed();

		/**
		 * Creates a new Android bootstrap connection dialog.
		 */
		public AndroidBootstrapConnectionAdd()
		{
			this.set_content_height(480);
			this.set_content_width(800);

			var page = new Adw.PreferencesPage();
			this.group = new Adw.PreferencesGroup();

			this.host_entry = new Gtk.Entry() {
				placeholder_text = "http://127.0.0.1:11434/api",
				width_request = 250,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			var host_suffix = new Gtk.Box(Gtk.Orientation.VERTICAL, 4) {
				halign = Gtk.Align.END
			};
			host_suffix.append(this.host_entry);
			host_suffix.append(new Gtk.Label(
				"URL of the Ollama or OpenAI API server"
			) {
				wrap = true,
				wrap_mode = Pango.WrapMode.WORD,
				xalign = 1.0f,
				justify = Gtk.Justification.RIGHT,
				css_classes = {"dim-label"},
				max_width_chars = 45
			});
			var host_row = new Adw.ActionRow() {
				title = "Host"
			};
			host_row.add_suffix(host_suffix);
			this.group.add(host_row);

			this.api_key_entry = new Gtk.Entry() {
				placeholder_text = "(optional)",
				width_request = 250,
				vexpand = false,
				valign = Gtk.Align.CENTER,
				visibility = false
			};
			var api_key_suffix = new Gtk.Box(Gtk.Orientation.VERTICAL, 4) {
				halign = Gtk.Align.END
			};
			api_key_suffix.append(this.api_key_entry);
			api_key_suffix.append(new Gtk.Label(
				"(optional) only need for online services or "
				+ "if you serve via nginx proxy"
			) {
				wrap = true,
				wrap_mode = Pango.WrapMode.WORD,
				xalign = 1.0f,
				justify = Gtk.Justification.RIGHT,
				css_classes = {"dim-label"},
				max_width_chars = 45
			});
			var api_key_row = new Adw.ActionRow() {
				title = "API Key"
			};
			api_key_row.add_suffix(api_key_suffix);
			this.group.add(api_key_row);

			page.add(this.group);

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
				css_classes = {"suggested-action"},
				sensitive = false
			};

			var footer = new Adw.PreferencesGroup();
			footer.add(this.next_button);
			page.add(footer);

			this.add(page);

			this.host_entry.changed.connect(() => {
				this.update_button_state();
			});

			this.next_button.clicked.connect(() => {
				this.test_and_save.begin();
			});

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
			this.group.description =
				"First step is to connect to a ollama or openai server "
				+ "(this is really designed for locally hosted LLMs, however "
				+ "you should be able to use online LLMs if you have an account)";
			this.host_entry.text = "";
			this.api_key_entry.text = "";
			this.next_button.sensitive = false;
		}

		private void update_button_state()
		{
			this.next_button.sensitive = this.host_entry.text.strip() != "";
		}

		private async void test_and_save()
		{
			var host = this.host_entry.text.strip();
			var api_key = this.api_key_entry.text.strip();

			if (host == "") {
				this.error_occurred("Host is required");
				return;
			}

			this.next_button.sensitive = false;
			this.spinner.spinning = true;
			this.spinner.visible = true;

			SettingsDialog.CheckingConnectionDialog? checking = null;
			var parent = this.get_root() as Gtk.Window;
			if (parent != null) {
				checking = new SettingsDialog.CheckingConnectionDialog(parent);
				checking.show_dialog();
			}

			try {
				var connection = new OLLMchat.Settings.Connection() {
					name = host,
					url = host,
					api_key = api_key
				};

				AndroidConnectionConfigTls.apply_to_connection(connection);

				var original_timeout = connection.timeout;
				connection.timeout = 5;
				try {
					var models_call = new OLLMchat.Call.Models(connection);
					var models = yield models_call.exec_models();
					GLib.debug(
						"Connection verified, found %d models", models.size
					);
				} finally {
					connection.timeout = original_timeout;
				}

				yield connection.detect_ollama();

				this.verified_connection = connection;
				this.force_close();

			} catch (Error e) {
				this.error_occurred("Failed to connect: " + e.message);
			} finally {
				if (checking != null) {
					checking.hide_dialog();
				}
				this.next_button.sensitive = true;
				this.spinner.spinning = false;
				this.spinner.visible = false;
			}
		}
	}
}
