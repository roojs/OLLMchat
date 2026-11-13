# Review after a change treats a missing file as editable, and deciding a hunk aborts

**Status:** ✅ 2026-11-13. User archived it.

## Problem

- 🔷 After the agent changes files, the editor footer shows `File 1 of 3`.
- 🔷 That button has to open a popover listing each changed file and the action (added, deleted, modified).
- 🔷 Opening a file that was deleted shows a blank editable buffer.
  - 🔷 A deleted file that had content shows that content in red, the same removed-line presentation as a diff, and a mask that says the file was deleted. Editing stays off.
  - 🔷 A deleted file that was empty does not show a blank buffer. The mask says the file was deleted.
- 🔷 The previous and next buttons say "Previous pending file" and "Next pending file" on hover. Hover shows the file name that button opens.
- 🔷 Deciding a hunk (the user remembers a reject) aborted `ollmchat`.

## Evidence

- ℹ️ Session after the closed create-and-notify log. Client `~/.cache/ollmchat/ollmchat.debug.log`, daemon `~/.cache/ollmchat/ollmfilesd.debug.log`, `~/.local/share/ollmchat/files.sqlite`. Abort at 09:03:35, pid `1806105`, signal 6.
- ✔️ Three pending files (`filebase.is_need_approval = 1`):
  - ✔️ `tests/editing/Hello world` — newest history `43132` `change_type=deleted`, `delete_id=43132`. Path is not on disk.
  - ✔️ `tests/editing/Hello world.txt` — history `43131` `change_type=added`, `delete_id=0`. Path is not on disk. `tests/editing/` is gone.
  - ✔️ `tests/um editing uh/hello world.txt` — still on disk. Histories `43134` added and `43135`–`43138` modified. `43138` is `reviewed=1` after the abort.
- ✔️ Opening the missing added file does not take the deleted path. `File.read` id `67` (09:02:37), `77` (09:02:45), and `107` (09:03:06) return `No such file or directory` for `tests/editing/Hello world.txt`. `SourceView.vala:568` warns, then logs `loaded=false chars=0` and continues. `delete_id` is `0`, so `handle_file_deleted` does not run, and the desktop branch sets `editable = true`.
- ✔️ `handle_file_deleted` clears the buffer and sets `editable = false`. The "file deleted" indicator is a comment. No placeholder text is set.
- ✔️ Diff for the soft-deleted path fails. `FileHistory.parts` id `52`, `62`, `89`, `100` reply `file not found` for `tests/editing/Hello world`. `FileHistory.parts` looks the path up in `project_files.child_map` and returns that error when the lookup is null. Daemon then hits `mtime_on_disk: File does not exist` and `type id '0' is invalid` on the missing `.txt` path (09:02:37, 09:02:45, 09:03:06).
- ✔️ The file button builds a popover and then refuses to show it. `sync_pending` fills the popover with basename buttons. The click and the hover both return when `file_labels.length < 1`. Live `ReviewBar` is constructed with an empty `file_labels`, and `sync_pending` never writes that array. `FileWithHistory.display_approval_text` already has added / deleted / modified wording. The rows use `path_basename` only.
- ✔️ The abort is `gee_array_list_real_set` asserting `index >= 0`, called from `oll_mcoder_diff_review_bar_send_part_co`. Two `FileDiffPart.apply` calls overlap: client id `126` at 09:03:35.076, reply 09:03:35.081, id `127` at 09:03:35.081, reply 09:03:35.090. The only hunk row that changed is `file_diff_part.id=4` (`file_history_id=43138`, `accepted=1`). That is an accept. The log does not record the action argument, so a reject click is not what was stored.
- ✔️ `send_part` reads `this.active` before the yield, then after the reply calls `this.parts.set(this.active, …)`. `next()` sets `this.active` from `pending_after`, which returns `-1` when no hunk is still pending. A second `send_part` still in flight then sets index `-1` and libgee aborts. The accept and reject buttons stay sensitive across the yield, so a second click sends the second apply.
- ℹ️ Same window, not the abort: `markdown_gtk_render_tool_output_output: assertion 'self != NULL'` and a run of `oll_mtools_edit_mode_stream_process_chunk: assertion 'self != NULL'` from 09:02:20. The process kept running until the review-bar abort.

