# Opening a file jumps to a pending change, and the change map misses its target

**Status:** ⏳ open — behavior from the 2026-11-16 session; fix not applied

**Pointer:** `docs/bug-fix-process.md` · [`2026-11-14-approve-deleted-advance.md`](2026-11-14-approve-deleted-advance.md)

## Problem

- 🔷 Open a file that is not in the review queue (README, just now). The editor should stay on that file. The review bar may show that other files still have pending changes.
- 🔷 Actual: as soon as the pending queue loads, the editor replaces README with a changed file.
- 🔷 The editor switches to a changed file only when a new change notification arrives (the chat write / `event.project.invalidate_cache`). Discovering files that were already pending does not switch.
- 🔷 Clicking a band in the footer change map scrolls the source view so the top of that change sits in the middle of the screen. The top is the first line of the pair (removed lines, then added lines) or the single add or remove. A change at the top of the document stays at the top when it cannot reach the middle. A change taller than the screen still puts its top line in the middle, so the rest can be scrolled through.
- 🔷 Actual: clicking the second band does not bring that change into view. The view moves to the wrong place.
- 🔷 Each band shows its line number as a tooltip.
- 🔷 Band width may grow with the change, up to twice the one-line width (the map square, `map_height`). Anything larger is drawn at that cap. A long change does not become a wide bar.

## Evidence

- ✔️ `SourceView.open_file` sets `current_file`, then `yield this.manager.review_files.refresh()` (`liboccoder/SourceView.vala:596` and `:624`).
- ✔️ `review_files.refreshed` (`liboccoder/SourceView.vala:190-224`) calls `sync_pending`, then:
  - queue empty and a file is open → `close_file()`
  - open file is in `file_map` → `show_pending_diff` and return
  - otherwise → `open_file` on `queue.get(0)`
- ✔️ README is not a pending path, so that handler opens the first pending path. The same handler runs for every refresh, including the one `open_file` just started. It was added so finishing a review advances or closes the editor ([`2026-11-14-approve-deleted-advance.md`](2026-11-14-approve-deleted-advance.md)).
- ✔️ `event.project.invalidate_cache` (`liboccoder/SourceView.vala:154-178`) only refreshes the queue and reloads the file already open. It does not open the file that just changed. The daemon sends that notification when a file is written (`ollmfilesd/File.vala:468` and `:801`).
- ✔️ A band click calls `navigate_to_line(hunk.scroll_line)` (`liboccoder/Diff/ReviewBar.vala:1418`). `HunkBand` sets `scroll_line` to `new_line_start - 1` for an add or replace, and to `old_line_start - 1` for a remove (`liboccoder/Diff/ReviewBar.vala:57-70`). Those are file line numbers, not buffer lines.
- ✔️ Pending review is painted by `ChangeView`, which inserts each hunk's removed lines before its added lines (`liboccoder/ChangeView.vala:207-242`). `show_pending_diff` clears `diff_active` (`liboccoder/SourceView.vala:837-841`). `navigate_to_line` adds removed-line offsets only when `diff_active` is true (`liboccoder/SourceView.vala:862-873`), so a later hunk is short by every removed line of the hunks above it. The second band therefore aims at unchanged text.
- ✔️ `navigate_to_line` calls `scroll_to_iter(iter, 0.0, false, 0.0, 0.5)` (`liboccoder/SourceView.vala:879`). `use_align` is false, so the `0.5` vertical align is ignored. GTK scrolls the minimum that brings the iter on screen.
- ✔️ `on_width` sizes a band as `line_count` squares when the row fits, as a share of the row proportional to `line_count / hunk_line_sum` when it does not, or as `line_count * half_sq` in scroll mode (`liboccoder/Diff/ReviewBar.vala:1201-1235`). One square is `map_height` (28). A long hunk becomes most of the strip.
- ℹ️ The map is one `Gtk.DrawingArea` (`map_area`). It has click and drag controllers (`liboccoder/Diff/ReviewBar.vala:501-530`) and no motion handler, so a band has no tooltip.
- ℹ️ Clicking the "N changes pending review" label still calls `file_index_changed(0)` (`liboccoder/Diff/ReviewBar.vala:537-544`). That is a click. This bug is the refresh that switches with no click.

## Root cause

