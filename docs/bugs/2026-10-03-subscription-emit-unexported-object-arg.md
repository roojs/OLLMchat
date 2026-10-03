# `Live.Subscription.emit` writes GObject args the connection never exported — connection dies

**Status:** ⏳ fix applied in `Live/Subscription.vala`; gate PASSes — await live (nested shell) verification. Found from `gnome-shell-rpc` 2026-10-03.

- ℹ️ Follows [`done/2026-09-19-FIXED-subscription-emit-drops-signal-args.md`](done/2026-09-19-FIXED-subscription-emit-drops-signal-args.md). Args are now packed. An object arg that is not already in `lease_ids` cannot be written.

## Problem

- 🔷 A subscribed named signal may carry a GObject this connection has not seen yet. The notification must arrive, and the connection must stay up.
- ℹ️ Today `Subscription.emit` packs `param_values` with `TypeOverride.pack_params` and calls `connection.write`. With `live_handles`, `Bin/StreamValue.vala` (lines ~265–295) looks the object up in `connection.lease_ids`. If it is missing, it throws `StreamError.PROTOCOL "live object %s not in connection.lease_ids"`. `Transport.Connection.write` catches that and calls `stop()`. The peer gets EOS.
- ℹ️ One unexported arg on any subscribed signal kills the whole connection.

### Reproduction

Gate (in `gnome-shell-rpc`, real libocrpc, two processes): `tests/call-sync-repro/subscribe-unexported-object-arg-gate.vala`.

- The server exports a `Peer` with `signal spawned(Child)`. The client subscribes with `RPC-Live-Subscribe.rpc_signal`.
- `Gate.fire` makes a new `Child`, never exported, and emits `spawned(child)`.
- PASS: the `spawned` notification arrives with one arg, and a later `Gate.ping` gets its reply.

```text
meson compile -C build
timeout 8 ./build/tests/call-sync-repro/subscribe-unexported-object-arg-gate
```

2026-10-03 result: **FAIL**.

```text
server: fire spawned(unexported child)
WARNING: Connection.vala:228: connection write error: live object Child not in connection.lease_ids
ERROR: Client.vala:702: Unexpected early end-of-stream
```

## Evidence (live)

Nested `gsr-server` (mutter 48), shell started, then a Wayland client opens a window:

```text
14:32:18.195405 Connection.vala:228: connection write error: live object MetaWindowWayland not in connection.lease_ids
14:32:18.224487 Client.vala:702: Unexpected early end-of-stream
14:32:18.251258 Server.vala:163: window_created ...
```

- ℹ️ gnome-shell subscribes to `Meta.Workspace::window-added` (`workspace.js`, `workspaceThumbnail.js`, `windowManager.js`) and `Meta.Display::window-entered-monitor` (`workspace.js`, `main.js`, `windowManager.js`).
- ℹ️ Mutter emits both while the new `Meta.Window` is still being constructed. `Meta.Display::window-created` comes after, and that is the first point where the consumer can export the window. The write error at .195 comes before the consumer's `window_created` at .251.

## Why this is libocrpc and not the consumer

- ✔️ The marshaller is libocrpc's: `Subscription.emit` is the GClosure marshal. The consumer has no hook between the signal firing and the write.
- ✔️ libocrpc already exports on its other write paths. `Gi.vala` GLIST / SLIST / GHASH returns call `this.request.connection.export(obj)` for each registered GObject before replying (lines ~1695, ~1711, ~1761). `Gi` constructors export the created object (lines ~455, ~703). The signal path is the only one that writes a live object without exporting it.
- ✔️ The gate uses only libocrpc plus the consumer's thin `Listen` / `Connection` subclass. That subclass overrides `emit_wait_poll` / `on_input_ready` only. `write` and `stop` are base.
- 💩 Signals that work today (`ClutterStage::before-update(StageView, Frame)`) work because `gnome-shell-rpc` pre-exports the stage views in `connection_ready`. That only works for objects that exist before the subscription. A new window does not.
- 💩 A consumer workaround is possible: connect `window-added` / `window-entered-monitor` on the server before the shell does, and export there. That has to be repeated for every signal that can carry a new object, so it is a patch over this bug, not a fix.

## Root cause

- ✔️ `Subscription.emit` and the `notify::` handler wrote live GObject args without `connection.export`. Every other libocrpc write path exports first. `StreamValue` then has no lease id and throws.

## Fix

- 🔷 ✔️ In `Subscription.emit` and the `notify::` handler, after packing and when `connection.live_handles` is set, call `connection.export(obj)` for each non-null GObject arg that is not `Bin.Serializable`. `export` is idempotent, so objects that are already leased keep their id.
- ✔️ The `notify::` handler now builds `packed` and the method name (`rpc_signal_alias` when a `TypeOverride` exists) first, then writes once. It uses a local instead of a ternary (Vala ternary bug).
- 🚫 Not changed: a `TypeOverride.pack` that returns a `Gee.ArrayList` of live objects is not walked. No in-tree override does that.
- 🔷 An unregistered GType throws `StreamError.REGISTRATION "Unregistered class type schema: %s"` in `Bin.Stream.write_reg_gtype`. `Connection.write` catches it and stops that connection only; the server keeps listening. Disconnect is the accepted result (user, 2026-10-03). Not hit by the gate or the live log.
## Notification write error stops the connection

- 🔷 Decision (user, 2026-10-03): keep `stop()`. A notification that cannot be encoded is a bug. It must crash, throw, or disconnect the client so it surfaces. It must not be dropped quietly.
- ✔️ `stop()` is also the only option that keeps the wire consistent. `Bin.Stream` writes straight to the socket and updates `server_names` / `client_names` / `name_to_token` during the write, so a mid-message throw leaves partial bytes and token state the peer never saw.
- 🚫 Catch and continue: desyncs the stream, and hides the bug.
- 🚫 Encode to memory first, roll back the name tables, drop the notification: considered and rejected. It masks encode bugs.

## Attempts / changelog

- 2026-10-03 — ✔️ Gate written and FAILs. Live log captured. No OLLMchat code changed.
- 2026-10-03 — ✔️ `libocrpc/Live/Subscription.vala`: export live args in `emit` and the `notify::` handler. Gate run against the build tree: `LD_LIBRARY_PATH=…/OLLMchat/build/libocrpc timeout 8 ./build/tests/call-sync-repro/subscribe-unexported-object-arg-gate` → `PASS` (spawned=true args=1, ping ok).
- ⏳ Next: install libocrpc, re-run nested `gsr-server` window-open (`window-added` / `window-entered-monitor`) and confirm no write error / EOS.