## Root cause

- ✔️ A missing file with `delete_id == 0` is a failed `File.read`. The open path logs the failure, leaves an empty buffer, and turns editing on. `handle_file_deleted` runs only for `delete_id > 0`, clears that buffer, and never says the file is deleted.
- ✔️ The red removed lines never get built for a soft-deleted path. `FileHistory.parts` returns `file not found` when the path is not in `project_files.child_map` (`tests/editing/Hello world`). A path that is still indexed but gone from disk (`tests/editing/Hello world.txt`) calls `mtime_on_disk`, which logs the critical and returns 0. The next three daemon lines on that call are `type id '0' is invalid`. `Differ` already turns backup text against an empty current file into one remove patch (`lines2.length == 0`).
- ✔️ An added file has no backup. `tests/editing/Hello world.txt` is that case, and the bytes are gone. There is nothing to paint red. The mask is the whole view.
- ✔️ `File 1 of 3` does not open its list because the click is gated on constructor `file_labels`, which the live queue does not set. The rows that would have been shown are basenames, without the change type.
- ✔️ Previous and next keep the constructor tooltips. Nothing writes the adjacent file name.
- ✔️ Two overlapping `send_part` calls share `this.active`. The first completion moves that index to `-1`. The second completion writes the parts list at that index and aborts.

## Not this fix

- ℹ️ `markdown_gtk_render_tool_output_output` and `oll_mtools_edit_mode_stream_process_chunk` `self != NULL` in the same session. The process kept running. Not the abort.
- ℹ️ `instance has no handler with id '10618'` once, on the open of `tests/editing/Hello world`. Not traced to a line this fix has to change. Not the abort.
- ℹ️ Deciding a hunk still calls `FileDiffPart.apply`, which writes the project file. That write stays. This fix stops the second call from aborting.

## Proposed fix

- 🔷 A file that is not on disk, or whose `delete_id > 0`, opens as deleted. Editing stays off.
  - 🔷 `FileHistory.parts` builds that file as backup text against an empty current file. `Differ` already emits one remove patch for that. `show_pending_diff` paints it with `diff-remove`.
  - 🔷 A mask on the editor overlay says "This file was deleted".
  - 🔷 No removed text (added file, backup empty, bytes gone): the editor stays hidden. The mask is the whole view.
- 🔷 `File N of M` click opens the popover. Each row is the action, then the file name.
- 🔷 Previous and next hover show the file name that click opens.
- 🔷 `send_part` keeps the hunk index from before the yield, and a second click does not send another `FileDiffPart.apply` until that call has finished. `next()` cannot make the in-flight call use `-1`.

### `ollmfilesd/FileHistory.vala` — `parts`

**Why:** a soft-deleted path is not in the project map, so this returns `file not found` and the editor never receives the remove patch. A path that is still indexed but missing on disk calls `mtime_on_disk`.

**Where:** the `file == null` reply and the `mtime_on_disk` cache test.

#### Remove

```vala
			var file = this.rpc_manager.get_file_from_active_project(
				histories.get(0).path);
			if (file == null) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error.INTERNAL_ERROR("file not found")
				});
				return;
			}
			var stamp = file.mtime_on_disk();
			if (this.live.has_key((int) id) && this.live_stamp.has_key((int) id) &&
				this.live_stamp.get((int) id) == (int) stamp) {
```

#### Replace with

```vala
			var file = this.rpc_manager.get_file_from_active_project(
				histories.get(0).path);
			if (file != null && GLib.FileUtils.test(file.path, GLib.FileTest.EXISTS)) {
				var stamp = file.mtime_on_disk();
				if (this.live.has_key((int) id) && this.live_stamp.has_key((int) id) &&
					this.live_stamp.get((int) id) == (int) stamp) {
```

#### Add

One closing brace, after the cached reply's existing `return` and its brace, before `Gee.ArrayList<FileDiffPart> rows`. That closes `if (file != null && … EXISTS)`. `rebuild_parts` stays outside it.

```vala
			}
```

### `ollmfilesd/FileHistory.vala` — `rebuild_parts`

**Why:** the current text of a file that is not on disk is empty. Backup against that empty string is the remove patch. `mtime_on_disk` is not called for a missing file.

