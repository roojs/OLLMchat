# Gi FLAGS IN convert requires G_VALUE_HOLDS_FLAGS

**Status:** ✅ FIXED  
**Hit:** 2026-09-07 — gnome-shell-rpc nested Wayland  
`Clutter-Actor.set_offscreen_redirect` →  
`g_value_get_flags: assertion 'G_VALUE_HOLDS_FLAGS (value)' failed`  
**Reporter tree:** `gnome-shell-rpc` (client packs FLAGS as wire `u`)

---

## Symptom

Server-side critical on every FLAGS method IN when the client sends a plain
uint (generator letter `"u"` for GIR FLAGS). Reply may still succeed after
the assert; value applied is wrong/undefined.

---

## Cause

`libocrpc/Gi.vala` `convert_interface`:

```vala
if (kind == GI.InfoType.FLAGS) {
    this.in_args[vi + offset].v_uint32 = val.get_flags();
    return true;
}
```

Wire decode / `OLLMrpc.args("u", …)` yields `GLib.Value` of type `uint`, not
FLAGS. `get_flags()` asserts. ENUM already accepts plain `int`.

`StreamValue` FLAGS read also materializes `Value(typeof(uint))`, so even a
FLAGS wire tag becomes uint before convert.

---

## Fix

FLAGS branch parity with ENUM — accept FLAGS-typed or uint:

```vala
if (kind == GI.InfoType.FLAGS) {
    if (val.type().is_a(GLib.Type.FLAGS)) {
        this.in_args[vi + offset].v_uint32 = val.get_flags();
        return true;
    }
    this.in_args[vi + offset].v_uint32 = val.get_uint();
    return true;
}
```

Applied in `libocrpc/Gi.vala` `convert_interface`.

---

## Refs

- `libocrpc/Gi.vala` — `convert_interface` FLAGS
- Downstream note: `gnome-shell-rpc/docs/bugs/2026-09-07-gi-flags-wire-uint.md`
