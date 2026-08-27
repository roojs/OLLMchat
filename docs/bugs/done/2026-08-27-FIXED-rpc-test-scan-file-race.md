# RPC harness: File.* after activate races filesystem scan

**Status:** ✅ FIXED — Path A scripts `skip_scan` + `File.register` before File.*. `meson test -C build test-rpc-t2` OK. User closed.

**Started:** 2026-08-27

---

## Problem

🔷 `test-rpc-t2` Path A: `File.read` / write / `changed.check` right after `rpc_activate_project`. Activate replies before the scan indexes the fixture → asserts fail (`id == -1`, wrong changed, sqlite count).

## Fix

✔️ Path A scripts: `skip_scan` + `File.register` on `__HELLO_PATH__`, then File.*. Same as Path B. No daemon edits.

Files: `tests/rpc/t2-scan.script.in`, `t2.script.in`, `t2-changed-dirty.script.in`, `t2-write-persist.script.in`, `tests/test-rpc-t2.sh` (jq ids).

## Ruled out

🚫 `wait_scan_idle` on File.*
🚫 Harness wait-notification / extra daemon field
🚫 Daemon `scanning.set` / `read_dir` timing
🚫 Same-script `fetch_files` after activate — script runner does not wait for the scan worker
