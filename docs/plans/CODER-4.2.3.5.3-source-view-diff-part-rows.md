# 4.2.3.5.3 — ReviewBar part rows and Approvals cleanup

**Status:** **⏳** proposed

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan.**

**Parent:** [`CODER-4.2.3.5-source-view-diff-approval.md`](CODER-4.2.3.5-source-view-diff-approval.md)

**Depends on:**

- [`CODER-4.2.3.5.2-source-view-diff-approval-phase-b.md`](CODER-4.2.3.5.2-source-view-diff-approval-phase-b.md) — **✔️** editor hosts **`ReviewBar`**; live **`ReviewFiles`** queue. Bulk accept / reject are in-memory stubs.
- [`CODER-4.2.3-URGENT-source-view-diff.md`](CODER-4.2.3-URGENT-source-view-diff.md) — **`file_diff_part`**, Flow A–F

**Pointer:** `docs/guide-to-writing-plans.md` — Checklist for plans

---

## Purpose

- 🔷 Phase 1 saves the decision and changes the file. Phase 2 paints the bar and the editor.
- 🔷 A pending hunk has no saved row. Accept leaves the file alone. Reject undoes that hunk. Reset of a reject puts the hunk back. Reset of an accept does not change the file.

---

## Phase 1 — Daemon and saved rows

A part row is the saved Accept or Reject for one hunk (`file_diff_part`). The model saving the file does not create rows.

### No row until you decide

- 🔷 ⏳ A hunk stays pending until you Accept or Reject it.
- 🔷 ⏳ The first Accept or Reject of that hunk creates its row.
- 🔷 ⏳ When every hunk in this batch has a row, the batch is marked reviewed (`file_history.reviewed`).

### What the call does to the file

- 🔷 ⏳ Accept: the project file stays as it is.
- 🔷 ⏳ Reject: that hunk is undone in the project file.
- 🔷 ⏳ Reset of an accept: the row is deleted. The project file does not change.
- 🔷 ⏳ Reset of a reject: the hunk is written back into the project file, then the row is deleted.
- ℹ️ An older note said unapprove never writes the file. That is only true for an accept.

### Hunk text file

- 🔷 The hunk text is a file, not a column. Same cache area as the version backups.
- 🔷 Version backup: `~/.cache/ollmchat/edited/{date}-{history id}-{filename}`.
- 🔷 Hunk file, already named by `FileDiffPart.path`: `~/.cache/ollmchat/edited/parts/{history id}-{part id}-{part index}-{filename}.patch`.
- 🔷 ⏳ The first Accept or Reject writes that file. Reset deletes it.

### The call

- 🔷 Accept, reject, and reset are one call. The argument is `action_state`, a number.
- 🔷 `RPC-` is only for internal calls, such as `RPC-Daemon.hello`. `FileDiffPart` is the row, not a call target.
- 🔷 Hyphens join the namespace and class. The dot is only the method separator.
- 💩 Method name still proposed:

```
OLLMfilesd-FileHistory.decide(path, history_id, part_index, action_state)

action_state:
  1     accept — save the row, write the hunk file, leave the project file alone
 -1     reject — save the row, write the hunk file, undo that hunk in the project file
  0     reset  — delete the row and the hunk file
                 if the row was a reject, put the hunk back in the project file first
```

### A later edit

- 🔷 A second model edit, or you editing the file, becomes the active file and is versioned like any other write.
- 🔷 ⏳ The next review diffs that active file against the saved hunk files.
- 🔷 A hunk matches on its text, not its line number. If it only moves, the accept or reject still stands.
- 🔷 That decision stays until the whole file is approved.
- 🔷 Anything that does not match is pending.

### Accept all files

- 🔷 No separate undo call. Looking back at approved batches is file history's job.
- 🔷 Fine for now. Git already covers uncommitted work in the tree.
- 🔷 ⏳ Accept-all uses this same `decide` call once per pending hunk. It does not get its own method.

