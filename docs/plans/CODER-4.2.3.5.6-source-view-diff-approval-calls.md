# 4.2.3.5.6 — Approval calls

**Status:** **⏳** proposed — no Vala fences yet

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan.**

**Parent:** [`CODER-4.2.3.5-source-view-diff-approval.md`](CODER-4.2.3.5-source-view-diff-approval.md)

**Design:** [`CODER-4.2.3.5.4-source-view-diff-wire-model.md`](CODER-4.2.3.5.4-source-view-diff-wire-model.md)

**Supersedes:** [`done/CODER-4.2.3.5.3-SUPERSEDED-source-view-diff-part-rows.md`](done/CODER-4.2.3.5.3-SUPERSEDED-source-view-diff-part-rows.md) — do not apply its fences.

**Depends on:** [`CODER-4.2.3.5.5-source-view-diff-items.md`](CODER-4.2.3.5.5-source-view-diff-items.md) — diff items stored on the file server, hunk text on the wire.

**Pointer:** `docs/guide-to-writing-plans.md` — Checklist for plans

---

## Purpose

- 🔷 One hunk goes through the diff item. That item applies the change. The file server updates the stored item.
- 🔷 **Accept file changes**, **Reject file changes**, and **Reset** are one method, `OLLMfilesd-FileHistory.decide`. The action is accept, reject, or reset.
- 🔷 Accept leaves the project file alone. Reject undoes that hunk. Reset of a reject puts the hunk back. Reset of an accept does not change the file.

---

## Calls

The bar and the menu send a decision. They do not send the file body.

```
desktop                                          ollmfilesd
────────────────────────────────────────────────────────────────
one hunk — Accept / Reject / Reset
  diff item
    diff-item id, approval          →
                                      that item applies it
                                      server updates the stored item
                                  ←  that item, updated

menu — Accept file changes
       Reject file changes
       Reset
  OLLMfilesd-FileHistory.decide
    history id, action              →
                                      action is accept, reject, or reset
                                      applied to every diff item
                                      on that history
```

- 🔷 One hunk is a call on the diff item. The request is that item and the approval.
- 🔷 `decide` covers every diff item on that history. It does not call the diff item once per hunk.
- 🔷 The file server updates the stored items, so the next load still has the decision.
- 🔷 The daemon does not run `Differ` again for a decision. The hunk text is already on the item.
- 🔷 When every diff item on that history has a decision, `file_history.reviewed` is set. A row existing is not enough. The item still has to be decided.
- 🔷 Accept turns the band light blue and moves to the next hunk. Reject turns the band light grey and moves to the next hunk. Reset sends the band back to pending red or green.
- 🔷 Click a decided band to scroll to that hunk. Reset is the existing bar button.
- 🔷 After accept, removed lines leave the view and the green comes off the added lines. Those lines look like normal source. The colour of a decided hunk is the bar band.
- 🔷 The active hunk uses the deeper red and green. Click a red or green hunk to make it active. Click white space and there is no active hunk. Accept and Reject hide until a hunk is selected again.
- 🔷 Remove the header changed-files popover. `show_pending_diff` is the only way to open a pending diff. Whole-file approve and reject are the bulk menu, not a second way to open the diff.
- ✅ Shades in `resources/style.css` stay. Source: `.oc-diff-add` `rgb(239, 252, 239)`, `.oc-diff-remove` `rgb(252, 239, 239)`. Active source and active bar: `.oc-diff-add-active` `rgb(191, 242, 191)`, `.oc-diff-remove-active` `rgb(242, 191, 191)`. Other bar bands: `.oc-diff-add-band` `rgb(215, 247, 215)`, `.oc-diff-remove-band` `rgb(247, 215, 215)`. Accepted bar: `.oc-diff-accepted` `rgb(191, 191, 242)`. Rejected bar: `.oc-diff-rejected` `rgb(221, 221, 221)`.
- ℹ️ Menu labels are in `liboccoder/Diff/ReviewBar.vala`. Today they only flip in-memory decisions. Today the whole-file wire is `RPC-FileHistory.rpc_approve` and `RPC-FileHistory.rpc_revert`.
- ℹ️ No separate undo call. Looking back at approved batches is file history's job. Git already covers uncommitted work in the tree.
- 💩 **Accept changes to all files** and **Reject changes to all files** are `decide` once per file.
- 💩 The hunk reply is that one updated item. The desktop adjusts the editor from the hunk text it already has.
- 💩 The diff-item method name is not chosen. It is not `FileHistory.decide`.

---

## LLM notes

- 🚫 Apply any fence from [`4.2.3.5.3`](done/CODER-4.2.3.5.3-SUPERSEDED-source-view-diff-part-rows.md). That `decide` took `part_index` and re-read both full texts.
- 🚫 Rewrite the project file on accept, or on reset of an accept.
- 🚫 Approve / reset aliased to GtkSource undo/redo.
- 🚫 Accept / Reject buttons drawn inside the green or red area.
- 🚫 Accept all files as the primary header button.
- 🚫 Keep the header changed-files popover.
- 🚫 Split `ReviewBar.vala`.
- 🚫 Review-state APIs on `SourceView`. `ReviewBar` only.
- ℹ️ Touch points: `liboccoder/Diff/ReviewBar.vala`, `liboccoder/Approvals.vala`, `liboccoder/SourceView.vala`, `ollmfilesd/FileHistory.vala`, `ollmfilesd/FileDiffPart.vala`.
