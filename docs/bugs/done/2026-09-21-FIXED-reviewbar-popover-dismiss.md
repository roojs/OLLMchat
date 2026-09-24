# ReviewBar hover menus stay up after leave / click-away

**Status:** ✅ FIXED — user archived 2026-09-23 (hover dismiss and first prev/next click)  
**Hit:** 2026-09-21 — `oc-test-source-diff` file nav, bulk, Feedback  
**Component:** `liboccoder/Diff/ReviewBar.vala`  
**Plan:** [`CODER-4.2.3.5`](../../plans/CODER-4.2.3.5-source-view-diff-approval.md)

---

## Problem

🔷 Hover popovers stayed up after leave / click-away.

🔷 After autohide-on: first prev/next click did nothing — the hide grab ate the press; second click worked.

🔷 Android has no hover: tap to open, tap again (or tap an item) to close; no leave timeout.

---

## Root cause

✔️ GTK **`autohide = true`** installs a grab. The first click outside the popover (prev/next, overlay) only dismisses; it does not reach the button.

---

## Landed

- ✔️ **`autohide = false`** on file / bulk / Feedback (no grab).
- ✔️ Desktop: hover + **750ms** leave timeout (`#if !ANDROID`).
- ✔️ Click/tap on the trigger **toggles** (Android and desktop).
- ✔️ Prev/next popdown the file list, then change file (first click counts).
- ✔️ Menu item activate still popdowns.

---

## Next

- ✅ 2026-09-23 — user tested dismiss; it was fine.
