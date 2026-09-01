# gi-test segfault on `Gio-Menu.get_n_items`

**Status:** ⏳ verify — parent walk applied; no `to_error` change

## Problem

- 🔷 `tests/test-rpc-gi` exits **139** (SIGSEGV). Do **not** trust bare `cmd | rg …; echo $?` — pipe exit masks the binary.
- 🔷 Expected: full gi-test smoke passes (Menu.new → get_n_items → File path → actors).
- 🔷 Actual: crash while handling `Gio-Menu.get_n_items` on the server.

## Evidence

- ✔️ gdb: `Gi.dispatch` → `reply_error(METHOD_NOT_FOUND)` → `RpcErrorCode.to_error` → SEGV at `((RpcErrorCode) code).message` (`RpcErrorCode.vala:49`).
- ✔️ Stack frame in test is `items_loop.run()` — Menu.new / lease / Handle stubs already succeeded.
- ✔️ C probe: `g_object_info_find_method(Menu, "get_n_items")` → **NULL**; same call on parent **MenuModel** → found. GI: find_method does **not** search parents.

## Root cause

1. ✔️ `Gi.dispatch` only called `find_method` on the leaf type — no parent walk → `MenuModel.get_n_items` → METHOD_NOT_FOUND.
2. ℹ️ That bogus METHOD_NOT_FOUND then hit `to_error`. **🚫** Do not change `to_error` / add a switch — settled in RPC-8.4.4; symptom clears when lookup works.

## Fix

- 🔷 `✔️` `Gi.dispatch` object path: walk `ObjectInfo.get_parent()` after a miss (interfaces unchanged).
- ✔️ get_n_items now found; test advances past Menu smoke.

## Follow-on (new wall)

- ✔️ Next SEGV still in `to_error`, but code is **INVALID_PARAMS** (-32602) from `dispatch_function` @ arg-count check (`Gi.vala` ~400) during **`Gio-File.read`** (`gi-test` ~184).
- ✔️ `File.read` has one IN arg `cancellable` (`may_be_null=1`); test sends **0** wire args → `n_values != args.size`.
- 🚫 Still no `to_error` / switch work — same symptom path.
- 💩 Candidate: treat omitted trailing `may_be_null` IN args as null in `dispatch_function` (and likely `dispatch_new`), or pass a null cancellable from the test only.

## Next

- ⏳ User call on may_be_null omission vs test-only args.
- ⏳ Then `set -o pipefail; build/tests/test-rpc-gi; echo $?` expect `0`.
