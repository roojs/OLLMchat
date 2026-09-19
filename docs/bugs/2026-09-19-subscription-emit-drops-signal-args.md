# `Live.Subscription.emit` drops GObject signal arguments

**Status:** ⏳ root cause confirmed; fix proposed — await apply approval  
**Hit:** 2026-09-19 — overview search `Meta.Laters` / `ClutterStage::before-update`  
**Component:** `libocrpc` / `OLLMrpc.Live.Subscription` + `Notification`  
**Consumer gate:** `gnome-shell-rpc/tests/call-sync-repro/subscribe-signal-args-gate` — **FAIL** 2026-09-19  
**Related:** `notify::` already copies the property string into `Notification.message` (`tests/rpc/subscribe-test.vala`). Named signals do not.

**Process:** Follow **`docs/bug-fix-process.md`** — propose → approve → apply. Do not land from the gnome-shell-rpc tree.

---

## Problem

🔷 `RPC-Live-Subscribe.rpc_signal` connects a named GObject signal and is supposed to notify the client so it can re-emit that signal on the proxy **with the same arguments**.

🔷 `notify::title` writes `Notification.message`. A named signal with parameters (`pinged("hello")`, `stopped(bool)`, `before-update(StageView, Frame)`) goes through `Subscription.emit()`, which sends only `method` + `id`.

**Expected:** after subscribe + `pinged("hello")`, the client `Notification` carries `"hello"` (and, for object/boxed args, enough to re-emit).

**Actual:** `method=pinged`, `message=""`, no argument list. Consumer cannot `g_signal_emit_by_name` with the real payload. gnome-shell-rpc must **not** Idle/Timeout/invent a Runtime flush delegate around this.

---

## Evidence

### Consumer (gnome-shell-rpc) — 2026-09-19

```bash
meson compile -C build subscribe-signal-args-gate
timeout 5 ./build/tests/call-sync-repro/subscribe-signal-args-gate
```

```
FAIL subscribe-signal-args-gate: named signal pinged("hello") did not arrive on Notification (Subscription.emit drops args).
```

### Library

`libocrpc/Live/Subscribe.vala` — `notify::` branch writes `message`. Named branch:

```vala
subscription.hid = GLib.Signal.connect_swapped(obj, name,
    (GLib.Callback) Subscription.emit, subscription);
```

`libocrpc/Live/Subscription.vala`:

```vala
public void emit()
{
    this.connection.write(new Notification() {
        method = this.method,
        id = this.id
    });
}
```

`Notification` has no `args` list. `Hook.emit(Gee.ArrayList<GLib.Value?> args)` already marshals callback parameters; subscribe does not.

`tests/rpc/subscribe-test.vala` covers `closed()` (zero args) and `notify::title` (`message`). It does not cover a named signal with a payload.

---

## Root cause

✔️ `g_signal_connect_swapped` to a `void emit()` C callback **cannot receive** the signal’s GValues. Those values are dropped. `Notification` has nowhere to put them even if they were captured.

This is not a mutter/gnome-shell-rpc later-phase bug. The wire subscribe path is missing signal marshalling.

---

## Proposed fix (library)

Intro: edits are **Remove** / **Replace with** / **Add** from the tree;
verify surrounding context before applying.

- 🔷 Named-signal subscribe packs GObject signal arguments onto
  `Notification` (same class of problem as `Hook.emit` args).
- 🔷 `notify::` keeps `message`.
- 🔷 Zero-arg signals stay `method` + `id` (empty `args` omitted on the
  wire, same as `Request.args` / `Invoke.args`).
- 💩 Property name `args` — same as `Request` / `Invoke` / `Response`.
  Wire encoding is the existing `ANY[]` block (copy `Invoke.bin_write_prop`
  / `bin_read_prop` `args` case, not a helper).
- 💩 Retarget existing `Subscription.emit` as the `GLib.ClosureMarshal`
  (no new method). Connect with `GLib.Signal.connect_closure` so GObject
  delivers the GValue array. `param_values[0]` is the instance; pack
  `[1..]`.
- 💩 `GLib.Type.OBJECT` args call `connection.export` before write so
  `Bin.StreamValue.write` finds a lease (same as `Hook.emit` packing).
- ℹ️ gnome-shell-rpc `subscribe-signal-args-gate` currently asserts
  `notif.message == "hello"`. After this, the string lives in
  `notif.args.get(0)`, and `message` stays empty. The gate must read
  `args` once this lands — do not change that tree from here.
