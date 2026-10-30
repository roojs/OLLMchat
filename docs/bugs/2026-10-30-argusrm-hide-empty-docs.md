# Hide empty drops docs on argusrm

**Status:** ⏳ root cause is the folder counts staying at 0 after the scan — fix not applied

## Problem

- 🔷 Phone, project `argusrm`. Hide empty is on. The root lists `README.txt` and does not list `docs`.
- 🔷 `docs` has files. It should stay in the list.

## Evidence

- ✔️ On disk, `/home/alan/gitlive/argusrm` has `README.txt` and `docs/`. `docs` has five symlinks to markdown files and `docs/plans/` with seven markdown files.
- ✔️ `files.sqlite` row 36687 is the project. Row 36688 is `README.txt` (`f`). Row 36689 is `docs` (`d`, not ignored, `points_to_id` 0). Under 36689 the same count query the daemon uses returns `folder_count` 1 and `file_count` 5.
- ✔️ 16:03:50 the daemon created the project. `create_project` saves the project row and does not scan.
- ✔️ 16:07:13 the phone activated `/home/alan/gitlive/argusrm`. The log is `opening project`, then `filesystem scan queued`, then `Folder.fetch_children` at 16:07:13.362, then `filesystem scan complete` at 16:07:13.388, then another `Folder.fetch_children` at 16:07:13.403. Connection `0x5707538c93f0`.
- ℹ️ The hide-empty filter drops a folder when `file_count` and `folder_count` are both 0. `liboccoder/Folder/Tree.vala`. Files are a separate list, so `README.txt` still shows.
- ℹ️ Those two counts are written only inside `Folder.load_files_from_db`. A folder created by the scan (`Folder.new_from_info`) leaves them at 0. `activate_project` calls `load_files_from_db` only while `children` is empty, and that call is before `read_dir`.

## Root cause

- ✔️ The first load runs before the scan has saved `docs`. The scan then adds `docs` with both counts still 0. Hide empty treats that as an empty folder. The database row would count as one child folder and five files. The object the phone filters never gets those numbers.

## Proposed fix

- 🔷 After this folder's children are updated in `read_dir`, set `folder_count`, `file_count`, `document_count`, and `code_count` from those children. Same rules as the load query: ignored and deleted rows do not count. A directory counts as a folder. `f` and `fa` count as files. Text with an empty language, or markdown / txt / text / plaintext, counts as a document. Other text counts as code.
- 🔷 `docs` then has `file_count` 5 and `folder_count` 1 before `fetch_children` copies the row. Hide empty keeps it. `README.txt` is still a file row.
- 🚫 Do not call `load_files_from_db` again after the scan. `needs_reload` can return before the count write, and that load rebuilds the tree.
- 🚫 Do not add a method for the count. It stays in `read_dir`, after the child list is final and before either return.

### `ollmfilesd/Folder.vala` — `read_dir`

**Why:** The scan inserts `docs` with both counts still 0. The hide-empty filter reads those fields. The load query is the only writer today, and it has already finished.

**Where:** After `read_dir_remove`, before `this.manager.scanning.set`.

#### Add

```vala
			this.folder_count = 0;
			this.file_count = 0;
			this.document_count = 0;
			this.code_count = 0;
			foreach (var child in this.children.items) {
				if (child.delete_id != 0 || child.is_ignored) {
					continue;
				}
				if (child.base_type == "d") {
					this.folder_count++;
					continue;
				}
				if (child.base_type != "f" && child.base_type != "fa") {
					continue;
				}
				this.file_count++;
				if (!child.is_text) {
					continue;
				}
				var kind = child.language.down();
				if (kind == "" || kind == "markdown" || kind == "txt" ||
					kind == "text" || kind == "plaintext") {
					this.document_count++;
					continue;
				}
				this.code_count++;
			}
```

## Attempts / changelog

- ℹ️ 2026-10-30 16:20 — disk listing, `files.sqlite` counts, daemon log around the 16:07 activate. No product change.
- ℹ️ 2026-10-30 16:28 — proposed the `read_dir` count. Not applied.

## Next

- 💩 ⏳ Apply the fence, then on the phone open `argusrm` with hide empty on. `docs` stays next to `README.txt`.
