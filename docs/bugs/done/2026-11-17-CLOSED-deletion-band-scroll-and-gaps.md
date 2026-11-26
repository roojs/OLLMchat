# Deletion bands scroll past the buffer, and white rows sit in the red span

**Status:** ✅

**Pointer:** `docs/bug-fix-process.md` · [`2026-11-16-FIXED-diff-preview-open-and-map.md`](2026-11-16-FIXED-diff-preview-open-and-map.md)

- ✅ Closed 2026-11-26. A general ticket covers this. Not relevant at present.

## Problem

- 🔷 Pending file `examples/oc-test-source-diff.vala` (history `43023`, backup `~/.cache/ollmchat/edited/2026-10-28-43023-oc-test-source-diff.vala`). The footer shows about six bands. The last three are deletions.
- 🔷 Expected: each deletion band scrolls so the first removed row of that band is in view. A long red span does not have ordinary rows sitting in the middle of it.
- 🔷 Actual: the first deletion scrolls to that change. The second does not land on it. The third does nothing. Inside the red span, and between those three blocks, some rows are plain white.

## Evidence

- ✔️ Pair compared with the verified `Differ` (before any anchor-dropping change), via `examples/oc-test-source-diff` `show_diff` on that backup and the file at `HEAD`. Six patches:

```
REPLACE  old 805-805    new 805-805
REPLACE  old 932-932    new 932-932
REPLACE  old 934-934    new 934-934
REMOVE   old 1240-1388  new 1240-1239
REMOVE   old 1390-1451  new 1390-1389
REMOVE   old 1453-1461  new 1453-1452
```

- ✔️ The two later `new` ranges are old-file numbers. The new file is 1243 lines. `1390` and `1453` are past its end.
- ✔️ Where that comes from: `edits_to_patches` writes a `REMOVE` patch's `new_line_start` / `new_line_end` from `line_offset1` and `delete_start_pos` (the old side). The add and replace arms use `line_offset2` and `insert_start_pos`. `libocfiles/Diff/Differ.vala` around the `PatchOperation.REMOVE` construction.
- ✔️ Same run, buffer after `show_diff` is 1466 lines. Remove runs start at buffer lines 1242, 1392, and 1455. Clicking with the old-file scroll line (`HunkBand` `scroll_line = old_line_start - 1`, then `navigate_to_line` while `diff_active`) landed on:

```
band 3  scroll_in 1239  cursor 1391  tag none  text "}"
band 4  scroll_in 1389  cursor 1465  tag none  (last line)
band 5  scroll_in 1452  cursor 1465  tag none  (last line)
```

- ✔️ Two untagged rows sit between those remove runs: buffer line 1391 `}` and buffer line 1454 `}`. Those are the equal lines the differ kept (old 1389 and old 1452). 16 other blank rows inside the removals are tagged `diff-remove`. 18 untagged blanks are outside the runs (blank lines that exist in the file).
- ℹ️ `diff -U0` on the same pair is four hunks, and the deletion is one: `@@ -1242,220 +1241,0 @@`. That is a different grouping. It is not by itself a defect in the verified differ.
- ℹ️ The app's pending paint is `ChangeView`, not `show_diff`. Both read the same patch line numbers. `ChangeView` inserts removed lines and leaves those equal lines as ordinary rows between the red blocks.
- ✔️ 2026-11-17 later run, built `libocfiles.so` (2026-11-13, still the old `REMOVE` new-range). Pair is `2caeca8d` of `examples/oc-test-source-diff.vala` against the file in the tree. Same three replaces (805, 932, 934). `lines1=1454`, `lines2=1243`. One removal, not three:

```
REPLACE  old 805-805    new 805-805
REPLACE  old 932-932    new 932-932
REPLACE  old 934-934    new 934-934
REMOVE   old 1242-1452  new 1242-1241
```

