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
	 * Phone dialog for the outbound file-server connection.
	 *
	 * Listens for the pairing service, then asks for the six digits.
	 */
	public class FileConnectionAdd : Adw.PreferencesDialog
	{
		/**
		 * ''tcp://host:port'' that answered hello. Null until then.
		 * {@link ConnectionsPage} reads this on {@link dialog_closed}.
		 */
		public string? registered_url { get; private set; }

		/**
		 * Every ''host:port'' from the reply, one per line.
		 */
		public string registered_addresses { get; private set; default = ""; }

		/**
		 * Desktop id from the pairing mDNS TXT record.
		 */
		public string server_id { get; private set; default = ""; }

		private Gtk.Label listen_label;
		private Gtk.Entry pin_entry;
		private Adw.ActionRow pin_row;
		private Gtk.Button request_button;
		private Adw.PreferencesGroup group;
		private string found = "";
		private uint browse_id = 0;

		public signal void error_occurred(string error_message);
		public signal void dialog_closed();

		public FileConnectionAdd()
		{
			this.title = "Add Remote Desktop Environment";
			this.set_content_height(360);
			this.set_content_width(720);

			var page = new Adw.PreferencesPage();
			this.group = new Adw.PreferencesGroup();
			this.pin_entry = new Gtk.Entry() {
				placeholder_text = "Six digits",
				max_length = 6,
				input_purpose = Gtk.InputPurpose.DIGITS
			};
			this.pin_row = new Adw.ActionRow() {
				title = "PIN",
				visible = false
			};
			this.pin_row.add_suffix(this.pin_entry);
			this.group.add(this.pin_row);
			this.listen_label = new Gtk.Label("Listening") {
				wrap = true,
				xalign = 0.5f,
				justify = Gtk.Justification.CENTER,
				margin_top = 18
			};
			this.group.add(this.listen_label);
			page.add(this.group);

			this.request_button = new Gtk.Button() {
				label = "Request",
				css_classes = {"suggested-action"},
				sensitive = false
			};
			var footer = new Adw.PreferencesGroup();
			footer.add(this.request_button);
			page.add(footer);
			this.add(page);

			this.error_occurred.connect((error_message) => {
				this.listen_label.label = error_message;
				this.request_button.sensitive = this.found != "";
				GLib.warning("%s", error_message);
			});
			this.pin_entry.activate.connect(() => {
				this.request.begin();
			});
			this.request_button.clicked.connect(() => {
				this.request.begin();
			});
			this.closed.connect(() => {
				this.can_close = true;
				if (this.browse_id != 0) {
					GLib.Source.remove(this.browse_id);
					this.browse_id = 0;
				}
				var root = this.get_root() as Gtk.Window;
				if (root != null) {
					android_pair_browse_stop(root);
				}
				this.pin_entry.text = "";
				this.request_button.sensitive = false;
				this.dialog_closed();
			});
		}

		/**
		 * Prepares the dialog before {@link Gtk.Window.present}.
		 */
		public void show_add()
		{
			this.registered_url = null;
			this.registered_addresses = "";
			this.server_id = "";
			this.found = "";
			this.pin_entry.text = "";
			this.pin_row.visible = false;
			this.listen_label.label = "Listening";
			this.request_button.sensitive = false;
			if (this.browse_id != 0) {
				GLib.Source.remove(this.browse_id);
				this.browse_id = 0;
			}
			this.browse_id = GLib.Idle.add(() => {
				this.browse_id = 0;
				var window = this.get_root() as Gtk.Window;
				if (window == null) {
					this.listen_label.label = "No desktop found";
					return false;
				}
				android_pair_browse_start(window);
				this.browse_id = GLib.Timeout.add(200, () => {
					var hit = android_pair_browse_poll();
					if (hit == "") {
						return true;
					}
					var root = this.get_root() as Gtk.Window;
					if (root != null) {
						android_pair_browse_stop(root);
					}
					this.browse_id = 0;
					if (hit == "none") {
						this.listen_label.label = "No desktop found";
						return false;
					}
					var nl = hit.index_of("\n");
					if (nl <= 0 || !GLib.Uuid.string_is_valid(hit.substring(0, nl))) {
						this.listen_label.label = "No server id";
						return false;
					}
					this.server_id = hit.substring(0, nl);
					this.found = hit.substring(nl + 1);
					this.listen_label.label = this.found;
					this.pin_row.visible = true;
					this.request_button.sensitive = true;
					this.pin_entry.grab_focus();
					return false;
				});
				return false;
			});
		}

		private async void request()
		{
			this.request_button.sensitive = false;
			if (this.found == "") {
				this.error_occurred("No desktop found");
				return;
			}
			var colon = this.found.last_index_of(":");
			if (colon <= 0) {
				this.error_occurred("Bad address");
				return;
			}
			var port = 0;
			if (!int.try_parse(this.found.substring(colon + 1), out port)) {
				this.error_occurred("Bad address");
				return;
			}
			var host = this.found.substring(0, colon);
			if (!GLib.Uuid.string_is_valid(this.server_id)) {
				this.error_occurred("No server id");
				return;
			}
			var dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "ollmchat", this.server_id);
			var tls_files = new OLLMrpc.Transport.Cert() {
				dir = dir,
				cert_pem = "client.pem",
				key_pem = "client-key.pem",
				cn = "ollmchat-device",
			};
			tls_files.ensure();
			var client = new GLib.SocketClient() {
				timeout = 10
			};
			if (!GLib.FileUtils.test(GLib.Path.build_filename(dir, "ollmrpc-ca.pem"),
					GLib.FileTest.EXISTS)) {
				var pin = this.pin_entry.text.strip();
				if (pin.length != 6) {
					this.error_occurred("Enter the six digits");
					return;
				}
				var csr = "";
				try {
					GLib.FileUtils.get_contents(
						GLib.Path.build_filename(dir, "client.csr"), out csr);
				} catch (GLib.Error e) {
					this.error_occurred(e.message);
					return;
				}
				GLib.SocketConnection conn;
				try {
					conn = client.connect_to_host(host, (uint16) port);
				} catch (GLib.Error e) {
					this.error_occurred(e.message);
					return;
				}
				try {
					conn.socket.blocking = true;
				} catch (GLib.Error e) {
					this.error_occurred(e.message);
					return;
				}
				GLib.TlsClientConnection tls;
				try {
					tls = GLib.TlsClientConnection.@new(conn, null);
				} catch (GLib.Error e) {
					this.error_occurred(e.message);
					return;
				}
				tls.accept_certificate.connect((peer_cert, errors) => {
					return true;
				});
				try {
					tls.handshake();
				} catch (GLib.Error e) {
					this.error_occurred(e.message);
					return;
				}
				OLLMrpc.Bin.Stream bin;
				try {
					bin = new OLLMrpc.Bin.Stream(
						new GLib.DataInputStream(tls.get_input_stream()),
						new GLib.DataOutputStream(tls.get_output_stream())
					);
				} catch (GLib.Error e) {
					this.error_occurred(e.message);
					return;
				}
				try {
					bin.write(new OLLMrpc.Request() {
						method = "ClientCert.request_registration",
						args = OLLMrpc.args("sss", pin, csr, "ollmchat")
					});
				} catch (GLib.Error e) {
					this.error_occurred(e.message);
					return;
				}
				OLLMrpc.Bin.Serializable parsed;
				var reply_wait = GLib.get_monotonic_time() + 10 * 1000000;
				while (true) {
					try {
						parsed = bin.parse();
					} catch (GLib.IOError e) {
						if (e.code != GLib.IOError.WOULD_BLOCK || GLib.get_monotonic_time() >= reply_wait) {
							this.error_occurred(e.message);
							return;
						}
						var reply_poll = GLib.PollFD();
						reply_poll.fd = conn.socket.fd;
						reply_poll.events = GLib.IOCondition.IN;
						GLib.poll(new GLib.PollFD[] { reply_poll }, 200);
						continue;
					} catch (GLib.Error e) {
						this.error_occurred(e.message);
						return;
					}
					if (!(parsed is OLLMrpc.Response)) {
						continue;
					}
					break;
				}
				var response = (OLLMrpc.Response) parsed;
				if (response.error != null) {
					this.error_occurred(response.error.message);
					return;
				}
				var packed = (string[]) response.retval;
				if (packed.length < 2) {
					this.error_occurred("reply needs a client cert and a CA");
					return;
				}
				try {
					GLib.FileUtils.set_contents(
						GLib.Path.build_filename(dir, "client.pem"), packed[0]);
				} catch (GLib.Error e) {
					this.error_occurred(e.message);
					return;
				}
				try {
					GLib.FileUtils.set_contents(
						GLib.Path.build_filename(dir, "ollmrpc-ca.pem"), packed[1]);
				} catch (GLib.Error e) {
					this.error_occurred(e.message);
					return;
				}
				tls_files.ensure();
				this.registered_addresses = string.joinv("\n", packed[2:packed.length]);
			}
			if (this.registered_addresses == "") {
				this.registered_addresses = this.found;
			}
			GLib.SocketConnection again;
			try {
				again = client.connect_to_host(host, (uint16) port);
			} catch (GLib.Error e) {
				this.error_occurred(e.message);
				return;
			}
			try {
				again.socket.blocking = true;
			} catch (GLib.Error e) {
				this.error_occurred(e.message);
				return;
			}
			GLib.TlsClientConnection tls2;
			try {
				tls2 = GLib.TlsClientConnection.@new(again, null);
			} catch (GLib.Error e) {
				this.error_occurred(e.message);
				return;
			}
			tls2.certificate = tls_files.certificate;
			tls2.database = tls_files.trust;
			tls2.accept_certificate.connect((peer_cert, errors) => {
				return peer_cert != null
					&& (errors & ~GLib.TlsCertificateFlags.BAD_IDENTITY) == 0;
			});
			try {
				tls2.handshake();
			} catch (GLib.Error e) {
				this.error_occurred(e.message);
				return;
			}
			OLLMrpc.Bin.Stream bin2;
			try {
				bin2 = new OLLMrpc.Bin.Stream(
					new GLib.DataInputStream(tls2.get_input_stream()),
					new GLib.DataOutputStream(tls2.get_output_stream())
				);
			} catch (GLib.Error e) {
				this.error_occurred(e.message);
				return;
			}
			try {
				bin2.write(new OLLMrpc.Request() {
					method = "RPC-Daemon.hello",
					args = OLLMrpc.args("is", 1, "ollmchat")
				});
			} catch (GLib.Error e) {
				this.error_occurred(e.message);
				return;
			}
			OLLMrpc.Bin.Serializable hello_parsed;
			var hello_wait = GLib.get_monotonic_time() + 10 * 1000000;
			while (true) {
				try {
					hello_parsed = bin2.parse();
				} catch (GLib.IOError e) {
					if (e.code != GLib.IOError.WOULD_BLOCK || GLib.get_monotonic_time() >= hello_wait) {
						this.error_occurred(e.message);
						return;
					}
					var hello_poll = GLib.PollFD();
					hello_poll.fd = again.socket.fd;
					hello_poll.events = GLib.IOCondition.IN;
					GLib.poll(new GLib.PollFD[] { hello_poll }, 200);
					continue;
				} catch (GLib.Error e) {
					this.error_occurred(e.message);
					return;
				}
				if (!(hello_parsed is OLLMrpc.Response)) {
					continue;
				}
				break;
			}
			var hello = (OLLMrpc.Response) hello_parsed;
			if (hello.error != null) {
				this.error_occurred(hello.error.message);
				return;
			}
			this.registered_url = "tcp://" + host + ":" + port.to_string();
			this.close();
		}
	}

	[CCode (cname = "ollmapp_android_pair_browse_start", cheader_filename = "android-pair-browse.h")]
	private extern void android_pair_browse_start(Gtk.Window window);

	[CCode (cname = "ollmapp_android_pair_browse_poll", cheader_filename = "android-pair-browse.h")]
	private extern string android_pair_browse_poll();

	[CCode (cname = "ollmapp_android_pair_browse_stop", cheader_filename = "android-pair-browse.h")]
	private extern void android_pair_browse_stop(Gtk.Window window);
}
