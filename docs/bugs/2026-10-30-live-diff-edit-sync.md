# Save live-diff edits to the file server

**Status:** ✔️ paused save applied in `liboccoder/SourceView.vala` — not checked in the app

ℹ️ The paint hook is [`2026-10-29-CLOSED-change-view-render.md`](done/2026-10-29-CLOSED-change-view-render.md). The class record is [`2026-10-28-CLOSED-sandbox-edit-reloads-without-diff.md`](done/2026-10-28-CLOSED-sandbox-edit-reloads-without-diff.md). Save-then-resync is [`CODER-4.2.3.5.7`](../plans/done/CODER-4.2.3.5.7-DONE-source-view-diff-resync.md).

## Problem

- 🔷 Expected: green lines and unchanged lines are the file on the server. Edits there are saved back up. After that save, the rebuilt diff matches the buffer. Red lines are not editable.
- 🔷 Actual: typing changes the editor only. Save copies that text into `file.buffer` only when every part is unchanged. A hunk on screen means Save writes the last plain read and drops the keystrokes. A later update then paints from that old server file.

## Evidence

- ✔️ `save_file` sets `plain` and copies the editor into `file.buffer` only when every `change_view.parts` item is `unchanged`. Then `file.buffer.sync_to_file()`. `liboccoder/SourceView.vala`.
- ✔️ The editor has no `insert-text` or `delete-range` handler. `notify["modified"]` only sets `current_file.is_unsaved`.
- ✔️ `ChangeView.proposal` reads `file.buffer`. `apply` writes the editor. Nothing writes an editor edit back.
- ✔️ `diff-remove` is `editable = false`. Added lines and unchanged lines stay editable. `ChangeView` constructor.
- ℹ️ [`CODER-4.2.3.5.7`](../plans/done/CODER-4.2.3.5.7-DONE-source-view-diff-resync.md): Save writes the project file with `sync_to_file` (`File.rpc_write`), then `show_pending_diff` loads `FileHistory.parts`. A stamp miss runs `rebuild_parts` against that file.
- ℹ️ The server file is the new side of the diff. Green lines are the additions in that file. Unchanged lines are the rest of that file. Red lines are the old text and are not in the file.
- ℹ️ The app was not run for this log. The path is the source above.

## Root cause

- ✔️ The paint hook keeps the editor and `file.buffer` as two objects. The only bridge is the whole-text copy in `save_file`, and that copy is skipped when any part is a hunk. The keystrokes never reach the server.
- ✔️ The next paint is whatever `rebuild_parts` last stored for the project file. An edit that is only in the editor is not in that file, so the paint replaces it.

## Proposed fix

- 🔷 A pause after the last edit writes the file on the server. The same path as Save: `sync_to_file`, then `show_pending_diff`. The next writer on the file server reads that file. `rebuild_parts` makes the diff match the buffer.
- 🔷 The bytes written are every editor line that does not carry `diff-remove`. That is the unchanged lines and the green lines, including edits to them. Red lines are left out.
- ✔️ Red lines stay `editable = false`. No new lock.
- ✔️ The pause is 2 seconds after the last edit. Each change resets it. Scroll saving uses the same shape at 500 ms. This write also rebuilds the diff, so it waits until typing stops.
- 🚫 Teaching `ChangeView` to absorb each keystroke, shift later parts, and replay the edit onto the next `proposal`. A later server update replaces that paint. Replaying the local edit onto the new diff is not the fix.
- 🚫 Copying the whole editor into `file.buffer` while a hunk is showing. That text includes the red lines.
- ℹ️ Edits are **Remove** / **Replace with** / **Add** from the tree.

### 1. `liboccoder/SourceView.vala` — pause, then save

**Why:** The file server has to be holding the latest text before something else writes the same file.

**Where:** next to `scroll_save_timeout_id`, and the `notify["modified"]` handler in the constructor.

**Depends on:** §2. The save must send the non-red text.

#### Add — after `scroll_save_timeout_id`

The id is `0` while no pause is waiting.

