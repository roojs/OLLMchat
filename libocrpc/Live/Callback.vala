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

namespace OLLMrpc.Live
{
	/**
	 * Live-handle GI callback ids (register / unregister / reply).
	 *
	 * The process-wide handler is {@link Request.register_live} at server
	 * boot. Each id is a {@link Hook} in
	 * {@link Transport.Connection.callbacks}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * OLLMrpc.Live.Callback.rpc_register();
	 * OLLMrpc.Request.register_live(
	 *     "RPC-Live-Callback", new OLLMrpc.Live.Callback());
	 * var req = new OLLMrpc.Request() {
	 *     method = "RPC-Live-Callback.register",
	 *     connection = connection
	 * };
	 * req.dispatch();
	 * }}}
	 */
	public class Callback : GLib.Object
	{
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"RPC-Live-Callback", typeof(Callback),
				"register", "",
				"unregister", "t",
				"reply", ""
			);
		}

		/**
		 * ''RPC-Live-Callback.register'' — allocate a callback id.
		 *
		 * @param request inbound RPC
		 */
		public void register(Request request)
		{
			if (!request.connection.live_handles) {
				GLib.error("Callback.register requires live_handles");
			}
			var id = request.connection.next_handle;
			request.connection.next_handle++;
			request.connection.callbacks.set(id, new Hook() {
				connection = request.connection,
				id = id
			});
			var response = new Response();
			response.args = OLLMrpc.args("t", (uint64) id);
			request.reply(response);
		}

		/**
		 * ''RPC-Live-Callback.unregister'' — drop a callback id.
		 *
		 * Completes an in-flight trampoline wait (empty return).
		 *
		 * @param request inbound RPC
		 * @param callback_id row in {@link Transport.Connection.callbacks}
		 */
		public void unregister(Request request, uint64 callback_id)
		{
			if (!request.connection.live_handles) {
				GLib.error("Callback.unregister requires live_handles");
			}
			var id = (int) callback_id;
			if (!request.connection.callbacks.has_key(id)) {
				request.connection.reply_error(request, (int) RpcErrorCode.INVALID_PARAMS);
				return;
			}
			request.connection.callbacks.get(id).replied = true;
			request.connection.callbacks.unset(id);
			request.reply(new Response());
		}

		/**
		 * ''RPC-Live-Callback.reply'' — complete one trampoline wait.
		 *
		 * {@link Request.args}[0] is {@link Invoke.reply_id}.
		 * Later rows are the GI return (void ack has none).
		 *
		 * @param request inbound RPC
		 */
		public void reply(Request request)
		{
			if (!request.connection.live_handles) {
				GLib.error("Callback.reply requires live_handles");
			}
			if (request.args.size == 0) {
				request.connection.reply_error(request, (int) RpcErrorCode.INVALID_PARAMS);
				return;
			}
			var correlation = (int) request.args.get(0).get_uint64();
			foreach (var id in request.connection.callbacks.keys) {
				var row = request.connection.callbacks.get(id);
				if (row.reply_id != correlation) {
					continue;
				}
				row.reply_args.clear();
				for (var i = 1; i < request.args.size; i++) {
					row.reply_args.add(request.args.get(i));
				}
				row.replied = true;
				request.reply(new Response());
				return;
			}
			request.connection.reply_error(request, (int) RpcErrorCode.INVALID_PARAMS);
		}
	}
}