**Where:** from `var file = this.rpc_manager.get_file_from_active_project(history.path)` through `var stamp = file.mtime_on_disk()`.

#### Remove

```vala
			var file = this.rpc_manager.get_file_from_active_project(history.path);
			if (file == null) {
				throw new GLib.IOError.FAILED("file not found");
			}
			if (file.buffer == null) {
				file.manager.buffer_provider.create_buffer(file);
			}
			var project = file.buffer.get_text();
			var stamp = file.mtime_on_disk();
```

#### Replace with

```vala
			var project = "";
			var stamp = (int64) 0;
			var file = this.rpc_manager.get_file_from_active_project(history.path);
			if (file != null && GLib.FileUtils.test(file.path, GLib.FileTest.EXISTS)) {
				if (file.buffer == null) {
					file.manager.buffer_provider.create_buffer(file);
				}
				project = file.buffer.get_text();
				stamp = file.mtime_on_disk();
			}
```

### `resources/style.css` — deleted mask

**Why:** the mask sits on the editor overlay. The red text stays visible under it. An empty delete uses the same label, centered, with the editor hidden.

**Where:** after `.oc-diff-review-overlay`.

#### Add

```css
.oc-file-deleted-mask {
  margin: 12px;
  padding: 8px 16px;
  border-radius: 6px;
  background-color: alpha(@window_bg_color, 0.92);
  color: @error_color;
}
```

### `liboccoder/SourceView.vala` — mask

**Why:** the overlay exists. It has no deleted label.

**Where:** the field list, next to `scrolled_window`. The overlay construction, on the line after `add_overlay(this.review_bar.review_overlay)`.

#### Add

```vala
			private Gtk.Label deleted_banner;
```

#### Add

```vala
				this.deleted_banner = new Gtk.Label("This file was deleted") {
					visible = false,
					halign = Gtk.Align.CENTER,
					valign = Gtk.Align.CENTER,
					css_classes = { "oc-file-deleted-mask" },
				};
				editor_overlay.add_overlay(this.deleted_banner);
```

### `liboccoder/SourceView.vala` — phone long-press

**Why:** a missing file can have `delete_id == 0`. The long-press turns editing on unless the mask is up.

**Where:** both `phone_hold` guards.

#### Remove

```vala
					if (this.source_view.editable || this.diff_active) {
						this.phone_hold.set_state(Gtk.EventSequenceState.DENIED);
						return;
					}
					if (this.current_file != null && this.current_file.delete_id > 0) {
						this.phone_hold.set_state(Gtk.EventSequenceState.DENIED);
					}
```

#### Replace with

```vala
					if (this.source_view.editable || this.diff_active ||
						this.deleted_banner.visible) {
						this.phone_hold.set_state(Gtk.EventSequenceState.DENIED);
						return;
					}
					if (this.current_file != null && this.current_file.delete_id > 0) {
						this.phone_hold.set_state(Gtk.EventSequenceState.DENIED);
					}
```

#### Remove

```vala
					if (this.source_view.editable || this.diff_active) {
						return;
					}
					if (this.current_file != null && this.current_file.delete_id > 0) {
						return;
					}
```

#### Replace with

```vala
					if (this.source_view.editable || this.diff_active ||
						this.deleted_banner.visible) {
						return;
					}
					if (this.current_file != null && this.current_file.delete_id > 0) {
						return;
					}
```

### `liboccoder/SourceView.vala` — `open_file`

**Why:** a failed read currently falls through into the editable branch. A `delete_id` hit calls `handle_file_deleted` and does not paint the remove patch.

**Where:** the `file.read()` catch, the `delete_id` notify, and the `delete_id > 0` branch.

#### Remove

```vala
				if (!file.buffer.is_loaded) {
					try {
						yield file.read();
					} catch (Error e) {
						GLib.warning("Failed to read file %s: %s", file.path, e.message);
						gtk_buffer.text = "";
					}
```

#### Replace with

```vala
				var missing = false;
				if (!file.buffer.is_loaded) {
					try {
						yield file.read();
					} catch (Error e) {
						GLib.warning("Failed to read file %s: %s", file.path, e.message);
						gtk_buffer.text = "";
						missing = true;
					}
```

#### Remove

