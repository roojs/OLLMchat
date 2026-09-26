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

namespace OLLMchat.Settings
{
	/**
	 * File-daemon listen settings on {@link Config2}.
	 *
	 * JSON key ''filesd''. ''ssl_enabled'' binds the local network
	 * SSL server from ''socket''. ''https_enabled'' binds HTTPS from
	 * ''https''. Do not read the old ''enabled'' key.
	 * {@link install} sets up the user systemd unit from
	 * {@link systemd}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * "filesd": {
	 *   "unix": true,
	 *   "socket": "",
	 *   "ssl_enabled": false,
	 *   "https": "127.0.0.1:8443",
	 *   "https_enabled": true,
	 *   "proxy": true,
	 *   "systemd": true
	 * }
	 * }}}
	 */
	public class Filesd : Object, Json.Serializable
	{
		/**
		 * Bin Unix-socket listen (default on). Config-only for now.
		 */
		public bool unix { get; set; default = true; }

		/**
		 * Local network SSL listen as ''host:port''. Kept when
		 * {@link ssl_enabled} is false. Empty means no address
		 * stored yet, not the off switch.
		 */
		public string socket { get; set; default = ""; }

		/**
		 * When false, ollmfilesd does not bind the local network
		 * SSL server. {@link socket} keeps its host and port.
		 */
		public bool ssl_enabled { get; set; default = false; }

		/**
		 * HTTPS listen as ''host:port''. Kept when
		 * {@link https_enabled} is false. Empty means no address
		 * stored yet.
		 */
		public string https { get; set; default = ""; }

		/**
		 * When false, ollmfilesd does not bind HTTPS. Host, port,
		 * {@link proxy}, and {@link systemd} keep their last values.
		 */
		public bool https_enabled { get; set; default = true; }

		/**
		 * Expect PROXY Protocol v1 on the HTTPS TCP listener.
		 */
		public bool proxy { get; set; default = false; }

		/**
		 * Install and enable the systemd user unit when true.
		 */
		public bool systemd { get; set; default = false; }

		public Filesd()
		{
		}

		/**
		 * Write the user unit and enable it when {@link systemd} is true.
		 *
		 * When {@link systemd} is false, runs ''disable --now'' on the
		 * user unit. Skips rewrite when the unit file already matches.
		 * Skips ''enable --now'' when already active or when this
		 * binary is ollmfilesd (the unit already started us).
		 * ''ExecStart'' is ''ollmfilesd'' on PATH. The unit sets
		 * ''OLLMFILESD_DAEMON=1'' so the process does not double-fork
		 * under ''Type=simple''.
		 */
		public void install()
		{
			if (!this.systemd) {
				string sout, serr;
				int status;
				try {
					GLib.Process.spawn_command_line_sync(
						"systemctl --user disable --now ollmfilesd.service",
						out sout, out serr, out status);
				} catch (GLib.Error e) {
					GLib.warning("systemd disable failed: %s", e.message);
				}
				return;
			}
			var unit_dir = GLib.Path.build_filename(
				GLib.Environment.get_user_config_dir(),
				"systemd",
				"user"
			);
			if (!GLib.FileUtils.test(unit_dir, GLib.FileTest.IS_DIR)) {
				GLib.DirUtils.create_with_parents(unit_dir, 0755);
			}
			var unit_path = GLib.Path.build_filename(
				unit_dir,
				"ollmfilesd.service"
			);
			var exe = GLib.Environment.find_program_in_path("ollmfilesd");
			if (exe == null || exe == "") {
				exe = "ollmfilesd";
			}
			var unit_text = """
[Unit]
Description=OLLMchat file daemon (ollmfilesd)
After=default.target

[Service]
Type=simple
Environment=OLLMFILESD_DAEMON=1
ExecStart=""" + exe + """
Restart=on-failure

[Install]
WantedBy=default.target
""";
			var need_write = true;
			if (GLib.FileUtils.test(unit_path, GLib.FileTest.EXISTS)) {
				try {
					var existing = "";
					GLib.FileUtils.get_contents(unit_path, out existing);
					if (existing == unit_text) {
						need_write = false;
					}
				} catch (GLib.Error e) {
				}
			}
			if (need_write) {
				try {
					GLib.FileUtils.set_contents(unit_path, unit_text);
				} catch (GLib.Error e) {
					GLib.warning("systemd unit write failed: %s", e.message);
					return;
				}
				string reload_out, reload_err;
				int reload_status;
				try {
					GLib.Process.spawn_command_line_sync(
						"systemctl --user daemon-reload",
						out reload_out, out reload_err, out reload_status);
				} catch (GLib.Error e) {
					GLib.warning("systemd daemon-reload failed: %s", e.message);
				}
				GLib.debug("systemd user unit installed at %s", unit_path);
			}
			try {
				if (GLib.Path.get_basename(GLib.FileUtils.read_link("/proc/self/exe")) == "ollmfilesd") {
					return;
				}
			} catch (GLib.FileError e) {
			}
			try {
				var sout = "";
				var serr = "";
				var status = 0;
				GLib.Process.spawn_command_line_sync(
					"systemctl --user is-active ollmfilesd.service",
					out sout,
					out serr,
					out status
				);
				if (sout.strip() == "active") {
					return;
				}
			} catch (GLib.Error e) {
			}
			string en_out, en_err;
			int en_status;
			try {
				GLib.Process.spawn_command_line_sync(
					"systemctl --user enable --now ollmfilesd.service",
					out en_out, out en_err, out en_status);
			} catch (GLib.Error e) {
				GLib.warning("systemd enable failed: %s", e.message);
			}
		}

		public unowned ParamSpec? find_property(string name)
		{
			return this.get_class().find_property(name);
		}

		public new void Json.Serializable.set_property(ParamSpec pspec, Value value)
		{
			base.set_property(pspec.get_name(), value);
		}

		public new Value Json.Serializable.get_property(ParamSpec pspec)
		{
			Value val = Value(pspec.value_type);
			base.get_property(pspec.get_name(), ref val);
			return val;
		}

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			return default_serialize_property(property_name, value, pspec);
		}

		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			return default_deserialize_property(property_name, out value, pspec, property_node);
		}
	}
}
