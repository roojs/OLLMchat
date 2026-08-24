# `test-rpc-gi` — `Gio-Menu.new` export of null

**Status:** ✔️ local `g_function_info_invoke` `out` binding — await user ✅

## Problem

🔷 `meson test test-rpc-gi` died in `Gio-Menu.new`:
- CRITICAL `oll_mrpc_transport_connection_export: assertion 'gobject != NULL' failed`
- SIGSEGV in `Response.bin_write_prop` at `result.get(0).get_type()` (`Response.vala:152`)

🔷 Expected: leased `GMenu` on `Response.result`, then `Gio-Menu.get_n_items` → `0`.

## Evidence

ℹ️ gdb: crash thread is `dispatch_new` → `Request.reply` → `result` write. `gi-test.vala:69` is still inside the `Gio-Menu.new` `MainLoop` (never reaches `get_n_items`).

✔️ System vapi `GI.FunctionInfo.invoke` takes `GI.Argument return_value` **by value**. C `g_function_info_invoke` writes through `GIArgument *`.

🚫 Ruled out: `Request.values` → `args` rename.

## Root cause

✔️ Vala `fn.invoke(..., ret)` copied the struct. libffi filled the copy. `ret.v_pointer` stayed null. `export` then `result.get(0)` crashed.

## Fix

✔️ `libocrpc/Gi.vala`: `[CCode (cname = "g_function_info_invoke")]` `private static extern` with `out GI.Argument`. Call sites use the full C name. No second C symbol.

ℹ️ Real fix remains the system vapi / annotations on `g_function_info_invoke` so `GI.FunctionInfo.invoke` is `out`. Then delete the local binding.

✔️ `meson test test-rpc-gi` **OK** (0.03s).
