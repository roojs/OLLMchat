# Sandbox edits reload the whole file and never paint the diff

**Status:** 🚫 CLOSED 2026-10-30. The class is in the tree. The source-view call is [`2026-10-29-CLOSED-change-view-render.md`](2026-10-29-CLOSED-change-view-render.md). Editing that paint is [`2026-10-30-CLOSED-live-diff-edit-sync.md`](2026-10-30-CLOSED-live-diff-edit-sync.md).

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

- 🔷 The change view manages the buffer.
  - 🔷 One constructor. The buffer argument is `GtkSource.Buffer?`. It has no default.
    - 🔷 The current change view is constructed with the editor buffer. `SourceView` holds it. It is created empty. Empty is the flag.
    - 🔷 The secondary change view is constructed with null.
  - 🚫 Flipping the two instances. The one with the buffer stays current.
  - ✔️ A `FileDiffPart` row today is one changed hunk. Add, remove, or replace. `hunk_remove` and `hunk_add` are the changed lines. The old and new line numbers are the span.
  - ✔️ The differ skips equal lines. A gap between one part's `new_line_end` and the next part's `new_line_start` is an unchanged run.
  - ✔️ `FileDiffPart.compare` tells two hunks apart on the daemon. `3` same lines and same text. `1` lines only. `2` text only. `0` neither. It does not edit a buffer.
  - 🔷 An unchanged run is a `FileDiffPart` with `unchanged` true. `hunk_add` is that run's file lines. `hunk_remove` stays empty. The old and new spans cover the run.
  - 🚫 The same text in `hunk_add` and `hunk_remove`.
- 🔷 A pump is `proposal`, then later `apply`. That includes the first fill and `event.project.invalidate_cache`.
  - 🔷 `open_file` is the only time the scroll is put back.
  - 🚫 `file.read` then `set_buffer`.
  - 🔷 `proposal` takes the file and the incoming hunks. It returns the proposal. It does not write the buffer.
    - 🔷 The secondary view is constructed with null. An empty incoming list still builds one.
    - 🔷 `parts` on that view is the whole file. Each gap between hunks is an unchanged `FileDiffPart`. Each incoming hunk is kept.
    - 🔷 A gap's lines are `string.joinv("\n", lines[start:end])` in `hunk_add` only. `end` is exclusive. `unchanged` is true. The gap and each kept hunk call `update_sum` so `compare` has a checksum.
    - 🚫 A loop over the file lines. The loop walks the hunks.
    - 🚫 A field for the secondary change view.
    - 🚫 Calling `apply` from `proposal`.
  - 🔷 `apply` is the call after `proposal`. The caller passes that return value to `apply`. `proposal` does not call it.
    - 🔷 An empty `parts` list writes the secondary view straight into the buffer with one `set_text`. That text is the file when every part is unchanged, and the file with the removed lines spliced in when a part is a hunk.
    - 🔷 A filled `parts` list is `apply_parts`. `apply` calls it and returns.
      - 🔷 The same piece is `FileDiffPart.compare`. `3` is the same lines and the same checksum: leave that stretch. `2` is the checksum only: leave that stretch. `1` is the lines only: replace that stretch. `0` is neither.
      - 🚫 A `switch` on that return. Each result is its own `if`, then `continue`. `if (!put) continue` so the insert is the rest of the iteration.
      - 🔷 A span ternary reads the aliased part. `end < start ? 0 : end - start + 1`. `parts.get` is not on the arm.
      - 🚫 A nested ternary, or a ternary arm that calls a method. That is the Vala codegen bug (`examples/oc-vala-ternary-bug.vala`). `compare`'s return stays `if`s.
      - 🔷 A piece only in the current change view: take it out.
      - 🔷 A piece only in the secondary change view: put it in.
      - 💩 On `0`, a later part whose `compare` is `2` or `3` is that piece. Both cursors have such a part: the nearer one is the insert or the delete. Neither does: that piece changed.
      - 🔷 Spans just written take `diff-add` and `diff-remove` on that buffer.
      - 🔷 The constructor that receives the editor buffer adds those two tags when the tag table does not already have them. Same colors as the source view.
      - 🔷 `ReviewBar.update_diff` redraws the hunk strip. It does not edit the buffer. `apply` does not call it.
