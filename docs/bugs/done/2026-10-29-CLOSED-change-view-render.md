# Wire ChangeView into the source view

**Status:** 🚫 CLOSED 2026-10-30. §1–§6 are in `liboccoder/SourceView.vala`. Not checked in the app. Editing that paint is [`2026-10-30-live-diff-edit-sync.md`](../2026-10-30-live-diff-edit-sync.md).

ℹ️ The class, `unchanged`, and `compare` are already applied. That record is [`2026-10-28-CLOSED-sandbox-edit-reloads-without-diff.md`](2026-10-28-CLOSED-sandbox-edit-reloads-without-diff.md). The paint is `ChangeView.apply`. This log is only the call from `SourceView`.

## Problem

- 🔷 Expected: an applied edit inserts the new lines in the open source view and paints them as the pending diff against what is approved.
- 🔷 Actual: `SourceView` still replaces the whole buffer. `ChangeView` is never constructed.

## Evidence

- ✔️ `liboccoder/ChangeView.vala` is compiled. `proposal` builds a secondary view and does not write. `apply` writes an empty `parts` list with one `set_text`. A filled list goes through `apply_parts`. Nothing in `SourceView` calls either method.
- ✔️ `event.project.invalidate_cache` in `SourceView`'s constructor calls `file.read`, then `source_view.set_buffer`, then restores the cursor and the scroll. If `review_files.file_map` already has the path, it calls `show_pending_diff` instead of restoring the scroll.
- ✔️ `review_files.refreshed` calls `show_pending_diff` for the current file, or `open_file` for the first queued path.
- ✔️ `open_file` reads the file when the buffer is not loaded, calls `set_buffer`, then `show_pending_diff`, then restores the cursor and the scroll on idle.
- ✔️ `show_pending_diff` calls `FileHistory.parts` for `approve_id`, builds a second `GtkSource.Buffer`, and `set_buffer`s that in. It then calls `ReviewBar.update_diff`.
- ℹ️ Same run as the parent log. Eight history rows were stored. `file_diff_part` was empty because `FileHistory.parts` never ran.
- ✔️ `ChangeView.update` reads `file.buffer.get_text()`. `apply` writes the buffer given to the constructor. `open_file` and `invalidate_cache` make those the same object: `source_view.set_buffer(file.buffer)`.
- ✔️ Parent log: history 43018 is the first backup (1242 lines). The live file is 1453 lines. `approve_id` is 43027. `rebuild_parts` diffs the backup of the id it was given. [`CODER-4.2.3.5.5`](../plans/done/CODER-4.2.3.5.5-DONE-source-view-diff-items.md) keeps that: `parts` takes `approve_id`, and the left side is that row's `backup_path`.

## Root cause

- ✔️ Confirmed in the parent log. `invalidate_cache` means the open project changed. The handler answers with `file.read`, which clears the buffer and inserts the whole file. `show_pending_diff` does the same kind of replacement with a second buffer.
- ✔️ Scroll and cursor restore belong on the first open. They are the wrong response to a later save of the file already on screen.

## Proposed fix

