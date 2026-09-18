# test-rpc-t2 File.write never replies (JSON `0` vs FFI `uint`)

**Status:** ⏳ root cause confirmed; fix proposed — await apply approval  
**Hit:** 2026-09-18 — `meson test -C build --suite rpc`  
**Component:** `libocrpc/Ffi.vala` `pack`  
**Gate:** `meson test -C build test-rpc-t2`

---

## Problem

🔷 `meson test --suite rpc` must be green.

🔷 `test-rpc-t2` fails `T2A.1 File.write (no error)`: script request id 6
(`RPC-File.rpc_write`) never gets a `Response` line. Expected `{ msg: "ok" }`.
Actual stdout has ids 1–5, 7, 99; no id 6.

Reproduce:

```bash
unset G_MESSAGES_DEBUG
meson test -C build test-rpc-t2 --print-errorlogs
```

---

## Evidence

- ℹ️ `tests/rpc/t2-scan.script.in` id 6:

```
RPC-File.rpc_write args [path, "hello from rpc fixture\n", "f", "", 0]
```

- ℹ️ `add_class` signature is `"ssssu"` (`ollmfilesd/File.vala`). A production
  client builds that last arg with `OLLMrpc.args("ssssu", …, unix_mode)` so the
  `GLib.Value` is `UINT`. The NDJSON harness does not — JSON `0` is decoded
  by `Bin/Json.vala` `json_array_to_bin` as `GLib.Type.INT` (any integer in
  `int.MIN`–`int.MAX`).
- ✔️ stderr on the original fail:

```
GLib-GObject : g_value_get_uint: assertion 'G_VALUE_HOLDS_UINT (value)' failed
```

- ℹ️ `Ffi.pack("u")` calls `val.get_uint()` with no coerce. `Gi.convert` already
  transforms to `UINT` before `get_uint()`. Listed FFI and GI therefore disagree
  on the same JSON number.
- ℹ️ `StdioConnection.drain_script_request` waits for a `Response` with that id,
  then gives up when `MainContext.iteration(true)` returns false (no sources).
  No reply → the script continues with id 7 / 99. Later sqlite asserts do not
  prove write replied — `File.register` already inserted the row.
- ✔️ `File.write()` already does `args.get(4).transform` to `uint` for its own
  locals. That never runs if `pack("u")` criticals first — `cif.call` still
  happens, but the handler is not a reliable reply path after the assertion.

---

## Root cause

✔️ Listed FFI `"u"` (and the other numeric D-Bus letters) pack JSON/bin
`INT` with `get_uint()` / `get_int64()` / … and no `GLib.Value.transform`.
GI already coerces. NDJSON `0` is `INT`, so `pack("u")` hits
`g_value_get_uint` and id 6 never replies.

---

## Proposed fix

💩 Insert the same coerce `Gi.convert` already uses, at the start of
`Ffi.pack`, before the existing `switch (tag)`. Map D-Bus letters to the
GType `Gi.convert` wants (`"u"`/`"q"` → `UINT`, `"n"` → `INT`, …). If the
inbound Value is already that type, do nothing. If `transform` fails,
`reply_error(INVALID_PARAMS)` then still assign the typed Value so the
existing `get_*` calls do not critical.

🚫 Do not change `pack` from `void` to `bool`. 🚫 Do not touch `dispatch`
call sites. 🚫 Do not rewrite the NDJSON `0` or drop `unix_mode` from the
script — production wire is `"ssssu"`. 🚫 Do not `g_return` / swallow the
critical without coerce.

### 1. `libocrpc/Ffi.vala` — `pack()`: coerce numeric tags like `Gi.convert`

**Why:** JSON numbers decode as `INT`; listed FFI `"u"` is `UINT`. Same
transform GI already does.
**Where:** `internal void pack(...) {`, immediately before the existing
`switch (tag) {`.

#### Add — coerce block before `switch (tag)`

Copy of `Gi.convert`'s want + `transform` (D-Bus letters instead of
`GI.TypeTag`). `pack` stays `void`; on transform failure still `val = coerced`
so the existing `get_uint()` is typed.

```vala
			var want = GLib.Type.INVALID;
			switch (tag) {
				case "b":
					want = GLib.Type.BOOLEAN;
					break;

				case "y":
					want = GLib.Type.UCHAR;
					break;

				case "n":
					want = GLib.Type.INT;
					break;

				case "q":
				case "u":
					want = GLib.Type.UINT;
					break;

				case "x":
					want = GLib.Type.INT64;
					break;

				case "t":
					want = GLib.Type.UINT64;
					break;

				case "f":
					want = GLib.Type.FLOAT;
					break;

				case "d":
					want = GLib.Type.DOUBLE;
					break;
			}
			if (want != GLib.Type.INVALID && val.type() != want) {
				var coerced = GLib.Value(want);
				if (!val.transform(ref coerced)) {
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
				}
				val = coerced;
			}
```

---

## Attempts / changelog

- ✔️ 2026-09-18 — suite 19/21; t2 id 6 missing; `g_value_get_uint` in t2-scan
  stderr.
- 🚫 Changing `pack` to `bool`, dummy `POINTER` slot, and `if (!this.pack)`
  in `dispatch` — extra machinery, not the coerce. Reverted.

## Next

- ⏳ 💩 Approve §1, then apply. Gate: `meson test -C build test-rpc-t2`.
