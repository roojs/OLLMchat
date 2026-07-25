# write_file: disk ok, not indexed → empty file dropdown / no UI refresh

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ⏳ A + B + C applied; await ✅ verify (cold open during scan →
Loading… then `total ≥ 1`)

**Started:** 2026-07-25

---

## Scoreboard (where we are)

User said apply fences in this bug log. Only **complete Remove/Replace/Add
code fences** count. Prose / 💩 “confirm helper” does **not**.

| Item | Fence complete? | User approved apply? | Applied in tree? | Notes |
|------|-----------------|----------------------|------------------|-------|
| **A** WriteFile prefix gate | ✔️ | 🔷 yes | ✔️ | `liboctools/WriteFile/Request.vala` |
| **A** EditMode prefix gate | ✔️ | 🔷 yes | ✔️ | `liboctools/EditMode/Stream.vala` (`sync_and_update_metadata` only) |
| **B** client `loading` on refresh | ✔️ | 🔷 yes | ✔️ | `libocfiles/ProjectFiles.vala` |
| **B** daemon hold `fetch_files` until scan idle | ✔️ | 🔷 yes | ✔️ | `wait_scan_idle` + `fetch_files_reply` |
| **C** notify after `to_real` | ✔️ | 🔷 yes | ✔️ | `ollmfilesd/File.vala` |
| **C** SourceView pull-down on notify | ✔️ | 🔷 yes | ✔️ | `liboccoder/SourceView.vala` |
| **C** Approvals refresh on notify | ✔️ | 🔷 yes | ✔️ | `liboccoder/Approvals.vala` |
| 💩 invalidate on every write (not only `to_real`) | n/a | 🚫 not confirmed | 🚫 | Minimal ship remains `to_real` only |
| **D** SourceView last-line / scroll | separate bug | separate | separate | [`2026-07-25-sourceview-open-shows-only-last-line.md`](2026-07-25-sourceview-open-shows-only-last-line.md) |

**Git reality check:**

- Changed: WriteFile, EditMode/Stream, ProjectFiles, ollmfilesd/File,
  Approvals, SourceView, ollmfilesd/Folder, ollmfilesd/ProjectManager.

**Still open for ✅:** cold open during scan → Loading… then `total ≥ 1`.

---

**Related:**

- ℹ️ Plan under test: [`docs/plans/2.22-write-file-tool.md`](../plans/2.22-write-file-tool.md)
- ℹ️ EditMode shares the same `is_in_project` / `contains_folder` gate:
  `liboctools/EditMode/Stream.vala` (`sync_and_update_metadata`)
- ℹ️ Client list contract: `libocfiles/ProjectFiles.vala` — *call `refresh`
  after index changes (open project, write file, approvals, notifications)*
- ℹ️ Per-file **banner** notifications **not** in scope here:
  [`docs/plans/2.10.4.8-per-client-project-notifications.md`](../plans/2.10.4.8-per-client-project-notifications.md)
  — 🔷 list sync uses an **internal** “file list invalid” notify from the
  daemon, not an activity-banner event.
- ℹ️ Debug logs: `~/.cache/ollmchat/ollmchat.debug.log`,
  `~/.cache/ollmchat/ollmfilesd.debug.log`
- ℹ️ DB: `~/.local/share/ollmchat/files.sqlite`
- ℹ️ Session: `~/.local/share/ollmchat/history/2026/07/25/15-01-30.json`
  (agent `code-assistant`, project `/home/alan/gitlive/app.RooTerm`)
- ℹ️ **Editor open follow-on (Gtk SourceView):** after the file finally
  appeared in the pull-down, opening it showed only the last line — logged in
  [`2026-07-25-sourceview-open-shows-only-last-line.md`](2026-07-25-sourceview-open-shows-only-last-line.md)
  and summarized under **Problem → D** below.
- ℹ️ Changed-files / approvals UI: `liboccoder/Approvals.vala` +
  `ProjectManager.review_files` (`fetch_pending_approvals`)

---

## Problem

🔷 After a successful `write_file` (new plan under a newly created
`docs/plans/`), the user expected either:

- the **file dropdown** (editor file pull-down) to show the new file
  (or otherwise look “dirty” / refreshed), and/or
- the **Changed files** / approvals indicator to reflect that something was
  added/changed and needs approval.

🔷 Actual: chat UI reported the write succeeded with **`Project file: no`**.
Opening the file pull-down showed **no results**. Disk file exists:

`/home/alan/gitlive/app.RooTerm/docs/plans/0.1-base-plan.md`

🔷 **Also after close + reopen:** file list still does **not** show the file,
even though the user expects a fresh project open / filesystem scan to include
it.

🔷 **D — Gtk SourceView after open:** Once the file finally showed in the
pull-down and was selected, the **SourceView did not present the file
normally** — only the last line (≈ line 16 / EOF caret) was in view; the rest
of the content felt hidden (scroll/layout). That is a **separate** editor bug,
tracked in full here:

