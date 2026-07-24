# FIXED — Add Model search empty (popup skipped on GtkText focus)

**Status:** ✅ FIXED — user verified 2026-07-24

**Started:** 2026-07-24

**Process:** Follow **`docs/bug-fix-process.md`**

**Related:**

- ℹ️ Prior FIXED (parser): [`2026-07-19-FIXED-libollamaweb-model-search-broken.md`](2026-07-19-FIXED-libollamaweb-model-search-broken.md)

---

## Problem

🔷 Desktop Add Model showed **no searching bar** and **no rows** when typing (e.g. `gamma` / `gemm`).

---

## Evidence (2026-07-24 ~09:02, `--debug`)

✔️ Search **succeeded** (`store ready q='gemm' items=20`).

✔️ Popup never opened: `loading popup skipped focus=GtkText` / `items popup skipped focus=GtkText`.

---

## Root cause

✔️ Focus guard called `Gtk.Widget.is_ancestor` **backwards**.

GTK: `widget.is_ancestor(ancestor)` = “is **widget** inside **ancestor**?”

Was: `this.model_pulldown.is_ancestor(focus)` (pulldown inside focus?).

Needed: `focus.is_ancestor(this.model_pulldown)` (focus inside pulldown?).

Typing focuses the entry’s inner `GtkText`, so the wrong call always skipped `set_popup_visible` → no searching bar (bar lives in the popup).

🚫 Not a `libollamaweb` parse regression.

---

## Fix applied

✔️ Both sites in `ollmapp/SettingsDialog/AddModelDialog.vala`:

`!this.model_pulldown.is_ancestor(focus)` → `!focus.is_ancestor(this.model_pulldown)`

✔️ Temporary investigation `GLib.debug()` removed; pre-existing commented debug in `SearchResults` restored.

✅ User verified Desktop Add Model search (searching bar + rows).
