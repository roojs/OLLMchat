/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMfilesd
{
	/**
	 * Unix socket listener — one {@link Session} per accepted connection.
	 * Holds RPC targets (one GObject property per wire `kind`).
	 */
	public class Listen : GLib.Object
	{
		public Rpc.Daemon daemon { get; default = new Rpc.Daemon(); }
		public Rpc.Projects projects { get; default = new Rpc.Projects(); }
		public string socket_path { get; construct; }

		private GLib.SocketService service { get; set; default = new GLib.SocketService(); }
		private bool listening = false;
		private Gee.ArrayList<Session> sessions = new Gee.ArrayList<Session>();

		public Listen(string? socket_path = null)
		{
			GLib.Object(
				socket_path: socket_path != null ? socket_path : GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(),
					"ollmchat",
					"ollmfilesd.sock"
				)
			);
		}

		public bool start()
		{
			if (this.listening) {
				return true;
			}

			var parent = GLib.File.new_for_path(this.socket_path).get_parent();
			if (parent != null && !parent.query_exists()) {
				try {
					parent.make_directory_with_parents(null);
				} catch (GLib.Error e) {
					GLib.warning("failed to create socket directory: %s", e.message);
					return false;
				}
			}

			if (GLib.FileUtils.test(this.socket_path, GLib.FileTest.EXISTS)) {
				try {
					GLib.FileUtils.unlink(this.socket_path);
				} catch (GLib.FileError e) {
					GLib.warning("could not remove stale socket: %s", e.message);
				}
			}

			this.service = new GLib.SocketService();
			GLib.SocketAddress? effective;
			try {
				this.service.add_address(
					new GLib.UnixSocketAddress(this.socket_path),
					GLib.SocketType.STREAM,
					GLib.SocketProtocol.DEFAULT,
					null,
					out effective
				);
			} catch (GLib.Error e) {
				GLib.warning("failed to bind socket %s: %s",
					this.socket_path, e.message);
				return false;
			}
			this.service.incoming.connect((conn) => {
				var session = new Session(this, conn);
				session.start();
				this.sessions.add(session);
				return true;
			});
			this.service.start();
			this.listening = true;
			return true;
		}

		public void stop()
		{
			if (!this.listening) {
				return;
			}
			this.listening = false;
			this.service.stop();
			this.service = new GLib.SocketService();
			foreach (var session in this.sessions) {
				session.stop();
			}
			this.sessions.clear();
			if (GLib.FileUtils.test(this.socket_path, GLib.FileTest.EXISTS)) {
				try {
					GLib.FileUtils.unlink(this.socket_path);
				} catch (GLib.FileError e) {
					GLib.warning("could not remove stale socket: %s", e.message);
				}
			}
		}
	}
}
