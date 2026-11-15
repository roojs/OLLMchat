# Stacked history rows stuck in review queue, DB updates unpersisted, and deleted-file RPC criticals

**Status:** ✔️ applied — await verification

**Pointer:** `docs/bug-fix-process.md` · `docs/bugs/2026-11-14-approve-deleted-advance.md`

## Problem

- 💩 Accepting all 6 hunks of `examples/oc-test-source-diff.vala` (`file_history` `43024`) left `review queue files=1 visible=true` instead of advancing/clearing the queue.
- 💩 Accepted/reviewed updates on `43024` and parts `13..18` were never flushed to `files.sqlite` on disk.
- 💩 Deleted pending file (`tests/editing/Hello world.txt`) triggered daemon criticals on `File.changed.check`, `FileHistory.parts`, and `FileHistory.decide`.

## Evidence

- ℹ️ `ollmchat.debug.log` (`2026-11-15 08:56:38`):
  - ✔️ `id=52 FileDiffPart.apply` (6th hunk) → `id=54 Folder.fetch_pending_approvals` → `ReviewBar.vala:1685: review queue files=1 visible=true` (`parts=6 hunks=6`).
- ℹ️ `files.sqlite`:
  - ✔️ `examples/oc-test-source-diff.vala` has 7 pending `file_history` rows (`43018`–`43024`, all `reviewed=0` on disk) and `filebase` `110944` (`is_need_approval=1`).
  - ✔️ Parts `13..18` (`file_history_id=43024`) and `43024.reviewed` were still `0` in `files.sqlite` on disk 2+ minutes after `08:56:38` (whereas `last_backup` countdown only fires if `db.backupDB()` or `db.is_dirty = true` is set).
- ℹ️ `ollmfilesd.debug.log`:
  - ✔️ `08:54:43.405` (`id=30,31 FileHistory.parts`), `08:54:53.693` (`id=33 FileHistory.decide`), `08:54:53.706` (`id=34 FileHistory.parts`): `type id '0' is invalid` / `cannot initialize GValue with type '(null)'` (empty `ArrayList` returned via `OLLMrpc.val` → `GLib.Type.INVALID`).
  - ✔️ `08:54:47.609` (`id=32 File.changed.check`): `oll_mfilesd_file_base_mtime_on_disk: assertion 'self != NULL' failed` (`tests/editing/Hello world.txt` is not in `active_project` after deletion).

## Root causes

- ✔️ **Stacked `file_history` rows (`FileDiffPart.commit` vs `FileWithHistory.pending`):**
  - `FileDiffPart.commit` (`ollmfilesd/FileDiffPart.vala:255-263`) marks only `histories.get(0)` (`43024`) `reviewed=1` and returns early when earlier rows (`43018`–`43023`) still have `reviewed=0`, leaving `filebase.is_need_approval = 1`.
  - On the next `Folder.fetch_pending_approvals(since_marker=43144)`, `43024` fails `(reviewed != 0 AND is_need_approval = 0)` and `43023` has `id <= 43144` and `since_id = 0`, so `FileWithHistory.pending` returns neither row; the client keeps stale `43024` forever.
  - Note: `FileHistory.approve` (`ollmfilesd/FileHistory.vala:880-892`) already closes **all** `reviewed = 0` rows for `this.path` when approving the head row; `FileDiffPart.commit` should either poke `since_id` on the remaining pending row(s) so the client advances to `43023`, or close all `reviewed = 0` rows for `path` (matching `FileHistory.approve`).
- ✔️ **Missing `db.backupDB()` after `FileDiffPart.commit` / `FileHistory.approve`:**
  - `SQ.Query.updateById` and `FileBase.saveToDB(..., false)` only write to the `:memory:` SQLite handle without calling `db.backupDB()` or setting `db.is_dirty = true`.
- ✔️ **`File.changed_check` on deleted file (`ollmfilesd/File.vala:313-317`):**
  - `get_file_from_active_project(path)` returns `null` for deleted files removed from `project_files`, then `file.mtime_on_disk()` is called on `null`.
