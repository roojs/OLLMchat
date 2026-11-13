# Ignored `.git/index` is in file history and in the review list

**Status:** ✅ 2026-11-13. User closed it. Ignored paths (including `.git`) are marked by `check_path_ignored` and filtered out of pending reviews.

## Problem

- 🔷 The review footer lists `.git/index` as `deleted — index`.
- 🔷 An ignored file is not a history row, and it is not a review row.
- 🔷 🚫 A `/.git/` path test. That hardcodes a path the ignore check already covers.

## Evidence

- ✔️ After the client merge, the pending files are `tests/editing/Hello world` (`deleted`), `tests/editing/Hello world.txt` (`added`), and `.git/index` (`deleted`).
- ✔️ `filebase` id `112505`, path `/home/alan/gitlive/OLLMchat/.git/index`, `is_ignored=0`, `is_need_approval=1`, `delete_id=43029`, parent `112504`. History `43026` is `added`. History `43029` is `deleted`, `reviewed=0`.
- ✔️ Two folder rows share that directory path. `112504` has `delete_id=43028`. `113030` is live and `is_ignored=0`.
- ✔️ `git_ignore_path_is_ignored` returns ignored for `.git` and for `.git/index`. The header says the default internal rules ignore `.git`. `git check-ignore` exits 1. The daemon uses libgit2, not that command.
- ✔️ `enumerate_directory_contents` `continue`s when `name == ".git"` before `check_path_ignored`.
- ✔️ `make_children` and `File.to_real` save the new row without `check_path_ignored`. `commit` then sees `is_ignored=0`.
- ✔️ `FileWithHistory.pending` keeps a row on `is_need_approval = 1`. It does not read `is_ignored`.
- ℹ️ `commit` already returns before insert when `is_ignored` is set, except `change_type == "deleted"` so `delete_id` has a history id. This proposal does not change that exception and does not delete stored history rows.

## Root cause

- ✔️ `.git/index` is stored as a normal file. The ignore check would have marked it, and the scan and the write path never call that check. The review query then trusts `is_need_approval`.

## Not this fix

- 🔷 🚫 A `/.git/` test in `FileHistory.commit` or `FileWithHistory.pending`. Reverted. The path is already ignored by `git_ignore_path_is_ignored`.
- 🔷 🚫 A second loop after `read_dir_update` that runs an `UPDATE` for every ignored directory. `read_dir_update` already saves `is_ignored` on the item the scan visits. A descendant repair pass is not justified.
- 🚫 `File.fetch` loading a `filebase` row that is not in the project map. Reverted. The review list should not contain the row.

## Proposed fix

- 🔷 Edits are **Remove** / **Replace with** / **Add**. Verify the surrounding lines before applying.
- 🔷 `check_path_ignored` is the existing check. Libgit2 already returns ignored for this path.
- 🔷 `read_dir` already skips a child with `is_ignored`, so a marked `.git` directory is not walked.
- ℹ️ Ignored deletions still insert one history row for `delete_id`. `pending` does not return that row once `is_ignored` is set.

### 1. `ollmfilesd/Folder.vala` — `check_path_ignored`: same namespace can call it

**Why:** `File.to_real` and `File.write` have to use this check. A second copy would be a new method.

**Where:** `check_path_ignored` signature.

**Depends on:** none.

#### Remove

```vala
		private bool check_path_ignored(string path)
```

#### Replace with

```vala
		internal bool check_path_ignored(string path)
```

### 2. `ollmfilesd/Folder.vala` — `enumerate_directory_contents`: ask the ignore check

**Why:** The name skip runs before `check_path_ignored`, so the directory is never stored as ignored.

**Where:** the child loop, after the `"."` / `".."` skip, before `cpath` is built.

**Depends on:** none.

#### Remove

```vala
				// Skip .git directories and other hidden/system folders
				if (name == ".git") {
					continue;
				}
```

### 3. `ollmfilesd/Folder.vala` — `make_children`: new folder uses the ignore check

**Why:** A write that creates `.git` never sets `is_ignored`, so the file saved under it is a normal file.

**Where:** the `new Folder.new_from_info` that creates the missing child, before `saveToDB`.

**Depends on:** §1.

#### Remove

```vala
			child_folder = new Folder.new_from_info(
				this.manager,
				this,
				folder_info,
				child_path
			);
```

#### Replace with

