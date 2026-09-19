# File Server Port looks unused / off for every Host

**Status:** OPEN — user vetoed filling Port with `8443`; keep empty text + placeholder. Enabled switch is the on/off.  
**Hit:** 2026-09-19 — Connections → File Server expander  
**Component:** `ollmapp/SettingsDialog/FileServerRow.vala`

---

## Problem

🔷 Port stays unusable / the listen address stays off no matter which Host is selected.

**Expected:** pick a Host, Port is 8443 (editable), close dialog → `filesd.https` is `ip:8443`.

**Actual:** Port is a suffix `Gtk.Entry` with **empty** `text` and placeholder `8443`. Placeholder is not saved. `apply_config` requires `host != "" && port != ""`, so Host alone writes `https = ""`. ActionRow stays activatable, so the entry can also fail to take clicks.

---

## Proposed fix

- Put `8443` in `port_entry.text` (constructor + `load_config` when saved port is empty).
- `host_row` / `port_row` `activatable = false` so the dropdown and entry receive input.
