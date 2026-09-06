# 4.2.3.5 — SourceView diff Phase 4: block approval flow

**Status:** **⏳** design — **UI settled** · **Phase A next** (mock UI on `oc-test-source-diff`) · Vala fences after sign-off

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan.**

**Parent:** [`CODER-4.2.3-URGENT-source-view-diff.md`](CODER-4.2.3-URGENT-source-view-diff.md)

**Depends on:** [`done/CODER-4.2.3.4-DONE-source-view-diff-view.md`](done/CODER-4.2.3.4-DONE-source-view-diff-view.md) (and earlier phases)

**Contract reference:** parent **Design — user walkthrough** + **SQLite model** + [`CODER-4.2.3.1`](CODER-4.2.3.1-source-view-diff-walkthrough-hello.md)

**Pointer:** `docs/guide-to-writing-plans.md` — Checklist for plans

---

## Overview

| Phase | Focus | Where it runs |
| --- | --- | --- |
| **A** | Footer bar + hunk map + centre Accept/Reject overlay; **in-memory** decisions | [`oc-test-source-diff`](../../examples/oc-test-source-diff.vala) |
| **B** | Wire to **`ReviewFiles`**, **`file_diff_part`**, daemon; move changed-files list from header **`Approvals`** | Product `SourceView` / editor |

🔷 **Chosen UI:** footer **overview bar** (not gutter icons, not inline per-hunk toolbars). **One new review-chrome type** in **`liboccoder`** — not more logic in **`SourceView`**. Extra files only if **you** review Phase A and decide to split — not an agent or size heuristic.

ℹ️ **Paint pattern:** proportional segments on **`Gtk.DrawingArea`** (Cairo fills + click hit-test + min segment width) — same idea as a progress strip, not a stock GTK widget.

🚫 **Rejected alternatives:** gutter icons per hunk; inline buffer toolbars; context-menu-only (see git history / earlier draft if needed).

---

## Phase A — Mock UI on `oc-test-source-diff`

**Goal:** Ship footer bar + centred Accept/Reject overlay and prove interaction with **fake state**, before daemon / **`file_diff_part`**.

ℹ️ Harness today: two CLI files → **`SourceView.show_diff(Differ)`**. Phase A adds review chrome underneath; decisions stay in memory.

### Settled UI (Phase A scope)

Footer **diff control bar** — three zones:

```
┌──────────────┬────────────────────────────────────────────┬──────────────┐
│ File nav     │  Hunk overview (proportional bands)        │ Bulk actions │
│ « 2 / 5 »    │  [gap][hunk][gap][hunk]…                   │  (stub)      │
└──────────────┴────────────────────────────────────────────┴──────────────┘
```

**Left — file nav (stub):** prev / next + `n / N` label only. Mock queue (e.g. **`2 / 5`**, CLI **`--mock-files=5`**). **No** real popover list yet — fake basenames; prev/next cycle mock index.

**Middle — hunk map:** proportional bands from real **`Differ.patches`** for the two smoke files.

- Pending add-only: **green**; remove-only: **red**; mixed: **red+green**.
- Decided: **grey** (Accept/Reject in memory only — **no disk write**).
- **Active hunk:** **border** around that band’s square (high-contrast outline; not colour alone).
- Strip **height** follows label / footer row (natural label height + border padding).
- **Min band width** = **50% of strip height** (square-ish minimum; clamp proportional widths to this).
- **White gaps:** fixed width — same as min band width (square gap), do not scale with unchanged spans.
- Label `12–18` when wide enough; else tooltip.
- **Inactive mock:** CLI **`--mock-inactive`** → no bands; red **`5 changes pending review`**; click → switch to mock oldest file + show bands.

**Centre overlay (on source view):** fixed Accept / Reject / Unapprove — **`Gtk.Overlay`** child, not on footer. Cursor-style rapid accept: buttons stay centred; after Accept, scroll to next pending hunk.

