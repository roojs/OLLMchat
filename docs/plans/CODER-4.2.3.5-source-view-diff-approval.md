# 4.2.3.5 — SourceView diff Phase 4: block approval flow

**Status:** **⏳** design — **UI settled**; **Phase A** = UI on `oc-test-source-diff` with dummy backing; Vala fences after sign-off

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan.**

**Parent:** [`CODER-4.2.3-URGENT-source-view-diff.md`](CODER-4.2.3-URGENT-source-view-diff.md)

**Depends on:** [`done/CODER-4.2.3.4-DONE-source-view-diff-view.md`](done/CODER-4.2.3.4-DONE-source-view-diff-view.md) (and earlier phases)

**Contract reference:** parent **Design — user walkthrough** + **SQLite model** + [`CODER-4.2.3.1`](CODER-4.2.3.1-source-view-diff-walkthrough-hello.md)

**Pointer:** `docs/guide-to-writing-plans.md` — Checklist for plans

---

## Purpose

- 🔷 Per-hunk **Accept** / **Reject** / **Unapprove** (Flows A, A1, D, E partial).
- 🔷 Insert / delete **`file_diff_part`** rows; set **`file_history.reviewed=1`** when every hunk decided.
- 🔷 Overlay off for decided hunks (accept = disk unchanged; reject = undo hunk on **V_disk**).
- 🔷 Footer **diff overview bar** as the primary per-hunk UI (not gutter buttons).
- 🔷 Named type **`DiffManager`** (or similar) owns hunk list + bar + overlay chrome — not more logic piled into `SourceView`.
- 🔷 Destructive / bulk actions live in a right-hand **Bulk actions** control (hover menu), not primary chrome.
- 🔷 **Accept** / **Reject** chrome is a **fixed overlay centred on the source view** so the pointer can stay put while hunks auto-advance (Cursor-style rapid accept).
- 🔷 **Phase A** first: prove the UI on [`examples/oc-test-source-diff.vala`](../../examples/oc-test-source-diff.vala) with **simple in-memory backing** (no daemon / `file_diff_part` yet).
- 🔷 ⏳ Vala **Remove / Replace / Add** fences only after user signs off this design pass.

---

## Approach discussion (pros / cons)

### A — Gutter icons per hunk

- 💩 Icon / button in the secondary gutter next to each green/red block.
- **Pros:** Affordance next to the change; familiar from some IDEs.
- **Cons:** Crowded gutter (baseline numbers already there); easy to miss small hunks; poor overview of “how many left”; hard on touch / narrow windows.
- 🚫 **Not chosen** as primary.

### B — Inline toolbar on the hunk in the buffer

- 💩 Floating Accept / Reject strip overlaid on the first line of each hunk.
- **Pros:** Immediate; no separate navigation chrome.
- **Cons:** Obscures code; repeats many times on large diffs; fights selection / copy; ugly when hunks are one line.
- 🚫 **Not chosen** as primary.

### C — Context menu / keyboard only

- 💩 Right-click hunk or shortcuts; no persistent overview.
- **Pros:** Clean editor chrome.
- **Cons:** Discoverability; no map of pending hunks; weak for “accept next” flow.
- 🚫 **Not chosen** as primary (shortcuts may be **later** add-on).

### D — Footer overview bar (settled)

- 🔷 Horizontal **footer** under the source view while diff-active / pending.
- 🔷 Middle = proportional **hunk bands** (red / green / red+green) separated by fixed-width **white** gaps (unchanged regions).
- 🔷 Click band → jump to that hunk; **Accept** / **Reject** stay in a **fixed centre overlay** on the source view (not on the footer band).
- 🔷 Decided hunk → **grey** band; click grey → centre overlay offers Unapprove (restore highlighting).
- 🔷 Hover tooltip with line range when bands are too narrow to label.
- **Pros:** Overview of whole file; emphasises change size; scales from few hunks to many; Accept-all / next-file fit naturally in the same bar; matches “where am I in the review” without Next/Back hunk buttons.
- **Cons:** Custom drawing / layout (not stock GTK); need min band width; must keep bar in sync with `show_diff` / `clear_diff` / part decisions.
- 🔷 **Chosen starting UI.**

