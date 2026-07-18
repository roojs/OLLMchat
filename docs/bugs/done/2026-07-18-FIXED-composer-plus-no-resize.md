# Composer does not resize after plus / programmatic fill

**Status:** ✅ FIXED — user confirmed; debug removed

**Started:** 2026-07-18

**Process:** `docs/bug-fix-process.md`

**Related:**

- ℹ️ `docs/bugs/done/2026-07-16-FIXED-composer-expanded-height.md` — `ScrolledView` owns height
- ℹ️ `docs/bugs/2026-07-18-android-poc-completion.md` **T1**
- ℹ️ Plus path → `ChatInput.update_entry` → `ScrolledView.buffer_change`

---

## Problem

**Expected:** 🔷 **+** fills composer; height grows to fit (wrap and/or newlines). Width changes (window / code editor) also refit height.

**Actual:** 🔷 Height stayed peer / single-row until edit; width changes did not refit.

---

## Root cause

✔️ GTK `get_line_yrange` returns **paragraph** height (includes wrap). Code treated `content_h <= h0` as “one visual line” and forced `target = peer_h`. Soft-wrapped single paragraph always matched that test.

---

## Fix

**✅** Peer only when `content_h <= peer_h`; else use yrange height.

**✅** On `size_allocate`, if TextView child width changed → Idle `buffer_change`.

**🚫** grow-from-`upper` / unbounded Idle — not used.

Temporary `GLib.debug` removed after verify.
