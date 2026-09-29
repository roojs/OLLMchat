# Subscribe without writing a reply

**Status:** ✔️ applied. `Live.Subscription.connect` writes no reply. `rpc_signal` calls it and still replies. Not user-verified. gnome-shell-rpc still has to call `connect` from `Helper-Actor.create` instead of `rpc_signal`.

**Consumer:** [`gnome-shell-rpc` `docs/bugs/2026-09-29-rpc-call-volume.md`](../../../gnome-shell-rpc/docs/bugs/2026-09-29-rpc-call-volume.md) row 1. That bug queues the first property sets and the signal names onto one create. The server has to subscribe before it replies. It cannot call `rpc_signal` to do that.

## Problem

- **🔷** `RPC-Live-Subscribe.rpc_signal` is the only way a client subscribes. It looks up the lease, connects the closure, and `request.reply`s.
- **🔷** A create handler that calls `rpc_signal` (or a throwaway `Request` whose handler is `rpc_signal`) writes that reply on the same connection. The client’s next read is the subscribe reply, not the create lease.
- **ℹ️** `signal_subs` is already public on `Transport.Connection`. The connect body does not need a `Request`.
- **🔷** Static methods on `Subscribe` are rejected. `Transport.Connection` is the channel, not the subscriber.
- **🔷** The no-reply connect is an instance method on `Live.Subscription`. That object already holds the connection, the lease id, the signal name, and the handler id.
- **🚫** `Subscribe.attach`, `Subscribe.attach_notify`, and `Subscribe.attach_closure`.
- **🚫** `Transport.Connection.subscribe`.
- **🚫** A second copy of the `notify::` or `connect_closure` block in gnome-shell-rpc.
- **🚫** Calling `rpc_signal` from `Helper-Actor.create`.

## ✔️ `Live.Subscription.connect`

- **💩** Instance method `connect` on `Live.Subscription`. The caller sets `connection`, `method`, and `id`, then calls `connect`. A missing lease or an empty `method` returns false. Already subscribed returns true. A named signal connects and returns. `notify::` is the rest of the method, not a nested branch. Either path stores this row in `connection.signal_subs` and returns true. It writes no reply.
- **🔷** A create handler does that once per name, then writes the create reply itself.
- **🔷** `rpc_signal` keeps the `live_handles` check and the one reply. It builds a `Subscription` and calls `connect`.
- **🔷** `unsubscribe` stays as it is. It is a client RPC and its reply is the unsubscribe result.
- **ℹ️** `Live/Subscription.vala` is the Unix file. The Windows stub does not gain `connect`. Nothing in the shared sources calls it.
- **💩** `tests/rpc/subscribe-test.vala` calls `connect` directly and checks that nothing is written until the signal fires.

### 1. `libocrpc/Live/Subscription.vala` — `connect`

**Why:** One subscription connects itself and writes nothing.

**Where:** Class docblock example, then the method after the `hid` property and before `emit`.

**Depends on:** none.

#### Remove

```vala
	 * {@link emit} is the C-callable method GObject invokes for named
	 * signals. {@link hid} is the handler id for disconnect.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var subscription = new OLLMrpc.Live.Subscription() {
	 *     connection = connection,
	 *     method = "closed",
	 *     id = (int) handle
	 * };
	 * var closure = new GLib.Closure.simple((uint) GLib.Closure.SIZE, subscription);
	 * closure.ref();
	 * closure.sink();
	 * closure.set_marshal((GLib.ClosureMarshal) Subscription.emit);
	 * closure.set_meta_marshal(subscription, (GLib.ClosureMarshal) Subscription.emit);
	 * subscription.hid = GLib.Signal.connect_closure(obj, "closed", closure, false);
	 * }}}
```

#### Replace with

Point the example at `connect`.

```vala
	 * {@link connect} records this row in
	 * {@link Transport.Connection.signal_subs} and writes no reply.
	 * {@link emit} is the C-callable method GObject invokes for named
	 * signals. {@link hid} is the handler id for disconnect.
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
```

#### Add — after the `hid` property, before `emit`. Connect this row and write nothing.