- ℹ️ `stopped(bool)` / `before-update(StageView, Frame)` then re-emit
  from `args` on the consumer. Boxed types `StreamValue` does not
  already encode (not `GLib.Bytes`) stay a StreamValue limit, not this
  bug.

**🚫** Consumer `GLib.Idle.add` / `Timeout.add` as a compositor phase.  
**🚫** Consumer Runtime flush delegates instead of re-emitting the real
signal.  
**🚫** HTTP/JSON. **🚫** Editing libocrpc from gnome-shell-rpc.  
**🚫** Copy the first string into `Notification.message` (`notify::` only).  
**🚫** `Notification.callback_args` / `reply_id` (that is `Live.Invoke`).  
**🚫** New pack/marshal helper.  
**🚫** Invent boxed `Frame` encoding.  
**🚫** `g_signal_add_emission_hook` (process-wide; would change
unsubscribe away from `SignalHandler.disconnect`).

---

### 1. `libocrpc/Notification.vala` — `args` on the subscribe notify

**Why:** named-signal payload has nowhere to live; `Invoke.args` is the
existing `ANY[]` encoding.

**Where:** class fields after `message`; `bin_write_prop` /
`bin_read_prop` switch before `default`.

**Depends on:** none.

#### Add — after `public string message { get; set; default = ""; }`

Named-signal parameters. Empty list is omitted on the wire.

```vala
		/**
		 * Named-signal parameters (GIR order). Empty for zero-arg
		 * signals and ''notify::''.
		 */
		public Gee.ArrayList<GLib.Value?> args {
			get; set; default = new Gee.ArrayList<GLib.Value?>();
		}
```

#### Add — in `bin_write_prop`, immediately before `default:`

Same `ANY[]` write as `libocrpc/Live/Invoke.vala` `case "args"`.

```vala
				case "args":
					if (this.args.size == 0) {
						return;
					}
					ctx.write_tag(prop.name);
					ctx.out_stream.put_byte((uint8) GLib.Type.INVALID | 0x80);
					if (this.args.size < 128) {
						ctx.out_stream.put_byte((uint8) this.args.size);
					} else {
						ctx.out_stream.put_byte(
							(uint8) (0x80 | ((this.args.size >> 8) & 0x7F)));
						ctx.out_stream.put_byte((uint8) (this.args.size & 0xFF));
					}
					foreach (var val in this.args) {
						Bin.StreamValue.write(ctx, val);
					}
					return;
```

#### Add — in `bin_read_prop`, immediately before `default:`

Same `ANY[]` read as `Invoke.bin_read_prop` `case "args"`.

```vala
				case "args":
					var n = ctx.in_stream.read_byte();
					var count = n & 0x7F;
					if ((n & 0x80) != 0) {
						count = (count << 8) | ctx.in_stream.read_byte();
					}
					for (var i = 0; i < count; i++) {
						var elem = ctx.in_stream.read_byte();
						this.args.add(Bin.StreamValue.read(ctx, elem));
					}
					return;
```

---

### 2. `libocrpc/Live/Subscription.vala` — `emit` is the GClosure marshal

**Why:** `connect_swapped` → `void emit()` has no GValue slots.
`GLib.ClosureMarshal` receives the full array.

**Where:** class docblock example; replace `emit()`.

**Depends on:** §1 (`Notification.args`).

💩 `return_value` is `GValue*` and **null** on void signals. Do not use
Vala `out GLib.Value` (compiler requires an assignment; writing through
null crashes). Cast to `GLib.ClosureMarshal` at `set_meta_marshal`.

#### Remove

```vala
	 * var subscription = new OLLMrpc.Live.Subscription() {
	 *     connection = connection,
	 *     method = "closed",
	 *     id = (int) handle
	 * };
	 * subscription.hid = GLib.Signal.connect_swapped(obj, "closed",
	 *     (GLib.Callback) Subscription.emit, subscription);
```

#### Replace with

Class `== Example ==` sample: connect via a GClosure marshal.

```vala
	 * var subscription = new OLLMrpc.Live.Subscription() {
	 *     connection = connection,
	 *     method = "closed",
	 *     id = (int) handle
	 * };
	 * var closure = new GLib.Closure.simple((uint) GLib.Closure.SIZE, subscription);
	 * closure.set_meta_marshal(subscription, (GLib.ClosureMarshal) Subscription.emit);
	 * subscription.hid = GLib.Signal.connect_closure(obj, "closed", closure, false);
```

#### Remove

```vala
		public void emit()
		{
			this.connection.write(new Notification() {
				method = this.method,
				id = this.id
			});
		}
```

#### Replace with

Same method name. GClosure marshal: pack `[1..]` into `Notification.args`.

