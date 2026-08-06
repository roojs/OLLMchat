# RPC: File.activate never replies → queue stall → unexpected response id abort

**Status:** ⏳ root cause confirmed — fix owned by plan Phase 0

ℹ️ Implement via [`docs/plans/2.10.4.7-URGENT-active-project-file-outside-db.md`](../plans/2.10.4.7-URGENT-active-project-file-outside-db.md) **Phase 0** (verbatim fences live there). Do not duplicate proposals here.

## Problem

🔷 App aborted: **`Client.vala:665 unexpected response id 22`**.

🔷 Abort is the **effect**. Must not “fix” by only downgrading `GLib.error` → warning.

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
✔️ Client serializes sends: hung id=21 blocks the queue until timeout.  
✔️ `wait_response` starts the **120 s timer when `call()` is entered** (when queued), **not when the request is actually sent**.

## Root cause

✔️ **Cause chain:**

1. UI activates a file → client RPC **`File.activate`**.
2. Daemon has no handler → **no reply** (only a critical log).
3. That call sits at the head of the client pending queue for ~120 s.
4. A later call (here **`Folder.fetch_files` id=22**) is queued behind it; its timeout **already started at queue time**.
5. When id=21 finally times out, id=22 is sent; its own timer is already ~expired → `complete_pending(22, TIMED_OUT)` removes it from pending.
6. Daemon’s fast reply for id=22 arrives with **nothing pending** → `GLib.error("unexpected response id 22")` → **process abort**.

🚫 Treating orphan replies as soft warnings alone papers over step 6 and leaves steps 1–5.

## Fix

🔷 Apply **Phase 0** of [`2.10.4.7-URGENT-active-project-file-outside-db.md`](../plans/2.10.4.7-URGENT-active-project-file-outside-db.md): drop `File.activate` RPC; `METHOD_NOT_FOUND` on failed dispatch; arm call timeout on **send**, not enqueue.

## Attempts / changelog

- 💩 2026-08-06 — First proposal only softened `GLib.error` (effect). User correctly rejected.
- ✔️ 2026-08-06 — Daemon log: `File.activate` id=21 no reply; id=22 ~121 s later; CRITICAL missing `call_activate`.
- ✔️ 2026-08-06 — Proposed fences moved into plan Phase 0; this file is evidence-only.

## Next

⏳ 🔷 Implement / approve via plan Phase 0 — not from this bug log.
