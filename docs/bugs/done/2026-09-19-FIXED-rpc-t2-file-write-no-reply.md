# test-rpc-t2 File.write reply / meson SIGTRAP

**Status:** ✅ FIXED — user closed. `meson test -C build test-rpc-t2` OK. No SIGTRAP on this tree.

**Started:** 2026-09-18  
**Closed:** 2026-09-19

---

## Problem

🔷 Id 6 `RPC-File.rpc_write` had no `Response`.

🔷 2026-09-18 meson run was **FAIL** exit 133 (SIGTRAP). That failure is **not** present now.

## Fix

✔️ `libocrpc/Ffi.vala` `pack("u")` — transform to `uint` then `get_uint()` (JSON `0` is `INT`; FFI `"u"` is `UINT`).

✔️ `ollmfilesd/StdioConnection.vala` `drain_script_request` — wait until that request’s `Response` is written so async write can reply.

## Gate

✔️ `meson test -C build test-rpc-t2` — 19/19, including under meson `MALLOC_PERTURB_`.

🚫 Open SIGTRAP hunt — a passing test is not a crash. The 2026-09-18 trap did not occur on re-run.