- Click pending band → jump + active border.
- Accept / Reject → grey band, auto-advance border (scroll may stub to log until wired).
- Click grey band → Unapprove → restore pending colour.
- **No** Next/Previous hunk buttons — map + border + auto-advance replace them.

**Right — bulk actions (stub):** visible label; menu optional (“Accept all this file” → grey all bands in memory).

### Ownership

**`OLLMcoder.Diff.ReviewBar`** (one file to start) — footer shell, Cairo hunk map, mock decision list, active hunk index, file-nav stub, hooks for centre Accept/Reject overlay. **`SourceView`** keeps buffer / gutter only.

Middle strip: **`Gtk.Box`** row of band widgets (preferred) or one **`DrawingArea`**; **`layout_hunk_map()`** on resize/state change; per-band click wired at build time — no linear hit-test scan.

### Reference — Cairo hunk strip (adapt, do not copy verbatim)

ℹ️ Existing in-tree pattern: proportional coloured segments on a fixed-height **`Gtk.DrawingArea`**, label on top via **`Gtk.Overlay`**, **`queue_draw()`** when counts change. Diff hunk map **extends** that with: fixed-width **gap** squares between hunks (not proportional silence), **min band width = half strip height**, **active hunk stroke**, and **per-hunk click** without scanning all bands on every click.

**Sizing** — strip height from label row; min width derived from height (not a magic pixel constant):

```vala
// hunk_map_height: label natural height (+ padding / border) for the footer row
private int hunk_map_height { get; set; default = 28; }   // set from label after realize if needed

private double min_band_width {
	get { return (double) this.hunk_map_height * 0.5; }
}

private double gap_width {
	get { return this.min_band_width; }   // square white gaps between hunks
}
```

**Click target (preferred)** — one **`Gtk.DrawingArea`** (or button) per hunk in a horizontal **`Gtk.Box`**, fixed-width gap widgets between; hunk index captured in each widget’s **`GestureClick`** at build time. GTK routes the click — **no hit-test loop**:

```vala
private Gtk.Box hunk_map_row;

private void rebuild_hunk_map_row(int map_width)
{
	// clear hunk_map_row children; layout_hunk_map(map_width) -> band_width[] 
	for (var i = 0; i < this.hunks.size; i++) {
		if (i > 0) {
			this.hunk_map_row.append(new Gtk.Box() { width_request = (int) this.gap_width });
		}
		var index = i;
		var band = new Gtk.DrawingArea() {
			width_request = (int) this.band_widths[i],
			content_height = this.hunk_map_height,
		};
		band.set_draw_func((area, cr, w, h) => {
			this.paint_one_hunk_band(cr, w, h, index);
		});
		var click = new Gtk.GestureClick();
		click.pressed.connect((n, x, y) => {
			this.set_active_hunk(index);
		});
		band.add_controller(click);
		this.hunk_map_row.append(band);
	}
}
```

**Layout pass** (on resize / hunk decision change — **not** inside paint, **not** on click):

```vala
private double[] band_starts = {};
private double[] band_widths = {};

private void layout_hunk_map(int map_width)
{
	// compute band_widths[] + band_starts[] once; clamp each width >= min_band_width; subtract gap_width * gaps
	// rebuild_hunk_map_row(map_width) when widths change
}
```

**Paint one band** (called from each band widget’s draw func, or single area if kept):

```vala
private void paint_one_hunk_band(Cairo.Context cr, int width, int height, int index)
{
	var hunk = this.hunks[index];
	this.set_hunk_band_color(cr, hunk.decision, hunk.kind);
	cr.rectangle(0.0, 0.0, (double) width, (double) height);
	cr.fill();
	if (index == this.active_hunk_index) {
		cr.set_source_rgb(0.0, 0.0, 0.0);
		cr.set_line_width(2.0);
		cr.rectangle(1.0, 1.0, (double) width - 2.0, (double) height - 2.0);
		cr.stroke();
	}
}
```

