# Approval bar stays hidden when a file opens

**Status:** ✅ fixed — user verified. Pending queue loads before `open_file` syncs the review bar.

## Problem

- 🔷 Open a project that has unapproved changes. The review bar should be on screen, with Accept, for a file that still needs approval.
- 🔷 It is not. Loading a file leaves the bar hidden.
- 🔷 Earlier tries were separate logs. They are not a single history. This file is that history from here on.

## Evidence

ℹ️ Client log `~/.cache/ollmchat/ollmchat.debug.log` at 12:53. `files.sqlite` after that run.

- ✔️ Startup restored `/home/alan/gitlive/OLLMchat` and called `Folder.fetch_pending_approvals`. The pending list was not skipped.
- ✔️ The first open was `tests/editing/Hello world`. `File.read` failed: the path is not on disk. `loaded=false`, `chars=0`.
- ✔️ `FileHistory.parts` then ran for that open and the reply came back.
- ✔️ Four seconds later `tests/README.md` was opened. That read succeeded. There was no second `FileHistory.parts`.
- ✔️ `filebase` 746 `tests/README.md` has `is_need_approval=0`. It is not a pending file.
- ✔️ Three rows are still pending:
  - `tests/editing/Hello world` id 113029, `delete_id=43132`
  - `tests/editing/Hello world.txt` id 113031, `delete_id=43142`
  - `tests/um editing uh/hello world.txt` id 113033, `delete_id=0`
- ✔️ The bar is created hidden (`SourceView` sets `review_bar.visible = false`). Only `ReviewBar.sync_pending` and `ReviewBar.update_diff` set `visible` again. Nothing else in the tree writes `review_bar.visible`.

## Ruled out

- 🚫 The project picker skipping `review_files.refresh`. That was [`2026-11-14-CLOSED-no-approve-on-load.md`](done/2026-11-14-CLOSED-no-approve-on-load.md). The 12:53 run did fetch pending approvals.
- 🚫 `tests/README.md` itself needing Accept. Its `is_need_approval` flag is 0.

## Root cause

- ✔️ `SourceView.open_file` paints the review bar from `review_files.file_map` via `sync_pending`, but that map can still be empty when the open runs ahead of `ReviewFiles.refresh` (startup race: `activate_project` used `refresh.begin()`, then a restored or fallback open could finish before pending rows existed). Opening a non-pending file (`tests/README.md`) then called `show_pending_diff` with an empty map, so `file_count` stayed 0 and the bar never became visible.
- 🔷 Every file load must wait for the pending queue, then sync the bar — even when the open file is not in the queue.

## Prior logs

ℹ️ These are the separate notes that already touched this bar or the pending paint. They stay where they are. New attempts are recorded below, not in those files.

- ℹ️ [`done/2026-11-14-CLOSED-no-approve-on-load.md`](done/2026-11-14-CLOSED-no-approve-on-load.md) — startup opened the deleted row, then the restored README.
- ℹ️ [`done/2026-10-28-CLOSED-sandbox-edit-reloads-without-diff.md`](done/2026-10-28-CLOSED-sandbox-edit-reloads-without-diff.md)
- ℹ️ [`done/2026-10-29-CLOSED-change-view-render.md`](done/2026-10-29-CLOSED-change-view-render.md)
- ℹ️ [`done/2026-10-30-CLOSED-live-diff-edit-sync.md`](done/2026-10-30-CLOSED-live-diff-edit-sync.md)
- ℹ️ [`done/2026-10-30-FIXED-phone-open-file-crash.md`](done/2026-10-30-FIXED-phone-open-file-crash.md) — empty hunk list crashed `update_diff`.
- ℹ️ Plans `docs/plans/done/CODER-4.2.3.5*.md` — the approval-bar design.

## Proposed fix

- 🔷 `activate_project`: `yield review_files.refresh()` after `clear()` so restore/startup does not open a file before pending rows load.
- 🔷 `ReviewFiles.refresh`: overlapping callers wait for the in-flight refresh instead of returning immediately.
- 🔷 `SourceView.open_file`: `yield review_files.refresh()` before `sync_pending` / `show_pending_diff` so each load reconciles outstanding review files.

## Next

- 🔷 ⏳ Restart the app and open the project again. Expect `review queue files=3 visible=true` in `~/.cache/ollmchat/ollmchat.debug.log` when `README.md` opens, or the first pending file opens with Accept visible.
- ℹ️ Remove temporary `GLib.debug` in `ReviewBar` after user verifies.

## Attempts / changelog

- ✔️ 2026-11-14 — opened this log. Added `GLib.debug` in `ReviewBar.sync_pending` and `ReviewBar.update_diff` so the next run records `visible`, `files`, `parts`, and `hunks`.
- ✔️ 2026-11-14 — root cause above; applied yield-on-load in `ProjectManager.activate_project`, `SourceView.open_file`, and await-in-flight in `ReviewFiles.refresh`.
