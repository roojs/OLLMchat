# `StreamValue.write` drops boxed types that are not `GLib.Bytes`

**Status:** ✅ FIXED — user archived. Registered boxed `GValue` on `Notification.args` (`0x50` + token + `uint32`). `Live.boxed_ok` is fatal on pointer-shaped GI fields.  
**Hit:** 2026-09-19 — nested mutter-rpc boot: `ClutterStage::before-update`  
**Component:** `libocrpc` / `OLLMrpc.Bin.StreamValue.write`  
**Consumer gate:** `gnome-shell-rpc/tests/call-sync-repro/subscribe-boxed-signal-arg-gate`  
**Related:** named-signal args on `Notification.args` already FIXED (`2026-09-19-FIXED-subscription-emit-drops-signal-args.md`). This is the next pack miss: boxed payload.

**Process:** Follow **`docs/bug-fix-process.md`** — propose → approve → apply. Do not land from the gnome-shell-rpc tree.

---

## Problem

🔷 `Live.Subscription.emit` now copies GObject signal parameters into `Notification.args` and `connection.write`s the notification.

🔷 `StreamValue.write` only encodes boxed as **`GLib.Bytes`**. Any other boxed GType throws `unsupported bin value type '%s'` and the transport resets the client.

**Expected:** subscribe + emit of a named signal whose parameter is a registered boxed type (not Bytes) delivers that boxed value on `Notification.args` (or a documented wire encoding the client can re-emit).

**Actual:** write error, connection reset.

Stock `ClutterStage::before-update` is `(ClutterStageView, ClutterFrame)`. `ClutterFrame` is compact boxed (`clutter_frame_get_type`, ref/unref). gnome-shell-rpc `Meta.Laters` `BEFORE_REDRAW` runs from that signal. Nested 2026-09-19: views were leased; then:

```
connection write error: unsupported bin value type 'ClutterFrame'
```

Client: `Connection reset by peer`. Boot looks locked (mutter keeps running; shell is dead). Consumer must **not** Idle/Timeout/`before-update` skip as a product fix.

---

## Evidence

### Nested (gnome-shell-rpc) — 2026-09-19 17:27

`get_laters` → `RPC-Live-Subscribe.rpc_signal` (`before-update`) → `schedule_update` → write error `ClutterFrame` → client reset.

`MetaRendererView` `lease_ids` was already cleared (peek + `connection.export` on `connection_ready`).

### Consumer gate

```bash
meson compile -C build subscribe-boxed-signal-arg-gate
timeout 5 ./build/tests/call-sync-repro/subscribe-boxed-signal-arg-gate
```

```
server: fire framed(VariantType i)
Connection.vala:213: connection write error: unsupported bin value type 'GVariantType'
Client.vala:701: Unexpected early end-of-stream
```

(client `GLib.error` abort; not a clean `return 1`.)

---

## Library

`libocrpc/Bin/StreamValue.vala` — boxed branch is `typeof(GLib.Bytes)` only; everything else falls through to:

```vala
throw new StreamError.PROTOCOL(
    "unsupported bin value type '%s'",
    val.type().name()
);
```

`Subscription.emit` packs `param_values[1…]` as-is. It cannot skip Frame from the consumer.

---

## Root cause

✔️ Knock-on from packing named-signal `GValue`s onto `Notification.args`. Those rows now hit `StreamValue.write`.

✔️ `0x48` `BOXED` is the untyped `GLib.Bytes` blob. There is no registered-boxed branch. `write_gtype` is `OBJECT` type-byte only on the wire (`0x50` + token) and is never called for `ClutterFrame` / `GVariantType`.

✔️ `Bin.register` already allowlists GTypes in `gtype_to_alias`. Objects use that table. Boxed never looks at it.

✔️ GI invoke memcpy’s POD structs into `GLib.Bytes` *before* `StreamValue`. Subscribe does not convert.

---

## Proposed fix (library)

Intro: edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

