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
	 * Widget group for the single outbound file-server connection row.
	 */
	public class FileConnectionRow : Object
	{
		public signal void remove_requested();

		public Adw.ExpanderRow expander { get; private set; }
		public Gtk.Button check_button { get; private set; }
		/** Enabled switch; live {@link reconnect} when the device is approved. */
		public Gtk.Switch enabled_switch { get; private set; }
		/** Status suffix on the Status action row. */
		public Gtk.Label status_label { get; private set; }
		/** Config row this expander edits. */
		public OLLMchat.Settings.FilesdClient client { get; private set; }
		/**
		 * Host window: config, {@link OLLMfiles.ProjectManager}, notifications.
		 */
		public OllmchatWindow win { get; private set; }

		/**
		 * File-connection expander for one
		 * {@link OLLMchat.Settings.FilesdClient}.
		 *
		 * @param client Config row (url, approved, enabled)
		 * @param win Host window for config, ProjectManager, and notifications
		 */
		public FileConnectionRow(OLLMchat.Settings.FilesdClient client, OllmchatWindow win)
		{
			this.client = client;
			this.win = win;
			var subtitle = client.approved ? "Active" : "Requested";
			var title = client.url;
			try {
				title = GLib.Uri.parse(client.url, GLib.UriFlags.NONE).get_host();
			} catch (GLib.UriError e) {
			}
			this.expander = new Adw.ExpanderRow() {
				title = title,
				subtitle = subtitle,
				can_focus = false,
				focus_on_click = false
			};

			var url_row = new Adw.ActionRow() {
				title = "URL"
			};
			url_row.add_suffix(new Gtk.Label(client.url) {
				xalign = 1,
				selectable = true,
				ellipsize = Pango.EllipsizeMode.MIDDLE
			});
			this.expander.add_row(url_row);

			var status_row = new Adw.ActionRow() {
				title = "Status"
			};
			this.status_label = new Gtk.Label(subtitle) {
				xalign = 1
			};
			status_row.add_suffix(this.status_label);
			this.expander.add_row(status_row);

			this.enabled_switch = new Gtk.Switch() {
				active = client.enabled,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			var enabled_row = new Adw.ActionRow() {
				title = "Enabled"
			};
			enabled_row.add_suffix(this.enabled_switch);
			this.enabled_switch.notify["active"].connect(() => {
				if (this.enabled_switch.active == this.client.enabled) {
					return;
				}
				var manager = this.win.project_manager;
				if (manager.active_file != null && manager.active_file.buffer.is_modified) {
					this.expander.subtitle = "Save or discard changes to "
						+ GLib.Path.get_basename(manager.active_file.path) + " first";
					this.enabled_switch.active = !this.enabled_switch.active;
					return;
				}
				this.client.enabled = this.enabled_switch.active;
				this.win.app.config.save();
				if (!this.client.approved) {
					return;
				}
				this.reconnect.begin(this.enabled_switch.active);
			});
			this.expander.add_row(enabled_row);

			this.check_button = new Gtk.Button.with_label("Check") {
				tooltip_text = "Ask the file server whether the desktop has approved this device"
			};
			this.check_button.clicked.connect(() => {
				this.check.begin();
			});
			var check_row = new Adw.ActionRow() {
				title = "Registration"
			};
			check_row.add_suffix(this.check_button);
			this.expander.add_row(check_row);

			var remove_button = new Gtk.Button.with_label("Remove") {
				css_classes = {"destructive-action"}
			};
			remove_button.clicked.connect(() => {
				this.remove_requested();
			});
			var button_row = new Adw.ActionRow();
			button_row.add_suffix(remove_button);
			this.expander.add_row(button_row);
		}

		/**
		 * Ask the remote file server whether this device is approved.
		 *
		 * Sends ''RPC-Daemon.hello'' with the device client certificate.
		 * On success sets {@link OLLMchat.Settings.FilesdClient.approved},
		 * saves config, and if Enabled calls {@link reconnect} to the remote
		 * server.
		 */
		public async void check()
		{
			var tls = new OLLMrpc.Transport.Cert() {
				dir = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(), "ollmchat"),
				cert_pem = "client.pem",
				key_pem = "client-key.pem",
				cn = "ollmchat-device",
				product_ca_resource = true
			};
			tls.ensure();
			var http = new OLLMrpc.Transport.HttpClient(this.client.url) {
				tls_certificate = tls.certificate,
				tls_database = tls.trust
			};
			this.check_button.sensitive = false;
			try {
				yield http.call(new OLLMrpc.Request() {
					method = "RPC-Daemon.hello",
					args = OLLMrpc.args("is", 1, "ollmchat")
				});
			} catch (GLib.Error e) {
				GLib.debug("file connection check: %s", e.message);
				this.check_button.sensitive = true;
				this.expander.subtitle = "Requested: " + e.message;
				return;
			}
			this.client.approved = true;
			this.win.app.config.save();
			this.expander.subtitle = "Active";
			this.status_label.label = "Active";
			this.check_button.sensitive = true;
			if (!this.client.enabled) {
				return;
			}
			yield this.reconnect(true);
		}

		/**
		 * Point the window's {@link OLLMfiles.ProjectManager} at the remote
		 * file server or back at the local Unix daemon, live.
		 *
		 * Builds the client, swaps it in with
		 * {@link OLLMfiles.ProjectManager.replace_rpc}, connects with
		 * ''RPC-Daemon.hello'', reloads projects and restores the window's
		 * active project and file. Progress goes through the window's
		 * ''client.project.load_start'' / ''load_end'' notifications.
		 *
		 * A remote connect failure disables the file connection, reports
		 * it with ''Alert.show'' and falls back to the local daemon (one
		 * recursive call with ''remote = false'').
		 *
		 * @param remote true for HTTPS to this row's URL, false for
		 *   the local Unix socket
		 */
		public async void reconnect(bool remote)
		{
			var data_dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "ollmchat");
			var rpc = new OLLMrpc.Client(data_dir, "ollmfilesd.pid", "ollmfilesd.sock");
			if (remote) {
				var tls = new OLLMrpc.Transport.Cert() {
					dir = data_dir,
					cert_pem = "client.pem",
					key_pem = "client-key.pem",
					cn = "ollmchat-device",
					product_ca_resource = true,
				};
				tls.ensure();
				var http = new OLLMrpc.Transport.HttpClient(this.client.url) {
					bin_body = true,
					tls_certificate = tls.certificate,
					tls_database = tls.trust
				};
				rpc = new OLLMrpc.Client("", "", this.client.url) { http = http };
			}
			this.win.notification(new OLLMrpc.Notification() {
				method = "client.project.load_start"
			});
			this.win.project_manager.replace_rpc(rpc);
			var hello = new OLLMrpc.Request() {
				method = "RPC-Daemon.hello",
				args = OLLMrpc.args("is", 1, "ollmchat")
			};
			var connected = false;
			if (remote) {
				connected = yield rpc.connect(hello);
			} else {
				connected = yield rpc.connect(hello, new OLLMrpc.ClientBoot());
			}
			if (!connected) {
				this.win.notification(new OLLMrpc.Notification() {
					method = "client.project.load_end"
				});
				this.win.notification(new OLLMrpc.Notification() {
					method = "Alert.show",
					message = (remote ? "File server: " : "Filesystem daemon: ")
						+ rpc.connect_error
				});
				if (!remote) {
					return;
				}
				this.client.enabled = false;
				this.win.app.config.save();
				this.enabled_switch.active = false;
				this.expander.subtitle = "Failed: " + rpc.connect_error;
				yield this.reconnect(false);
				return;
			}
			try {
				yield this.win.project_manager.rpc_load_projects_from_db();
				var win_cfg = this.win.window_config();
				yield this.win.project_manager.restore_active_state(win_cfg.project, win_cfg.file);
			} catch (GLib.Error e) {
				GLib.critical("file server reconnect: %s", e.message);
				this.win.notification(new OLLMrpc.Notification() {
					method = "Alert.show",
					message = "Could not load projects: " + e.message
				});
			} finally {
				this.win.notification(new OLLMrpc.Notification() {
					method = "client.project.load_end"
				});
			}
		}
	}
}
