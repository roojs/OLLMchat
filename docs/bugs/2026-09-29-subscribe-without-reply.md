# Subscribe without writing a reply

**Status:** ⏳ open. gnome-shell-rpc wants to attach signal handlers while it is still inside `Helper-Actor.create`. `rpc_signal` always writes a reply, so that reply is what the client reads as the create result.

**Consumer:** [`gnome-shell-rpc` `docs/bugs/2026-09-29-rpc-call-volume.md`](../../../gnome-shell-rpc/docs/bugs/2026-09-29-rpc-call-volume.md) row 1. That bug queues the first property sets and the signal names onto one create. The server has to subscribe before it replies. It cannot call `rpc_signal` to do that.

## Problem

- **🔷** `RPC-Live-Subscribe.rpc_signal` is the only way a client subscribes. It looks up the lease, connects the closure, and `request.reply`s.
- **🔷** A create handler that calls `rpc_signal` (or a throwaway `Request` whose handler is `rpc_signal`) writes that reply on the same connection. The client’s next read is the subscribe reply, not the create lease.
- **ℹ️** `signal_subs` is already public on `Transport.Connection`. The connect body does not need a `Request`.

## ⏳ 🔷 Replace `libocrpc/Live/Subscribe.vala` `rpc_signal`

`rpc_signal` keeps the live-handles check and the one reply. The connect moves to `attach`, which returns false for a bad lease or an empty name and writes nothing.

**Replace:**

```vala
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
					var current = GLib.Value(pspec.value_type);
					obj.get_property(pspec.name, ref current);
					var helper = OLLMrpc.Bin.TypeOverride.lookup(pspec.value_type);
					var packed = new Gee.ArrayList<GLib.Value?>();
					var method_name = name;
					if (helper != null) {
						foreach (var field in helper.pack(current)) {
							packed.add(field);
						}
						method_name = helper.rpc_signal_alias(name);
					}
					if (helper == null) {
						packed.add(current);
					}
					request.connection.write(new Notification() {
						method = method_name,
						id = id,
						args = packed
					});
				});
				subs.get(id).set(name, subscription);
				request.reply(new Response());
				return;
			}
			var closure = new GLib.Closure.simple((uint) GLib.Closure.SIZE, subscription);
			closure.ref();
			closure.sink();
			closure.set_marshal((GLib.ClosureMarshal) Subscription.emit);
			closure.set_meta_marshal(subscription, (GLib.ClosureMarshal) Subscription.emit);
			subscription.hid = GLib.Signal.connect_closure(obj, name, closure, false);
			subs.get(id).set(name, subscription);
			request.reply(new Response());
		}
```

**Replace with:**

```vala
		public void rpc_signal(Request request, string name)
		{
			if (!request.connection.live_handles) {
				GLib.error("Subscribe.signal requires live_handles");
			}
			if (!Subscribe.attach(request.connection, (int) request.lease_id, name)) {
				request.connection.reply_error(request, (int) RpcErrorCode.INVALID_PARAMS);
				return;
			}
			request.reply(new Response());
		}

		/**
		 * Connect ''name'' on ''id'' for ''connection''.
		 * Already subscribed is success. Does not write a reply.
		 */
		public static bool attach(Transport.Connection connection, int id, string name)
		{
			if (!connection.leases.has_key(id) || name.length == 0) {
				return false;
			}
			var subs = connection.signal_subs;
			if (!subs.has_key(id)) {
				subs.set(id, new Gee.HashMap<string, Subscription>());
			}
			if (subs.get(id).has_key(name)) {
				return true;
			}
			var obj = connection.leases.get(id);
			var subscription = new Subscription() {
				connection = connection,
				method = name,
				id = id
			};
			if (name.has_prefix("notify::")) {
				Subscribe.attach_notify(obj, subscription, name);
				subs.get(id).set(name, subscription);
				return true;
			}
			Subscribe.attach_closure(obj, subscription, name);
			subs.get(id).set(name, subscription);
			return true;
		}

		static void attach_notify(GLib.Object obj, Subscription subscription, string name)
		{
			var id = subscription.id;
			subscription.hid = obj.notify[name.substring(8)].connect((pspec) => {
				var current = GLib.Value(pspec.value_type);
				obj.get_property(pspec.name, ref current);
				var helper = OLLMrpc.Bin.TypeOverride.lookup(pspec.value_type);
				var packed = new Gee.ArrayList<GLib.Value?>();
				var method_name = name;
				if (helper == null) {
					packed.add(current);
					subscription.connection.write(new Notification() {
						method = method_name,
						id = id,
						args = packed
					});
					return;
				}
				foreach (var field in helper.pack(current)) {
					packed.add(field);
				}
				method_name = helper.rpc_signal_alias(name);
				subscription.connection.write(new Notification() {
					method = method_name,
					id = id,
					args = packed
				});
			});
		}

		static void attach_closure(GLib.Object obj, Subscription subscription, string name)
		{
			var closure = new GLib.Closure.simple((uint) GLib.Closure.SIZE, subscription);
			closure.ref();
			closure.sink();
			closure.set_marshal((GLib.ClosureMarshal) Subscription.emit);
			closure.set_meta_marshal(subscription, (GLib.ClosureMarshal) Subscription.emit);
			subscription.hid = GLib.Signal.connect_closure(obj, name, closure, false);
		}
```

`unsubscribe` stays as it is. It is a client RPC and its reply is the unsubscribe result.

- **🚫** A second copy of the `notify::` or `connect_closure` block in gnome-shell-rpc.
- **🚫** Calling `rpc_signal` from `Helper-Actor.create`.
