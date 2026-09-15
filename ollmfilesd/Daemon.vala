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

namespace OLLMfilesd
{
	/** Server {@code Daemon.*} — {@code hello} and {@code shutdown}. */
	public class Daemon : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Daemon", typeof(Daemon));
			OLLMrpc.Request.add_class(
				"RPC-Daemon", typeof(Daemon),
				"hello", "is",
				"shutdown", "",
				"request_registration", ""
			);
		}

		public OllmfilesdApplication app { get; construct; }

		public Daemon(OllmfilesdApplication app)
		{
			GLib.Object(app: app);
		}

		public int protocol { get; set; default = 1; }
		public string server { get; set; default = "ollmfilesd"; }
		public bool ready { get; set; default = true; }

		public void hello(OLLMrpc.Request request, int protocol, string client)
		{
			if (protocol > 0) {
				this.protocol = protocol;
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", this)
			});
		}

		public void shutdown(OLLMrpc.Request request)
		{
			this.ready = false;
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
			this.app.quit();
		}

		/**
		 * Record this connection's client cert as pending registration.
		 *
		 * Duplicate fingerprint (pending or registered) is ignored.
		 * Max three pending rows per IP; older-than-24h pending rows pruned first.
		 *
		 * @param request inbound RPC (connection must be {@link OLLMrpc.Transport.HttpReply})
		 */
		public void request_registration(OLLMrpc.Request request)
		{
			var reply = request.connection as OLLMrpc.Transport.HttpReply;
			if (reply == null) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
						"HTTPS registration only"
					)
				});
				return;
			}
			if (reply.cert_fingerprint == "") {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
						"client certificate required"
					)
				});
				return;
			}
			var db = this.app.project_manager.db;
			var cutoff = new GLib.DateTime.now_utc().to_unix() - (24 * 60 * 60);
			var errmsg = "";
			db.db.exec(
				"DELETE FROM client_cert WHERE status = 'pending' AND created < %lld".printf(cutoff),
				null, out errmsg);
			var existing = new Gee.ArrayList<ClientCert>();
			ClientCert.query(db).select(
				"WHERE fingerprint = '%s'".printf(
					reply.cert_fingerprint.replace("'", "''")),
				existing);
			if (existing.size > 0) {
				request.reply(new OLLMrpc.Response() {
					msg = "ok"
				});
				return;
			}
			var by_ip = new Gee.ArrayList<ClientCert>();
			ClientCert.query(db).select(
				"WHERE status = 'pending' AND ip = '%s'".printf(
					reply.client_ip.replace("'", "''")),
				by_ip);
			if (by_ip.size >= 3) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
						"too many pending registrations for this IP"
					)
				});
				return;
			}
			var row = new ClientCert() {
				fingerprint = reply.cert_fingerprint,
				status = "pending",
				ip = reply.client_ip,
				created = new GLib.DateTime.now_utc().to_unix()
			};
			ClientCert.query(db).insert(row);
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
		}

		public override void bin_write_prop(
			OLLMrpc.Bin.Stream ctx,
			GLib.ParamSpec prop
		) throws GLib.Error
		{
			if (prop.name == "app") {
				return;
			}
			bin_default_write_prop(ctx, prop);
		}

		public override void bin_read_prop(
			OLLMrpc.Bin.Stream ctx,
			GLib.ParamSpec prop,
			uint8 type_byte
		) throws GLib.Error
		{
			if (prop.name == "app") {
				return;
			}
			bin_default_read_prop(ctx, prop, type_byte);
		}
	}
}
