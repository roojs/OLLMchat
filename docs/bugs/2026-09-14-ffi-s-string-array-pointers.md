# Ffi `"S"` length ok but element pointers ≠ wire `GStrv`

**Status:** ✔️ applied + in-tree `test-rpc-ffi-as` PASS — await user verify  
**Hit:** 2026-09-14 — gnome-shell-rpc nest `Helper-WaylandClient.spawnv`  
**Component:** `libocrpc` / `OLLMrpc.Ffi.dispatch` (`"S"` / `pack("as")`)  
**Prior (length):** [`done/2026-09-14-FIXED-ffi-s-string-array-length.md`](done/2026-09-14-FIXED-ffi-s-string-array-length.md)  
**In-tree gate:** `meson test -C build test-rpc-ffi-as` (`tests/rpc/ffi-as-test.vala`)  
**Consumer gate:** `gnome-shell-rpc/tests/call-sync-repro/ffi-as-string-array-gate`  
**Related:** `libocrpc/Ffi.vala`

---

## Problem

🔷 `"S"` now sets Vala array **length** correctly (`ffi_len=4`).

🔷 Ffi-handed `string[]` **element pointers do not match** the wire
`request.args` `GStrv`. Gate `match=0`. GDB: `items_length1=4` but
`items[0]` unreadable / garbage; Vala `string[] wire = items` SEGV in
`g_strdup`.

🔷 Consumer nest: Helper logs `argv_len=4` → mutter
`meta_wayland_client_spawnv` assert `argv[0][0] != '\0'`.

🔷 Expected: `"S"` pointer slot is a live null-terminated `GStrv` for the
duration of `cif.call` (same contents as `request.args`), so
indexing/`g_strdup` is safe.

---

## Evidence

From gnome-shell-rpc tree:

```bash
meson compile -C build ffi-as-string-array-gate
timeout 5 ./build/tests/call-sync-repro/ffi-as-string-array-gate
```

```
server echo_S ffi_len=4 req_len=4 match=0 …
FAIL … OPC Ffi "S" length=4 but element pointers != wire GStrv (match=0)
```

`Ffi.vala` `"S"` path (current shape):

```vala
this.pack("as", as_val, ref slots[2 + si], out atypes[2 + si], pin);
slots[2 + si + 1].set_int32(((string[]) as_val).length);
```

`pack("as")` (current):

```vala
case "as":
case "ay":
    slot.set_pointer(val.get_boxed());
    atype = Libffi.POINTER;
    break;
```

Generated C (`build/libocrpc/.../Ffi.c`):

- ✔️ `"S"` branch: `gee_abstract_list_get` → owned `GValue* as_val`;
  `pack("as")` → `g_value_get_boxed` into the libffi slot; length via
  `g_strv_length` on that boxed pointer.
- ✔️ Same branch then `__vala_GValue_free0 (as_val)` (`g_boxed_free
  (G_TYPE_VALUE, …)` → `g_value_unset` → `g_strfreev`) **before** the
  packing loop finishes.
- ✔️ `ollmrpc_ffi_call_void` / `cif.call` runs **after** that free
  (~line 1854 free vs ~2052 call).

ℹ️ Scalar `"s"` already pins: `pin.add(held)` because `val` is by-value
and would otherwise dangle. `"as"` has no equivalent pin.

---

## Root cause

✔️ Length was fixed by casting the `GLib.Value`, but the pointer slot
still aliases `get_boxed()` on a **temporary owned copy** of the arg
Value (`args.get` → free at end of the `"S"` iteration). That frees the
`GStrv` before `cif.call`, so the Helper sees length 4 and garbage
element pointers (`match=0` / SEGV). Same class of bug as unpinned
`"s"` — `"as"` never got a pin list.

---

## Proposed fix

🔷 Pin an **owned** `string[]` for the duration of `cif.call` (mirror
`pin` for strings). `pack("as")` must `GLib.strdupv` (or equivalent
owned copy), store it on a `Gee.ArrayList<string[]>` kept until after
the call, and hand **that** pointer to libffi. `"S"` length should come
from the **same** pinned array.

🚫 Consumer workarounds in gnome-shell-rpc.  
🚫 Changing wire / `StreamValue` string[] encode.  
🚫 Leaving `get_boxed()` unpinned (reproduces this FAIL).

