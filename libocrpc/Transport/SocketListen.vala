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

namespace OLLMrpc.Transport
{
	/** Unix socket {@link Listen} — one {@link Connection} per accepted client. */
	public class SocketListen : Listen
	{
		public string socket_path { get; construct; }

		private GLib.SocketService service { get; set; default = new GLib.SocketService(); }
		private bool listening = false;
		private Gee.ArrayList<Connection> connections = new Gee.ArrayList<Connection>();

		public SocketListen(string socket_path)
		{
			GLib.Object(socket_path: socket_path);
		}

		public override bool start()
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
				var connection = new Connection(conn);
				connection.start();
				this.connections.add(connection);
				return true;
			});
			this.service.start();
			this.listening = true;
			return true;
		}

		public override void broadcast(GLib.Object gobject)
		{
			foreach (var connection in this.connections) {
				connection.write(gobject);
			}
		}

		public override void stop()
		{
			if (!this.listening) {
				return;
			}
			this.listening = false;
			this.service.stop();
			this.service = new GLib.SocketService();
			foreach (var connection in this.connections) {
				connection.stop();
			}
			this.connections.clear();
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