```vala
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
				if (helper == null) {
					packed.add(current);
					this.connection.write(new Notification() {
						method = this.method,
						id = this.id,
						args = packed
					});
					return;
				}
				foreach (var field in helper.pack(current)) {
					packed.add(field);
				}
				this.connection.write(new Notification() {
					method = helper.rpc_signal_alias(this.method),
					id = this.id,
					args = packed
				});
			});
			this.connection.signal_subs.get(this.id).set(this.method, this);
			return true;
		}
```

### 2. `libocrpc/Live/Subscribe.vala` — `rpc_signal`

**Why:** The client RPC still answers. The connect is `Subscription.connect`.

**Where:** Body of `rpc_signal`, after the `live_handles` check.

**Depends on:** §1.

#### Keep

```vala
		public void rpc_signal(Request request, string name)
		{
			if (!request.connection.live_handles) {
				GLib.error("Subscribe.signal requires live_handles");
			}
```

#### Remove

```vala
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
```

#### Replace with

Build a `Subscription` and reply once.

```vala
			var subscription = new Subscription() {
				connection = request.connection,
				method = name,
				id = (int) request.lease_id
			};
			if (!subscription.connect()) {
				request.connection.reply_error(request, (int) RpcErrorCode.INVALID_PARAMS);
				return;
			}
			request.reply(new Response());
```

#### Keep

```vala
		}
```

### 3. `libocrpc/Bin/TypeOverride.vala` — `rpc_signal_alias` docblock

**Why:** The notify alias is called from `Subscription.connect`.

**Where:** Docblock of `rpc_signal_alias`, the `Called from` line.

**Depends on:** §1.

#### Remove

```vala
		 * Called from {@link OLLMrpc.Live.Subscribe.rpc_signal} with the
		 * subscribed name. The default returns that name unchanged.
```

#### Replace with

Point the docblock at `Subscription.connect`.

```vala
		 * Called from {@link OLLMrpc.Live.Subscription.connect} with the
		 * subscribed name. The default returns that name unchanged.
```

### 4. `tests/rpc/subscribe-test.vala` — direct `connect`

**Why:** `rpc_signal` still replies. This checks `connect` writes nothing until the signal fires, and that a second connect is success.

**Where:** End of `run_rpc_test`, after the `notify::stamp` checks, before the closing brace of `run_rpc_test`.

**Depends on:** §1.

#### Add — end of `run_rpc_test`, after the `notify::stamp` value check. Call `connect` with no RPC reply.

```vala
			var direct = new Capture() {
				live_handles = true
			};
			var direct_probe = new Probe();
			var direct_id = (int) direct.export(direct_probe);
			var missing = new OLLMrpc.Live.Subscription() {
				connection = direct,
				method = "closed",
				id = 0
			};
			this.check(command_line, !missing.connect(), "connect rejects a missing lease");
			var empty = new OLLMrpc.Live.Subscription() {
				connection = direct,
				method = "",
				id = direct_id
			};
			this.check(command_line, !empty.connect(), "connect rejects an empty name");
			var notify_sub = new OLLMrpc.Live.Subscription() {
				connection = direct,
				method = "notify::title",
				id = direct_id
			};
			this.check(command_line, notify_sub.connect(), "connect notify failed");
			this.check(command_line, direct.writes == 0, "connect wrote before the signal");
			var again = new OLLMrpc.Live.Subscription() {
				connection = direct,
				method = "notify::title",
				id = direct_id
			};
			this.check(command_line, again.connect(), "connect twice failed");
			direct_probe.title = "e";
			this.check(command_line, direct.writes == 1, "direct connect did not notify once");
			this.check(command_line, direct.last.method == "notify::title", "direct notify method mismatch");
			var direct_closed = new OLLMrpc.Live.Subscription() {
				connection = direct,
				method = "closed",
				id = direct_id
			};
			this.check(command_line, direct_closed.connect(), "connect closed failed");
			direct_probe.closed();
			this.check(command_line, direct.writes == 2, "direct closed did not notify");
			this.check(command_line, direct.last.method == "closed", "direct closed method mismatch");
```
