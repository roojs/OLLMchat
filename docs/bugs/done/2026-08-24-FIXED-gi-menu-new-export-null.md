# FIXED: `test-rpc-gi` — `Gio-Menu.new` export of null

**Status:** ✅ FIXED — local `g_function_info_invoke` `out` binding. User closed.

---

## Problem

`meson test test-rpc-gi` died in `Gio-Menu.new`:

- CRITICAL `export: assertion 'gobject != NULL' failed`
- SIGSEGV in `Response.bin_write_prop` at `result.get(0).get_type()`

Expected: leased `GMenu` on `Response.result`, then `Gio-Menu.get_n_items` → `0`.

## Root cause

System vapi `GI.FunctionInfo.invoke` takes `GI.Argument return_value` **by value**. C `g_function_info_invoke` writes through `GIArgument *`. libffi filled the copy; `ret.v_pointer` stayed null.

## Fix

`libocrpc/Gi.vala`: `[CCode (cname = "g_function_info_invoke")]` `private static extern` with `out GI.Argument`. Call sites use that. No second C symbol.

ℹ️ System vapi / annotations on `g_function_info_invoke` should still become `out` later; then delete the local binding.

## Evidence

`meson test test-rpc-gi` OK.
