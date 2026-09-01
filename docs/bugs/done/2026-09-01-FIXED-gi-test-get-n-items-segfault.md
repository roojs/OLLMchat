# FIXED — gi-test segfault on `Gio-Menu.get_n_items`

**Status:** ✅ FIXED — moved to `docs/bugs/done/`

## Problem

- 🔷 `tests/test-rpc-gi` SIGSEGV on `Gio-Menu.get_n_items` / later `Gio-File.read` protocol errors.

## Root cause + fix

1. ✔️ `Gi.dispatch` did not walk `ObjectInfo.get_parent()` → `MenuModel.get_n_items` miss → METHOD_NOT_FOUND → `to_error` SEGV.
2. ✔️ `RpcErrorCode.to_error` used `((RpcErrorCode) code).message` — now message `""` (clients rebuild from domain / gerror_code).
3. ✔️ `dispatch_function` / `dispatch_new` required exact wire arity — now trailing `may_be_null` IN args may be omitted (null).

## Verified

- ✔️ `set -o pipefail; build/tests/test-rpc-gi` → EXIT 0, no failure text.