- 🔷 The paint is `ChangeView.apply`: the text edit and the green and red tags. `SourceView` does not build a display buffer and does not apply those tags. It holds the current `ChangeView` and calls `proposal` then `apply`.
- 🔷 `SourceView` holds the current `ChangeView`. Construct it with `source_view.buffer`. It starts empty. Empty is the flag. The secondary view is the one `proposal` returns. Do not swap the two instances.
- 🔷 The editor buffer and `file.buffer` stay different objects. `file.read` fills the plain file. `apply` writes the editor. `set_buffer` is what made them the same object.
- 🔷 The pump is `proposal`, then `apply`. That is the first fill and `invalidate_cache`. Both go through `show_pending_diff`. `refreshed` and `save_file` already call it.
- 🔷 The hunk list is `parts`: the array `FileHistory.parts` returns for `approve_id`. That contract is [`CODER-4.2.3.5.5`](../plans/done/CODER-4.2.3.5.5-DONE-source-view-diff-items.md). `rebuild_parts` diffs that row's `backup_path` against the project file. Each item is one hunk: `hunk_remove`, `hunk_add`, and the line range. This log does not change `FileHistory`.
- 🔷 `proposal` takes the file and `parts`. The caller passes that proposal to `apply`. `proposal` does not call `apply`.
- 🔷 `open_file` still calls `file.read` when `file.buffer.is_loaded` is false. That loads the plain text `proposal` slices. It does not call `set_buffer`. It is the only place that puts the scroll back. A different file clears `parts` and sets `empty` before the pump, so `apply` uses `set_text`.
- 🔷 `invalidate_cache` still calls `file.read`, then `show_pending_diff`. It does not call `set_buffer`. It does not restore the cursor or the scroll. The skip is the editor buffer's `get_modified()`, cleared at the end of `show_pending_diff`. Typing sets that flag. The paint must not.
- 🔷 `ReviewBar.update_diff` redraws the hunk strip from `parts` (the incoming hunks, not the secondary view). It does not edit the buffer. `apply` does not call it. `show_pending_diff` does, after `apply`.
- 🔷 `save_file` copies the editor into `file.buffer` before `sync_to_file` when every current part is `unchanged`. A real hunk leaves the plain file as the save source.
- 🚫 `set_buffer` in `open_file`, on `invalidate_cache`, and in `show_pending_diff`.
- 🚫 `show_pending_diff`: a second buffer, `display` and `kinds`, then `set_buffer`.
- 🚫 A new query in `rebuild_parts` for the oldest unreviewed backup. Flow B reviews the active chunk only ([`CODER-4.2.3`](../plans/done/CODER-4.2.3-DONE-source-view-diff.md)).
- 🚫 Replaying the eight history rows in time order. One `FileHistory.parts` call for `approve_id`.
- 🚫 A field on `SourceView` that keeps the secondary change view.
- ℹ️ `show_diff` and `clear_diff` still swap `diff_buffer`. This hook does not call them.
- ✔️ 2026-10-30 — §1–§6 applied. `liboccoder` Vala compiled.

### 1. `liboccoder/SourceView.vala` — construct the current `ChangeView`

**Why:** The view keeps the buffer `GtkSource.View` created. `ChangeView` writes that buffer. `file.buffer` stays the plain file.

**Where:** the `source_view` property, then the constructor, on the line after the `source_view` object initializer and before `add_css_class("source-view")`.

**Depends on:** none.

#### Add — after the `source_view` property

The field is assigned in the constructor. It has no initializer.

```vala
			/**
			 * Current change view. Constructed with the editor
			 * buffer. Starts empty. The secondary view is only
			 * the return from {@link ChangeView.proposal}.
			 */
			private ChangeView change_view;
```

#### Add — after the `source_view` object initializer

The view's buffer exists once the view is constructed.

```vala
				this.change_view = new ChangeView(this.source_view.buffer as GtkSource.Buffer);
```

### 2. `liboccoder/SourceView.vala` — `invalidate_cache`: read, then the pump

**Why:** A later save of the file already on screen splices the editor. It does not swap buffers or jump the scroll. `file.read` still runs so `file.buffer` is the new plain text `proposal` slices.

**Where:** the `check_changed` callback in the constructor. The `NO_CHANGE` and `current_file` checks stay. `file.buffer.is_modified` becomes the editor flag. The `read` callback loses `save_current_file_state`, `set_buffer`, and both restores.

**Depends on:** §1 and §4.

#### Remove

