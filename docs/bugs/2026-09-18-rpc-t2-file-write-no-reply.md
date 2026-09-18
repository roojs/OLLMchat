# test-rpc-t2 File.write never replies (JSON `0` vs FFI `uint`)

**Status:** 🌗 pack `"u"` transform + script drain wait applied; gate still SIGTRAP later in the suite  
**Hit:** 2026-09-18 — `meson test -C build --suite rpc`  
**Component:** `libocrpc/Ffi.vala` `pack` `"u"`; `ollmfilesd/StdioConnection.vala` `drain_script_request`  
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

`Bin/Json.vala` boxes that `0` as `INT`. Production client boxes `"u"` as `UINT`. `Ffi.pack("u")` then `get_uint()` on `INT` → GLib critical.

That critical does **not** abort. `rpc_write` still `write.begin`s. The missing reply is the script drain:

- `StdioConnection.drain_script_request` waited with `iteration(true)` and **broke** when it returned false.
- GIO `replace_async` in `File.realize` is often not pending yet on that first iterate.
- Drain continues to id 7 / 99. Id 6 reply never lands.

`--debug` slows the loop enough that id 6 usually appears. Without debug, t2-scan id 6 was flaky after the `"u"` transform alone.

`File.write()` also transforms arg 4 for its own local — that never runs if pack criticals first; after pack, it still needs drain to wait for the async reply.

---

## Applied

### 1. `libocrpc/Ffi.vala` — `pack` `"u"`: transform then `get_uint` ✔️

**Where:** `case "u":` in `pack()`. Same three lines as `File.write`. Not a second type map.

```vala
				case "u":
					var u = GLib.Value(typeof(uint));
					val.transform(ref u);
					slot.set_uint32(u.get_uint());
					atype = Libffi.UINT32;
					break;
```

🔷 User accepted this hunk.

### 2. `ollmfilesd/StdioConnection.vala` — drain until the reply ✔️

**Where:** `drain_script_request`.

Removed the `if (!iteration(true)) break`. Wait until `script_awaiting_id` clears (a `Response` with that id was written).

💩 Not in the original §1 hunk. Needed once pack stopped critical-ing: id 6 is async `write.begin` / GIO. t2-scan id 6 then replies (`msg=ok`).

---

## Attempts / changelog

- ✔️ 2026-09-18 — t2 id 6 missing; `g_value_get_uint` in stderr.
- 🚫 `pack` → `bool` + dummy slot + `if (!this.pack)` in `dispatch`. Reverted.
- 🚫 Copy `Gi.convert` coerce map before `switch (tag)`. User veto — replica of the type map `pack` already has.
- ✔️ Apply §1 `pack("u")` transform.
- ✔️ After §1: no `g_value_get_uint`. t2-scan id 6 flaky (1/5 miss without `--debug`; `--debug` always had id 6).
- ✔️ Drain wait until reply. t2-scan / persist / delete scripts reply id 6 when run alone.

---

## Still open

- ⏳ 💩 `pack("x")` is the same JSON `INT` vs `INT64` hole (`changed.check` `"sx"` with script `0`). `g_value_get_int64` still in persist/dirty stderr. Same three-line transform as `"u"`. Not applied — user asked `"u"` only.
- ⏳ 🔷 `meson test -C build test-rpc-t2` still **SIGTRAP** (~0.19s) in the full script (later isolated persist/delete). Single-script runs of those cases exit 0. Separate from id 6. `G_DEBUG=fatal-criticals` traps on the expected `RPC-File.activate` critical (test already asserts that stderr line).
- ℹ️ `rpc_delete` can `remove.begin(null)` when `get_file_from_active_project` misses (`filebase != NULL` critical). Not this cut.

## Next

- ⏳ Confirm drain + `"u"` on device, or revert drain if that wait is the wrong layer.
- ⏳ 💩 `"x"` transform if persist/dirty criticals should die too.
- ⏳ Full `test-rpc-t2` SIGTRAP as its own log if it is not this write/int issue.
