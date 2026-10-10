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
	 * Per-subscription holder for by-name GObject connect.
	 *
	 * {@link connect} records this row in
	 * {@link Transport.Connection.signal_subs} and writes no reply.
	 * {@link emit} is the C-callable method GObject invokes for named
	 * signals. {@link hid} is the handler id for disconnect. Live GObject
	 * args and property values are exported on the connection before the
	 * notification is written.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var subscription = new OLLMrpc.Live.Subscription() {
	 *     connection = connection,
	 *     method = "closed",
	 *     id = (int) handle
	 * };
	 * subscription.connect();
	 * }}}
	 */
	public class Subscription : GLib.Object
	{
		public Transport.Connection connection { get; set; }
		public string method { get; set; default = ""; }
		public int id { get; set; default = 0; }
		public ulong hid { get; set; default = 0; }
		/**
		 * Handler bool finishes inside the emission.
		 */
		public bool blocking { get; set; default = false; }

		/**
		 * Connect ''method'' on lease ''id'' for ''connection''.
		 *
		 * Already subscribed is success. A missing lease or an empty
		 * ''method'' returns false. Writes no reply, so a create
		 * handler can connect several names and then reply once.
		 *
		 * @return false when the lease is missing or ''method'' is empty
		 */
		public bool connect()
		{
			if (!this.connection.leases.has_key(this.id) || this.method.length == 0) {
				return false;
			}
			if (!this.connection.signal_subs.has_key(this.id)) {
				this.connection.signal_subs.set(this.id, new Gee.HashMap<string, Subscription>());
			}
			if (this.connection.signal_subs.get(this.id).has_key(this.method)) {
				return true;
			}
			var obj = this.connection.leases.get(this.id);
			if (!this.method.has_prefix("notify::")) {
				var closure = new GLib.Closure.simple((uint) GLib.Closure.SIZE, this);
				closure.ref();
				closure.sink();
				closure.set_marshal((GLib.ClosureMarshal) Subscription.emit);
				closure.set_meta_marshal(this, (GLib.ClosureMarshal) Subscription.emit);
				this.hid = GLib.Signal.connect_closure(obj, this.method, closure, false);
				this.connection.signal_subs.get(this.id).set(this.method, this);
				return true;
			}
			this.hid = obj.notify[this.method.substring(8)].connect((pspec) => {
				var current = GLib.Value(pspec.value_type);
				obj.get_property(pspec.name, ref current);
				var helper = OLLMrpc.Bin.TypeOverride.lookup(pspec.value_type);
				var packed = new Gee.ArrayList<GLib.Value?>();
				packed.add(current);
				var name = this.method;
				if (helper != null) {
					packed = helper.pack(current);
					name = helper.rpc_signal_alias(this.method);
				}
				foreach (var arg in packed) {
					if (!this.connection.live_handles || !arg.type().is_a(GLib.Type.OBJECT)) {
						continue;
					}
					// object properties may hold null
					if (arg.get_object() == null || arg.get_object() is Bin.Serializable) {
						continue;
					}
					this.connection.export(arg.get_object());
				}
				this.connection.write(new Notification() {
					method = name,
					id = this.id,
					args = packed
				});
			});
			this.connection.signal_subs.get(this.id).set(this.method, this);
			return true;
		}

		/**
		 * GClosure marshal for a named GObject signal.
		 *
		 * Packs parameters after the instance into
		 * {@link Notification.args} and writes the notification. With
		 * ''live_handles'', each non-Serializable GObject arg is exported
		 * first, so objects the peer has not seen yet get a handle.
		 * {@link blocking} writes {@link Notification.reply_id} and waits
		 * for ''RPC-Live-Callback.reply'', then stores the handler bool.
		 *
		 * @param closure unused GObject slot
		 * @param return_value handler bool; null on void signals
		 * @param param_values instance then signal arguments
		 * @param invocation_hint unused GObject slot
		 * @param marshal_data the {@link Subscription}
		 */
		public static void emit(
			GLib.Closure closure,
			[CCode (type = "GValue*")] GLib.Value? return_value,
			[CCode (array_length_cname = "n_param_values", array_length_pos = 2.5, array_length_type = "guint")]
			GLib.Value[] param_values,
			void* invocation_hint,
			void* marshal_data
		) {
			var subscription = (Subscription) marshal_data;
			var packed = OLLMrpc.Bin.TypeOverride.pack_params(param_values);
			foreach (var arg in packed) {
				if (!subscription.connection.live_handles || !arg.type().is_a(GLib.Type.OBJECT)) {
					continue;
				}
				// signal emitters may pass a null object arg
				if (arg.get_object() == null || arg.get_object() is Bin.Serializable) {
					continue;
				}
				subscription.connection.export(arg.get_object());
			}
			var note = new Notification() {
				method = subscription.method,
				id = subscription.id,
				args = packed
			};
			if (!subscription.blocking || return_value == null) {
				subscription.connection.write(note);
				return;
			}
			var waiter = new OLLMrpc.Live.Hook() {
				connection = subscription.connection
			};
			waiter.id = subscription.connection.next_handle;
			subscription.connection.next_handle++;
			subscription.connection.callbacks.set(waiter.id, waiter);
			waiter.reply_id = subscription.connection.next_handle;
			note.reply_id = waiter.reply_id;
			subscription.connection.next_handle++;
			subscription.connection.write(note);
			while (!waiter.replied && subscription.connection.running) {
				subscription.connection.emit_wait_poll();
			}
			subscription.connection.callbacks.unset(waiter.id);
			return_value.set_boolean(waiter.reply_args.size > 0
				&& waiter.reply_args.get(0).type() == GLib.Type.BOOLEAN
				&& waiter.reply_args.get(0).get_boolean());
		}
	}
}
