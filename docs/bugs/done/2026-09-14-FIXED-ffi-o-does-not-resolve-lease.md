# Ffi `pack("o")` does not resolve wire lease ids

**Status:** ✅ FIXED — `pack("o")` lease resolve applied  
**Hit:** 2026-09-14 — gnome-shell-rpc `Helper-WaylandClient.create`  
**Component:** `libocrpc` / `OLLMrpc.Ffi.pack`  
**Consumer:** gnome-shell-rpc Helpers with GObject args (`"o"`)  
**Gate (consumer):** `gnome-shell-rpc/tests/call-sync-repro/ffi-o-lease-gate.vala`  
**Consumer bug:** `gnome-shell-rpc/docs/bugs/2026-09-14-ffi-o-lease-resolve.md`  
**Related:** `libocrpc/Ffi.vala`, `libocrpc/Gi.vala` (OBJECT lease resolve),
`gnome-shell-rpc/.../HelperMock.arg_object`

---

## Problem

🔷 Client packing turns GObject args into lease `uint64` on the wire
(consumer `call_value`, same idea as live Gi IN).

🔷 `OLLMrpc.Gi` resolves OBJECT / INTERFACE args from that `uint64` via
`connection.leases.get`.

🔷 `OLLMrpc.Ffi.pack("o")` only calls `val.get_object()`.
`add_class` / `register_live` Helper methods typed as `GObject` therefore
get null and hit `G_VALUE_HOLDS_OBJECT` CRITICAL when the client did the
right thing.

🔷 Expected: Ffi `"o"` accepts live Object **or** lease id (like Gi /
`HelperMock.arg_object`).

---

## Evidence

Gate (from gnome-shell-rpc tree):

```bash
timeout 5 ./build/tests/call-sync-repro/ffi-o-lease-gate
```

2026-09-14 FAIL:

```
g_value_get_object: assertion 'G_VALUE_HOLDS_OBJECT (value)' failed
gate_echo: assertion 'peer != NULL' failed
call timed out Gate.echo
```

`libocrpc/Ffi.vala` (current):

```vala
case "o":
    slot.set_pointer((void*) val.get_object());
    atype = Libffi.POINTER;
    break;
```

`libocrpc/Gi.vala` (OBJECT path already resolves `uint64`):

```vala
var id = (int) val.get_uint64();
…
var obj = this.request.connection.leases.get(id);
this.in_args[vi + offset].v_pointer = (void*) obj;
```

ℹ️ `Ffi.dispatch` already resolves **instance** `lease_id` via
`this.request.connection.leases.get` — only **arg** `"o"` is missing that step.

---

## Root cause

✔️ Inbound decode for Helper FFI: wire `"o"` arrives as a lease `uint64`
`GLib.Value`, not a `GObject`. `pack("o")` still does `get_object()`, so the
libffi slot is null / wrong-type and the Helper never sees the leased object.

---

## Proposed fix

🔷 In `Ffi.pack("o")` (already has `this.request`):

- if Value holds OBJECT → current `get_object()` path
- if Value holds UINT64 → `leases.get((int) id)` (id `0` → null; missing key →
  `reply_error(INVALID_PARAMS)` like Gi OBJECT)
- else → `GLib.critical` + null pointer

🚫 Consumer workarounds of `"t"` + manual `leases.get`.
🚫 Changing Gi lease packing.
🚫 Editing gnome-shell-rpc Helpers to take `uint64` instead of objects.

### 1. `libocrpc/Ffi.vala` — `pack` case `"o"` resolve lease

#### Remove

```vala
				case "o":
					slot.set_pointer((void*) val.get_object());
					atype = Libffi.POINTER;
					break;
```

#### Replace with

```vala
				case "o":
					if (val.type().is_a(GLib.Type.OBJECT)) {
						slot.set_pointer((void*) val.get_object());
						atype = Libffi.POINTER;
						break;
					}
					var id = (int) val.get_uint64();
					if (id == 0) {
						slot.set_pointer(null);
						atype = Libffi.POINTER;
						break;
					}
					if (!this.request.connection.leases.has_key(id)) {
						this.request.connection.reply_error(
							this.request, (int) RpcErrorCode.INVALID_PARAMS);
						slot.set_pointer(null);
						atype = Libffi.POINTER;
						break;
					}
					slot.set_pointer((void*) this.request.connection.leases.get(id));
					atype = Libffi.POINTER;
					break;
```

ℹ️ Matches Gi OBJECT IN resolve (`Gi.vala` ~1295–1335), without GIR
`may_be_null` / alias checks — Ffi Helpers are not typelib-gated that way.
Missing lease uses the same `reply_error` pattern as `Ffi.dispatch` for
instance `lease_id`.

---

## Non-goals

- Changing Gi lease packing
- Editing gnome-shell-rpc Helpers to take `uint64` instead of objects

---

## Attempts / changelog

- ✔️ 2026-09-14 — Applied `pack("o")` lease resolve in `libocrpc/Ffi.vala`
  (OBJECT → `get_object()`; UINT64 → `leases.get` / id `0` null / missing
  `reply_error(INVALID_PARAMS)`).

## Next

✔️ Applied `pack("o")` lease resolve in `libocrpc/Ffi.vala`.  
✔️ Moved to `docs/bugs/done/2026-09-14-FIXED-ffi-o-does-not-resolve-lease.md`.
