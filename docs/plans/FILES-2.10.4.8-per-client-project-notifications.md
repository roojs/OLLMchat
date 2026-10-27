# 2.10.4.8 — Per-client project context and file-change notifications

**Status:** PROPOSAL — **future**. **No implementation yet** (no project
interest wire, open-project monitor, routed notifications, or V2 signal
restore).

**Depends on:** [`2.10.4.4`](done/2.10.4.4-DONE-projectmanager.md) ✅–[`2.10.4.6`](done/2.10.4.6-DONE-file.md) cutover; [`2.10.4.7`](done/2.10.4.7-DONE-active-project-file-outside-db.md) (active project/file on client, not daemon DB)

**Related:** [`APP-4.2.3-background-sync-file-watcher.md`](APP-4.2.3-background-sync-file-watcher.md) (older watcher notes; this plan owns the current per-client/open-project design); [`2.10.4.4`](done/2.10.4.4-DONE-projectmanager.md) events section (`OLLMrpc.Client.notification`); [`CODER-4.2.7`](CODER-4.2.7-coder-view-outstanding.md) (file-navigation consumer)

**Parent:** [`FILES-2.10.4.0-summary.md`](FILES-2.10.4.0-summary.md) · **Cutover:** [`done/2.10.4.9-DONE-v2-caller-cutover.md`](done/2.10.4.9-DONE-v2-caller-cutover.md) · **Layout:** [`done/2.10.4.0-DONE-libocfiles-v2-and-rpc-layout.md`](done/2.10.4.0-DONE-libocfiles-v2-and-rpc-layout.md)

---

## Problem

With **multiple windows** (each with its own `V2/ProjectManager` + `OLLMrpc.Client`):

1. **Window A** edits and saves a file via `File.write` — handled; no issue.
2. **Window B** has the **same project** open — it should learn the file changed (reload banner, buffer conflict, etc.).
3. **An external editor** changes a file on disk — the **daemon** detects the change (file watcher) but must tell only windows that care (those working on **that project**), not every connected client.

Today there is **no** per-session project binding on the daemon and **no** `event.file.*` delivery to clients. V2 `ProjectManager` temporarily dropped `file_contents_changed` because scan/index moved to `File.write` on the server — but the **client still needs a local signal** when notifications arrive.

---

## Goal

The daemon knows **which project each RPC client (window) is working on**, so it can **route file-change notifications** to the right `OLLMrpc.Client` sessions.

Each window’s `V2/ProjectManager` keeps (or restores) **`file_contents_changed(File file)`** — emitted when that window’s client receives a relevant daemon notification, not when local `File.write` succeeds (daemon already queued scan/index on write).

---

## Open projects and monitor lifetime

- 🔷 Each window has one open project.
- 🔷 When a window opens or switches project, its RPC session registers that
  project with `ollmfilesd`.
- 🔷 Every project open in at least one connected window is monitored for
  filesystem changes.
- 🔷 Two or more windows on the same project share one daemon-side project
  monitor. Notification routing remains per client.
- 🔷 A project monitor stops when no connected session has that project open.
- 🔷 Reconnect restores the window's project interest after the RPC session is
  re-established.
- 🔷 The daemon owns monitoring and stored file state. A window does not
  monitor the filesystem itself.

---

## Folder and file freshness

- 🔷 Files created, removed, moved, or changed after the initial project scan
  must update the daemon's stored folder and file rows.
- 🔷 Folder and file navigation reads those current rows and receives a
  notification when visible data becomes stale.
- 🔷 Notifications must distinguish content changes from structural changes
  that affect folder or file lists.
- 🔷 A structural change includes file or directory create, delete, move, and
  rename.
- 🔷 ⏳ Decide whether requesting a folder also performs a shallow scan of
  that folder as recovery from a missed monitor event.
  - The recovery scan would inspect direct children only.
  - It would not recursively scan descendants.
  - Its response would include changes found by that scan.
- 💩 ⏳ Decide whether the recovery scan belongs in `Folder.fetch_dir`, in a
  separate refresh call, or before the existing request.
- 💩 ⏳ Decide whether repeated folder access needs a short freshness window.

---

## Target model

```text
Window A (project /home/a/proj1)          Window B (project /home/a/proj2)
        │                                          │
        ▼                                          ▼
   OLLMrpc.Client A                          OLLMrpc.Client B
   watch: proj1                               watch: proj2
        │                                          │
        └──────────────┬───────────────────────────┘
                       ▼
                  ollmfilesd
            Session → project_path map
            file watcher / cross-window write
                       │
         event.file.changed { path, mtime, ... }
                       │
              route to clients where
              file.path under session.project_path
                       │
                       ▼
              OLLMrpc.Client.notification
                       │
                       ▼
         V2 PM → file_contents_changed(file)
                       │
                       ▼
              UI (reload banner, etc.)
```