```vala
						if (file.check_changed.end(res) == OLLMfiles.FileUpdateStatus.NO_CHANGE
							|| this.current_file != file
							|| file.buffer.is_modified) {
							return;
						}
						this.save_current_file_state();
						file.read.begin((read_obj, read_res) => {
							file.read.end(read_res);
							if (this.current_file != file) {
								return;
							}
							if (this.diff_active) {
								this.clear_diff();
							}
							this.source_view.set_buffer(file.buffer as GtkSource.Buffer);
							if (this.manager.review_files.file_map.has_key(file.path)) {
								this.show_pending_diff.begin(file);
								return;
							}
							this.restore_cursor_position(file);
							this.restore_scroll_position(file);
						});
```

#### Replace with

`show_pending_diff` clears `get_modified()` after it paints. A user edit sets the flag again and this callback returns.

```vala
						if (file.check_changed.end(res) == OLLMfiles.FileUpdateStatus.NO_CHANGE
							|| this.current_file != file
							|| (this.source_view.buffer as GtkSource.Buffer).get_modified()) {
							return;
						}
						file.read.begin((read_obj, read_res) => {
							file.read.end(read_res);
							if (this.current_file != file) {
								return;
							}
							this.show_pending_diff.begin(file);
						});
```

### 3. `liboccoder/SourceView.vala` — `open_file`: first fill

**Why:** The first load still reads the plain file. The view is already on the change-view buffer, so there is no `set_buffer`. Switching files drops the previous `parts` so the next `apply` is `set_text`. The scroll restore later in this method stays.

**Where:** replace the `set_buffer` comment and call. `current_file = file` stays on the following line. The idle `restore_cursor_position` / `restore_scroll_position` stays.

**Depends on:** §1 and §4.

#### Remove

```vala
				// Switch view to file's buffer (GtkSourceFileBuffer IS a GtkSource.Buffer)
				this.source_view.set_buffer(gtk_buffer);
```

#### Replace with

`gtk_buffer` is still `file.buffer`. Its language moves onto the editor buffer. Highlighting follows the file. The buffer object does not.

```vala
				if (this.current_file != file) {
					this.change_view.parts.clear();
					this.change_view.empty = true;
				}
				(this.source_view.buffer as GtkSource.Buffer).language = gtk_buffer.language;
```

### 4. `liboccoder/SourceView.vala` — `show_pending_diff`: `proposal` then `apply`

**Why:** This is the pump. Callers stay: `open_file`, `invalidate_cache`, `review_files.refreshed`, `save_file`, and `ReviewBar`. A path that is not pending still runs the pump with an empty `parts` list, so a reload with no hunks paints the plain file.

**Where:** replace the docblock and the method body. The signature stays `public async void show_pending_diff(OLLMfiles.File file)`.

**Depends on:** §1.

#### Remove

```vala
			/**
			 * If ''file'' is pending approval, load diff items and paint them.
			 *
			 * Calls ''FileHistory.parts''. Does not read the backup.
			 *
			 * @param file open project file (buffer already holds V_disk)
			 */
```

#### Replace with

`parts` is the hunk list `proposal` receives. Empty means the whole file is unchanged.

```vala
			/**
			 * Paint ''file'' through the current change view.
			 *
			 * Pending paths load one ''FileHistory.parts'' reply
			 * for ''approve_id'' into ''parts''. That array is the
			 * hunks for that history row. Any other path leaves
			 * ''parts'' empty.
			 * {@link ChangeView.proposal} then {@link ChangeView.apply}.
			 * The review bar is redrawn after apply.
			 *
			 * @param file open project file; ''buffer'' is the plain text
			 */
```

#### Remove

