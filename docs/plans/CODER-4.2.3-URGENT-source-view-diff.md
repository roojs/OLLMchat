# 4.2.3. URGENT - SourceView inline diff (approve / reject)

> **Do not update `docs/plans/CODER-1.0-summary.md` for this plan.**

**Status:** **URGENT** · **DESIGN OPEN** · **⏳** implementation **blocked** until baseline, partial-approval, and undo/approval separation are designed

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

**Parent:** [`done/4.2-DONE-code-editor-tool.md`](done/4.2-DONE-code-editor-tool.md) — Phase 6 (split from ⏳ FUTURE)

**Related:**

- ℹ️ Shipped list + approve/reject: [`done/2.10.4.26-DONE-file-history-approval-knock-on.md`](done/2.10.4.26-DONE-file-history-approval-knock-on.md)
- ℹ️ Daemon approve/revert: [`done/2.10.4.25-DONE-file-history-approval.md`](done/2.10.4.25-DONE-file-history-approval.md)
- ℹ️ Diff library: [`done/5.2-DONE-diff-match-patch-simple-port.md`](done/5.2-DONE-diff-match-patch-simple-port.md) — `OLLMfiles.Diff.Differ`
- ℹ️ Hunk merge reference: [`examples/oc-diff.vala`](../../examples/oc-diff.vala)

---

## Purpose

### Confirmed (UI — ship when design unblocks)

- 🔷 Pending-approval files show an **inline unified diff** in `SourceView` (not a second editor pane).
- 🔷 **Secondary gutter** — baseline line numbers beside the normal gutter.
- 🔷 **Added** lines: green background.
- 🔷 **Removed** lines: red background; interleaved rows (unified-diff style).
- ✔️ Per-file **Approve** / **Reject** / changed-files list on **`Approvals`** bar — shipped today; **placement of destructive / bulk actions** is still ⏳ (see below).
- 🔷 Destructive review actions (whole-file reject, **approve all files**, reject all) must **not** sit as casual primary UI — tuck away (e.g. changes-list menu), with explicit revert.

### Open (must decide before coding)

- 🔷 ⏳ **Partial approval** — user may accept **some** hunks/lines/chunks, not only whole-file approve.
- 🔷 ⏳ **What the diff is against** — which stored snapshot is “baseline” while review is in progress.
- 🔷 ⏳ **Intermediate approved state** — where a partly-approved file lives between clicks and between LLM rounds.
- 🔷 ⏳ **Stacked LLM edits** — file still pending (or partly approved); agent writes again; what diff do we show?
- 🔷 ⏳ **Undo approval vs undo edit** — approval rollback must **not** rely on editor undo/redo (see **Cursor contrast** below).
- 🔷 ⏳ **Bulk approve all files** — if offered at all, placement, confirmation, and **revert bulk approve** (see **Destructive actions**).

**Suggested order**

1. 🔷 ⏳ Close **Design — approval baseline** (partial approve, intermediate storage, stacked edits, **approval undo**).
2. 🔷 ⏳ Design **diff UI** and **destructive-action placement** (changes dropdown, bulk actions, revert paths).
3. 🔷 ⏳ Add **implementation spec** (code fences) to this plan or a sub-plan — only after 1–2.

---

## Design — approval baseline and partial approval

ℹ️ Parent context: [`done/4.2-DONE-code-editor-tool.md`](done/4.2-DONE-code-editor-tool.md) Phase 6 (“temporary approved copy”, diff against that, sliding window when further changes occur).

ℹ️ Shipped today ([`done/2.10.4.25-DONE-file-history-approval.md`](done/2.10.4.25-DONE-file-history-approval.md)):

- One **file** row in `ReviewFiles` with **`approve_id`** (newest pending `file_history` row) and **`reject_id`** (newest row with backup).
- **Approve (whole file):** marks that row and all older pending rows on the file approved.
- **Reject (whole file):** restores from **`reject_id`** backup; disk + DB update; client `File.read`.
- Multiple **`file_history`** rows per file already exist (timeline); UI collapses to one popover row per file.

