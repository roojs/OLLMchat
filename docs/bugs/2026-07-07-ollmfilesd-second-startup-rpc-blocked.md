# ollmfilesd blocks RPC when busy — second app startup on same daemon

**Status:** OPEN — investigation in progress; partial mitigations applied, not verified

**Started:** 2026-07-07

**Process:** `docs/bug-fix-process.md`

**Related:**

- [`docs/plans/2.10.4.30-startup-and-daemon-status-ui.md`](../plans/2.10.4.30-startup-and-daemon-status-ui.md) — status UI for scan/activate (proposed)
- [`docs/bugs/done/2026-05-15-FIXED-background-scan-ui-sluggish.md`](done/2026-05-15-FIXED-background-scan-ui-sluggish.md) — prior backupDB / scan jank on project open
- [`docs/plans/done/2.10.4.22-DONE-app-rpc-daemon-startup.md`](../plans/done/2.10.4.22-DONE-app-rpc-daemon-startup.md) — RPC boot order

---

## Problem

On **second app startup**, the client reconnects to the **same long-lived `ollmfilesd`** (correct behaviour — the daemon is not respawned). The daemon is still busy from the first session’s project open (filesystem scan / DB reconcile on the main thread) and **does not service new RPC calls in time**. The UI hangs on session restore.

**Expected:** `ollmfilesd` stays running across app restarts. The second `ollmchat` process connects to that **existing** daemon via the Unix socket and gets timely replies for `ProjectManager.activate_project`, `Folder.fetch_files`, etc. Heavy background work (scan, index) must not starve the RPC main loop.

**Actual:** Client logs show `send id=6 activate_project` and `send id=7 fetch_files`, but **no `replied id=6` / `replied id=7`**. Earlier calls on the same connection (`fetch_files` id=4, `fetch_pending_approvals` id=5) **do** reply. After ~120 s the client hits `gee-future-error-quark` / `GTask finalized without ever returning` on the timed-out calls.

The bug is **daemon resource management** — not client boot or daemon lifecycle. Connecting to the same daemon is working as designed; the daemon is simply too busy to read/respond.

This is especially visible when the active session restores project `OLLMchat` itself (~50k files in `files.sqlite`).

---

## Reproduce

1. Build and run with debug logging (`ollmchat --debug`; daemon with `--debug` → `~/.cache/ollmchat/ollmfilesd.debug.log`).
2. **First startup:** app spawns `ollmfilesd` (or attaches if already running), connects, session restore runs (`restoring session project path=…/OLLMchat`) — triggers heavy `activate_project` / filesystem scan on the daemon.
3. **Quit or kill the app** while the daemon is still running and still busy (do **not** kill `ollmfilesd` — leave the same PID alive).
4. **Second startup:** launch `ollmchat` again — it reconnects to the **same** daemon (`~/.local/share/ollmchat/ollmfilesd.sock`).
5. Observe client log: `send id=6 method=ProjectManager.activate_project` and `send id=7 method=Folder.fetch_files` with no matching `replied` lines; id=4 and id=5 may still reply.

**Confirm same daemon:** `cat ~/.local/share/ollmchat/ollmfilesd.pid` unchanged across steps 3–4.

---

## Evidence (2026-07-07 ~22:26, after log-noise reduction)

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

### Daemon (`~/.cache/ollmchat/ollmfilesd.debug.log`) — entire capture only 20 lines

| Time | Event |
|------|--------|
| `22:26:33` | Daemon listening |
| `22:26:33` | Connection 1: `recv id=1` hello, `id=2` load_projects |
| `22:26:37` | `recv id=3..6` — **`activate_project`**, `opening project path=…/OLLMchat` |
| `22:26:40` | `recv id=7` fetch_files |
| `22:26:40` | `filesystem scan queued` → `returned` (35 ms) |
| `22:26:50` | Connection 2 (second app): `recv id=1` hello, `id=2` load_projects — **same daemon PID** |
| `22:26:54` | `recv id=3..5` only — **`id=6` / `id=7` never logged** |