→ [`2026-07-25-sourceview-open-shows-only-last-line.md`](2026-07-25-sourceview-open-shows-only-last-line.md)

### Reproduction (observed)

1. Active project: `app.RooTerm` (nearly empty — only the new tree under `docs/`).
2. Model: `mkdir -p docs/plans` via `run_command` (sandbox), then
   `write_file` → `docs/plans/0.1-base-plan.md` (`complete_file`).
3. Chat success frame: *Successfully wrote file … / Project file: no*.
4. File dropdown: empty / no new file.
5. Quit app, reopen, open project / file pull-down → still empty.

---

## Evidence

### Session / UI

- ✔️ `15-01-30` tool reply: file written, 16 lines.
- ✔️ UI frame (msg 33):

  ```text
  Successfully wrote file: …/docs/plans/0.1-base-plan.md
  Project file: no
  ```

- ✔️ On disk: file present (`ls` after the run).

### Files daemon (ollmfilesd) RPC — not missing write

From `ollmchat.debug.log` at `15:04:01`:

- ✔️ `id=24` `Folder.contains_folder` → replied
- ✔️ `id=25` `File.write` → replied
- ✔️ **No** `File.register` / client `to_real` after that
- ✔️ Tool completed: *File '…/0.1-base-plan.md' written. 16 lines.*

So the write **did** go through the files daemon; registration did not.

### Code path that produced `Project file: no`

`liboctools/WriteFile/Request.vala` after apply:

```vala
var is_in_project = (this.file.id > 0);
if (!is_in_project && project_manager.active_project != null) {
    var dir_path = GLib.Path.get_dirname(this.normalized_path);
    if (yield project_manager.active_project.contains_folder(dir_path)) {
        is_in_project = true;
    }
}
// …
if (change_type == "added" && this.file.id <= 0 && is_in_project) {
    yield this.file.to_real();  // → File.register
}
// …
if (is_in_project) {
    yield project_manager.review_files.refresh();
}
```

- ✔️ Permission skip uses **path prefix under project** (`build_perm_question`)
  → log: *Tool 'write_file' does not require permission*.
- 🔷 **Permission behaviour is correct / expected.** Under-project paths must
  **not** prompt. The tool correctly treated the path as in-project for
  permission (prefix check: `dir_path == project_path` or
  `dir_path.has_prefix(project_path + "/")`). No change wanted there.
- ✔️ **Same write** then uses a **stricter** gate for register: `is_in_project`
  via **`Folder.contains_folder`** on the **exact parent dir** (`…/docs/plans`).
- ✔️ Daemon `contains_folder` (`ollmfilesd/Folder.vala`) returns true only if
  `project_files.folder_map.has_key(p.path)`. New dirs from `mkdir` are **on
  disk but not in `folder_map`** → reply is not `"true"` → client treats as
  outside project **for index only**.
- ✔️ Consequence: skip `to_real()` / `File.register`, skip
  `review_files.refresh()`, UI prints **Project file: no** — even though
  permission already decided “in project”.

🔷 **Inconsistency to fix:** permission “in project” ≠ register “in project”.
Prefix under active project should be enough to **create missing parent
folders in the index, then register the file** (as permission already
assumes), not “only if the exact parent leaf is already in `folder_map`”.

### Why `to_real` would likely have worked if called

Daemon `File.to_real` (`ollmfilesd/File.vala`) uses
`find_container_of(dirname)` — walks **up** until an indexed folder (typically
project root) — then `make_children` creates missing folder rows and indexes
the file. The WriteFile gate requires the **leaf** dir already in
`folder_map`, so new subtrees never reach that path.

### UI refresh / notification gaps (second layer)

Even when registration succeeds, today:

- ℹ️ `WriteFile.Tool.change_done` / `EditMode.Tool.change_done` — **no
  `.connect` anywhere** in the tree — and 🔷 **should not** be how the file
  list stays in sync (daemon notifies invalidate instead).
- ℹ️ Post-write client refresh is only `review_files.refresh()` (approvals
  list), **not** `FileDropdown` / client `ProjectFiles.refresh`.
- ℹ️ Client `ProjectFiles` docblock says callers must `refresh` after write;
  FileDropdown only refreshes on project switch / search / scroll.
- ℹ️ Activity banner handles `event.filesystem.scan_*` only.
  🔷 **No** banner for file-list invalidate — that signal is internal UI sync
  only.

So “stale/empty file pull-down” after a live write is expected with the current
wiring, and empty dropdown is especially visible when the project had **no
other indexed files** (RooTerm after this run).

### Close / reopen still empty — scan wins, UI loses the race

User closed and reopened; file list still empty. Evidence at **15:10:54**:

