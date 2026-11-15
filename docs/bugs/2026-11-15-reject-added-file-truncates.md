# Rejecting an added file truncates it to 0 bytes instead of deleting it

**Status:** ✔️ applied — await verification

**Pointer:** `docs/bug-fix-process.md`

## Problem

- 🔷 Rejecting a pending `added` file (`tests/um editing uh/hello world.txt`) should delete the file from disk and remove it from the project/review queue.
- 🔷 Actual: `tests/um editing uh/hello world.txt` stayed on disk truncated to 0 bytes (`git diff` shows all 5 lines removed, 0-byte file remaining).

## Evidence

- ℹ️ Logs (`2026-11-15 08:54:43`, `~/.cache/ollmchat/ollmchat.debug.log` + `ollmfilesd.debug.log`):
  - ✔️ `id=24 method=FileDiffPart.apply` ran for `file_history` `43134` (`tests/um editing uh/hello world.txt`).
  - ✔️ `ReviewBar` advanced to `files=2` (`tests/editing/Hello world.txt`).
- ℹ️ SQLite (`~/.local/share/ollmchat/files.sqlite`):
  - ✔️ `file_history` `43134`: `change_type="added"`, `reviewed=1`, `since_id=43144`, `backup_path=""`.
  - ✔️ `file_diff_part` `12`: `file_history_id=43134`, `accepted=-1`.
  - ✔️ `filebase` `113033`: `is_need_approval=0`, `last_change_type=""`, `delete_id=0`.
- ✔️ Disk: `tests/um editing uh/hello world.txt` exists with size 0 bytes.

## Root cause

- ✔️ `FileHistory.rebuild_parts` diffs `""` against the added file, producing one `FileDiffPart` with `hunk_remove = ""` and `hunk_add` = file contents.
- ✔️ `FileDiffPart.commit` (`ollmfilesd/FileDiffPart.vala:200-235`) handles `action == -1` by writing `hunk_remove` (`""`) through `file.buffer.apply_edits`, which calls `DummyFileBuffer.write_real` and writes a 0-byte file instead of deleting the added file.
- ✔️ `FileHistory.revert` (`ollmfilesd/FileHistory.vala:938-943`) rejects `this.change_type == "added"` with `"Cannot revert added files"`, so whole-file reject via `FileHistory.decide` / `FileHistory.rpc_revert` (e.g. a 0-byte added file) also fails instead of deleting.

## Proposed fix

- 🔷 Rejecting an `added` file (`FileDiffPart.commit` when `action == -1` and `histories.get(0).change_type == "added"`, and `FileHistory.revert` when `this.change_type == "added"`) backs up the rejected content with a `revert` history row (`reviewed = 1`), unlinks the file from disk, sets `delete_id` and clears approval on `filebase`, and runs `delete_manager.cleanup()`.
- 💩 Keep a `revert` backup in `~/.cache/ollmchat/edited/` before unlinking (same pattern as `FileHistory.revert` for modified/deleted files) so rejected new files are still recoverable from history.
- 🚫 Do not leave `change_type = "deleted"` with `reviewed = 0` via `DeleteManager.remove`, which would re-queue the rejected file as a pending deletion.

### 1. `ollmfilesd/FileDiffPart.vala` — delete on reject when history is `added`

**Where:** `FileDiffPart.commit` (`ollmfilesd/FileDiffPart.vala:198-238` and `288-302`).

#### Remove

```vala
			var list = history.live.get((int) this.file_history_id);
			if ((action == -1 && this.accepted != -1) || (action != -1 && this.accepted == -1)) {
				var insert = this.hunk_add;
				if (action == -1) {
					insert = this.hunk_remove;
				}
				var file = history.rpc_manager.get_file_from_active_project(histories.get(0).path);
				if (file == null) {
					throw new GLib.IOError.FAILED("file not found");
				}
				if (file.buffer == null) {
					file.manager.buffer_provider.create_buffer(file);
				}
				var span = this.new_line_end < this.new_line_start
					? 0 : this.new_line_end - this.new_line_start + 1;
				if (this.accepted == -1) {
					span = this.old_line_end < this.old_line_start
						? 0 : this.old_line_end - this.old_line_start + 1;
				}
				var inserted = 0;
				if (insert != "") {
					inserted = insert.split("\n").length;
				}
				var changes = new Gee.ArrayList<FileChange>();
				changes.add(new FileChange(file) {
					start = this.new_line_start,
					end = this.new_line_start + span,
					replacement = insert
				});
				yield file.buffer.apply_edits(changes);
				var delta = inserted - span;
				this.new_line_end = inserted == 0
					? this.new_line_start - 1
					: this.new_line_start + inserted - 1;
				foreach (var other in list) {
					if (other.id == this.id || other.new_line_start < this.new_line_start + span) {
						continue;
					}
					other.new_line_start += delta;
					other.new_line_end += delta;
				}
				history.live_stamp.set((int) this.file_history_id, (int) file.mtime_on_disk());
			}
```

#### Replace with

