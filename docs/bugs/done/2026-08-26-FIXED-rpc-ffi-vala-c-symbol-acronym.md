# FIXED: RPC FFI Vala C-symbol acronym mismatch (hello hang)

**Status:** ✅ FIXED — acronym regex + string pin; hello / t0 / t1 green. User closed.

## Problem

- 🔷 `meson test --suite rpc` harness (`test-rpc`, `test-rpc-t1`, `test-rpc-t2`) timed out / failed after RPC `args` migration.
- 🔷 Ready notification emitted; `RPC-Daemon.hello` never replied (then later: other methods got garbage paths).

## Evidence

- ✔️ Manual `t0`: `RPC dispatch: no symbol ollmfilesd_daemon_hello` vs exported `oll_mfilesd_daemon_hello`.
- ✔️ After acronym fix: hello replies; create_project path was garbage (`"\f…"`) — `GLib.Value` by-value into `pack` + `get_string()` dangling before `cif.call`.
- ✔️ Harness scripts still used pre-migration wire names (`create_project` vs `rpc_create_project`).

## Root cause

1. ✔️ FFI symbol regex only split lower→Upper; Vala also splits acronym→word (`OLLMfilesd` → `oll_mfilesd`).
2. ✔️ `pack(GLib.Value val)` by-value: string pointer into temporary GValue freed before `cif.call`.
3. ✔️ Test scripts / T2A.7 stderr match lagged the `rpc_*` wire rename and FFI “no handler” message.

## Fix applied

- ✔️ `libocrpc/Ffi.vala` — acronym regex + pin owned strings until after `cif.call`.
- ✔️ `tests/rpc/*.script.in` — `rpc_*` method names to match `add_class`.
- ✔️ `tests/test-rpc-t2.sh` — File.activate stderr match for FFI.

## Results (2026-08-26)

- ✔️ `test-rpc` (t0 hello) OK
- ✔️ unit suite (bin/live/subscribe/callback/values/gi/scm/proxies) OK
- ✔️ `test-rpc-t1` OK
- 🚫 `test-rpc-t2` remaining asserts (File.read id=-1 after scan activate; CHANGED_HAS_UNSAVED; sqlite count 2 vs 1) are activate/scan/DB semantics, not this symbol lookup. Out of scope here.