- ✔️ **Empty `Gee.ArrayList` replies in `FileHistory.parts` / `FileHistory.decide` (`ollmfilesd/FileHistory.vala`):**
  - `OLLMrpc.val("o", list)` is designed to return an unset `GLib.Value` (`GLib.Type.INVALID`) when `list.size == 0`, which in Vala executes `GLib.Value(GLib.Type.INVALID)` → `g_value_init(..., 0)` (`type id '0' is invalid` / `cannot initialize GValue with type '(null)'`).
  - For deleted files with 0 diff parts, `FileHistory.parts` and `FileHistory.commit_decided` (`rows.size < 1`) pass an empty list to `OLLMrpc.val` instead of leaving `Response.retval` unset (`new OLLMrpc.Response() { id = request.id }`).
- 🚫 **Do not change `OLLMrpc.val` in `libocrpc/namespace.vala`:**
  - Returning unset `GLib.Type.INVALID` for an empty `Gee.ArrayList` is the `OLLMrpc.val` API (tested by `tests/rpc/values-test.vala`). Rejected by user.

## Proposed fix

### 1. `ollmfilesd/FileDiffPart.vala` — advance remaining history row (or mark reviewed) and trigger `db.backupDB()`

- 💩 When `left.size > 0` after closing `histories.get(0)`, poke `since_id = poke` on the newest remaining pending row (`left` ordered by `timestamp DESC`) so `Folder.fetch_pending_approvals` advances the client's `approve_id` to it, and call `db.backupDB()` whenever `FileDiffPart.commit` updates the DB.

**Where:** `ollmfilesd/FileDiffPart.vala:246-291`.

#### Remove

```vala
			histories.get(0).reviewed = open ? 0 : 1;
			if (open) {
				FileHistory.query(db).updateById(histories.get(0));
				return;
			}
			var max_ids = FileHistory.query(db).fetchAllInt64(
				FileHistory.query(db).selectPrepare("SELECT MAX(id) FROM file_history")
			);
			histories.get(0).since_id = (max_ids.size > 0 ? max_ids.get(0) : (int64) 0) + 1;
			FileHistory.query(db).updateById(histories.get(0));
			var left = new Gee.ArrayList<FileHistory>();
			FileHistory.query(db).select(
				"WHERE path = '" + histories.get(0).path.replace("'", "''") +
					"' AND reviewed = 0",
				left
			);
			if (left.size > 0) {
				return;
			}
```

#### Replace with

```vala
			histories.get(0).reviewed = open ? 0 : 1;
			if (open) {
				FileHistory.query(db).updateById(histories.get(0));
				db.backupDB();
				return;
			}
			var max_ids = FileHistory.query(db).fetchAllInt64(
				FileHistory.query(db).selectPrepare("SELECT MAX(id) FROM file_history"));
			var poke = (int64) 1;
			if (max_ids.size > 0) {
				poke = max_ids.get(0) + 1;
			}
			histories.get(0).since_id = poke;
			FileHistory.query(db).updateById(histories.get(0));
			var left = new Gee.ArrayList<FileHistory>();
			FileHistory.query(db).select(
				"WHERE path = '" + histories.get(0).path.replace("'", "''") +
					"' AND reviewed = 0 ORDER BY timestamp DESC", left);
			if (left.size > 0) {
				left.get(0).since_id = poke;
				FileHistory.query(db).updateById(left.get(0));
				db.backupDB();
				return;
			}
```

#### Remove

```vala
			row.is_need_approval = false;
			row.last_change_type = "";
			row.saveToDB(db, null, false);
		}
```

#### Replace with

```vala
			row.is_need_approval = false;
			row.last_change_type = "";
			row.saveToDB(db, null, true);
		}
```

### 2. `ollmfilesd/FileHistory.vala` — flush DB backup on `approve`

**Where:** `FileHistory.approve` (`ollmfilesd/FileHistory.vala:902-906`).

#### Remove

```vala
			file.is_need_approval = false;
			file.last_change_type = "";
			file.saveToDB(db, null, false);
		}
```

#### Replace with

```vala
			file.is_need_approval = false;
			file.last_change_type = "";
			file.saveToDB(db, null, true);
		}
```

### 3. `ollmfilesd/File.vala` — handle deleted / unindexed file in `changed_check`

**Where:** `File.changed_check` (`ollmfilesd/File.vala:313-320`).

#### Remove

```vala
			var file = this.manager.get_file_from_active_project(path);
			var status = FileUpdateStatus.NO_CHANGE;
			if (file.mtime_on_disk() > last_known_mtime) {
				status = FileUpdateStatus.CHANGED;
			}
```

