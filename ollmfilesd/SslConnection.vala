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
	 * Bin connection on the local network SSL server.
	 *
	 * {@link allow_request} matches {@link Https.allow_rpc}.
	 * {@link SslListen} constructs one after the TLS handshake.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var rpc = new OLLMfilesd.SslConnection(conn, app) {
	 *     io = tls,
	 *     cert_fingerprint = fingerprint
	 * };
	 * rpc.start();
	 * }}}
	 */
	public class SslConnection : OLLMrpc.Transport.Connection
	{
		public OllmfilesdApplication app { get; construct; }

		public SslConnection(GLib.SocketConnection stream, OllmfilesdApplication app)
		{
			GLib.Object(stream: stream, app: app);
		}

		/**
		 * Same gate as {@link Https.allow_rpc} for bin RPC.
		 *
		 * Unknown certs may only call
		 * ''RPC-ClientCert.request_registration''.
		 *
		 * @param request inbound RPC
		 * @return true when the method may run
		 */
		public override bool allow_request(OLLMrpc.Request request)
		{
			switch (request.method) {
				case "RPC-ClientCert.pending_cert":
				case "RPC-ClientCert.client_cert":
					this.reply(request, new OLLMrpc.Response() {
						error = new OLLMrpc.Error(
							(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "local admin only")
					});
					return false;
			}
			if (request.method == "RPC-ClientCert.request_registration") {
				return true;
			}
			if (this.cert_fingerprint == "") {
				this.reply(request, new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "client certificate required")
				});
				return false;
			}
			var rows = new Gee.ArrayList<ClientCert>();
			var cert_q = ClientCert.query(this.app.project_manager.db);
			var int_binds = new Gee.HashMap<string, int>();
			var text_binds = new Gee.HashMap<string, string>();
			text_binds.set("fingerprint", this.cert_fingerprint);
			cert_q.selectWhere(
				"WHERE fingerprint = $fingerprint AND status = 1",
				int_binds, text_binds, rows);
			if (rows.size > 0) {
				return true;
			}
			this.reply(request, new OLLMrpc.Response() {
				error = new OLLMrpc.Error(
					(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "certificate not registered")
			});
			return false;
		}
	}
}
