# FIXED: ollmfilesd blocks RPC when busy — second app startup on same daemon

**Status: FIXED** (2026-07-07)

**Resolution:** Client serializes RPC round-trips (`libocrpc/Client.vala` — one pending request sent at a time until its response arrives). Daemon replies from `activate_project` before the filesystem scan runs (`ollmfilesd/ProjectManager.vala`). Per-file `backupDB()` removed from scan reconcile (`ollmfilesd/Folder.vala`). Second-startup repro passes: `replied id=6` / `replied id=7` while scan continues on the daemon main thread.

**Commits:** `bae08a27` (scan backup churn), `48f04f35` (early reply, log noise), `2646959c` (client queue, RPC/daemon diagnostics, `--scan-project`).

**Process:** `docs/bug-fix-process.md`

**Related:**

- [`docs/plans/2.10.4.30-startup-and-daemon-status-ui.md`](../../plans/2.10.4.30-startup-and-daemon-status-ui.md) — status UI for scan/activate (follow-up)
- [`docs/bugs/done/2026-05-15-FIXED-background-scan-ui-sluggish.md`](2026-05-15-FIXED-background-scan-ui-sluggish.md) — prior backupDB / scan jank on project open
- [`docs/plans/done/2.10.4.22-DONE-app-rpc-daemon-startup.md`](../../plans/done/2.10.4.22-DONE-app-rpc-daemon-startup.md) — RPC boot order

---

## Problem

On **second app startup**, the client reconnects to the **same long-lived `ollmfilesd`** (correct behaviour — the daemon is not respawned). The daemon is still busy from the first session's project open (filesystem scan / DB reconcile on the main thread) and **does not service new RPC calls in time**. The UI hangs on session restore.

**Expected:** `ollmfilesd` stays running across app restarts. The second `ollmchat` process connects to that **existing** daemon via the Unix socket and gets timely replies for `ProjectManager.activate_project`, `Folder.fetch_files`, etc.

**Actual (before fix):** Client logs showed `send id=6 activate_project` and `send id=7 fetch_files`, but **no `replied id=6` / `replied id=7`**. Earlier calls on the same connection (`fetch_files` id=4, `fetch_pending_approvals` id=5) **did** reply. After ~120 s the client hit `gee-future-error-quark` / `GTask finalized without ever returning` on the timed-out calls.

Especially visible when the active session restores project `OLLMchat` itself (~50k files in `files.sqlite`).

---

## Reproduce (pre-fix)

1. Build and run with debug logging (`ollmchat --debug`; daemon with `--debug` → `~/.cache/ollmchat/ollmfilesd.debug.log`).
2. **First startup:** app connects, session restore runs (`restoring session project path=…/OLLMchat`) — triggers heavy `activate_project` / filesystem scan on the daemon.
3. **Quit or kill the app** while the daemon is still running (do **not** kill `ollmfilesd`).
4. **Second startup:** launch `ollmchat` again — reconnects to the **same** daemon.
5. Observe client log: `send id=6` / `id=7` with no matching `replied` lines; id=4 and id=5 may still reply.

**Confirm same daemon:** `cat ~/.local/share/ollmchat/ollmfilesd.pid` unchanged across steps 3–4.

---

## Evidence (2026-07-07 ~22:26)

### Client (`ollmchat --debug`)

```
restoring session project path=/home/alan/gitlive/OLLMchat
send id=4 method=Folder.fetch_files
send id=5 method=Folder.fetch_pending_approvals
send id=6 method=ProjectManager.activate_project
send id=7 method=Folder.fetch_files
replied id=4
replied id=5
(no replied id=6 or id=7)
```

### Daemon (`~/.cache/ollmchat/ollmfilesd.debug.log`)

| Time | Event |
|------|--------|
| `22:26:33` | Daemon listening |
| `22:26:33` | Connection 1: `recv id=1` hello, `id=2` load_projects |
| `22:26:37` | `recv id=3..6` — **`activate_project`**, `opening project path=…/OLLMchat` |
| `22:26:40` | `recv id=7` fetch_files |
| `22:26:40` | `filesystem scan queued` → `returned` (35 ms) |
| `22:26:50` | Connection 2 (second app): `recv id=1` hello, `id=2` load_projects — **same daemon PID** |
| `22:26:54` | `recv id=3..5` only — **`id=6` / `id=7` never logged** |

Earlier sessions (before silencing hot-path logs) showed **~270k–300k log lines in ~10 s** after `filesystem scan returned`, almost entirely `saveToDB` + coalesced `backupDB` on the main thread.

---

## Root cause

Two issues compounded:

### 1. Client pipelined RPC requests (primary trigger for the hang)

`OLLMrpc.Client` queued outgoing **writes** (one `flush_async` at a time) but allowed **many requests in flight**. Session restore sent `fetch_files`, `fetch_pending_approvals`, `activate_project`, and another `fetch_files` before earlier replies arrived. While the daemon was busy in a long `activate_project` handler, later requests sat in the kernel buffer unread — client awaited replies that could not be processed in time, hitting the 120 s `call_timeout_seconds`.