#### Replace with

```vala
			var file = this.manager.get_file_from_active_project(path);
			var status = FileUpdateStatus.NO_CHANGE;
			if (file == null) {
				if (GLib.FileUtils.test(path, GLib.FileTest.EXISTS)) {
					status = FileUpdateStatus.CHANGED;
				}
			} else if (file.mtime_on_disk() > last_known_mtime) {
				status = FileUpdateStatus.CHANGED;
			}
```

### 4. `ollmfilesd/FileHistory.vala` — omit `retval` when `parts` / `commit_decided` reply with 0 rows

- 💩 Leave `Response.retval` unset (`new OLLMrpc.Response() { id = request.id }`) instead of calling `OLLMrpc.val("o", ...)` when `rows` / `this.live.get(id)` is empty.
- 🚫 Rejected: changing `OLLMrpc.val` in `libocrpc/namespace.vala` to return the empty `Gee.ArrayList` (violates the `OLLMrpc.val` API).

**Where:** `FileHistory.parts` (`ollmfilesd/FileHistory.vala:506-526`) and `FileHistory.commit_decided` (`ollmfilesd/FileHistory.vala:575-623`).

#### Remove

```vala
				if (this.live.has_key((int) id) && this.live_stamp.has_key((int) id) &&
					this.live_stamp.get((int) id) == (int) stamp) {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						retval = OLLMrpc.val("o", this.live.get((int) id))
					});
					return;
				}
```

#### Replace with

```vala
				if (this.live.has_key((int) id) && this.live_stamp.has_key((int) id) &&
					this.live_stamp.get((int) id) == (int) stamp) {
					if (this.live.get((int) id).size > 0) {
						request.reply(new OLLMrpc.Response() {
							id = request.id,
							retval = OLLMrpc.val("o", this.live.get((int) id))
						});
						return;
					}
					request.reply(new OLLMrpc.Response() {
						id = request.id
					});
					return;
				}
```

#### Remove

```vala
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				retval = OLLMrpc.val("o", rows)
			});
```

#### Replace with

```vala
			if (rows.size > 0) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					retval = OLLMrpc.val("o", rows)
				});
				return;
			}
			request.reply(new OLLMrpc.Response() {
				id = request.id
			});
```

#### Remove

```vala
				if (action == 0) {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						retval = OLLMrpc.val("o", this.live.get(id))
					});
					return;
				}
```

#### Replace with

```vala
				if (action == 0) {
					request.reply(new OLLMrpc.Response() {
						id = request.id
					});
					return;
				}
```

#### Remove

```vala
				if (action == 1) {
					histories.get(0).approve(this.rpc_manager.db, file);
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						retval = OLLMrpc.val("o", this.live.get(id))
					});
					return;
				}
```

#### Replace with

```vala
				if (action == 1) {
					histories.get(0).approve(this.rpc_manager.db, file);
					request.reply(new OLLMrpc.Response() {
						id = request.id
					});
					return;
				}
```

## Attempts / changelog

- ✔️ 2026-11-15 — inspected `ollmchat.debug.log`, `ollmfilesd.debug.log`, `files.sqlite`, `FileDiffPart.vala`, `FileHistory.vala`, `File.vala`, `libocrpc/namespace.vala`; root causes confirmed and fixes proposed.
- 🚫 2026-11-15 — user rejected the `libocrpc/namespace.vala` (`OLLMrpc.val`) change (returning `GLib.Type.INVALID` for empty lists is the `OLLMrpc.val` API); updated item 4 to omit `retval` in `ollmfilesd/FileHistory.vala` when the list is empty.
- ✔️ 2026-11-15 — applied items 1–4 in `ollmfilesd/FileDiffPart.vala`, `ollmfilesd/FileHistory.vala`, and `ollmfilesd/File.vala` (`db.backupDB()` also added on the `found.size == 0` early return in `FileDiffPart.commit`; `File.changed_check` written without `else if`). Built with `ninja -C build` and verified `meson test -C build test-rpc-filesd-pair-flow` passes.

## Next

- 🔷 ⏳ Verify live review flow (accepting stacked `file_history` rows advances/clears the queue and flushes `files.sqlite`; deleted-file `File.changed.check`, `FileHistory.parts`, and `FileHistory.decide` produce no GLib criticals).
