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
	 * Client TLS certificate row + ''RPC-ClientCert'' handler.
	 *
	 * ''status'': ''0'' pending, ''1'' approved, ''-1'' IP ban, ''-2'' rejected
	 * (kept for audit). Three ''-2'' rows from one IP within 30 days auto-bans
	 * that IP for 30 days (''created'' on ban rows).
	 * RPC singleton from {@link for_rpc}; plain rows from {@link query} have
	 * no ''app''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * ClientCert.init_db(db);
	 * OLLMrpc.Request.register("RPC-ClientCert", new ClientCert.for_rpc(app));
	 * }}}
	 */
	public class ClientCert : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("ClientCert", typeof(ClientCert));
			OLLMrpc.Request.add_class(
				"RPC-ClientCert", typeof(ClientCert),
				"request_registration", "s",
				"pending_cert", "",
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
		 * Wire dispatch singleton for ''RPC-ClientCert''.
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

		/**
		 * Record this connection's client cert as pending registration.
		 *
		 * @param request inbound RPC (connection must be
		 * {@link OLLMrpc.Transport.HttpReply})
		 * @param requester best-effort device string sent by the client
		 */
		public void request_registration(OLLMrpc.Request request, string requester)
		{
			var reply = request.connection as OLLMrpc.Transport.HttpReply;
			if (reply == null) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "HTTPS registration only")
				});
				return;
			}
			if (reply.cert_fingerprint == "") {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "client certificate required")
				});
				return;
			}
			var db = this.app.project_manager.db;
			var q = ClientCert.query(db);
			var int_binds = new Gee.HashMap<string, int>();
			var text_binds = new Gee.HashMap<string, string>();
			int_binds["status"] = 0;
			int_binds["before"] = (int) (new GLib.DateTime.now_utc().to_unix() - (24 * 60 * 60));
			q.deleteWhere("WHERE status = $status AND created < $before", int_binds, null);
			var banned_ip = new Gee.ArrayList<ClientCert>();
			int_binds["status"] = -1;
			text_binds["ip"] = reply.client_ip;
			q.selectWhere("WHERE status = $status AND ip = $ip", int_binds, text_binds, banned_ip);
			if (banned_ip.size > 0) {
				var ban_cutoff = new GLib.DateTime.now_utc().to_unix() - (30 * 24 * 60 * 60);
				if (banned_ip.get(0).created < ban_cutoff) {
					q.deleteId(banned_ip.get(0).id);
				} else {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error(
							(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "IP banned")
					});
					return;
				}
			}
			var existing = new Gee.ArrayList<ClientCert>();
			int_binds.clear();
			text_binds.clear();
			text_binds["fingerprint"] = reply.cert_fingerprint;
			q.selectWhere("WHERE fingerprint = $fingerprint", int_binds, text_binds, existing);
			if (existing.size > 0) {
				var row = existing.get(0);
				if (row.status != 0) {
					request.reply(new OLLMrpc.Response() {
						msg = "ok"
					});
					return;
				}
				row.created = new GLib.DateTime.now_utc().to_unix();
				row.requester = requester;
				q.updateById(row);
				this.app.broadcast(new OLLMrpc.Notification() {
					method = "event.client_cert",
					object_type = "ClientCert",
					action = "request"
				});
				request.reply(new OLLMrpc.Response() {
					msg = "ok"
				});
				return;
			}
			var by_ip = new Gee.ArrayList<ClientCert>();
			int_binds["status"] = 0;
			text_binds["ip"] = reply.client_ip;
			q.selectWhere("WHERE status = $status AND ip = $ip", int_binds, text_binds, by_ip);
			if (by_ip.size >= 3) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
						"too many pending registrations for this IP")
				});
				return;
			}
			var row = new ClientCert() {
				fingerprint = reply.cert_fingerprint,
				status = 0,
				ip = reply.client_ip,
				created = new GLib.DateTime.now_utc().to_unix(),
				requester = requester
			};
			q.insert(row);
			this.app.broadcast(new OLLMrpc.Notification() {
				method = "event.client_cert",
				object_type = "ClientCert",
				action = "request"
			});
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
		}

		/**
		 * Newest pending client cert for the preferences banner.
		 *
		 * @param request inbound RPC (local Unix / bin)
		 */
		public void pending_cert(OLLMrpc.Request request)
		{
			var q = ClientCert.query(this.app.project_manager.db);
			var rows = new Gee.ArrayList<ClientCert>();
			var int_binds = new Gee.HashMap<string, int>();
			int_binds["status"] = 0;
			q.selectWhere("WHERE status = $status ORDER BY created DESC LIMIT 1", int_binds, null, rows);
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows.size > 0 ? rows.get(0) : new ClientCert()),
				msg = "ok"
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
		 * ''action'': ''accept'' / ''reject'' / ''ban'' / ''remove''.
		 * Retval ''true'' on success, ''false'' if not found / unknown action.
		 *
		 * @param request inbound RPC
		 * @param action op indicator
		 * @param id ''client_cert.id''
		 */
		public void client_cert(OLLMrpc.Request request, string action, int64 id)
		{
			var q = ClientCert.query(this.app.project_manager.db);
			var int_binds = new Gee.HashMap<string, int>();
			var text_binds = new Gee.HashMap<string, string>();
			switch (action) {
				case "accept":
					var accept_rows = new Gee.ArrayList<ClientCert>();
					int_binds["id"] = (int) id;
					int_binds["status"] = 0;
					q.selectWhere("WHERE id = $id AND status = $status", int_binds, null, accept_rows);
					if (accept_rows.size == 0) {
						request.reply(new OLLMrpc.Response() {
							retval = OLLMrpc.val("b", false),
							msg = "ok"
						});
						return;
					}
					accept_rows.get(0).status = 1;
					accept_rows.get(0).ip = "";
					q.updateById(accept_rows.get(0));
					request.reply(new OLLMrpc.Response() {
						retval = OLLMrpc.val("b", true),
						msg = "ok"
					});
					return;

				case "reject":
					var reject_rows = new Gee.ArrayList<ClientCert>();
					int_binds["id"] = (int) id;
					int_binds["status"] = 0;
					q.selectWhere("WHERE id = $id AND status = $status", int_binds, null, reject_rows);
					if (reject_rows.size == 0) {
						request.reply(new OLLMrpc.Response() {
							retval = OLLMrpc.val("b", false),
							msg = "ok"
						});
						return;
					}
					var rejected = reject_rows.get(0);
					var reject_now = new GLib.DateTime.now_utc().to_unix();
					rejected.status = -2;
					rejected.created = reject_now;
					q.updateById(rejected);
					var recent_rejects = new Gee.ArrayList<ClientCert>();
					text_binds["ip"] = rejected.ip;
					int_binds["since"] = (int) (reject_now - (30 * 24 * 60 * 60));
					q.selectWhere("WHERE status = -2 AND ip = $ip AND created > $since",
						int_binds, text_binds, recent_rejects);
					if (recent_rejects.size < 3 || rejected.ip == "") {
						request.reply(new OLLMrpc.Response() {
							retval = OLLMrpc.val("b", true),
							msg = "ok"
						});
						return;
					}
					var auto_ban = new Gee.ArrayList<ClientCert>();
					int_binds["status"] = -1;
					q.selectWhere("WHERE status = $status AND ip = $ip", int_binds, text_binds, auto_ban);
					if (auto_ban.size == 0) {
						q.insert(new ClientCert() {
							fingerprint = "ip:" + rejected.ip,
							status = -1,
							ip = rejected.ip,
							created = reject_now
						});
					} else {
						auto_ban.get(0).created = reject_now;
						auto_ban.get(0).fingerprint = "ip:" + rejected.ip;
						q.updateById(auto_ban.get(0));
					}
					if (this.app.https_listen != null
						&& !this.app.https_listen.banned_ips.contains(rejected.ip)) {
						this.app.https_listen.banned_ips.add(rejected.ip);
					}
					GLib.debug("auto-banned IP %s after %d rejects in 30 days",
						rejected.ip, recent_rejects.size);
					request.reply(new OLLMrpc.Response() {
						retval = OLLMrpc.val("b", true),
						msg = "ok"
					});
					return;

				case "ban":
					var ban_rows = new Gee.ArrayList<ClientCert>();
					int_binds["id"] = (int) id;
					int_binds["status"] = 0;
					q.selectWhere("WHERE id = $id AND status = $status", int_binds, null, ban_rows);
					if (ban_rows.size == 0) {
						request.reply(new OLLMrpc.Response() {
							retval = OLLMrpc.val("b", false),
							msg = "ok"
						});
						return;
					}
					ban_rows.get(0).status = -1;
					ban_rows.get(0).fingerprint = "ip:" + ban_rows.get(0).ip;
					ban_rows.get(0).created = new GLib.DateTime.now_utc().to_unix();
					q.updateById(ban_rows.get(0));
					if (this.app.https_listen != null && ban_rows.get(0).ip != ""
						&& !this.app.https_listen.banned_ips.contains(ban_rows.get(0).ip)) {
						this.app.https_listen.banned_ips.add(ban_rows.get(0).ip);
					}
					request.reply(new OLLMrpc.Response() {
						retval = OLLMrpc.val("b", true),
						msg = "ok"
					});
					return;

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
