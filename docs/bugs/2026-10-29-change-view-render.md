# Wire ChangeView into the source view

**Status:** ⏳ class is in the build; the editor still reloads the file. Call sites not proposed.

ℹ️ The class, `unchanged`, and `compare` are already applied. That record is [`2026-10-28-sandbox-edit-reloads-without-diff.md`](2026-10-28-sandbox-edit-reloads-without-diff.md). This log is only the render path.

## Problem

- 🔷 Expected: an applied edit inserts the new lines in the open source view and paints them as the pending diff against what is approved.
- 🔷 Actual: `SourceView` still replaces the whole buffer. `ChangeView` is never constructed.

## Evidence

- ✔️ `liboccoder/ChangeView.vala` is compiled. `update` builds a secondary view and does not write. `apply` writes an empty `parts` list with one `set_text`. A filled list goes through `apply_parts`. Nothing in `SourceView` calls either method.
- ✔️ `event.project.invalidate_cache` in `SourceView`'s constructor calls `file.read`, then `source_view.set_buffer`, then restores the cursor and the scroll. If `review_files.file_map` already has the path, it calls `show_pending_diff` instead of restoring the scroll.
- ✔️ `review_files.refreshed` calls `show_pending_diff` for the current file, or `open_file` for the first queued path.
- ✔️ `open_file` reads the file when the buffer is not loaded, calls `set_buffer`, then `show_pending_diff`, then restores the cursor and the scroll on idle.
- ✔️ `show_pending_diff` calls `FileHistory.parts` for `approve_id`, builds a second `GtkSource.Buffer`, and `set_buffer`s that in. It then calls `ReviewBar.update_diff`.
- ℹ️ Same run as the parent log. Eight history rows were stored. `file_diff_part` was empty because `FileHistory.parts` never ran.

## Root cause

- ✔️ Confirmed in the parent log. `invalidate_cache` means the open project changed. The handler answers with `file.read`, which clears the buffer and inserts the whole file. `show_pending_diff` does the same kind of replacement with a second buffer.
- ✔️ Scroll and cursor restore belong on the first open. They are the wrong response to a later save of the file already on screen.

## Proposed fix

- 🔷 `SourceView` holds the current `ChangeView`. Construct it with the editor buffer. It starts empty. Empty is the flag. The secondary view is the one `update` returns. Do not swap the two instances.
- 🔷 The pump is `update`, then `apply`. That is the first fill and `invalidate_cache`.
- 🔷 `update` takes the file and the incoming hunks. The caller passes the returned view to `apply`. `update` does not call `apply`.
- 🔷 `open_file` is the only place that puts the scroll back.
- 🔷 `ReviewBar.update_diff` redraws the hunk strip. It does not edit the buffer. `apply` does not call it. The caller does, after `apply`.
- 🚫 `file.read` then `set_buffer` on `invalidate_cache`.
- 🚫 `show_pending_diff`: a second buffer, `display` and `kinds`, then `set_buffer`.
- 🚫 Painting the newest history row (`approve_id`) as the whole pending diff.
- 🚫 Replaying the eight history rows in time order. Eight saves are one `update` against what is approved.
- 🚫 A field on `SourceView` that keeps the secondary change view.
- ⏳ The `SourceView` edits are not fenced yet. Do not apply them from this note alone.
- ⏳ Where the incoming hunks come from on the first fill and on `invalidate_cache`. `FileHistory.parts` is the only loader today, and it was keyed to the newest row.
- 💩 `open_file` still calls `file.read` when `file.buffer.is_loaded` is false. That is the first load of an empty buffer. Whether that read stays, with `update` / `apply` after it, is not decided.

## Attempts / changelog

- ℹ️ 2026-10-28 — investigation and the class proposal live in the parent log.
- ✔️ 2026-10-29 — phase one compiled: `ChangeView`, client `compare` / `update_sum`, `unchanged` on both parts. `SourceView` was not changed.
- 🔷 2026-10-29 — this file is the render work. The parent log stays the class record.

## Next

- ⏳ Propose the `SourceView` fences: construct the current `ChangeView`, and call `update` then `apply` on the first fill and on `invalidate_cache`.
- ⏳ Name the hunk list that `update` receives. One update against what is approved.
