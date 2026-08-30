# 8.5.3 — `Response.retval`

> **Do not update `docs/plans/RPC-1.0-summary.md` for this plan.**

**Status:** **PROPOSED**

**Parent:** [`RPC-8.5-rpc-drop-callparam-reply-value.md`](done/RPC-8.5-rpc-drop-callparam-reply-value.md) — this is that file’s Phase 3. FFI handler walk is ✔️ there.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

**Related:** [`docs/bin-rpc-protocol.md`](../bin-rpc-protocol.md) §15. [`RPC-8.3.3-REJECTED-notification-gobject-payload.md`](done/RPC-8.3.3-REJECTED-notification-gobject-payload.md) — GObject `payload` on `Notification` stays withdrawn.

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

---

## Purpose

- **🔷** `⏳` Add `Response.retval` (`GLib.Value`). One payload: number, string, object, or object list.
- **🔷** `⏳` Leave `result` (`Gee.ArrayList<GLib.Object>`) as it is. Do not delete or retype it in this cut.
- **🔷** `⏳` Encode / decode `retval` with `StreamValue`.
- **🔷** `⏳` `StreamValue` writes live-handle objects and `typeof(Gee.ArrayList)` as `OBJECT|0x80` (`parse_object_array` on read).
- **ℹ️** Method migration and deleting `result` → [`RPC-8.5.4-rpc-retval-migrate.md`](RPC-8.5.4-rpc-retval-migrate.md).
- **ℹ️** `args` / `msg` / `msg_encode` unchanged. No protocol version bump.

---

## Shape

- **🔷** Property name `retval` (wire tag `retval`). Not `result`.
- **🔷** Unset (`GLib.Type.INVALID`) is omitted on the wire.
- **🔷** Empty `Gee.ArrayList` is omitted (same as empty `result` today).
- **🔷** One GObject → `set_object` (bare `OBJECT`). N GObjects → `GLib.Value(typeof(Gee.ArrayList)); set_object(list)` (`0xD0`).
- **🔷** List GType check is `val.type().is_a(typeof(Gee.ArrayList))`, not `get_object() is Gee.ArrayList`.
- **🔷** A method that still uses `result` does not also write `retval` “for compatibility”.
- **💩** `⏳` Notification `GLib.Value` — not this cut.

---

## Today

- **ℹ️** `result` is a never-null object list. Empty omitted. One row is a one-element list.
- **ℹ️** `StreamValue.write` throws if the object is not `Serializable` (no live-handle path).
- **ℹ️** Object arrays only work through `Response.result`, not `StreamValue.read`.

---

## Phase 1 — `StreamValue` (so `retval` can hold objects)

- **🔷** `⏳` Live-handle lease write in `StreamValue.write`.
- **🔷** `⏳` `typeof(Gee.ArrayList)` writes as today’s `result` object array.
- **🔷** `⏳` `OBJECT|0x80` in `read()` **before** `read_array`. `parse_object_array` reads gtype then count.

### 1. `libocrpc/Bin/StreamValue.vala` — `write`: live handle + `ArrayList`

**Why:** `retval` calls `StreamValue.write`. A GObject or object list must not throw.

**Where:** `write()`, the `GLib.Type.OBJECT` branch at the end (after FLAGS).

**Depends on:** none.

#### Remove

```vala
			if (val.type().is_a(GLib.Type.OBJECT)) {
				if (val.get_object() == null) {
					return;
				}
				if ((val.get_object() as Serializable) == null) {
					throw new StreamError.PROTOCOL(
						"value type '%s' is not Bin.Serializable",
						val.get_object().get_type().name()
					);
				}
				ctx.write_gtype(val.get_object().get_type());
				((Serializable) val.get_object()).bin_write(ctx);
				return;
			}
```

#### Replace with

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
				foreach (var child in list) {
					if (!ctx.connection.live_handles || child.get_type().is_a(typeof(Serializable))) {
						((Serializable) child).bin_write(ctx);
						continue;
					}
					var ptr = (uint64) (void*) child;
					ctx.out_stream.put_uint64((uint64) ctx.connection.lease_ids.get(
						(int) (ptr >> 32)).get((int) ptr));
					ctx.out_stream.put_uint16(Stream.TOKEN_END);
				}
				return;
			}
			if (val.type().is_a(GLib.Type.OBJECT)) {
				if (val.get_object() == null) {
					return;
				}
				if (!val.get_object().get_type().is_a(typeof(Serializable))
					&& ctx.connection.live_handles) {
					var live = val.get_object();
					ctx.write_gtype(live.get_type());
					var ptr = (uint64) (void*) live;
					ctx.out_stream.put_uint64((uint64) ctx.connection.lease_ids.get(
						(int) (ptr >> 32)).get((int) ptr));
					ctx.out_stream.put_uint16(Stream.TOKEN_END);
					return;
				}
				if ((val.get_object() as Serializable) == null) {
					throw new StreamError.PROTOCOL(
						"value type '%s' is not Bin.Serializable",
						val.get_object().get_type().name()
					);
				}
				ctx.write_gtype(val.get_object().get_type());
				((Serializable) val.get_object()).bin_write(ctx);
				return;
			}