```vala
			/**
			 * Pause after the last edit before the file is
			 * written. Reset on each change. Zero when idle.
			 */
			private uint save_timeout_id = 0;
```

#### Remove

```vala
				source_buffer.notify["modified"].connect(() => {
					if (this.current_file != null) {
						this.current_file.is_unsaved = source_buffer.get_modified();
					}
				});
```

#### Replace with

Arm one save when the editor is modified. A file switch or a cleared modified flag drops it.

```vala
				source_buffer.notify["modified"].connect(() => {
					if (this.current_file == null) {
						return;
					}
					this.current_file.is_unsaved = source_buffer.get_modified();
					if (!source_buffer.get_modified()) {
						return;
					}
					if (this.save_timeout_id != 0) {
						GLib.Source.remove(this.save_timeout_id);
					}
					var file = this.current_file;
					this.save_timeout_id = GLib.Timeout.add(2000, () => {
						this.save_timeout_id = 0;
						if (this.current_file != file || !source_buffer.get_modified()) {
							return false;
						}
						this.save_file.begin();
						return false;
					});
				});
```

### 2. `liboccoder/SourceView.vala` — `save_file` writes the non-red text

**Why:** Green and unchanged lines are the server file. Red lines are not. The copy runs for a hunked file as well as a plain one, then the existing `sync_to_file` and `show_pending_diff` run.

**Where:** `save_file`, the `plain` loop through the `set_text` that follows it. Cancel any waiting pause at the top of the method, after the `current_file` null return.

**Depends on:** none.

#### Add — after the `current_file` null return in `save_file`

A manual save must not also run the waiting pause.

```vala
				if (this.save_timeout_id != 0) {
					GLib.Source.remove(this.save_timeout_id);
					this.save_timeout_id = 0;
				}
```

#### Remove

```vala
				var plain = true;
				for (var i = 0; i < this.change_view.parts.size; i++) {
					if (this.change_view.parts.get(i).unchanged) {
						continue;
					}
					plain = false;
					break;
				}
				if (plain) {
					Gtk.TextIter start_iter;
					Gtk.TextIter end_iter;
					(this.source_view.buffer as GtkSource.Buffer).get_bounds(out start_iter, out end_iter);
					(file.buffer as GtkSource.Buffer).set_text(
						(this.source_view.buffer as GtkSource.Buffer).get_text(start_iter, end_iter, false),
						-1);
				}
```

#### Replace with

Skip each `diff-remove` line. A source file can be hundreds of lines, so the text is a `StringBuilder`.

```vala
				var editor = this.source_view.buffer as GtkSource.Buffer;
				var remove_tag = editor.tag_table.lookup("diff-remove");
				var kept = new GLib.StringBuilder();
				Gtk.TextIter cursor;
				editor.get_start_iter(out cursor);
				while (!cursor.is_end()) {
					var line_end = cursor;
					if (!line_end.ends_line()) {
						line_end.forward_to_line_end();
					}
					if (remove_tag != null && cursor.has_tag(remove_tag)) {
						if (!cursor.forward_line()) {
							break;
						}
						continue;
					}
					if (kept.len > 0) {
						kept.append_c('\n');
					}
					kept.append(editor.get_text(cursor, line_end, false));
					if (!cursor.forward_line()) {
						break;
					}
				}
				(file.buffer as GtkSource.Buffer).set_text(kept.str, -1);
```

## Attempts / changelog

- ℹ️ 2026-10-30 — found while reading the `save_file` copy in the render hook. No code change.
- ℹ️ 2026-10-31 — first fences tried to keep `ChangeView` in step with each keystroke and replay that edit onto the next paint. Rejected. The server file is the non-red text. A paused save writes that file and `rebuild_parts` refreshes the diff.
- ℹ️ 2026-10-31 — red stays non-editable. Green and unchanged lines are what the save sends.
- ✔️ 2026-10-31 — applied in `liboccoder/SourceView.vala`. Comments on the pause, the manual-save cancel, and the red-line skip. Not run in the app.

## Next

- ⏳ Try an edit on a green line, wait for the pause, and confirm the server file matches the buffer and the red lines are unchanged.