- ✔️ `PatchApplier` on those patches reproduces the new file byte for byte. The new anchor `1242-1241` is inside the new file. `diff -U0` is the same deletion: `@@ -1243,211 +1242,0 @@` (its start is one line later than `split("\n")`).
- ✔️ The removal is the appended `namespace OLLMapp.SettingsDialog` block. It contains 16 empty lines (old 1243, 1258, 1263, 1268, 1276, 1279, 1285, 1307, 1317, 1344, 1381, 1426, 1430, 1444, 1447, 1450). The `show_diff` walk tags all 16 `diff-remove`. 18 blanks sit outside the run. Old 1389 is `var colon = this.found.last_index_of(":");`, not a kept `}`.
- ℹ️ The backup named in the first measurement is not on disk, so that exact three-removal split was not re-run. This pair has the same replace sites and the same 16 / 18 blank counts, and the built differ does not split it.
- ✔️ Screenshot of the deletion (`FileConnectionAdd`): text rows sample to `(248, 232, 232)`, which is `.oc-diff-remove` `rgb(252, 239, 239)` after 8-bit quantization (`252//8*8`, `239//8*8`). Blank rows in the same block sample to `(248, 248, 248)`, the editor background. They are not the pale wash and not the tag's `rgb(242, 191, 191)`.
- ✔️ GtkSourceView 5.16 `gtk_source_view_paint_line_background` documents that a text tag cannot paint an empty line (a tag cannot cover an empty range). The full-line paint, including an empty line, is `GtkSourceMark` plus `GtkSourceMarkAttributes` background, drawn across the visible width. `show_line_marks` is already on.

## Root cause

- ✔️ The differ reports this deletion correctly. One `REMOVE`, and applying the patches yields the new file. Nothing in the Myers path needs to change for the white rows.
- ✔️ The white rows inside the red span are empty lines of that removal. They are tagged. GtkSourceView does not paint a text tag on an empty line, so those rows stay the editor background while the lines that have text show the wash.
- 🚫 The pale-versus-glyph theory. The measured blank is the editor background, not `rgb(252, 239, 239)` and not `rgb(242, 191, 191)`. Copying the swatch onto `background_rgba` and extending the active tag through the newline does not paint an empty line.
- ℹ️ A later removal whose new anchor is still an old-file line number would still scroll past the buffer. This pair does not do that: the new anchor is `1242-1241`. The three-removal scroll numbers in the first measurement were not reproduced.

## Ruled out

- 🚫 Matching `}`, `};`, or blank lines and gluing the deletions together. A generic diff does not look at the text.
- 🚫 Adding `discard_confusing_lines`, or any other change to the Myers / `shift_boundaries` path, without a failing test the user accepts. That step is not in the verified differ. It was added and taken back out.

## Proposed fix

- 🚫 Do not change `Differ` for this. The removal it reports is the deleted text, and the applier round-trips.
- 🔷 A source mark on each changed line, with a mark-attribute background of the same color as that line's wash. GtkSourceView paints that across the whole line, including a blank one. The active hunk uses a second category at a higher priority so its blanks follow the stronger wash. No filler characters (the space drawer would draw them).

#### Add

`liboccoder/SourceView.vala`, after the diff tags are created:

```vala
				var add_line = new GtkSource.MarkAttributes();
				add_line.set_background(Gdk.RGBA() {
					red = 0.75f,
					green = 0.95f,
					blue = 0.75f,
					alpha = 1.0f
				});
				this.source_view.set_mark_attributes("diff-add", add_line, 1);
				var remove_line = new GtkSource.MarkAttributes();
				remove_line.set_background(Gdk.RGBA() {
					red = 0.95f,
					green = 0.75f,
					blue = 0.75f,
					alpha = 1.0f
				});
				this.source_view.set_mark_attributes("diff-remove", remove_line, 1);
				var add_active_line = new GtkSource.MarkAttributes();
				add_active_line.set_background(Gdk.RGBA() {
					red = 0.75f,
					green = 0.95f,
					blue = 0.75f,
					alpha = 1.0f
				});
				this.source_view.set_mark_attributes("diff-add-active", add_active_line, 2);
				var remove_active_line = new GtkSource.MarkAttributes();
				remove_active_line.set_background(Gdk.RGBA() {
					red = 0.95f,
					green = 0.75f,
					blue = 0.75f,
					alpha = 1.0f
				});
				this.source_view.set_mark_attributes("diff-remove-active", remove_active_line, 2);
```

