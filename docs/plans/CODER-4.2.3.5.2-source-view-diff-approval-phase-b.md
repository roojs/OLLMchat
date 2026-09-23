# 4.2.3.5.2 — ReviewBar Phase B: product wire

**Status:** **⏳** proposed — design carry-over from parent; **no Vala fences** until open **💩** items are **🔷**

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan.**

**Parent:** [`CODER-4.2.3.5-source-view-diff-approval.md`](CODER-4.2.3.5-source-view-diff-approval.md)

**Depends on:**

- [`done/CODER-4.2.3.4-DONE-source-view-diff-view.md`](done/CODER-4.2.3.4-DONE-source-view-diff-view.md) — **`show_pending_diff`**, backup vs disk diff
- [`done/CODER-4.2.3.5.1-DONE-source-view-diff-review-responses.md`](done/CODER-4.2.3.5.1-DONE-source-view-diff-review-responses.md) — **`responses()`**, **Feedback** popover (harness)
- Phase A **`ReviewBar`** + **`oc-test-source-diff`** — footer chrome **✅** user-smoked

**Contract reference:** [`CODER-4.2.3-URGENT-source-view-diff.md`](CODER-4.2.3-URGENT-source-view-diff.md) (walkthrough, **`file_diff_part`**, Flow A–F) · [`CODER-4.2.3.1-source-view-diff-walkthrough-hello.md`](CODER-4.2.3.1-source-view-diff-walkthrough-hello.md)

**Pointer:** `docs/guide-to-writing-plans.md` — Checklist for plans

---

## Purpose

- 🔷 Same footer + centre overlay chrome as Phase A, backed by **real** pending review state — **`file_diff_part`**, daemon RPC, **`ReviewFiles`**, disk on reject.
- 🔷 **`ReviewBar`** stays the review-chrome owner; **`SourceView`** keeps **`show_diff` / `navigate_to_line` / `clear_diff`** only (see parent **SourceView vs ReviewBar**).
- 🔷 **`show_pending_diff`** + editor shell — not harness-only.
- 🔷 Move **changed-files list** from header **`Approvals`** into footer file nav; **remove** top popover when footer ships.
- ℹ️ Phase A mock decisions in **`ReviewBar`** become persistence + RPC in this sub-plan.

---

## How it works

1. User opens a pending file → existing **`show_pending_diff`** builds **`Differ`**; editor hosts **`ReviewBar`** under **`SourceView`** (same layout as **`oc-test-source-diff`**).
2. **`ReviewBar.update_diff`** loads hunks from **`Differ.patches`** and merges **`file_diff_part`** rows for the active **`file_history`** chunk (no row = pending hunk).
3. Accept hunk → insert **`file_diff_part`** **`accepted=1`**; **no** disk write; grey band + advance.
4. Reject hunk → apply hunk undo on **V_disk** + insert **`accepted=0`**; grey band + advance.
5. Unapprove → delete part row; band pending again; disk unchanged for a prior accept.
6. All hunks have part rows → **`file_history.reviewed=1`** for that chunk.
7. Owner wires **`responses()`** for LLM feedback (same as harness); **`review_response`** handled outside **`ReviewBar`**.

---

## Persistence and disk

- 🔷 Accept → insert **`file_diff_part`** with **`accepted=1`**; **no** disk write.
- 🔷 Reject → undo hunk on **V_disk** + **`accepted=0`** part row.
- 🔷 Unapprove → delete part row; overlay state back; disk unchanged for prior accept.
- 🔷 Chunk complete when every hunk has a part row → **`file_history.reviewed=1`**.
- 🔷 Insert part rows **on first** user accept/reject per hunk — **no** upfront rows on agent write.
- 🔷 ⏳ Daemon RPC surface for part insert/delete/reject-apply (name methods when spec is **🔷**).
- 🔷 ⏳ Hunk file format at **`FileDiffPart.path`** — unified-diff text vs serialised **`Patch`** (parent open item).
- 🚫 Rewrite disk on **accept**.
- 🚫 Approve / unapprove aliased to GtkSource undo/redo.

