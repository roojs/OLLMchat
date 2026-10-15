# `Live.Subscription` does not block void signals

**Status:** ✅ FIXED — user archived 2026-10-15. Blocking void signals wait
for the remote reply. gnome-shell-rpc marked `before-update` blocking; its
35-check signal-reentrancy suite had no unexpected failures, and nested
Weston kept the drag scale transition alive across the forced 400ms gap.

## Problem

🔷 A subscription with `blocking = true` must keep the server inside the
GObject signal emission until the remote handler replies.

🔷 This must work for void signals as well as boolean signals. GNOME Shell's
`ClutterStage::before-update`, `clicked`, and `long-press` are void signals.

🔷 Actual: a blocking void signal is sent as a one-way notification with
`reply_id = 0`. The server returns from the signal before the client handler
finishes.

## Evidence

✔️ The gnome-shell-rpc consumer gate uses the configured real libocrpc:

```bash
meson compile -C build tests/call-sync-repro/blocking-void-signal-gate
timeout 5 ./build/tests/call-sync-repro/blocking-void-signal-gate
```

✔️ Result before the library fix, exit 1:

```text
FAIL blocking-void-signal-gate: blocking void signal was one-way tick=true reply-id=false observed-during-emit=false error=
```

✔️ Result after the library fix, exit 0:

```text
PASS blocking-void-signal-gate: void signal waited for reply
```

ℹ️ Gate:
`/home/alan/gitlive/gnome-shell-rpc/tests/call-sync-repro/blocking-void-signal-gate.vala`.
It connects a blocking subscription to a void signal. The notification
handler calls back into the server before replying. The nested call observes
that the original signal emission has already returned.

## Root cause

✔️ `libocrpc/Live/Subscription.vala` uses the GClosure `return_value` pointer
to decide whether to block:

```vala
			if (!subscription.blocking || return_value == null) {
				subscription.connection.write(note);
				return;
			}
```

✔️ GClosure supplies `return_value == null` for every void signal. That
describes the signal return type; it does not cancel the subscription's
blocking contract.

✔️ The early return happens inside libocrpc before the consumer receives the
notification. The consumer cannot allocate the missing reply id or keep the
server's GClosure emission open. This is therefore a library defect, not a
gnome-shell-rpc scheduling fix.

## Proposed fix

🔷 Blocking controls whether the emission waits. `return_value` controls only
whether the remote boolean result is copied back into GClosure.

🔷 No API or wire-format change is needed. The existing blocking path already
allocates `Notification.reply_id`, waits in `emit_wait_poll()`, and supports
nested RPC calls while waiting.

### 1. `libocrpc/Live/Subscription.vala` — `blocking` contract

**Why:** document the existing property for both supported signal shapes.

**Where:** the `blocking` property docblock.

**Depends on:** none.

#### Remove

```vala
		/**
		 * Handler bool finishes inside the emission.
		 */
```

#### Replace with

```vala
		/**
		 * Wait for the remote handler before the signal emission returns.
		 *
		 * Boolean signals copy the handler result into the return value.
		 * Void signals only wait.
		 */
```

### 2. `libocrpc/Live/Subscription.vala` — `emit`: wait independently of return type

**Why:** a null return slot is the valid GClosure contract for void signals.
It suppresses only the final boolean assignment.

**Where:** `Subscription.emit`, first at the one-way branch after `note`, then
at the final assignment after the wait.

**Depends on:** §1.

#### Remove

```vala
			if (!subscription.blocking || return_value == null) {
				subscription.connection.write(note);
				return;
			}
```

#### Replace with

```vala
			if (!subscription.blocking) {
				subscription.connection.write(note);
				return;
			}
```

#### Remove

```vala
			return_value.set_boolean(waiter.reply_args.size > 0
				&& waiter.reply_args.get(0).type() == GLib.Type.BOOLEAN
				&& waiter.reply_args.get(0).get_boolean());
```

#### Replace with

```vala
			if (return_value != null) {
				return_value.set_boolean(waiter.reply_args.size > 0
					&& waiter.reply_args.get(0).type() == GLib.Type.BOOLEAN
					&& waiter.reply_args.get(0).get_boolean());
			}
```

## Verification

🔷 Rebuild libocrpc, configure gnome-shell-rpc against that build, and rerun
the consumer gate. Required result:

```text
PASS blocking-void-signal-gate: void signal waited for reply
```

🔷 Existing boolean blocking tests must remain passing.

🔷 The consumer must separately mark `before-update` blocking, then rerun its
signal-reentrancy suite and Weston drag smoke. Existing blocking void
subscriptions such as `clicked` and `long-press` need regression coverage
because this correction makes their configured blocking behavior effective.

## Attempts / changelog

✔️ 2026-10-15: consumer added and ran the real-libocrpc FAIL gate. No
libocrpc product code was changed.

✔️ 2026-10-15: applied the two `Subscription.vala` edits. The notification
local in `emit` is `notif`. `note` is a note document, so that name does
not belong on a `Notification`.

✔️ Gate, loaded
`/home/alan/gitlive/OLLMchat/build/libocrpc/libocrpc.so`:

```text
PASS blocking-void-signal-gate: void signal waited for reply
```

✔️ gnome-shell-rpc was reconfigured with:

```bash
meson configure build -Docrpc_libdir=/home/alan/gitlive/OLLMchat/build/libocrpc
```

✔️ After adding `before-update` to the consumer blocking list, its
signal-reentrancy suite reported 25 passes and 10 expected failures, with no
unexpected failures or timeouts.

✔️ Nested Weston: the `dnd.js` transition read 403ms after creation returned
the transition, then `new-frame` fired. The old `transition-gone` error did
not occur. The drag smoke continued to a separate consumer failure:
`miss preview-moved dx=0`.

## Next

✅ Closed. The zero-displacement drag (`miss preview-moved dx=0`) is a
separate gnome-shell-rpc failure and is not this library bug.