```vala
				if (!this.manager.review_files.file_map.has_key(file.path)) {
					return;
				}
				var row = this.manager.review_files.file_map.get(file.path);
				OLLMrpc.Response response;
				try {
					response = yield this.manager.rpc.call(new OLLMrpc.Request() {
						method = "FileHistory.parts",
						args = OLLMrpc.args("x", row.approve_id)
					});
				} catch (GLib.Error e) {
					GLib.warning("Failed to load diff parts for %s: %s", file.path, e.message);
					return;
				}
				if (this.current_file != file) {
					return;
				}
				if (response.error != null) {
					GLib.warning("Failed to load diff parts for %s: %s", file.path, response.error.message);
					return;
				}
				if (response.retval.type() == GLib.Type.INVALID) {
					if (this.diff_active) {
						this.clear_diff();
					}
					return;
				}
				if (this.diff_active) {
					this.clear_diff();
				}
				var parts = (Gee.ArrayList<OLLMfiles.FileDiffPart>) response.retval.get_object();
				var editor_lines = (file.buffer as GtkSource.Buffer).text.split("\n");
				var display = new Gee.ArrayList<string>();
				var kinds = new Gee.ArrayList<int>();
				this.diff_baseline.clear();
				this.diff_remove_at.clear();
				this.diff_remove_n.clear();
				var new_i = 1;
				foreach (var part in parts) {
					var add_count = part.new_line_end < part.new_line_start
						? 0 : part.new_line_end - part.new_line_start + 1;
					var remove_count = part.old_line_end < part.old_line_start
						? 0 : part.old_line_end - part.old_line_start + 1;
					while (new_i < part.new_line_start && new_i <= editor_lines.length) {
						display.add(editor_lines[new_i - 1]);
						this.diff_baseline.add(new_i);
						kinds.add(0);
						new_i++;
					}
					if (part.accepted != 0) {
						if (add_count == 0) {
							if (part.new_line_start > new_i) {
								new_i = part.new_line_start;
							}
							continue;
						}
						for (var ln = part.new_line_start;
							ln < part.new_line_start + add_count && ln <= editor_lines.length;
							ln++) {
							display.add(editor_lines[ln - 1]);
							this.diff_baseline.add(ln);
							kinds.add(0);
						}
						new_i = part.new_line_start + add_count;
						continue;
					}
					if (remove_count > 0 && part.hunk_remove != "") {
						this.diff_remove_at.add(part.new_line_start);
						this.diff_remove_n.add(remove_count);
						var removed = part.hunk_remove.split("\n");
						for (var r = 0; r < remove_count && r < removed.length; r++) {
							display.add(removed[r]);
							this.diff_baseline.add(0);
							kinds.add(2);
						}
					}
					if (add_count == 0) {
						if (part.new_line_start > new_i) {
							new_i = part.new_line_start;
						}
						continue;
					}
					for (var ln = part.new_line_start;
						ln < part.new_line_start + add_count && ln <= editor_lines.length;
						ln++) {
						display.add(editor_lines[ln - 1]);
						this.diff_baseline.add(ln);
						kinds.add(1);
					}
					new_i = part.new_line_start + add_count;
				}
				while (new_i <= editor_lines.length) {
					display.add(editor_lines[new_i - 1]);
					this.diff_baseline.add(new_i);
					kinds.add(0);
					new_i++;
				}
				this.diff_buffer = new GtkSource.Buffer(this.diff_tag_table);
				this.diff_buffer.set_text(string.joinv("\n", display.to_array()), -1);
				var add_tag = this.diff_tag_table.lookup("diff-add");
				var remove_tag = this.diff_tag_table.lookup("diff-remove");
				for (var i = 0; i < kinds.size; i++) {
					if (kinds.get(i) == 0) {
						continue;
					}
					Gtk.TextIter iter;
					this.diff_buffer.get_iter_at_line(out iter, i);
					var line_end = iter;
					if (!line_end.ends_line()) {
						line_end.forward_to_line_end();
					}
					if (!line_end.is_end()) {
						line_end.forward_char();
					}
					this.diff_buffer.apply_tag(
						kinds.get(i) == 1 ? add_tag : remove_tag, iter, line_end);
				}
				this.pre_diff_buffer = this.source_view.buffer as GtkSource.Buffer;
				this.source_view.set_buffer(this.diff_buffer);
				this.source_view.show_line_numbers = false;
				this.diff_active = true;
				this.scrolled_window.visible = true;
				this.review_bar.update_diff(parts, this.review_bar.file_index);
```

