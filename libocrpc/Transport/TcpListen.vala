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
	/**
	 * TCP loopback {@link Listen} for platforms without Unix sockets.
	 *
	 * Defaults to loopback; remote access needs an authenticated transport
	 * before callers should bind a public address.
	 */
	public class TcpListen : Listen
	{
		public string host { get; construct; default = "127.0.0.1"; }
		public uint16 port { get; construct; default = 4141; }

		private GLib.SocketService service { get; set; default = new GLib.SocketService(); }
		private bool listening = false;
		private Gee.ArrayList<Connection> connections = new Gee.ArrayList<Connection>();

		public TcpListen(string host = "127.0.0.1", uint16 port = 4141)
		{
			GLib.Object(host: host, port: port);
		}

		public override bool start()
		{
			if (this.listening) {
				return true;
			}

			this.service = new GLib.SocketService();
			var effective = (GLib.SocketAddress) new GLib.InetSocketAddress.from_string(
				this.host,
				this.port
			);
			try {
				this.service.add_address(
					effective,
					GLib.SocketType.STREAM,
					GLib.SocketProtocol.TCP,
					null,
					out effective
				);
			} catch (GLib.Error e) {
				GLib.warning(
					"failed to bind TCP listener %s:%u: %s",
					this.host,
					this.port,
					e.message
				);
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

		public override async void broadcast(GLib.Object gobject)
		{
			foreach (var connection in this.connections) {
				yield connection.write(gobject);
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
		}
	}
}
