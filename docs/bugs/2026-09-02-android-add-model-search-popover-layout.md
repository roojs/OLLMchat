# Android Add Model search: popover too narrow, clips off top of screen

**Status:** ⏳ OPEN — user report 2026-09-02; fix not proposed yet

**Started:** 2026-09-02

**Package:** `org.roojs.ollmchat.androidpoc`

**Process:** `docs/bug-fix-process.md`

**Related:**

- ✅ TLS / empty search (closed): [`done/2026-08-31-FIXED-android-add-model-search-tls.md`](done/2026-08-31-FIXED-android-add-model-search-tls.md) — search works; noted tiny popup (60×68 CSS) as separate UX
- ℹ️ Widget: `ollmapp/SettingsDialog/SearchablePulldown.vala` (shared desktop + Android)
- ℹ️ Entry point: Settings → Add Model → model search row (`ollmapp/SettingsDialog/AddModelDialog.vala`)

---

## Problem

🔷 On Android, Settings → **Add Model** → type in the model search field. The results **popover** opens, but:

1. **Width** — too narrow. Each result row is cramped. User wants the popover **full width of the phone screen** so rows have more horizontal space.

2. **Height / position** — the popover **extends off the top of the screen** (content clipped or unreachable above the display). User wants height **capped to the space between the search text entry and the top of the screen** — use all available room upward from the entry, but not beyond the top edge.

🔷 Desktop behaviour may be acceptable; this is an **Android layout** issue on a narrow tall screen inside `Adw.PreferencesDialog`.

---

## Evidence

- ✔️ User verified 2026-09-02: TLS search OK; layout still wrong.
- ✔️ Prior TLS log (2026-08-31): `Gdk Android.Popup: present` mapped **225×255 px → 60×68 CSS** — popup much smaller than screen.
- ✔️ `SearchablePulldown.size_allocate`: `popup.set_size_request(width * 2, -1)` — width is **2× the entry widget**, not screen / dialog width.
- ✔️ `SearchablePulldown.set_popup_visible` (idle after `popup()`): height from `root_window.get_height() - entry_alloc.y - entry_alloc.height - 20`, clamped **200 … min(available, max_content_height)** where `max_content_height` defaults to **400**. Uses **entry Y in window coordinates** — on Android inside nested settings UI this may not match visible space above the entry, and does not account for popover opening **above** the anchor when near the bottom of the dialog.
- ✔️ Popover: `position = BOTTOM`, `has_arrow = false`, `halign = START` — no Android-specific sizing.

---

## Expected vs actual

| | Expected (Android) | Actual |
|---|-------------------|--------|
| Width | Full screen width (or full dialog content width) | ~2× narrow entry field |
| Height | From entry up to top of screen — no clip | Extends past top; list clipped / lost |

---

## Root cause

⏳ **Hypothesis (needs device measure):** Shared `SearchablePulldown` sizing assumes desktop: 2× entry width and window-height math from `Gtk.Window` + entry allocation. On Android GDK popup, the mapped surface is tiny and/or positioned so the computed `min_content_height` pushes content outside the visible region.

🚫 Not TLS, not empty search results.

---

## Proposed fix direction

🔷 **Android-only** (`#if ANDROID` in `SearchablePulldown` or thin wrapper from `AddModelDialog`):

1. **Width** — on popup show, set popover width to **screen / root content width** (not `width * 2` of entry). Centre or align to dialog margins as needed.

2. **Height** — compute **distance from entry bottom (or top) to top of usable screen / dialog**, set `scrolled_window` `max_content_height` and `min_content_height` to that value (with small margin). Ensure popover **position** (`TOP` vs `BOTTOM`) or GDK placement does not draw above the display.

⏳ Fences deferred until device measure confirms coordinate space (window vs surface vs CSS px).

---

## Attempts / changelog

- ✔️ 2026-09-02 — User: search works; popover needs full width + height capped to entry→top of screen.

## Next

⏳ 🔷 Optional: log popup bounds + entry alloc on device (`--debug`), then propose verbatim fences in this file.
