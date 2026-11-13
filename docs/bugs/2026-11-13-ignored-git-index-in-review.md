# Ignored `.git/index` is in file history and in the review list

**Status:** ⏳ open. No product change. An attempted filter was reverted.

## Problem

- 🔷 The review footer lists three pending files. The last row is `deleted — index`.
- 🔷 That path is `/home/alan/gitlive/OLLMchat/.git/index`. It is inside `.git`. The scan does not index that directory.
- 🔷 An ignored file is not a history row, and it is not a review row.

## Evidence

- ✔️ After the client merge (`reviewed != 0` removes the path), the three pending files are `tests/editing/Hello world` (`deleted`), `tests/editing/Hello world.txt` (`added`), and `.git/index` (`deleted`). Basename order puts `index` last.
- ✔️ `filebase` id `112505`, path `/home/alan/gitlive/OLLMchat/.git/index`, `is_ignored=0`, `is_need_approval=1`, `delete_id=43029`. History `43026` is `added`. History `43029` is `deleted`, `reviewed=0`, backup `/home/alan/.cache/ollmchat/edited/2026-10-28-43029-index`.
- ✔️ `Folder` scan skips a child named `.git`, so that path is never given `is_ignored`. `File.fetch` only reads `project_files.child_map`, so a click on the row returns no file. Client log 09:04:39: `File.fetch` id `25` replies, and no `File.read` follows.
- ✔️ `FileWithHistory.pending` keeps a row when `is_need_approval = 1`. It does not look at `is_ignored`.
- ✔️ `FileHistory.commit` skips an ignored file unless the change is `deleted`. This row was stored with `is_ignored=0`, so both the add and the delete were written.

## Root cause

- ✔️ The review list trusts `file_history` plus `is_need_approval`. `.git/index` is stored as a normal file (`is_ignored=0`) even though the scan refuses the directory. The pending query then shows it.

## Not this fix

- 🚫 A `/.git/` test in `FileHistory.commit` and in `FileWithHistory.pending`. That was applied and reverted. It bypasses `is_ignored`, and the `commit` change also dropped the ignored-deletion row that `filebase.delete_id` points at.
- 🚫 `File.fetch` loading a `filebase` row when the path is not in the project map. Reverted. That would open a file the review list should not contain.

## Proposed fix

- 🔷 Not applied. The row has to be ignored, so it is not written to `file_history` and `Folder.fetch_pending_approvals` does not return it.
- 🔷 The ignore flag is the existing check. A path-substring special case is not the fix.

## Attempts / changelog

- ✔️ 2026-11-13: client log and `files.sqlite` read. The third row is `.git/index`.
- 💩 2026-11-13: `commit` and the pending query were changed to skip `/.git/` and every ignored deletion. Reverted. `File.vala` and `FileWithHistory.vala` match the tree from before that edit. `FileHistory.vala` still has the deleted-file diff change from `2026-11-12-review-deleted-and-file-list.md`.

## Next

- 🔷 ⏳ Decide how an existing `.git/index` row becomes ignored, and how the pending list drops it, before editing product code.
