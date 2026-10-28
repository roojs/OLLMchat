# Sandbox edits reload the whole file and never paint the diff

**Status:** ⏳ root cause confirmed from the 08:19 Agent Pi transcript and `files.sqlite` — fix not applied

Same run as [`2026-10-28-sandbox-git-status-truncates-index.md`](2026-10-28-sandbox-git-status-truncates-index.md). The model was told to bundle `FileConnectionAdd` onto the end of `examples/oc-test-source-diff.vala`. The `write` tool never applied a fence. Bash did change the live file. Each of those writes replaced the open buffer with the whole file. History rows were stored. The source view never loaded them, so nothing was highlighted.

## Problem

- 🔷 Expected: an applied edit inserts the new lines in the open source view and paints them as the pending diff against the backup.
- 🔷 Actual: each sandbox write reloaded the entire file into the editor. No hunk highlight appeared.
- 🔷 The `write` tool was called eight times and applied nothing. The model then edited with `cat`, `sed`, and `awk`.

## What the transcript shows

- ℹ️ Chat log `/home/alan/.cache/ollmchat/ollmchat.debug.log`, daemon log `/home/alan/.cache/ollmchat/ollmfilesd.debug.log`, from 08:19 to 08:30.
- ✔️ First `LS` missed the directory: `ls: cannot access 'home/alan/gitlive/OLLMchat/examples/oc-test-source-diff'` (no leading slash). A later `bash` `ls -la` saw the symlink `FileConnectionAdd.vala` → `../../ollmapp/android/FileConnectionAdd.vala`.
- ✔️ 08:23:49 `rm -rf examples/oc-test-source-diff` printed `removed symlink dir`. That was a whiteout in the overlay. The live directory is still there. The model treated the delete as done.
- ✔️ `write` (class `OLLMtools.EditMode.Write`) does not take the new text as an argument. It turns on edit mode and tells the model to emit a fenced block before the turn ends. All eight calls were tool-only turns. The harness then inserted: "You enabled edit mode for '…oc-test-source-diff.vala' but did not provide any code blocks". One of those was `examples/meson.build`. No fence was ever sent, so edit mode applied nothing.
- ✔️ The model switched to bash. 08:26:08 `cat >> examples/oc-test-source-diff.vala` appended `namespace OLLMapp.SettingsDialog` / `class FileConnectionAdd`. That is the change that was supposed to happen.
- ✔️ Later `sed -i` and `awk | mv` tried to rewrite `This.` to `this.` and to fix browse helpers. The seccomp log says `blocked write path=examples/oc-test-source-diff.vala`. The notify answers `USER_NOTIF_FLAG_CONTINUE`, so the write still lands in the overlay and the scan publishes it. The live `show_add` is now broken: line 1350 is `this.registered_url = null;` and 1351 is the same assignment without a semicolon, then the body of the idle callback is spliced into the method.
- ✔️ 08:29:16 a second bash in the same second failed: `Cannot create overlay directory structure: …/overlay-20261028-082916: File exists`. The overlay directory name is the timestamp to the second.
- ✔️ 08:29:06 `git status` truncated `.git/index` (the other bug). 08:29:38 `git diff` returned `fatal: .git/index: index file smaller than expected`.

## Evidence — history was stored

- ✔️ `filebase` id 110944, path `examples/oc-test-source-diff.vala`, `is_need_approval = 1`, `last_change_type = modified`, `is_ignored = 0`.
- ✔️ Eight unreviewed `file_history` rows, 43018 through 43027, timestamps 08:26:08, 08:27:24, 08:27:39, 08:27:59, 08:28:40, 08:28:45, 08:28:53, 08:29:26. Each has a backup under `~/.cache/ollmchat/edited/`.
- ✔️ First backup is 1242 lines (the file before the append). The live file is 1453 lines.
- ✔️ `file_diff_part` has zero rows. `FileHistory.parts` is what inserts them, and only when something calls it. Nothing did.

## Evidence — the editor reloads the whole file

- ✔️ `ollmfilesd/FileVerification.modified` copies the overlay file with `file.realize`, which is `buffer.write_real` of the entire string, then sends `event.project.invalidate_cache`.
- ✔️ `liboccoder/SourceView` on that notification calls `file.read` and `set_buffer` on the whole buffer. It clears a diff that was already showing. It calls `show_pending_diff` only when `review_files.file_map` already contains the path.
- ✔️ `show_pending_diff` is the only caller of `FileHistory.parts`. That call builds the hunks from the backup and paints them. It never ran: the part table is empty.
- ✔️ The refresh that fills `file_map` is `review_files.refresh`, hooked from `liboccoder/Approvals` on `invalidate_cache`. Nothing in the tree constructs `Approvals`. The write-tool path refreshes after a fence is applied. This run never applied a fence, so that refresh did not run either.
- ✔️ The pending query's `approve_id` is the newest unreviewed row only (`FileWithHistory` subquery `ORDER BY timestamp DESC LIMIT 1`). Even after a refresh, the paint would be the last awk step (backup 43027), not the original 1242-line file. The earlier seven backups would stay unused.

