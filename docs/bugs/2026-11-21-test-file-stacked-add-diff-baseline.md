# New file + follow-up edits: diff baseline should be empty, not latest backup

**Status:** ⏳ Applied in `FileHistory.rebuild_parts` — await user verify on gtktest1 `test-file.txt`.

**Pointer:** `docs/bug-fix-process.md` · related [gtktest1 write loop](done/2026-11-20-FIXED-desktop-write-file-edit-loop.md).

## Problem

- 🔷 **Expected:** `/home/alan/gitlive/gtktest1/test-file.txt` was **created** (first history row `added`, no backup). Later **modified** rows have backups. Nothing on the file has ever been approved. The review diff should be **empty file → current file** (all green adds).
- 🔷 **Actual:** Source view shows **red and green** — diff is **latest pending row’s backup** vs disk, not empty vs disk.

## Reproduction

1. Project `gtktest1`, open `test-file.txt` with pending review (same state as 2026-11-20 agent/bash overlay session).
2. Open file in coder → pending diff overlays.

## Evidence

- ✔️ `files.sqlite` `file_history` for `test-file.txt`:
  - `43144` — `change_type=added`, `reviewed=0`, `backup_path=""` (valid for new file).
  - `43145`–`43150` — `change_type=modified`, `reviewed=0`, each has `backup_path` under `~/.cache/ollmchat/edited/`.
- ✔️ `FileWithHistory.pending` sets **`approve_id`** to the **newest** `reviewed=0` row → **`43150`** (`modified`), not `43144` (`added`).
- ✔️ `SourceView.show_pending_diff` calls `FileHistory.parts` with that `approve_id`.
- ✔️ `FileHistory.rebuild_parts` loads **`history.backup_path`** for that row and diffs it against the project file — so baseline is **pre-edit snapshot before edit #6**, not **empty**.

## Root cause

- ✔️ Review UI always paints the **newest pending chunk’s** backup vs disk. For a file whose **first unapproved chunk is `added` (empty backup)**, the user-visible baseline should still be **empty** (or “last approved”, which here is empty). Instead the newest `modified` row’s backup wins → misleading red deletions.

## Proposed fix

- 🔷 **Approved:** If the **oldest** pending row for the path is `added` with `backup_path == ""`, diff left side is **empty string** (ignore newer rows’ backups until the stack is approved).
- ✔️ **Applied** `ollmfilesd/FileHistory.vala` — `rebuild_parts` queries oldest `reviewed = 0` row; when `added` + empty backup, skip loading `history.backup_path`.

## Attempts / changelog

- ✔️ 2026-11-21 — Queried `files.sqlite`; traced `approve_id` + `rebuild_parts` vs user expectation (gtktest1 `test-file.txt`).

## Accept no-op (stacked rows)

- ✔️ Log `21:10:32` — `FileDiffPart.apply` OK, queue stays `files=1`, diff repaints (head chunk `43150` reviewed, six older rows still `reviewed=0`).
- ✔️ **Fix:** `FileDiffPart.commit` — stacked `added` + accept → `FileHistory.approve` whole path.

## Post-accept UX (bar + plain buffer)

- 🔷 Bar stays while file stays open: accepted chunk, map + **Unapprove** on bands; label **Changes accepted** when queue empty.
- ✔️ No `set_text` from file buffer (stripped green wrong). Closed chunk → `ChangeView.proposal` with accepted parts → plain lines; skip `show_pending_diff` before `refresh`.

## Next

- ⏳ Rebuild → restart filesd → open `test-file.txt` → all-green diff → Accept → white buffer, queue empty, bar inactive.