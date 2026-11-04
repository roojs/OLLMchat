# Empty ArrayList encode aborts; TlsClient hits a null connection

**Status:** ✔️ applied — empty ArrayList is count `0` with no list type; `TlsClient` reads `Stream.live_handles`

**Pointer:** `docs/bug-fix-process.md`. `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala must follow `docs/coding-standards.md`.

ℹ️ Filed from Argus. `docs/bugs/done/2026-11-02-FIXED-tls-one-shot-rpc.md` said libocrpc is not edited from the Argus tree. This is that library report.
ℹ️ Argus log: `/home/alan/gitlive/argusrm/docs/bugs/2026-11-04-osquery-sync-kills-agent.md`.

---

## Problem

- 🔷 `Bin.StreamValue.write` cannot encode an empty `Gee.ArrayList` of objects.
  - `list.get(0)` is a libgee `g_assert`.
  - The process aborts.
- 🔷 An empty object array is count `0` and has **no list type** on the wire.
  - The reader must accept that.
  - It must not call `read_gtype`.
- 🔷 `Transport.TlsClient.call` encodes the same arrays on a `Bin.Stream` that has no `Transport.Connection`.
  - `StreamValue` reads `ctx.connection.live_handles`.
  - That is `oll_mrpc_transport_connection_get_live_handles: assertion 'self != NULL' failed`.
- 🔷 Argus `OSQuery.sync` sends one array per table, including `[]`.
  - That is a supported `Request` argument, not a live handle.
  - The Linux `--service` process dies on the first empty table.

---

## Why this is a libocrpc bug

- 💩 Argus cannot write a different wire shape. `TlsClient.call` → `Bin.Stream.write` → `StreamValue.write` is the only encoder for a `Request` `o` argument that is an `ArrayList`.
- 💩 Skipping an empty call in Argus would hide this. The server would keep stale rows.
- 💩 Putting a dummy `Transport.Connection` on `TlsClient` would only silence the critical. It would not stop `get(0)` from aborting.
- 💩 `Stream.parse_object_array` always `read_gtype()` then count.
  - That is the reading bug.
  - Count `0` has no element type, so that read is wrong.
- 💩 `Stream.live_handles` already exists. `TlsClient` leaves it false. `StreamValue` ignores that flag and reads `connection` instead.
- ℹ️ `TlsClient` was added in `docs/bugs/done/2026-11-02-FIXED-tls-one-shot-rpc.md` so callers do not copy the TLS loop. Its stream has no connection by design.

---

## Evidence

- ✔️ `libocrpc/Bin/StreamValue.vala` ArrayList branch:
  - `ctx.write_gtype(list.get(0).get_type(), …)`
  - then count
  - then `ctx.connection.live_handles` for each child
- ✔️ `libocrpc/Bin/Stream.vala` `parse_object_array`:
  - `read_gtype()` then count
  - An empty body (`0xD0` + `0`) is not accepted
- ✔️ libgee `ArrayList.get` is `assert (index < _size)`. Empty is abort, not `Error`.
- ✔️ `Transport.TlsClient` default stream is `new Bin.Stream(null, null, false)`.
  - `open` sets the I/O streams only.
  - No `connection`. No `live_handles`.
- ✔️ Argus agent log: two `get_live_handles` criticals, then the process is gone.
  - Server got two `OSQuery.sync` calls, then `TLS connection closed unexpectedly`.
- ✔️ On the reporter machine `osqueryi --json 'SELECT * FROM logged_in_users'` is `[]`.

---

## Root cause

- ✔️ The ArrayList encoder assumes a non-empty list so it can take a type from `get(0)`.
- ✔️ The ArrayList decoder assumes a list type is always present.
- 🔷 The rule: empty is count `0` and has no list type.
- ✔️ `TlsClient` has no `Transport.Connection`. The live-handles critical is that read.

---

## Proposed fix

- 🔷 Object array body is count first, then the list type only when count is not `0`.
- 🔷 Empty write: `0xD0`, count `0`, stop.
- 🔷 Empty read: count `0`, return. No `read_gtype`.
- 🚫 Do not invent a list type for empty (`list.element_type` or a dummy class).
- 🚫 Do not copy `read_gtype` into `parse_object_array`.
- 💩 `StreamValue` reads `ctx.live_handles`, not `ctx.connection.live_handles`.
  - Live lease ids still use `ctx.connection`. That path only runs when the flag is on.
- 💩 `Connection.start` and `Client` connect copy `live_handles` onto the stream.
- 🚫 Do not null-check `ctx.connection` to hide the critical.
- 🚫 Do not add a dummy connection on `TlsClient`.
- 🚫 Do not change Argus in this log.

### `libocrpc/Bin/StreamValue.vala` — empty write is count 0, no type

**Why:** `get(0)` aborts. Empty has no list type.

**Where:** `write`, the `Gee.ArrayList` branch, before `write_gtype`.

**Depends on:** `parse_object_array` below.

#### Remove

```vala
			if (val.type().is_a(typeof(Gee.ArrayList))) {
				var list = (Gee.ArrayList<GLib.Object>) val.get_object();
				ctx.write_gtype(list.get(0).get_type(),
					(uint8) GLib.Type.OBJECT | 0x80);
				if (list.size < 128) {
					ctx.out_stream.put_byte((uint8) list.size);
				} else {
					ctx.out_stream.put_byte(
						(uint8) (0x80 | ((list.size >> 8) & 0x7F)));
					ctx.out_stream.put_byte((uint8) (list.size & 0xFF));
				}
```

#### Replace with

```vala
			if (val.type().is_a(typeof(Gee.ArrayList))) {
				var list = (Gee.ArrayList<GLib.Object>) val.get_object();
				if (list.size == 0) {
					ctx.out_stream.put_byte((uint8) GLib.Type.OBJECT | 0x80);
					ctx.out_stream.put_byte(0);
					return;
				}
				ctx.write_reg_gtype(list.get(0).get_type());
				ctx.out_stream.put_byte((uint8) GLib.Type.OBJECT | 0x80);
				if (list.size < 128) {
					ctx.out_stream.put_byte((uint8) list.size);
				} else {
					ctx.out_stream.put_byte(
						(uint8) (0x80 | ((list.size >> 8) & 0x7F)));
					ctx.out_stream.put_byte((uint8) (list.size & 0xFF));
				}
				var reg_id = (uint) ctx.name_to_token.get(
					gtype_to_alias.get(list.get(0).get_type())
				);
				if (reg_id < 128) {
					ctx.out_stream.put_byte((uint8) reg_id);
				} else {
					ctx.out_stream.put_byte(
						(uint8) (0x80 | ((reg_id >> 8) & 0x7F)));
					ctx.out_stream.put_byte((uint8) (reg_id & 0xFF));
				}
```

#### Remove

```vala
					if (!ctx.connection.live_handles || child.get_type().is_a(typeof(Serializable))) {
```

#### Replace with

```vala
					if (!ctx.live_handles || child.get_type().is_a(typeof(Serializable))) {
```

#### Remove

```vala
				if (!val.get_object().get_type().is_a(typeof(Serializable))
					&& ctx.connection.live_handles) {
```

#### Replace with

```vala
				if (!val.get_object().get_type().is_a(typeof(Serializable))
					&& ctx.live_handles) {
```

### `libocrpc/Bin/Stream.vala` — empty read is count 0, no type

**Why:** The reader must accept the empty write. Count `0` has no `read_gtype`.

**Where:** `parse_object_array`.

**Depends on:** the empty write above.

#### Remove

```vala
		public Gee.ArrayList<GLib.Object> parse_object_array()
			throws GLib.Error
		{
			var elem_gtype = this.read_gtype();
			var count = (uint) this.in_stream.read_byte();
			if ((count & 0x80) != 0) {
				count = ((count & 0x7F) << 8) | this.in_stream.read_byte();
			}
			var list = new Gee.ArrayList<GLib.Object>();
			for (var i = 0u; i < count; i++) {
				list.add(this.parse_object(elem_gtype));
			}
			return list;
		}
```

#### Replace with

```vala
		public Gee.ArrayList<GLib.Object> parse_object_array()
			throws GLib.Error
		{
			var count = (uint) this.in_stream.read_byte();
			if ((count & 0x80) != 0) {
				count = ((count & 0x7F) << 8) | this.in_stream.read_byte();
			}
			var list = new Gee.ArrayList<GLib.Object>();
			if (count == 0) {
				return list;
			}
			var elem_gtype = this.read_gtype();
			for (var i = 0u; i < count; i++) {
				list.add(this.parse_object(elem_gtype));
			}
			return list;
		}
```

### `libocrpc/Transport/Connection.vala` — copy live_handles onto the stream

**Why:** After `StreamValue` reads `Stream.live_handles`, a live listen must still see the flag.

**Where:** `start`, the `Bin.Stream` construction.

**Depends on:** StreamValue live-flag change above.

#### Remove

```vala
				this.bin = new Bin.Stream(in_stream, out_stream, true) {
					connection = this
				};
```

#### Replace with

```vala
				this.bin = new Bin.Stream(in_stream, out_stream, true) {
					connection = this,
					live_handles = this.live_handles
				};
```

### `libocrpc/Client.vala` — copy live_handles onto the stream

**Why:** The same stream flag is what encode will read.

**Where:** connect, the `Bin.Stream` construction.

**Depends on:** StreamValue live-flag change above.

#### Remove

```vala
			this.bin = new Bin.Stream(this.input, this.output) {
				client = this
			};
```

#### Replace with

```vala
			this.bin = new Bin.Stream(this.input, this.output) {
				client = this,
				live_handles = this.live_handles
			};
```

---

## Attempts / changelog

- 🔷 User: do not edit libocrpc from the Argus tree. File a library bug and justify it.
- 🔷 User: empty array is count `0` and has no list type. That is a reader accept rule. Do not invent `element_type`.
- ✔️ Applied `StreamValue` empty write (`0xD0` + count `0`), count-then-type for non-empty, `parse_object_array` accepts that, `live_handles` is the stream flag.
- ✔️ `write_reg_gtype` stays before `0xD0` on the non-empty path. After count it would sit where `read_gtype` expects `reg_id`; a fresh `TlsClient` name table always introduces the alias first.

---

## Next

- 🔷 `⏳` Rebuild / install `ocrpc`. Argus then rebuilds against it.
- 🔷 `⏳` Confirm Argus `OSQuery.sync` with an empty table no longer kills `--service`.