Client (`ollmchat.debug.log`):

```text
15:10:54.315  opening project path=…/app.RooTerm
15:10:54.315  Folder.fetch_files
15:10:54.318  ProjectFiles refresh done query= total=0 loaded=0
15:10:54.322  ProjectManager.activate_project
15:10:54.357  event.filesystem.scan_start / scan_end
```

Daemon (`ollmfilesd.debug.log`):

```text
15:10:54.356  filesystem scan queued …/app.RooTerm
15:10:54.442  filesystem scan complete …
15:10:54.465  vector index queued 1 files for project …
15:10:54.475  vector index file=…/docs/plans/0.1-base-plan.md
```

SQLite after that reopen (`files.sqlite` `filebase`):

| id | path | base_type |
| -- | ---- | --------- |
| 110453 | `…/app.RooTerm` | `d` (project) |
| 110454 | `…/docs` | `d` |
| 110455 | `…/docs/plans` | `d` |
| 110456 | `…/0.1-base-plan.md` | `f`, `is_text=1`, language `markdown` |

✔️ So after reopen the **daemon scan did pick up the file** and wrote it to
DB (and vector-indexed it). The UI file list stayed empty because:

1. `activate_project` sets `active_project` and emits `active_project_changed`
   **before** the fire-and-forget RPC / `read_dir` finishes.
2. `SourceView.apply_manager_state` / `open_project` immediately
   `FileDropdown.update_project` → `Folder.fetch_files` while daemon
   `project_files` is still empty → **`total=0 loaded=0`**.
3. Activity banner handles `event.filesystem.scan_end` (label only) — **no**
   `FileDropdown` / `ProjectFiles.refresh` on scan end.
4. No later `fetch_files` in the client log for that session.

🚫 Close/reopen failure is **not** “scan ignored the file”. Scan worked;
dropdown never reloaded after scan.

---

## Root cause

✔️ **A — Write-time register skip (permission OK, index not):** Permission
correctly skipped for a path under the active project (prefix). Register then
used `contains_folder(exact parent)`, which is false for **new** dirs not yet
in `folder_map`. WriteFile therefore skipped `File.register` (`to_real`) and
approvals refresh — UI **Project file: no** — despite permission already
treating the path as in-project.

🚫 Do **not** “fix” by prompting for permission on under-project paths.

✔️ **B — Open-project race (explains close/reopen):** File dropdown calls
`fetch_files` **while** filesystem `read_dir` is still running (or before it
starts). Daemon replies immediately with an empty/stale list; nothing waits
for scan. After reopen the scan *does* index the file into DB, but the UI
already painted `total=0`.

🔷 **B fix direction (user):** hold `fetch_files` until scanning stops
(global idle). New methods: `ProjectManager.wait_scan_idle`, and Folder
`fetch_files_reply` (async — so connect can `.begin` and the body can
`yield wait_scan_idle`). Connect keeps project-not-found; everything from
`if (p.paths.length > 0)` lives in `fetch_files_reply`. UI keeps loading —
one reply, no second reload.

🚫 **Superseded:** duplicated reply body + `scanning.has_key(project.path)`;
inline `wait_scan_idle.begin` with reply stuffed in the end-callback.

💩 **C — Live write UI:** After index changes from a write/register, nothing
tells the file pull-down its list is stale. Tool → UI hooks are the wrong
layer; the **file server** should notify.

🔷 **C fix direction (user):** On write/register that changes the index, the
**file daemon** emits an **internal** notify (not a banner). UI: invalidate /
reload the file pull-down; **Changed files / approvals** should watch the
same class of notify (or a sibling “added/changed → approval flow”) and
refresh `review_files` — not the tool calling into Approvals.

🚫 Not a failed `File.write` — daemon write succeeded; disk has the file.
🚫 Not “reopen never scans” — scan indexed the file; UI did not refetch.

---

## Proposed fix (fences)

ℹ️ **Scoreboard above is authoritative** for applied vs not. Fences below are
the reviewed text for each item.

### Labels on each fence

| Marker on a fence | Meaning |
|-------------------|---------|
| ✔️ applied | In the working tree now |
| ⏳ needs complete fence | Intent 🔷; code not ready to apply |
| 🚫 do not apply | Incomplete / invalid stub |

---

### A — `liboctools/WriteFile/Request.vala` — `execute_request` gate

**✔️ applied**

#### Remove

```vala
			var is_in_project = (this.file.id > 0);
			if (!is_in_project && project_manager.active_project != null) {
				var dir_path = GLib.Path.get_dirname(this.normalized_path);
				if (yield project_manager.active_project.contains_folder(dir_path)) {
					is_in_project = true;
				}
			}
```

#### Replace with

Same place after `apply_change` succeeds — under-project prefix (match
`build_perm_question`), not `contains_folder`. `dir_path` once; no
`project_path` temp; short `if` to set the flag.

