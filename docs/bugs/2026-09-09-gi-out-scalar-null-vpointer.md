# Gi.dispatch_function: non-caller-allocates OUT left with null `v_pointer`

**Status:** ✔️ applied in OPC; consumer prove ✔️  
**Hit:** 2026-09-09 — gnome-shell-rpc nested `chrome-stage-smoke` / panel chrome  
**Component:** `libocrpc` / `Gi.vala` `dispatch_function`

---

## Problem

🔷 `Meta.Display.get_size` / `Clutter.Actor.get_size` via Gi returned **0×0** because non-caller-allocates OUT never got a staging pointer (NULL → callee skip write).

## Fix

✔️ Stage a zeroed `sizeof(GI.Argument)` cell for those OUTs; flatten into `out_args[oi]` before `scalar()`. Caller-allocates INTERFACE blob path unchanged.

## Prove

✔️ Nested `chrome-stage-smoke` (2026-09-09): `Meta-Display.get_size` → **800×600**; stage `Clutter-Actor.get_size` → **800×600**; `get_monitor_geometry` still OK. Temporary `Helper-Display.get_size` workaround removed.