#### Add

`liboccoder/SourceView.vala` `show_diff`, after `apply_tag` on a changed line:

```vala
					this.diff_buffer.create_source_mark(null,
						kinds.get(i) == 1 ? "diff-add" : "diff-remove", iter);
```

#### Add

`liboccoder/ChangeView.vala`, after each `apply_tag` on a remove or add span (both `apply` and `apply_parts`): one `create_source_mark` per line of that span, category `diff-remove` or `diff-add`.

#### Add

`examples/oc-test-source-diff.vala` `apply_highlight`, after the swatch colors are copied onto the tags: the same colors onto the four mark attributes, drop any `diff-add-active` / `diff-remove-active` marks, and on the active hunk add a mark in the matching `-active` category for each line that already has a `diff-add` or `diff-remove` mark.

## Attempts / changelog

- ✔️ 2026-11-17 — measured with `build/examples/oc-test-source-diff` on the backup and `HEAD` of `examples/oc-test-source-diff.vala`. Dump helper removed from that file.
- ✔️ 2026-11-17 — text match in `edits_to_patches` added, then removed.
- ✔️ 2026-11-17 — `discard_confusing_lines` added to `myers_diff`, then removed. `myers_diff` is the verified body again.
- ✔️ 2026-11-17 — ran the built `Differ` (library dated 2026-11-13) on `2caeca8d` against the tree file. Four patches, applier matches, 16 tagged blanks inside the one removal.
- ℹ️ Commit `976b4aca` already points a `REMOVE` new range at `line_offset2`. This pair's anchor is the same either way, because the earlier hunks are one-line replaces.
- ✔️ 2026-11-17 — source marks added on each changed line in `show_diff` and `ChangeView`, with mark-attribute colors matching the wash. `apply_highlight` copies the swatch onto those attributes and puts a higher-priority `-active` mark on the current hunk, including its blank lines. `examples/oc-test-source-diff` rebuilt.

## Next

- 🔷 ⏳ Restart the diff window and look at a blank row inside a red or green block. It should be the same wash as the other rows in that block. Do not change `Differ`.
- ✔️ 2026-11-17 — reordered sample. `2caeca8d` had `\t\t}` and `\t}` on the class close, immediately before the appended namespace, so the differ kept them with the new file and deleted the namespace as one run. Those two lines are moved into the namespace (`tests/source-diff/deletion-bands-baseline.vala`). The new side is `tests/source-diff/deletion-bands-current.vala` (the tree file). Built differ, old `REMOVE` anchors:

```
REPLACE  old 805-805    new 805-805
REPLACE  old 932-932    new 932-932
REPLACE  old 934-934    new 934-934
REMOVE   old 1240-1340  new 1240-1239
REMOVE   old 1342-1442  new 1342-1341
REMOVE   old 1444-1452  new 1444-1443
```

`PatchApplier` matches. The kept lines are old 1341 `\t\t}` and old 1443 `\t}`. The later new anchors are past the 1243-line new file. 16 blank lines sit inside the removals. `diff -U0` also splits this pair (three deletion hunks); the original backup's single GNU hunk is not reproduced. Open with `build/examples/oc-test-source-diff tests/source-diff/deletion-bands-baseline.vala tests/source-diff/deletion-bands-current.vala`. The `show_diff` walk sets `new_i` from those past-the-end anchors, so the second brace and the shared closing lines are not copied (`leftover_new` about -200).
