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

namespace OLLMrpc.Live
{
	/**
	 * Server-side **.fd** listen and pairing for one main RPC socket path.
	 *
	 * {@link Transport.SocketListen} holds one instance when
	 * {@link Transport.Connection.live_handles} is on; all fd-channel accept
	 * logic lives here.
	 */
	public class BufferListen : GLib.Object
	{
		public string fd_path { get; private set; default = ""; }

		private GLib.SocketService service {
			get; set; default = new GLib.SocketService();
		}

		private Gee.ArrayQueue<GLib.Socket> pending_sockets {
			get; set; default = new Gee.ArrayQueue<GLib.Socket>();
		}

		private Gee.ArrayQueue<Transport.Connection> waiting_connections {
			get; set; default = new Gee.ArrayQueue<Transport.Connection>();
		}

		private bool listening = false;

		public BufferListen(string main_socket_path)
		{
			Object();
			this.fd_path = main_socket_path + ".fd";
		}

		public bool start()
		{
			if (this.listening) {
				return true;
			}
			if (GLib.FileUtils.test(this.fd_path, GLib.FileTest.EXISTS)) {
				try {
					GLib.FileUtils.unlink(this.fd_path);
				} catch (GLib.FileError e) {
					GLib.warning("could not remove stale fd socket: %s", e.message);
				}
			}
			this.service = new GLib.SocketService();
			GLib.SocketAddress? effective;
			try {
				this.service.add_address(
					new GLib.UnixSocketAddress(this.fd_path),
					GLib.SocketType.STREAM,
					GLib.SocketProtocol.DEFAULT,
					null,
					out effective
				);
			} catch (GLib.Error e) {
				GLib.warning("failed to bind fd socket %s: %s",
					this.fd_path, e.message);
				return false;
			}
			this.service.incoming.connect((conn) => {
				this.on_fd_accept(conn.get_socket());
				return true;
			});
			this.service.start();
			this.listening = true;
			return true;
		}

		public void pair_connection(Transport.Connection connection)
		{
			if (this.pending_sockets.size > 0) {
				connection.buffer_stream = new BufferStream() {
					socket = this.pending_sockets.poll()
				};
				return;
			}
			this.waiting_connections.offer(connection);
		}

		public void stop()
		{
			if (!this.listening) {
				return;
			}
			this.listening = false;
			this.service.stop();
			this.service = new GLib.SocketService();
			this.pending_sockets.clear();
			this.waiting_connections.clear();
			if (GLib.FileUtils.test(this.fd_path, GLib.FileTest.EXISTS)) {
				try {
					GLib.FileUtils.unlink(this.fd_path);
				} catch (GLib.FileError e) {
					GLib.warning("could not remove stale fd socket: %s", e.message);
				}
			}
		}

		private void on_fd_accept(GLib.Socket fd_socket)
		{
			if (this.waiting_connections.size > 0) {
				var connection = this.waiting_connections.poll();
				connection.buffer_stream = new BufferStream() {
					socket = fd_socket
				};
				return;
			}
			this.pending_sockets.offer(fd_socket);
		}
	}
}
