# Ffi `"S"` / `"as"` delivers empty Vala `string[]` (length lost)

**Status:** ⏳ fix applied — await consumer gate / user verify  
**Hit:** 2026-09-14 — gnome-shell-rpc `Helper-WaylandClient.spawnv`  
**Component:** `libocrpc` / `OLLMrpc.Ffi.dispatch` (`"S"` length + `"as"` pack)  
**Consumer:** gnome-shell-rpc Helpers with Vala length-bearing `string[]`  
**Gate (consumer):** `gnome-shell-rpc/tests/call-sync-repro/ffi-as-string-array-gate.vala`  
**Consumer bug:** `gnome-shell-rpc/docs/bugs/2026-09-14-ffi-as-string-array-empty.md`  
**Related:** `libocrpc/Ffi.vala`, `libocrpc/namespace.vala` (`OLLMrpc.args` docs for `"S"`)

---

## Problem

🔷 Wire and pack are fine: `OLLMrpc.args("as", payload)` → `GStrv`,
length 4; after bin decode, server `request.args[0]` still length 4.

🔷 `add_class` Helper methods typed as Vala `string[]` get **`ffi_len=0`**
for both signature `"as"` and `"S"`.

🔷 Boot symptom (gnome-shell-rpc): client `spawnv argv_len=4` → Helper
`argv_len=0` → `meta_wayland_client_spawnv` assert.

🔷 Expected: `"S"` packs pointer **and** Vala array length so the Helper
sees the same length as `request.args`. `"as"` is pointer-only (C GStrv /
no Vala length) — documented; Vala length-bearing params need `"S"`.

---

## Evidence

Gate (from gnome-shell-rpc tree):

```bash
meson compile -C build ffi-as-string-array-gate
timeout 5 ./build/tests/call-sync-repro/ffi-as-string-array-gate
```

2026-09-14 FAIL:

```
client pack type=GStrv
client payload len=4 packed args len=4
server echo_as ffi_len=0 req_args_len=4 args_size=1
server echo_S ffi_len=0 req_args_len=4 args_size=1
FAIL ffi-as-string-array-gate: echo_S ffi_len=0 want 4 (req_args_len=4)
```

`libocrpc/Ffi.vala` `"S"` path (current):

```vala
if (rest.has_prefix("S")) {
    this.pack("as", this.request.args.get(ai), ref slots[2 + si], out atypes[2 + si], pin);
    slots[2 + si + 1].set_int32(((string[]) this.request.args.get(ai).get_boxed()).length);
    atypes[2 + si + 1] = Libffi.SINT32;
    …
}
```

ℹ️ Casting **`get_boxed()`** (void*) to `string[]` does not restore Vala /
GStrv length. Casting the **`GLib.Value`** does — gate uses
`(string[]) v` on `request.args.get(0)` and gets 4.

`pack("as")` (current):

```vala
case "as":
case "ay":
    slot.set_pointer(val.get_boxed());
    atype = Libffi.POINTER;
    break;
```

Pointer-only is correct for `"as"`. Without a length slot, Vala
`string[]` params still compile to `(gchar**, int length)` → length
reads as 0 / garbage. That is why `"as"` alone fails for Helpers; `"S"`
must supply the length correctly.

---

## Root cause

✔️ Inbound `string[]` is present on `request.args` (GStrv / length 4).
`"S"` computes length via `((string[]) val.get_boxed()).length` → **0**,
so libffi passes length 0 into the Vala method. `"as"` never passes
length, so Vala length-bearing Helpers always see empty.

---

## Proposed fix

🔷 In `Ffi.dispatch` `"S"` branch: take length from the `GLib.Value`, not
from a void* cast of `get_boxed()`.

🚫 Consumer workarounds of reading `request.args` inside Helpers / spawnv.  
🚫 Changing wire / `StreamValue` string[] encode (already OK).  
🚫 Editing gnome-shell-rpc to invent launch APIs.

### 1. `libocrpc/Ffi.vala` — `"S"` length from `GLib.Value`

#### Remove

```vala
				if (rest.has_prefix("S")) {
					this.pack("as", this.request.args.get(ai), ref slots[2 + si], out atypes[2 + si], pin);
					slots[2 + si + 1].set_int32(((string[]) this.request.args.get(ai).get_boxed()).length);
					atypes[2 + si + 1] = Libffi.SINT32;
					offset += 1;
					si += 2;
					ai += 1;
					continue;
				}
```

#### Replace with

```vala
				if (rest.has_prefix("S")) {
					var as_val = this.request.args.get(ai);
					this.pack("as", as_val, ref slots[2 + si], out atypes[2 + si], pin);
					string[] arr = (string[]) as_val;
					slots[2 + si + 1].set_int32(arr.length);
					atypes[2 + si + 1] = Libffi.SINT32;
					offset += 1;
					si += 2;
					ai += 1;
					continue;
				}
```

ℹ️ Same cast the consumer gate uses for `req_args_len=4`. Prefer
`g_strv_length` only if Values are always null-terminated GStrv; the
`GLib.Value` cast matches current pack/`StreamValue` type (`GStrv`).

### 2. Docs / contract (optional, same PR)

🔷 Keep `"as"` = pointer only; `"S"` = pointer + Vala length (already in
`OLLMrpc.args` docs). Note that Vala `string[]` Helper params must use
`"S"` in `add_class` signatures.

---

## Non-goals

- Consumer Helpers reading `request.args` instead of typed params
- Changing bin `StreamValue` string[] encode/decode (gate proves wire OK)
- Making `"as"` invent a Vala length (that is what `"S"` is for)

---

## Attempts / changelog

- ⏳ 2026-09-14 — Filed from gnome-shell-rpc FAIL gate (pack/wire OK, Ffi empty).
- ✔️ 2026-09-14 — Applied `"S"` length from `(string[]) as_val` (GLib.Value
  cast), not `get_boxed()`, in `libocrpc/Ffi.vala`.

## Next

✔️ Apply `"S"` length fix in `libocrpc/Ffi.vala`.  
⏳ Consumer: `timeout 5 ./build/tests/call-sync-repro/ffi-as-string-array-gate`
→ expect `echo_S` PASS; `echo_as` may still FAIL (pointer-only — OK).  
⏳ Optionally tighten gate so PASS = `echo_S` only, or accept both when
`"as"` is defined not to feed Vala length.  
⏳ User verify → move to `docs/bugs/done/…-FIXED-…`.