- 🚫 A second `GtkSource.Buffer` built from the change view and swapped in with `set_buffer`. That is `show_pending_diff` (`display` and `kinds`, then `set_text`).
- 🚫 Applying the eight history rows in time order, and only when the buffer text still equals that step's backup. Eight saves are one `proposal` against what is approved.
- 🚫 Painting the newest history row (`approve_id`, backup 43027) as the whole pending diff.
- 🚫 Building as its own entry that takes the file contents and refuses the file. `proposal` takes the file and the part array.
- 🚫 A field initializer that constructs `new GtkSource.Buffer(null)`. The buffer is only the constructor argument.
- 🔷 The body of `apply` and `apply_parts` is in §3. Empty `parts` is one `set_text`. A filled list is `apply_parts`.
- 🔷 Phase one is that class, the `unchanged` flag, and the build entries. It is in the tree.
- ℹ️ The source-view call landed in [`2026-10-29-CLOSED-change-view-render.md`](2026-10-29-CLOSED-change-view-render.md). Closed with this log.

### 1. `libocfiles/FileDiffPart.vala` — `unchanged`

**Why:** An unchanged run is a `FileDiffPart`. The flag marks it. The file lines stay in `hunk_add` only. `compare` and `update_sum` live on the file-server part today. The editor holds this class, so the same two methods go here.

**Where:** `unchanged` after the `hunk_add` property. The methods after `decided_at`. The class overview stops saying `compare` is file-server only.

**Depends on:** none.

#### Add — after the `hunk_add` property

The flag is not a database column. A real hunk leaves it false.

```vala
		/**
		 * True for an unchanged run built in the editor.
		 * Not a database column. {@link hunk_remove} stays
		 * empty. {@link hunk_add} holds the file lines.
		 */
		public bool unchanged { get; set; default = false; }
```

#### Remove — class overview, the `compare` sentence

```vala
	 * {@link accepted} is 0 undecided, 1 accepted, -1 rejected.
	 * ''compare'' is on the file-server part. It takes another
	 * part.
```

#### Replace with

The editor calls `compare` on this type. The file server keeps the same return values.

```vala
	 * {@link accepted} is 0 undecided, 1 accepted, -1 rejected.
	 * {@link compare} takes another part. 0 neither. 1 lines
	 * only. 2 checksum only. 3 both. The file server matches.
```

#### Add — after `decided_at`

`update_sum` matches the file server. `compare` reads `checksum`, so `update_sum` has to run first. The return is `if`s. The file server still has the nested ternary.

```vala
		/**
		 * Set {@link checksum} from {@link hunk_remove} and
		 * {@link hunk_add}. SHA256 of the remove text, a NUL,
		 * then the add text.
		 */
		public void update_sum()
		{
			var sum = new GLib.Checksum(GLib.ChecksumType.SHA256);
			sum.update((uint8[]) (this.hunk_remove + "\0" + this.hunk_add).to_utf8(), -1);
			this.checksum = sum.get_string();
		}

		/**
		 * Compare this part to another file part.
		 *
		 * 0 neither. 1 line numbers only. 2 checksum only. 3 both.
		 *
		 * @param other the other hunk
		 * @return 0, 1, 2, or 3
		 */
		public int compare(FileDiffPart other)
		{
			var lines = this.old_line_start == other.old_line_start &&
				this.old_line_end == other.old_line_end &&
				this.new_line_start == other.new_line_start &&
				this.new_line_end == other.new_line_end;
			var hunks = this.checksum != "" && this.checksum == other.checksum;
			if (lines && hunks) {
				return 3;
			}
			if (lines) {
				return 1;
			}
			if (hunks) {
				return 2;
			}
			return 0;
		}
```

### 2. `ollmfilesd/FileDiffPart.vala` — `unchanged`

**Why:** The file-server part is the same wire type. A real hunk leaves the flag false.

**Where:** after the `hunk_add` property.

**Depends on:** none.

#### Add — after the `hunk_add` property

Same property as §1. No table change.

```vala
		/**
		 * True for an unchanged run built in the editor.
		 * Not a database column. {@link hunk_remove} stays
		 * empty. {@link hunk_add} holds the file lines.
		 */
		public bool unchanged { get; set; default = false; }
```

### 3. `liboccoder/ChangeView.vala` — new class

**Why:** The change view owns the editor buffer. `proposal` builds the secondary view's `parts`, unchanged runs included, and does not write the buffer. `apply` writes an empty `parts` list with one `set_text`. A filled list returns through `apply_parts`.

**Where:** new file.

**Depends on:** §1 and §2.

