# Open editor not reloaded after LLM write

**Status:** ✅ FIXED — user closed 2026-09-02 (editor reload after LLM write of clean open file)

**Started:** 2026-08-15

**Related:**

- ✅ [`done/2026-08-12-FIXED-changed-files-notification-approvals-ui.md`](done/2026-08-12-FIXED-changed-files-notification-approvals-ui.md)
- ✅ [`done/2026-08-15-FIXED-approvals-click-no-approve-reject.md`](done/2026-08-15-FIXED-approvals-click-no-approve-reject.md)
- ✅ [`done/2026-08-15-FIXED-approvals-approve-noop.md`](done/2026-08-15-FIXED-approvals-approve-noop.md)

**Process:** `docs/bug-fix-process.md` — edits are **Remove** / **Replace with** / **Add** from `docs/guide-to-writing-plans.md`.

---

## Problem

🔷 LLM edited the already-open file (`docs/Hello World Test` — add more lines). Write succeeded. Approve / Reject appeared (file was open). **Editor content did not update.**

🔷 If the open buffer is **not dirty**, reload it from the written file. If it **is** dirty, keep the existing overwrite/refresh banner.

---

## Reproduction

1. Open `docs/Hello World Test` in the editor (clean buffer).
2. Ask the agent to write more lines into that file (`write` / `complete_file`).
3. **Expected:** editor shows the new lines; Approve / Reject visible.
4. **Actual:** Approve / Reject show; editor still has the old text.

---

## Evidence

✔️ Live client `~/.cache/ollmchat/ollmchat.debug.log` ~10:24:

- `write` tool on `/home/alan/gitlive/OLLMchat/docs/Hello World Test`
- `File.read` **id=11** at tool **start** (edit-mode activate)
- Stream completes → `File.write` **id=12** → `event.project.invalidate_cache`
- Then `Folder.fetch_files` (dropdown) + `Folder.fetch_pending_approvals` (Approvals)
- ✔️ **No** `File.read` after the write

ℹ️ `invalidate_cache` in `liboccoder/SourceView.vala` only `file_dropdown.refresh` — does not reload `source_view`.

ℹ️ `on_file_selected` returns early when `current_file.path == file.path`. `open_file` skips load when `file.buffer.is_loaded` — after a tool write the buffer is loaded and stale.

ℹ️ `FileUpdateStatus` (`libocfiles/File.vala` and `ollmfilesd/File.vala`) is only `NO_CHANGE` / `CHANGED_HAS_UNSAVED`. Daemon `File.changed.check` reports a change **only** when `mtime` moved **and** `buffer_dirty`. Window handles that on **focus** only (`ollmapp/Window.vala` → banner). Clean + disk-changed is treated as `NO_CHANGE` and never reloads.

ℹ️ `EditMode/Stream.sync_and_update_metadata` and `WriteFile/Request` set `file.last_modified = now` **before** `File.write`. `check_changed` sends that as `last_known_mtime`. After the write, disk mtime is often **not** greater (same second) → `NO_CHANGE`.

ℹ️ After write, those tools refresh `review_files` only.

ℹ️ `SourceView.refresh_file()` already exists: `buffer.read_async()` if not modified; it does **not** `source_view.set_buffer`. Do not call it from this fix (`GLib.error` if dirty). Inline `File.read` + `set_buffer` in the existing notification lambda.

---

## Hypotheses

✔️ **H1 — No reload path for a clean open buffer after API write.**  
Tool write + `invalidate_cache` never call `File.read` / `SourceView` rebind. Matches the log (no post-write `File.read`). User requirement.

💩 **H2 — Tool wrote a different `GtkSource.Buffer` than the widget still displays.**  
`BufferProvider.create_buffer` assigns a **new** `GtkSourceFileBuffer` onto `file.buffer` if the previous one was not that type. `SourceView` keeps `source_view.set_buffer` on the old instance. A `File.read` on `file.buffer` would not fix the widget unless `SourceView` rebinds. `set_buffer` after read covers this without a separate helper.

---

## Root cause

✔️ H1: project `invalidate_cache` refreshes the file dropdown only. Daemon `changed.check` treats clean + disk-newer as `NO_CHANGE` because it ANDs in client `buffer_dirty`. Tools stamp `last_modified` before write so a mtime check would miss the LLM write anyway. Dirty vs clean is `buffer.is_modified` on the client, not a daemon enum.

---

## Proposed fix