Connection 2 is a new client socket on the **existing** daemon, while connection 1’s `activate_project` scan work is still monopolizing the main loop.

Earlier sessions (before silencing hot-path logs) showed **~270k–300k log lines in ~10 s** after `filesystem scan returned`, almost entirely `saveToDB` + coalesced `backupDB` on the main thread.

---

## Root cause (working theory — not fully fixed)

The daemon lifecycle is **correct**. The defect is that **`ollmfilesd` does not manage CPU/main-loop time** — heavy project-open work starves RPC handling for all clients, including a freshly reconnected app.

### Definitive

1. **`ProjectManager.activate_project` runs heavy work on the GLib main thread**: `load_files_from_db`, `read_dir` reconcile (`read_dir_update` → `saveToDB` per file), stale-row `DeleteManager.remove`, `project_files.update_from`.
2. **While that work runs, the main loop is saturated** — the RPC `IOChannel` watch in `libocrpc/Transport/Connection.vala` does not read further requests from the socket (client sends id=6/id=7 but daemon never logs `recv`).
3. **Client `OLLMrpc.Client.call_timeout_seconds` defaults to 120** — unanswered calls eventually throw; fire-and-forget `.begin()` on `activate_project` still leaves other awaiters (e.g. `fetch_files` id=7) blocked.
4. **Second app startup** opens a new RPC connection to the **same busy daemon**; the first session’s scan (or a overlapping second `activate_project`) is still running; new requests queue in the kernel buffer unread.

### Strongly suspected

- `background_recurse` only offloads **directory enumeration** to a thread; **all DB writes** in `read_dir_update` / `read_dir_remove` stay on the main thread.
- Large self-hosted project (`OLLMchat`, ~50k `filebase` rows) amplifies reconcile (many stale paths after `libocvector` → `libocvector2` consolidation, build dirs, renamed docs).
- No prioritization or yielding on the RPC path — scan work and incoming RPC share one main context with no fair scheduling.

### Related incident (same day)

`ollmfilesd` stale reconcile attempted to delete paths under `libocvector2/` that were **broken symlinks** after consolidation; **`faiss_c_wrapper.{cpp,h}` deleted from disk**, breaking Meson (`File faiss_c_wrapper.cpp does not exist`). Restored via `git restore`. Separate hardening needed: reconcile must not `delete_async` workspace source files.

---

## Attempts / changelog (in progress — not approved as final fix)

| Change | File(s) | Purpose | Result |
|--------|---------|---------|--------|
| Remove per-file `backupDB()` after `saveToDB` in scan | `ollmfilesd/Folder.vala` `read_dir_update` | Cut disk-backup churn during reconcile | Insufficient — main cost is `saveToDB`, not flush |
| **Early `request.reply()`** before `read_dir` / post-scan `update_from` | `ollmfilesd/ProjectManager.vala` | Unblock `activate_project` RPC while scan continues | **Not verified** on second-startup repro; may still block socket read for other ids |
| Comment out hot-path debug/warning | `libocsqlite/Database.vala`, `Query.vala`, `FileHistory.vala`, `DeleteManager.vala` | Log file was ~300k lines per open | Log now ~20 lines; easier to read, does not fix blocking |
| Restore `libocvector2/faiss_c_wrapper.*` | git | Build break after symlink deletion | Build green |

**Do not treat the above as closed** until second-startup repro passes with `replied id=6` / `replied id=7` in client log.

---

## Hypotheses (open)

| ID | Hypothesis | How to test |
|----|------------|-------------|
| H1 | Main thread blocked by `read_dir_update` `saveToDB` flood | Sysprof during repro; count time in `SQ.Query` / sqlite |
| H2 | Early reply not in running binary or still after slow `load_files_from_db` | Daemon log: gap between `opening project` and `filesystem scan queued`; client `replied id=6` timestamp |
| H3 | Second app connection arrives while first session’s `activate_project` scan still running on same daemon | Log `recv` per connection; confirm **same PID** across app restart |
| H4 | Client sends id=6–7 before socket flush while daemon stuck in id=5 handler | Strace / wire log ordering |
| H5 | `process_folders` idle storm + `update_from` after early reply still prevents `IOChannel` dispatch | Reply id=6 succeeds but id=7 still hangs |

