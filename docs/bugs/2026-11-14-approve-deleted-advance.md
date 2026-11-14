# After Accept on deleted file, advance or close editor

**Status:** ⏳ open

## Problem

- 🔷 Open a pending **deleted** file in the review bar. Press **Accept** when review is complete.
- 🔷 Expected: close that file; if another file is still pending review, open it; if none remain, close the editor (no file open).
- 🔷 Actual: the deleted banner and empty buffer stay on screen; the user is stuck until they pick another file manually.

## Root cause

- ✔️ Deleted pending paths often get **`FileHistory.parts` = 0 hunks** (no on-disk file for diff). `update_diff` still shows **Accept**, but the button only called `send_part`, which returns immediately when `parts.size < 1` — no RPC, no approval.
- ✔️ Whole-file approval for zero-hunk histories must use `FileHistory.decide` / `approve`, not `FileDiffPart.apply`. `commit_decided` used to run zero commits and never marked the row reviewed.
- ✔️ Daemon `rpc_approve` / `revert` failed for paths missing from `child_map` (deleted file rows), same class of bug as `File.fetch`.
- ✔️ After a successful approve, `review_files.refresh()` and the `refreshed` handler must advance or `close_file` (earlier client work).

## Proposed fix

- 🔷 `ReviewBar.send_part`: after the last hunk is decided, `yield review_files.refresh()` so the refreshed handler can advance.
- 🔷 `ReviewBar.decide_file`: same refresh after a whole-file decision.
- 🔷 `SourceView.close_file`: clear editor state, `activate_file(null)`, sync review bar with `current_file == null`.
- 🔷 `SourceView` `refreshed` handler: when the queue is empty and a file is still open, call `close_file`.
- 🔷 `CoderView`: on `active_file_changed(null)`, reset the file button label to **Select file** and hide doc preview.

## Attempts / changelog

- ✔️ 2026-11-14 — logged; implementation in `SourceView`, `ReviewBar`, `CoderView`.
- ✔️ 2026-11-14 — `send_part` / `decide_file` yield `review_files.refresh()` when the chunk is closed; `refreshed` calls `close_file` when the queue is empty; `CoderView` resets the file label when `active_file` is null.
- ✔️ 2026-11-14 — **Accept no-op fix:** `ReviewBar` routes zero-hunk files to `decide_file`; `FileHistory.commit_decided` calls `approve` / `revert` when the hunk list is empty; `rpc_approve` and `revert` resolve `filebase` rows off-tree.
- ✔️ 2026-11-14 — **Second Accept / edit file:** log `18:31:12` shows `FileDiffPart.apply` succeeded but queue stayed at 3 — `is_need_approval` not cleared on last hunk; Accept stayed visible via `show_review = pending || file_count > 0` while `active=-1`, so the next click hit `send_part`’s early return. Fixed: `FileDiffPart.commit` clears approval when the chunk closes; Accept only when a hunk is active (fallback `decide_file` when all hunks decided).

## Next

- 🔷 ⏳ Accept a deleted pending file with more pending rows behind it → next file opens.
- 🔷 ⏳ Accept the last pending file → editor closes, header shows **Select file**.