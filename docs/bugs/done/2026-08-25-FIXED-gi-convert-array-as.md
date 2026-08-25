# FIXED: `Gi.convert_array` native `as` / `string[]`

**Status:** ✅ FIXED — `string[]` type check before the Variant gate. User closed.

**Parent:** [`8.4.6-rpc-ffi-leftovers.md`](../../plans/8.4.6-rpc-ffi-leftovers.md) §8.

---

## Problem

GIR `UTF8[]` / `FILENAME[]` IN arrives as native `string[]` (`STRING|0x80`). The opening `typeof(GLib.Variant)` gate treated every array as a numeric slab and would `INVALID_PARAMS`.

## Root cause

Variant is for numeric slabs (`ai` / `au` / …). Native `as` is a different GLib type. The gate must not run first.

## Fix

`libocrpc/Gi.vala` `convert_array`: if `val.type() == typeof(string[])` and the element tag is UTF8 / FILENAME, alias `v_pointer` to that row. Other tags fall through. The Variant gate is unchanged.

🚫 Do not drop the Variant check (gnome-shell-rpc 0.5.2 proposal).

## Evidence

`meson test test-rpc-gi test-rpc-values` OK. Numeric native arrays remain 8.4.6. Generator `ARRAY` → `string[]` emit stays gnome-shell-rpc Phase 5.
