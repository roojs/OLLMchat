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
	 * HTTPS RPC server with client-cert registration gate.
	 *
	 * Extends {@link OLLMrpc.Transport.HttpServer}. Unknown certs may only
	 * call {@link ClientCert.request_registration}; registered certs pass
	 * through. Call {@link listen} after construct to bind from ''filesd''
	 * settings.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var http = new OLLMfilesd.Https(app);
	 * if (http.listen()) {
	 *     // bound
	 * }
	 * }}}
	 */
	public class Https : OLLMrpc.Transport.HttpServer
	{
		public OllmfilesdApplication app { get; private set; }

		public Https(OllmfilesdApplication app)
		{
			base();
			this.app = app;
		}

		/**
		 * Mint the product-CA leaf if needed and bind per ''filesd.https''.
		 *
		 * No-op (returns ''false'') when ''filesd.enabled'' is false,
		 * ''filesd.https'' is empty, or not a valid ''host:port''. Uses
		 * {@link app} for ''config.filesd'' and ''data_dir''.
		 *
		 * @return true when the HTTPS listener is up
		 */
		public bool listen()
		{
			var filesd = this.app.config.filesd;
			if (!filesd.enabled) {
				return false;
			}
			if (filesd.https == "") {
				return false;
			}
			var colon = filesd.https.last_index_of(":");
			if (colon <= 0) {
				GLib.warning("filesd.https must be host:port, got %s", filesd.https);
				return false;
			}
			var host = filesd.https.substring(0, colon);
			var port = 0;
			if (host == ""
				|| !int.try_parse(filesd.https.substring(colon + 1), out port)
				|| port <= 0) {
				GLib.warning("filesd.https must be host:port, got %s", filesd.https);
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
			this.host = host;
			this.port = (uint) port;
			this.proxy = filesd.proxy;
			var cert = new OLLMrpc.Transport.Cert() {
				dir = tls_dir,
				ca_pem_path = ca_pem,
				ca_key_path = ca_key,
				server_san = true,
			};
			cert.ensure();
			this.tls_certificate = cert.certificate;
			if (!this.start()) {
				GLib.error("failed to start HTTPS RPC listener");
			}
			GLib.debug("HTTPS listening on %s:%u proxy=%s",	host, this.port, 
				filesd.proxy ? "true" : "false");
			var cert_q = ClientCert.query(this.app.project_manager.db);
			var banned = new Gee.ArrayList<ClientCert>();
			var int_binds = new Gee.HashMap<string, int>();
			int_binds["status"] = -1;
			cert_q.selectWhere("WHERE status = $status ORDER BY created DESC", int_binds, null, banned);
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
		 * Gate HTTPS RPC: admin wires blocked; unknown certs may only
		 * register; approved certs pass.
		 *
		 * @param reply HTTPS connection (client IP + cert fingerprint)
		 * @param request inbound RPC
		 * @return true when the method may run
		 */
		protected override bool allow_rpc(
			OLLMrpc.Transport.HttpReply reply, OLLMrpc.Request request)
		{
			switch (request.method) {
				case "RPC-ClientCert.pending_cert":
				case "RPC-ClientCert.client_cert":
					reply.write(new OLLMrpc.Response() {
						id = request.id,
						error = new OLLMrpc.Error(
							(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "local admin only")
					});
					return false;
			}
			if (request.method == "RPC-ClientCert.request_registration") {
				return true;
			}
			if (reply.cert_fingerprint == "") {
				reply.write(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error((int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, 
						"client certificate required")
				});
				return false;
			}
			var rows = new Gee.ArrayList<ClientCert>();
			var cert_q = ClientCert.query(this.app.project_manager.db);
			var int_binds = new Gee.HashMap<string, int>();
			var text_binds = new Gee.HashMap<string, string>();
			int_binds["status"] = 1;
			text_binds["fingerprint"] = reply.cert_fingerprint;
			cert_q.selectWhere("WHERE fingerprint = $fingerprint AND status = $status",
				int_binds, text_binds, rows);
			if (rows.size > 0) {
				return true;
			}
			reply.write(new OLLMrpc.Response() {
				id = request.id,
				error = new OLLMrpc.Error((int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, 
					"certificate not registered")
			});
			return false;
		}
	}
}
