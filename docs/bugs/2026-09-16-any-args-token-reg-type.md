# ANY[] does not consume `TOKEN_REG_TYPE`

**Status:** ✔️ applied in libocrpc; in-tree RPC suite green except flaky `test-rpc-t2` — await gnome-shell-rpc `hook-o-gate` verify  
**Hit:** 2026-09-16 — gnome-shell-rpc sent a live actor in a callback and the
client process died (`unsupported bin array type 0x7F`)  
**Component:** `libocrpc` — type-byte position on `ANY[]` (`Invoke.args` /
`Request.args` / `Response.args`)  
**Gate:** `gnome-shell-rpc/tests/call-sync-repro/hook-o-gate.vala`  
**Files:** `libocrpc/Bin/StreamValue.vala`, `libocrpc/Bin/Stream.vala`

---

## Problem

🔷 First time a class alias appears on a connection, `write_gtype` prefixes
`TOKEN_REG_TYPE` (`0xFF 0xFE` + id + alias) **before** the real type byte
(`0x50` object, or `0xD0` object array).

🔷 `parse()` and `bin_read` already skip that intro, then read the type byte.
`ANY[]` element loops do not: they treat the first byte as a type and pass it
to `StreamValue.read`.

🔷 Expected: callback `args` `"od"` decodes the live object, then the double.  
🔷 Actual: client `GLib.error` — `unsupported bin array type 0x7F`.

Reproduce:

```bash
meson compile -C build hook-o-gate
timeout 5 ./build/tests/call-sync-repro/hook-o-gate
```

```
server: emit od BEGIN
** ERROR **: Client.vala:659: unsupported bin array type 0x7F
```

---

## Why the old title was wrong

ℹ️ The live `Peer` / actor is only how this showed up. Any first-use object
inside `ANY[]` (Serializable or live) emits the same intro.

- ✔️ `Bin.register("Gate-Peer", …)` is process-wide alias → GType. It does
  **not** put the alias in this connection’s name table.
- ✔️ `write_reg_gtype` emits `0xFF 0xFE …` only when `name_to_token` does not
  yet have that alias (`Stream.vala`).
- ✔️ Later uses of the same class skip the intro and start at `0x50`. Those
  `ANY[]` elements already decode.
- ✔️ `Response.retval = an object` works because the object sits on a
  **property**: `bin_read` eats `0xFF` before `StreamValue.read`.
- ✔️ Existing GI hooks that pass a **lease uint64** never call `write_gtype`,
  so they never emit `TOKEN_REG_TYPE`.

---

## Evidence

ℹ️ Writer payload for `"od"` (hook-o-gate 2026-09-16, 34 bytes):

```
FF FE 01 09 47 61 74 65 2D 50 65 65 72 50 01 00
00 00 00 00 00 00 03 FF FD 3C 3F F8 00 00 00 00
00 00
```

```
FF FE                         TOKEN_REG_TYPE (name registration)
01                            name id 1
09                            alias length 9
47 61 74 65 2D 50 65 65 72    "Gate-Peer"
50                            G_TYPE_OBJECT
01                            use name id 1
00 00 00 00 00 00 00 03       lease 3
FF FD                         TOKEN_END
3C                            double
3F F8 00 00 00 00 00 00       1.5
```

Same read `Invoke` uses, before the client:

```
server: Invoke.args first type byte 0xFF
server: StreamValue.read unsupported bin array type 0x7F
```

✔️ `0x7F` is `0xFF` with the array bit stripped. `StreamValue.read` saw bit 7
set and tried `read_array`. There was never an array.

Readers that already skip `0xFF` at type-byte position:

- ℹ️ `Stream.parse`
- ℹ️ `Serializable.bin_read`
- ℹ️ `Json.bin_to_json` / `bin_to_json_object`

Readers that do not (`read_byte` → `StreamValue.read`):

- ℹ️ `Live.Invoke.bin_read_prop` `args`
- ℹ️ `Request.bin_read_prop` `args`
- ℹ️ `Response.bin_read_prop` `args`

ℹ️ Protocol (`docs/bin-rpc-protocol.md` §5) currently says only `parse()` and
`bin_read` do the skip. `write_gtype` still prefixes the intro in front of
every first-use object, including `StreamValue.write` for `ANY[]`.

---

## Root cause

✔️ `TOKEN_REG_TYPE` is a type-byte-position token (`0xFF` reserved — see
`Stream.TYPE_NAME_REF_REG` comment). `StreamValue.read` is that codec for
positional values and does not consume it.

🚫 Not a live-handle / lease encoding bug. The object body after `0x50` is
fine. The reader never reaches `0x50`.

---

## Proposed fix

🔷 When `StreamValue.read` is handed a type byte, treat `0xFF` the same way
`parse` and `bin_read` already do: `read_reg_gtype()`, then read the real
type byte and continue.

One place covers `Invoke.args`, `Request.args`, and `Response.args`.

🚫 Do not tell consumers to send a lease number instead. The writer already
sent the object.

ℹ️ Json `ANY[]` (`Json.bin_member_to_json`) has the same `read_byte` loop and
does not go through `StreamValue.read` for objects. Json currently refuses
object elements on write. Out of this gate.

### 1. `libocrpc/Bin/StreamValue.vala` — `read`

#### Remove

```vala
		public static GLib.Value read(Stream ctx, uint8 type_byte) throws GLib.Error
		{
			if ((GLib.Type) (type_byte & 0x7F) == GLib.Type.BOXED) {
```

#### Replace with

```vala
		public static GLib.Value read(Stream ctx, uint8 type_byte) throws GLib.Error
		{
			if (type_byte == 0xFF) {
				ctx.read_reg_gtype();
				type_byte = ctx.in_stream.read_byte();
			}
			if ((GLib.Type) (type_byte & 0x7F) == GLib.Type.BOXED) {
```

Same single skip as `Stream.parse` / `Serializable.bin_read`.

### 2. `docs/bin-rpc-protocol.md` §5 — type alias introduction

#### Remove

```text
On read, `parse()` and `bin_read` use a single `if (b == 0xFF) read_reg_gtype()` before the type byte.
```

#### Replace with

```text
On read, `parse()`, `bin_read`, and `StreamValue.read` use a single `if (b == 0xFF) read_reg_gtype()` before the type byte. That includes `ANY[]` elements (`Request.args` / `Response.args` / `Invoke.args`).
```

---

## After the fix

```bash
timeout 5 ./build/tests/call-sync-repro/hook-o-gate
```

Expect **PASS**: client `get_object()` is the same `Peer` that `make`
returned.

---

## Attempts / changelog

- ⏳ 2026-09-16 — FAIL gate from gnome-shell-rpc. No libocrpc code
  change from that tree.
- ✔️ 2026-09-16 — retitled: this is missing `TOKEN_REG_TYPE` consume on
  `ANY[]`, not a live-object codec hole.
- ✔️ 2026-09-16 — `StreamValue.read` consumes `0xFF` via `read_reg_gtype()`;
  protocol §5 names `StreamValue.read` / `ANY[]`.
- ✔️ 2026-09-16 — `meson test -C build --suite rpc`: 17/19 in sandbox
  (`test-rpc-bin`, `test-rpc-values`, `test-rpc-callback`, live/gi/http OK).
  `test-rpc-t1` OK unsandboxed. `test-rpc-t2` flakes SIGTRAP on
  write-persist/delete isolation (same crash with the skip reverted; first
  run with the skip was OK).
- ⏳ `hook-o-gate` lives in gnome-shell-rpc — not in this tree.
