# Gi: GObject.Value (GValue*) IN/OUT — no double-wrap; round-trip scalars

**Status:** ✅ FIXED — `libocrpc/Gi.vala` GObject.Value pin / fill-back / scalar unwrap  
**Hit:** 2026-09-11 — gnome-shell-rpc nested Wayland / 0.8 init  
**Package / area:** `libocrpc` — `Gi.vala` `convert_interface` / OUT pack (`scalar`)  
**Consumer:** `gnome-shell-rpc` — client overrides call stock
`Meta-MonitorManager.get_property` / `Meta-Context.get_property` /
`set_property` (GIR: `g_object_get_property` / `g_object_set_property`)  
**Consumer bug:**
[`gnome-shell-rpc/docs/bugs/2026-09-11-gir-property-no-getter-missing-on-stub.md`](file:///home/alan/git/gnome-shell-rpc/docs/bugs/2026-09-11-gir-property-no-getter-missing-on-stub.md)

---

## Problem

🔷 **Expected:** Typelib invoke of `GObject.Object.get_property` /
`set_property` on a leased Meta (or any GObject) works over Gi:

- Wire args are already `GLib.Value` rows (`Request.args`).
- GIR `value` parameter is `GValue*` (`GObject.Value` record).
- Get fills that buffer; set reads it. Reply carries the property
  payload as a normal scalar `GLib.Value` (bool, int, string, …) on
  `Response.args`.

**Actual:** Gi has no `GObject.Value` special case. `convert_interface`
treats the record like a sized STRUCT/BOXED and requires
`typeof(GLib.Bytes)` of `sizeof(GValue)`. A wire row that is already a
`GLib.Value` holding the property payload is rejected (or, if naively
boxed again, becomes Value-in-Value). GIR marks `get_property`’s `value`
as **IN** even though C fills it like **OUT**, so Gi also does not pack
the filled buffer back onto `Response.args`.

First consumer call shape:

```text
Meta-MonitorManager.get_property  lease=MonitorManager  args=["night-light-supported"]   # GValue slot omitted
Meta-Context.get_property         lease=Context         args=["unsafe-mode"]
Meta-Context.set_property         lease=Context         args=["unsafe-mode", <bool Value>]
```

---

## Evidence

- ✔️ GIR `GObject.Value`: STRUCT, `sizeof` 24, `is_gtype_struct=0`,
  `get_g_type() == G_TYPE_VALUE` — today’s STRUCT path requires
  `GLib.Bytes` of length 24 (`Gi.vala` ~1211–1238).
- ✔️ `Object.get_property` / `set_property` `value` arg: direction IN,
  `caller_allocates=0`, `may_be_null=0`, interface `Value`.
- ✔️ Consumer overrides today:
  - get: `OLLMrpc.args("s", name)` only — no second wire row
  - set: `OLLMrpc.args("sb", name, value)` — bool is the held payload
  - get reads `response.retval.get_boolean()` — **wrong vs designed
    `args` pack**; consumer should use `response.args.get(0)` after this
    fix (out of libocrpc scope unless asked).

---

## Root cause

✔️ Confirmed from GIR + `Gi.vala` (not a guess):

1. **Double-wrap risk** — every RPC arg is already a `GLib.Value`. For a
   GIR parameter whose interface is `GObject.Value`, the correct IN
   pointer is a pinned copy of that wire row (`GValue*`). Do **not**
   `set_boxed` a Value into another Value; do **not** require
   `typeof(GLib.Bytes)`.
2. **Wrong convert path today** — STRUCT/BOXED `GLib.Bytes` memcpy is
   for opaque POD; wrong for `GValue` (held type + data).
3. **OUT / fill-back** — after `g_object_get_property`, the same buffer
   holds the property. Gi must append that Value onto `response.args`.
   GIR direction alone skips IN args in the pack loop.
4. **Omitted get buffer** — overrides omit the slot; `may_be_null=0`
   would `INVALID_PARAMS`. Gi must allocate an empty `GValue` when the
   wire omits a `GObject.Value` IN arg (fill slot for get).
5. **set_property** — wire Value’s held type is the property type
   (bool for `unsafe-mode`). Pin that row; no wrap.

---

## Proposed fix (`libocrpc/Gi.vala` only)

🔷 Detect via `typeof(GLib.Value)` — there is **no** `GLib.Type.VALUE`
fundamental; `G_TYPE_VALUE` is the `GLib.Value` class type_id.

🔷 **IN + wire present:** pin into `value_keep[]`, set `v_pointer`.

🔷 **IN + wire omitted:** empty `GLib.Value(INVALID)` fill slot, then
`continue`.

🔷 **`scalar`:** early-return unwrap of `GValue*` — never `GLib.Bytes`
of the struct.

🔷 **After invoke:** IN `GObject.Value` → `scalar` into `response.args`
(early `continue`s for non-matches).

🚫 No Helper API. 🚫 No Value-in-Value. 🚫 No new helper methods.
🚫 No nested `if (a && b) { big block }` — flat `continue` / early
`return`.

### `libocrpc/Gi.vala` — field + clear

#### Add — after `string_keep` field (~line 82)

```vala
		/**
		 * Pinned {@link GLib.Value} IN buffers for GIR {@code GObject.Value}
		 * ({@code GValue*}) — wire row copy or empty get fill-slot.
		 * {@link GI.Argument} ''v_pointer'' aliases {@code &value_keep[i]}.
		 */
		private GLib.Value[] value_keep = {};
```

#### Remove — both `dispatch_new` / `dispatch_function` keep resets

```vala
			this.boxed_keep.clear();
			this.string_keep.clear();
			this.glist_keep = {};
			this.gslist_keep = {};
```

#### Replace with

```vala
			this.boxed_keep.clear();
			this.string_keep.clear();
			this.value_keep = {};
			this.glist_keep = {};
			this.gslist_keep = {};
```

### `dispatch_function` — omit → empty GValue; post-invoke pack IN GValue

INOUT already `continue`s above. Treat remaining non-OUT as **IN** with
flat continues (wire present first, then omit/GValue, then may_be_null).

#### Remove — trailing IN omit / convert branch (~488–502)

```vala
				if (arg.get_direction() != GI.Direction.OUT) {
					if (vi >= this.request.args.size) {
						if (!arg.may_be_null()) {
							this.request.connection.reply_error(
								this.request, (int) RpcErrorCode.INVALID_PARAMS);
							return true;
						}
						vi++;
						continue;
					}
					if (!this.convert(arg, vi, instance ? 1 : 0)) {
						return true;
					}
					vi++;
					continue;
				}
```

#### Replace with

```vala
				if (arg.get_direction() == GI.Direction.IN) {
					if (vi < this.request.args.size) {
						if (!this.convert(arg, vi, instance ? 1 : 0)) {
							return true;
						}
						vi++;
						continue;
					}
					if (arg.get_type().get_tag() == GI.TypeTag.INTERFACE) {
						var omit_iface = arg.get_type().get_interface();
						var omit_kind = omit_iface.get_type();
						if (omit_kind == GI.InfoType.STRUCT || omit_kind == GI.InfoType.BOXED) {
							if (((GI.RegisteredTypeInfo) omit_iface).get_g_type() == typeof(GLib.Value)) {
								var omit_i = this.value_keep.length;
								this.value_keep += GLib.Value(GLib.Type.INVALID);
								this.in_args[this.in_slot[i]].v_pointer = &this.value_keep[omit_i];
								vi++;
								continue;
							}
						}
					}
					if (!arg.may_be_null()) {
						this.request.connection.reply_error(
							this.request, (int) RpcErrorCode.INVALID_PARAMS);
						return true;
					}
					vi++;
					continue;
				}
```

#### Remove — post-invoke IN skip (~597–599)

```vala
				if (arg.get_direction() == GI.Direction.IN) {
					continue;
				}
```

#### Replace with

```vala
				if (arg.get_direction() == GI.Direction.IN) {
					if (arg.get_type().get_tag() != GI.TypeTag.INTERFACE) {
						continue;
					}
					var in_iface = arg.get_type().get_interface();
					var in_kind = in_iface.get_type();
					if (in_kind != GI.InfoType.STRUCT && in_kind != GI.InfoType.BOXED) {
						continue;
					}
					if (((GI.RegisteredTypeInfo) in_iface).get_g_type() != typeof(GLib.Value)) {
						continue;
					}
					if (!this.scalar(arg.get_type(), this.in_args[this.in_slot[i]], response.args)) {
						return true;
					}
					continue;
				}
```

### `convert_interface` — pin wire Value (early return)

#### Add — before `size_t n = 0;` STRUCT/BOXED/UNION block (~1211)

```vala
			if (kind == GI.InfoType.STRUCT || kind == GI.InfoType.BOXED) {
				if (((GI.RegisteredTypeInfo) arg.get_type().get_interface()).get_g_type() == typeof(GLib.Value)) {
					var pin_i = this.value_keep.length;
					this.value_keep += GLib.Value(GLib.Type.INVALID);
					val.copy(ref this.value_keep[pin_i]);
					this.in_args[vi + offset].v_pointer = &this.value_keep[pin_i];
					return true;
				}
			}
```

### `scalar` — unwrap held Value (early return before Bytes)

#### Add — inside `INTERFACE` after FLAGS, before `size_t n = 0;` (~1351)

```vala
					if (kind == GI.InfoType.STRUCT || kind == GI.InfoType.BOXED) {
						if (((GI.RegisteredTypeInfo) type.get_interface()).get_g_type() == typeof(GLib.Value)) {
							if (arg.v_pointer == null) {
								this.request.connection.reply_error(
									this.request, (int) RpcErrorCode.INVALID_PARAMS);
								return false;
							}
							dest.add(*(GLib.Value*) arg.v_pointer);
							return true;
						}
					}
```

---

## Attempts / changelog

- ✔️ 2026-09-11 — applied proposed fences in `libocrpc/Gi.vala`
  (`value_keep`, omit empty GValue, pin in `convert_interface`,
  unwrap in `scalar`, post-invoke IN GValue pack). `ninja -C build
  libocrpc/libocrpc.so` ok.
- ✅ 2026-09-11 — marked done; archived as
  `docs/bugs/done/2026-09-11-FIXED-gi-gvalue-property-args.md`.

## Consumer follow-up

ℹ️ Overrides should read `response.args.get(0).get_boolean()` (generator
OUT pattern), not `response.retval` — `get_property` returns void
(consumer tree).

---

## Prove

From gnome-shell-rpc (after libocrpc install):

```bash
./scripts/nested-init-prove.sh
rg 'method=Meta-MonitorManager.get_property|method=Meta-Context.get_property|method=Meta-Context.set_property' \
  ~/.cache/gnome-shell-rpc/org.gnome.ShellRpc.debug.log
```

**Done when:** those calls reply with a bool on `args` (not
`INVALID_PARAMS`); no Value-in-Value; nested init no longer blocked on
missing property *values* once stubs expose the GIR property names.

---

## Related

- Consumer stub gap (property missing on client GType): gnome-shell-rpc
  bug above — override installs names; values need this Gi support.
- Contrast: `panel-orientation-managed` uses a real GIR getter method —
  already on the method wire; no `GValue*`.
