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
	 * Per-connection ''SCM_RIGHTS'' fd channel — separate from the main bin RPC
	 * socket. All fd send/recv/watch logic lives here; {@link OLLMrpc.Transport.Connection}
	 * and {@link OLLMrpc.Client} only hold a reference and delegate.
	 */
	public class BufferStream : GLib.Object
	{
		public GLib.Socket? socket { get; private set; default = null; }

		internal Gee.ArrayQueue<Buffer> pending {
			get;
			private set;
			default = new Gee.ArrayQueue<Buffer>();
		}

		private GLib.IOChannel? channel = null;
		private uint watch_id = 0;

		/** Server: wrap an accepted fd-channel socket (no watch). */
		public BufferStream.socket(GLib.Socket socket)
		{
			Object();
			this.socket = socket;
		}

		/** Client: empty until {@link connect_client}. */
		public BufferStream()
		{
			Object();
		}

		/**
		 * Client: connect the **.fd** leg and start watching.
		 *
		 * Call after {@link BufferStream()} on the client path.
		 *
		 * @param main_socket_path main RPC socket path (**.fd** is appended)
		 */
		public async void connect_client(string main_socket_path) throws GLib.Error
		{
			var fd_client = new GLib.SocketClient();
			var fd_conn = yield fd_client.connect_async(
				new GLib.UnixSocketAddress(main_socket_path + ".fd"),
				null
			);
			this.socket = fd_conn.get_socket();
			this.start_watch();
		}

		/**
		 * Server send path: fd on this channel first, then bin object on main.
		 */
		public void write_with(
			Buffer? buffer,
			Bin.Serializable serializable,
			Bin.Stream bin
		) throws GLib.Error
		{
			if (buffer != null && this.socket != null) {
				buffer.send(this.socket);
			}
			bin.write(serializable);
			bin.out_stream.flush();
		}

		/** Client receive path: attach the next queued fd to a notification. */
		public void attach(Notification notif)
		{
			notif.buffer = this.take_pending();
		}

		/** Pop the next received fd (client). FIFO — matches fd-first send order. */
		public Buffer? take_pending()
		{
			if (this.pending.size == 0) {
				return null;
			}
			return this.pending.poll();
		}

		/** One ''recvmsg''; queue a {@link Buffer} with the stolen fd. */
		public void receive_one() throws GLib.Error
		{
			if (this.socket == null) {
				return;
			}
			var buffer = new Buffer();
			buffer.receive(this.socket);
			this.pending.offer(buffer);
		}

		/** Client: watch fd channel and fill {@link pending}. */
		public void start_watch()
		{
			if (this.socket == null || this.watch_id != 0) {
				return;
			}
			var fd = this.socket.get_fd();
			this.channel = new GLib.IOChannel.unix_new(fd);
			this.channel.set_encoding(null);
			this.channel.set_buffered(false);
			this.watch_id = this.channel.add_watch(
				GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR,
				this.on_input_ready
			);
		}

		public void close()
		{
			if (this.watch_id != 0) {
				GLib.Source.remove(this.watch_id);
				this.watch_id = 0;
			}
			this.channel = null;
			if (this.socket != null) {
				try {
					this.socket.close();
				} catch (GLib.Error e) {
				}
				this.socket = null;
			}
			this.pending.clear();
		}

		private bool on_input_ready(
			GLib.IOChannel source,
			GLib.IOCondition condition
		)
		{
			if ((condition & GLib.IOCondition.HUP) != 0
			 || (condition & GLib.IOCondition.ERR) != 0) {
				this.close();
				return false;
			}
			if ((condition & GLib.IOCondition.IN) == 0) {
				return this.socket != null;
			}
			do {
				if (this.socket == null) {
					break;
				}
				try {
					this.receive_one();
				} catch (GLib.IOError e) {
					if (e.code == GLib.IOError.WOULD_BLOCK) {
						break;
					}
					GLib.warning("buffer stream receive: %s", e.message);
					this.close();
					return false;
				} catch (GLib.Error e) {
					GLib.warning("buffer stream receive: %s", e.message);
					this.close();
					return false;
				}
			} while (
				(source.get_buffer_condition() & GLib.IOCondition.IN) != 0
			);
			return this.socket != null;
		}
	}

	/**
	 * Server-side **.fd** listen and pairing for one main RPC socket path.
	 *
	 * {@link Transport.SocketListen} holds one instance when
	 * {@link Transport.Connection.live_handles} is on; all fd-channel accept
	 * logic lives here.
	 */
	public class BufferListen : GLib.Object
	{
		private string fd_path { get; construct; }

		private GLib.SocketService service {
			get;
			set;
			default = new GLib.SocketService();
		}

		private Gee.ArrayQueue<GLib.Socket> pending_sockets {
			get;
			set;
			default = new Gee.ArrayQueue<GLib.Socket>();
		}

		private Gee.ArrayQueue<Transport.Connection> waiting_connections {
			get;
			set;
			default = new Gee.ArrayQueue<Transport.Connection>();
		}

		private bool listening = false;

		public BufferListen(string main_socket_path)
		{
			Object(fd_path: main_socket_path + ".fd");
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
				connection.buffer_stream = new BufferStream.socket(
					this.pending_sockets.poll()
				);
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
				connection.buffer_stream = new BufferStream.socket(fd_socket);
				return;
			}
			this.pending_sockets.offer(fd_socket);
		}
	}
}
