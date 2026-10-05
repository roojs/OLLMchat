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
	 * Widget group for the Desktop server expander.
	 *
	 * No control on the right. Rows are Unix socket, systemd,
	 * then Local network SSL server.
	 * {@link ssl_switch} writes
	 * {@link OLLMchat.Settings.Filesd.ssl_enabled} after a
	 * host and port are saved.
	 * Toggles and Port blur call {@link apply_config}, which writes
	 * {@link filesd} and {@link reboot}s if listen fields changed.
	 * Dialog close still calls {@link apply_config}.
	 * {@link load_config} fills widgets when the settings dialog is
	 * shown and must not reboot.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var row = new FileServerRow(config.filesd, win, overlay);
	 * boxed_list.append(row.expander);
	 * row.load_config();
	 * }}}
	 */
	public class FileServerRow : Object
	{
		/**
		 * The Desktop server expander. Nothing sits on the right.
		 */
		public Adw.ExpanderRow expander { get; private set; }

		/**
		 * systemd user-unit switch bound to
		 * {@link OLLMchat.Settings.Filesd.systemd}.
		 */
		public Gtk.Switch systemd_switch { get; private set; }

		/**
		 * systemd action row under Unix socket. The toggle is
		 * on this row.
		 */
		private Adw.ActionRow systemd_row;

		/**
		 * Unix socket row. Suffix says Running. No toggle.
		 */
		private Adw.ActionRow unix_row;

		/**
		 * ''Running'' on the Unix socket row.
		 */
		private Gtk.Label unix_label;

		/**
		 * Local network SSL server expander.
		 *
		 * Subtitle is Recommended for local networks only.
		 * Host and Port are its rows. The host list leaves out
		 * ''127.0.0.1''.
		 */
		public Adw.ExpanderRow ssl_expander { get; private set; }

		/**
		 * Local network SSL on/off. Hidden until {@link filesd.socket}
		 * has a host and a port in 1024–65535. Writes
		 * {@link OLLMchat.Settings.Filesd.ssl_enabled}.
		 */
		public Gtk.Switch ssl_switch { get; private set; }

		/**
		 * SSL listen IP. {@link OLLMrpc.Transport.TcpListen.ifaces} plus ''All''.
		 * ''All'' stores ''0.0.0.0''.
		 */
		public Gtk.DropDown ssl_host_dropdown { get; private set; }

		/**
		 * SSL host row inside {@link ssl_expander}.
		 */
		public Adw.ActionRow ssl_host_row { get; private set; }

		/**
		 * SSL listen port. Placeholder is 8422.
		 */
		public Gtk.Entry ssl_port_entry { get; private set; }

		/**
		 * SSL port row. Invalid ports set the subtitle to ''Invalid''.
		 */
		public Adw.ActionRow ssl_port_row { get; private set; }

		/**
		 * Config ''filesd'' object this expander edits.
		 */
		public OLLMchat.Settings.Filesd filesd { get; private set; }
		/**
		 * True when the files daemon accepts a connection.
		 *
		 * Set at the end of {@link load_config} from
		 * {@link OLLMrpc.ClientBoot.connectable}.
		 */
		public bool running { get; private set; default = false; }
		/**
		 * Host window: {@link OLLMfiles.ProjectManager} after a local bounce.
		 */
		public OllmchatWindow win { get; private set; }
		/**
		 * Connections-tab overlay for restart toasts.
		 */
		public Adw.ToastOverlay toast_overlay { get; private set; }
		private bool loading = false;

		private bool was_systemd = false;
		private bool rebooting = false;
		private bool reboot_again = false;

		/**
		 * Desktop server expander for one {@link OLLMchat.Settings.Filesd}.
		 *
		 * @param filesd Config listen settings (socket, systemd)
		 * @param win Host window for ProjectManager reconnect
		 * @param toast_overlay Connections-tab overlay for restart toasts
		 */
		public FileServerRow(
			OLLMchat.Settings.Filesd filesd,
			OllmchatWindow win,
			Adw.ToastOverlay toast_overlay)
		{
			this.filesd = filesd;
			this.win = win;
			this.toast_overlay = toast_overlay;
			this.expander = new Adw.ExpanderRow() {
				title = "Desktop server",
				subtitle = "Not running"
			};
			this.unix_label = new Gtk.Label("Running") {
				valign = Gtk.Align.CENTER
			};
			this.unix_row = new Adw.ActionRow() {
				title = "Unix socket"
			};
			this.unix_row.add_suffix(this.unix_label);
			this.expander.add_row(this.unix_row);

			this.systemd_switch = new Gtk.Switch() {
				active = false,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.systemd_row = new Adw.ActionRow() {
				title = "systemd"
			};
			this.systemd_row.add_suffix(this.systemd_switch);
			this.expander.add_row(this.systemd_row);

			this.ssl_switch = new Gtk.Switch() {
				active = false,
				visible = false,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.ssl_expander = new Adw.ExpanderRow() {
				title = "Local network SSL server",
				subtitle = "Recommended for local networks only"
			};
			this.ssl_expander.add_suffix(this.ssl_switch);
			this.ssl_host_dropdown = new Gtk.DropDown(new Gtk.StringList({}), null) {
				selected = Gtk.INVALID_LIST_POSITION,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.ssl_host_row = new Adw.ActionRow() {
				title = "Host"
			};
			this.ssl_host_row.add_suffix(this.ssl_host_dropdown);
			this.ssl_host_row.set_activatable_widget(this.ssl_host_dropdown);
			this.ssl_expander.add_row(this.ssl_host_row);
			this.ssl_port_entry = new Gtk.Entry() {
				width_chars = 5,
				valign = Gtk.Align.CENTER,
				max_length = 5,
				placeholder_text = "8422"
			};
			this.ssl_port_entry.insert_text.connect((new_text, new_text_length, ref position) => {
				if (GLib.Regex.match_simple("^[0-9]*$", new_text)) {
					return;
				}
				GLib.Signal.stop_emission_by_name(this.ssl_port_entry, "insert-text");
			});
			this.ssl_port_row = new Adw.ActionRow() {
				title = "Port"
			};
			this.ssl_port_row.add_suffix(this.ssl_port_entry);
			this.ssl_port_row.set_activatable_widget(this.ssl_port_entry);
			var ssl_port_focus = new Gtk.EventControllerFocus();
			ssl_port_focus.leave.connect(() => {
				if (this.loading) {
					return;
				}
				this.apply_config();
			});
			this.ssl_port_entry.add_controller(ssl_port_focus);
			this.ssl_expander.add_row(this.ssl_port_row);
			this.expander.add_row(this.ssl_expander);

			this.ssl_switch.notify["active"].connect(() => {
				if (this.loading) {
					return;
				}
				this.apply_config();
			});
			this.ssl_host_dropdown.notify["selected"].connect(() => {
				if (this.loading) {
					return;
				}
				this.apply_config();
			});
			this.systemd_switch.notify["active"].connect(() => {
				if (this.loading) {
					return;
				}
				this.apply_config();
			});
		}

		/**
		 * Fill the Desktop server rows from {@link filesd}.
		 *
		 * SSL uses {@link OLLMrpc.Transport.TcpListen.ifaces} and
		 * adds ''All'' first. That list never includes
		 * ''127.0.0.1''. Call when the
		 * settings dialog is shown, not from the constructor.
		 */
		public void load_config()
		{
			this.loading = true;
			var ips = OLLMrpc.Transport.TcpListen.ifaces();
			var n = ips.length;
			var ssl_ips = ips[0:n];
			ssl_ips.resize(n + 1);
			ssl_ips.move(0, 1, n);
			ssl_ips[0] = "All";
			// resize+move drops the strv terminator; the slice puts it back.
			ssl_ips = ssl_ips[0:n + 1];
			var socket_host = "";
			var socket_port = "";
			var socket_colon = this.filesd.socket.last_index_of(":");
			if (socket_colon > 0) {
				socket_host = this.filesd.socket.substring(0, socket_colon);
				socket_port = this.filesd.socket.substring(socket_colon + 1);
			}
			this.systemd_switch.active = this.filesd.systemd;
			if (ssl_ips.length > 0) {
				var ssl_selected = Gtk.INVALID_LIST_POSITION;
				if (socket_host == "0.0.0.0") {
					ssl_selected = 0;
				}
				for (var i = 0; i < ssl_ips.length; i++) {
					if (ssl_ips[i] != socket_host) {
						continue;
					}
					ssl_selected = i;
					break;
				}
				if (socket_host != "" && socket_host != "0.0.0.0"
					&& ssl_selected == Gtk.INVALID_LIST_POSITION) {
					ssl_ips += socket_host;
					ssl_selected = ssl_ips.length - 1;
				}
				this.ssl_host_dropdown.model = new Gtk.StringList(ssl_ips);
				this.ssl_host_dropdown.selected = ssl_selected;
			}
			var socket_n = 0;
			int.try_parse(socket_port, out socket_n);
			this.ssl_port_entry.text = socket_port;
			this.ssl_port_row.subtitle = "";
			this.ssl_port_entry.remove_css_class("error");
			if (socket_port != "" && (socket_n < 1024 || socket_n > 65535)) {
				this.ssl_port_row.subtitle = "Invalid";
				this.ssl_port_entry.add_css_class("error");
			}
			this.ssl_switch.active = this.filesd.ssl_enabled;
			var data_dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "ollmchat");
			var boot = new OLLMrpc.ClientBoot(data_dir, "ollmfilesd.pid", "ollmfilesd.sock");
			var up = boot.connectable();
			this.running = up;
			var via_systemd = false;
			string active_out, active_err;
			int active_status;
			try {
				GLib.Process.spawn_command_line_sync(
					"systemctl --user is-active ollmfilesd.service",
					out active_out, out active_err, out active_status);
				via_systemd = active_out.strip() == "active";
			} catch (GLib.Error e) {
			}
			var ssl_ok = this.filesd.ssl_enabled && socket_host != ""
				&& socket_n >= 1024 && socket_n <= 65535;
			var how = "Not running";
			if (up) {
				how = "Running on socket";
			}
			if (up && via_systemd) {
				how = "Running via systemd";
			}
			if (up && ssl_ok) {
				how = how + " and local network SSL";
			}
			this.expander.subtitle = how;
			var ssl_ready = socket_host != ""
				&& socket_n >= 1024 && socket_n <= 65535;
			this.ssl_switch.visible = ssl_ready;
			this.loading = false;
		}

		/**
		 * Write the Desktop server rows back into {@link filesd}.
		 *
		 * Off keeps the saved socket address. A saved
		 * socket host and port shows {@link ssl_switch}. If listen
		 * fields changed, save config and {@link reboot}.
		 */
		public void apply_config()
		{
			var prev_socket = this.filesd.socket;
			var prev_systemd = this.filesd.systemd;
			var prev_ssl = this.filesd.ssl_enabled;
			this.was_systemd = prev_systemd;
			this.filesd.systemd = this.systemd_switch.active;
			var ssl_host = "";
			var ssl_item = this.ssl_host_dropdown.selected_item as Gtk.StringObject;
			if (ssl_item != null) {
				ssl_host = ssl_item.string;
			}
			if (ssl_host == "All") {
				ssl_host = "0.0.0.0";
			}
			var ssl_n = 0;
			var ssl_port = this.ssl_port_entry.text.strip();
			int.try_parse(ssl_port, out ssl_n);
			this.ssl_port_row.subtitle = "";
			this.ssl_port_entry.remove_css_class("error");
			if (ssl_port != "" && (ssl_n < 1024 || ssl_n > 65535)) {
				this.ssl_port_row.subtitle = "Invalid";
				this.ssl_port_entry.add_css_class("error");
			}
			if (ssl_host != "" && ssl_n >= 1024 && ssl_n <= 65535) {
				this.filesd.socket = ssl_host + ":" + ssl_n.to_string();
			}
			var saved_n = 0;
			var saved_colon = this.filesd.socket.last_index_of(":");
			var saved_host = "";
			if (saved_colon > 0) {
				saved_host = this.filesd.socket.substring(0, saved_colon);
				int.try_parse(this.filesd.socket.substring(saved_colon + 1), out saved_n);
			}
			var ssl_ready = saved_host != ""
				&& saved_n >= 1024 && saved_n <= 65535;
			this.ssl_switch.visible = ssl_ready;
			if (this.ssl_switch.visible) {
				this.filesd.ssl_enabled = this.ssl_switch.active;
			}
			if (this.filesd.ssl_enabled != prev_ssl
				|| this.filesd.socket != prev_socket
				|| this.filesd.systemd != prev_systemd) {
				this.win.app.config.save();
				GLib.debug("file server apply systemd=%s was=%s socket=%s",
					this.filesd.systemd ? "on" : "off",
					this.was_systemd ? "on" : "off",
					this.filesd.socket);
				if (this.rebooting) {
					this.reboot_again = true;
					return;
				}
				this.reboot.begin();
			}
		}

		/**
		 * Stop the local Unix ollmfilesd and start it again.
		 *
		 * {@link OLLMrpc.ClientBoot.kill} then
		 * {@link OLLMrpc.ClientBoot.ensure_daemon}. Spawn or stay-up
		 * failure toasts ''File server did not stay up'' on
		 * Connections. Stay-up success toasts the expander subtitle
		 * (socket only vs socket and local network SSL). If this
		 * window is still on Unix, reconnect
		 * {@link OLLMfiles.ProjectManager} like
		 * {@link FileConnectionRow.reconnect} with ''remote = false''.
		 * If the window is on a remote file connection, only bounce
		 * the local daemon.
		 */
		public async void reboot()
		{
			this.rebooting = true;
			this.reboot_again = false;
			var want_systemd = this.filesd.systemd;
			var from_systemd = this.was_systemd;
			GLib.debug("file server reboot systemd=%s from=%s",
				want_systemd ? "on" : "off", from_systemd ? "on" : "off");
			var data_dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "ollmchat");
			var boot = new OLLMrpc.ClientBoot(data_dir, "ollmfilesd.pid", "ollmfilesd.sock");
			var toast = new Adw.Toast("Starting on startup…") { timeout = 2 };
			if (want_systemd) {
				toast.title = "Starting via systemd…";
			}
			this.toast_overlay.add_toast(toast);
			if (want_systemd && from_systemd) {
				string sout, serr;
				int status;
				try {
					GLib.Process.spawn_command_line_sync(
						"systemctl --user restart ollmfilesd.service",
						out sout, out serr, out status);
				} catch (GLib.Error e) {
					GLib.warning("systemd restart failed: %s", e.message);
				}
			}
			if (want_systemd && !from_systemd) {
				yield boot.kill();
				this.filesd.install();
			}
			if (!want_systemd) {
				this.filesd.install();
				yield boot.kill();
				try {
					yield boot.ensure_daemon();
				} catch (GLib.Error e) {
					GLib.critical("file server restart: %s", e.message);
					this.toast_overlay.add_toast(
						new Adw.Toast("File server did not stay up") { timeout = 2 });
					this.expander.subtitle = "Not running";
					this.rebooting = false;
					if (this.reboot_again) {
						this.reboot.begin();
					}
					return;
				}
			}
			if (!boot.connectable()) {
				GLib.Timeout.add_seconds(2, () => {
					this.reboot.callback();
					return false;
				});
				yield;
			}
			if (!boot.connectable()) {
				this.toast_overlay.add_toast(
					new Adw.Toast("File server did not stay up") { timeout = 2 });
				this.expander.subtitle = "Not running";
				this.rebooting = false;
				if (this.reboot_again) {
					this.reboot.begin();
				}
				return;
			}
			var via_systemd = false;
			string active_out, active_err;
			int active_status;
			try {
				GLib.Process.spawn_command_line_sync(
					"systemctl --user is-active ollmfilesd.service",
					out active_out, out active_err, out active_status);
				via_systemd = active_out.strip() == "active";
			} catch (GLib.Error e) {
			}
			var ssl_ok = false;
			var socket_colon = this.filesd.socket.last_index_of(":");
			if (this.filesd.ssl_enabled && socket_colon > 0) {
				var socket_n = 0;
				if (int.try_parse(this.filesd.socket.substring(socket_colon + 1), out socket_n)
					&& socket_n >= 1024 && socket_n <= 65535) {
					ssl_ok = true;
				}
			}
			var how = "Running on socket";
			if (via_systemd) {
				how = "Running via systemd";
			}
			if (ssl_ok) {
				how = how + " and local network SSL";
			}
			this.expander.subtitle = how;
			this.toast_overlay.add_toast(new Adw.Toast(this.expander.subtitle) { timeout = 2 });
			if (this.win.app.config.filesd_client.url != "") {
				this.rebooting = false;
				if (this.reboot_again) {
					this.reboot.begin();
				}
				return;
			}
			this.win.project_manager.replace_rpc(
				new OLLMrpc.Client(data_dir, "ollmfilesd.pid", "ollmfilesd.sock")
			);
			var hello = new OLLMrpc.Request() {
				method = "RPC-Daemon.hello",
				args = OLLMrpc.args("is", 1, "ollmchat")
			};
			yield this.win.project_manager.rpc.connect(hello, new OLLMrpc.ClientBoot());
			this.rebooting = false;
			if (this.reboot_again) {
				this.reboot.begin();
			}
		}
	}
}
