# File Server Port looks unused / off for every Host

**Status:** CLOSED — user vetoed filling Port with `8443`; empty text + placeholder. Enabled is HTTPS on/off.  
**Hit:** 2026-09-19 — Connections → File Server expander  
**Superseded by:** [`2026-09-19-FIXED-fileserver-port-not-sensitive.md`](2026-09-19-FIXED-fileserver-port-not-sensitive.md)

---

## Problem

🔷 Port looked unused; listen stayed off no matter which Host was selected. Placeholder `8443` is not saved.

**Proposed (vetoed):** put `8443` in `port_entry.text` when saved port is empty; `activatable = false` on Host/Port.

---

## Outcome

🔷 Keep empty Port + placeholder. Empty = no HTTPS. `activatable = false` did **not** make Port editable (see the Port-not-sensitive log).