#### Add — new file `liboccoder/ChangeView.vala`

The class. `proposal` returns the proposal and does not call `apply`. `apply` writes an empty `parts` list. `apply_parts` writes a filled one.

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMcoder
{
	/**
	 * Owns one editor buffer and the parts last applied to it.
	 *
	 * Construct it with the editor buffer for the current view.
	 * {@link SourceView} holds that instance. {@link proposal} returns a
	 * second instance whose {@link parts} include unchanged runs.
	 * {@link apply} writes that proposal into this buffer. The two
	 * instances are not swapped.
	 *
	 * == Example ==
	 *
	 * === Empty part list ===
	 *
	 * {{{
	 * var view = new OLLMcoder.ChangeView(buffer);
	 * var hunks = new Gee.ArrayList<OLLMfiles.FileDiffPart>();
	 * var proposal = view.proposal(file, hunks);
	 * view.apply(proposal);
	 * }}}
	 */
	public class ChangeView : Object
	{
		/**
		 * Editor buffer from the constructor. Null on the
		 * secondary instance. Not allocated here.
		 */
		private GtkSource.Buffer? buffer;

		/**
		 * True when this instance holds no parts.
		 * A new instance starts empty. That is the flag.
		 */
		public bool empty = true;

		/**
		 * Whole file for this view. Unchanged runs and hunks.
		 */
		public Gee.ArrayList<OLLMfiles.FileDiffPart> parts {
			get; set; default = new Gee.ArrayList<OLLMfiles.FileDiffPart>();
		}

		/**
		 * Current or secondary change view.
		 *
		 * The secondary view passes null. The current view passes the
		 * editor buffer. That buffer receives ''diff-add'' and
		 * ''diff-remove'' when the tag table lacks them.
		 *
		 * @param buffer editor buffer, or null for the secondary view
		 */
		public ChangeView(GtkSource.Buffer? buffer)
		{
			this.buffer = buffer;
			if (this.buffer == null) {
				return;
			}
			if (this.buffer.tag_table.lookup("diff-add") != null) {
				return;
			}
			this.buffer.tag_table.add(new Gtk.TextTag("diff-add") {
				paragraph_background_rgba = Gdk.RGBA() {
					red = 0.75f,
					green = 0.95f,
					blue = 0.75f,
					alpha = 1.0f
				}
			});
			this.buffer.tag_table.add(new Gtk.TextTag("diff-remove") {
				paragraph_background_rgba = Gdk.RGBA() {
					red = 0.95f,
					green = 0.75f,
					blue = 0.75f,
					alpha = 1.0f
				},
				editable = false
			});
		}

		/**
		 * Build a proposal from the file and the incoming hunks.
		 * Does not call {@link apply}.
		 * Gaps between hunks become unchanged parts. An empty
		 * hunk list still builds those parts from the file.
		 *
		 * @param file file text for the unchanged runs
		 * @param parts incoming hunks, or an empty list
		 * @return the proposal
		 */
		public ChangeView proposal(OLLMfiles.File file, Gee.ArrayList<OLLMfiles.FileDiffPart> parts)
		{
			var next = new ChangeView(null);
			var lines = file.buffer.get_text().split("\n");
			var new_at = 1;
			var old_at = 1;
			for (var i = 0; i <= parts.size; i++) {
				var new_end = lines.length;
				var old_end = old_at + lines.length - new_at;
				if (i < parts.size) {
					var inc = parts.get(i);
					new_end = inc.new_line_start - 1;
					old_end = inc.old_line_start - 1;
				}
				if (new_end > lines.length) {
					new_end = lines.length;
				}
				if (new_at <= new_end) {
					var gap = new OLLMfiles.FileDiffPart() {
						new_line_start = new_at,
						new_line_end = new_end,
						old_line_start = old_at,
						old_line_end = old_end,
						hunk_add = string.joinv("\n", lines[new_at - 1:new_end]),
						unchanged = true
					};
					gap.update_sum();
					next.parts.add(gap);
					new_at = gap.new_line_end + 1;
					if (gap.old_line_end >= gap.old_line_start) {
						old_at = gap.old_line_end + 1;
					}
				}
				if (i == parts.size) {
					break;
				}
				var inc = parts.get(i);
				inc.update_sum();
				next.parts.add(inc);
				if (inc.new_line_end >= inc.new_line_start) {
					new_at = inc.new_line_end + 1;
				}
				if (inc.old_line_end >= inc.old_line_start) {
					old_at = inc.old_line_end + 1;
				}
			}
			next.empty = next.parts.size == 0;
			return next;
		}

		/**
		 * Write {@link next} into this buffer.
		 *
		 * A filled {@link parts} list calls {@link apply_parts} and
		 * returns. An empty list writes the secondary view with one
		 * ''set_text'', then paints green and red on the hunk spans.
		 * {@link proposal} does not call this. The caller redraws the
		 * strip with ''ReviewBar.update_diff''.
		 *
		 * @param next proposal from {@link proposal}
		 */
		public void apply(ChangeView next)
		{
			if (this.parts.size > 0) {
				this.apply_parts(next);
				return;
			}
			var add_tag = this.buffer.tag_table.lookup("diff-add");
			var remove_tag = this.buffer.tag_table.lookup("diff-remove");
			string[] blobs = {};
			for (var n = 0; n < next.parts.size; n++) {
				var part = next.parts.get(n);
				var new_n = part.new_line_end < part.new_line_start ? 0 : part.new_line_end - part.new_line_start + 1;
				var old_n = part.old_line_end < part.old_line_start ? 0 : part.old_line_end - part.old_line_start + 1;
				if (part.unchanged) {
					if (new_n > 0) {
						blobs += part.hunk_add;
					}
					continue;
				}
				if (old_n > 0) {
					blobs += part.hunk_remove;
				}
				if (new_n > 0) {
					blobs += part.hunk_add;
				}
			}
			this.buffer.set_text(string.joinv("\n", blobs), -1);
			var at = 0;
			for (var n = 0; n < next.parts.size; n++) {
				var part = next.parts.get(n);
				var new_n = part.new_line_end < part.new_line_start ? 0 : part.new_line_end - part.new_line_start + 1;
				var old_n = part.old_line_end < part.old_line_start ? 0 : part.old_line_end - part.old_line_start + 1;
				if (part.unchanged) {
					at += new_n;
					continue;
				}
				if (old_n > 0) {
					Gtk.TextIter tag_start;
					Gtk.TextIter tag_end;
					this.buffer.get_iter_at_line(out tag_start, at);
					if (!this.buffer.get_iter_at_line(out tag_end, at + old_n)) {
						this.buffer.get_end_iter(out tag_end);
					}
					this.buffer.apply_tag(remove_tag, tag_start, tag_end);
					at += old_n;
				}
				if (new_n > 0) {
					Gtk.TextIter tag_start;
					Gtk.TextIter tag_end;
					this.buffer.get_iter_at_line(out tag_start, at);
					if (!this.buffer.get_iter_at_line(out tag_end, at + new_n)) {
						this.buffer.get_end_iter(out tag_end);
					}
					this.buffer.apply_tag(add_tag, tag_start, tag_end);
					at += new_n;
				}
			}
			this.parts.clear();
			this.parts.add_all(next.parts);
			this.empty = this.parts.size == 0;
		}

		/**
		 * Write {@link next} by the differentials.
		 *
		 * {@link OLLMfiles.FileDiffPart.compare} 2 or 3 leaves the
		 * stretch. 1 replaces it. 0 takes out a piece only in this
		 * view or puts one in from {@link next}.
		 * {@link apply} calls this when {@link parts} is filled.
		 *
		 * @param next proposal from {@link proposal}
		 */
		private void apply_parts(ChangeView next)
		{
			var add_tag = this.buffer.tag_table.lookup("diff-add");
			var remove_tag = this.buffer.tag_table.lookup("diff-remove");
			var i = 0;
			var j = 0;
			var at = 0;
			while (i < this.parts.size || j < next.parts.size) {
				var put = i >= this.parts.size;
				var take = j >= next.parts.size;
				if (i < this.parts.size && j < next.parts.size) {
					var cur = this.parts.get(i);
					var inc = next.parts.get(j);
					var rel = cur.compare(inc);
					if (rel == 2 || rel == 3) {
						at += cur.new_line_end < cur.new_line_start ? 0 : cur.new_line_end - cur.new_line_start + 1;
						if (!cur.unchanged) {
							at += cur.old_line_end < cur.old_line_start ? 0 : cur.old_line_end - cur.old_line_start + 1;
						}
						i++;
						j++;
						continue;
					}
					if (rel == 1) {
						put = true;
						take = true;
					}
					if (rel == 0) {
						var later_next = j + 1;
						while (later_next < next.parts.size) {
							var ahead = cur.compare(next.parts.get(later_next));
							if (ahead == 2 || ahead == 3) {
								break;
							}
							later_next++;
						}
						var later_cur = i + 1;
						while (later_cur < this.parts.size) {
							var ahead = inc.compare(this.parts.get(later_cur));
							if (ahead == 2 || ahead == 3) {
								break;
							}
							later_cur++;
						}
						var found_next = later_next < next.parts.size;
						var found_cur = later_cur < this.parts.size;
						put = !found_cur || (found_next && later_next - j <= later_cur - i);
						take = !found_next || (found_cur && later_cur - i < later_next - j);
					}
				}
				if (take) {
					var cur = this.parts.get(i);
					var old_n = cur.old_line_end < cur.old_line_start ? 0 : cur.old_line_end - cur.old_line_start + 1;
					var new_n = cur.new_line_end < cur.new_line_start ? 0 : cur.new_line_end - cur.new_line_start + 1;
					var span = new_n;
					if (!cur.unchanged) {
						span = old_n + new_n;
					}
					if (span > 0) {
						Gtk.TextIter start_iter;
						if (this.buffer.get_iter_at_line(out start_iter, at)) {
							Gtk.TextIter end_iter;
							if (!this.buffer.get_iter_at_line(out end_iter, at + span)) {
								this.buffer.get_end_iter(out end_iter);
							}
							this.buffer.delete(ref start_iter, ref end_iter);
						}
					}
					i++;
				}
				if (!put) {
					continue;
				}
				var inc = next.parts.get(j);
				var old_n = inc.old_line_end < inc.old_line_start ? 0 : inc.old_line_end - inc.old_line_start + 1;
				var new_n = inc.new_line_end < inc.new_line_start ? 0 : inc.new_line_end - inc.new_line_start + 1;
				var text = inc.hunk_add;
				if (!inc.unchanged && inc.hunk_remove != "") {
					text = inc.hunk_add == "" ? inc.hunk_remove : inc.hunk_remove + "\n" + inc.hunk_add;
				}
				var span = new_n;
				if (!inc.unchanged) {
					span = old_n + new_n;
				}
				Gtk.TextIter at_iter;
				var at_end = !this.buffer.get_iter_at_line(out at_iter, at);
				if (at_end) {
					this.buffer.get_end_iter(out at_iter);
				}
				if (text == "" && span > 0) {
					var blanks = span;
					if (at_end) {
						blanks = span - 1;
					}
					text = string.nfill(blanks, '\n');
				}
				if (text != "" && !at_end && !text.has_suffix("\n")) {
					text = text + "\n";
				}
				if (text != "") {
					this.buffer.insert(ref at_iter, text, -1);
				}
				if (!inc.unchanged && old_n > 0) {
					Gtk.TextIter tag_start;
					Gtk.TextIter tag_end;
					this.buffer.get_iter_at_line(out tag_start, at);
					if (!this.buffer.get_iter_at_line(out tag_end, at + old_n)) {
						this.buffer.get_end_iter(out tag_end);
					}
					this.buffer.apply_tag(remove_tag, tag_start, tag_end);
				}
				if (!inc.unchanged && new_n > 0) {
					Gtk.TextIter tag_start;
					Gtk.TextIter tag_end;
					this.buffer.get_iter_at_line(out tag_start, at + old_n);
					if (!this.buffer.get_iter_at_line(out tag_end, at + old_n + new_n)) {
						this.buffer.get_end_iter(out tag_end);
					}
					this.buffer.apply_tag(add_tag, tag_start, tag_end);
				}
				at += span;
				j++;
			}
			this.parts.clear();
			this.parts.add_all(next.parts);
			this.empty = this.parts.size == 0;
		}
	}
}
```

### 4. `liboccoder/meson.build` — compile `ChangeView.vala`

**Why:** The new file has to be in the library.

**Where:** `occoder_src`, after `'GtkSourceFileBuffer.vala',`.

**Depends on:** §3.

#### Add — after `'GtkSourceFileBuffer.vala',`

List the new source before `SourceView.vala`.

```meson
  'ChangeView.vala',