- ✔️ `refreshed` treats "the open file is not a pending file" as "open the first pending file", and treats "the queue is empty" as "close the open file". Both run when the user has just opened some other file.
- ✔️ The map scrolls to a new-file or old-file line number inside a buffer that also contains the red removed lines, and it does not align that line to the middle.
- ✔️ Band width is linear in `line_count` with no cap.

## Proposed fix

- 🔷 A refresh updates the review bar and reloads the diff when the open file is still pending. It does not open another file, and it does not close the editor, unless one of the two cases below matches.
- 🔷 After the user finishes the file they are reviewing (that path was pending and this refresh dropped it): open the next pending file, or `close_file` when the queue is empty. That is the check still owed by [`2026-11-14-approve-deleted-advance.md`](2026-11-14-approve-deleted-advance.md).
- 🔷 On `event.project.invalidate_cache`, after that refresh, if a path is pending now and was not pending before, open the new one (`approve_id` highest when several appear). The file already on screen reloads in place.
- 🔷 A band click, and the map's previous/next buttons, scroll so the top buffer line of that hunk is in the middle (`scroll_to_iter` with `use_align` true and `yalign` 0.5). GTK keeps a line near the start of the buffer at the top.
- 🔷 The top buffer line is `new_line_start - 1` plus the removed-line counts of earlier hunks that are still pending (`accepted == 0`). Decided hunks are drawn as plain new-file lines, so their removed lines are not added. A remove-only hunk uses the same `new_line_start` anchor, which is where the red lines are inserted.
- 💩 `update_diff` also calls `navigate_to_line` on every paint (`liboccoder/Diff/ReviewBar.vala:1169-1170`). A same-file reload that keeps the same active hunk should not scroll. Scroll when the file changes or the active hunk changes.
- 🔷 Hovering a band sets `map_area.tooltip_text` to `Line N` or `Lines N–M` from `line_start` and `line_end`.
- 🔷 Each band is `min(line_count, 2)` squares wide (`map_height`, doubled at most). Scroll mode uses that same cap. It does not go back to `line_count * half_sq`.

### 1. `liboccoder/SourceView.vala` — refresh must not steal the open file

**Why:** `open_file` refreshes the queue after `current_file` is set. The `refreshed` handler then opens `queue.get(0)` whenever that file is not pending.

**Where:** fields next to `current_file` (`liboccoder/SourceView.vala:99`), the `invalidate_cache` handler (`liboccoder/SourceView.vala:154-160`), and the `refreshed` handler (`liboccoder/SourceView.vala:190-225`).

#### Add

```vala
			private Gee.HashSet<string> pending_paths = new Gee.HashSet<string>();
			private bool follow_new_change = false;
```

#### Replace with

```vala
					this.follow_new_change = true;
					this.manager.review_files.refresh.begin();
```

#### Replace with

```vala
				this.manager.review_files.refreshed.connect(() => {
					var rows = new Gee.ArrayList<OLLMfiles.FileWithHistory>();
					rows.add_all(this.manager.review_files.file_map.values);
					var previous = this.pending_paths;
					var now = new Gee.HashSet<string>();
					OLLMfiles.FileWithHistory arrived = null;
					foreach (var row in rows) {
						now.add(row.path);
						if (!this.follow_new_change || previous.contains(row.path)) {
							continue;
						}
						if (arrived == null || row.approve_id > arrived.approve_id) {
							arrived = row;
						}
					}
					this.follow_new_change = false;
					this.pending_paths = now;
					this.review_bar.sync_pending(rows, this.current_file);
					if (arrived != null &&
						(this.current_file == null || this.current_file.path != arrived.path)) {
						this.open_pending_path(arrived.path);
						return;
					}
					if (this.current_file != null && now.contains(this.current_file.path)) {
						this.show_pending_diff.begin(this.current_file);
						return;
					}
					var reviewed_away = this.current_file != null
						&& previous.contains(this.current_file.path);
					if (!reviewed_away) {
						return;
					}
					if (this.review_bar.queue.size < 1) {
						this.close_file();
						return;
					}
					this.open_pending_path(this.review_bar.queue.get(0).path);
				});
```

`open_pending_path` is the cache-or-`fetch_file` sequence already in this handler (`liboccoder/SourceView.vala:205-224`). The early return that skips `open_file` when `current_file` is back in `file_map` stays inside that helper.

### 2. `liboccoder/SourceView.vala` — center one buffer line