### 1. `libocrpc/Ffi.vala` — pin owned `string[]` for `"as"` / `"S"`

#### Remove (`pack` signature + `"as"`/`"ay"` case)

```vala
		internal void pack(
			string tag,
			GLib.Value val,
			ref Libffi.Arg slot,
			out Libffi.Type atype,
			Gee.ArrayList<string> pin
		) {
```

```vala
				case "as":
				case "ay":
					slot.set_pointer(val.get_boxed());
					atype = Libffi.POINTER;
					break;
```

#### Replace with

```vala
		internal void pack(
			string tag,
			GLib.Value val,
			ref Libffi.Arg slot,
			out Libffi.Type atype,
			Gee.ArrayList<string> pin,
			Gee.ArrayList<GLib.Value?> pin_as
		) {
```

```vala
				case "as":
					var keep = GLib.Value(typeof(string[]));
					keep.set_boxed(GLib.strdupv((string[]) val));
					pin_as.add(keep);
					slot.set_pointer(pin_as.get(pin_as.size - 1).get_boxed());
					atype = Libffi.POINTER;
					break;

				case "ay":
					slot.set_pointer(val.get_boxed());
					atype = Libffi.POINTER;
					break;
```

ℹ️ Vala rejects `Gee.ArrayList<string[]>` (arrays are not generic type
args). Use `Gee.ArrayList<GLib.Value?>` + `add` (same container as
`Request.args`), owning a `strdupv` copy in the Value.

#### Remove (`dispatch` pin + `"S"` + other `pack` calls)

```vala
			var pin = new Gee.ArrayList<string>();
```

```vala
				if (rest.has_prefix("S")) {
					var as_val = this.request.args.get(ai);
					this.pack("as", as_val, ref slots[2 + si], out atypes[2 + si], pin);
					slots[2 + si + 1].set_int32(((string[]) as_val).length);
					atypes[2 + si + 1] = Libffi.SINT32;
					offset += 1;
					si += 2;
					ai += 1;
					continue;
				}
```

```vala
				this.pack(tag, this.request.args.get(ai), ref slots[2 + si], out atypes[2 + si], pin);
```

#### Replace with

```vala
			var pin = new Gee.ArrayList<string>();
			var pin_as = new Gee.ArrayList<GLib.Value?>();
```

```vala
				if (rest.has_prefix("S")) {
					var as_val = this.request.args.get(ai);
					this.pack("as", as_val, ref slots[2 + si], out atypes[2 + si], pin, pin_as);
					slots[2 + si + 1].set_int32(((string[]) pin_as.get(pin_as.size - 1)).length);
					atypes[2 + si + 1] = Libffi.SINT32;
					offset += 1;
					si += 2;
					ai += 1;
					continue;
				}
```

```vala
				this.pack(tag, this.request.args.get(ai), ref slots[2 + si], out atypes[2 + si], pin, pin_as);
```

ℹ️ Update `pack` docblock: `pin_as` owned `string[]` Values kept alive
until after `cif.call` (same rationale as `pin` for `"s"`). Split `"ay"`
so Bytes stay `get_boxed()` (unchanged this bug).

---

## Non-goals

- Consumer Helpers reading `request.args` instead of typed params
- Changing bin `StreamValue` string[] encode/decode
- Fixing Gi `convert_array` UTF8 alias lifetime (separate if hit)

---

## Attempts / changelog

- ⏳ 2026-09-14 — Filed from gate `match=0` after length-only fix.
- ✔️ 2026-09-14 — Root cause: `as_val` / boxed `GStrv` freed before
  `cif.call`; `"as"` lacks a pin (unlike `"s"`).
- ✔️ 2026-09-14 — Applied `pack("as")` pin via single `GLib.Value[]`
  (`resize` + index — Gi `value_keep` shape). `ArrayList<GLib.Value?>.get`
  frees a temporary Value and drops the boxed `GStrv` before `cif.call`
  (caught by new in-tree gate).
- ✔️ 2026-09-14 — Added `tests/rpc/ffi-as-test.vala` /
  `meson test -C build test-rpc-ffi-as` (length + element match).

## Next

✔️ Apply pin/`strdupv` fix in `libocrpc/Ffi.vala`.  
✔️ In-tree `test-rpc-ffi-as` PASS.  
⏳ Consumer gate optional cross-check.  
⏳ User verify → move to `docs/bugs/done/…-FIXED-…`.
