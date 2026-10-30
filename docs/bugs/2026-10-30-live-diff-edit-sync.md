# Sync live-diff edits into the file buffer

**Status:** ⏳ root cause confirmed from the source; sync mapping open — await approval

ℹ️ The paint hook is [`2026-10-29-CLOSED-change-view-render.md`](done/2026-10-29-CLOSED-change-view-render.md). The class record is [`2026-10-28-CLOSED-sandbox-edit-reloads-without-diff.md`](done/2026-10-28-CLOSED-sandbox-edit-reloads-without-diff.md). Save-then-resync is [`CODER-4.2.3.5.7`](../plans/done/CODER-4.2.3.5.7-DONE-source-view-diff-resync.md).

## Problem

- 🔷 Expected: editing the live diff writes those changes into the file buffer.
- 🔷 Actual: typing changes the editor only. Save copies that text into `file.buffer` only when every part is unchanged. A hunk on screen means Save writes the last plain read and drops the keystrokes.

## Evidence

- ✔️ `save_file` sets `plain` and copies the editor into `file.buffer` only when every `change_view.parts` item is `unchanged`. Then `file.buffer.sync_to_file()`. `liboccoder/SourceView.vala`.
- ✔️ The editor has no `insert-text` or `delete-range` handler. `notify["modified"]` only sets `current_file.is_unsaved`.
- ✔️ `ChangeView.proposal` reads `file.buffer`. `apply` writes the editor. Nothing writes an editor edit back.
- ✔️ `diff-remove` is `editable = false`. Added lines and unchanged lines stay editable. `ChangeView` constructor.
- ℹ️ [`CODER-4.2.3.5.7`](../plans/done/CODER-4.2.3.5.7-DONE-source-view-diff-resync.md) and [`CODER-4.2.3.5.4`](../plans/done/CODER-4.2.3.5.4-DONE-source-view-diff-wire-model.md): Save writes the project file with `sync_to_file`, then `FileHistory.parts` / `rebuild_parts` refills the hunks.
- ℹ️ [`CODER-4.2.3`](../plans/done/CODER-4.2.3-DONE-source-view-diff.md) left open whether an unsaved edit is folded into the review overlay. That is a different question. This log is the write into `file.buffer`.
- ℹ️ The app was not run for this log. The path is the source above.

## Root cause

- ✔️ The paint hook keeps the editor and `file.buffer` as two objects. The only bridge is the whole-text copy in `save_file`, and that copy is skipped when any part is a hunk.
- ✔️ A keystroke does not update `file.buffer` or the part that owns the span. The parts stay the last paint. The next `proposal` is built from `file.buffer`, so it can replace the keystrokes.

## Proposed fix

- 🔷 An edit in the live diff syncs into `file.buffer`.
- 💩 An insert or delete in an unchanged span or an added span is applied at the same place in `file.buffer`. Removed lines are not in that buffer. The remove tag already refuses typing there.
- 💩 The part that owns the span updates `hunk_add`, its line range, and `update_sum()`. Later parts shift when the line count changes. The next `apply_parts` then sees the edit.
- 💩 `apply` writes the editor from `file.buffer`. Those writes are not user edits and must not be copied back.
- 🚫 Copying the whole editor into `file.buffer` while a hunk is showing. That text includes the removed lines.
- 🚫 Rebuilding the saved file from the parts as they stand. Those parts do not contain the keystrokes.
- ⏳ The Vala fence waits on this mapping. Do not apply from this note alone.

## Attempts / changelog

- ℹ️ 2026-10-30 — found while reading the `save_file` copy in the render hook. No code change.

## Next

- ⏳ Approve the mapping: editor insert/delete in an unchanged or added span updates `file.buffer` and that part. Then the fence.
