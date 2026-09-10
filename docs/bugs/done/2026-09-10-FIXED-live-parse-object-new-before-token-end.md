# Bin parse reentrancy: sync RPC during live `Object.new` eats `TOKEN_END` as next message

**Status:** ✔️ applied — await consumer verify  
**Hit:** 2026-09-10 — gnome-shell-rpc nested Wayland after emit-poll fix  
**Component:** `libocrpc` / `Bin.Stream.parse_object` (live_handles) + `Client.call_poll`  
**Consumer:** `Clutter.DesaturateEffect.factor` set-construct → `Clutter-DesaturateEffect.set_factor`  
**Consumer bug:** `gnome-shell-rpc/docs/bugs/2026-09-10-desaturate-nested-set-factor-wire.md`  
**Log:** `/tmp/mutter-rpc-emit-poll2.log` ~18336–18340  

---

## Symptom

```text
Client: id=4595 method=Clutter-DesaturateEffect.new
Server: recv id=4595 method=Clutter-DesaturateEffect.new
Client: id=4596 method=Clutter-DesaturateEffect.set_factor   ← nested mid-wait
Server: recv id=4596 method=Clutter-DesaturateEffect.set_factor
Client: unexpected byte 0xFD after 0xFF   ← Client.vala poll_drain → bin.parse
```

No `replied id=4595`. Client aborts; socket goes quiet for RPC.

`0xFF` `0xFD` is {@link Bin.Stream.TOKEN_END} (`0xFFFD`). Nested
`bin.parse()` at a root boundary saw leading `0xFF` and assumed
{@link TOKEN_REG_TYPE} (`0xFF` `0xFE`).

---

## Root cause

`parse_object` live path called `GLib.Object.new` **before** consuming
`TOKEN_END`. Construct property setters (`set construct` on `factor`)
could nest `call_poll` on the same `DataInputStream` while the outer
object's end token was still unread.

---

## Fix (applied)

**`libocrpc/Bin/Stream.vala` — `parse_object` live path:** read
`uint64` handle → verify `TOKEN_END` → then `Object.new` with
`rpc-lid`.

```vala
var handle = this.in_stream.read_uint64();
if (this.in_stream.read_uint16() != TOKEN_END) {
    throw new StreamError.PROTOCOL("expected end after live handle");
}
var live = GLib.Object.new(decode_type, "rpc-lid", handle);
this.client.proxies.set((int) handle, live);
return live;
```

Wire format unchanged (handle then `TOKEN_END` only). No `0xFF`
disambiguation hardening — rejected; keep current token format.

**Tests:** `test-rpc-live-handles`, `test-rpc-bin`, `test-rpc-proxies` pass.

---

## Reproduce (pre-fix)

```bash
cd gnome-shell-rpc
timeout 30 dbus-run-session ./build/src/mutter-rpc --debug --wayland --nested \
  > /tmp/mutter-rpc-emit-poll2.log 2>&1
```

---

## Consumer note

gnome-shell-rpc may still defer RPC from `factor` set-construct until
after `construct {}` finishes; library now consumes framing before
`Object.new`.