```

### 5. `docs/meson.build` — valadoc input

**Why:** New Vala files are valadoc inputs.

**Where:** liboccoder sources, after `'../liboccoder/GtkSourceFileBuffer.vala',`.

**Depends on:** §3.

#### Add — after the `GtkSourceFileBuffer.vala` valadoc line

Same order as `liboccoder/meson.build`.

```meson
    '../liboccoder/ChangeView.vala',
```

### 6. `liboccoder/namespace.vala` — list `ChangeView`

**Why:** The namespace overview lists the editor types.

**Where:** UI Components list, after the `SourceView` bullet.

**Depends on:** §3.

#### Add — after the `SourceView` overview bullet

Name the type that owns the buffer.

```vala
 *  * ChangeView: owns the editor buffer and applies file updates
```

## Attempts / changelog

- ✔️ 2026-10-28 — read the 08:19–08:30 transcript, the eight history rows, and the empty `file_diff_part` table.
- 🚫 2026-10-28 — reloading the file and then painting `show_pending_diff` still replaces the whole view and restores the scroll. That is first-open behaviour.
- 🚫 2026-10-28 — `on_review_files_refresh` inserting the newest history row into the buffer on screen, including a second copy of the green tag. The buffer on screen is not always the file, and eight saves are one proposed change view.
- 🚫 2026-10-29 — `SourceView.update_diff` walking part lists, and applying each history row only when the buffer still matches that row's backup.
- 🚫 2026-10-29 — a flat sequence whose last step sets the current change view to the proposed one. Building makes one view's data from the file contents and that change view. Comparison alters the buffer from the two data objects.
- 🚫 2026-10-29 — dropping the current change view after the comparison. `SourceView` holds that value. The patch-set change view is the local, and it is not kept.
- 🚫 2026-10-29 — a comparison entry that takes two already-built change views. The current change view is constructed with the buffer, empty. `proposal` takes the file and the part array, builds the no-buffer change view, and `apply` writes it. An empty array goes straight into the buffer. A non-empty array goes by the differentials. The two instances are not flipped.
- 🚫 2026-10-29 — class proposal that left `apply` empty for a second phase.
- 🔷 2026-10-29 — `apply` is in the class proposal. Empty `parts` writes the secondary view with `set_text` and the green and red tags. A filled list leaves, replaces, takes out, and puts in.
- 🔷 2026-10-29 — piece match is `FileDiffPart.compare`. 2 or 3 leaves. 1 replaces. 0 looks ahead for a 2 or 3. `proposal` calls `update_sum` so the checksum is set. The editor part gains those two methods.
- 🚫 2026-10-29 — `switch` on the `compare` return inside the parts walk. The cases nest the take and the put.
- 🔷 2026-10-29 — `apply_parts` is the filled list. `apply` calls it when `parts.size > 0` and returns. Each `compare` result is an `if` then `continue`.
- 🔷 2026-10-29 — `part`, `cur`, and `inc` alias `parts.get` before a span ternary. The arm is `end < start ? 0 : end - start + 1`. `parts.get` stays off the arm.
- 🔷 2026-10-29 — `apply_parts` continues when `put` is false. The insert is the rest of the iteration.
- 🚫 2026-10-29 — `proposal` copying the incoming hunks with `add_all` and calling `apply`. `proposal` builds `parts`, unchanged runs included, and returns that view.
- 🚫 2026-10-29 — a loop that copies file lines one by one. The gap text is `lines[start:end]` passed to `string.joinv`. The loop walks the hunks.
- 🚫 2026-10-29 — assigning `FileDiffPart` fields after `new`. The unchanged run uses `new OLLMfiles.FileDiffPart() { … }`.
- 🚫 2026-10-29 — the same gap text in `hunk_add` and `hunk_remove`. `unchanged` is the flag. The lines sit in `hunk_add` only.
- 🔷 2026-10-29 — phase one is the approved class and the build. The render path is a separate log: [`2026-10-29-CLOSED-change-view-render.md`](2026-10-29-CLOSED-change-view-render.md).
- 🚫 2026-10-30 — closed. The call is in that log. Live edits are [`2026-10-30-CLOSED-live-diff-edit-sync.md`](2026-10-30-CLOSED-live-diff-edit-sync.md).
- ✔️ 2026-10-29 — phase one landed: client `compare` and `update_sum`, `unchanged` on both parts, `liboccoder/ChangeView.vala`, meson, and the namespace list. `SourceView` still reloads the file.
- ✔️ 2026-10-30 — `update` renamed to `proposal`. `apply` writes that proposal.
- ✔️ 2026-10-29 — the delete checks `span > 0`, then calls `get_iter_at_line` on its own. Vala does not treat an `out` argument on the right of `&&` as assigned.