```vala
				this.delete_id_handler_id = file.notify["delete-id"].connect(() => {
					if (file.delete_id > 0) {
						this.handle_file_deleted(file);
					}
				});
			
				this.scrolled_window.visible = true;
			
				// Check if file is already deleted
				if (file.delete_id > 0) {
					this.handle_file_deleted(file);
				} else {
					// Remove deleted CSS class if it was set
					this.source_view.remove_css_class("file-deleted");
```

#### Replace with

```vala
				this.delete_id_handler_id = file.notify["delete-id"].connect(() => {
					if (file.delete_id > 0) {
						this.handle_file_deleted(file);
						this.show_pending_diff.begin(file);
					}
				});

				if (missing || file.delete_id > 0) {
					this.handle_file_deleted(file);
					yield this.show_pending_diff(file);
				}
				if (!missing && file.delete_id == 0) {
					this.deleted_banner.visible = false;
					this.scrolled_window.visible = true;
					this.source_view.remove_css_class("file-deleted");
```

The rest of the old `else` body stays, including `yield this.show_pending_diff(file)`, and its closing brace stays. The `else` keyword is gone.

### `liboccoder/SourceView.vala` — `handle_file_deleted`

**Why:** the async buffer clear races the diff paint. The method has to raise the mask and hide the editor until `show_pending_diff` has text to show.

#### Remove

```vala
			private void handle_file_deleted(OLLMfiles.File file)
			{
				// Clear buffer contents
				if (file.buffer != null) {
					file.buffer.clear.begin((obj, res) => {
						try {
							file.buffer.clear.end(res);
						} catch (Error e) {
							GLib.warning("Failed to clear buffer for deleted file %s: %s", file.path, e.message);
						}
					});
				}
				(this.source_view.buffer as GtkSource.Buffer).set_text("", -1);
				this.change_view.parts.clear();
				this.change_view.empty = true;
			
				// Show "file deleted" indicator in placeholder
			
				// Disable editing
				this.source_view.editable = false;
			
				// Disable save button
				this.save_button.sensitive = false;
			
				// Add CSS class to indicate deleted state (for potential styling)
				this.source_view.add_css_class("file-deleted");
			
				// Note: Future enhancement - when sourceview can handle diffs, show the original file
				// content as red deleted (like a diff view showing deleted lines)
				// Can access deletion info via: file.delete_id -> FileHistory record
			}
```

#### Replace with

```vala
			private void handle_file_deleted(OLLMfiles.File file)
			{
				(this.source_view.buffer as GtkSource.Buffer).set_text("", -1);
				this.change_view.parts.clear();
				this.change_view.empty = true;
				this.source_view.editable = false;
				this.save_button.sensitive = false;
				this.source_view.add_css_class("file-deleted");
				this.scrolled_window.visible = false;
				this.deleted_banner.label = "This file was deleted";
				this.deleted_banner.valign = Gtk.Align.CENTER;
				this.deleted_banner.visible = true;
			}
```

### `liboccoder/SourceView.vala` — `show_pending_diff`

**Why:** a remove patch fills the buffer after the mask has hidden the editor. Empty text leaves the mask as the whole view.

**Where:** the last lines of `show_pending_diff`, after `update_diff`.

#### Remove

```vala
				this.scrolled_window.visible = true;
				this.review_bar.update_diff(parts, this.review_bar.file_index);
			}
```

#### Replace with

```vala
				this.scrolled_window.visible = true;
				this.review_bar.update_diff(parts, this.review_bar.file_index);
				if (!this.deleted_banner.visible) {
					return;
				}
				var shown = (this.source_view.buffer as GtkSource.Buffer).text != "";
				this.scrolled_window.visible = shown;
				this.deleted_banner.valign = shown ? Gtk.Align.START : Gtk.Align.CENTER;
			}
```

### `liboccoder/Diff/ReviewBar.vala` — file button

**Why:** `sync_pending` already puts a child in the popover. The click returns because `file_labels` is empty. The row text is only the basename.

**Where:** the click guard, the hover guard, and the row button in `sync_pending`.

#### Remove

```vala
			this.file_nav_btn.clicked.connect(() => {
				if (this.file_count < 2 || this.file_labels.length < 1) {
					return;
				}
```

#### Replace with

