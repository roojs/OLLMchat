# FIXED: GiMock UTF8/FILENAME empty uses `set_string(null)` (breaks string retvals)

**Status:** ✔️ FIXED — `mock_empty` UTF8/FILENAME uses `set_string("")`; await consumer re-smoke

**Started:** 2026-09-05

**Process:** `docs/bug-fix-process.md`

**Package / area:** `libocrpc` — `GiMock.vala` (`mock_empty`, `GI.TypeTag.UTF8` / `FILENAME`)

**Related:**

- ℹ️ Design: [`docs/plans/done/RPC-1.7-DONE-mock-dispatch-and-gi-mock.md`](../../plans/done/RPC-1.7-DONE-mock-dispatch-and-gi-mock.md)
- ℹ️ Wire already null-coalesces on write: `Bin/StreamValue.vala` (`s = s != null ? s : ""`)
- ℹ️ Consumer: gnome-shell-rpc `gi-rpc-mock` / `St-Label.get_text` (LayoutManager → BackgroundMenu → PopupSeparatorMenuItem)

---

## Problem

🔷 **Symptom (gnome-shell-rpc mock boot):** `St-Label.get_text` via GiMock → client sees GLib-GObject CRITICAL (`type id '0' is invalid` / cannot initialize GValue) on the reply, then GJS `TypeError: malformed UTF-8 character sequence at offset 0` when reading `label.text` (`popupMenu.js` `_syncVisibility`).

🔷 **Expected:** UTF8 / FILENAME empty mock returns a real empty string (`""`), same as other scalar empties (`false`, `0`).

**Actual:** `GiMock.mock_empty` used `val.set_string(null)`.

---

## Root cause

✔️ Empty string ≠ null string GValue. `set_string(null)` leaves a STRING-typed GValue whose content is NULL; in-process / unpack / `get_string()` paths still see null; GJS blows up on the bad string.

---

## Fix applied

✔️ In `mock_empty` UTF8/FILENAME: `val.set_string("")`.

🚫 Paper over in consumers with client-local text props.

---

## Changelog

- ✔️ 2026-09-05 — Hit from gnome-shell-rpc LayoutManager / BackgroundMenu path; confirmed `mock_empty` UTF8 arm.
- ✔️ 2026-09-05 — Applied `set_string("")` in `libocrpc/GiMock.vala`.
