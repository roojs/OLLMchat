# call_sync: Source.remove on private-context watch → CRITICAL + consumer hang

**Status:** ✅ FIXED (CRITICAL)  
**Hit:** 2026-09-08 ~20:55–20:56 — gnome-shell-rpc nested Wayland after `do_call` → `call_sync`  
**Related:** [nested MainLoop / call_sync API](2026-09-08-FIXED-sync-call-nested-mainloop-reentrancy.md)  
**Follow-up hang:** [consumer hang after burst](../2026-09-08-call-sync-consumer-hang-after-burst.md)  
**Consumer:** gnome-shell-rpc `GiStub.Runtime.do_call`  

---

## Cause

✔️ `Source.remove` only removes from the **default** main context; private-context attach ids need `Source.destroy()`.

## Fix

✔️ Keep `IOSource` / `TimeoutSource` and `destroy()` them; do not `Source.remove` private ids.

## Prove

✔️ Nested 2026-09-08 ~21:04: **no** per-call `Source ID … was not found`.