```vala
			child_folder = new Folder.new_from_info(
				this.manager,
				this,
				folder_info,
				child_path
			) {
				is_ignored = this.check_path_ignored(child_path)
			};
```

### 4. `ollmfilesd/Folder.vala` — `to_real`: folder history sees the flag

**Why:** `commit` skips an ignored add only when `is_ignored` is already set.

**Where:** `to_real`, after `this.id = 0`, before the `FileHistory` for `"added"`.

**Depends on:** §1.

#### Add — after `this.id = 0`

The active project already has the repository. The new folder may not.

```vala
			this.is_ignored = this.manager.active_project.check_path_ignored(
				this.path
			);
```

### 5. `ollmfilesd/File.vala` — `to_real`: file history sees the flag

**Why:** The add is recorded before anyone sets `is_ignored`.

**Where:** `to_real`, immediately before `if (this.manager.db != null)`.

**Depends on:** §1. `found_base_folder` is the scanned folder that holds the repository. The parent created for `.git` does not.

#### Add — before the database block

```vala
			this.is_ignored = found_base_folder.check_path_ignored(this.path);
```

#### Remove

```vala
			if (this.manager.db != null) {
				this.saveToDB(this.manager.db, null, false);
				this.is_need_approval = true;
				this.last_change_type = "added";
				var file_history = new FileHistory(
					this.manager.db,
					this,
					"added",
					new GLib.DateTime.now_local()
				);
				yield file_history.commit();
				this.saveToDB(this.manager.db, null, false);
			}
```

#### Replace with

The save stays its own `if`. History is a sibling `if`: `manager.db` and not ignored.

```vala
			if (this.manager.db != null) {
				this.saveToDB(this.manager.db, null, false);
			}
			if (this.manager.db != null && !this.is_ignored) {
				this.is_need_approval = true;
				this.last_change_type = "added";
				var file_history = new FileHistory(
					this.manager.db,
					this,
					"added",
					new GLib.DateTime.now_local()
				);
				yield file_history.commit();
				this.saveToDB(this.manager.db, null, false);
			}
```

### 6. `ollmfilesd/File.vala` — `write`: a modify uses the ignore check

**Why:** An existing row with `is_ignored=0` still takes the modified history path.

**Where:** `write`, the `default` arm, immediately before `if (change_type == "modified"`.

**Depends on:** §1.

#### Add — before the modified-history `if`

```vala
						if (this.manager.active_project != null) {
							file.is_ignored =
								this.manager.active_project.check_path_ignored(
									file.path
								);
						}
```

#### Remove

```vala
						if (change_type == "modified" && this.manager.db != null) {
```

#### Replace with

```vala
						if (change_type == "modified" &&
							this.manager.db != null &&
							!file.is_ignored) {
```

### 7. `ollmfilesd/FileWithHistory.vala` — `pending`: review list reads the flag

**Why:** A stored ignored row is still returned while `is_need_approval` is set.

**Where:** the `pending` query, after the `base_type` condition, before the `reviewed` condition.

**Depends on:** the row's own `is_ignored` already being set. This query does not walk directories and does not write. `.git/index` is still `is_ignored=0`, and the scan does not open that directory, so this filter does not drop that row.

#### Remove

```vala
		COALESCE(filebase.base_type, file_history.base_type) = 'f'
	AND
	(
		file_history.reviewed != 0
```

#### Replace with

```vala
		COALESCE(filebase.base_type, file_history.base_type) = 'f'
	AND
		COALESCE(filebase.is_ignored, 0) = 0
	AND
	(
		file_history.reviewed != 0
```

## Attempts / changelog

- ✔️ 2026-11-13: client log and `files.sqlite`. The third row is `.git/index` with `is_ignored=0`.
- 💩 2026-11-13: `commit` and `pending` skipped `/.git/` and every ignored deletion. Reverted.
- ✔️ 2026-11-13: libgit2 returns ignored for `.git` and `.git/index`.
- 💩 2026-11-13: proposed a second `read_dir` loop that `UPDATE`s every ignored directory's descendants. Removed. No justification.
- ✔️ 2026-11-13: applied the fences. `ollmfilesd/ollmfilesd` compiled. Pre-existing warnings only.

## Next

- ✅ 2026-11-13. User closed it. Restart `ollmfilesd` to load this binary for any pre-existing `.git/index` row.
