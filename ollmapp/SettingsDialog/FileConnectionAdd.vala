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

namespace OLLMapp.SettingsDialog
{
	/**
	 * Dialog for adding the single outbound file-server connection.
	 */
	public class FileConnectionAdd : Adw.PreferencesDialog
	{
		/**
		 * HTTPS URL after a successful registration request; null otherwise.
		 * {@link ConnectionsPage} reads this on {@link dialog_closed}, same as
		 * {@link ConnectionAdd.verified_connection}.
		 */
		public string? registered_url { get; private set; }

		/**
		 * Every ''host:port'' from the last pairing reply, one per line.
		 */
		public string registered_addresses { get; private set; default = ""; }

		private Gtk.Entry url_entry;
		private Gtk.Button request_button;
		private Gtk.Spinner spinner;
		private Gtk.Box button_box;
		private Adw.PreferencesGroup group;

		public signal void error_occurred(string error_message);
		public signal void dialog_closed();

		public FileConnectionAdd()
		{
			this.title = "Add Remote Desktop Environment";
			this.set_content_height(360);
			this.set_content_width(720);

			var page = new Adw.PreferencesPage();
			this.group = new Adw.PreferencesGroup() {
				description = "Connect to a desktop environment. "
					+ "The desktop must Accept the registration request."
			};

			this.url_entry = new Gtk.Entry() {
				placeholder_text = "192.168.1.10:8443",
				width_request = 280,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			var url_row = new Adw.ActionRow() {
				title = "URL"
			};
			url_row.subtitle = "Host:port of the desktop";
			url_row.add_suffix(this.url_entry);
			this.group.add(url_row);

			page.add(this.group);

			this.button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
			this.spinner = new Gtk.Spinner() {
				spinning = false,
				visible = false
			};
			this.button_box.append(this.spinner);
			this.button_box.append(new Gtk.Label("Request"));
			this.request_button = new Gtk.Button() {
				child = this.button_box,
				css_classes = {"suggested-action"},
				sensitive = false
			};
			var footer = new Adw.PreferencesGroup();
			footer.add(this.request_button);
			page.add(footer);
			this.add(page);

			this.url_entry.changed.connect(() => {
				this.request_button.sensitive = this.url_entry.text.strip() != "";
			});
			this.request_button.clicked.connect(() => {
				this.request.begin();
			});
			this.closed.connect(() => {
				this.can_close = true;
				this.url_entry.text = "";
				this.request_button.sensitive = false;
				this.spinner.spinning = false;
				this.spinner.visible = false;
				this.dialog_closed();
			});
		}

		/**
		 * Prepares the dialog before {@link Gtk.Window.present}, like
		 * {@link ConnectionAdd.show_add}.
		 */
		public void show_add()
		{
			this.registered_url = null;
			this.registered_addresses = "";
			this.url_entry.text = "";
			this.request_button.sensitive = false;
		}

		private async void request()
		{
			var url = this.url_entry.text.strip();
			if (url == "") {
				this.error_occurred("URL is required");
				return;
			}
		}
	}
}
