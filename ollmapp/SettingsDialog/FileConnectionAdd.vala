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
				placeholder_text = "192.168.1.10:8443",
				width_request = 280,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			var url_row = new Adw.ActionRow() {
				title = "URL"
			};
#if ANDROID
			var url_suffix = new Gtk.Box(Gtk.Orientation.VERTICAL, 4) {
				halign = Gtk.Align.END
			};
			url_suffix.append(this.url_entry);
			url_suffix.append(new Gtk.Label("Host:port or HTTPS URL of the remote file server") {
				wrap = true,
				wrap_mode = Pango.WrapMode.WORD,
				xalign = 1.0f,
				justify = Gtk.Justification.RIGHT,
				css_classes = {"dim-label"},
				max_width_chars = 45
			});
			url_row.add_suffix(url_suffix);
#else
			url_row.subtitle = "Host:port or HTTPS URL of the remote file server";
			url_row.add_suffix(this.url_entry);
#endif
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

		private async void request()
		{
			var url = this.url_entry.text.strip();
			if (url == "") {
				this.error_occurred("URL is required");
				return;
			}
			if (url.has_prefix("http://")) {
				url = "https://" + url.substring("http://".length);
			}
			if (!url.has_prefix("https://")) {
				url = "https://" + url;
			}

			this.request_button.sensitive = false;
			this.spinner.spinning = true;
			this.spinner.visible = true;
			this.can_close = false;

			var tls = new OLLMrpc.Transport.Cert() {
				dir = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(), "ollmchat"),
				cert_pem = "client.pem",
				key_pem = "client-key.pem",
				cn = "ollmchat-device",
				product_ca_resource = true,
			};
			tls.ensure();
			var http = new OLLMrpc.Transport.HttpClient(url) {
				tls_certificate = tls.certificate,
				tls_database = tls.trust
			};
			var os = GLib.Environment.get_os_info("PRETTY_NAME");
			var requester = (os != null && os != "") ? os : "unknown OS";
			GLib.debug("file connection request url=%s", url);
			var finished = false;
			var timeout_id = GLib.Timeout.add_seconds(15, () => {
				if (finished) {
					return false;
				}
				finished = true;
				this.request_button.sensitive = true;
				this.spinner.spinning = false;
				this.spinner.visible = false;
				this.can_close = true;
				GLib.debug("file connection request timed out");
				this.error_occurred("Could not connect: timed out");
				return false;
			});
			try {
				yield http.call(new OLLMrpc.Request() {
					method = "RPC-ClientCert.request_registration",
					args = OLLMrpc.args("s", requester)
				});
			} catch (GLib.Error e) {
				if (finished) {
					return;
				}
				finished = true;
				if (timeout_id != 0) {
					GLib.Source.remove(timeout_id);
				}
				this.request_button.sensitive = true;
				this.spinner.spinning = false;
				this.spinner.visible = false;
				this.can_close = true;
				GLib.debug("file connection request failed: %s", e.message);
				this.error_occurred("Could not connect: " + e.message);
				return;
			}
			if (finished) {
				return;
			}
			finished = true;
			if (timeout_id != 0) {
				GLib.Source.remove(timeout_id);
			}
			this.can_close = true;
			GLib.debug("file connection request ok");
			this.config.filesd_client.url = url;
			this.config.filesd_client.approved = false;
			this.config.filesd_client.enabled = true;
			this.config.save();
			this.force_close();
		}
	}
}
