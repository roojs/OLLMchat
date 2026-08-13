# Changed-files notification → Approvals icon / open in editor

**Status:** ⏳ OPEN — daemon `File.write` creates pending approval; live UI path still untested

**Started:** 2026-08-12 · **Updated:** 2026-08-13

---

## Problem

🔷 Create a Hello World file under the project **`docs/`** directory **via our API** (`File.write` / tools that call it — not a raw disk copy). Expected end-to-end:

1. **Daemon** creates a pending-approval record for that file.
2. **Backend → frontend notification** that the changed-file list should refresh.
3. **Approvals control** (top-right header, next to save) becomes visible / clickable and shows the pending file(s).
4. Selecting a row **opens that file in the editor** (`SourceView`).

🔷 **Actual (user smoke):** Approvals icon / list did not reflect the new file.

🔷 Scope is the **API create → notify → Approvals → open** path.  
🚫 Not about manually copying a file onto disk outside the API (agent misread that earlier as “external drop”).

---

## Reproduction

1. Open app with a project that has a `docs/` tree.
2. Create a small Hello World file under `docs/` **through the API** (`File.write` / write_file tool / equivalent).
3. Watch header Approvals control and daemon→client notifications.
4. **Expected:** pending list updates; icon usable; click opens file in editor.
5. **Actual:** no observed Approvals update for that file.

---

## Related

ℹ️ Approvals UI + `ReviewFiles` refresh on `event.project.invalidate_cache`:

- `liboccoder/Approvals.vala` — `rpc.notification` → `review_files.refresh.begin()` when method is `event.project.invalidate_cache`
- `liboccoder/SourceView.vala` — same notification refreshes file dropdown; `approvals.file_selected` → `open_file`
- Daemon emit: `ollmfilesd/File.vala` (`File.write` / `to_real`) — `event.project.invalidate_cache`

ℹ️ Pending list RPC: `Folder.fetch_pending_approvals` → client `libocfiles/ReviewFiles.vala`

ℹ️ Prior related: [`2026-07-27-write-file-no-project-index-ui.md`](2026-07-27-write-file-no-project-index-ui.md)

ℹ️ Editor open: `Approvals.update_selected_file()` only emits `file_selected` if `file_cache.get(row.path)` is non-null.

---

## Hypotheses

💩 **H1 — Daemon never creates a pending-approval record on API write.**  
✔️ **Ruled out 2026-08-13:** `File.write` via `ollmfilesd --rpc-script` **does** create the record (see Evidence).

💩 **H2 — Record exists, but live app never gets / never acts on the notify** (`event.project.invalidate_cache` → Approvals refresh).  
⏳ Next to test against a live window (or client connected to daemon).

💩 **H3 — Notify handled, but Approvals / `ReviewFiles` refresh still wrong** (empty list, wrong project path, etc.).  
⏳ After H2.

💩 **H4 — List OK, open broken:** row visible but `file_cache` miss blocks editor open.  
⏳ After list works.

---

## Evidence

### Probe A — API `File.write` creates approval ✔️

Tool: `build/ollmfilesd/ollmfilesd --interactive --rpc-script=…`

1. `ProjectManager.create_project` + `activate_project`
2. `File.write` → `docs/hello-via-write.txt`
3. `Folder.fetch_pending_approvals`

**Result** (`/tmp/ollm-approval-probe-wIdN`):

- Write: `msg: ok`
- Pending: one `FileWithHistory`, `last-change-type: added`, `approve-id: 1`
- SQLite: `is_need_approval=1`, `file_history` `added` / `status=0`
- Notification: `event.project.invalidate_cache` with project path

→ Step 1 of the expected chain works at the daemon/API layer.

### Out of scope (agent misread)

ℹ️ Earlier “Probe B / external drop” used raw disk `printf` with no API. **User clarified that is not the scenario under test.** Left only as a note so we don’t chase it again.

### Client receive path (code review 2026-08-13)

Chain when a notify arrives on the app’s `OLLMrpc.Client`:

1. **`libocrpc/Client.vala` `dispatch_message`**  
   - ✔️ **Has debug:** `notification method=%s object_type=%s`  
   - Then emits `this.notification(notif)`.

2. **`liboccoder/Approvals.vala` ctor** (listener):  
   - If `method != "event.project.invalidate_cache"` → return.  
   - Else `review_files.refresh.begin()` (no path filter).  
   - 🚫 **No `GLib.debug` here.**

3. **`ReviewFiles.refresh()`** → `Folder.fetch_pending_approvals` → replace list → `items_changed` + `refreshed()`.  
   - `refreshed` → `Approvals.update_button_visibility()` (show next-button if `get_n_items() > 0`).  
   - 🚫 **No `GLib.debug` in refresh / fetch_pending / visibility.**

4. **Parallel:** `SourceView` also listens — same method, **plus** requires `notif.message == active_project.path`, then refreshes file dropdown only.  
   - 🚫 **No debug** on that branch either.

5. **`Window`** also forwards every RPC notify (via Idle) to `ActivityBanner` — banner has **no** case for `invalidate_cache` (scan/vector only). Harmless for Approvals; Approvals is wired directly on `rpc.notification`.

**Live check with `--debug`:** look for, in order:

1. Client: `notification method=event.project.invalidate_cache` — wire reached client
2. Approvals: `invalidate_cache received message=… — refreshing review_files` — Approvals handler ran
3. ReviewFiles: `review_files refresh done old=N new=M` — fetch finished; `new>0` means pending rows returned

If (1) missing → H2. If (1)+(2) but `new=0` or icon still hidden → H3. If `new>0` but icon still hidden → visibility/open path (H3/H4).

---

## Root cause

⏳ Unknown for the UI failure — daemon approval-on-write is fine; break is later (notify delivery or Approvals client).

---

## Proposed fix

⏳ None yet — debug the live notify → Approvals path next.

---

## Attempts / changelog

- ✔️ 2026-08-12 — Bug log created.
- ✔️ 2026-08-13 — CLI Probe A: `File.write` creates pending approval + `invalidate_cache`.
- ✔️ 2026-08-13 — User correction: scope is **API create**, not disk-only drop; bug log refocused.
- ✔️ 2026-08-13 — Reviewed client receive path: only `OLLMrpc.Client` logged the notify.
- ✔️ 2026-08-13 — Added temporary debug: Approvals on `invalidate_cache`; `ReviewFiles.refresh` old/new counts.

---

## Next

⏳ 🔷 Run app with `--debug`, API-create under `docs/`, grep client log for `notification method=event.project.invalidate_cache` (H2 vs H3).

⏳ 🔷 If list has a row but click does not open → H4 (`file_cache`).

⏳ Propose fix with fences; await apply approval.
