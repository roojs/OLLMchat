# Deletion bands scroll past the buffer, and white rows sit in the red span

**Status:** ⏳ differ round-trip confirmed; white rows are the line wash — fix not applied

**Pointer:** `docs/bug-fix-process.md` · [`done/2026-11-16-FIXED-diff-preview-open-and-map.md`](done/2026-11-16-FIXED-diff-preview-open-and-map.md)

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
- ✔️ `examples/oc-test-source-diff.vala` `apply_highlight` copies the swatch `color` onto `paragraph_background` only. `.oc-diff-remove` is `rgb(252, 239, 239)`. The tag's `background_rgba` stays `rgb(242, 191, 191)`, which paints glyphs. An empty line has no glyphs, so it stays the near-white paragraph wash. The active tag is applied from the line start to `forward_to_line_end()`. On an empty line that range is empty, so `diff-remove-active` never covers it.

## Root cause

- ✔️ The differ reports this deletion correctly. One `REMOVE`, and applying the patches yields the new file. Nothing in the Myers path needs to change for the white rows.
- ✔️ The white rows inside the red span are the 16 empty lines of that removal. They are tagged. The test app's line wash paints text and empty lines with different colors, and the active wash skips the empty lines.
- ℹ️ A later removal whose new anchor is still an old-file line number would still scroll past the buffer. This pair does not do that: the new anchor is `1242-1241`. The three-removal scroll numbers in the first measurement were not reproduced.

## Ruled out

- 🚫 Matching `}`, `};`, or blank lines and gluing the deletions together. A generic diff does not look at the text.
- 🚫 Adding `discard_confusing_lines`, or any other change to the Myers / `shift_boundaries` path, without a failing test the user accepts. That step is not in the verified differ. It was added and taken back out.

## Proposed fix

- 🚫 Do not change `Differ` for this. The removal it reports is the deleted text, and the applier round-trips.
- 💩 In `examples/oc-test-source-diff.vala` `apply_highlight`, the line wash and the glyph wash are the same swatch color, and the active tag covers the newline the way `show_diff` already tags a line. An empty removed row then takes the same color as the rest of that hunk.

#### Replace with

```vala
			add_tag.paragraph_background_rgba = this.add_swatch.get_color();
			add_tag.background_rgba = this.add_swatch.get_color();
			remove_tag.paragraph_background_rgba = this.remove_swatch.get_color();
			remove_tag.background_rgba = this.remove_swatch.get_color();
```

#### Replace with

```vala
			active_add.paragraph_background_rgba = this.add_active_swatch.get_color();
			active_add.background_rgba = this.add_active_swatch.get_color();
			active_remove.paragraph_background_rgba = this.remove_active_swatch.get_color();
			active_remove.background_rgba = this.remove_active_swatch.get_color();
```

#### Replace with

```vala
				to = from;
				if (!to.ends_line()) {
					to.forward_to_line_end();
				}
				if (!to.is_end()) {
					to.forward_char();
				}
```

- ℹ️ `ChangeView` already sets paragraph and glyph background to the same pink and tags through the following line. That path is not the white-row cause on this pair.

## Attempts / changelog

- ✔️ 2026-11-17 — measured with `build/examples/oc-test-source-diff` on the backup and `HEAD` of `examples/oc-test-source-diff.vala`. Dump helper removed from that file.
- ✔️ 2026-11-17 — text match in `edits_to_patches` added, then removed.
- ✔️ 2026-11-17 — `discard_confusing_lines` added to `myers_diff`, then removed. `myers_diff` is the verified body again.
- ✔️ 2026-11-17 — ran the built `Differ` (library dated 2026-11-13) on `2caeca8d` against the tree file. Four patches, applier matches, 16 tagged blanks inside the one removal.
- ℹ️ Commit `976b4aca` already points a `REMOVE` new range at `line_offset2`. This pair's anchor is the same either way, because the earlier hunks are one-line replaces.

## Next

- 🔷 ⏳ Apply the `apply_highlight` wash so an empty removed row uses the same color as the rest of the hunk. Do not change `Differ`.
- ℹ️ The backup `~/.cache/ollmchat/edited/2026-10-28-43023-oc-test-source-diff.vala` is gone, so the earlier three-removal split cannot be re-run until that file is back.
