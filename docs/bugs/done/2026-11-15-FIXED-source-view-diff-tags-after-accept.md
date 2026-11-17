# SourceView keeps red and green diff highlighting after accepting a hunk

**Status:** ✅ fixed — highlighting lands in `ChangeView.proposal` / `apply_parts`. Review bar and deletion-band scroll stay open.

**Pointer:** `docs/bug-fix-process.md` · `docs/plans/done/CODER-4.2.3.5.6-DONE-source-view-diff-approval-calls.md`

## Problem

- 🔷 Accepting a hunk in `SourceView` (`examples/oc-test-source-diff.vala`) should remove its `diff-remove` (red) lines and strip the `diff-add` (green) highlight from the accepted lines so they look like normal source (while `ReviewBar` shows the band in light blue).
- 🔷 Actual: `ReviewBar` turned the hunk bands blue, while `SourceView` kept all red and green highlighting.

## Evidence

- ℹ️ Spec (`docs/plans/done/CODER-4.2.3.5.6-DONE-source-view-diff-approval-calls.md:58`):
  - *"After accept, removed lines leave the view and the green comes off the added lines. Those lines look like normal source. The colour of a decided hunk is the bar band."*
- ℹ️ Log (`2026-11-15 08:56:22`–`08:56:38`, `~/.cache/ollmchat/ollmchat.debug.log`):
  - ✔️ 6 `FileDiffPart.apply` calls (`id=42,44,46,48,50,52`) each followed by `FileHistory.parts` (`id=43,45,47,49,51,53`) via `ReviewBar.send_part` → `SourceView.show_pending_diff`.

## Root cause

- ✔️ `ChangeView.proposal` (`liboccoder/ChangeView.vala:109-156`) does not check `inc.accepted != 0`; decided hunks stay `unchanged = false`.
- ✔️ `ChangeView.apply` (`liboccoder/ChangeView.vala:170-231`) and `ChangeView.apply_parts` (`liboccoder/ChangeView.vala:243-369`) only omit `hunk_remove` and diff tags when `part.unchanged` is `true`.
- ✔️ `ChangeView.apply_parts` (`liboccoder/ChangeView.vala:256-265`) matches `cur` and `inc` using `cur.compare(inc)` (`old_line_*`, `new_line_*`, `checksum`) without checking `cur.unchanged == inc.unchanged`. Even if a pure-add hunk (`hunk_remove == ""`) flips to `unchanged = true`, `compare()` still returns `3` and skips updating the buffer.

## Proposed fix

- 🔷 In `ChangeView.proposal`, convert any decided hunk (`inc.accepted != 0`) into an `unchanged = true` `FileDiffPart` using the current buffer lines (`inc.new_line_start..inc.new_line_end`, or `""` when `new_line_end < new_line_start`), so both `apply` (initial load) and `apply_parts` (live update) render accepted/rejected hunks as plain source without `diff-remove` or `diff-add` tags, while `Unapprove` (`accepted == 0`) restores red/green diff display.
- 🔷 In `ChangeView.apply_parts`, require `cur.unchanged == inc.unchanged` for `rel == 2 || rel == 3` skips and lookahead matches, and replace (`put = true; take = true;`) when `cur.unchanged != inc.unchanged`.

### 1. `liboccoder/ChangeView.vala` — render decided hunks as `unchanged` and compare `unchanged`

**Where:** `ChangeView.proposal` (`liboccoder/ChangeView.vala:144-154`) and `ChangeView.apply_parts` (`liboccoder/ChangeView.vala:254-292`).

#### Remove

```vala
				var inc = parts.get(i);
				inc.update_sum();
				next.parts.add(inc);
				if (inc.new_line_end >= inc.new_line_start) {
```

#### Replace with

```vala
				var inc = parts.get(i);
				var part = inc;
				if (inc.accepted != 0) {
					var text = "";
					if (inc.new_line_end >= inc.new_line_start &&
						inc.new_line_start >= 1 &&
						inc.new_line_end <= lines.length) {
						text = string.joinv("\n", lines[inc.new_line_start - 1:inc.new_line_end]);
					}
					part = new OLLMfiles.FileDiffPart() {
						new_line_start = inc.new_line_start,
						new_line_end = inc.new_line_end,
						old_line_start = inc.old_line_start,
						old_line_end = inc.old_line_end,
						hunk_add = text,
						unchanged = true
					};
				}
				part.update_sum();
				next.parts.add(part);
				if (inc.new_line_end >= inc.new_line_start) {
```

#### Remove

```vala
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
```

#### Replace with

```vala
				if (i < this.parts.size && j < next.parts.size) {
					var cur = this.parts.get(i);
					var inc = next.parts.get(j);
					var rel = cur.compare(inc);
					if ((rel == 2 || rel == 3) && cur.unchanged == inc.unchanged) {
						at += cur.new_line_end < cur.new_line_start ? 0 : cur.new_line_end - cur.new_line_start + 1;
						if (!cur.unchanged) {
							at += cur.old_line_end < cur.old_line_start ? 0 : cur.old_line_end - cur.old_line_start + 1;
						}
						i++;
						j++;
						continue;
					}
					if (rel == 1 || ((rel == 2 || rel == 3) && cur.unchanged != inc.unchanged)) {
						put = true;
						take = true;
					}
					if (rel == 0) {
						var later_next = j + 1;
						while (later_next < next.parts.size) {
							var cand = next.parts.get(later_next);
							var ahead = cur.compare(cand);
							if ((ahead == 2 || ahead == 3) && cur.unchanged == cand.unchanged) {
								break;
							}
							later_next++;
						}
						var later_cur = i + 1;
						while (later_cur < this.parts.size) {
							var cand = this.parts.get(later_cur);
							var ahead = inc.compare(cand);
							if ((ahead == 2 || ahead == 3) && inc.unchanged == cand.unchanged) {
								break;
							}
							later_cur++;
						}
```

## Attempts / changelog

- ✔️ 2026-11-15 — inspected `ollmchat.debug.log` and `liboccoder/ChangeView.vala`; root cause confirmed and fix proposed.
- ✔️ 2026-11-15 — applied item 1 in `liboccoder/ChangeView.vala`. Built with `ninja -C build` and verified `meson test -C build test-rpc-filesd-pair-flow` passes.

## Next

- 🔷 ⏳ Verify accepting/rejecting/unapproving hunks updates `SourceView` highlighting to plain source (and back on Unapprove).
