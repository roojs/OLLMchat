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
	 * returns that {@link OLLMrpc.Response}.
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
	 * var link = new OLLMrpc.Transport.TlsClient(host, port) {
	 *     accept_any = true
	 * };
	 * var response = link.call(request);
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

		private bool connected = false;
		private int fd = -1;
		/* Keeps the handshake alive. The bin streams borrow the
		 * TLS input stream; they do not own the connection. */
		private GLib.SocketConnection? socket = null;
		private GLib.TlsClientConnection? link = null;
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
			this.link = tls;
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
			this.bin.write(request);
			var reply_wait = GLib.get_monotonic_time() + 10 * 1000000;
			while (true) {
				try {
					var parsed = this.bin.parse();
					if (!(parsed is Response)) {
						continue;
					}
					return (Response) parsed;
				} catch (GLib.IOError e) {
					if (e.code != GLib.IOError.WOULD_BLOCK ||
						GLib.get_monotonic_time() >= reply_wait) {
						throw e;
					}
					var reply_poll = GLib.PollFD();
					reply_poll.fd = this.fd;
					reply_poll.events = GLib.IOCondition.IN;
					GLib.poll(new GLib.PollFD[] { reply_poll }, 200);
				}
			}
		}
	}
}
