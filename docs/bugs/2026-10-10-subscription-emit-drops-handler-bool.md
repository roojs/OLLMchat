# `Live.Subscription.emit` drops the handler bool

**Status:** ✔️ libocrpc edit applied. The wait still needs gnome-shell-rpc `LiveCallback.reply` to set `replied` on this mailbox.
**Component:** `libocrpc` / `OLLMrpc.Live.Subscription` + `Notification`
**Related:** gnome-shell-rpc [`docs/bugs/2026-10-10-blocking-signal-subscribe.md`](../../../gnome-shell-rpc/docs/bugs/2026-10-10-blocking-signal-subscribe.md) — `add_signals` sets `blocking`, and the client sends the bool back. [`done/RPC-8.3.6-rpc-live-callbacks.md`](../plans/done/RPC-8.3.6-rpc-live-callbacks.md) — `Hook.emit` already waits on `RPC-Live-Callback.reply`.

**Process:** Follow **`docs/bug-fix-process.md`** — propose → approve → apply. Do not land from the gnome-shell-rpc tree.

## Problem

- **🔷** A named signal whose handler returns bool has to finish before Clutter ends the emission.
- **🔷** `Live.Subscription.emit` writes a `Notification` and returns. The bool is discarded.
- **🔷** `blocking` is set on the subscription when it is created.
- **🔷** When that flag is set, `emit` waits the way `Hook.emit` waits, and writes the bool into `return_value`.
- **🔷** The signal still travels as a `Notification`. `reply_id` is how the reply finds that wait.
- **ℹ️** Zero `reply_id` stays one-way. Same bytes as today.

gnome-shell-rpc `LiveCallback.reply` has to mark this mailbox `replied`. `Hook.complete` returns false when there is no frame. That edit is in the bug above.

## 1. `libocrpc/Live/Subscription.vala` — `blocking`, and `emit` waits

**Why:** The flag is stored on the row. `emit` is the closure Clutter calls. A blocking name writes the handler bool into `return_value` before `emit` returns.

**Where:** after `hid`, and the end of `emit` after the existing `connection.write`.

**Depends on:** `Notification.reply_id` below.

#### Add — after `public ulong hid`

```vala
		/**
		 * Handler bool finishes inside the emission.
		 */
		public bool blocking { get; set; default = false; }
```

#### Remove

```vala
			subscription.connection.write(new Notification() {
				method = subscription.method,
				id = subscription.id,
				args = packed
			});
		}
```

#### Replace with

```vala
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
```

## 2. `libocrpc/Notification.vala` — `reply_id`

**Why:** A one-way notification has no reply. A blocking emission needs the correlation `Callback.reply` already uses.

**Where:** next to `id`. `bin_write_prop` skips `reply_id` of 0 the same way `Invoke` does.

**Depends on:** none.

#### Add — after `public int id`

```vala
		/**
		 * Non-zero while the sender waits on
		 * ''RPC-Live-Callback.reply''.
		 * Zero is one-way.
		 */
		public int reply_id { get; set; default = 0; }
```

#### Add — inside `bin_write_prop`, before the `method` case

```vala
				case "reply-id":
					if (this.reply_id == 0) {
						return;
					}
					this.bin_default_write_prop(ctx, prop);
					return;
```

## Attempts / changelog

- **✔️** `libocrpc/Live/Subscription.vala` — `blocking`, and `emit` waits on a `Hook` mailbox when that flag is set and `return_value` is present. The `emit` docblock no longer calls `return_value` unused.
- **✔️** `libocrpc/Notification.vala` — `reply_id`, omitted on the wire at 0. The property docblock uses `''RPC-Live-Callback.reply''`. `{@code}` is not valid valadoc.
- **✔️** `ninja -C build libocrpc/libocrpc.so` succeeded.

## Next

- **⏳** gnome-shell-rpc `LiveCallback.reply` still has to set `replied` on this mailbox. `Hook.complete` returns false because this wait has no frame.