- 🔷 **Allowlist.** A boxed GType goes on this path only if both peers `Bin.register` it (`gtype_to_alias`). Same table as objects.
- 🔷 Unregistered boxed still hits `unsupported bin value type`.
- 🔷 `GLib.Bytes` stays the untyped `0x48` blob (no register). Do not overload `0x48` with a compact token (collides with `uint32` length).
- 🔷 **GI layout check once per GType**, not every write. Helper `Live.boxed_ok` (not `Bin` — GI/Live are unix; `Stream.vala` compiles on Android/Windows). First call walks `find_by_gtype` and sets `boxed_valid`; later calls return. Size `0` / disguised (`ClutterFrame`) passes; size `> 0` and a field tag `>= UTF8` is fatal (`GLib.error`).
- 💩 Named boxed reuses the existing `write_gtype` header (`0x50` + token). Reader uses `read_gtype().is_a(BOXED)`. No `write_gtype` signature change.
- 💩 Method name `boxed_ok`. `GVariantType` payload is `peek_string()` UTF-8 after `uint32` BE length (no GI walk). Any other registered boxed that `boxed_ok` accepts writes `uint32` `0`.
- 💩 Wire alias `"GLib.VariantType"`. Consumer registers `"Clutter-Frame"` after `Gi.register("Clutter", …)` — not this repo.
- ℹ️ `tests/rpc/subscribe-test.vala` `Capture.write` never calls `StreamValue.write`. Library gate is `bin-test`.
- ℹ️ Write enters the boxed branch only when `gtype_to_alias` has that GType.
- ℹ️ `GI.TypeTag` is sequential: `VOID`…`GTYPE` are `< UTF8` (scalars). `UTF8` and above are pointer-shaped.

**🚫** GI field walk on every `StreamValue.write`.  
**🚫** New type byte. **🚫** Putting a token after `0x48`.  
**🚫** Sending every boxed `GValue` with no `Bin.register`.  
**🚫** Reject-at-`Bin.register` (would refuse `ClutterFrame` if size-0 were treated as a pointer).  
**🚫** Boxed live-handles / `lease_ids`.  
**🚫** Consumer Idle / Timeout / skip `before-update`.  
**🚫** Changing the `GLib.Bytes` blob layout.

### 1. `libocrpc/Live/namespace.vala` — `boxed_valid` + `boxed_ok`

**Why:** GI field walk lives in one method. The flag map skips the walk after the first success. `StreamValue.write` must not inline this.

**Where:** namespace statics after `gtype_to_alias`; method after `register()`.

**Depends on:** none.

#### Add — after `public static Gee.HashMap<GLib.Type, string> gtype_to_alias;`

```vala
	/** Boxed GTypes that already passed {@link boxed_ok}. */
	public static Gee.HashMap<GLib.Type, bool> boxed_valid;
```

#### Add — after `register()`, before `register_alias`

```vala
	/**
	 * GI layout check for a registered boxed GType.
	 *
	 * Cached in {@link boxed_valid}. First call walks fields; later
	 * calls return. Size 0 / disguised passes. Size greater than 0 with
	 * a field tag at or above UTF8 throws.
	 *
	 * @param gtype boxed GType already in {@link gtype_to_alias}
	 */
	public static void boxed_ok(GLib.Type gtype) throws GLib.Error
	{
		if (boxed_valid == null) {
			boxed_valid = new Gee.HashMap<GLib.Type, bool>();
		}
		if (boxed_valid.has_key(gtype)) {
			return;
		}
		var gi = GI.Repository.get_default().find_by_gtype(gtype);
		if (gi == null) {
			throw new StreamError.PROTOCOL(
				"boxed type '%s' has no GI info",
				gtype.name()
			);
		}
		if (gi.get_type() == GI.InfoType.STRUCT || gi.get_type() == GI.InfoType.BOXED) {
			var si = (GI.StructInfo) gi;
			if (!si.is_gtype_struct() && si.get_size() > 0) {
				for (var fi = 0; fi < si.get_n_fields(); fi++) {
					if ((int) si.get_field(fi).get_type().get_tag() < (int) GI.TypeTag.UTF8) {
						continue;
					}
					throw new StreamError.PROTOCOL(
						"boxed type '%s' is not wire-portable",
						gtype.name()
					);
				}
			}
		}
		if (gi.get_type() == GI.InfoType.UNION) {
			var ui = (GI.UnionInfo) gi;
			if (ui.get_size() > 0) {
				for (var fi = 0; fi < ui.get_n_fields(); fi++) {
					if ((int) ui.get_field(fi).get_type().get_tag() < (int) GI.TypeTag.UTF8) {
						continue;
					}
					throw new StreamError.PROTOCOL(
						"boxed type '%s' is not wire-portable",
						gtype.name()
					);
				}
			}
		}
		boxed_valid.set(gtype, true);
	}
```