| Piece | Owner |
| ----- | ----- |
| Which project **this window** shows | Client `active_project` ([`2.10.4.7`](done/2.10.4.7-DONE-active-project-file-outside-db.md)) |
| Tell daemon “I am on project X” | Client RPC when project opens / changes (TBD method name) |
| Detect disk change | Daemon file watcher ([`4.2.3`](APP-4.2.3-background-sync-file-watcher.md)) |
| Route notification to sessions | Daemon `Listen` / `Session` — match path prefix to registered project |
| Local UI hook | `V2/ProjectManager.file_contents_changed` |

---

## Wire (TBD — document only)

**Client → daemon (register interest):**

- When local `activate_project` / open project: e.g. `ProjectManager.watch_project` with `params.path` (project root).
- On project switch: update watch; on disconnect: drop session entry.
- Optional: `params.client` / window id from hello already identifies session — project path is the extra binding.

**Daemon → client (notification):**

- e.g. `event.file.changed` — `params.path`, `mtime`, maybe `origin` (`external` | `peer` | `self`) so UI can suppress echo for own save.
- Only sent to sessions whose watched project contains `path`.
- See [`2.10.4.6`](done/2.10.4.6-DONE-file.md) events table — extend beyond `event.file.added`.

**Not in scope for v1 tranche:** full event catalog, watcher implementation, UI reload policy.

---

## Client handling (when implemented)

1. `OLLMrpc.Client.notification` → V2 PM handler (or thin relay on PM).
2. If `notification.method` is `event.file.changed` (or similar):
   - Resolve `File` for `param.path` (cache / `get_file_from_active_project` / lazy RPC).
   - If path is under `this.active_project`: emit **`file_contents_changed(file)`**.
3. Window / `SourceView` connects as today on shipping PM — reload banner, `check_active_file_changed`, etc.

**Do not** reintroduce `on_file_contents_change()` as a post-`File.write` client hook — write path stays fire-and-forget; notifications are the cross-window / external-change path.

---

## Scenarios

| Scenario | Expected behaviour |
| -------- | ------------------- |
| Window A saves file in proj1 | A: buffer cleared locally; B on proj1: notification → reload/conflict UI; B on proj2: nothing |
| External edit to file in proj1 | All sessions watching proj1 get `event.file.changed` |
| Window switches project | Client sends new watch; old project notifications stop for that session |
| No project open | Client sends empty watch or disconnect; no file events |

---

## Open questions (decide before coding)

1. **Watch granularity** — one project path per session, or list (multi-root later)?
2. **Same file, two windows, same project** — both get notification; conflict UI per window (existing `FileUpdateStatus`)?
3. **Notification vs refresh** — is `File.changed.check` on focus sufficient,
   or should folder access perform the shallow recovery scan described above?
4. **Peer write origin** — suppress notification to the session that performed `File.write`, or always broadcast to other sessions on same project?
5. **Relationship to vector scan** — daemon queues index on write; notification is separate UI concern (do not conflate with `BackgroundScan` on client).
6. **Monitor implementation** — recursive watcher, watched-directory set, or
   another daemon-side mechanism?
7. **Structural events** — one folder-invalidated event or separate added,
   removed, and moved events?

---

## Phased delivery (this plan only)

| Phase | What |
| ----- | ---- |
| **A** | Lock wire names in [`2.10.4.1`](FILES-2.10.4.1-ollmfilesd-rpc-api.md) / [`2.10.4.6`](done/2.10.4.6-DONE-file.md) |
| **B** | Daemon session registry: `OLLMrpc.Client` session id → watched project path |
| **C** | Monitor every project referenced by at least one live session; update stored rows |
| **D** | Emit content and structural file events; route them by project |
| **E** | V2 PM: restore change signals; connect `OLLMrpc.Client.notification` |
| **F** | Window UI: reload/conflict handling and folder/file-list refresh |

---

## Test plan (when implementing)

1. Two windows, same project — save in A → B gets notification (not A, if origin suppressed).
2. Two windows, different projects — save in A → B silent.
3. External `touch` on file under proj1 → only windows watching proj1 notified.
4. Switch project on window — notifications follow new project only.
5. Daemon restart — clients re-watch on reconnect.
6. Create, remove, rename, and move files externally — stored folder/file rows
   and open navigation update without reopening the project.
7. Two windows on one project — one daemon monitor, notifications delivered
   to both sessions.
8. Close or switch the last window using a project — its monitor is released.

---

## Summary

Multi-window needs the **daemon to know each client’s project**, not a global active project. File changes (peer window or external editor) arrive as **`OLLMrpc.Client.notification`**; **`V2/ProjectManager.file_contents_changed`** remains the local signal for UI. **No code until** 2.10.4.4–7 cutover and watcher plan are ready.
