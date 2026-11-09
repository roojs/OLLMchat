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

namespace OLLMrpc.Transport
{
	/**
	 * TCP TLS client that sends a {@link OLLMrpc.Request} and
	 * returns that {@link OLLMrpc.Response}. {@link watch} reads
	 * {@link OLLMrpc.Notification} while idle. {@link call} emits
	 * {@link notification} for those messages instead of dropping them.
	 *
	 * Peer to {@link HttpClient} for a raw socket. Not
	 * {@link OLLMrpc.Client}: that type sends hello, drops the
	 * body, and keeps a read watch. {@link open} handshakes
	 * once. A later {@link call} writes the next request on
	 * that stream. {@link call} opens first when the caller
	 * did not. The reply wait polls the socket, so it runs on
	 * Android, where {@link OLLMrpc.Client.call_sync} throws.
	 *
	 * Set {@link accept_any} to accept any server certificate.
	 * {@link tls_certificate} is still presented when it is
	 * set. Registration leaves it unset. Argus download and
	 * the identity post set both. Leave {@link accept_any}
	 * false to require a peer certificate and ignore only
	 * {@link GLib.TlsCertificateFlags.BAD_IDENTITY}, the same
	 * rule as {@link OLLMrpc.Client.connect}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var connection = new OLLMrpc.Transport.TlsClient(host, port) {
	 *     accept_any = true
	 * };
	 * var response = connection.call(request);
	 *
	 * var authed = new OLLMrpc.Transport.TlsClient(host, port) {
	 *     tls_certificate = certificate,
	 *     tls_database = trust
	 * };
	 * var paired = authed.call(pair_request);
	 * var hello = authed.call(hello_request);
	 *
	 * var download = new OLLMrpc.Transport.TlsClient(host, port) {
	 *     accept_any = true,
	 *     tls_certificate = certificate
	 * };
	 * var file = download.call(get_request);
	 * }}}
	 */
	public class TlsClient : GLib.Object
	{
		/** Remote host passed to {@link GLib.SocketClient.connect_to_host}. */
		public string host { get; construct; }

		/** Remote port passed to {@link GLib.SocketClient.connect_to_host}. */
		public uint16 port { get; construct; }

		/**
		 * True accepts any server certificate.
		 *
		 * {@link tls_certificate} is still presented when it is set.
		 * Registration leaves the certificate unset. Argus download
		 * and the identity post set both.
		 */
		public bool accept_any = false;

		/**
		 * Seconds for the TCP connect. The reply wait is 10 seconds,
		 * matching the copied loops.
		 */
		public uint timeout = 10;

		/**
		 * Client certificate to present. Null sends none, matching
		 * {@link HttpClient.tls_certificate}.
		 */
		public GLib.TlsCertificate? tls_certificate { get; set; default = null; }

		/**
		 * Product CA trust store. Null leaves the handshake on
		 * the {@link accept_any} or bad-identity rule, matching
		 * {@link HttpClient.tls_database}.
		 */
		public GLib.TlsDatabase? tls_database { get; set; default = null; }

		/**
		 * A notification parsed on this stream.
		 *
		 * {@link call} emits this when the next message is a
		 * {@link OLLMrpc.Notification}. {@link watch} emits the
		 * same signal while idle.
		 *
		 * @param notif the decoded notification
		 */
		public signal void notification(Notification notif);

		/**
		 * The idle read stopped because the connection failed.
		 *
		 * {@link watch} emits this after it closes the socket.
		 * {@link connected} is then false, so {@link open} can
		 * handshake again.
		 */
		public signal void closed();

		/**
		 * True after {@link open} until the idle read fails.
		 */
		public bool connected { get; private set; default = false; }
		private int fd = -1;
		private uint watch_id = 0;
		private bool watching = false;
		private GLib.Mutex mutex;
		/* Keeps the handshake alive. The bin streams borrow the
		 * TLS input stream; they do not own the connection. */
		private GLib.SocketConnection? socket = null;
		private GLib.TlsClientConnection? connection = null;
		private Bin.Stream bin {
			get; set; default = new Bin.Stream(null, null, false);
		}

		public TlsClient(string host, uint16 port)
		{
			GLib.Object(host: host, port: port);
		}

