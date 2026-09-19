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
	 * those rows and sets {@link OLLMchat.Settings.Filesd.enabled}
	 * false without clearing their values. The Connections page
	 * calls {@link apply_config} on close, which writes
	 * {@link filesd} and {@link reboot}s if listen fields changed.
	 * {@link load_config} fills the IP dropdown and listen fields
	 * when the settings dialog is shown.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var row = new FileServerRow(config.filesd, win);
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
		 * File Server on/off. Off hides Host / Port / Proxy /
		 * systemd and sets {@link OLLMchat.Settings.Filesd.enabled}
		 * false; those fields keep their last values.
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
		 * {@link OLLMchat.Settings.Filesd.https}).
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
		 * systemd action row; hidden when Enabled is off.
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
		 * File Server expander for one {@link OLLMchat.Settings.Filesd}.
		 *
		 * @param filesd Config listen settings (enabled, https, proxy, systemd)
		 * @param win Host window for ProjectManager reconnect
		 */
		public FileServerRow(OLLMchat.Settings.Filesd filesd, OllmchatWindow win)
		{
			this.filesd = filesd;
			this.win = win;
			this.expander = new Adw.ExpanderRow() {
				title = "File Server",
				subtitle = "Off",
				can_focus = false,
				focus_on_click = false
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
				activatable = false,
				visible = false
			};
			this.host_row.add_suffix(this.host_dropdown);
			this.expander.add_row(this.host_row);

			this.port_entry = new Gtk.Entry() {
				text = "",
				placeholder_text = "8443",
				width_chars = 6,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.port_row = new Adw.ActionRow() {
				title = "Port",
				activatable = false,
				visible = false
			};
			this.port_row.add_suffix(this.port_entry);
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
				title = "systemd",
				visible = false
			};
			this.systemd_row.add_suffix(this.systemd_switch);
			this.expander.add_row(this.systemd_row);

			this.enabled_switch.notify["active"].connect(() => {
				this.proxy_row.visible = this.enabled_switch.active;
				this.systemd_row.visible = this.enabled_switch.active;
				this.host_row.visible = false;
				this.port_row.visible = false;
				if (!this.enabled_switch.active) {
					return;
				}
				if (this.host_dropdown.model.get_n_items() == 0) {
					return;
				}
				this.host_row.visible = true;
				this.port_row.visible = true;
			});
		}

		/**
		 * Fill Host / Port / Proxy / systemd from {@link filesd}.
		 *
		 * Enumerates this machine's IPv4 listen addresses into
		 * {@link host_dropdown}. Off {@link enabled_switch} hides
		 * Host / Port / Proxy / systemd without clearing widgets.
		 * No addresses: hide {@link host_row} and {@link port_row}
		 * even when Enabled is on. Call when the settings dialog is
		 * shown, not from the constructor.
		 */
		public void load_config()
		{
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
			this.port_entry.text = port;
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
			this.expander.subtitle = "Off";
			if (this.filesd.enabled && this.filesd.https != "") {
				this.expander.subtitle = this.filesd.https;
			}
			this.proxy_row.visible = this.enabled_switch.active;
			this.systemd_row.visible = this.enabled_switch.active;
			this.host_row.visible = false;
			this.port_row.visible = false;
			if (!this.enabled_switch.active) {
				return;
			}
			if (ips.length == 0) {
				return;
			}
			this.host_row.visible = true;
			this.port_row.visible = true;
		}

		/**
		 * Write Enabled / Host / Port / Proxy / systemd back into
		 * {@link filesd}.
		 *
		 * Off {@link enabled_switch} sets
		 * {@link OLLMchat.Settings.Filesd.enabled} false and leaves
		 * ''https'' / proxy / systemd unchanged. On, Host / Port
		 * write ''https'' when both are filled. If listen fields
		 * changed, save config and {@link reboot}.
		 */
		public void apply_config()
		{
			var prev_https = this.filesd.https;
			var prev_proxy = this.filesd.proxy;
			var prev_systemd = this.filesd.systemd;
			var prev_enabled = this.filesd.enabled;
			this.filesd.enabled = this.enabled_switch.active;
			if (this.filesd.enabled && this.host_row.visible) {
				var host = "";
				var item = this.host_dropdown.selected_item as Gtk.StringObject;
				if (item != null) {
					host = item.string;
				}
				var port = this.port_entry.text.strip();
				if (host != "" && port != "") {
					this.filesd.https = host + ":" + port;
				}
			}
			if (this.filesd.enabled) {
				this.filesd.proxy = this.proxy_switch.active;
				this.filesd.systemd = this.systemd_switch.active;
			}
			this.expander.subtitle = "Off";
			if (this.filesd.enabled && this.filesd.https != "") {
				this.expander.subtitle = this.filesd.https;
			}
			if (this.filesd.enabled != prev_enabled
				|| this.filesd.https != prev_https
				|| this.filesd.proxy != prev_proxy
				|| this.filesd.systemd != prev_systemd) {
				this.win.app.config.save();
				this.reboot.begin();
			}
		}

		/**
		 * Stop the local Unix ollmfilesd and start it again.
		 *
		 * {@link OLLMrpc.ClientBoot.kill} then
		 * {@link OLLMrpc.ClientBoot.ensure_daemon}. Spawn failure
		 * raises ''Alert.show'' on the window and returns. If this
		 * window is still on Unix, reconnect
		 * {@link OLLMfiles.ProjectManager} like
		 * {@link FileConnectionRow.reconnect} with ''remote = false''.
		 * If the window is on a remote file connection, only bounce the
		 * local daemon.
		 */
		public async void reboot()
		{
			var data_dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "ollmchat");
			var boot = new OLLMrpc.ClientBoot(data_dir, "ollmfilesd.pid", "ollmfilesd.sock");
			yield boot.kill();
			try {
				yield boot.ensure_daemon();
			} catch (GLib.Error e) {
				GLib.critical("file server restart: %s", e.message);
				this.win.notification(new OLLMrpc.Notification() {
					method = "Alert.show",
					message = "File daemon is not up: " + e.message
				});
				return;
			}
			if (this.win.project_manager.rpc.http != null) {
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
		}
	}
}
