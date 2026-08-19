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
	 * Params for {@link Remote} ref / unref.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var req = new OLLMrpc.Request() {
	 *     method = "Remote.unref",
	 *     param = new OLLMrpc.Live.RemoteParams() {
	 *         object_id = handle
	 *     }
	 * };
	 * }}}
	 */
	public class RemoteParams : CallParam
	{
		public uint64 object_id { get; set; default = 0; }

		public static void rpc_register()
		{
			Bin.register("RemoteParams", typeof(RemoteParams));
		}
	}

	/**
	 * Process-wide handler for live-handle refcount RPCs.
	 *
	 * Uses {@link Request.connection} so each peer has its own lease table.
	 * Wire type is {@link RemoteParams} only. Handler wiring is
	 * {@link Request.register} at server boot, not a method on this class.
	 *
	 * == Example ==
	 *
	 * {{{
	 * OLLMrpc.Live.RemoteParams.rpc_register();
	 * OLLMrpc.Request.register(
	 *     "Remote", new OLLMrpc.Live.Remote(),
	 *     typeof(OLLMrpc.Live.RemoteParams));
	 * var req = new OLLMrpc.Request() {
	 *     method = "Remote.unref",
	 *     param = new OLLMrpc.Live.RemoteParams() {
	 *         object_id = handle
	 *     },
	 *     connection = connection
	 * };
	 * req.dispatch();
	 * }}}
	 */
	public class Remote : GLib.Object
	{
		public signal void call_ref(Request request);
		public signal void call_unref(Request request);

		construct
		{
			this.call_ref.connect((request) => {
				if (!request.connection.live_handles) {
					request.connection.reply_error(request, (int) RpcErrorCode.METHOD_NOT_FOUND);
					return;
				}
				var param = request.param as RemoteParams;
				if (param == null) {
					request.connection.reply_error(request, (int) RpcErrorCode.INVALID_PARAMS);
					return;
				}
				var id = (int) param.object_id;
				if (!request.connection.leases.has_key(id)) {
					request.connection.reply_error(request, (int) RpcErrorCode.INVALID_PARAMS);
					return;
				}
				request.connection.leases.get(id).ref();
				request.connection.extras.set(id, request.connection.extras.get(id) + 1);
				request.reply(new Response());
			});
			this.call_unref.connect((request) => {
				if (!request.connection.live_handles) {
					request.connection.reply_error(request, (int) RpcErrorCode.METHOD_NOT_FOUND);
					return;
				}
				var param = request.param as RemoteParams;
				if (param == null) {
					request.connection.reply_error(request, (int) RpcErrorCode.INVALID_PARAMS);
					return;
				}
				var id = (int) param.object_id;
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
				request.connection.lease_ids.unset(((uint64) (void*) obj).to_string(
					"%" + uint64.FORMAT_MODIFIER + "x"));
				request.connection.leases.unset(id);
				request.connection.floors.unset(id);
				request.connection.extras.unset(id);
				request.reply(new Response());
			});
		}
	}
}