---

## Footer chrome (real queue)

### Left — file nav

- 🔷 **`n / N`** over real pending files; queue **oldest pending change first** (by **`file_history`** write time).
- 🔷 Changed-files **hover list** from header **`Approvals`** (`next_button` popover) — same interaction, footer anchor.
- 🔷 Reconcile sort: **`Approvals`** today uses **`last_modified` descending** → footer **oldest-first**.
- 🔷 ⏳ Status affordance per file in list (pending / partial / decided) — **💩** exact glyphs TBD in review.

### Middle — inactive file

- 🔷 User on non-pending file: grey bar, red **`N changes pending review`** (real **N**).
- 🔷 Click → open **oldest** pending file via **`show_pending_diff`**.

### Right — bulk actions

- 🔷 Hover menu: unapprove all (file); accept all pending files (confirm); destructive bulk per parent plan.
- 🔷 Whole-file reject (full **V_backup** restore) stays destructive — **`Approvals`** or bulk menu, not casual band click.
- 💩 Exact middle placeholder copy vs hide footer when zero pending.

---

## Editor and `Approvals` integration

- 🔷 Hook **`Diff.ReviewBar`** into **`show_pending_diff`** / editor shell.
- 🔷 ⏳ Header **`Approvals`:** strip changed-files popover; demote or relocate whole-file Approve/Reject.
- 🔷 ⏳ **`review_response`** signal → product handler (send prompt to LLM); not in scope for daemon parts unless **🔷** later.
- 🔷 ⏳ Phone: no source-view diff preview. Tablet: **ReviewBar** + interleaved diff.
- 🔷 ⏳ Editor scroll view / **`SourceView`:** tap-on-scrolled-content (menu dismiss, etc.) — **not** **ReviewBar**.
- 🔷 ⏳ Stacked LLM edit (**Flow B**) — review **H2** only; no carry-forward v1.
- 🔷 ⏳ Unsaved dirty buffer while reviewing — **lean: no**.
- 🔷 ⏳ Header **`Approvals`** Approve/Reject vs footer relationship.
- 🔷 ⏳ Accept all files — confirm / revert semantics.

---

## Suggested order

1. 🔷 ⏳ **Wire chrome** — embed **`ReviewBar`** in product editor; real file nav + changed-files list from **`ReviewFiles`**; inactive middle label; bulk menu stubs calling real queue counts.
2. 🔷 ⏳ **Daemon + parts** — RPCs for part CRUD and reject→**V_disk**; **`ReviewBar`** reads/writes parts for active **`file_history`**.
3. 🔷 ⏳ **Approvals cleanup** — remove header changed-files popover; relocate remaining approve/reject; **`show_pending_diff`** as single entry for pending diff + bar state.

---

## Done when

- 🔷 Pending file in editor → footer matches Phase A interaction but **persists** **`file_diff_part`**.
- 🔷 File nav walks the **real** pending queue (oldest-first).
- 🔷 Click **`N changes pending review`** opens oldest pending file.
- 🔷 Reject writes **V_disk**; accept does not.
- 🔷 Header no longer owns the changed-files list.

---

## LLM notes

- 🚫 Vala implementation fences until **Still open** **💩** bullets are promoted or rejected in review.
- 🚫 Accept all files as primary header button.
- 🚫 Carry-forward inside **`OLLMfiles.Diff`**.
- 🚫 Keep header changed-files popover after footer file nav ships.
- 🚫 Phone source-view diff preview (tablet only).
- 🚫 **ReviewBar** handling taps on the editor scroll view.
- 🚫 Split **`ReviewBar.vala`** without explicit user request.
- 🚫 Add review-state APIs to **`SourceView`** — **ReviewBar** only.
- ℹ️ Touch points: `liboccoder/Diff/ReviewBar.vala`, `liboccoder/SourceView.vala`, `liboccoder/Approvals.vala`, `ollmfilesd/FileHistory.vala`, `ollmfilesd/FileDiffPart.vala`, `libocfiles/ReviewFiles.vala`.
