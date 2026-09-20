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
	 * Widget group for the desktop File Server expander.
	 *
	 * Binds {@link OLLMchat.Settings.Filesd} listen fields (https
	 * host/port, proxy, systemd). Off {@link enabled_switch} hides
	 * Host / Port / Proxy and sets
	 * {@link OLLMchat.Settings.Filesd.enabled} false without
	 * clearing their values. {@link systemd_row} stays visible.
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
		 * The expander row containing File Server fields.
		 */
		public Adw.ExpanderRow expander { get; private set; }

		/**
		 * File Server HTTPS on/off. Off hides Host / Port / Proxy
		 * and sets {@link OLLMchat.Settings.Filesd.enabled} false;
		 * those fields keep their last values. systemd stays shown.
		 */
		public Gtk.Switch enabled_switch { get; private set; }

		/**
		 * HTTPS listen IP from this machine (left of ''host:port'' in
		 * {@link OLLMchat.Settings.Filesd.https}).
		 */
		public Gtk.DropDown host_dropdown { get; private set; }
		/**
		 * Host (interface) action row; hidden when Enabled is off
		 * or when no IPv4 addresses.
		 */
		public Adw.ActionRow host_row { get; private set; }

		/**
		 * HTTPS listen port (right of ''host:port'' in
		 * {@link OLLMchat.Settings.Filesd.https}). Suffix
		 * {@link Gtk.Entry} with
		 * {@link Adw.ActionRow.set_activatable_widget} like Tools
		 * Engine ID. ''width_chars = 5'' fits 65535. Valid range
		 * 1024–65535; empty is off. Too low or too high sets this
		 * row's subtitle to ''Invalid'' and is not written.
		 */
		public Gtk.Entry port_entry { get; private set; }
		/**
		 * Port action row; hidden when Enabled is off or when no
		 * IPv4 addresses.
		 */
		public Adw.ActionRow port_row { get; private set; }

		/**
		 * PROXY Protocol switch bound to
		 * {@link OLLMchat.Settings.Filesd.proxy}.
		 */
		public Gtk.Switch proxy_switch { get; private set; }

		/**
		 * systemd user-unit switch bound to
		 * {@link OLLMchat.Settings.Filesd.systemd}.
		 */
		public Gtk.Switch systemd_switch { get; private set; }

		/**
		 * Proxy action row; hidden when Enabled is off.
		 */
		private Adw.ActionRow proxy_row;

		/**
		 * systemd action row; always shown (start-on-boot is
		 * independent of HTTPS Enabled).
		 */
		private Adw.ActionRow systemd_row;

		/**
		 * Config ''filesd'' object this expander edits.
		 */
		public OLLMchat.Settings.Filesd filesd { get; private set; }
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
		 * File Server expander for one {@link OLLMchat.Settings.Filesd}.
		 *
		 * @param filesd Config listen settings (enabled, https, proxy, systemd)
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
				title = "File Server",
				subtitle = "Not running"
			};
			this.enabled_switch = new Gtk.Switch() {
				active = false,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.expander.add_suffix(this.enabled_switch);

			this.host_dropdown = new Gtk.DropDown(new Gtk.StringList({}), null) {
				selected = Gtk.INVALID_LIST_POSITION,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.host_row = new Adw.ActionRow() {
				title = "Host",
				visible = false
			};
			this.host_row.add_suffix(this.host_dropdown);
			this.host_row.set_activatable_widget(this.host_dropdown);
			this.expander.add_row(this.host_row);

			this.port_entry = new Gtk.Entry() {
				width_chars = 5,
				valign = Gtk.Align.CENTER,
				max_length = 5,
				placeholder_text = "8443"
			};
			this.port_entry.insert_text.connect((new_text, new_text_length, ref position) => {
				if (GLib.Regex.match_simple("^[0-9]*$", new_text)) {
					return;
				}
				GLib.Signal.stop_emission_by_name(this.port_entry, "insert-text");
			});
			this.port_row = new Adw.ActionRow() {
				title = "Port",
				visible = false
			};
			this.port_row.add_suffix(this.port_entry);
			this.port_row.set_activatable_widget(this.port_entry);
			var port_focus = new Gtk.EventControllerFocus();
			port_focus.leave.connect(() => {
				if (this.loading) {
					return;
				}
				this.apply_config();
			});
			this.port_entry.add_controller(port_focus);
			this.expander.add_row(this.port_row);

			this.proxy_switch = new Gtk.Switch() {
				active = false,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.proxy_row = new Adw.ActionRow() {
				title = "Proxy",
				visible = false
			};
			this.proxy_row.add_suffix(this.proxy_switch);
			this.expander.add_row(this.proxy_row);

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

			this.enabled_switch.notify["active"].connect(() => {
				this.proxy_row.visible = this.enabled_switch.active;
				this.host_row.visible = false;
				this.port_row.visible = false;
				if (this.enabled_switch.active && this.host_dropdown.model.get_n_items() > 0) {
					this.host_row.visible = true;
					this.port_row.visible = true;
				}
				if (this.loading) {
					return;
				}
				this.apply_config();
			});
			this.host_dropdown.notify["selected"].connect(() => {
				if (this.loading) {
					return;
				}
				this.apply_config();
			});
			this.proxy_switch.notify["active"].connect(() => {
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
		 * Fill Host / Port / Proxy / systemd from {@link filesd}.
		 *
		 * Enumerates this machine's IPv4 listen addresses into
		 * {@link host_dropdown}. Off {@link enabled_switch} hides
		 * Host / Port / Proxy without clearing widgets.
		 * {@link systemd_row} stays visible. No addresses: hide
		 * {@link host_row} and {@link port_row} even when Enabled is
		 * on. Call when the settings dialog is shown, not from the
		 * constructor.
		 */
		public void load_config()
		{
			this.loading = true;
			var host = "";
			var port = "";
			var colon = this.filesd.https.last_index_of(":");
			if (colon > 0) {
				host = this.filesd.https.substring(0, colon);
				port = this.filesd.https.substring(colon + 1);
			}
			string[] ips = {};
			Linux.Network.IfAddrs addrs;
			if (Linux.Network.getifaddrs(out addrs) == 0) {
				for (unowned var iface = addrs; iface != null; iface = iface.ifa_next) {
					if (iface.ifa_addr == null) {
						continue;
					}
					if (iface.ifa_addr.sa_family != Posix.AF_INET) {
						continue;
					}
					if ((iface.ifa_flags & Linux.Network.IfFlag.UP) == 0) {
						continue;
					}
					var sin = (Posix.SockAddrIn*) iface.ifa_addr;
					var buf = new uint8[Posix.INET_ADDRSTRLEN];
					var ip = Posix.inet_ntop(Posix.AF_INET, &sin.sin_addr, buf);
					if (ip == null || ip == "" || ip == "0.0.0.0") {
						continue;
					}
					var seen = false;
					foreach (var existing in ips) {
						if (existing != ip) {
							continue;
						}
						seen = true;
						break;
					}
					if (seen) {
						continue;
					}
					ips += ip;
				}
			}
			this.proxy_switch.active = this.filesd.proxy;
			this.systemd_switch.active = this.filesd.systemd;
			var n = 0;
			int.try_parse(port, out n);
			this.port_entry.text = port;
			this.port_row.subtitle = "";
			this.port_entry.remove_css_class("error");
			if (port != "" && (n < 1024 || n > 65535)) {
				this.port_row.subtitle = "Invalid";
				this.port_entry.add_css_class("error");
			}
			if (ips.length > 0) {
				var selected = Gtk.INVALID_LIST_POSITION;
				for (var i = 0; i < ips.length; i++) {
					if (ips[i] != host) {
						continue;
					}
					selected = i;
					break;
				}
				if (host != "" && selected == Gtk.INVALID_LIST_POSITION) {
					ips += host;
					selected = ips.length - 1;
				}
				this.host_dropdown.model = new Gtk.StringList(ips);
				this.host_dropdown.selected = selected;
			}
			this.enabled_switch.active = this.filesd.enabled;
			var data_dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "ollmchat");
			var boot = new OLLMrpc.ClientBoot(data_dir, "ollmfilesd.pid", "ollmfilesd.sock");
			var up = boot.connectable();
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
			var https_ok = this.filesd.enabled && n >= 1024 && n <= 65535;
			this.expander.subtitle = "Not running";
			if (up) {
				this.expander.subtitle = "Running on startup (socket only)";
			}
			if (up && via_systemd) {
				this.expander.subtitle = "Running via systemd (socket only)";
			}
			if (up && https_ok) {
				this.expander.subtitle = "Running on startup (socket and HTTPS)";
			}
			if (up && via_systemd && https_ok) {
				this.expander.subtitle = "Running via systemd (socket and HTTPS)";
			}
			this.proxy_row.visible = this.enabled_switch.active;
			this.host_row.visible = false;
			this.port_row.visible = false;
			if (this.enabled_switch.active && ips.length > 0) {
				this.host_row.visible = true;
				this.port_row.visible = true;
			}
			this.loading = false;
		}

		/**
		 * Write Enabled / Host / Port / Proxy / systemd back into
		 * {@link filesd}.
		 *
		 * Off {@link enabled_switch} sets
		 * {@link OLLMchat.Settings.Filesd.enabled} false and leaves
		 * ''https'' / proxy unchanged. systemd is always written.
		 * On, Host / Port write ''https'' when both are filled. If
		 * listen fields changed, save config and {@link reboot}.
		 */
		public void apply_config()
		{
			var prev_https = this.filesd.https;
			var prev_proxy = this.filesd.proxy;
			var prev_systemd = this.filesd.systemd;
			var prev_enabled = this.filesd.enabled;
			this.was_systemd = prev_systemd;
			this.filesd.enabled = this.enabled_switch.active;
			if (this.filesd.enabled && this.host_row.visible) {
				var host = "";
				var item = this.host_dropdown.selected_item as Gtk.StringObject;
				if (item != null) {
					host = item.string;
				}
				var n = 0;
				var port = this.port_entry.text.strip();
				int.try_parse(port, out n);
				this.port_row.subtitle = "";
				this.port_entry.remove_css_class("error");
				if (port != "" && (n < 1024 || n > 65535)) {
					this.port_row.subtitle = "Invalid";
					this.port_entry.add_css_class("error");
				}
				if (host != "" && n >= 1024 && n <= 65535) {
					this.filesd.https = host + ":" + n.to_string();
				}
			}
			this.filesd.systemd = this.systemd_switch.active;
			if (this.filesd.enabled) {
				this.filesd.proxy = this.proxy_switch.active;
			}
			if (this.filesd.enabled != prev_enabled
				|| this.filesd.https != prev_https
				|| this.filesd.proxy != prev_proxy
				|| this.filesd.systemd != prev_systemd) {
				this.win.app.config.save();
				GLib.debug("file server apply systemd=%s was=%s https=%s",
					this.filesd.systemd ? "on" : "off",
					this.was_systemd ? "on" : "off", this.filesd.https);
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
		 * {@link OLLMrpc.ClientBoot.ensure_daemon}. Spawn or stay-up failure toasts
		 * ''File server did not stay up'' on Connections. If this
		 * window is still on Unix, reconnect
		 * {@link OLLMfiles.ProjectManager} like
		 * {@link FileConnectionRow.reconnect} with ''remote = false''.
		 * If the window is on a remote file connection, only bounce the
		 * local daemon.
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
			var https_ok = false;
			var colon = this.filesd.https.last_index_of(":");
			if (this.filesd.enabled && colon > 0) {
				var n = 0;
				if (int.try_parse(this.filesd.https.substring(colon + 1), out n)
					&& n >= 1024 && n <= 65535) {
					https_ok = true;
				}
			}
			this.expander.subtitle = "Running on startup (socket only)";
			if (via_systemd) {
				this.expander.subtitle = "Running via systemd (socket only)";
			}
			if (https_ok) {
				this.expander.subtitle = "Running on startup (socket and HTTPS)";
			}
			if (via_systemd && https_ok) {
				this.expander.subtitle = "Running via systemd (socket and HTTPS)";
			}
			var done = "Running on startup";
			if (via_systemd) {
				done = "Running via systemd";
			}
			this.toast_overlay.add_toast(new Adw.Toast(done) { timeout = 2 });
			if (this.win.project_manager.rpc.http != null) {
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
