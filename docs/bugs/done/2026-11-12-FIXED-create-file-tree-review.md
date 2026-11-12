# Create folder and file does not refresh the tree or the editor footer

**Status:** ✅ 2026-11-12. User closed it. A later create notifies, the tree reloads, and the new file opens in the editor.

## Problem

- 🔷 Local agent-pi session `2026-11-12-08-28-37`, project `/home/alan/gitlive/OLLMchat`.
- 🔷 The user asked for a folder `tests/editing` and a file `Hello world` with five lines of text, then a rename to `Hello world.txt`.
- 🔷 That create has to notify, the folder tree has to reload and show the new folder and file, and the new file has to show on the text-editor footer (`ReviewBar`) as needing review.
- 🔷 Actual: the file was registered. The tree stayed on the startup listing. The footer did not list the new file.

## Evidence

- ✔️ `~/.cache/ollmchat/ollmchat.debug.log` and `~/.cache/ollmchat/ollmfilesd.debug.log`, 08:28–08:31.
- ✔️ The agent used `bash`, three times. It did not call `write`.
- ✔️ 08:29:01 `bash` listed the project (`preview: total 212`). No create.
- ✔️ 08:29:55 the daemon ran, inside overlay `overlay-20261112-082955`:
  - ✔️ `mkdir -p tests/editing && cat > tests/editing/Hello\ world`
  - ✔️ Seccomp `blocked write path=tests/editing/Hello world` pid `1798925`
  - ✔️ Two `disk backup requested` lines (folder row, then file row)
- ✔️ 08:29:55.571 the client received `event.project.invalidate_cache` `object_type=Project`.
- ✔️ 08:31:13 a second overlay, `overlay-20261112-083113`, ran `git mv` / `mv` of `tests/editing/Hello world` to `tests/editing/Hello world.txt`.
- ✔️ 08:31:14.024 the client received `event.project.invalidate_cache` again. Tool result `preview: total 12`.
- ✔️ After each of those notifications the client called `File.changed.check` only. The next `File.read` is `tests/markdown/bold-list-items.md` at 08:31:43 (the editor file already open).
- ✔️ `Folder.fetch_children` and `Folder.fetch_pending_approvals` run at 08:27:00, while the project is opening. Neither runs again after either `invalidate_cache`.
- ℹ️ `File.to_real` emits `event.project.invalidate_cache` with `message` set to the active project path. `Folder.to_real` saves the new folder and emits nothing. The one notification is the new file.
- ℹ️ `File/Nav.vala` reloads `folder_tree` only for `event.filesystem.scan_end`. This create does not emit that.
- ℹ️ `SourceView` handles `event.project.invalidate_cache` by `check_changed` on `current_file` only. The open file was `tests/markdown/bold-list-items.md`, so that check is a no-op for `tests/editing/Hello world`.
- ℹ️ `SourceView` shows the footer from `review_files.refreshed` → `ReviewBar.sync_pending`. Nothing in this session called `review_files.refresh` after the create. `Approvals` would have, and `Approvals` is never constructed.

## Root cause

- ✔️ The sandbox spill registered `tests/editing/Hello world` and notified `event.project.invalidate_cache`. The live UI does not reload the folder tree on that notification, and it does not refresh `ReviewFiles`, so the footer stays hidden.

## Proposed fix

- 🔷 Edits are **Remove** / **Replace with** / **Add**. Verify the surrounding lines before applying.
- 🔷 `File/Nav.vala` reloads the folder tree on `event.project.invalidate_cache` the same way it already reloads on `event.filesystem.scan_end`. The method test is a `switch` on `notif.method`. The cache event carries the project path in `message`. The scan event carries it in `args[0]`.
- 🔷 `SourceView` calls `review_files.refresh()` when that same cache event matches the active project, including when no file is open. `refreshed` already calls `sync_pending`.

### 1. `liboccoder/File/Nav.vala` — notification handler

**Why:** the tree reload already exists. It is bound to the project scan event, which a sandbox create does not emit.

**Where:** the `rpc.notification` handler in the `Nav` constructor, the method test and the path test above `folders.loaded.remove`.

**Depends on:** none.

#### Remove

```vala
			this.manager.rpc.notification.connect((notif) => {
				if (notif.method != "event.filesystem.scan_end") {
					return;
				}
				if (!this.project.is_project) {
					return;
				}
				if (notif.args.get(0).get_string() != this.project.path) {
					return;
				}
```

#### Replace with

```vala
			this.manager.rpc.notification.connect((notif) => {
				if (!this.project.is_project) {
					return;
				}
				var path = "";
				switch (notif.method) {
					case "event.filesystem.scan_end":
						path = notif.args.get(0).get_string();
						break;

					case "event.project.invalidate_cache":
						path = notif.message;
						break;

					default:
						return;
				}
				if (path != this.project.path) {
					return;
				}
```

### 2. `liboccoder/SourceView.vala` — `SourceView` constructor

**Why:** `refreshed` already fills `ReviewBar`. The cache notification never starts that refresh. `Approvals` is not in the window.

**Where:** the `notification` handler, after the project-path test and before the `current_file == null` return.

**Depends on:** none.

#### Add — inside the `invalidate_cache` handler, on the line after the project-path test and before `if (this.current_file == null)`. Starts the pending-file refresh for this project.

```vala
					this.manager.review_files.refresh.begin();
```

## Attempts / changelog

- ℹ️ 2026-11-12: log opened from the failed local create.
- ✔️ 2026-11-12: read both debug logs. Shell hypothesis dropped. The notification did arrive.
- ✔️ 2026-11-12: applied the `Nav` switch and the `SourceView` `review_files.refresh()` call. `liboccoder` built.
- ✅ 2026-11-12: user confirmed the notification arrives and the editor opens the new file. Review of those changes is a separate log: `docs/bugs/2026-11-12-review-deleted-and-file-list.md`.

## Next

- ✔️ Closed.