---

## Proposed fix directions

### Preferred: **Option B — worker thread + same `SQ.Database`** (restore pre-RPC pattern)

**Decision (2026-07-07):** Go with **Option B**. The old design used a **background worker thread** with its own `MainLoop`, a worker-side `ProjectManager`, and the **same** `SQ.Database` instance protected by `db_mutex` (`Sqlite.SERIALIZED`). That worked reasonably well before the RPC cutover.

**Reference:** [`docs/plans/done/2.10.1-DONE-codebase-search-background-scanning.md`](../plans/done/2.10.1-DONE-codebase-search-background-scanning.md), [`docs/bugs/done/2026-05-15-FIXED-background-scan-ui-sluggish.md`](done/2026-05-15-FIXED-background-scan-ui-sluggish.md).

**Target shape:**

- **Main thread / RPC loop:** dispatch RPC only; quick reads via `SQ.Database` (short mutex holds).
- **Worker thread:** `read_dir` reconcile, `saveToDB`, `DeleteManager` stale cleanup, `project_files.update_from` after scan — dispatched via `IdleSource` on worker `MainContext` (same pattern as old `BackgroundScan`).
- **`activate_project`:** reply immediately after setting active project + optional DB load for display; enqueue full filesystem scan on worker.
- **During scan:** reads OK on main (may be slightly stale); **block or reject writes** for the scanning project until worker finishes; notify clients when done (see below).
- **On scan complete:** worker signals main → reload `project_files`, `backupDB()` once, broadcast scan-done notification.

**Why it regressed:** RPC migration moved filesystem scan **inside** daemon `activate_project` on the **GLib main thread** (`yield project.read_dir` → `read_dir_update` → per-file `saveToDB`). `background_recurse` only threads directory **enumeration**; all DB reconcile stayed on main. Project scale grew (~50k `filebase` rows on self-hosted `OLLMchat`; stale rows after `libocvector` consolidation) — so the same architecture hurts more than it used to, but the fix is restoring background execution, not abandoning single-daemon + `SQ.Database`.

**Still do (compatible with B):** early RPC reply, batch/coalesce `backupDB` during scan, no `delete_async` on reconcile for missing paths, `event.project.filesystem_scan_update` progress events (plan 2.10.4.30).

---

### Alternative (not chosen): **Option A — temp scan database + merge/swap**

Documented as a **potential** approach if Option B proves insufficient.

1. At scan start: **snapshot** main in-memory DB → `scan_db` (`Sqlite.Backup` between connections).
2. Worker writes only to `scan_db` during reconcile.
3. **Main DB serves RPC reads** during scan (stable pre-scan snapshot).
4. **Writes blocked** (or rejected with busy error) for the scanning project while scan runs.
5. On complete: **swap** `scan_db` → main (`Backup`), reload in-memory tree, **one** disk `backupDB()`, notify clients to **refresh**.

Avoid row-by-row merge (ID remapping pain). Full `Backup` swap is simpler than diff merge.

**Scan-complete client contract (either option):**

| Phase | Reads | Writes | Client |
|-------|-------|--------|--------|
| Scan running | OK (stale snapshot) | Block / reject per project | Status bar + `event.project.filesystem_scan_update` |
| Scan done | Refresh from main DB | Resume | Re-`fetch_files` / reload tree on notification |

---

### Other options (lower priority)

| Option | Notes |
|--------|--------|
| **C.** Early reply + yield/batch on main only | Partial; insufficient alone (current attempts) |
| **D.** In-memory batch, one transaction at end | Still needs work off main thread |

---

## Step 0 — diagnostic: `ollmfilesd` project scan option (first)

**Goal:** Isolate filesystem scan from app/RPC noise. See **what** the scan does, **how long** each phase takes, and what debug output looks like — before implementing Option B.

**Proposed CLI** (implemented in `ollmfilesd/Application.vala`):

