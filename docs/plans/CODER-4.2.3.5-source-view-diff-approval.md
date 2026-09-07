# 4.2.3.5 — SourceView diff Phase 4: block approval flow

**Status:** **✔️** Phase A **agent-done** (mock UI on `oc-test-source-diff`) · awaiting user smoke **✅** · Phase B not started

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
│ « 2 / 5 ▾»  │  [gap][hunk][gap][hunk]…                   │  (hover)     │
└──────────────┴────────────────────────────────────────────┴──────────────┘
```

**Left — file nav (stub):** prev / next + `n / N` label; **hover popover** lists pending files (Phase A: CLI pair basenames from harness; same interaction as header [`Approvals`](../../liboccoder/Approvals.vala) task-due hover list — Phase B wires **`ReviewFiles`** and removes top popover).

**Right — bulk actions (stub):** visible **Bulk actions** label; **hover popover** (not click dropdown) with “Accept all this file” → grey all bands in memory; overlay hides.

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

**Right — bulk actions:** see **Left — file nav** block above (hover popover spec).

### Ownership

**`OLLMcoder.Diff.ReviewBar`** (one file to start) — footer shell, Cairo hunk map, mock decision list, active hunk index, file-nav stub, hooks for centre Accept/Reject overlay. **`SourceView`** keeps buffer / gutter only.

### SourceView vs ReviewBar (agent boundary)

**`SourceView`** (inline diff view — [`4.2.3.4`](done/CODER-4.2.3.4-DONE-source-view-diff-view.md); **not** Phase A review work):

- **`show_diff(Differ)`** — interleaved buffer, `diff-add` / `diff-remove` tags, baseline gutter
- **`navigate_to_line`**, **`clear_diff`**
- 🚫 **No** review state, hunk-index tracking, hunk display ranges, focus/dim tag variants, or **`set_review_*`** APIs

**`ReviewBar`** (**current Phase A work**):

- Footer bands, overlay, in-memory decisions, file nav, bulk menu, accept/reject preview (`sync_diff_from_decisions` rebuilds effective baseline/current and calls **`show_diff`**)
- **✔️** Active hunk **border on footer band**
- **⏳** Active hunk **in-buffer** indicator (dim non-selected / emphasize selected changed lines) — **ReviewBar** owns this if we add it; via ReviewBar logic and public buffer access only, **not** by extending **`SourceView.show_diff`**

ℹ️ **Agent reminder:** If the user mentions in-text hunk highlighting, dimming unchanged hunks, or “indicator on the text” — that is **in this plan under ReviewBar**, not SourceView. Say that explicitly; **do not** add review fields or helpers to **`SourceView.vala`**. We are working on **ReviewBar**; SourceView diff view is settled unless a separate diff-view bug is filed.

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
| [`liboccoder/Diff/ReviewBar.vala`](../../liboccoder/Diff/ReviewBar.vala) | **`Diff.ReviewBar`** | **✔️** **Only new Vala file for Phase A.** Footer three zones, hunk bands (Cairo), mock state, stub file nav / bulk; centre overlay child exposed as **`review_overlay`**. |

| Also (minimal) | Change |
| --- | --- |
| [`liboccoder/meson.build`](../../liboccoder/meson.build) | **✔️** Add **one** `Diff/ReviewBar.vala` to `occoder_src` |
| [`examples/oc-test-source-diff.vala`](../../examples/oc-test-source-diff.vala) | **✔️** Vertical **`Gtk.Box`**: **`Gtk.Overlay`**(`SourceView` + **`ReviewBar.review_overlay`**) + **`ReviewBar`** footer; **`ReviewBar(source_view, differ, …)`** after `show_diff`. |
| [`resources/style.css`](../../resources/style.css) | **✔️** `.oc-diff-review-bar`, `.oc-diff-pending-label`, `.oc-diff-review-overlay`, `.oc-diff-hunk-map`, `.oc-diff-hunk-gap` |

ℹ️ **Split extra types/files:** **user review after Phase A smoke** — not an automated or agent decision. Do **not** create `Manager.vala`, `HunkMap.vala`, `ReviewOverlay.vala`, `HunkBand.vala` up front.

### Mock data

- **Hunks:** real **`Differ(baseline, current)`** from CLI args.
- **Decisions:** in-memory list inside **`ReviewBar`** (parallel to **`Differ.patches`**).
- **File nav / inactive:** flags above — no **`ProjectManager`**, no **`ReviewFiles`**.

### Implementation order (Phase A)

1. **✔️** **🔷** Fence **one file** — **`Diff.ReviewBar`** (footer + hunk map + overlay + mock state).
2. **✔️** **🔷** Wire **`oc-test-source-diff`**; smoke bands, border, Accept/Unapprove.
3. **⏳** **💩** **You** review smoke; split into extra types/files only if **you** ask for it — agents do not split proactively.

### Done when (Phase A)

**Agent:** all bullets below implemented and compile-clean. **User:** run smoke test and promote to **✅**.

- **✔️** Proportional hunk bands from real **`Differ.patches`**; active hunk **border**; click band → border moves + scroll.
- **✔️** Centre **Accept** / **Reject** / **Unapprove** overlay on **`SourceView`**; Accept advances to next pending hunk without moving mouse.
- **✔️** Accept/Reject → grey band; **Unapprove** on grey → pending colours back.
- **✔️** Stub file nav (**`--mock-files=N`**) and inactive middle (**`--mock-inactive`**) behave as stubbed.
- **✔️** Bulk actions stub greys all bands in memory.
- **⏳** User smoke on a display confirms interaction feels right.

ℹ️ **Implementation notes (vs reference blocks above):** single generic **`map_row`** click handler + **`HunkList.index_at`** (sort-by-distance on copy) instead of per-band **`GestureClick`**; layout on **`notify["width"]`** via **`on_width()`**; Cairo in **`draw_hunk_band()`**.

### Test (Phase A)

Build (from repo root):

```bash
meson compile -C build occoder examples/oc-test-source-diff
```

**Basic smoke** — diff view + footer bands + overlay (needs a display):

```bash
./build/examples/oc-test-source-diff \
  tests/source-diff/hello-baseline.txt \
  tests/source-diff/hello-current.txt
