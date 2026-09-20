# File Server Port row is not editable

**Status:** ✅ FIXED — user archived 2026-09-20  
**Hit:** 2026-09-19 — Connections → File Server → Port  
**Component:** `ollmapp/SettingsDialog/FileServerRow.vala`

---

## Problem

🔷 Port could not be edited. Clicking it did nothing.

**Expected:** click Port and type a listen port (user ports 1024–65535). Invalid if too low. Field only as wide as `65535`.

---

## Root cause

✔️ Tools **Engine ID** (`Rows.String` inside `Rows.Tool : Adw.ExpanderRow`) works: `Gtk.Entry { width_chars = 30 }`, `add_suffix`, `set_activatable_widget`. No `can_focus = false` on that expander.

✔️ File Server / LLM `ConnectionRow` expanders used `can_focus = false` + `focus_on_click = false` and never copied that Engine ID wiring.

---

## Dead ends (do not repeat)

- 🚫 `activatable = false` on Host/Port (from the placeholder log) — suffix never received clicks.
- 🚫 Suffix `Gtk.Entry` inside `Adw.ExpanderRow` without Engine ID wiring — pencil / no focus.
- 🚫 `Adw.EntryRow` as the Port row.
- 🚫 `Gtk.SpinButton` — steppers worked, typing the inner `Gtk.Text` did not; allowed ports below 1024.

---

## Landed

- ✔️ Port is `Gtk.Entry` `width_chars = 5`, `max_length = 5`, placeholder `8443`, digits `insert_text`, `set_activatable_widget`. Blur: empty = no HTTPS; `n < 1024` or `n > 65535` → subtitle **Invalid** + error CSS.
- ✔️ LLM Name / URL / API Key: same `width_chars = 30` + `set_activatable_widget`; expander `can_focus` / `focus_on_click` false removed.
