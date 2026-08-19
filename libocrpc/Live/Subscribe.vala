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
	 * Process-wide handler for live-handle signal subscribe.
	 *
	 * Uses {@link Request.connection} so each peer has its own
	 * {@link Transport.Connection.signal_subs} table.
	 * Wire type is {@link SubscribeParams} only. Handler wiring is
	 * {@link Request.register} at server boot, not a method on this class.
	 *
	 * == Example ==
	 *
	 * {{{
	 * OLLMrpc.Live.SubscribeParams.rpc_register();
	 * OLLMrpc.Request.register(
	 *     "RPC-Live-Subscribe", new OLLMrpc.Live.Subscribe(),
	 *     typeof(OLLMrpc.Live.SubscribeParams));
	 * var req = new OLLMrpc.Request() {
	 *     method = "RPC-Live-Subscribe.signal",
	 *     param = new OLLMrpc.Live.SubscribeParams() {
	 *         object_id = handle,
	 *         name = "notify::title"
	 *     },
	 *     connection = connection
	 * };
	 * req.dispatch();
	 * }}}
	 */
	public class Subscribe : GLib.Object
	{
		public signal void call_signal(Request request);
		public signal void call_unsubscribe(Request request);

		construct
		{
			this.call_signal.connect((request) => {
				if (!request.connection.live_handles) {
					GLib.error("Subscribe.signal requires live_handles");
				}
				var param = request.param as SubscribeParams;
				if (param == null) {
					request.connection.reply_error(request, (int) RpcErrorCode.INVALID_PARAMS);
					return;
				}
				var id = (int) param.object_id;
				if (!request.connection.leases.has_key(id)) {
					request.connection.reply_error(request, (int) RpcErrorCode.INVALID_PARAMS);
					return;
				}
				if (param.name.length == 0) {
					request.connection.reply_error(request, (int) RpcErrorCode.INVALID_PARAMS);
					return;
				}
				var subs = request.connection.signal_subs;
				if (!subs.has_key(id)) {
					subs.set(id, new Gee.HashMap<string, Subscription>());
				}
				if (subs.get(id).has_key(param.name)) {
					request.reply(new Response());
					return;
				}
				var obj = request.connection.leases.get(id);
				var subscription = new Subscription() {
					connection = request.connection,
					method = param.name,
					id = id
				};
				if (param.name.has_prefix("notify::")) {
					subscription.hid = obj.notify[param.name.substring(8)].connect((pspec) => {
						var current = GLib.Value(typeof(string));
						obj.get_property(pspec.name, ref current);
						var text = current.get_string();
						text = text != null ? text : "";
						request.connection.write(new Notification() {
							method = param.name,
							id = id,
							message = text
						});
					});
					subs.get(id).set(param.name, subscription);
					request.reply(new Response());
					return;
				}
				subscription.hid = GLib.Signal.connect_swapped(obj, param.name, (GLib.Callback) Subscription.emit, subscription);
				subs.get(id).set(param.name, subscription);
				request.reply(new Response());
			});
			this.call_unsubscribe.connect((request) => {
				if (!request.connection.live_handles) {
					GLib.error("Subscribe.unsubscribe requires live_handles");
				}
				var param = request.param as SubscribeParams;
				if (param == null) {
					request.connection.reply_error(request, (int) RpcErrorCode.INVALID_PARAMS);
					return;
				}
				var id = (int) param.object_id;
				if (!request.connection.leases.has_key(id)) {
					request.connection.reply_error(request, (int) RpcErrorCode.INVALID_PARAMS);
					return;
				}
				var subs = request.connection.signal_subs;
				if (!subs.has_key(id) || !subs.get(id).has_key(param.name)) {
					request.connection.reply_error(request, (int) RpcErrorCode.INVALID_PARAMS);
					return;
				}
				GLib.SignalHandler.disconnect(request.connection.leases.get(id), subs.get(id).get(param.name).hid);
				subs.get(id).unset(param.name);
				request.reply(new Response());
			});
		}
	}
}
