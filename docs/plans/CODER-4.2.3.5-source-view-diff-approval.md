# 4.2.3.5 — SourceView diff Phase 4: block approval flow

**Status:** **⏳** stub — **DESIGN OPEN** until Phase 3 works; then design pass, then fences

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan.**

**Parent:** [`CODER-4.2.3-URGENT-source-view-diff.md`](CODER-4.2.3-URGENT-source-view-diff.md)

**Depends on:** [`done/CODER-4.2.3.4-DONE-source-view-diff-view.md`](done/CODER-4.2.3.4-DONE-source-view-diff-view.md) (and earlier phases)

**Contract reference:** parent **Design — user walkthrough** + **SQLite model** + [`CODER-4.2.3.1`](CODER-4.2.3.1-source-view-diff-walkthrough-hello.md)

**Pointer:** `docs/guide-to-writing-plans.md` — Checklist for plans

---

## Purpose

- 🔷 Per-hunk **Approve** / **Reject** / **Unapprove** (Flows A, A1, D, E partial).
- 🔷 Insert / delete **`file_diff_part`** rows; set **`file_history.reviewed=1`** when every hunk decided.
- 🔷 Overlay off for decided hunks (approve = disk unchanged; reject = undo hunk on **V_disk**).
- 🔷 Destructive / bulk placement (changes-list menu, confirm, revert) — parent **Destructive actions**.
- 🔷 ⏳ **Stop and design** UI affordances when Phase 3 lands — do not invent gutter buttons from open bullets alone.
- 🔷 ⏳ Add **Remove / Replace / Add** fences only after that design pass.

---

## Open (close in design pass)

- 🔷 ⏳ Where partial-approve controls live (gutter / bar / menu / keys).
- 🔷 ⏳ Stacked LLM edit (Flow B) behaviour for v1.
- 🔷 ⏳ Bulk approve / reject all placement + revert.
- 🔷 ⏳ Unapprove vs Reject vs editor undo (must stay separate).
- 🔷 ⏳ Hunk file format at **`FileDiffPart.path`**.
- 🔷 ⏳ **Unsaved user edits while reviewing** — if the buffer is dirty, should the overlay re-diff against the unsaved buffer (show the user’s edits in the review diff)? **Lean: no** — keep review diff as **V_backup** vs **V_disk** (saved); unsaved edits stay ordinary buffer dirty state / editor undo, not part of the approval overlay. Confirm in design pass.

---

## LLM notes

- 🚫 Vala fences until user signs off Phase **4** design.
- 🚫 Approve / unapprove aliased to GtkSource undo/redo.
- 🚫 Approve all / reject all as primary header buttons.
- 🚫 Rewrite disk on **approve**.
- 🚫 Carry-forward logic inside **`OLLMfiles.Diff`**.
