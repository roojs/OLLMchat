# Live `Object.new` mid-parent parse — nested RPC desync

**Status:** CLOSED — fixed in gnome-shell-rpc (consumer); no libocrpc change  
**Hit:** 2026-09-10 — nested Wayland after `TOKEN_END`-before-`Object.new` (`f5417b2c`)  
**Component:** would have been `libocrpc` framing / parse; **not pursued here**  
**Prior:** [`2026-09-10-FIXED-live-parse-object-new-before-token-end.md`](2026-09-10-FIXED-live-parse-object-new-before-token-end.md)  

---

## Symptom (after TOKEN_END fix)

```text
Client: id=4593 method=Clutter-DesaturateEffect.new
Client: id=4594 method=Clutter-DesaturateEffect.set_factor
Client: expected object type byte, got 0x00
```

Nested `call_poll` from a `set construct` setter ran while the outer `Response` was still on the wire.

---

## Decision

- **libocrpc:** keep current socket framing (no length-prefixed message envelopes).
- **Consumer:** defer sync RPC from `set construct` until `construct {}` finishes (or equivalent guard). Boot OK with that pattern.

Sketched OPC fix (length-prefixed `read_frame` / `write_frame`) is **withdrawn** for this repo.

---

## Reproduce (historical)

```bash
cd gnome-shell-rpc
# libocrpc TOKEN_END fix, no consumer construct guards
timeout 20 dbus-run-session ./build/src/mutter-rpc --debug --wayland --nested
```