```vala
			var list = history.live.get((int) this.file_history_id);
			var added_delete_id = (int64) 0;
			if ((action == -1 && this.accepted != -1) || (action != -1 && this.accepted == -1)) {
				var file = history.rpc_manager.get_file_from_active_project(histories.get(0).path);
				if (file == null) {
					throw new GLib.IOError.FAILED("file not found");
				}
				if (action == -1 && histories.get(0).change_type == "added") {
					var revert_history = new FileHistory(
						db, file, "revert", new GLib.DateTime.now_local());
					revert_history.reviewed = 1;
					yield revert_history.commit();
					added_delete_id = revert_history.id;
					if (GLib.FileUtils.test(file.path, GLib.FileTest.EXISTS)) {
						yield GLib.File.new_for_path(file.path).delete_async();
					}
					this.new_line_end = this.new_line_start - 1;
				}
				if (added_delete_id == 0) {
					var insert = this.hunk_add;
					if (action == -1) {
						insert = this.hunk_remove;
					}
					if (file.buffer == null) {
						file.manager.buffer_provider.create_buffer(file);
					}
					var span = this.new_line_end < this.new_line_start
						? 0 : this.new_line_end - this.new_line_start + 1;
					if (this.accepted == -1) {
						span = this.old_line_end < this.old_line_start
							? 0 : this.old_line_end - this.old_line_start + 1;
					}
					var inserted = 0;
					if (insert != "") {
						inserted = insert.split("\n").length;
					}
					var changes = new Gee.ArrayList<FileChange>();
					changes.add(new FileChange(file) {
						start = this.new_line_start,
						end = this.new_line_start + span,
						replacement = insert
					});
					yield file.buffer.apply_edits(changes);
					var delta = inserted - span;
					this.new_line_end = inserted == 0
						? this.new_line_start - 1
						: this.new_line_start + inserted - 1;
					foreach (var other in list) {
						if (other.id == this.id || other.new_line_start < this.new_line_start + span) {
							continue;
						}
						other.new_line_start += delta;
						other.new_line_end += delta;
					}
					history.live_stamp.set((int) this.file_history_id, (int) file.mtime_on_disk());
				}
			}
```

#### Remove

```vala
			foreach (var target in targets) {
				target.is_need_approval = false;
				target.last_change_type = "";
				target.saveToDB(db, null, false);
			}
			row.is_need_approval = false;
			row.last_change_type = "";
			row.saveToDB(db, null, true);
		}
```

#### Replace with

```vala
			foreach (var target in targets) {
				target.is_need_approval = false;
				target.last_change_type = "";
				if (added_delete_id > 0) {
					target.delete_id = added_delete_id;
				}
				target.saveToDB(db, null, false);
			}
			row.is_need_approval = false;
			row.last_change_type = "";
			if (added_delete_id > 0) {
				row.delete_id = added_delete_id;
			}
			row.saveToDB(db, null, true);
			if (added_delete_id > 0) {
				yield history.rpc_manager.delete_manager.cleanup();
			}
		}
```

### 2. `ollmfilesd/FileHistory.vala` — delete on `revert` when `change_type == "added"`

**Where:** `FileHistory.revert` (`ollmfilesd/FileHistory.vala:948-954`).

#### Remove

```vala
			if (this.change_type == "added") {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error.INTERNAL_ERROR("Cannot revert added files")
				});
				return;
			}
```

#### Replace with

```vala
			if (this.change_type == "added") {
				var now = new GLib.DateTime.now_local();
				var revert_history = new FileHistory(manager.db, file, "revert", now);
				revert_history.reviewed = 1;
				try {
					yield revert_history.commit();
					if (GLib.FileUtils.test(this.path, GLib.FileTest.EXISTS)) {
						yield GLib.File.new_for_path(this.path).delete_async();
					}
				} catch (GLib.Error e) {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						error = new OLLMrpc.Error.INTERNAL_ERROR(e.message)
					});
					return;
				}
				this.reviewed = 1;
				var max_ids = FileHistory.query(manager.db).fetchAllInt64(
					FileHistory.query(manager.db).selectPrepare("SELECT MAX(id) FROM file_history"));
				this.since_id = (int64) 1;
				if (max_ids.size > 0) {
					this.since_id = max_ids.get(0) + 1;
				}
				FileHistory.query(manager.db).updateById(this);
				file.delete_id = revert_history.id;
				file.last_change_type = "";
				file.is_need_approval = false;
				file.saveToDB(manager.db, null, true);
				yield manager.delete_manager.cleanup();
				var row = new File(manager);
				row.copy_from(file, { "manager", "buffer", "parent" });
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					retval = OLLMrpc.val("o", row),
					msg = "ok"
				});
				return;
			}
```

## Attempts / changelog

- ✔️ 2026-11-15 — inspected `ollmchat.debug.log`, `files.sqlite`, `FileDiffPart.vala`, `FileHistory.vala`; root cause confirmed and fix proposed.
- ✔️ 2026-11-15 — applied items 1–2 in `ollmfilesd/FileDiffPart.vala` and `ollmfilesd/FileHistory.vala`. Built with `ninja -C build` and verified `meson test -C build test-rpc-filesd-pair-flow` passes.

## Next

- 🔷 ⏳ Verify rejecting an `added` file unlinks it on disk and removes it from the project/review queue.
