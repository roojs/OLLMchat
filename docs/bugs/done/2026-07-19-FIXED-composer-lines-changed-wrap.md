# Composer `lines_changed`: soft-wrap stays at 1

> Pointer: `docs/bug-fix-process.md` (emoji + code fences). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✅ FIXED — user confirmed on Android

**Started:** 2026-07-19

**Process:** `docs/bug-fix-process.md`

**Related:**

- ℹ️ `docs/bugs/done/2026-07-19-FIXED-composer-chrome-hysteresis.md` — `lines_changed` 0/1/2 from `use_peer`
- ℹ️ `docs/bugs/done/2026-07-18-FIXED-composer-plus-no-resize.md` — height from yrange vs peer
- ℹ️ `libollmchatgtk/ScrolledView.vala` — `buffer_change` / `lines_changed`

---

## Problem

- **🔷** Plus / restore fill that soft-wraps to two visual lines did not expand composer chrome on Android.

---

## Root cause

- **✔️** `lines_changed` used `use_peer` (`content_h <= peer_h`). Phone: `peer_h=34`, `glyph_h=16` — wrap with `content_h=31` still reported `lines=1`.

## Evidence

- **✔️** Logcat: `end_off=61 content_h=31 peer_h=34 glyph_h=16 use_peer=true → lines=1`

## Fix

- **✅** Drive `lines` from `content_h > glyph.height`; keep `use_peer` for viewport height only.
- **✅** Temporary `GLib.message` probe removed after verify.