ℹ️ **Precedent:** [app.Snappr2 `AutomationProgress`](file:///home/alan/gitlive/app.Snappr2/src/UI/AutomationProgress.vala) — `Gtk.DrawingArea` + Cairo proportional segments (done / pending / skipped), `Gtk.Overlay` + label on top; per-domain rows use the same paint pattern. Diff hunk bar should reuse that approach (segments = hunks; click hit-test; min width), not invent a new widget family. Related: [`ScanDepthMap`](file:///home/alan/gitlive/app.Snappr2/src/UI/ScanDepthMap.vala) for Cairo cell maps (less directly applicable — grid, not a 1D strip).

---

## Settled UI — footer diff control bar

### Layout (three zones)

```
┌──────────────┬────────────────────────────────────────────┬──────────────┐
│ File nav     │  Hunk overview (proportional bands)        │ Bulk actions │
│ « 2 / 10 »   │  [gap][hunk][gap][hunk]…                   │  (hover)     │
└──────────────┴────────────────────────────────────────────┴──────────────┘
```

- 🔷 **Left — file nav:** previous / next pending file; label like `2 / 10` (current index among pending files).
- 🔷 **Middle — hunk map:** one band per hunk that needs (or had) a decision; white fixed squares for gaps between hunks.
- 🔷 **Right — Bulk actions:** labelled control (e.g. “Bulk actions”) with a **hover** menu — same motion pattern as [`Approvals`](../../liboccoder/Approvals.vala) next-button popover. Name must signal multi-file / bulk ops; **do not** call it “overflow”.

### Hunk bands

- 🔷 **Pending add-only:** green band.
- 🔷 **Pending remove-only:** red band.
- 🔷 **Pending mixed (add+remove):** red+green (split / two-tone) band.
- 🔷 **Decided (accepted or rejected):** grey band.
- 🔷 **Current focus:** black outline / black box on the band for the hunk in view (or just acted on).
- 🔷 **Width:** proportional to hunk size (line count), down to a **minimum square**; white **gaps always fixed** width (do not grow with unchanged spans — emphasise diffs, not silence).
- 🔷 **Label:** when band is wide enough, text like `12–18`; otherwise tooltip on hover with line range / change type.

### Click / Accept–Reject overlay (centre of source view)

- 🔷 Click **pending** band (or auto-select first pending) → scroll/jump to that hunk; mark it current on the **footer** (black outline / bar on that band).
- 🔷 **Accept** / **Reject** live in a **fixed overlay centred on the source view** (stable screen position) — not floating above the footer band.
- 🔷 Goal: Cursor-style rapid accept — park the pointer on **Accept**; after Accept, view scrolls to the **next pending** hunk while buttons stay put → click Accept again without moving the mouse.
- 🔷 Prefer **overlay widget** over `Gtk.Popover` for that chrome (no grab-dismiss; position stays centre).
- 🔷 **Accept** → insert `file_diff_part` `accepted=1`; band → grey; jump to **next pending**; overlay stays centred.
- 🔷 **Reject** → undo hunk on **V_disk** + `accepted=0`; band → grey; jump to next pending.
- 🔷 Click **grey** band → same centre overlay shows **Unapprove** (delete part row; restore green/red; **V_disk** unchanged for prior accept).
- 🔷 **Accept all** (this file) → all pending bands → grey; still DB-only for accepts.

### Bulk actions (right)

- 🔷 Label **Bulk actions** (or similar) — hover to open menu (Approvals-style enter/leave), not a silent “⋯ overflow”.
- 🔷 Items (v1 candidates):
  - 🔷 Unapprove all (this file) — restore pending highlighting.
  - 🔷 Accept all changes in **all** pending files — **destructive-ish bulk**; confirm; only here.
  - 💩 Reject all / other bulk — only if we keep placement rules from parent **Destructive actions**.
- 🚫 Do not put Accept all files on the everyday left/middle chrome.
- 🚫 Do not use the word **overflow** for this control in UI copy or plan prose.

### What we skip in the bar

- 🔷 No dedicated **Next hunk** / **Previous hunk** buttons — the map + black current marker + auto-advance after Accept/Reject replace that.
- 🔷 Whole-file Reject (restore full **V_backup**) stays a **destructive** path (existing Approvals Reject or Bulk actions) — not a casual band action.

---

### DiffManager (ownership)

- 🔷 New type (working name **`DiffManager`**) owns:
  - Pending hunk list for the open file (from current `Differ` / patches + decision state).
  - Footer bar widget + band model.
  - Accept / Reject / Unapprove (Phase A: in-memory; later: daemon RPC).
  - Sync with `SourceView.show_diff` / `clear_diff` / `show_pending_diff`.
- 🔷 `SourceView` keeps buffer / gutter / navigate; does **not** grow another hundred lines of review chrome.
- ℹ️ Exact class name / file (`liboccoder/DiffManager.vala` vs nested under SourceView) — confirm at fence time.
- ℹ️ Middle strip paint: follow Snappr **`AutomationProgress.paint_pages_row`** / domain-row Cairo pattern (`DrawingArea` + width × fraction fills); add click coordinates → hunk index and min-band clamp for our gaps.

---

## Phase A — UI on `oc-test-source-diff` (dummy backing)

ℹ️ Harness today: [`examples/oc-test-source-diff.vala`](../../examples/oc-test-source-diff.vala) — two files → `SourceView.show_diff(Differ)`. No Approvals / RPC needed for this phase.

**Goal:** ship footer bar + centred Accept/Reject overlay and prove interaction with **fake state**, before wire to `file_diff_part`.

- 🔷 Build hunk model from the same `Differ.patches` already used by `show_diff` (line ranges, add/remove/mixed).
- 🔷 Simple backing: in-memory list of hunk decisions (`pending` / `accepted` / `rejected`) — e.g. `Gee.ArrayList` parallel to patches, or a tiny struct list owned by `DiffManager`.
- 🔷 Accept / Reject / Unapprove mutate that list only; **no** disk write, **no** daemon, **no** `file_diff_part`.
- 🔷 Accept → grey band + scroll to next pending; Reject → same UI path (still no disk in Phase A); Unapprove on grey → pending again.
- 🔷 Footer left: stub or hide file nav (`1 / 1`) for the single-file smoke.
- 🔷 Footer right: **Bulk actions** can be stubbed (Accept all this file = mark all pending accepted in memory) or minimal.
- 🔷 Wire into the test app after `show_diff` so the window shows bar + overlay.
- 🚫 Phase A does **not** require ProjectManager review_files, Approvals header changes, or hunk-file apply.

**Done when:** run `oc-test-source-diff a b` → see proportional bands, click → jump, Accept repeatedly without moving the mouse, grey + Unapprove works.

---

## Phase B — Product wire (after Phase A)

- 🔷 ⏳ Hook `DiffManager` into real `show_pending_diff` / Approvals file list.
- 🔷 ⏳ Persist Accept/Reject/Unapprove via daemon + **`file_diff_part`**.
- 🔷 ⏳ Reject writes **V_disk** (hunk apply); Accept stays DB-only.
- 🔷 ⏳ File nav `n / N` across pending files; Bulk actions for all-files accept + confirm.

---

## Still open (close before fences)

- 🔷 ⏳ Sign-off on this footer-bar UI + Phase A scope (this doc).
- 🔷 ⏳ Stacked LLM edit (**Flow B**) for v1 — review **H2** only; no carry-forward.
- 🔷 ⏳ Hunk file format at **`FileDiffPart.path`** (unified text vs serialised `Patch`) — Phase B.
- 🔷 ⏳ Unsaved dirty buffer while reviewing — **lean: no** (keep **V_backup** vs **V_disk** only).
- 🔷 ⏳ Relationship of header **Approvals** Approve/Reject to the new footer (demote header to file-level only? hide while footer visible?) — Phase B.
- 🔷 ⏳ Confirm / undo semantics for **Accept all files** — Phase B.
- 💩 Min band pixel size / colour tokens — polish at implement time.

---

## Suggested order (after sign-off)

### Phase A (dummy / smoke)

1. 🔷 ⏳ Fence **`DiffManager`** + footer shell + centred Accept/Reject overlay (dummy decisions).
2. 🔷 ⏳ Band model from `Differ.patches` + Cairo paint (Snappr-style) + click hit-test.
3. 🔷 ⏳ Accept / Reject / Unapprove on in-memory state; auto-advance; grey bands.
4. 🔷 ⏳ Wire [`oc-test-source-diff`](../../examples/oc-test-source-diff.vala); smoke until rapid Accept feels right.

### Phase B (product)

5. 🔷 ⏳ Left file nav `n / N` + right **Bulk actions** hover menu (real pending list).
6. 🔷 ⏳ Daemon part RPCs / hunk apply for Reject; Accept → `file_diff_part`.
7. 🔷 ⏳ Integrate with `show_pending_diff` / Approvals header relationship.

---

## LLM notes

- 🚫 Vala fences until user signs off Phase **4** design (this UI + open bullets).
- 🚫 Gutter Accept/Reject buttons as primary UI.
- 🚫 Inline per-hunk toolbars cluttering the buffer.
- 🚫 Approve / unapprove aliased to GtkSource undo/redo.
- 🚫 Accept all files as a primary header button.
- 🚫 Rewrite disk on **accept**.
- 🚫 Carry-forward logic inside **`OLLMfiles.Diff`**.
- 🚫 Accept/Reject chrome anchored to the footer band (breaks rapid Accept).
- 🚫 Calling the right control “overflow” in UI or docs.
- 🚫 Phase A daemon / `file_diff_part` / disk writes — UI + in-memory decisions only on `oc-test-source-diff`.
- 🚫 Emphasise white gap width with file proportion — gaps stay fixed squares.
