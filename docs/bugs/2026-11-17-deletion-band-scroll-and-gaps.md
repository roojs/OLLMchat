# Deletion bands scroll past the buffer, and white rows sit in the red span

**Status:** ⏳ open

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

## Root cause

- ✔️ A pure deletion's new-file anchor is stored with the old file's coordinates. After earlier edits have shifted the new file, the last deletion bands point past the buffer, so the click does not move or lands on the last line.
- ✔️ The white rows between the three red blocks are those two equal lines, not missing tag paint. Blank rows inside a removal are tagged. They are empty lines from the deleted text.

## Ruled out

- 🚫 Matching `}`, `};`, or blank lines and gluing the deletions together. A generic diff does not look at the text.
- 🚫 Adding `discard_confusing_lines`, or any other change to the Myers / `shift_boundaries` path, without a failing test the user accepts. That step is not in the verified differ. It was added and taken back out.

## Proposed fix

- 💩 One line-number correction in `edits_to_patches`, and nothing else in `Differ`. A `REMOVE` patch's new range uses the new-file cursor, as the add and replace arms already do.

#### Replace with

```vala
				if (delete_count > 0) {
					this.patches.add(new Patch(
						PatchOperation.REMOVE,
						line_offset1 + delete_start_pos + 1,
						line_offset1 + delete_start_pos + delete_count,
						line_offset2 + insert_start_pos + 1,
						line_offset2 + insert_start_pos,
						this.lines1,
						this.lines2
					));
					continue;
				}
```

- 💩 On that pair the last two removals then report `new 1241-1240` and `new 1242-1241`, which exist. The scroll target for each band is that anchor plus earlier removed rows, which is buffer lines 1242, 1392, and 1455 (the three remove-run starts above).
- 🔷 The two `}` rows between the blocks stay. They are what this differ returns. Collapsing them is a differ design change and waits on an explicit test.

## Attempts / changelog

- ✔️ 2026-11-17 — measured with `build/examples/oc-test-source-diff` on the backup and `HEAD` of `examples/oc-test-source-diff.vala`. Dump helper removed from that file.
- ✔️ 2026-11-17 — text match in `edits_to_patches` added, then removed.
- ✔️ 2026-11-17 — `discard_confusing_lines` added to `myers_diff`, then removed. `myers_diff` is the verified body again.
- 💩 The `REMOVE` new-range edit above may already be in the working tree from before this log. It is not user-approved. Revert it if the proposal is rejected.

## Next

- 🔷 ⏳ User decides whether the `REMOVE` new-range correction is accepted.
- 🔷 ⏳ After that, re-run the same pair through `oc-test-source-diff` and confirm the three deletion clicks land on buffer lines 1242, 1392, and 1455.
- 🚫 ⏳ Do not change the differ algorithm while that check is open.