### 2. `libocrpc/Bin/StreamValue.vala` — `write`: registered boxed after objects

**Why:** `typeof(GLib.Bytes)` already returned. Only *registered* boxed GTypes take the named path. Unregistered boxed must fall through to the existing throw.

**Where:** `StreamValue.write`, immediately before the final `throw new StreamError.PROTOCOL`.

**Depends on:** §1.

#### Add — immediately before `throw new StreamError.PROTOCOL("unsupported bin value type '%s'", …)`

`Bytes` stays the earlier equality branch. The `has_key` test is the allowlist. `GVariantType` writes `peek_string()`. Other registered boxed calls `boxed_ok` then length `0`.

```vala
			if (val.type().is_a(GLib.Type.BOXED)
				&& gtype_to_alias != null
				&& gtype_to_alias.has_key(val.type())) {
				ctx.write_gtype(val.type());
				if (val.type() == typeof(GLib.VariantType) && val.get_boxed() != null) {
					var vt = (GLib.VariantType) val.get_boxed();
					var s = vt.peek_string();
					ctx.out_stream.put_uint32((uint32) s.length);
					size_t boxed_written;
					ctx.out_stream.write_all(((uint8[]) s)[0:s.length], out boxed_written);
					return;
				}
				OLLMrpc.Live.boxed_ok(val.type());
				ctx.out_stream.put_uint32(0);
				return;
			}

```

### 3. `libocrpc/Bin/StreamValue.vala` — `read`: `OBJECT` type byte may name a boxed GType

**Why:** named boxed is written with `write_gtype` (`0x50` + token), so decode lands in the `OBJECT` case. `parse_object` cannot return a boxed `GValue`.

**Where:** `StreamValue.read`, `case GLib.Type.OBJECT`.

**Depends on:** §2.

#### Remove

```vala
				case GLib.Type.OBJECT:
					var child = ctx.parse_object();
					var obj_val = GLib.Value(child.get_type());
					obj_val.set_object(child);
					return obj_val;
```

#### Replace with

Read the token first. `is_a(BOXED)`: `uint32` + optional `GVariantType` string. Else GObject: same `parse_object` body with the GType already consumed.

```vala
				case GLib.Type.OBJECT:
					var wire_gtype = ctx.read_gtype();
					if (wire_gtype.is_a(GLib.Type.BOXED)) {
						var blob_len = ctx.in_stream.read_uint32();
						var boxed_val = GLib.Value(wire_gtype);
						if (blob_len == 0) {
							return boxed_val;
						}
						var blob_buf = new uint8[blob_len + 1];
						size_t boxed_read;
						ctx.in_stream.read_all(blob_buf[0:blob_len], out boxed_read);
						blob_buf[blob_len] = 0;
						if (wire_gtype == typeof(GLib.VariantType)) {
							boxed_val.set_boxed(new GLib.VariantType((string) blob_buf));
						}
						return boxed_val;
					}
					var child = ctx.parse_object(wire_gtype);
					var obj_val = GLib.Value(child.get_type());
					obj_val.set_object(child);
					return obj_val;
```

### 4. `tests/rpc/bin-test.vala` — `Notification.args` boxed round-trip

**Why:** `Capture.write` in subscribe-test never encodes. This is the library gate for the gnome-shell-rpc `GVariantType` FAIL, plus unregistered boxed still throws.

**Where:** `run_rpc_test`, after the method-ref `parsed_a` / `parsed_b` checks, before the `} catch (GLib.Error e)`.

**Depends on:** §1, §2, §3.

#### Add — after the `"method-ref round-trip mismatch"` check, before `} catch`

Register `Notification` and `GLib.VariantType`. Write/parse a `framed` notification whose arg is `VariantType("i")`. Unregistered `GLib.DateTime` must throw. Registered `GLib.Error` (sized struct + `UTF8` message pointer) must throw on write.