```vala
			var dir_path = GLib.Path.get_dirname(this.normalized_path);
			var is_in_project = this.file.id > 0;
			if (!is_in_project && project_manager.active_project != null
				&& (dir_path == project_manager.active_project.path
					|| dir_path.has_prefix(project_manager.active_project.path + "/"))) {
				is_in_project = true;
			}
```

### A — `liboctools/EditMode/Stream.vala` — `sync_and_update_metadata` gate

**✔️ applied**

#### Remove

```vala
			var is_in_project = (this.file.id > 0);
			
			if (!is_in_project && this.file.manager.active_project != null) {
				if (yield this.file.manager.active_project.contains_folder(
					GLib.Path.get_dirname(this.request.normalized_path)
				)) {
					is_in_project = true;
				}
			}
```

#### Replace with

Same place at start of `sync_and_update_metadata` — same shape.

```vala
			var dir_path = GLib.Path.get_dirname(this.request.normalized_path);
			var is_in_project = this.file.id > 0;
			if (!is_in_project && this.file.manager.active_project != null
				&& (dir_path == this.file.manager.active_project.path
					|| dir_path.has_prefix(this.file.manager.active_project.path + "/"))) {
				is_in_project = true;
			}
```

---

### B — `ollmfilesd/ProjectManager.vala` — `wait_scan_idle`

**✔️ applied**

### B — `ollmfilesd/Folder.vala` — `call_fetch_files` → `fetch_files_reply`

**✔️ applied**

### B — `libocfiles/ProjectFiles.vala` — `refresh` sets `loading`

**✔️ applied**

#### Remove

```vala
		public async void refresh(string query = "")
		{
			this.query = query;
			this.offset = 0;
			this.total = 0;

			var old_n_items = this.items.size;
			this.items.clear();

			var response = yield this.project.fetch_files(0, 50, query);
```

#### Replace with

```vala
		public async void refresh(string query = "")
		{
			this.query = query;
			this.offset = 0;
			this.total = 0;

			var old_n_items = this.items.size;
			this.items.clear();

			this.loading = true;
			var response = yield this.project.fetch_files(0, 50, query);
			this.loading = false;
```

---

### C — `ollmfilesd/File.vala` — notify after `to_real`

**✔️ applied** (`to_real` only — 💩 write-path emit still unconfirmed)

#### Add

After `new_file_added(this);` at end of `to_real`:

```vala
			this.manager.notification(new OLLMrpc.Notification() {
				method = "event.project.invalidate_cache",
				object_type = "Project",
				message = this.manager.active_project.path
			});
```

💩 Also emit after successful write/`realize` for already-indexed files so
approvals refresh without tool→UI — **confirm**. Minimal first ship:
**`to_real` only**; keep client `review_files.refresh()` until then.

### C — `liboccoder/SourceView.vala` — reload pull-down on notify

**✔️ applied**

#### Add

In ctor after `file_dropdown` is created:

```vala
			this.manager.rpc.notification.connect((notif) => {
				if (notif.method != "event.project.invalidate_cache") {
					return;
				}
				if (this.manager.active_project == null) {
					return;
				}
				if (notif.message != this.manager.active_project.path) {
					return;
				}
				this.file_dropdown.refresh.begin();
			});
```

### C — `liboccoder/Approvals.vala` — refresh pending on notify

**✔️ applied**

#### Add

Next to existing `review_files.refreshed` connect:

```vala
			this.project_manager.rpc.notification.connect((notif) => {
				if (notif.method != "event.project.invalidate_cache") {
					return;
				}
				this.project_manager.review_files.refresh.begin();
			});
```

---

## Attempts / changelog

- ✔️ Investigated session `15-01-30` / reopen race `15:10:54`.
- 🚫 Agent shipped unfenced `reply_fetch_files` / lambda — **reverted**.
- ✔️ Applied (fenced): A WriteFile + EditMode; B client loading; C notify +
  SourceView + Approvals.
- 🚫 B-daemon duplicated-body / `has_key(project.path)` fence — **superseded**.
- 🚫 Agent proposed Folder `fetch_files` helper — **rejected** at the time.
- 🚫 Inline `wait_scan_idle.begin` + reply-in-callback — **superseded**.
- ✔️ B-daemon applied: `ProjectManager.wait_scan_idle` + Folder
  `fetch_files_reply` (`.begin` from connect; `yield` inside). `ollmfilesd`
  builds clean.

---

## Next

1. ⏳ 🔷 Verify A/C: mkdir + write → `Project file: yes` + list + Changed-files.
2. ⏳ 🔷 Cold open during scan → Loading… then `total ≥ 1`.
3. ⏳ **D** → separate bug log.
4. ⏳ When all ✅: move to `docs/bugs/done/` with `FIXED`.
