# test-rpc-t2 File.write never replies (JSON `0` vs FFI `uint`)

**Status:** ⏳ root cause confirmed; previous coerce-map proposal 🚫; rewrite await apply  
**Hit:** 2026-09-18 — `meson test -C build --suite rpc`  
**Component:** `libocrpc/Ffi.vala` `pack` `"u"`  
**Gate:** `meson test -C build test-rpc-t2`

---

## Problem

🔷 `test-rpc-t2` id 6 (`RPC-File.rpc_write`) never gets a `Response`. stdout has 1–5, 7, 99.

```bash
unset G_MESSAGES_DEBUG
meson test -C build test-rpc-t2 --print-errorlogs
```

---

## What is actually wrong

JSON has one number type. Listed FFI `"u"` does not.

Script (last arg is JSON `0`):

```
RPC-File.rpc_write args [path, "hello…", "f", "", 0]
```

`Bin/Json.vala` boxes that `0` as `INT`:

```vala
if (i64 >= int.MIN && i64 <= int.MAX) {
    var int_val = GLib.Value(typeof(int));
    int_val.set_int((int) i64);
    StreamValue.write(bin, int_val);
```

Production client boxes `"u"` as `UINT`:

```vala
args = OLLMrpc.args("ssssu", this.path, write_content, base_type, target, unix_mode)
```

```vala
case "u":
    var u_val = GLib.Value(typeof(uint));
    u_val.set_uint(l.arg<uint>());
```

`Ffi.pack("u")` then requires `UINT`:

```vala
case "u":
    slot.set_uint32(val.get_uint());  // g_value_get_uint: G_VALUE_HOLDS_UINT
```

NDJSON `0` is `INT` → assertion → id 6 never replies.

GI already transforms before the same getter. Listed FFI does not.

`File.write()` also transforms for its own local — that never runs if `pack` criticals first:

```vala
var unix_mode_val = GLib.Value(typeof(uint));
request.args.get(4).transform(ref unix_mode_val);
var unix_mode = unix_mode_val.get_uint();
```

---

## Proposed fix

💩 Same three lines as `File.write`, inside the existing `"u"` case. Not a second type map.

🚫 Do not copy `Gi.convert`'s `want` switch in front of `pack`.  
🚫 Do not change `pack` to `bool`.  
🚫 Do not rewrite the script `0`. Wire is `"ssssu"`.

### 1. `libocrpc/Ffi.vala` — `pack` `"u"`: transform then `get_uint`

**Where:** `case "u":` in `pack()`.

#### Replace

```vala
				case "u":
					slot.set_uint32(val.get_uint());
					atype = Libffi.UINT32;
					break;
```

#### Replace with

```vala
				case "u":
					var u = GLib.Value(typeof(uint));
					val.transform(ref u);
					slot.set_uint32(u.get_uint());
					atype = Libffi.UINT32;
					break;
```

---

## Attempts / changelog

- ✔️ 2026-09-18 — t2 id 6 missing; `g_value_get_uint` in stderr.
- 🚫 `pack` → `bool` + dummy slot + `if (!this.pack)` in `dispatch`. Reverted.
- 🚫 Copy `Gi.convert` coerce map before `switch (tag)`. User veto — replica of the type map `pack` already has.

## Next

- ⏳ 💩 Approve §1, then apply. Gate: `meson test -C build test-rpc-t2`.
