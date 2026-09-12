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

namespace OLLMrpc.Transport
{
	/**
	 * HTTP RPC session — shared bin JIT name tables, sequence, idle expiry.
	 *
	 * Many {@link HttpReply} POSTs share one session's {@link bin} tables.
	 * Leases and {@link Connection.next_handle} live on each {@link HttpReply}
	 * (per POST), not here. HTTP looks up sessions by ''X-rpc-session'' via
	 * {@link take}. Socket {@link Connection} does not use this type.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var session = OLLMrpc.Transport.Session.take("");
	 * var reply = new OLLMrpc.Transport.HttpReply(soup, msg, session);
	 * }}}
	 */
	public class Session : GLib.Object
	{
		/** Opaque session UUID (echoed on ''X-rpc-session''; empty until assigned). */
		public string id { get; set; default = ""; }

		/**
		 * Shared JIT wire-name tables ({@link Bin.Stream.client_names} /
		 * {@link Bin.Stream.server_names}). I/O streams are attached per POST
		 * on {@link HttpReply}; {@link Bin.Stream.connection} points at the
		 * active {@link HttpReply} for that POST's leases.
		 */
		public Bin.Stream bin {
			get; set; default = new Bin.Stream(null, null, true);
		}

		/**
		 * Per-session request counter. Client must send the last echoed
		 * value (or ''0'' / omit on first POST); ''-1'' resets bin + counter.
		 * Server increments on accept.
		 */
		public uint sequence { get; set; default = 0; }

		/**
		 * Monotonic µs of last {@link take} touch (idle expiry).
		 */
		public int64 last_used { get; set; default = 0; }

		internal static Gee.HashMap<string, Session> by_id;

		/** Idle TTL in seconds (default 30 minutes — see plan). */
		internal static uint idle_secs = 1800;

		/**
		 * Look up ''id'', or allocate a new session when ''id'' is empty.
		 * Purges idle sessions first; touches {@link last_used} on success.
		 *
		 * @param id client ''X-rpc-session'' value, or empty to create
		 * @return session, or null when ''id'' is non-empty and unknown/expired
		 */
		public static Session? take(string id)
		{
			if (by_id == null) {
				by_id = new Gee.HashMap<string, Session>();
			}
			var now = GLib.get_monotonic_time();
			var idle_us = (int64) idle_secs * 1000 * 1000;
			/* Horribly inefficient at large session counts (full-map scan
			 * every take). Revisit if we ever see high load. */
			var stale = new Gee.ArrayList<string>();
			foreach (var sid in by_id.keys) {
				if (now - by_id.get(sid).last_used > idle_us) {
					stale.add(sid);
				}
			}
			foreach (var sid in stale) {
				by_id.unset(sid);
			}
			if (id != "") {
				if (!by_id.has_key(id)) {
					return null;
				}
				var existing = by_id.get(id);
				existing.last_used = now;
				return existing;
			}
			var session = new Session();
			session.id = GLib.Uuid.string_random();
			session.last_used = now;
			by_id.set(session.id, session);
			return session;
		}
	}
}
