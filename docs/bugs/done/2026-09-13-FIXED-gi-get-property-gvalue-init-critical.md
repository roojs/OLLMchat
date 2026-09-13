# Gi: `get_property` out GValue not initialized correctly → CRITICAL

**Status:** ✔️ FIXED — omit slot `resize` (G_VALUE_INIT); pin `Value(val.type())`+copy  
**Hit:** 2026-09-13  
**Component:** `libocrpc/Gi.vala` — empty GValue for `g_object_get_property`  
**Consumer:** gnome-shell-rpc  
**Consumer gate:** `gnome-shell-rpc/tests/call-sync-repro/gvalue-omit-gate` — PASS  
**Consumer note:** [`gnome-shell-rpc/docs/bugs/2026-09-13-gi-gvalue-omit-invalid-critical.md`](file:///home/alan/git/gnome-shell-rpc/docs/bugs/2026-09-13-gi-gvalue-omit-invalid-critical.md)  
**Follows:** [FIXED gi-gvalue-property-args](2026-09-11-FIXED-gi-gvalue-property-args.md) (omit fill-slot landed; init wrong)

---

## Problem

🔷 On the server, when Gi calls `g_object_get_property`, it does not
initialize the out `GValue` correctly (type 0 / invalid). GLib
CRITICALs. Property still returns; CRITICAL is the fail.

🔷 Init as a normal empty GValue (`G_VALUE_INIT` / zeroed), not as type
invalid.

ℹ️ Same constructor was used when pinning a GValue for `set_property`
before copy — different correct init (see Root cause).

Sites in `Gi.vala`: omit fill-slot (~511), set pin (~1255) — both were
`GLib.Value(GLib.Type.INVALID)`.

---

## Evidence

- ✔️ Gate FAIL (before):
  ```text
  GLib-GObject-CRITICAL **: type id '0' is invalid
  FAIL gvalue-omit-gate: 3 GObject CRITICAL(s) from Gi omit slot
  ```
- ✔️ `GLib.Value(GLib.Type.INVALID)` → `g_value_init(&v, G_TYPE_INVALID)` CRITICAL triad.
- ✔️ `value_keep.resize(n+1)` → unset `G_VALUE_INIT`; get fill works.
- ✔️ Empty then `copy` CRITICALs — pin needs `GLib.Value(val.type())` then `copy`.
- ✔️ Gate PASS (after apply + rebuild libocrpc):
  ```text
  PASS gvalue-omit-gate: get_property omit, no type-id-0 CRITICAL
  ```

---

## Root cause

✔️ Confirmed: omit fill-slot used `GLib.Value(GLib.Type.INVALID)` as
“empty.” Ctor calls `g_value_init` with type id 0 → CRITICAL.
`g_object_get_property` needs unset `G_VALUE_INIT`. Pin-before-copy
needed typed dest `GLib.Value(val.type())`, not unset/`INVALID`.

---

## Fix applied

✔️ `libocrpc/Gi.vala` omit fill-slot: `this.value_keep.resize(omit_i + 1)`.  
✔️ `libocrpc/Gi.vala` set pin: `this.value_keep += GLib.Value(val.type())` then `copy`.

🚫 No `Value(INVALID)` at either site. 🚫 No helper methods.