**Single `DrawingArea` fallback only** — if you keep one canvas, **`layout_hunk_map()`** fills monotonic **`band_starts[]`**; click uses **binary search** on starts (O(log n)), **not** a linear foreach:

```vala
private int hit_test_hunk_binary(double x)
{
	// band_starts[] sorted ascending — bisect to find largest i where band_starts[i] <= x
	// return -1 if x falls in a gap square
}
```

🚫 **Do not** linear-scan all hunks on every click.

**Centre Accept/Reject overlay** — separate from footer; fixed on source view:

```vala
private Gtk.Overlay editor_overlay;
private Gtk.Box review_actions;   // Accept, Reject, Unapprove — centre via valign/halign CSS or align widget

// editor_overlay.set_child(source_view);
// editor_overlay.add_overlay(review_actions);
// review_actions.add_css_class("oc-diff-review-overlay");
```

ℹ️ Colours: use theme/CSS tokens at implement time — reference uses placeholder rgba loop pattern only.

### Proposed files (Phase A — start with one)

**Namespace:** **`OLLMcoder.Diff`** (not **`OLLMfiles.Diff`**).

| File | Type | Role |
| --- | --- | --- |
| [`liboccoder/Diff/ReviewBar.vala`](../../liboccoder/Diff/ReviewBar.vala) | **`Diff.ReviewBar`** | **Only new Vala file for Phase A.** Footer three zones, hunk bands (Cairo), mock state, stub file nav / bulk; builds or hosts centre overlay. Enums/structs stay **in this file** until **you** choose to split after review. |

| Also (minimal) | Change |
| --- | --- |
| [`liboccoder/meson.build`](../../liboccoder/meson.build) | Add **one** `Diff/ReviewBar.vala` to `occoder_src` |
| [`examples/oc-test-source-diff.vala`](../../examples/oc-test-source-diff.vala) | Vertical **`Gtk.Box`**: **`Gtk.Overlay`**(`SourceView` + overlay child from **`ReviewBar`**) + **`ReviewBar`** footer; bind **`Differ`** after `show_diff`. |
| [`resources/style.css`](../../resources/style.css) | CSS classes **when needed** — not a prerequisite to first paint |

ℹ️ **Split extra types/files:** **user review after Phase A smoke** — not an automated or agent decision. Do **not** create `Manager.vala`, `HunkMap.vala`, `ReviewOverlay.vala`, `HunkBand.vala` up front.

### Mock data

- **Hunks:** real **`Differ(baseline, current)`** from CLI args.
- **Decisions:** in-memory list inside **`ReviewBar`** (parallel to **`Differ.patches`**).
- **File nav / inactive:** flags above — no **`ProjectManager`**, no **`ReviewFiles`**.

### Implementation order (Phase A)

1. 🔷 ⏳ Fence **one file** — **`Diff.ReviewBar`** (footer + hunk map + overlay + mock state).
2. 🔷 ⏳ Wire **`oc-test-source-diff`**; smoke bands, border, Accept/Unapprove.
3. 💩 **You** review smoke; split into extra types/files only if **you** ask for it — agents do not split proactively.

### Done when (Phase A)

Run **`oc-test-source-diff a b`** → proportional bands, **active hunk bordered**, click → border moves, Accept repeatedly without moving mouse, grey + Unapprove works. Optional: **`--mock-inactive`** / **`--mock-files`** behave as stubbed.

### Still open (Phase A)

- 🔷 ⏳ Sign-off on this scope before fences.
- 💩 Active-border colour & label padding — implement time (min width / gap = **50% of strip height** is settled).

### LLM notes (Phase A)

- 🚫 Vala fences until sign-off.
- 🚫 Daemon, **`file_diff_part`**, disk writes, **`ReviewFiles`**, **`Approvals`** changes.
- 🚫 Gutter / inline-buffer Accept/Reject as primary UI.
- 🚫 Accept/Reject chrome on footer band (breaks rapid accept).
- 🚫 Linear foreach hit-test over all hunks on every click (use per-band widgets or binary search on `band_starts[]`).
- 🚫 Pre-splitting into extra files before first smoke.
- 🚫 Agent/automated split of **`ReviewBar.vala`** (e.g. “file too long”) — split is **your** call after review.

