# FIXED: OLLMrpc.to_value `"o"` SIGSEGV on null

**Status:** ✔️ FIXED — `to_value` `"o"` packs null without `get_type()`; await consumer re-smoke

**Started:** 2026-09-05

**Process:** `docs/bug-fix-process.md`

**Package / area:** `libocrpc` — `namespace.vala` (`to_value` / `args` / `val`)

**Related:**

- ℹ️ Prior note: [`done/2026-09-01-FIXED-gi-null-object-return-segfault.md`](2026-09-01-FIXED-gi-null-object-return-segfault.md) (avoided `val("o", null)`; did not fix packer)
- ℹ️ GiMock mint: [`2026-09-05-FIXED-gimock-pointer-return-skips-mint.md`](2026-09-05-FIXED-gimock-pointer-return-skips-mint.md)
- ℹ️ Consumer: gnome-shell-rpc `Clutter.BindConstraint` construct → `OLLMrpc.args("oif", null, …)`

---

## Problem

🔷 Client SIGSEGV packing a null GObject into an RPC arg list.

🔷 Repro (gnome-shell-rpc mock smoke): `./scripts/gi-rpc-smoke.sh run` → crash in LayoutManager / BindConstraint construct.

## Evidence

ℹ️ GDB:

```
SIGSEGV in oll_mrpc_to_value (tag="o") at libocrpc/namespace.vala:162
  var o_val = GLib.Value(obj.get_type());
← oll_mrpc_args ("oif")
← clutter_bind_constraint_constructor (Clutter_generated.vala)
```

## Root cause

✔️ `to_value` case `"o"` always calls `obj.get_type()`; null is a valid nullable object arg (e.g. construct property not yet set). Wire path already treats null OBJECT as lease `0` / omit on write.

## Fix applied

✔️ In `to_value` `"o"`: if `obj == null`, pack `GLib.Value(typeof(GLib.Object))` with `set_object(null)` — do not call `get_type()`.

🚫 Paper over in gnome-shell-rpc HelperMock / generator (skip null construct args).

## Attempts / changelog

- ✔️ 2026-09-05 — Applied null `"o"` branch in `libocrpc/namespace.vala`; `libocrpc.so` rebuilt.