## Root cause

- ✔️ The signal is `event.project.invalidate_cache`. It means "the open project changed".
- ✔️ The handler then calls `file.read`. That is not a signal. `File.read` clears the buffer and inserts the entire file at line 1 (`buffer.clear`, then `apply_edit` with `start = 1`). The handler then swaps that buffer onto the view and jumps the scroll back to the saved position.
- ✔️ Scroll and cursor restore belong in `open_file`, the first time a file is shown. They are the wrong response to a later save of the file already on screen.
- ✔️ `show_pending_diff` is the same kind of replacement. It builds a second buffer from every line and swaps that in. Calling it after a save would still throw away the view.

## Proposed fix

- 🚫 Painting the newest history row onto whatever buffer is showing. A refresh is not one edit, and the thing on screen is not always the file.
- 💩 The `write` tool still expects a code fence in the same turn. That is why the model gave up and used bash. Separate from the editor.
- 🚫 The "blocked write" line in the daemon log did not stop the write. Do not treat that log line as a fix.

### Strategy

A file the user is looking at is one buffer. Opening it is the only time that buffer is filled with the whole file, and the only time the scroll is put back.

These are different events. They are currently treated as one reload:

1. A sandbox save writes the whole file and says the project changed. It does not say which lines changed.
2. The editor answers by reading the whole file and jumping the scroll. That answer is only right the first time the file is opened.
3. The pending list is the saved steps. This run has eight. Each step kept the file from before that step. The list's `approve_id` is only the latest step.
4. The green and red view is a second document. It is built by copying every line. Once the red lines are in it, its line numbers are not the file's line numbers. The green tag belongs to that document's tag table. It was never on the file buffer.
5. Accept and reject already change the file buffer at a line. The coloured document is then built again, so that change is thrown off the screen.

The project-changed notice means new steps may be waiting. It does not load the file.

Steps are applied in time order. A step is applied only when the text in the file buffer is still that step's backup. The lines inserted or removed are the difference between that backup and the file after that step. When the step has been applied, the buffer matches the next step's backup, so the next step can be applied. Eight saves are eight steps. They are not one paint of the last `awk`.

If the buffer does not match the next backup, nothing is painted. That is the case when the user has typed, when the same step is delivered again, and when the coloured document is what is on screen. Updates are not applied to that coloured document.

Highlighting is not a separate pass over whatever is on screen. A step that has just been applied to the file buffer can be marked with the green and red tag that already exists. Copying that tag onto another buffer, or building the coloured document and calling that the refresh, is not part of this.

### What a fresh step hands us

- ✔️ The old file is that step's backup. The new file is the project file after the step. The diff is those two texts.
- ✔️ `FileDiffPart` is only the changed hunks. Add, remove, or replace. Each part has the removed lines (`hunk_remove`), the added lines (`hunk_add`), and the old and new line numbers. It does not contain the unchanged stretches. The differ skips equal lines when it builds patches. A gap between one part's `new_line_end` and the next part's `new_line_start` is the unchanged run, and those lines stay as they are.
- ✔️ A first show has no current parts. The walk is just the new parts, in order, and the unchanged gaps between them.
- ✔️ A later step already has a current part list. `FileDiffPart.compare` says whether two parts are the same: `3` same lines and same text, `1` same lines only, `2` same text only, `0` neither. The daemon already uses that when it stores parts. The buffer walk is the same idea on screen.
- 🔷 `SourceView.update_diff` walks the new parts against the current parts. Same part (`3`): leave that stretch. A part that changed: replace that stretch in the file buffer. A current part with no new part: take it out. A new part with no current part: put it in. Unchanged gaps are not touched.
- 🔷 That method then calls `ReviewBar.update_diff`. That is the existing call that redraws the hunk strip at the bottom. It does not edit the buffer.

## Attempts / changelog

- ✔️ 2026-10-28 — read the 08:19–08:30 transcript, the eight history rows, and the empty `file_diff_part` table.
- 🚫 2026-10-28 — reloading the file and then painting `show_pending_diff` still replaces the whole view and restores the scroll. That is first-open behaviour.
- 🚫 2026-10-28 — `on_review_files_refresh` inserting the newest history row into the buffer on screen, including a second copy of the green tag. The buffer on screen is not always the file, and eight saves are eight steps.