| Flag | Purpose |
|------|---------|
| `--scan-project=PATH` | After DB open, run a full project filesystem scan on `PATH` (same code path as `activate_project` → `read_dir`, but **no RPC listener**, no app) |
| `--debug` / `-d` | Log to `~/.cache/ollmchat/ollmfilesd.debug.log` (existing) |

**Behaviour (sketch):**

1. Foreground only (no `daemonize` when `--scan-project` set).
2. Open `files.sqlite` from `--data-dir` (default `~/.local/share/ollmchat`).
3. Resolve or create project folder row for `PATH`.
4. Log phase boundaries with wall time (logging pipeline already timestamps lines):
   - DB load (`load_files_from_db` if needed)
   - `read_dir` start / root returned / full subtree complete (`process_folders` drained)
   - `project_files.update_from`
   - `backupDB` / exit
5. Optional summary line: elapsed seconds, approximate files touched (if cheap to count).
6. **Exit** when scan completes (diagnostic one-shot).

**Manual run (once implemented):**

```bash
# kill any running daemon first if you want a clean DB copy
build/ollmfilesd/ollmfilesd --debug --scan-project=/home/alan/gitlive/OLLMchat
# or explicit data dir:
build/ollmfilesd/ollmfilesd --debug --data-dir=$HOME/.local/share/ollmchat \
  --scan-project=/home/alan/gitlive/OLLMchat
```

**Inspect:**

```bash
less ~/.cache/ollmchat/ollmfilesd.debug.log
# grep: filesystem scan queued|returned|scan-project|scan done
```

**What we learn from this step:**

- Wall-clock time for scan on real `OLLMchat` tree (~50k DB rows).
- Whether root `read_dir` “returned” in milliseconds but subtree work dominates (confirms `process_folders` / `read_dir_update` hotspot).
- Stale reconcile volume (DeleteManager / missing paths) without client reconnect in the mix.
- Baseline to compare after Option B (worker thread) — same flag, same project, should complete with RPC loop free if B is correct.

**Note:** Run **manually** with the flag below for timing baseline on real projects (e.g. `OLLMchat`).

---

## Useful grep patterns

| Pattern | Log file | Meaning |
|---------|----------|---------|
| `restoring session project` | app debug | Session restore → `activate_project` |
| `opening project path=` | app / daemon | Client or daemon project open |
| `scan-project` | daemon | Diagnostic scan mode (proposed) |
| `filesystem scan queued` / `returned` | daemon | Root `read_dir` timing |
| `scan done` | daemon | Full scan complete (proposed summary) |
| `send id=6.*activate_project` | app (`Client.vala`) | Activate RPC sent |
| `replied id=6` | app | Activate RPC completed |
| `recv id=6.*activate_project` | `ollmfilesd.debug.log` | Daemon received activate |
| `Connection.vala:149: recv` | daemon | All inbound RPC (watch for missing id=6/7) |

---

## Open questions

- Does early reply (current uncommitted `ProjectManager.vala`) emit `replied id=6` on client before scan finishes?
- Does failure also occur on **first** connection if the client pipelines id=6–7 before the daemon finishes prior work (no app restart)?
- Should `activate_project` with `skip_scan=true` be used on session restore when the daemon already has a warm DB for that project?
- Should the daemon cancel or coalesce overlapping `activate_project` calls from reconnecting clients?

---

## Next steps

1. **Step 0:** Add `--scan-project=PATH` to `ollmfilesd` (foreground, scan-only, phase timing logs, exit) — user runs manually on `OLLMchat` and captures `ollmfilesd.debug.log` baseline.
2. **Design Option B** — worker thread for `activate_project` filesystem scan (reuse `BackgroundScan` / old `ProjectManager`-on-worker patterns); keep `SQ.Database` + `db_mutex` on main and worker.
3. Define write-guard during scan (per project) and scan-done notification → client refresh (plan 2.10.4.30).
4. Re-run `--scan-project` + second-startup repro after Option B; compare timings and confirm `replied id=6` / `id=7` while scan runs on worker.
5. Follow-up: reconcile must not `delete_async` real source files (faiss wrapper incident).
