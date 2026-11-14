# Approval bar stays hidden when a file opens

**Status:** ⏳ open — critical. This is the log for the missing Accept bar. Further attempts go here.

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

- ⏳ Not confirmed. Pending data is present and `FileHistory.parts` ran for the deleted file. The bar is still not on screen after that, and opening `README.md` does not ask for parts.

## Prior logs

ℹ️ These are the separate notes that already touched this bar or the pending paint. They stay where they are. New attempts are recorded below, not in those files.

- ℹ️ [`done/2026-11-14-CLOSED-no-approve-on-load.md`](done/2026-11-14-CLOSED-no-approve-on-load.md) — startup opened the deleted row, then the restored README.
- ℹ️ [`done/2026-10-28-CLOSED-sandbox-edit-reloads-without-diff.md`](done/2026-10-28-CLOSED-sandbox-edit-reloads-without-diff.md)
- ℹ️ [`done/2026-10-29-CLOSED-change-view-render.md`](done/2026-10-29-CLOSED-change-view-render.md)
- ℹ️ [`done/2026-10-30-CLOSED-live-diff-edit-sync.md`](done/2026-10-30-CLOSED-live-diff-edit-sync.md)
- ℹ️ [`done/2026-10-30-FIXED-phone-open-file-crash.md`](done/2026-10-30-FIXED-phone-open-file-crash.md) — empty hunk list crashed `update_diff`.
- ℹ️ Plans `docs/plans/done/CODER-4.2.3.5*.md` — the approval-bar design.

## Next

- 🔷 ⏳ Restart the app and open the project again. `~/.cache/ollmchat/ollmchat.debug.log` should contain `review queue` and `review bar` lines: `visible`, `files`, `parts`, `hunks`.
- ℹ️ Those lines are temporary. They come out once this log says why the bar stays hidden.

## Attempts / changelog

- ✔️ 2026-11-14 — opened this log. Added `GLib.debug` in `ReviewBar.sync_pending` and `ReviewBar.update_diff` so the next run records `visible`, `files`, `parts`, and `hunks`.