```vala
			this.file_nav_btn.clicked.connect(() => {
				if (this.file_count < 2) {
					return;
				}
```

#### Remove

```vala
			file_anchor_motion.enter.connect(() => {
				if (this.file_count < 2 || this.file_labels.length < 1) {
					return;
				}
```

#### Replace with

```vala
			file_anchor_motion.enter.connect(() => {
				if (this.file_count < 2) {
					return;
				}
```

#### Remove

```vala
				var row_btn = new Gtk.Button() {
					label = this.queue.get(fi).path_basename,
					tooltip_text = rel,
					has_frame = false,
				};
```

#### Replace with

```vala
				var row_label = this.queue.get(fi).path_basename;
				if (this.queue.get(fi).last_change_type != "") {
					row_label = "%s — %s".printf(
						this.queue.get(fi).last_change_type,
						row_label);
				}
				var row_btn = new Gtk.Button() {
					label = row_label,
					tooltip_text = rel,
					has_frame = false,
				};
```

`last_change_type` is the history action (`added`, `deleted`, `modified`). A file removed from disk with no `deleted` row still says `added`. The editor mask is what says it was deleted.

### `liboccoder/Diff/ReviewBar.vala` — previous and next hover

**Why:** the tooltips are fixed strings. Hover is the name of the file that button opens. The live names come from the queue. The mock window's names are `file_labels`.

**Where:** drop the fixed strings. Set the names after `file_nav.visible` in the constructor, at the end of `sync_pending` once `file_index` is final, and after every later `file_index` write (previous click, next click, menu pick, popover row).

#### Remove

```vala
			this.file_prev = new Gtk.Button() {
				icon_name = "go-previous-symbolic",
				tooltip_text = "Previous pending file",
			};
```

#### Replace with

```vala
			this.file_prev = new Gtk.Button() {
				icon_name = "go-previous-symbolic",
			};
```

#### Remove

```vala
			this.file_next = new Gtk.Button() {
				icon_name = "go-next-symbolic",
				tooltip_text = "Next pending file",
			};
```

#### Replace with

```vala
			this.file_next = new Gtk.Button() {
				icon_name = "go-next-symbolic",
			};
```

#### Add

After `this.file_nav.visible = this.file_count > 1` in the constructor.

```vala
			if (this.file_labels.length > 1) {
				this.file_prev.tooltip_text = this.file_labels[
					(this.file_index - 1 + this.file_count) % this.file_count];
				this.file_next.tooltip_text = this.file_labels[
					(this.file_index + 1) % this.file_count];
			}
```

#### Add

In `sync_pending`, after the `if (this.file_count < 1) return` block, before `var file_list`.

```vala
			if (this.file_count > 1) {
				this.file_prev.tooltip_text = this.queue.get(
					(this.file_index - 1 + this.file_count) % this.file_count).path_basename;
				this.file_next.tooltip_text = this.queue.get(
					(this.file_index + 1) % this.file_count).path_basename;
			}
```

#### Add

Inside each `file_index` write in the previous click, the next click, the menu pick, and the popover row, after the label update and before `file_index_changed`.

```vala
					if (this.queue.size > 1) {
						this.file_prev.tooltip_text = this.queue.get(
							(this.file_index - 1 + this.file_count) % this.file_count).path_basename;
						this.file_next.tooltip_text = this.queue.get(
							(this.file_index + 1) % this.file_count).path_basename;
					}
					if (this.queue.size < 2 && this.file_labels.length > 1) {
						this.file_prev.tooltip_text = this.file_labels[
							(this.file_index - 1 + this.file_count) % this.file_count];
						this.file_next.tooltip_text = this.file_labels[
							(this.file_index + 1) % this.file_count];
					}
```

### `liboccoder/Diff/ReviewBar.vala` — `send_part`

**Why:** two calls share `this.active`. The first `next()` sets it to `-1` when no hunk is still pending. The second `parts.set` aborts in libgee on `index >= 0`.

**Where:** a field next to `active`, and the whole of `send_part`. The flag stays set through `next()` and `show_pending_diff`. The hunk index saved before the yield is the one written after the reply.

#### Add

```vala
		private bool part_sending = false;
```

#### Remove

