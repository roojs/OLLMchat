# `Live.Hook.emit` on a stopped connection waits forever

**Status:** ✔️ FIXED — early return in `Live/Hook.vala` when `Connection.running` is false; gate PASSes. Archived 2026-10-03. Found from `gnome-shell-rpc` (1.2 teardown).

## Problem

- 🔷 A consumer may still hold a `Live.Hook` row after its connection stops: for example, a C vfunc trampoline that fires on the next relayout. `emit` must return. A short `reply_args` is fine, because callers already fall back to the base / default path.
- ℹ️ `Live/Hook.vala` `emit` sets `this.replied = false`, calls `connection.write`, then loops `while (!frame.replied && !this.replied) connection.emit_wait_poll();`.
- ℹ️ After `Transport.Connection.stop()`:
    - `write` returns at once (`!channel_open`).
    - `callbacks` is cleared, so no `Callback.reply` can find the row.
    - `stop()` set `replied = true` on each row, but `emit` resets it to `false` first.
    - Nothing completes the frame. The loop waits forever, and the host process (mutter) hangs.
- ℹ️ An emit that is already waiting when `stop()` runs is fine: `stop()` sets `replied` and the loop exits. Only emits that start after the stop hang.

### Reproduction

Gate (in `gnome-shell-rpc`, real libocrpc, base `Transport.Connection` only, no consumer subclass): `tests/call-sync-repro/hook-emit-after-stop-gate.vala`.

- Open a real Unix socket pair, `start()` a `Transport.Connection` on the accepted end, and register one `Live.Hook` in `callbacks`.
- `stop()` the connection, then call `hook.emit(empty args)`.
- A 2 s watchdog prints FAIL and exits 1.

```text
meson compile -C build
timeout 8 ./build/tests/call-sync-repro/hook-emit-after-stop-gate
```

2026-10-03 result (before the fix): **FAIL**.

```text
gate: connection stopped, emitting on held hook
FAIL hook-emit-after-stop-gate: Hook.emit still waiting 2s after the connection stopped.
```

## Evidence (live)

- ℹ️ `gnome-shell-rpc` sets Clutter `LayoutManager` / `Constraint` vfunc hooks from the client. When the shell client exits, the server stops the connection, but mutter keeps laying out actors that still carry those hooks. Without a consumer-side clear of every hook holder, the next allocate blocks mutter in `emit_wait_poll`.

## Why this is libocrpc and not the consumer

- ✔️ The wait loop and the `replied` reset are in `Live/Hook.vala`. The gate uses no consumer code.
- ✔️ The consumer cannot tell from a `Hook` row that its connection stopped: `running` was `protected` on `Transport.Connection`.
- 💩 Consumer workaround: find and clear every object that holds a hook at teardown, by type. That has to be repeated for each hook holder, so it is a patch over this bug, not a fix.

## Root cause

- ✔️ `emit` always clears `replied` and then blocks in `emit_wait_poll` until a reply arrives. After `stop()`, `write` is a no-op and `callbacks` is empty, so no reply can arrive. `stop()` had already set `replied`, and `emit` overwrites that.

## Fix

- 🔷 ✔️ `running` is public so `Hook.emit` can read it. Subclasses still assign the same field.
- 🔷 ✔️ In `Hook.emit`, return before writing when the connection is not running. `reply_args` is cleared.

#### Add — at the start of `Hook.emit`, before `next_handle`

```vala
if (!this.connection.running) {
    this.reply_args.clear();
    return;
}
```

- 🔷 ✔️ The wait loop also requires `connection.running`, so a stop that lands after `replied` is cleared still ends the wait.

#### Replace — `Hook.emit` wait condition

```vala
while (!frame.replied && !this.replied) {
```

#### Replace with

```vala
while (!frame.replied && !this.replied && this.connection.running) {
```

- ✔️ Gate PASSes: emit returns, `reply_args.size == 0`.

## Attempts / changelog

- 2026-10-03 — ✔️ Gate written and FAILs. No OLLMchat code changed.
- 2026-10-03 — ✔️ `libocrpc/Live/Hook.vala`: return when `!connection.running`, and stop the wait loop when `running` goes false. `libocrpc/Transport/Connection.vala`: `running` is public. Gate against the build tree: `LD_LIBRARY_PATH=…/OLLMchat/build/libocrpc timeout 8 ./build/tests/call-sync-repro/hook-emit-after-stop-gate` → `PASS hook-emit-after-stop-gate reply_args=0`.
- 2026-10-03 — Archived to `docs/bugs/done/`. The live mutter relayout check was not re-run in this session.