#### Replace with

The RPC error returns leave the editor as it was. A missing retval is an empty `parts` list, and the pump still runs.

```vala
				var parts = new Gee.ArrayList<OLLMfiles.FileDiffPart>();
				if (this.manager.review_files.file_map.has_key(file.path)) {
					OLLMrpc.Response response;
					try {
						response = yield this.manager.rpc.call(new OLLMrpc.Request() {
							method = "FileHistory.parts",
							args = OLLMrpc.args("x",
								this.manager.review_files.file_map.get(file.path).approve_id)
						});
					} catch (GLib.Error e) {
						GLib.warning("Failed to load diff parts for %s: %s", file.path, e.message);
						return;
					}
					if (this.current_file != file) {
						return;
					}
					if (response.error != null) {
						GLib.warning("Failed to load diff parts for %s: %s", file.path, response.error.message);
						return;
					}
					if (response.retval.type() != GLib.Type.INVALID) {
						parts = (Gee.ArrayList<OLLMfiles.FileDiffPart>) response.retval.get_object();
					}
				}
				if (this.current_file != file) {
					return;
				}
				if (this.diff_active) {
					this.clear_diff();
				}
				var proposal = this.change_view.proposal(file, parts);
				this.change_view.apply(proposal);
				(this.source_view.buffer as GtkSource.Buffer).set_modified(false);
				this.scrolled_window.visible = true;
				this.review_bar.update_diff(parts, this.review_bar.file_index);
```

### 5. `liboccoder/SourceView.vala` — `save_file`: plain editor text

**Why:** With no hunks, the user is typing in the editor buffer, and `sync_to_file` writes `file.buffer`. Copy first. A real hunk keeps the plain file as the bytes on disk.

**Where:** `save_file`, after `var file = this.current_file;` and before the `try` that calls `sync_to_file`.

**Depends on:** §1 and §4.

#### Add — in `save_file`, before `yield file.buffer.sync_to_file()`

`plain` stays true when `parts` is empty. That is a file that has not been painted as a diff.

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

### 6. `liboccoder/SourceView.vala` — `handle_file_deleted`: clear the editor

**Why:** The view is no longer `file.buffer`. Clearing the file buffer leaves the previous paint on screen.

**Where:** `handle_file_deleted`, after the `file.buffer.clear` block and before `this.source_view.editable = false`.

**Depends on:** §1.

#### Add — in `handle_file_deleted`, after the `file.buffer` clear

Empty `parts` so the next open of another file is a first fill.

```vala
				(this.source_view.buffer as GtkSource.Buffer).set_text("", -1);
				this.change_view.parts.clear();
				this.change_view.empty = true;
```

## Attempts / changelog

- ℹ️ 2026-10-28 — investigation and the class proposal live in the parent log.
- ✔️ 2026-10-29 — phase one compiled: `ChangeView`, client `compare` / `update_sum`, `unchanged` on both parts. `SourceView` was not changed.
- 🔷 2026-10-29 — this file is the render work. The parent log stays the class record.
- 💩 2026-10-30 — a `rebuild_parts` query for the oldest unreviewed backup. Withdrawn. The plans already return the hunks for `approve_id`.
- ✔️ 2026-10-30 — call sites stay. `proposal` receives that array. `apply` writes it.
- ✔️ 2026-10-30 — §1–§6 applied in `SourceView`. The editor stays on its own buffer. `show_pending_diff` calls `proposal` then `apply`.
- ✔️ 2026-10-30 — `ChangeView.update` renamed to `proposal`.
- 🚫 2026-10-30 — closed. Not checked in the app. Live edits are [`2026-10-30-live-diff-edit-sync.md`](../2026-10-30-live-diff-edit-sync.md).

## Next

- 🚫 Closed 2026-10-30 with the class log.
