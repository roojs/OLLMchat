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
	 * Client TLS certificate registration row (pending or registered).
	 *
	 * Keyed by SHA-256 fingerprint. ''ip'' is stored only while
	 * ''status'' is ''pending'' (rate-limit bucket); cleared on approve
	 * in Phase 2.
	 *
	 * == Example ==
	 *
	 * {{{
	 * ClientCert.init_db(db);
	 * var rows = new Gee.ArrayList<ClientCert>();
	 * ClientCert.query(db).select("WHERE status = 'pending'", rows);
	 * }}}
	 */
	public class ClientCert : GLib.Object
	{
		public int64 id { get; set; default = 0; }
		public string fingerprint { get; set; default = ""; }
		public string status { get; set; default = ""; }
		public string ip { get; set; default = ""; }
		public int64 created { get; set; default = 0; }

		public static SQ.Query<ClientCert> query(SQ.Database db)
		{
			return new SQ.Query<ClientCert>(db, "client_cert");
		}

		/**
		 * Create ''client_cert'' and prune pending rows older than 24 h.
		 *
		 * @param db daemon ''files.sqlite''
		 */
		public static void init_db(SQ.Database db)
		{
			var errmsg = "";
			var create = "CREATE TABLE IF NOT EXISTS client_cert (" +
				"id INTEGER PRIMARY KEY, " +
				"fingerprint TEXT NOT NULL UNIQUE, " +
				"status TEXT NOT NULL DEFAULT '', " +
				"ip TEXT NOT NULL DEFAULT '', " +
				"created INT64 NOT NULL DEFAULT 0" +
				");";
			if (Sqlite.OK != db.db.exec(create, null, out errmsg)) {
				GLib.warning("Failed to create client_cert table: %s", db.db.errmsg());
			}
			var cutoff = new GLib.DateTime.now_utc().to_unix() - (24 * 60 * 60);
			if (Sqlite.OK != db.db.exec(
				"DELETE FROM client_cert WHERE status = 'pending' AND created < %lld".printf(cutoff),
				null, out errmsg)) {
				GLib.warning("Failed to prune client_cert: %s", db.db.errmsg());
			}
		}
	}
}
