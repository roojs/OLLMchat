# Gi: `get_property` out GValue not initialized correctly → CRITICAL

**Status:** ⏳ root cause confirmed; fix proposed — await apply approval  
**Hit:** 2026-09-13  
**Component:** `libocrpc/Gi.vala` — empty GValue for `g_object_get_property`  
**Consumer:** gnome-shell-rpc  
**Consumer gate (FAIL):** `gnome-shell-rpc/tests/call-sync-repro/gvalue-omit-gate`  
**Consumer note:** [`gnome-shell-rpc/docs/bugs/2026-09-13-gi-gvalue-omit-invalid-critical.md`](file:///home/alan/git/gnome-shell-rpc/docs/bugs/2026-09-13-gi-gvalue-omit-invalid-critical.md)  
**Follows:** [FIXED gi-gvalue-property-args](done/2026-09-11-FIXED-gi-gvalue-property-args.md) (omit fill-slot landed; init wrong)

---

## Problem

🔷 On the server, when Gi calls `g_object_get_property`, it does not
initialize the out `GValue` correctly (type 0 / invalid). GLib
CRITICALs. Property still returns; CRITICAL is the fail.

🔷 Init as a normal empty GValue (`G_VALUE_INIT` / zeroed), not as type
invalid.

ℹ️ Same constructor is used when pinning a GValue for `set_property`
before copy — different correct init (see Root cause).

Sites in `Gi.vala`: omit fill-slot (~511), set pin (~1255) — both
`GLib.Value(GLib.Type.INVALID)`.

---

## Evidence

- ✔️ Gate FAIL from gnome-shell-rpc:
  ```text
  GLib-GObject-CRITICAL **: type id '0' is invalid
  GLib-GObject-CRITICAL **: can't peek value table for type '<invalid>'
  GLib-GObject-CRITICAL **: cannot initialize GValue with type '(null)'
  FAIL gvalue-omit-gate: 3 GObject CRITICAL(s) from Gi omit slot
  ```
- ✔️ `GLib.Value(GLib.Type.INVALID)` alone emits that same CRITICAL triad
  (Vala ctor → `g_value_init(&v, G_TYPE_INVALID)`).
- ✔️ `GLib.Value empty = {}` / `value_keep.resize(n+1)` → type_id 0 unset
  (`G_VALUE_INIT`); `init(typeof(bool))` then set works with 0 CRITICAL.
- ✔️ Empty/`{}` then `val.copy(ref dest)` CRITICALs (`dest_type` assert) —
  `g_value_copy` requires dest already typed. Pin path needs
  `GLib.Value(val.type())` then `copy`, not `{}`.

---

## Root cause

✔️ Confirmed (gate + Vala/GLib probe, not a guess):

The prior omit fill-slot used `GLib.Value(GLib.Type.INVALID)` thinking
“empty.” That ctor calls `g_value_init` with type id 0 → CRITICAL.
`g_object_get_property` needs an **unset** buffer (`G_VALUE_INIT`) so it
can `g_value_init` with the property type.

Pin-before-copy (~1255) uses the same wrong ctor. Fix there is **not**
`{}`: dest for `copy` must already be `GLib.Value(val.type())`.

---

## Proposed fix

🔷 **Omit fill-slot (~511):** grow `value_keep` with a zeroed slot
(`resize`), no `Value(INVALID)`.

🔷 **Set pin (~1255):** pin with `GLib.Value(val.type())` then `copy`
(typed empty dest, not INVALID / not unset).

🚫 Do not use `GLib.Value(GLib.Type.INVALID)` for either site.  
🚫 Do not use unset `{}` for the pin/`copy` dest.  
🚫 No helper methods. Scope: `libocrpc/Gi.vala` only (not GiMock /
`namespace.vala` INVALID returns).

### `libocrpc/Gi.vala` — omit fill-slot

#### Remove

```vala
								var omit_i = this.value_keep.length;
								this.value_keep += GLib.Value(GLib.Type.INVALID);
								this.in_args[this.in_slot[i]].v_pointer = &this.value_keep[omit_i];
```

#### Replace with

```vala
								var omit_i = this.value_keep.length;
								this.value_keep.resize(omit_i + 1);
								this.in_args[this.in_slot[i]].v_pointer = &this.value_keep[omit_i];
```

### `libocrpc/Gi.vala` — set pin before copy

#### Remove

```vala
					var pin_i = this.value_keep.length;
					this.value_keep += GLib.Value(GLib.Type.INVALID);
					val.copy(ref this.value_keep[pin_i]);
```

#### Replace with

```vala
					var pin_i = this.value_keep.length;
					this.value_keep += GLib.Value(val.type());
					val.copy(ref this.value_keep[pin_i]);
```

---

## Prove

```bash
# from gnome-shell-rpc (links this libocrpc)
meson compile -C build gvalue-omit-gate
timeout 5 ./build/tests/call-sync-repro/gvalue-omit-gate
# FAIL — 3× GLib-GObject-CRITICAL (type id '0')
```

After fix: gate PASS (0 CRITICAL, bool still returned).

---

## Next

⏳ Apply after approval → rebuild linked libocrpc → re-run gate.