```

**Check:**

- Footer shows proportional coloured bands with square gaps; one band has an active **border**.
- Click another band → border moves; editor scrolls to that hunk.
- Click **Accept** repeatedly (mouse stays on overlay) → each hunk greys; border advances.
- Click a grey band → **Unapprove** appears; restore pending colour.
- **Reject** greys and advances like Accept.
- **Bulk actions** greys all bands; overlay hides.

**Mock file nav (single pair, stub count):**

```bash
./build/examples/oc-test-source-diff --mock-files=5 \
  tests/source-diff/hello-baseline.txt tests/source-diff/hello-current.txt
```

- Footer left shows **`File 1 of 5`**; prev/next cycle stub index (no real file switch).

**Two real file pairs (footer nav + switch diff):**

```bash
./build/examples/oc-test-source-diff \
  tests/source-diff/hello-baseline.txt tests/source-diff/hello-current.txt \
  tests/source-diff/insert-only-baseline.txt tests/source-diff/insert-only-current.txt
```

- Footer shows **`File 1 of 2`** / **`File 2 of 2`**; prev/next loads each pair.
- **Single pair:** entire file nav (label + buttons) **hidden** — no **`File 1 of 1`**.

**Inactive middle:**

```bash
./build/examples/oc-test-source-diff --mock-inactive --mock-files=5 \
  tests/source-diff/hello-baseline.txt tests/source-diff/hello-current.txt
```

- Red **`5 changes pending review`** instead of bands; click label → bands appear, mock file **`File 1 of 5`**.

### Still open (Phase A)

- **⏳** **💩** User smoke **✅** on the checks above.
- **⏳** **💩** Active-border colour & label padding polish if smoke finds gaps (min width / gap = **50% of strip height** is implemented).
- **⏳** **ReviewBar:** in-buffer active-hunk highlight (dim / emphasize changed lines) — **not** SourceView; design + implement in **`ReviewBar.vala`** only when user approves approach.
- **⏳** Smoke fixes in progress: hunk map visibility, overlay position, bulk menu, file nav hidden when one file, two-pair CLI on **`oc-test-source-diff`**.
- **⏳** Accept/Reject **diff preview** (rebuild **`show_diff`** after each decision) — **removed** unauthorized **`sync_diff_from_decisions`** / **`load_diff`** helpers; needs **user-named** approach in **`ReviewBar`** before re-adding.

### LLM notes (Phase A)

- **✔️** Phase A Vala landed in **`ReviewBar.vala`** + test harness (Phase B still 🚫).
- ℹ️ **SourceView boundary:** review hunk tracking / in-text highlight belongs in **ReviewBar** (see **SourceView vs ReviewBar** above). Wrong experiment reverted — do not re-add to **`SourceView.vala`** without explicit user approval.
- 🚫 **`ReviewBar` helpers** unless **user or plan names them** — approved: **`on_width()`**, **`draw_hunk_band()`**, **`on_accept_clicked()`**, **`on_reject_clicked()`**, **`on_map_clicked()`**; do **not** add **`sync_*`**, **`load_*`**, **`ensure_*`**, etc. without approval.
- 🚫 Daemon, **`file_diff_part`**, disk writes, **`ReviewFiles`**, **`Approvals`** changes.
- 🚫 Gutter / inline-buffer Accept/Reject as primary UI.
- 🚫 Accept/Reject chrome on footer band (breaks rapid accept).
- 🚫 Pre-splitting into extra files before first smoke.
- 🚫 Agent/automated split of **`ReviewBar.vala`** (e.g. “file too long”) — split is **your** call after review.
- 🚫 Adding review-state fields, hunk display ranges, or **`set_review_*`** to **`SourceView`** — **ReviewBar** only (see **SourceView vs ReviewBar**).

### Agent session note (ReviewBar vs SourceView)

When the user asks about **in-text hunk highlighting**, **dimming non-active hunks**, or similar editor-buffer styling during Phase A smoke:

1. Confirm it is **planned under ReviewBar** (see **SourceView vs ReviewBar** and **Still open** above), **not** SourceView.
2. **`SourceView`** is limited to **`show_diff` / `navigate_to_line` / `clear_diff`** for this sub-plan.
3. Current implementation work is **`ReviewBar.vala`** + **`oc-test-source-diff`** harness — do not expand **`SourceView.vala`** for review chrome.

---

## Phase B — Product wire

**Goal:** Same chrome as Phase A, backed by real pending review state — **`file_diff_part`**, daemon RPC, **`ReviewFiles`**, disk on reject.

**Depends on:** Phase A UI **✔️** agent-done; user smoke **✅** on **`oc-test-source-diff`** before product wire.

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

- 🚫 Vala fences for **Phase B** until Phase A user **✅**.
- 🚫 Duplicate approve/reject in editor body until placement closed.
- 🚫 Split **`ReviewBar.vala`** into more files without explicit user request after Phase A review.
- ℹ️ Touch points when spec exists: `liboccoder/Diff/ReviewBar.vala`, `SourceView.vala`, `Approvals.vala`, `ollmfilesd/FileHistory.vala`, `FileDiffPart.vala`.
