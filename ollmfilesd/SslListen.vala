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

namespace OLLMfilesd
{
	/**
	 * TLS bin listener for the local network SSL server.
	 *
	 * Binds ''filesd.socket'' when ''ssl_enabled'' is on and the
	 * address is a non-loopback ''host:port'' in 1024–65535.
	 * Otherwise {@link listen} returns false and the daemon stays
	 * up on Unix and HTTPS. Same product CA and {@link ClientCert}
	 * rows as {@link Https}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var ssl = new OLLMfilesd.SslListen(app);
	 * if (ssl.listen()) {
	 *     // bound
	 * }
	 * }}}
	 */
	public class SslListen : GLib.Object
	{
		public OllmfilesdApplication app { get; private set; }
		public Gee.ArrayList<string> banned_ips {
			get; set; default = new Gee.ArrayList<string>();
		}

		private GLib.SocketService service {
			get; set; default = new GLib.SocketService();
		}
		private bool listening = false;
		private Gee.ArrayList<SslConnection> connections {
			get; set; default = new Gee.ArrayList<SslConnection>();
		}

		public SslListen(OllmfilesdApplication app)
		{
			this.app = app;
		}

		/**
		 * Bind the TLS bin socket from ''filesd.socket''.
		 *
		 * Returns false when SSL is off or the address is empty,
		 * loopback, or outside 1024–65535. Does not stop the
		 * daemon. Bind failure logs a warning and returns false.
		 *
		 * @return true when the SSL listener is up
		 */
		public bool listen()
		{
			if (this.listening) {
				return true;
			}
			var filesd = this.app.config.filesd;
			if (!filesd.ssl_enabled) {
				return false;
			}
			var socket = filesd.socket;
			var colon = socket.last_index_of(":");
			var host = "";
			var port = 0;
			if (colon > 0) {
				host = socket.substring(0, colon);
				int.try_parse(socket.substring(colon + 1), out port);
			}
			if (socket == "" || colon <= 0 || host == ""
				|| host == "127.0.0.1" || host == "localhost" || host == "::1"
				|| port < 1024 || port > 65535) {
				return false;
			}
			var tls_dir = GLib.Path.build_filename(this.app.data_dir, "tls");
			if (!GLib.FileUtils.test(tls_dir, GLib.FileTest.IS_DIR)) {
				GLib.DirUtils.create_with_parents(tls_dir, 0700);
			}
			var ca_pem = GLib.Path.build_filename(tls_dir, "ollmrpc-ca.pem");
			var ca_key = GLib.Path.build_filename(tls_dir, "ollmrpc-ca-key.pem");
			if (!GLib.FileUtils.test(ca_pem, GLib.FileTest.EXISTS)) {
				try {
					GLib.FileUtils.set_contents(ca_pem,
						(string) GLib.resources_lookup_data("/ollmrpc/ollmrpc-ca.pem",
							GLib.ResourceLookupFlags.NONE).get_data());
				} catch (GLib.Error e) {
					GLib.error("extract CA PEM: %s", e.message);
				}
			}
			if (!GLib.FileUtils.test(ca_key, GLib.FileTest.EXISTS)) {
				try {
					GLib.FileUtils.set_contents(ca_key,
						(string) GLib.resources_lookup_data("/ollmrpc/ollmrpc-ca-key.pem",
							GLib.ResourceLookupFlags.NONE).get_data());
				} catch (GLib.Error e) {
					GLib.error("extract CA key: %s", e.message);
				}
			}
			var cert = new OLLMrpc.Transport.Cert() {
				dir = tls_dir,
				ca_pem_path = ca_pem,
				ca_key_path = ca_key,
				server_san = true,
			};
			cert.ensure();
			var server_cert = cert.certificate;
			var parsed = new GLib.InetSocketAddress.from_string(host, (uint16) port);
			if (parsed == null) {
				return false;
			}
			this.service = new GLib.SocketService();
			var effective = (GLib.SocketAddress) parsed;
			try {
				this.service.add_address(
					effective,
					GLib.SocketType.STREAM,
					GLib.SocketProtocol.TCP,
					null,
					out effective
				);
			} catch (GLib.Error e) {
				GLib.warning("failed to bind SSL listener %s:%u: %s",
					host, (uint) port, e.message);
				return false;
			}
			this.service.incoming.connect((conn) => {
				var ip = "";
				try {
					var remote = conn.get_remote_address() as GLib.InetSocketAddress;
					if (remote != null) {
						ip = remote.get_address().to_string();
					}
				} catch (GLib.Error e) {
				}
				if (ip != "" && this.banned_ips.contains(ip)) {
					GLib.debug("dropping banned client IP %s", ip);
					try {
						conn.close();
					} catch (GLib.Error e) {
					}
					return true;
				}
				GLib.TlsServerConnection tls;
				try {
					tls = GLib.TlsServerConnection.@new(conn, server_cert);
				} catch (GLib.Error e) {
					GLib.warning("ssl accept failed: %s", e.message);
					return true;
				}
				tls.authentication_mode = GLib.TlsAuthenticationMode.REQUESTED;
				tls.accept_certificate.connect((peer_cert, errors) => {
					return true;
				});
				tls.handshake_async.begin(GLib.Priority.DEFAULT, null, (obj, res) => {
					try {
						tls.handshake_async.end(res);
					} catch (GLib.Error e) {
						GLib.warning("ssl handshake failed: %s", e.message);
						return;
					}
					var fingerprint = "";
					var peer = tls.get_peer_certificate();
					if (peer != null) {
						fingerprint = GLib.Checksum.compute_for_data(
							GLib.ChecksumType.SHA256, peer.certificate.data);
					}
					var rpc = new SslConnection(conn, this.app) {
						io = tls,
						cert_fingerprint = fingerprint
					};
					rpc.start();
					this.connections.add(rpc);
				});
				return true;
			});
			this.service.start();
			this.listening = true;
			GLib.debug("SSL listening on %s:%u", host, (uint) port);
			var cert_q = ClientCert.query(this.app.project_manager.db);
			var banned = new Gee.ArrayList<ClientCert>();
			cert_q.select("WHERE status = -1 ORDER BY created DESC", banned);
			var ban_cutoff = new GLib.DateTime.now_utc().to_unix() - (30 * 24 * 60 * 60);
			foreach (var row in banned) {
				if (row.created < ban_cutoff) {
					cert_q.deleteId(row.id);
					continue;
				}
				if (row.ip != "" && !this.banned_ips.contains(row.ip)) {
					this.banned_ips.add(row.ip);
				}
			}
			return true;
		}

		/**
		 * Unbind the socket and stop each bin connection.
		 *
		 * No-op when {@link listen} did not bind.
		 */
		public void stop()
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
