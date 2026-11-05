# `Live.Subscription.emit` could not return non-Boolean signal values

**Status:** ✔️ fixed and verified by library and real-consumer gates

## Problem

- 🔷 A blocking subscription must return the remote handler's value using the
  GObject signal's declared return type.
- ✔️ `OLLMrpc.Live.Subscription.emit` treated every non-void return as
  Boolean. For `signal uint ask()`, it called `set_boolean()` on a uint
  `GValue`.
- ✔️ GLib reported:

```text
GLib-GObject-CRITICAL: g_value_set_boolean: assertion
'G_VALUE_HOLDS_BOOLEAN (value)' failed
```

- ✔️ The signal emitter received uint `0` after the remote handler returned
  uint `7`.

## Reproduction and evidence

- ℹ️
  [`gnome-shell-rpc/tests/call-sync-repro/subscription-uint-return-gate.vala`](../../../../gnome-shell-rpc/tests/call-sync-repro/subscription-uint-return-gate.vala)
  creates a real libocrpc subscription to `signal uint ask()`. The client
  receives a blocking notification and replies with uint `7`.
- ✔️ Before the fix:

```text
GLib-GObject-CRITICAL: g_value_set_boolean: assertion
'G_VALUE_HOLDS_BOOLEAN (value)' failed
FAIL subscription-uint-return-gate: uint reply lost ask=true reply-id=true returned=0 error=
```

- ✔️ `ask=true` proved the notification arrived, `reply-id=true` proved it was
  blocking, and the empty callback error proved the typed reply RPC
  completed. The failure occurred while the generic subscription marshaller
  filled the GClosure return value.

## Root cause

- ✔️ `RPC-Live-Callback.reply` preserved the handler's typed first return in
  `waiter.reply_args`.
- ✔️ `Subscription.emit` discarded that type and called `set_boolean()`
  unconditionally for every non-void signal.
- ✔️ The destination `GValue` is initialized by GObject with the signal's
  declared return type. The correct generic operation is `g_value_copy()`
  from the typed wire value into that destination.
- 🚫 A type-mismatch fallback was not added. `g_value_copy()` requires
  matching source and destination types; a mismatch is a protocol bug that
  must remain visible.

## Fix

- ✔️ `libocrpc/Live/Subscription.vala` now copies the first typed handler
  result with `g_value_copy()` when the signal has a return value.
- ✔️ Void signals still send and wait without touching a null return pointer.
- ✔️ The Boolean-only API documentation now describes typed returns.
- ✔️ `tests/rpc/subscribe-test.vala` covers both a uint return of `7` and a
  blocking void signal.

### Why a second `g_value_copy()` declaration is required

The standard Vala binding already exposes `g_value_copy()` as
`GLib.Value.copy(ref GLib.Value)`. The extern does not replace a missing API;
it supplies the C function's nullable-pointer signature for this marshaller.

GObject passes a null `GValue*` for a void signal, so the marshaller's
destination must remain `GLib.Value?`. Calling the standard binding would
require changing it to non-nullable `ref GLib.Value`. Vala then generates
`g_return_if_fail(return_value != NULL)` at method entry, which prevents void
signals from sending their blocking notification.

The file-scope extern retains `GValue* return_value`, allows the existing null
check, and emits a direct `g_value_copy(reply, return_value)` call.

## Verification

- ✔️ Focused library build and regression:

```bash
ninja -C build tests/test-rpc-subscribe
meson test -C build test-rpc-subscribe --print-errorlogs
```

```text
1/1 ollmchat:rpc / test-rpc-subscribe OK
Ok: 1
Fail: 0
```

- ✔️ Void-signal path under fatal GLib criticals:

```bash
G_DEBUG=fatal-criticals meson test -C build test-rpc-subscribe --print-errorlogs
```

```text
1/1 ollmchat:rpc / test-rpc-subscribe OK
Ok: 1
Fail: 0
```

- ✔️ Valadoc:

```bash
ninja -C build docs/valadoc
```

```text
Succeeded - 458 warning(s)
```

  The warnings are existing project-wide documentation warnings; the target
  succeeded.

- ✔️ Original real-libocrpc consumer gate after rebuilding:

```bash
meson compile -C build tests/call-sync-repro/subscription-uint-return-gate
timeout 5 ./build/tests/call-sync-repro/subscription-uint-return-gate
```

```text
PASS subscription-uint-return-gate: uint reply returned 7
```

- ✔️ IDE diagnostics and `git diff --check` report no errors.

## Remaining consumer work

- ℹ️ This libocrpc fix resolves the `guint` half of the Shell 50 keymap
  failure:
  - `reset-keymap-layout-index` returns `guint`.
  - `reset-keymap-description` returns boxed `Meta.KeymapDescription`.
- 💩 ⏳ `gnome-shell-rpc` still has two consumer-owned gaps:
  1. `src/server/libmutter-clutter-18/ClutterActor.vala` does not mark either
     reset signal as blocking, so today it sends them one-way.
  2. `src/client/libshell-16/Signals.vala` cannot encode boxed
     `KeymapDescription`; an object lease id is not a boxed-value return.
- 💩 ⏳ The boxed return needs its own failing gate and a defined boxed return
  codec before deciding whether that gap belongs in generic libocrpc or in the
  consumer's `Meta.KeymapDescription` override.
- 🚫 `keymap-changed` and `keymap-layout-group-changed` are void notifications,
  not instances of this typed-return defect.

## Attempts / changelog

- ✔️ 2026-11-05: Confirmed the Boolean-only implementation and reproduced the
  failure with the real-libocrpc uint gate.
- ✔️ 2026-11-05: Compile-tested the proposed nullable C binding and uint/void
  regressions in an isolated worktree.
- ✔️ 2026-11-05: Applied the documented fix to
  `libocrpc/Live/Subscription.vala` and `tests/rpc/subscribe-test.vala`.
- ✔️ 2026-11-05: Passed the focused test, fatal-critical test, Valadoc build,
  and original `gnome-shell-rpc` gate.