```

**ℹ️** `typeof(Gee.ArrayList)` is a GObject GType, so it would also match `is_a(OBJECT)`. Test ArrayList **first**.

### 2. `libocrpc/Bin/StreamValue.vala` — `read`: `OBJECT|0x80`

**Why:** Object-array header is gtype then count. Must not enter numeric `read_array`.

**Where:** `read()`, immediately before `if ((type_byte & 0x80) != 0) { return StreamValue.read_array…`.

**Depends on:** ### 1.

#### Add — before the `read_array` call — decode an object list into `typeof(Gee.ArrayList)`

```vala
			if ((type_byte & 0x80) != 0
				&& (GLib.Type) (type_byte & 0x7F) == GLib.Type.OBJECT) {
				var objects = ctx.parse_object_array();
				var list_val = GLib.Value(typeof(Gee.ArrayList));
				list_val.set_object(objects);
				return list_val;
			}
```

---

## Phase 2 — add `retval`, keep `result`

- **🔷** `⏳` New property + `bin_write_prop` / `bin_read_prop` cases. `result` / `args` cases stay.

### 3. `libocrpc/Response.vala` — `retval` property

**Why:** Gradual path for any return. `result` stays the object-list property.

**Where:** class body, after `result`, before `args`. Class docblock: one `retval` example after Object result.

**Depends on:** ### 1, ### 2.

#### Add — after the `result` property (before `args`) — the `GLib.Value` return slot

```vala
		/**
		 * Typed return ({@link GLib.Value}).
		 *
		 * Unset ({@link GLib.Type.INVALID}) is omitted on the wire. A
		 * number or string uses the same {@link Bin.StreamValue}
		 * encoding as {@link args} elements. A GObject is one object.
		 * A {@link Gee.ArrayList} is an object array. Live GObjects
		 * write a lease id when {@link Transport.Connection.live_handles}
		 * is on. Existing list replies stay on {@link result} until
		 * that method moves here.
		 *
		 * == Example ==
		 *
		 * {{{
		 * var n = GLib.Value(typeof(int));
		 * n.set_int(3);
		 * resp.retval = n;
		 * }}}
		 */
		public GLib.Value retval { get; set; }
```

#### Add — in the class docblock, after the Object result `{{{ }}}` sample — `retval` usage

```vala
	 * === Retval ===
	 *
	 * {{{
	 * stdout.printf("%d\n", resp.retval.get_int());
	 * }}}
```

### 4. `libocrpc/Response.vala` — `bin_write_prop` / `bin_read_prop` `retval`

**Why:** Default GObject write cannot encode a `GLib.Value`. Omit unset / empty list, then `StreamValue`.

**Where:** `bin_write_prop` / `bin_read_prop` — new `case "retval":` before `case "args":`. Do not edit `case "result":`.

**Depends on:** ### 3.

#### Add — `bin_write_prop`, after `case "result":` … `return;` and before `case "args":` — omit empty, then `StreamValue.write`

```vala
				case "retval":
					if (this.retval.type() == GLib.Type.INVALID) {
						return;
					}
					if (this.retval.type().is_a(typeof(Gee.ArrayList))
						&& ((Gee.ArrayList<GLib.Object>) this.retval.get_object()).size == 0) {
						return;
					}
					ctx.write_tag(prop.name);
					Bin.StreamValue.write(ctx, this.retval);
					return;
```

#### Add — `bin_read_prop`, after `case "result":` … `return;` and before `case "args":` — decode with `StreamValue.read`

```vala
				case "retval":
					this.retval = Bin.StreamValue.read(ctx, type_byte);
					return;
```

---

## Phase 3 — migrate / drop `result`

- **ℹ️** [`RPC-8.5.4-rpc-retval-migrate.md`](RPC-8.5.4-rpc-retval-migrate.md). Not this file.

---

## Phase 4 — protocol

- **ℹ️** Final §15 text ( `retval` only, no `result` ) is **8.5.4** ### 13. Do not add a dual-property subsection here.

---

## LLM notes

- **🚫** Delete, retype, or stop writing `Response.result` in this cut.
- **🚫** Convert every handler / `Gi` / libocfiles caller onto `retval` here — that is **8.5.4**.
- **🚫** Dual-write `result` and `retval` on the same reply.
- **🚫** `get_object() is Gee.ArrayList`. Use `val.type().is_a(typeof(Gee.ArrayList))`.
- **🚫** Put `OBJECT|0x80` through numeric `read_array`. Use `parse_object_array`.
- **🚫** Revive `Notification.payload` as `GLib.Object`.
- **🚫** New packing helpers. Inline `GLib.Value` + `set_object` / `StreamValue` / `OLLMrpc.args`.
- **🚫** Fold `msg` / `msg_encode` or drop `Response.args` in this plan.
