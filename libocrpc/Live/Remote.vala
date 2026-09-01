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

namespace OLLMrpc.Live
{
	/**
	 * Process-wide handler for live-handle refcount RPCs.
	 *
	 * Uses {@link Request.connection} so each peer has its own lease table.
	 * Lease id is {@link Request.lease_id}. Handler wiring is
	 * {@link Request.register_live} at server boot, not a method on this class.
	 *
	 * == Example ==
	 *
	 * {{{
	 * OLLMrpc.Live.Remote.rpc_register();
	 * OLLMrpc.Request.register_live("RPC-Live-Remote", new OLLMrpc.Live.Remote());
	 * var req = new OLLMrpc.Request() {
	 *     method = "RPC-Live-Remote.rpc_unref",
	 *     lease_id = handle,
	 *     connection = connection
	 * };
	 * req.dispatch();
	 * }}}
	 */
	public class Remote : GLib.Object
	{
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"RPC-Live-Remote", typeof(Remote),
				"rpc_ref", "",
				"rpc_unref", ""
			);
		}

		/**
		 * ''Live.Remote.rpc_ref'' — extra client ref on a
		 * leased object.
		 *
		 * @param request inbound RPC
		 */
		public void rpc_ref(Request request)
		{
			if (!request.connection.live_handles) {
				GLib.error("Remote.ref requires live_handles");
			}
			var id = (int) request.lease_id;
			if (!request.connection.leases.has_key(id)) {
				request.connection.reply_error(request, (int) RpcErrorCode.INVALID_PARAMS);
				return;
			}
			request.connection.leases.get(id).ref();
			request.connection.extras.set(id, request.connection.extras.get(id) + 1);
			request.reply(new Response());
		}

		/**
		 * ''Live.Remote.rpc_unref'' — drop a client extra, or
		 * the export hold.
		 *
		 * @param request inbound RPC
		 */
		public void rpc_unref(Request request)
		{
			if (!request.connection.live_handles) {
				GLib.error("Remote.unref requires live_handles");
			}
			var id = (int) request.lease_id;
			if (!request.connection.leases.has_key(id)) {
				request.connection.reply_error(request, (int) RpcErrorCode.INVALID_PARAMS);
				return;
			}
			if (request.connection.extras.get(id) > 0) {
				request.connection.leases.get(id).unref();
				request.connection.extras.set(id, request.connection.extras.get(id) - 1);
				request.reply(new Response());
				return;
			}
			var obj = request.connection.leases.get(id);
			if (request.connection.signal_subs.has_key(id)) {
				foreach (var name in request.connection.signal_subs.get(id).keys) {
					GLib.SignalHandler.disconnect(obj, request.connection.signal_subs.get(id).get(name).hid);
				}
				request.connection.signal_subs.unset(id);
			}
			var ptr = (uint64) (void*) obj;
			var lo = (int) ptr;
			request.connection.lease_ids.get((int) (ptr >> 32)).unset(lo);
			request.connection.leases.unset(id);
			request.connection.floors.unset(id);
			request.connection.extras.unset(id);
			request.reply(new Response());
		}
	}
}