### Cursor contrast (what to avoid)

ℹ️ In Cursor, rolling back an approval decision is **hard** — it is effectively bundled into **undo/redo**, not a first-class “I changed my mind about this approve” action. That is **counterintuitive** for a review workflow.

ℹ️ Cursor also exposes **approve all changes** across **multiple files** alongside per-file approve — both classes of action are **highly destructive** but easy to hit from the general review UI.

- 🔷 Approval state changes must be **explicit review actions**, not aliases of **`Ctrl+Z` / `Ctrl+Shift+Z`** on the text buffer.
- 🔷 ⏳ **Unapprove / rollback approval** — dedicated affordance(s) with clear semantics:
  - whole-file “undo approve” while file still in review?
  - per-hunk “unaccept” after partial approve?
  - distinct from **Reject** (which restores disk from backup)?
  - **bulk** “undo approve all” if bulk approve exists?
- 🔷 ⏳ **`file_history` timeline** should be the audit trail for approve/unapprove — not the GtkSource undo stack.
- 🔷 ⏳ After user **edits the file manually** during review, undo stack and approval state must stay **separate** (manual edit undo ≠ unapprove LLM hunk).

### Destructive actions (placement + revert)

🔷 Whole-file **Approve** and **Reject** (and any **approve all / reject all**) mutate disk + `file_history` — treat as **destructive**, not generic toolbar actions.

- 🔷 ⏳ **Primary bar** — keep for **navigation** (next file, open changed file) and **non-destructive** review chrome; reconsider whether per-file Approve/Reject stay as prominent **`suggested-action`** buttons long term.
- 🔷 ⏳ **Bulk actions** — if we ship **approve all pending files** (Cursor parity), place in **changes-list overflow** (popover / dropdown menu on the changed-files control), **not** next to everyday editor chrome.
- 🔷 ⏳ **Confirmation** — bulk approve all and bulk reject all likely need an explicit confirm step (count of files + chunks).
- 🔷 ⏳ **Revert bulk actions** — must exist as first-class operations:
  - revert last bulk approve (restore pending state per file)?
  - or per-file unapprove only (no single “undo all”)?
  - backed by `file_history` / batch id — **not** editor undo.
- ℹ️ Shipped today: per-file Approve/Reject on [`liboccoder/Approvals.vala`](../../liboccoder/Approvals.vala) header — redesign may move or restyle when diff UI lands.

### Questions to close (user + design review)

- 🔷 ⏳ **Partial approve granularity** — hunk, line range, or `file_history` chunk? Per-hunk buttons in the diff view vs a separate chunk list?
- 🔷 ⏳ **Baseline for the diff** while pending:
  - (A) **`reject_id` backup** — pre–latest-write on disk (matches today’s revert target; whole-file mental model).
  - (B) **Last fully approved snapshot** — “approved head” even if user only partly approved last time.
  - (C) **Last intermediate snapshot** — explicit “working approved copy” updated as user accepts hunks.
  - (D) **Per-chunk backup** — each `file_history` row’s `backup_path` (aligns with chunk timeline).
- 🔷 ⏳ **Intermediate storage** — where does partly-approved content live?
  - On disk (new backup path / “staging” file)?
  - Only in DB flags on `file_history` rows (some approved, some pending)?
  - Client-side until next save (probably insufficient for multi-window / reload)?
- 🔷 ⏳ **Second LLM edit while still pending** — agent modifies the same file again before user finishes review:
  - New `file_history` row + new backup; diff baseline stays “start of this review session” or “last approved/intermediate”?
  - Does partial progress reset, merge, or apply on top of the intermediate copy?
  - Does **`approve_id` / `reject_id`** on `FileWithHistory` stay sufficient or do we need **`diff_base_id`** (or similar) on the wire?