```vala
		/**
		 * GClosure marshal for a named GObject signal.
		 *
		 * Packs parameters after the instance into
		 * {@link Notification.args} and writes the notification.
		 * {@link GLib.Type.OBJECT} values are exported so
		 * {@link Bin.StreamValue.write} can send the lease.
		 *
		 * @param closure unused GObject slot
		 * @param return_value unused; null on void signals
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
			var packed = new Gee.ArrayList<GLib.Value?>();
			for (var i = 1; i < param_values.length; i++) {
				if (param_values[i].type().is_a(GLib.Type.OBJECT)
					&& param_values[i].get_object() != null) {
					subscription.connection.export(param_values[i].get_object());
				}
				var copy = GLib.Value(param_values[i].type());
				param_values[i].copy(ref copy);
				packed.add(copy);
			}
			subscription.connection.write(new Notification() {
				method = subscription.method,
				id = subscription.id,
				args = packed
			});
		}
```

---

### 3. `libocrpc/Live/Subscribe.vala` — `rpc_signal` named-signal connect

**Why:** `connect_swapped` cannot deliver GValues into `emit`.

**Where:** named-signal branch; the `GLib.Signal.connect_swapped` line.

**Depends on:** §2.

#### Remove

```vala
			subscription.hid = GLib.Signal.connect_swapped(obj, name, (GLib.Callback) Subscription.emit, subscription);
```

#### Replace with

Same place: GClosure + `connect_closure`. `hid` still works with
`SignalHandler.disconnect` on unsubscribe / `stop` / `rpc_unref`.

```vala
			var closure = new GLib.Closure.simple((uint) GLib.Closure.SIZE, subscription);
			closure.set_meta_marshal(subscription, (GLib.ClosureMarshal) Subscription.emit);
			subscription.hid = GLib.Signal.connect_closure(obj, name, closure, false);
```

---

### 4. `libocrpc/Live/namespace.vala` — Win32/Android `Subscription.emit` stub

**Why:** compile-only shell must match the Unix method.

**Where:** `#if G_OS_WIN32 || ANDROID` `Subscription` class; `emit`.

**Depends on:** §2.

#### Remove

```vala
		public void emit() {}
```

#### Replace with

Empty marshal with the Unix signature.

```vala
		public static void emit(
			GLib.Closure closure,
			[CCode (type = "GValue*")] GLib.Value? return_value,
			[CCode (array_length_cname = "n_param_values", array_length_pos = 2.5, array_length_type = "guint")]
			GLib.Value[] param_values,
			void* invocation_hint,
			void* marshal_data
		) {
		}
```

---

### 5. `tests/rpc/subscribe-test.vala` — `pinged("hello")` on `Notification.args`

**Why:** library gate for the gnome-shell-rpc FAIL (string payload).
Existing `closed()` / `notify::title` counts stay unchanged.

**Where:** `Probe` signals; new `Capture` block after the `held_probe`
unref checks.

**Depends on:** §1, §2, §3.

#### Add — on `Probe`, after `public signal void closed();`

```vala
		public signal void pinged(string payload);
```

#### Add — at the end of `run_rpc_test`, before the closing `}` of the method

Fresh connection so existing `writes` asserts are untouched.

```vala
			var pinged_conn = new Capture() {
				live_handles = true
			};
			var pinged_probe = new Probe();
			var pinged_id = pinged_conn.export(pinged_probe);
			var pinged_sub = new OLLMrpc.Request() {
				method = "RPC-Live-Subscribe.rpc_signal",
				lease_id = pinged_id,
				args = OLLMrpc.args("s", "pinged"),
				connection = pinged_conn
			};
			this.check(command_line, pinged_sub.dispatch(), "Subscribe.signal pinged dispatch failed");
			pinged_probe.pinged("hello");
			this.check(command_line, pinged_conn.writes == 1, "pinged did not write one Notification");
			this.check(command_line, pinged_conn.last.method == "pinged", "pinged method mismatch");
			this.check(command_line, pinged_conn.last.args.size == 1, "pinged args missing");
			this.check(command_line, pinged_conn.last.args.get(0).get_string() == "hello", "pinged payload mismatch");
			this.check(command_line, pinged_conn.last.message == "", "pinged must not stuff message");
```

---

## Next

- 🔷 ⏳ Apply §1–§5 here after approve.
- 🔷 ⏳ gnome-shell-rpc keeps the FAIL gate until this lands, then
  asserts `notif.args` (not `message`) and re-emits with those GValues.
  No Laters / Runtime flush workaround.