```vala
			OLLMrpc.Notification.rpc_register();
			OLLMrpc.Bin.register("GLib.VariantType", typeof(GLib.VariantType));
			mem = new GLib.MemoryOutputStream.resizable();
			out_stream = new GLib.DataOutputStream(mem);
			write_bin = new OLLMrpc.Bin.Stream(null, out_stream);
			var framed = GLib.Value(typeof(GLib.VariantType));
			framed.set_boxed(new GLib.VariantType("i"));
			var notif_src = new OLLMrpc.Notification() {
				method = "framed"
			};
			notif_src.args.add(framed);
			write_bin.write(notif_src);
			out_stream.close();
			bytes = mem.steal_as_bytes();
			in_base = new GLib.MemoryInputStream.from_bytes(bytes);
			in_stream = new GLib.DataInputStream(in_base);
			read_bin = new OLLMrpc.Bin.Stream(in_stream, null);
			var notif_dst = read_bin.parse() as OLLMrpc.Notification;
			this.check(command_line, !(notif_dst == null), "framed parse returned null\n");
			this.check(command_line, notif_dst.args.size == 1, "framed args missing");
			this.check(
				command_line,
				notif_dst.args.get(0).type() == typeof(GLib.VariantType),
				"framed type mismatch"
			);
			var got_vt = (GLib.VariantType) notif_dst.args.get(0).get_boxed();
			this.check(command_line, got_vt.peek_string() == "i", "framed payload mismatch");
			mem = new GLib.MemoryOutputStream.resizable();
			out_stream = new GLib.DataOutputStream(mem);
			write_bin = new OLLMrpc.Bin.Stream(null, out_stream);
			var dt = GLib.Value(typeof(GLib.DateTime));
			dt.set_boxed(new GLib.DateTime.now_utc());
			var bad = new OLLMrpc.Notification() {
				method = "framed"
			};
			bad.args.add(dt);
			var threw = false;
			try {
				write_bin.write(bad);
			} catch (OLLMrpc.Bin.StreamError e) {
				threw = true;
			}
			this.check(command_line, threw, "unregistered boxed must throw");
			GI.Repository.get_default().require("GLib", "2.0", 0);
			OLLMrpc.Bin.register("GLib.Error", typeof(GLib.Error));
			mem = new GLib.MemoryOutputStream.resizable();
			out_stream = new GLib.DataOutputStream(mem);
			write_bin = new OLLMrpc.Bin.Stream(null, out_stream);
			var err_val = GLib.Value(typeof(GLib.Error));
			err_val.set_boxed(new GLib.Error(GLib.FileError.FAILED, "x"));
			var err_n = new OLLMrpc.Notification() {
				method = "framed"
			};
			err_n.args.add(err_val);
			threw = false;
			try {
				write_bin.write(err_n);
			} catch (OLLMrpc.Bin.StreamError e) {
				threw = true;
			}
			this.check(command_line, threw, "pointer-field boxed must throw");
```

### 5. `docs/bin-rpc-protocol.md` — registered boxed GValue body

**Why:** `0x50` is documented as GObject-only today. Named boxed reuses that header.

**Where:** after §13 blob “Custom overrides” paragraph, before `## 14. Nested object`.

**Depends on:** §2, §3.

```markdown
Registered boxed `GValue` (not `GLib.Bytes`) uses the §14 type header
(`0x50` + compact token from `Bin.register`) then a `uint32` BE length.

- `GLib.VariantType`: length is the `peek_string()` byte count, then that UTF-8.
- Size-0 / disguised boxed (`ClutterFrame`): length `0`, no payload.
- Sized boxed with a pointer-shaped GI field: write throws `not wire-portable`.

```text
50           ;; G_TYPE_OBJECT header (registered GType, boxed or object)
01           ;; compact token → "GLib.VariantType"
00 00 00 01  ;; uint32 length 1
69           ;; "i"
```

Untyped `GLib.Bytes` stays §13 (`0x48` + `uint32` + data). Do not put a
token after `0x48`.

```

---

## Next

- 🔷 ✅ Applied in this repo: `Live.boxed_ok` (unix GI walk, `GLib.error` if not wire-portable; Windows/Android stub in `Live/namespace.windows.vala`), `StreamValue` registered-boxed write/read, `bin-test` VariantType round-trip + unregistered boxed throw, protocol §13.
- ℹ️ gnome-shell-rpc: `Gi.register` Clutter/GLib, then `Bin.register` the boxed GTypes on subscribed signals (`GLib.VariantType`, `Clutter-Frame`, …). Not this repo.
