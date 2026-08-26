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
	 * Process-wide handler for live-handle signal subscribe.
	 *
	 * Uses {@link Request.connection} so each peer has its own
	 * {@link Transport.Connection.signal_subs} table.
	 * Lease id is {@link Request.lease_id}; signal name is
	 * the ''s'' argument. Handler wiring is {@link Request.register_live}
	 * at server boot, not a method on this class.
	 *
	 * == Example ==
	 *
	 * {{{
	 * OLLMrpc.Live.Subscribe.rpc_register();
	 * OLLMrpc.Request.register_live("RPC-Live-Subscribe", new OLLMrpc.Live.Subscribe());
	 * var req = new OLLMrpc.Request() {
	 *     method = "RPC-Live-Subscribe.rpc_signal",
	 *     lease_id = handle,
	 *     args = OLLMrpc.args("s", "notify::title"),
	 *     connection = connection
	 * };
	 * req.dispatch();
	 * }}}
	 */
	public class Subscribe : GLib.Object
	{
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"RPC-Live-Subscribe", typeof(Subscribe),
				"rpc_signal", "s",
				"unsubscribe", "s",
				null
			);
		}

		/**
		 * ''Live.Subscribe.rpc_signal'' — subscribe to a named
		 * signal on the lease.
		 *
		 * @param request inbound RPC
		 * @param name signal or ''notify::'' property
		 */
		public void rpc_signal(Request request, string name)
		{
			if (!request.connection.live_handles) {
				GLib.error("Subscribe.signal requires live_handles");
			}
			var id = (int) request.lease_id;
			if (!request.connection.leases.has_key(id)) {
				request.connection.reply_error(request, (int) RpcErrorCode.INVALID_PARAMS);
				return;
			}
			if (name.length == 0) {
				request.connection.reply_error(request, (int) RpcErrorCode.INVALID_PARAMS);
				return;
			}
			var subs = request.connection.signal_subs;
			if (!subs.has_key(id)) {
				subs.set(id, new Gee.HashMap<string, Subscription>());
			}
			if (subs.get(id).has_key(name)) {
				request.reply(new Response());
				return;
			}
			var obj = request.connection.leases.get(id);
			var subscription = new Subscription() {
				connection = request.connection,
				method = name,
				id = id
			};
			if (name.has_prefix("notify::")) {
				subscription.hid = obj.notify[name.substring(8)].connect((pspec) => {
					var current = GLib.Value(typeof(string));
					obj.get_property(pspec.name, ref current);
					var text = current.get_string();
					text = text != null ? text : "";
					request.connection.write(new Notification() {
						method = name,
						id = id,
						message = text
					});
				});
				subs.get(id).set(name, subscription);
				request.reply(new Response());
				return;
			}
			subscription.hid = GLib.Signal.connect_swapped(obj, name, (GLib.Callback) Subscription.emit, subscription);
			subs.get(id).set(name, subscription);
			request.reply(new Response());
		}

		/**
		 * ''Live.Subscribe.unsubscribe'' — drop a named
		 * subscription on the lease.
		 *
		 * @param request inbound RPC
		 * @param name signal or ''notify::'' property
		 */
		public void unsubscribe(Request request, string name)
		{
			if (!request.connection.live_handles) {
				GLib.error("Subscribe.unsubscribe requires live_handles");
			}
			var id = (int) request.lease_id;
			if (!request.connection.leases.has_key(id)) {
				request.connection.reply_error(request, (int) RpcErrorCode.INVALID_PARAMS);
				return;
			}
			var subs = request.connection.signal_subs;
			if (!subs.has_key(id) || !subs.get(id).has_key(name)) {
				request.connection.reply_error(request, (int) RpcErrorCode.INVALID_PARAMS);
				return;
			}
			GLib.SignalHandler.disconnect(request.connection.leases.get(id), subs.get(id).get(name).hid);
			subs.get(id).unset(name);
			request.reply(new Response());
		}
	}
}
