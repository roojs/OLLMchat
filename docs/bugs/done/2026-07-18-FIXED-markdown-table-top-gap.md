# FIXED — Markdown table top gap / table CSS

**Status:** ✅ FIXED (2026-07-18) — user verified

**Process:** `docs/bug-fix-process.md`

**Repro:** `tests/markdown/repro-table-header.md`  
`build/examples/oc-test-gtkmd tests/markdown/repro-table-header.md`

---

## Problem

🔷 Massive gap above markdown tables; wanted ~half a line under heading/paragraph.
🔷 Gray box / theme chrome around tables; bottom spacing too large at times.
🔷 `oc-test-gtkmd` looked wrong vs chat (gray page background) while debugging CSS.

---

## Root cause

✔️ **Gap:** Trailing newlines in the TextView above the table (header spacer + parser
`TEXT: "\n"`) — TextView reserved an empty last line. Not markdown blank lines.

✔️ **Table chrome:** `Gtk.Frame` theme padding/box; replaced with `Gtk.Box` + top
`Separator`. Separator CSS needed `separator.horizontal.…` to beat Adwaita.

✔️ **Test gray background:** `oc-test-gtkmd` scrolled window lacked `chat-view-text`
(ChatView applies it → white from `style.css`). That made frame/table CSS look
“broken” in the test until the class was added.

✔️ **CSS load:** gresource load was fine; soft success fill is just subtle on white.

---

## Fix

✔️ `Render.on_table(true)` — chomp trailing whitespace; `remove_empty` if blank.
✔️ `Table` — `Gtk.Box` + `oc-table` / `oc-table-top-rule`; Vala `margin_top = 16`.
✔️ `style.css` — table separator selectors; drop invalid `max-height` / `overflow`
on task-progress header.
✔️ `oc-test-gtkmd` — same CSS sheets as ChatView + `chat-view-text` on scrolled window.

---

## Not in scope / cleaned up

ℹ️ Temporary CSS debug, lime `oc-frame-css-probe`, and disk-first CSS loading —
removed after diagnosis.