- 🔷 ⏳ **Reject after partial approve** — revert to original pre-change backup, to last intermediate, or ask user?
- 🔷 ⏳ **Relationship to whole-file Approve/Reject on `Approvals` bar** — demote, move to menu, or keep for selected file only?
- 🔷 ⏳ **Approve all files** — ship at all? Menu-only? Reversible how?
- 🔷 ⏳ **Reject all pending** — same placement rules as approve all?
- 🔷 ⏳ **Undo approve vs Reject** — if user approved by mistake, is there an **Unapprove** that reopens pending state without full disk revert? How does that differ from Reject and from editor undo?
- 🔷 ⏳ **Partial unapprove** — walk back one hunk, one chunk, or only all-or-nothing?

### UI (not designed yet)

- 🔷 ⏳ Where partial-approve controls live — gutter icons, per-hunk bar, context menu, keyboard?
- 🔷 ⏳ Read-only diff buffer vs editable file with overlays?
- 🔷 ⏳ How user sees progress when some hunks approved and others not (counts, dimming, second list)?
- 🔷 ⏳ Secondary baseline gutter — always visible in diff mode, or only on changed hunks?
- 🔷 ⏳ **Unapprove** control placement — bar, diff hunk, history list, changes menu; must **not** be “use undo”.
- 🔷 ⏳ **Changes-list menu** — home for approve all, reject all, revert last bulk action?

### Working notes (not decisions)

- 💩 “Approved head” pointer on `filebase` (successor to old `last_approved_copy_path` idea) — one canonical path or blob id for “what user has signed off on”.
- 💩 Diff UI might show **two** baselines in labels: “vs last approved” and “vs this write’s backup” — clarify whether one diff or stacked sessions.
- 💩 Partial apply may need **`PatchApplier`** ([`done/5.2-DONE-diff-match-patch-simple-port.md`](done/5.2-DONE-diff-match-patch-simple-port.md)) on daemon side when persisting intermediate state, not only `Differ` in the editor.
- 💩 **`file_history` row types** for `approved`, `unapproved`, `partially_applied` — may be needed so rollback is data-driven, not undo-stack-driven.
- 💩 **`bulk_approval_id`** (or batch timestamp) on daemon — group rows approved in one “approve all” so revert bulk is one operation.

### Out of scope until design closes

- 🔷 ⏳ **Diff UI** — layout, partial-approve affordances, interaction model (not designed yet).
- 🔷 ⏳ Per-chunk popover UI promised as “later” in 2.10.4.25 — may merge into this plan once baseline rules exist.

---

## Implementation spec

ℹ️ **No code fences in this plan** — interface and approval model are not designed yet.

- 🔷 ⏳ After **Design — approval baseline** and **diff UI** are closed, add a follow-on plan section (or sub-plan) with **Remove / Replace with / Add** fences per `docs/guide-to-writing-plans.md`.
- ℹ️ Likely touch points when spec exists: `ollmfilesd/FileHistory.vala`, `libocfiles/FileHistory.vala`, `liboccoder/SourceView.vala`, `resources/style.css` — names only; no proposals until then.
- ℹ️ Diff engine in tree: `OLLMfiles.Diff.Differ` ([`done/5.2-DONE-diff-match-patch-simple-port.md`](done/5.2-DONE-diff-match-patch-simple-port.md)); hunk merge reference: [`examples/oc-diff.vala`](../../examples/oc-diff.vala).

---

## LLM notes

- 🚫 **No code fences** in this plan until user closes design + UI.
- 🚫 Conflate **approve / unapprove** with GtkSource **undo/redo** or buffer edit history.
- 🚫 **Approve all** / **reject all** as primary header buttons beside everyday editor controls.
- 🚫 Do not implement daemon RPC, `SourceView` diff mode, or CSS from this document as it stands.
- 🚫 Do not add duplicate approve/reject in the editor body until UI design closes (bar/menu placement TBD).
- ℹ️ When spec is added later: prefer `OLLMfiles.Diff.Differ`; see [`examples/oc-diff.vala`](../../examples/oc-diff.vala).