```vala
		private async void send_part(int action)
		{
			if (this.active < 0 || this.active >= this.parts.size) {
				return;
			}
			if (action != 0 && this.parts.get(this.active).accepted != 0) {
				return;
			}
			if (action == 0 && this.parts.get(this.active).accepted == 0) {
				return;
			}
			var before = this.parts.get(this.active);
			var file = this.source_view.current_file;
			OLLMrpc.Response response;
			try {
				response = yield this.source_view.manager.rpc.call(new OLLMrpc.Request() {
					method = "FileDiffPart.apply",
					args = OLLMrpc.args("xi", before.id, action)
				});
			} catch (GLib.Error e) {
				GLib.warning("Failed to apply diff item: %s", e.message);
				return;
			}
			if (response.error != null) {
				GLib.warning("Failed to apply diff item: %s", response.error.message);
				return;
			}
			this.parts.set(this.active,
				(OLLMfiles.FileDiffPart) response.retval.get_object());
			switch (action) {
				case 1:
					this.hunks.get(this.active).decision = HunkDecision.ACCEPTED;
					break;

				case -1:
					this.hunks.get(this.active).decision = HunkDecision.REJECTED;
					break;

				default:
					this.hunks.get(this.active).decision = HunkDecision.PENDING;
					break;
			}
```

#### Replace with

```vala
		private async void send_part(int action)
		{
			if (this.part_sending) {
				return;
			}
			if (this.active < 0 || this.active >= this.parts.size) {
				return;
			}
			if (action != 0 && this.parts.get(this.active).accepted != 0) {
				return;
			}
			if (action == 0 && this.parts.get(this.active).accepted == 0) {
				return;
			}
			var part_index = this.active;
			var before = this.parts.get(part_index);
			var file = this.source_view.current_file;
			this.part_sending = true;
			OLLMrpc.Response response;
			try {
				response = yield this.source_view.manager.rpc.call(new OLLMrpc.Request() {
					method = "FileDiffPart.apply",
					args = OLLMrpc.args("xi", before.id, action)
				});
			} catch (GLib.Error e) {
				this.part_sending = false;
				GLib.warning("Failed to apply diff item: %s", e.message);
				return;
			}
			if (response.error != null) {
				this.part_sending = false;
				GLib.warning("Failed to apply diff item: %s", response.error.message);
				return;
			}
			if (part_index >= this.parts.size || part_index >= this.hunks.size) {
				this.part_sending = false;
				return;
			}
			this.parts.set(part_index,
				(OLLMfiles.FileDiffPart) response.retval.get_object());
			switch (action) {
				case 1:
					this.hunks.get(part_index).decision = HunkDecision.ACCEPTED;
					break;

				case -1:
					this.hunks.get(part_index).decision = HunkDecision.REJECTED;
					break;

				default:
					this.hunks.get(part_index).decision = HunkDecision.PENDING;
					break;
			}
```

#### Remove

The buffer edit and `next()` above this stay.

```vala
			if (file != null) {
				this.source_view.show_pending_diff.begin(file);
			}
		}
```

#### Replace with

`part_sending` stays set through the repaint. The button handler already calls `send_part.begin`, so this yield does not block the UI thread.

```vala
			if (file != null) {
				yield this.source_view.show_pending_diff(file);
			}
			this.part_sending = false;
		}
```

## Attempts / changelog

- ℹ️ 2026-11-12: opened from the session after the create-and-notify fix. User closed that log.
- ✔️ 2026-11-12: client log, daemon log, coredump stack, and `files.sqlite` read. No product code changed.
- 🔷 2026-11-12: deleted view is two cases. Content stays, in red, under a deleted mask. An empty delete is the mask only. Previous and next hover show the file name that button opens.
- ✔️ 2026-11-12: proposal completed. The missing piece was `FileHistory.parts`: a deleted path never produced the remove patch, so the editor had nothing red to show. No product code changed.
- ✔️ 2026-11-13: proposal applied. `FileHistory.parts` and `rebuild_parts` skip a missing path and diff backup against empty text. The editor mask and open path, the file popover, previous and next names, and `send_part` are in. `liboccoder`, `ollmfilesd`, and `libollmchat` compiled.
- ✅ 2026-11-13: user archived the log.

## Next

- ✔️ Closed.
