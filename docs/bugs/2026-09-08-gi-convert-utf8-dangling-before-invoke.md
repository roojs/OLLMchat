# Gi.convert UTF8 IN: dangling `get_string` before `g_function_info_invoke`

**Status:** ✔️ fix applied in `libocrpc/Gi.vala` — await consumer retest  
**Hit:** 2026-09-08  
**Package / area:** `libocrpc` — `Gi.vala` `convert` (`GI.TypeTag.UTF8` / `FILENAME`)  
**Consumer:** gnome-shell-rpc L7 — `Clutter-ActorMeta.set_name("align")` → mutter `priv->name` garbage → `get_constraint('align')` miss  
**Consumer bug:** `gnome-shell-rpc/docs/bugs/2026-09-08-get-constraint-align-null.md`

---

## Problem

🔷 **Expected:** Gi typelib invoke of `clutter_actor_meta_set_name(meta, "align")` stores `"align"` on the leased meta.

**Actual:** After stock `Clutter-ActorMeta.set_name`, mutter `get_name` returns garbage (not `"align"`). Same lease + Helper Vala `meta.set_name(name)` works.

Affects **every** Gi UTF8/FILENAME IN arg, not only ActorMeta — any string setter on the typelib path.

---

## Root cause (proven)

`Gi.convert` does:

```vala
var val = this.request.args.get(vi);   // GValue by-value copy
this.in_args[…].v_string = val.get_string();  // aliases the copy
// convert returns → copy unset → string freed
// then g_function_info_invoke runs with a dangling pointer
```

`Ffi.pack` already avoids this with an owned `pin` `ArrayList<string>` held until after `cif.call`. **Gi has no equivalent pin.**

### A/B probe (gnome-shell-rpc Helper, same `g_function_info_invoke`)

Minimal invoke of `Clutter.ActorMeta.set_name` — only packing differs:

| Pack | `want` | `meta.get_name()` after invoke |
| --- | --- | --- |
| Like `Gi.convert` (no pin) | `"align"` | garbage (`���u�W`, …) |
| Like `Ffi.pack` (pin until after invoke) | `"align"` | `"align"` |

Log: `/tmp/mutter-rpc-l7-gi-probe2.log` (`L7 gi-set_name pin=false|true`).

Mutter C (`g_set_str`) is fine. Wire `"align"` is fine. **Dangling UTF8 IN pointer in Gi.**

---

## Fix (libocrpc only — do not paper in consumers)

🔷 In `Gi.vala`:

1. Add `Gee.ArrayList<string> string_keep` (parallel to `boxed_keep` / `Ffi.pack` pin).
2. Clear it at the start of `dispatch_new` / `dispatch_function` (with `boxed_keep`).
3. In `convert` UTF8 / FILENAME:

```vala
var held = val.get_string();
this.string_keep.add(held);
this.in_args[vi + offset].v_pointer =
	(void*) this.string_keep.get(this.string_keep.size - 1);
```

(or equivalent unowned alias into `string_keep` storage — same pattern as `Ffi.pack` case `"s"`).

🚫 Consumer Helper bypass of `Clutter-ActorMeta.set_name` as the long-term fix.

---

## Attempts / changelog

- ✔️ `libocrpc/Gi.vala`: added `string_keep`, clear with `boxed_keep` in `dispatch_new` / `dispatch_function`, pin UTF8/FILENAME in `convert` (Ffi `pin` pattern).

---

## Related

- ℹ️ `Ffi.vala` `pack` — documents pin: *“val is by-value; get_string would otherwise dangle”*
- ℹ️ Vala ternary/`get_string` footgun is separate (`examples/oc-vala-ternary-bug.vala`); this bug is Gi convert lifetime, not ternary logging
- ℹ️ Prior UTF8 mock empty: `docs/bugs/done/2026-09-05-FIXED-gimock-utf8-empty-set-string-null.md`