---

## Phase B — Product wire

**Goal:** Same chrome as Phase A, backed by real pending review state — **`file_diff_part`**, daemon RPC, **`ReviewFiles`**, disk on reject.

**Depends on:** Phase A UI signed off and smoking on **`oc-test-source-diff`**.

### Adds on top of Phase A

**Persistence & disk**

- Accept → insert **`file_diff_part`** `accepted=1`; **no disk write**.
- Reject → undo hunk on **V_disk** + `accepted=0`.
- Unapprove → delete part row; overlay back; disk unchanged for prior accept.
- All hunks decided → **`file_history.reviewed=1`**.

**Left — file nav (real)**

- **`n / N`** over real pending files; queue **oldest pending change first** (by **`file_history`** write time).
- **Changed-files hover list** moves here from header **`Approvals`** (`next_button` popover) — same list, Approvals-style hover.
- **Remove** top popover when footer ships.
- Reconcile sort: today’s **`Approvals`** uses **`last_modified` descending** → footer uses **oldest-first**.

**Middle — inactive file (real)**

- User on non-pending file: grey bar, red **`N changes pending review`**.
- Click → open **oldest** pending file (`show_pending_diff`).

**Right — bulk actions (real)**

- Hover menu (not “overflow”): Unapprove all (file); Accept all pending files (confirm); destructive bulk per parent plan.
- Whole-file Reject (full **V_backup** restore) stays destructive — **`Approvals`** or bulk menu, not casual band click.

**Integration**

- Hook **`Diff.ReviewBar`** into **`show_pending_diff`** / editor shell (not test harness only).
- Header **`Approvals`:** strip changed-files popover; demote or relocate whole-file Approve/Reject ⏳.

### Still open (Phase B)

- 🔷 ⏳ Stacked LLM edit (**Flow B**) — review **H2** only; no carry-forward v1.
- 🔷 ⏳ Hunk file format at **`FileDiffPart.path`**.
- 🔷 ⏳ Unsaved dirty buffer while reviewing — **lean: no**.
- 🔷 ⏳ Header **`Approvals`** Approve/Reject vs footer relationship.
- 🔷 ⏳ Accept all files — confirm / revert semantics.
- 💩 Exact middle placeholder copy vs hide footer when zero pending.

### Implementation order (Phase B)

1. 🔷 ⏳ Real file nav + changed-files list (from **`Approvals`**) + inactive middle label + **Bulk actions** menu.
2. 🔷 ⏳ Daemon part RPCs; Reject → hunk apply on **V_disk**; Accept → **`file_diff_part`**.
3. 🔷 ⏳ Integrate **`show_pending_diff`**; strip header popover; wire remaining **`Approvals`** buttons.

### Done when (Phase B)

Pending file in editor → footer matches Phase A behaviour but persists; file nav across real queue; click **`N changes pending review`** opens oldest pending; reject writes disk; header no longer owns changed-files list.

### LLM notes (Phase B)

- 🚫 Rewrite disk on **accept**.
- 🚫 Approve / unapprove aliased to GtkSource undo/redo.
- 🚫 Accept all files as primary header button.
- 🚫 Carry-forward inside **`OLLMfiles.Diff`**.
- 🚫 Keep header changed-files popover after footer file nav ships.
- 🚫 “Overflow” naming in UI or docs.

---

## Shared LLM notes (both phases)

- 🚫 Vala fences until user signs off design.
- 🚫 Duplicate approve/reject in editor body until placement closed.
- 🚫 Split **`ReviewBar.vala`** into more files without explicit user request after Phase A review.
- ℹ️ Touch points when spec exists: `liboccoder/Diff/ReviewBar.vala`, `SourceView.vala`, `Approvals.vala`, `ollmfilesd/FileHistory.vala`, `FileDiffPart.vala`.
