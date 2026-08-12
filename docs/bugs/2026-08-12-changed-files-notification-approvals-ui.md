# Changed-files notification → Approvals icon / open in editor

**Status:** ⏳ OPEN — symptom logged; not yet debugged

**Started:** 2026-08-12

---

## Problem

🔷 User dropped a simple **Hello World** file into the project **`docs/`** directory (active project). Expected end-to-end:

1. **Daemon** notices the new/changed file and updates pending / changed-file state.
2. **Backend → frontend notification** that the changed-file list should refresh.
3. **Approvals control** (top-right header, next to save) becomes visible / clickable and shows the pending file(s).
4. Selecting a row **opens that file in the editor** (`SourceView`).

🔷 **Actual:** No usable UI update observed — Approvals icon / list did not reflect the new file after the drop.

🔷 Class as a **bug** even where pieces are unfinished wiring: the intended product path (external or daemon-detected change → Approvals list → open) is broken or incomplete for this smoke test.

---

## Reproduction (user)

1. Open app with a project that has a `docs/` tree.
2. Create / copy a small Hello World file under `docs/` on disk (outside the in-app editor / tools path).
3. Watch header Approvals control (top-right) and any daemon→client notification activity.
4. **Expected:** list updates; icon usable; click opens file in editor.
5. **Actual:** no observed Approvals update for that file.

---

## Related (pointers only — not root cause yet)

ℹ️ Approvals UI + `ReviewFiles` client refresh on `event.project.invalidate_cache`:

- `liboccoder/Approvals.vala` — `rpc.notification` → `review_files.refresh.begin()` when method is `event.project.invalidate_cache`
- `liboccoder/SourceView.vala` — same notification refreshes file dropdown; `approvals.file_selected` → `open_file`
- Daemon emit sites today: `ollmfilesd/File.vala` (write / register / `to_real`-style paths) — `event.project.invalidate_cache` with project path in `message`

ℹ️ Pending list RPC: `Folder.fetch_pending_approvals` → client `libocfiles/ReviewFiles.vala` (`fetch_pending` / `refresh`). Client also refreshes on project activate and after approve/reject / some tools — **not** on arbitrary disk drops unless a notification arrives.

ℹ️ Planned / unfinished notification + watcher work:

- [`docs/plans/2.10.4.8-per-client-project-notifications.md`](../plans/2.10.4.8-per-client-project-notifications.md) — **FUTURE** — per-client project watch + `event.file.*` routing
- [`docs/plans/4.2.3-background-sync-file-watcher.md`](../plans/4.2.3-background-sync-file-watcher.md) — **TODO** — filesystem watcher
- [`docs/plans/done/2.10.4.14-DONE-daemon-scan-update-notification.md`](../plans/done/2.10.4.14-DONE-daemon-scan-update-notification.md) — vector `scan_update` only (not Approvals list)
- [`docs/plans/done/2.10.4.26-DONE-file-history-approval-knock-on.md`](../plans/done/2.10.4.26-DONE-file-history-approval-knock-on.md) — Approvals / `ReviewFiles` V2 wire

ℹ️ Prior similar symptom (tool write path, not necessarily external drop):

- [`docs/bugs/2026-07-27-write-file-no-project-index-ui.md`](2026-07-27-write-file-no-project-index-ui.md) — write/edit_mode create → pull-down + changed-files empty; `invalidate_cache` / `review_files` issues

ℹ️ Editor open from Approvals:

- `Approvals.update_selected_file()` only emits `file_selected` when `project_manager.file_cache.get(row.path)` is non-null.
- 💩 If a pending row exists in `ReviewFiles` but the `File` is not yet in client `file_cache`, click may update selection without opening the editor — separate failure mode to check once the list populates.

---

## Hypotheses (unconfirmed)

💩 **H1 — No daemon detect:** External add under `docs/` is never registered / never marked `is_need_approval` (watcher missing; scan doesn’t treat drop as pending). → `fetch_pending_approvals` would stay empty even after a manual refresh.

💩 **H2 — Detected but no notify:** Daemon updates DB / history, but never sends `event.project.invalidate_cache` (or a dedicated pending-list event) for this path. → Approvals stays stale until project re-activate / other refresh trigger.

💩 **H3 — Notify but client ignore / mismatch:** Notification arrives but `message` ≠ `active_project.path` (SourceView filters that way for dropdown; Approvals currently does **not** filter by path) or client RPC/notification path broken.

💩 **H4 — List OK, open broken:** Approvals shows the file, but `file_cache` miss prevents `file_selected` → editor open.

---

## Evidence

⏳ None captured yet this session (no `--debug` log slice, no SQLite pending check, no confirmation whether `invalidate_cache` fired).

Suggested first checks when debugging starts:

1. Disk: confirm Hello World path under active project root.
2. Daemon log: any register / history / `invalidate_cache` / filesystem scan around the drop time (`~/.cache/ollmchat/ollmfilesd.debug.log`).
3. Client log: `event.project.invalidate_cache` / `Folder.fetch_pending_approvals` (`~/.cache/ollmchat/ollmchat.debug.log` with `--debug`).
4. DB: `filebase` row for path; `is_need_approval`; `file_history` pending rows (`~/.local/share/ollmchat/files.sqlite`).
5. After force `review_files.refresh` (e.g. re-activate project): does Approvals light up? Isolates H1 vs H2.

---

## Root cause

⏳ Unknown — await evidence.

---

## Proposed fix

⏳ None yet — debug first per `docs/bug-fix-process.md`. Do **not** paper over with polling-only UI or defensive null caches; fix detection and/or notification and/or open-from-cache at the real break.

---

## Scope notes (product)

🔷 Notification → Approvals refresh is the primary broken loop for this report.

🔷 Opening the selected changed file in the editor is in scope for the same bug once the list works (or in parallel if list already works and only open fails).

ℹ️ Full multi-window routing may still live under **2.10.4.8**; this bug is the **single-window** smoke path: external/daemon-known change → UI list → open.

---

## Attempts / changelog

- ✔️ 2026-08-12 — Bug log created from user smoke test (Hello World under `docs/`).

---

## Next

⏳ 🔷 Reproduce with `--debug`; capture daemon + client logs around the drop.

⏳ 🔷 Confirm whether pending row exists in DB after drop (H1 vs H2).

⏳ 🔷 If list refreshes only after project re-activate, focus on missing notification emit for external/scan discovery.

⏳ 🔷 If list has row but click does not open, check `file_cache` miss in `Approvals.update_selected_file` (H4).

⏳ Propose root-cause fix with Remove/Replace/Add fences; await apply approval.