---

## Phase 2 — Review bar and editor

Depends on Phase 1. The bar calls `decide`. It does not write the file itself.

### Bands

- 🔷 ⏳ Accept turns the band light blue and moves to the next hunk.
- 🔷 ⏳ Reject turns the band light grey and moves to the next hunk.
- 🔷 ⏳ Reset sends the band back to pending red or green.
- 🔷 ⏳ Click a decided band to scroll to that hunk. Reset is the existing bar button.
- ✅ Shades in `resources/style.css` are approved until you change them. Source lines: `.oc-diff-add` `rgb(239, 252, 239)`, `.oc-diff-remove` `rgb(252, 239, 239)`. Active source and active bar: `.oc-diff-add-active` `rgb(191, 242, 191)`, `.oc-diff-remove-active` `rgb(242, 191, 191)`. Other bar bands: `.oc-diff-add-band` `rgb(215, 247, 215)`, `.oc-diff-remove-band` `rgb(247, 215, 215)`. Accepted bar: `.oc-diff-accepted` `rgb(191, 191, 242)`. Rejected bar: `.oc-diff-rejected` `rgb(221, 221, 221)`.

### After accept, in the editor

The colour on a decided hunk is the bar band, not a wash on the source text. The band does not draw line numbers. Clicking it scrolls the editor (`navigate_to_line`). The editor gutter is where the line numbers are.

- 🔷 ⏳ Red (removed) lines leave the view.
- 🔷 ⏳ Green highlighting comes off the added lines.
- 🔷 ⏳ Those lines look like normal source.
- ℹ️ Reject does not yet say how the editor text changes.

### Which hunk is active

- 🔷 ⏳ The active hunk uses the deeper red and green. `ReviewBar` owns the bar bands.
- 🔷 ⏳ Click a red or green hunk to make it the active review.
- 🔷 ⏳ Click white space and there is no active hunk. Accept and Reject hide until a hunk is selected again.
- 🚫 Accept / Reject buttons drawn inside the green or red area.
- 🔷 ⏳ A tap on the editor scroll view, such as dismissing a menu, belongs to the scroll view, not `ReviewBar`.
- ℹ️ You can scroll the source by hand. Accept and Reject still move to the next hunk. That already works on the bar.

### Header Approvals

The footer already lists the pending files ([`4.2.3.5.2`](CODER-4.2.3.5.2-source-view-diff-approval-phase-b.md)). The header list goes away once the footer menu really saves rows.

- 🔷 ⏳ Remove the header changed-files popover.
- 🔷 ⏳ Whole-file Approve and Reject move off that header. They are not a second way to open the diff.
- 🔷 ⏳ `show_pending_diff` is the only way to open a pending diff.
- 🔷 ⏳ Whole-file reject still restores the full backup. It stays on the header or the bulk menu, not on a band click.
- 🔷 ⏳ The accept-all menu item calls Phase 1 `decide` for each pending hunk. No undo button on the bar.

---

## LLM notes

- 🚫 Rewrite disk on **accept**, or on unapprove of an accept.
- 🔷 Unapprove of a **reject** does write disk: put that hunk back on **V_disk**.
- 🚫 Approve / unapprove aliased to GtkSource undo/redo.
- 🚫 Match carried hunks inside `OLLMfiles.Diff`. Matching is by hunk text when the next batch is reviewed.
- 🚫 Accept all files as primary header button.
- 🚫 Keep header changed-files popover after footer file nav ships.
- 🚫 Split **`ReviewBar.vala`** without explicit user request.
- 🚫 Add review-state APIs to **`SourceView`** — **ReviewBar** only.
- ℹ️ Touch points: `liboccoder/Diff/ReviewBar.vala`, `liboccoder/SourceView.vala`, `liboccoder/Approvals.vala`, `ollmfilesd/FileHistory.vala`, `ollmfilesd/FileDiffPart.vala`, `libocfiles/ReviewFiles.vala`.