🔷 After the open file is written: if `buffer.is_modified` is false, `File.read` and `source_view.set_buffer`. If true, do not reload (existing dirty banner on focus).

🔷 Dirty vs clean is `buffer.is_modified` on the client. Daemon `changed.check` only answers whether disk mtime is newer.

🔷 Rename `FileUpdateStatus.CHANGED_HAS_UNSAVED` → `CHANGED` on both `libocfiles/File.vala` and `ollmfilesd/File.vala` (same ordinal; wire stays `1`). Client splits banner vs reload.

💩 Stop stamping `last_modified` in the two tool write paths so `check_changed` still sees disk newer than the last open/read. `File.read` `copy_from` then updates `last_modified` from the daemon.

💩 `SourceView` `invalidate_cache` handler: `check_changed` on the open file; if disk changed and not `is_modified`, save cursor, `File.read`, `set_buffer`, restore cursor/scroll. Do **not** reload on every project invalidate without mtime (would reset cursor when another file was written).

💩 Window focus: if disk changed and `is_modified`, banner; if disk changed and clean, `reload_file_from_disk`.

🚫 Do not have the daemon read `buffer_dirty`. 🚫 Do not hide Approvals when the buffer is stale. 🚫 Do not reload over unsaved edits. 🚫 Do not add helper methods. 🚫 Do not change `invalidate_cache` `message` (stays project path). 🚫 Do not call `refresh_file()`.

💩 Immediate dirty banner on `invalidate_cache` (today banner is focus-only) — **not** in the fences below.

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `libocfiles/File.vala` + `ollmfilesd/File.vala` — rename enum value

**Why:** Daemon reports disk mtime newer only; `HAS_UNSAVED` in the name is wrong. Same int value (`1`).

**Where:** `FileUpdateStatus` enum in both files.

**Depends on:** none (apply before call sites that mention the old name).

#### Remove
```vala
	public enum FileUpdateStatus {
		NO_CHANGE,              // File hasn't changed on disk
		CHANGED_HAS_UNSAVED     // File changed on disk, buffer has unsaved changes - needs warning
	}
```

#### Replace with
```vala
	public enum FileUpdateStatus {
		NO_CHANGE, // File hasn't changed on disk
		CHANGED    // File changed on disk; client decides banner vs reload via is_modified
	}
```

Apply the same **Remove** / **Replace with** in **both** `libocfiles/File.vala` and `ollmfilesd/File.vala`.

---

### 2. `ollmfilesd/File.vala` — `call_changed_check`: mtime only

**Why:** Daemon has no editor buffer. Drop `buffer_dirty`. Newer disk mtime → `CHANGED`. Client uses `is_modified`.

**Where:** `rpc_register()`, `this.call_changed_check.connect` lambda.

**Depends on:** ### 1.

#### Remove
```vala
			this.call_changed_check.connect((request) => {
				var p = (FileParams) request.param;
				var file = this.manager.get_file_from_active_project(p.path);
				var status = FileUpdateStatus.NO_CHANGE;
				if (file.mtime_on_disk() > p.last_known_mtime
					&& p.buffer_dirty) {
					status = FileUpdateStatus.CHANGED_HAS_UNSAVED;
				}
				request.reply(new OLLMrpc.Response() {
					msg = ((int) status).to_string()
				});
			});
```

#### Replace with
```vala
			this.call_changed_check.connect((request) => {
				var p = (FileParams) request.param;
				var file = this.manager.get_file_from_active_project(p.path);
				var status = FileUpdateStatus.NO_CHANGE;
				if (file.mtime_on_disk() > p.last_known_mtime) {
					status = FileUpdateStatus.CHANGED;
				}
				request.reply(new OLLMrpc.Response() {
					msg = ((int) status).to_string()
				});
			});
```

---

### 3. `liboctools/EditMode/Stream.vala` — `sync_and_update_metadata`: do not stamp `last_modified` before write

**Why:** If `last_modified` is set to now before `File.write`, `check_changed` sends that as `last_known_mtime` and disk mtime is often not greater. Leave the open/read value; `File.read` after reload copies daemon mtime.

**Where:** `sync_and_update_metadata`, the line immediately after `this.file.last_change_type = change_type`.

**Depends on:** ### 2 (otherwise this stamp is harmless but the reload still never runs).

#### Remove
```vala
			this.file.last_modified = new GLib.DateTime.now_local().to_unix();
```

---

### 4. `liboctools/WriteFile/Request.vala` — write path: do not stamp `last_modified` before write

