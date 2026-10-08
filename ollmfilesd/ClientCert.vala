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
	 * Client TLS certificate row + ''ClientCert'' handler.
	 *
	 * ''status'' ''1'' is an approved certificate. Pairing inserts that
	 * row immediately. {@link client_cert} ''remove'' deletes it.
	 * RPC singleton from {@link for_rpc}; plain rows from {@link query} have
	 * no ''app''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * ClientCert.init_db(db);
	 * OLLMrpc.Request.register("ClientCert", new ClientCert.for_rpc(app));
	 * }}}
	 */
	public class ClientCert : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("ClientCert", typeof(ClientCert));
			OLLMrpc.Request.add_class(
				"ClientCert", typeof(ClientCert),
				"request_registration", "sss",
				"pair", "s",
				"client_cert", "sx",
				"approved_certs", ""
			);
		}

		public OllmfilesdApplication app { get; private set; }

		public int64 id { get; set; default = 0; }
		public string fingerprint { get; set; default = ""; }
		public int status { get; set; default = 0; }
		public string ip { get; set; default = ""; }
		public int64 created { get; set; default = 0; }
		public string requester { get; set; default = ""; }

		public ClientCert()
		{
			Object();
		}

		/**
		 * Wire dispatch singleton for ''ClientCert''.
		 *
		 * @param app daemon application (DB + HTTPS ban list)
		 */
		public ClientCert.for_rpc(OllmfilesdApplication app)
		{
			Object();
			this.app = app;
			ClientCert.rpc_register();
		}

		public static SQ.Query<ClientCert> query(SQ.Database db)
		{
			return new SQ.Query<ClientCert>(db, "client_cert");
		}

		/**
		 * Ensure ''client_cert'' with int ''status'', prune pending older than
		 * 24 h.
		 *
		 * If an early-build table exists with ''status TEXT'', drop and
		 * recreate (SQLite cannot ALTER column type; feature unused so no
		 * row copy).
		 *
		 * @param db daemon ''files.sqlite''
		 */
		public static void init_db(SQ.Database db)
		{
			var errmsg = "";
			var sql = "";
			db.db.exec(
				"SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'client_cert'",
				(n, values, names) => {
					if (n > 0 && values[0] != null) {
						sql = values[0];
					}
					return 0;
				},
				out errmsg
			);
			if (sql.contains("status TEXT")) {
				db.db.exec("DROP TABLE client_cert", null, out errmsg);
			}
			if (Sqlite.OK != db.db.exec(
				"CREATE TABLE IF NOT EXISTS client_cert (" +
				"id INTEGER PRIMARY KEY, " +
				"fingerprint TEXT NOT NULL UNIQUE, " +
				"status INTEGER NOT NULL DEFAULT 0, " +
				"ip TEXT NOT NULL DEFAULT '', " +
				"created INT64 NOT NULL DEFAULT 0, " +
				"requester TEXT NOT NULL DEFAULT ''" +
				");",
				null, out errmsg)) {
				GLib.warning("Failed to create client_cert table: %s", db.db.errmsg());
			}
			db.db.exec(
				"ALTER TABLE client_cert ADD COLUMN requester TEXT NOT NULL DEFAULT ''",
				null, out errmsg);
			db.db.exec("DROP TABLE IF EXISTS client_cert_reject", null, out errmsg);
			var q = ClientCert.query(db);
			var now = new GLib.DateTime.now_utc().to_unix();
			var int_binds = new Gee.HashMap<string, int>();
			int_binds["before"] = (int) (now - (24 * 60 * 60));
			int_binds["status"] = 0;
			q.deleteWhere("WHERE status = $status AND created < $before", int_binds, null);
			int_binds["status"] = -2;
			int_binds["before"] = (int) (now - (30 * 24 * 60 * 60));
			q.deleteWhere("WHERE status = $status AND created < $before", int_binds, null);
			int_binds["status"] = -1;
			q.deleteWhere("WHERE status = $status AND created < $before", int_binds, null);
		}

		[CCode (cname = "gnutls_x509_crt_set_crq", cheader_filename = "gnutls/x509.h")]
		private static extern int gnutls_x509_crt_set_crq(
			GnuTLS.X509.Certificate crt,
			GnuTLS.X509.CertificateRequest request
		);

		/**
		 * Sign ''csr'' when ''pin'' matches {@link OLLMfilesd.SslListen.pin}.
		 *
		 * The reply ''retval'' is a string array. Index 0 is the new
		 * client certificate PEM. Index 1 is the CA certificate PEM.
		 * Each later entry is a ''host:port'' for the listen choice.
		 * A wrong PIN leaves the window up and writes no row.
		 *
		 * @param request inbound RPC on the TLS bin socket
		 * @param pin six digits from the desktop dialog
		 * @param csr PEM certificate request
		 * @param requester best-effort device string
		 */
		public void request_registration(
			OLLMrpc.Request request,
			string pin,
			string csr,
			string requester
		) {
			var rpc = request.connection as SslConnection;
			if (rpc == null) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "socket registration only")
				});
				return;
			}
			var listen = this.app.ssl_listen;
			if (listen == null) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "SSL listener is off")
				});
				return;
			}
			if (pin != listen.pin) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "number rejected")
				});
				this.app.broadcast(new OLLMrpc.Notification() {
					method = "event.pair",
					action = "rejected"
				});
				return;
			}
			var init_ret = GnuTLS.global_init();
			if (init_ret < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR, "could not sign")
				});
				return;
			}
			var csr_datum = GnuTLS.Datum() {
				data = csr,
				size = csr.length
			};
			var crq = GnuTLS.X509.CertificateRequest.create();
			if (crq.import(ref csr_datum, GnuTLS.X509.CertificateFormat.PEM) < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "bad csr")
				});
				return;
			}
			var crt = GnuTLS.X509.Certificate.create();
			if (gnutls_x509_crt_set_crq(crt, crq) < 0 || crt.set_version(3) < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "bad csr")
				});
				return;
			}
			var serial = new uint8[16];
			for (var i = 0; i < serial.length; i++) {
				serial[i] = (uint8) GLib.Random.int_range(0, 256);
			}
			var now = (time_t) (GLib.get_real_time() / 1000000);
			if (crt.set_serial(serial, serial.length) < 0
				|| crt.set_activation_time(now) < 0
				|| crt.set_expiration_time(now + (time_t) (3650 * 24 * 60 * 60)) < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR, "could not sign")
				});
				return;
			}
			var tls_dir = GLib.Path.build_filename(this.app.data_dir, "tls");
			var ca_pem = "";
			var ca_key_pem = "";
			try {
				GLib.FileUtils.get_contents(
					GLib.Path.build_filename(tls_dir, "ollmrpc-ca.pem"), out ca_pem);
				GLib.FileUtils.get_contents(
					GLib.Path.build_filename(tls_dir, "ollmrpc-ca-key.pem"), out ca_key_pem);
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR, "could not sign")
				});
				return;
			}
			var ca_datum = GnuTLS.Datum() {
				data = ca_pem,
				size = ca_pem.length
			};
			var key_datum = GnuTLS.Datum() {
				data = ca_key_pem,
				size = ca_key_pem.length
			};
			var ca_crt = GnuTLS.X509.Certificate.create();
			var ca_key = GnuTLS.X509.PrivateKey.create();
			if (ca_crt.import(ref ca_datum, GnuTLS.X509.CertificateFormat.PEM) < 0
				|| ca_key.import(ref key_datum, GnuTLS.X509.CertificateFormat.PEM) < 0
				|| crt.sign2(ca_crt, ca_key, GnuTLS.DigestAlgorithm.SHA256, 0) < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR, "could not sign")
				});
				return;
			}
			var crt_len = (size_t) 0;
			crt.export(GnuTLS.X509.CertificateFormat.PEM, null, ref crt_len);
			var crt_buf = new uint8[crt_len];
			if (crt.export(GnuTLS.X509.CertificateFormat.PEM, crt_buf, ref crt_len) < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR, "could not sign")
				});
				return;
			}
			var crt_pem = (string) crt_buf;
			var fingerprint = "";
			try {
				var issued = new GLib.TlsCertificate.from_pem(crt_pem, crt_pem.length);
				fingerprint = GLib.Checksum.compute_for_data(
					GLib.ChecksumType.SHA256, issued.certificate.data);
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR, "could not sign")
				});
				return;
			}
			var q = ClientCert.query(this.app.project_manager.db);
			q.insert(new ClientCert() {
				fingerprint = fingerprint,
				status = 1,
				created = new GLib.DateTime.now_utc().to_unix(),
				requester = requester
			});
			listen.pin = "";
			var socket = this.app.config.filesd.socket;
			var colon = socket.last_index_of(":");
			var host = "";
			var port_text = "";
			if (colon > 0) {
				host = socket.substring(0, colon);
				port_text = socket.substring(colon + 1);
			}
			string[] packed = {};
			packed += crt_pem;
			packed += ca_pem;
			if (host == "0.0.0.0") {
				foreach (var ip in OLLMrpc.Transport.TcpListen.ifaces()) {
					packed += ip + ":" + port_text;
				}
			}
			if (host != "" && host != "0.0.0.0") {
				packed += host + ":" + port_text;
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("as", packed),
				msg = "ok"
			});
			this.app.broadcast(new OLLMrpc.Notification() {
				method = "event.pair",
				action = "done"
			});
		}

		/**
		 * Set {@link OLLMfilesd.SslListen.pin} from the desktop dialog.
		 *
		 * Empty ''pin'' means the handshake requires a client
		 * certificate. Unix socket only.
		 *
		 * @param request inbound RPC from the GTK app
		 * @param pin six digits, or empty to close the window
		 */
		public void pair(OLLMrpc.Request request, string pin)
		{
			var listen = this.app.ssl_listen;
			if (listen == null) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "SSL listener is off")
				});
				return;
			}
			if (!(request.connection is SslConnection)) {
				listen.pin = pin;
				request.reply(new OLLMrpc.Response() {
					msg = "ok"
				});
				return;
			}
			if (pin != listen.pin) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "number rejected")
				});
				this.app.broadcast(new OLLMrpc.Notification() {
					method = "event.pair",
					action = "rejected"
				});
				return;
			}
			listen.pin = "";
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
			this.app.broadcast(new OLLMrpc.Notification() {
				method = "event.pair",
				action = "done"
			});
		}

		/**
		 * Approved client certs for the Connections tab expanders.
		 *
		 * @param request inbound RPC (local Unix / bin)
		 */
		public void approved_certs(OLLMrpc.Request request)
		{
			var q = ClientCert.query(this.app.project_manager.db);
			var rows = new Gee.ArrayList<ClientCert>();
			var int_binds = new Gee.HashMap<string, int>();
			int_binds["status"] = 1;
			q.selectWhere("WHERE status = $status ORDER BY created DESC", int_binds, null, rows);
			var list = new Gee.ArrayList<GLib.Object>();
			foreach (var row in rows) {
				list.add(row);
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", list)
			});
		}

		/**
		 * Mutate a client-cert row (local Unix / bin).
		 *
		 * ''action'' is ''remove''. Retval ''true'' when that approved
		 * row was deleted, ''false'' otherwise.
		 *
		 * @param request inbound RPC
		 * @param action op indicator
		 * @param id ''client_cert.id''
		 */
		public void client_cert(OLLMrpc.Request request, string action, int64 id)
		{
			var q = ClientCert.query(this.app.project_manager.db);
			var int_binds = new Gee.HashMap<string, int>();
			switch (action) {
				case "remove":
					var remove_rows = new Gee.ArrayList<ClientCert>();
					int_binds["id"] = (int) id;
					int_binds["status"] = 1;
					q.selectWhere("WHERE id = $id AND status = $status", int_binds, null, remove_rows);
					if (remove_rows.size == 0) {
						request.reply(new OLLMrpc.Response() {
							retval = OLLMrpc.val("b", false),
							msg = "ok"
						});
						return;
					}
					q.deleteId(id);
					request.reply(new OLLMrpc.Response() {
						retval = OLLMrpc.val("b", true),
						msg = "ok"
					});
					return;

				default:
					request.reply(new OLLMrpc.Response() {
						retval = OLLMrpc.val("b", false),
						msg = "ok"
					});
					return;
			}
		}

		public override void bin_write_prop(
			OLLMrpc.Bin.Stream ctx, GLib.ParamSpec prop) throws GLib.Error
		{
			if (prop.name == "app") {
				return;
			}
			this.bin_default_write_prop(ctx, prop);
		}

		public override void bin_read_prop(
			OLLMrpc.Bin.Stream ctx, GLib.ParamSpec prop, uint8 type_byte
		) throws GLib.Error
		{
			if (prop.name == "app") {
				return;
			}
			this.bin_default_read_prop(ctx, prop, type_byte);
		}
	}
}