### 2. Daemon main-thread scan work (underlying load)

`ProjectManager.activate_project` ran filesystem reconcile (`read_dir` → `read_dir_update` → per-file `saveToDB`) on the GLib main thread **before** replying. `background_recurse` only offloads directory enumeration; DB writes stay on main. Large projects (e.g. `OLLMchat`, ~50k `filebase` rows) saturate the main loop and delay RPC `IOChannel` dispatch for all connections.

Daemon lifecycle (reconnect to same PID) was **correct** — the defect was resource scheduling on both client and daemon.

### Related incident (same day, separate follow-up)

Stale reconcile attempted to delete paths under `libocvector2/` that were **broken symlinks** after consolidation; **`faiss_c_wrapper.{cpp,h}` deleted from disk**, breaking Meson. Restored via `git restore`. Reconcile hardening still needed.

---

## Fix

| Change | File(s) | Purpose |
|--------|---------|---------|
| **Serialize RPC round-trips** — single `pending` queue; only head entry sent (`PendingWrite.sent`) until response; then `send_head` for next | `libocrpc/Client.vala` | Stop pipelining; client waits for each reply before sending the next request |
| **Early `request.reply()`** before `read_dir` / post-scan `update_from` | `ollmfilesd/ProjectManager.vala` | Unblock `activate_project` RPC while scan continues on main |
| Remove per-file `backupDB()` after `saveToDB` in scan | `ollmfilesd/Folder.vala` | Cut disk-backup churn during reconcile |
| `recv` / `reply` logging with `conn=%p` | `libocrpc/Transport/Connection.vala` | Per-connection wire diagnostics |
| `emit call_*` / `emit returned` around signal dispatch | `libocrpc/Request.vala` | Handler timing diagnostics |
| `--scan-project=PATH` foreground scan CLI | `ollmfilesd/Application.vala` | Isolate scan timing without RPC/app noise |
| Comment out hot-path debug/warning | `libocsqlite/Database.vala`, `Query.vala`, `FileHistory.vala`, `DeleteManager.vala` | Log file was ~300k lines per open |

**Verification:** Second-startup repro passes — client logs `replied id=6` and `replied id=7` during session restore while daemon scan continues.

---

## Hypotheses (resolved)

| ID | Hypothesis | Verdict |
|----|------------|---------|
| H1 | Main thread blocked by `read_dir_update` `saveToDB` flood | **Confirmed** — contributes load; early reply + client serialization sufficient for repro |
| H2 | Early reply not emitted before scan | **Fixed** — `request.reply()` moved before `read_dir` |
| H3 | Second connection while first scan still running | **Confirmed** scenario; fixed by client not pipelining + early reply |
| H4 | Client sends id=6–7 before daemon finishes prior handler | **Confirmed** — root client bug; fixed by serial queue |
| H5 | Post-reply idle storm still blocks id=7 | **Ruled out** after serial client + early reply |

---

## Follow-ups (not part of this fix)

| Item | Notes |
|------|--------|
| **Option B — worker thread for scan** | Move `read_dir` reconcile off main thread (pre-RPC `BackgroundScan` pattern). Deferred; main-thread scan still runs but no longer blocks session restore. See plan references in original investigation. |
| **Reconcile must not delete workspace source** | `faiss_c_wrapper` incident — harden `DeleteManager` / stale path handling |
| **Scan status UI** | [`docs/plans/2.10.4.30-startup-and-daemon-status-ui.md`](../../plans/2.10.4.30-startup-and-daemon-status-ui.md) |
| **`--scan-project` baseline** | Run manually on `OLLMchat` for timing before Option B |

---

## Useful grep patterns

| Pattern | Log file | Meaning |
|---------|----------|---------|
| `restoring session project` | app debug | Session restore → `activate_project` |
| `opening project path=` | app / daemon | Project open |
| `scan-project` | daemon | Diagnostic scan mode |
| `filesystem scan queued` / `returned` | daemon | Root `read_dir` timing |
| `send id=` / `replied id=` | app (`Client.vala`) | RPC send/reply pairing |
| `recv id=` / `reply id=` | `ollmfilesd.debug.log` | Daemon wire in/out per connection |
| `emit call_` / `emit returned` | daemon (`Request.vala`) | Handler dispatch timing |

---

## Diagnostic: `--scan-project`

```bash
build/ollmfilesd/ollmfilesd --debug --scan-project=/path/to/project
# or:
build/ollmfilesd/ollmfilesd --debug --data-dir=$HOME/.local/share/ollmchat \
  --scan-project=/path/to/project
```

Foreground, no RPC listener; same scan path as `activate_project` → `read_dir`. Logs to `~/.cache/ollmchat/ollmfilesd.debug.log`.