**Why:** Same as ### 3 for the `write` tool.

**Where:** after `this.file.last_change_type = change_type`, before `if (!(yield this.file.write()))`.

**Depends on:** ### 2.

#### Remove
```vala
			this.file.last_modified = new GLib.DateTime.now_local().to_unix();
```

---

### 5. `liboccoder/SourceView.vala` — `invalidate_cache`: reload clean open file

**Why:** This is the notification that already fires after `File.write`. Dropdown refresh stays. `var file` is the GLib async target for `begin`/`end`, not a one-shot property alias. Reload only when disk changed and `!file.buffer.is_modified`.

**Where:** `SourceView` constructor, `this.manager.rpc.notification.connect` lambda that currently only calls `file_dropdown.refresh.begin()`.

**Depends on:** ### 1, ### 2, ### 3, ### 4.

#### Remove
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

#### Replace with
```vala
			this.manager.rpc.notification.connect((notif) => {
				if (notif.method != "event.project.invalidate_cache"
					|| this.manager.active_project == null
					|| notif.message != this.manager.active_project.path) {
					return;
				}
				this.file_dropdown.refresh.begin();
				if (this.current_file == null) {
					return;
				}
				var file = this.current_file;
				file.check_changed.begin((obj, res) => {
					if (file.check_changed.end(res) == OLLMfiles.FileUpdateStatus.NO_CHANGE
						|| this.current_file != file
						|| file.buffer.is_modified) {
						return;
					}
					this.save_current_file_state();
					file.read.begin((read_obj, read_res) => {
						file.read.end(read_res);
						if (this.current_file != file) {
							return;
						}
						this.source_view.set_buffer(file.buffer as GtkSource.Buffer);
						this.restore_cursor_position(file);
						this.restore_scroll_position(file);
					});
				});
			});
```

---

### 6. `ollmapp/Window.vala` — focus: banner vs reload from `is_modified`

**Why:** External disk edits (no `invalidate_cache`) still go through focus. Daemon only says disk changed. `is_modified` chooses banner vs `reload_file_from_disk`. Window has no `SourceView`; LLM writes are ### 5.

**Where:** constructor, `this.notify["is-active"]` handler, the `check_active_file_changed.begin` callback.

**Depends on:** ### 1, ### 2.

#### Remove
```vala
				this.project_manager.check_active_file_changed.begin((obj, res) => {
					var status = this.project_manager.check_active_file_changed.end(res);
					
					if (status == OLLMfiles.FileUpdateStatus.CHANGED_HAS_UNSAVED) {
						// File changed on disk but buffer has unsaved changes - show warning banner
						var filename = this.project_manager.active_file != null 
							? GLib.Path.get_basename(this.project_manager.active_file.path) 
							: "file";
						this.file_change_banner.show(filename);
					}
				});
```

#### Replace with
```vala
				this.project_manager.check_active_file_changed.begin((obj, res) => {
					if (this.project_manager.check_active_file_changed.end(res)
						== OLLMfiles.FileUpdateStatus.NO_CHANGE) {
						return;
					}
					if (this.project_manager.active_file.buffer.is_modified) {
						this.file_change_banner.show(GLib.Path.get_basename(this.project_manager.active_file.path));
						return;
					}
					this.project_manager.reload_file_from_disk.begin();
				});
```

---

## Attempts / changelog

- ✔️ 2026-08-15 — User: approvals working; close those tickets; editor did not update after LLM write of open clean file.
- ✔️ 2026-08-15 — Log: write + invalidate + pending refresh; no post-write `File.read`.
- ✔️ 2026-08-16 — Fences in this file; Vala not applied.
- ✔️ 2026-08-16 — Daemon must not own dirty/clean; `changed.check` is mtime only; client branches on `buffer.is_modified`.
- ✔️ 2026-08-16 — User: rename `CHANGED_HAS_UNSAVED` → `CHANGED` (enum fences ### 1; call sites use `CHANGED`).
- ✔️ 2026-08-16 — User: no `switch` on status — early return on `NO_CHANGE`.
- ✔️ 2026-08-16 — User: merge stacked `if` early-returns (`||`), not `if` / `if` / `if`.
- ✔️ 2026-08-16 — User: wrap combined `||` across lines. Applied fences (enum rename, mtime-only `changed.check`, drop pre-write `last_modified`, SourceView reload, Window banner vs reload).

## Next

- ✅ User closed 2026-09-02.