**Where:** `navigate_to_line` (`liboccoder/SourceView.vala:858-879`).

#### Replace with

```vala
			public void navigate_to_line(int line_number, bool align_middle = false)
			{
				var buffer = this.source_view.buffer;
				var display_line = line_number;
				if (this.diff_active) {
					var extras = 0;
					var disk = line_number + 1;
					for (var i = 0; i < this.diff_remove_at.size; i++) {
						if (this.diff_remove_at.get(i) > disk) {
							break;
						}
						extras += this.diff_remove_n.get(i);
					}
					display_line = line_number + extras;
				}
				Gtk.TextIter iter;
				if (!buffer.get_iter_at_line(out iter, display_line)) {
					return;
				}
				buffer.place_cursor(iter);
				this.source_view.scroll_to_iter(iter, 0.0, align_middle, 0.0, 0.5);
			}
```

Review-bar jumps pass `align_middle: true` and a buffer line, so the `diff_active` branch is not used for them. Other callers keep the default and do not start centering.

### 3. `liboccoder/Diff/ReviewBar.vala` — buffer line, tooltip, width cap

**Where:** `HunkBand` (`liboccoder/Diff/ReviewBar.vala:39-87`), `on_width` (`liboccoder/Diff/ReviewBar.vala:1188-1258`), `on_map_clicked` (`liboccoder/Diff/ReviewBar.vala:1399-1449`), and the `navigate_to_line(scroll_line)` calls at `:424`, `:468`, `:557`, `:1056`, `:1170`, `:1371`.

#### Add

```vala
		private int buffer_line(int index)
		{
			var extra = 0;
			for (var n = 0; n < index && n < this.parts.size; n++) {
				var prev = this.parts.get(n);
				if (prev.accepted != 0) {
					continue;
				}
				if (prev.old_line_end < prev.old_line_start) {
					continue;
				}
				extra += prev.old_line_end - prev.old_line_start + 1;
			}
			var part = this.parts.get(index);
			var top = part.new_line_start - 1 + extra;
			return top < 0 ? 0 : top;
		}

		private void show_hunk(int index)
		{
			if (index < 0 || index >= this.hunks.size || index >= this.parts.size) {
				return;
			}
			this.source_view.navigate_to_line(this.buffer_line(index), true);
		}
```

Each `navigate_to_line(this.hunks.get(...).scroll_line)` from a click, next, or previous becomes `show_hunk` on that index. `update_diff` calls `show_hunk` only when `same_file` is false or `this.active` changed.

#### Add

```vala
			var map_motion = new Gtk.EventControllerMotion();
			map_motion.motion.connect((x, y) => {
				var map_x = this.map_scroll_mode ? x + this.map_scroll_x : x;
				var i = this.hunks.index_at(map_x);
				if (i < 0) {
					this.map_area.tooltip_text = "";
					return;
				}
				var hunk = this.hunks.get(i);
				this.map_area.tooltip_text = hunk.line_start == hunk.line_end
					? "Line %d".printf(hunk.line_start)
					: "Lines %d–%d".printf(hunk.line_start, hunk.line_end);
			});
			this.map_area.add_controller(map_motion);
```

#### Replace with

```vala
			var unit = (double) this.map_height;
			var cap = unit * 2.0;
			var capped = 0.0;
			foreach (var hunk in this.hunks) {
				var band = (double) int.max(1, hunk.line_count) * unit;
				capped += band > cap ? cap : band;
			}
```

The rest of `on_width` lays bands out from those capped widths (`min(line_count, 2) * unit`), including scroll mode. `line_count * sq`, `avail * line_count / weight_sum`, and `line_count * half_sq` go away.

## Attempts / changelog

- ✔️ 2026-11-16 — logged from the README open and from `SourceView` / `ReviewBar` / `ChangeView`. Not re-run in the app.

## Next

- 🔷 ⏳ Apply the three edits above.
- 🔷 ⏳ Open README while another file is pending: README stays, the bar shows the pending count.
- 🔷 ⏳ A new chat write switches the editor to that file.
- 🔷 ⏳ Accept the last pending file that is actually open: editor closes. Accept one of several: the next pending file opens.
- 🔷 ⏳ Click the second band: its top line is in the middle, and the tooltip shows the line range.
- 🔷 ⏳ A long hunk is two squares wide, not most of the strip.
