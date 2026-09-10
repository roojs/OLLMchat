# `Hook.emit` cannot recv nested `RPC-Live-Callback.reply` mid-`on_input_ready`

**Status:** ✔️ applied — await consumer verify  
**Hit:** 2026-09-10 — gnome-shell-rpc nested Wayland after `call_poll` + in-flow reply  
**Component:** `libocrpc` / `Live.Hook.emit` + `Transport.Connection.on_input_ready`  
**Consumer:** gnome-shell-rpc `Helper.Actor` sync preferred/allocate emit  
**Consumer bug:** `gnome-shell-rpc/docs/bugs/2026-09-10-nested-reply-mid-emit-hang.md`  
**Related (client, fixed):** `done/2026-09-10-FIXED-call-sync-nested-io-watch-reentrancy-hang.md`  
**Harness shape:** `gnome-shell-rpc/tests/call-sync-repro/` mode `stack`

---

## Symptom (consumer, 2026-09-10 ~09:43)

After many successful preferred/allocate relays (`call_poll` + in-flow
`RPC-Live-Callback.reply`), startup hangs with **one emit left open**:

| Counter | Value |
|---------|------:|
| server `emit BEGIN` | 53 |
| server `emit END` | **52** |
| client `DBG invoke ENTER` | 53 |
| client `DBG invoke REPLY start` | 53 |
| client `DBG invoke REPLY done` | **52** |

Hang window (`~/.cache/gnome-shell-rpc/*.debug.log`):

```text
server: Helper.Actor.preferred_width emit BEGIN hook_id=61
client: id=1563 method=Clutter-Actor.remove_all_transitions
client: DBG invoke ENTER id=61 reply_id=528
client: DBG invoke REPLY start id=61 reply_id=528
client: id=1564 method=RPC-Live-Callback.reply
server: recv id=1563 method=Clutter-Actor.remove_all_transitions
client: replied id=1563
… silence …
server: never recv id=1564
client: never DBG invoke REPLY done id=61
server: never emit END hook_id=61
```

Outer GI Response for `1563` completes; nested reply Request `1564` never
appears in `Connection` `recv` logs. Client sits in `call_poll(1564)`.
Server sits in `Hook.emit` → `MainContext.default().iteration(true)`.

Same shape earlier the same morning with `Meta-Background.set_color` /
reply id=199 (BEGIN=16 END=15).

---

## Why this is OPC (not consumer Idle)

Consumer Runtime already:

- uses `Client.call_poll` for stub calls
- replies to `Live.Invoke` **in-flow** (no Idle queue / drain)

Nested `call_poll(RPC-Live-Callback.reply)` is entered and logged. The
missing piece is **server never demuxes that Request** while waiting in
`Hook.emit`.

---

## Suspected root cause

`Live/Hook.vala`:

```vala
this.connection.write(new Invoke() { … });
while (!this.replied) {
    GLib.MainContext.default().iteration(true);
}
```

`Transport/Connection.on_input_ready` is a default-context IO watch that
`dispatch()`s each Request. Typical hang stack:

1. Watch fires → `on_input_ready` → dispatch outer GI (e.g.
   `remove_all_transitions` / `set_color`).
2. That path (or nested layout) calls `Hook.emit` → write `Live.Invoke` →
   `iteration` wait for `Callback.reply`.
3. Client demuxes Invoke mid-`call_poll`, starts nested
   `call_poll(RPC-Live-Callback.reply)` and writes Request `1564`.
4. Server `iteration` **cannot re-enter the same IO watch** while still
   inside `on_input_ready` (`G_HOOK_FLAG_IN_CALL`) → `1564` never parsed
   → `replied` never set → emit loops forever.
5. Outer GI may still finish and send its Response (client sees
   `replied id=1563`) if that Response was written before / beside the
   nested emit wait — client then blocks only on the nested reply
   Response that never comes.

This is the **server** twin of the fixed **client** bug
`call_sync` single-watch IN_CALL
(`done/2026-09-10-FIXED-call-sync-nested-io-watch-reentrancy-hang.md`).
Client moved to `call_poll` (no private MainLoop watch). Server `Hook.emit`
still pumps the **same** default context that owns the connection watch.

Consumer harness `stack` mode was written for this shape: emit inside
`on_input`, reply deferred / never dispatched, parent stalls.

---

## What we need from OPC

One of (design pick upstream — do not patch from gnome-shell-rpc):

1. **`Hook.emit` wait that can read the socket without relying on
   re-entering the connection IO watch** (e.g. direct drain / nested
   parse while waiting for `replied`), or
2. **Document that sync `Hook.emit` must not run on the request-dispatch
   stack** and provide a supported off-stack emit that still returns
   preferred/allocate outs synchronously to Clutter, or
3. Another contract that makes nested `RPC-Live-Callback.reply` during
   mid-dispatch emit reliably receivable.

Also useful for prove: temporary DBG after `Callback.reply` MATCH/MISS and
server `recv` of reply while `emit` open — consumer cannot add these
without an OPC change.

---

## Reproduce

```bash
# consumer tree, current Runtime call_poll + in-flow reply + Helper.Actor sync emit
cd gnome-shell-rpc
meson compile -C build
timeout 20 dbus-run-session ./build/src/mutter-rpc --debug --wayland --nested \
  > /tmp/mutter-rpc-nested-reply-hang.log 2>&1
# Expect: emit BEGIN = emit END + 1; last open preferred_*; no recv of nested reply id
```

Toy: `tests/call-sync-repro/` `stack` (FAIL) vs `reenter` (PASS).

---

## Attempts / changelog

- ✔️ `Connection.emit_wait_poll()` — **virtual**; default
  `MainContext.iteration`; docblock describes socket override (`GLib.poll` +
  parse/dispatch). No in-tree subclass — server app overrides on its
  `Connection` type.
- ✔️ `Hook.emit` — calls `connection.emit_wait_poll()` each wait turn.
- ⏳🔷 Consumer (mutter-rpc): subclass `Connection`, override
  `emit_wait_poll`, wire into listen accept path.
- ✔️ `tests/test-rpc.sh` + `test-rpc-callback` — pass.

## Non-goals / already done elsewhere

- Client Idle-defer reply — removed in consumer; not this bug.
- `call_poll` PollFD `revents` copy / IOChannel buffer-condition — fixed.
- Client nested `call_sync` IO watch — fixed / superseded by `call_poll`.
