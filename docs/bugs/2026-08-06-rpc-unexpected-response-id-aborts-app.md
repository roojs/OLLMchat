# RPC: File.activate never replies → queue stall → unexpected response id abort

**Status:** ✔️ Phase 0 applied — await user ✅

ℹ️ Implemented via [`docs/plans/2.10.4.7-URGENT-active-project-file-outside-db.md`](../plans/2.10.4.7-URGENT-active-project-file-outside-db.md) **Phase 0**.

## Problem

🔷 App aborted: **`Client.vala:665 unexpected response id 22`**.

🔷 Abort is the **effect**. Must not “fix” by softening `GLib.error`, moving call timeouts, or other client queue cosmetics.

## Evidence

ℹ️ Daemon `~/.cache/ollmchat/ollmfilesd.debug.log` on `conn=0x55556abacf30`:

| Time | Event |
|------|--------|
| 08:32:23.662 | `recv id=21 method=File.activate` |
| 08:32:23.662 | **CRITICAL** `RPC dispatch: no signal call_activate on File for File.activate` |
| *(no `reply id=21`)* | |
| 08:34:24.157 | `recv id=22 method=Folder.fetch_files` (~**121 s** later ≈ `call_timeout_seconds` 120) |
| 08:34:24.158 | `reply id=22 Folder.fetch_files` |
| ~08:34:36 | App restarted (new client hello) |

✔️ Client still sends `File.activate` from `libocfiles/ProjectManager.activate_file` (`rpc.call.begin`).  
✔️ Daemon `ollmfilesd/File.vala` has **no** `call_activate` — wire was dropped.  
✔️ `Request.dispatch` logs CRITICAL and returns **false** without `reply` / `reply_error`.  
✔️ Client serializes sends: hung id=21 blocks the queue until timeout; later calls pile up and the abort follows when a reply arrives after the client already gave up.

## Root cause

✔️ **Cause chain:**

1. UI activates a file → client RPC **`File.activate`**.
2. Daemon has no handler → **no reply** (only a critical log).
3. That call sits at the head of the client pending queue for ~120 s.
4. Later calls queue behind it; when the hung call finally times out, a follow-on reply can land with nothing pending → `GLib.error("unexpected response id …")` → **process abort**.

🚫 Softening orphan-reply abort, or moving when timeouts arm, papers over steps 1–2 and leaves silent no-reply handlers dangerous.

## Fix

✔️ Applied **Phase 0**:

1. Dropped `File.activate` RPC from `ProjectManager.activate_file` (local activate only).
2. On failed `dispatch()`, daemon `reply_error(METHOD_NOT_FOUND)`.

## Attempts / changelog

- 💩 2026-08-06 — Soften `GLib.error` on unexpected response id. User rejected (effect only).
- 💩 2026-08-06 — Arm call timeout on send instead of enqueue. User rejected (papers over missing replies).
- ✔️ 2026-08-06 — Daemon log: `File.activate` id=21 no reply; id=22 ~121 s later; CRITICAL missing `call_activate`.
- ✔️ 2026-08-06 — Cause fences in plan Phase 0.1–0.2; Phase 0 applied in tree.

## Next

⏳ User ✅ after verifying file activate no longer stalls RPC / aborts.
