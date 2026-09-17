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
		public OLLMchat.Settings.Config2 config { get; construct; }

		private Gtk.Entry url_entry;
		private Gtk.Button request_button;
		private Gtk.Spinner spinner;
		private Gtk.Box button_box;
		private Adw.PreferencesGroup group;

		public signal void error_occurred(string error_message);
		public signal void dialog_closed();

		public FileConnectionAdd(OLLMchat.Settings.Config2 config)
		{
			Object(config: config);
			this.title = "Add file connection";
			this.set_content_height(360);
			this.set_content_width(720);

			var page = new Adw.PreferencesPage();
			this.group = new Adw.PreferencesGroup() {
				description = "Connect to a remote OLLMchat file server over HTTPS. "
					+ "The desktop must Accept the registration request."
			};

			this.url_entry = new Gtk.Entry() {
				placeholder_text = "https://host:8443",
				width_request = 280,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			var url_row = new Adw.ActionRow() {
				title = "URL",
				subtitle = "HTTPS URL of the remote file server"
			};
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
				this.url_entry.text = "";
				this.request_button.sensitive = false;
				this.spinner.spinning = false;
				this.spinner.visible = false;
				this.dialog_closed();
			});
		}

		private async void request()
		{
			var url = this.url_entry.text.strip();
			if (url == "") {
				this.error_occurred("URL is required");
				return;
			}
			if (!url.has_prefix("https://")) {
				this.error_occurred("URL must start with https://");
				return;
			}

			this.request_button.sensitive = false;
			this.spinner.spinning = true;
			this.spinner.visible = true;

			try {
				var data_dir = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(), "ollmchat");
				var tls = new OLLMrpc.Transport.Cert() {
					dir = data_dir,
					cert_pem = "client.pem",
					key_pem = "client-key.pem",
					cn = "ollmchat-device",
					product_ca_resource = true,
				};
				tls.ensure();
				var http = new OLLMrpc.Transport.HttpClient(url) {
					bin_body = true,
					tls_certificate = tls.certificate,
					tls_database = tls.ensure_trust()
				};
				var os = GLib.Environment.get_os_info("PRETTY_NAME");
				var requester = (os != null && os != "") ? os : "unknown OS";
				yield http.call(new OLLMrpc.Request() {
					method = "RPC-ClientCert.request_registration",
					args = OLLMrpc.args("s", requester)
				});
			} catch (GLib.Error e) {
				this.request_button.sensitive = true;
				this.spinner.spinning = false;
				this.spinner.visible = false;
				this.error_occurred("Request failed: " + e.message);
				return;
			}

			this.config.filesd_client.url = url;
			this.config.filesd_client.approved = false;
			this.config.filesd_client.enabled = true;
			this.config.save();
			this.force_close();
		}
	}
}