		/**
		 * Connect and handshake. A second call returns immediately.
		 *
		 * {@link call} invokes this when the caller did not.
		 *
		 * @throws GLib.Error the TCP connect or the TLS handshake failed
		 */
		public void open() throws GLib.Error
		{
			if (this.connected) {
				return;
			}
			var client = new GLib.SocketClient();
			client.timeout = this.timeout;
			var conn = client.connect_to_host(this.host, this.port);
			/* Android's async connect leaves the socket nonblocking.
			 * The reply wait in call needs a blocking socket that
			 * still reports WOULD_BLOCK until TLS has data. */
			conn.socket.blocking = true;
			var tls = GLib.TlsClientConnection.@new(conn, null);
			if (this.tls_certificate != null) {
				tls.set_certificate(this.tls_certificate);
			}
			if (this.accept_any) {
				tls.accept_certificate.connect((peer_cert, errors) => {
					return true;
				});
			}
			if (!this.accept_any) {
				if (this.tls_database != null) {
					tls.database = this.tls_database;
				}
				tls.accept_certificate.connect((peer_cert, errors) => {
					return peer_cert != null &&
						(errors & ~GLib.TlsCertificateFlags.BAD_IDENTITY) == 0;
				});
			}
			tls.handshake();
			this.bin.in_stream = new GLib.DataInputStream(tls.get_input_stream());
			this.bin.in_stream.set_byte_order(GLib.DataStreamByteOrder.BIG_ENDIAN);
			this.bin.out_stream = new GLib.DataOutputStream(tls.get_output_stream());
			this.bin.out_stream.set_byte_order(GLib.DataStreamByteOrder.BIG_ENDIAN);
			this.socket = conn;
			this.connection = tls;
			this.fd = conn.socket.fd;
			this.connected = true;
		}

		/**
		 * Write one request and return the next {@link OLLMrpc.Response}.
		 *
		 * Opens first when {@link open} has not run. A later call
		 * uses the same stream.
		 *
		 * @param request wire request; the caller owns
		 *   {@link OLLMrpc.Request.id}
		 * @return decoded response, including a response error
		 * @throws GLib.Error connect, handshake, or the reply
		 *   wait ran out
		 */
		public Response call(Request request) throws GLib.Error
		{
			this.open();
			if (this.watch_id != 0) {
				GLib.Source.remove(this.watch_id);
				this.watch_id = 0;
			}
			this.socket.socket.blocking = true;
			this.mutex.lock();
			this.bin.write(request);
			var reply_wait = GLib.get_monotonic_time() + 10 * 1000000;
			while (true) {
				try {
					var parsed = this.bin.parse();
					var notif = parsed as Notification;
					if (notif != null) {
						this.notification(notif);
						continue;
					}
					if (!(parsed is Response)) {
						continue;
					}
					this.mutex.unlock();
					if (this.watching) {
						GLib.Idle.add(() => {
							this.watch();
							return false;
						});
					}
					return (Response) parsed;
				} catch (GLib.IOError e) {
					if (e.code != GLib.IOError.WOULD_BLOCK ||
						GLib.get_monotonic_time() >= reply_wait) {
						this.mutex.unlock();
						if (this.watching) {
							GLib.Idle.add(() => {
								this.watch();
								return false;
							});
						}
						throw e;
					}
					var reply_poll = GLib.PollFD();
					reply_poll.fd = this.fd;
					reply_poll.events = GLib.IOCondition.IN;
					GLib.poll(new GLib.PollFD[] { reply_poll }, 200);
				}
			}
		}

		/**
		 * Read notifications while no {@link call} is waiting.
		 *
		 * A second call is ignored. {@link call} removes the
		 * source and queues this again when {@link watching} is
		 * set. The source is a timeout. A would-block or
		 * timed-out read keeps the source. Any other read error
		 * stops the source, closes the socket, and emits
		 * {@link closed}.
		 */
		public void watch()
		{
			if (this.watch_id != 0) {
				return;
			}
			this.watching = true;
			this.open();
			this.socket.socket.blocking = false;
			this.watch_id = GLib.Timeout.add(50, () => {
				if (this.watch_id == 0) {
					return false;
				}
				this.mutex.lock();
				if (this.watch_id == 0) {
					this.mutex.unlock();
					return false;
				}
				this.socket.socket.blocking = false;
				if (this.bin.in_stream.get_available() < 1) {
					var pollable = this.connection.get_input_stream()
						as GLib.PollableInputStream;
					if (pollable == null || !pollable.is_readable()) {
						this.mutex.unlock();
						return true;
					}
				}
				try {
					var parsed = this.bin.parse();
					var notif = parsed as Notification;
					if (notif != null) {
						this.notification(notif);
					}
				} catch (GLib.Error e) {
					if (e.code == GLib.IOError.WOULD_BLOCK ||
						e.code == GLib.IOError.TIMED_OUT) {
						this.mutex.unlock();
						return true;
					}
					GLib.warning("%s", e.message);
					this.watch_id = 0;
					this.watching = false;
					this.connected = false;
					this.fd = -1;
					var tls = this.connection;
					this.connection = null;
					this.socket = null;
					this.mutex.unlock();
					if (tls != null) {
						try {
							tls.close();
						} catch (GLib.Error close_error) {
							GLib.warning("%s", close_error.message);
						}
					}
					this.closed();
					return false;
				}
				this.mutex.unlock();
				return true;
			});
		}
	}
}
