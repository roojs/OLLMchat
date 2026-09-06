# FIXED: GiMock `mock_new` mints GIR return type, not constructor class

**Status:** ✔️ FIXED — applied in `libocrpc/GiMock.vala`; await consumer ✅ (gnome-shell-rpc Panel Effect.new)

**Started:** 2026-09-06

**Process:** `docs/bug-fix-process.md`

**Package / area:** `libocrpc` — `GiMock.vala` (`mock_new` → mint wire prefix, else `mint_object_lease`)

**Related:**

- ℹ️ Design: [`docs/plans/done/RPC-1.7-DONE-mock-dispatch-and-gi-mock.md`](../../plans/done/RPC-1.7-DONE-mock-dispatch-and-gi-mock.md)
- ℹ️ Prior: [`2026-09-05-FIXED-gimock-pointer-return-skips-mint.md`](2026-09-05-FIXED-gimock-pointer-return-skips-mint.md)
- ℹ️ Consumer: gnome-shell-rpc `gi-rpc-mock` / Panel boot (`Clutter-BrightnessContrastEffect.new`)

---

## Problem

🔷 **Symptom (gnome-shell-rpc mock smoke):**

```
Clutter-BrightnessContrastEffect.new
g_object_new_is_valid_property: object class 'ClutterEffect' has no property named 'rpc-lid'
RPC … add_effect_with_name: no rpc_lid on ClutterBrightnessContrastEffect
```

Client lease-on-construct expects a wire object whose alias is the **concrete** leaf (`Clutter-BrightnessContrastEffect`), which maps to a Vala stub implementing `Live.Handle` (`rpc-lid`). Instead the reply encodes as `Clutter-Effect`. The C ABI `Clutter.Effect` parent has no `rpc-lid` → decode CRITICAL → local stub stays unleased.

🔷 **GIR:** many `*Effect.new` constructors declare return type `Effect*` / `ClutterEffect*`, not the leaf class, e.g. Clutter-16:

```xml
<constructor name="new" c:identifier="clutter_brightness_contrast_effect_new">
  <return-value transfer-ownership="full">
    <type name="Effect" c:type="ClutterEffect*"/>
  </return-value>
</constructor>
```

Same pattern: BlurEffect, ColorizeEffect, DesaturateEffect, PageTurnEffect, …

---

## Root cause

✔️ `GiMock.mock_new` minted from **`fn.get_return_type()`**. For constructors, GIR often returns a **parent** (covariant C API). Correct mint is the **wire method prefix** (constructed class).

| | Correct | Was |
| --- | --- | --- |
| `BrightnessContrastEffect.new` | mint `Clutter-BrightnessContrastEffect` | mint `Clutter-Effect` (return type) |
| Client decode | `Object.new(BrightnessContrastEffect, "rpc-lid", …)` | `Object.new(Effect, "rpc-lid", …)` → CRITICAL |

---

## Fix (applied)

✔️ `mock_new`: if wire prefix is in `Bin.alias_to_gtype`, `GiMock.mint(prefix)`; else fall back to `mint_object_lease(fn.get_return_type())`.

---

## Consumer workaround (temporary)

gnome-shell-rpc `HelperMock`: hand-arm `*.new` for affected Effect leaves → `HelperMock.mint(prefix)`. Drop when rebuilt `libocrpc` mints the constructor class.

---

## Attempts / changelog

- ✔️ 2026-09-06 — Hit on gnome-shell-rpc `_initializeUI` Panel (`BrightnessContrastEffect`).
- ✔️ 2026-09-06 — Confirmed GIR return `Effect*`; traced to `GiMock.mock_new` + `mint_object_lease(fn.get_return_type())`.
- ✔️ 2026-09-06 — Filed; HelperMock workaround only in consumer (no libocrpc edit from that tree).
- ✔️ 2026-09-06 — Applied: `mock_new` mints wire prefix when registered; return-type fallback otherwise.
