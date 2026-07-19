# Composer chrome: expand on fit, collapse only when empty

> Pointer: `docs/bug-fix-process.md` (emoji + code fences). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✅ FIXED — user confirmed

**Started:** 2026-07-19

**Process:** `docs/bug-fix-process.md`

**Related:**

- ℹ️ Plan: `docs/plans/1.30-chat-input-composer.md`
- ℹ️ `docs/bugs/done/2026-07-18-FIXED-composer-plus-no-resize.md` — height fit works; chrome flip is separate
- ℹ️ `docs/bugs/done/2026-07-16-FIXED-composer-expanded-height.md` — `ScrolledView` owns height
- ℹ️ `libollmchatgtk/ChatInput.vala` — `is_expanded` / `expanded_changed` / side play
- ℹ️ `libollmchatgtk/ScrolledView.vala` — `buffer_change` / `content_height` / `use_peer`

---

## Purpose

- **🔷** `✔️` After paste / previous-chat fill / wrap: height already grows, but compact↔expanded **chrome** must flip (side play → footer) when content needs more than one visual line.
- **🔷** `✔️` Collapse chrome only when the composer text is **empty** — never because line count went back to one.
- **🔷** `✔️` One-shot hysteresis: up anytime; down only on empty (avoids expand/collapse oscillation).
- **ℹ️** Coding standards: `docs/coding-standards.md` via router when implementing.

---

## Problem

### Symptom A — fill / paste / wrap

- **🔷** Programmatic fill (previous chat / plus) or paste that soft-wraps: `ScrolledView` resizes height correctly.
- **🔷** Side play stays on the right; footer play does not take over (`is_expanded` / `expanded_changed` never goes true).
- **🔷** Expected: once content needs a second visual line, expand chrome (hide side play, show footer play).

### Symptom B — delete sweet spot (oscillation risk)

- **🔷** Expanded = full width (no side play). Compact = narrower (play eats width).
- **🔷** Text can be one visual line at full width, but wrap again if collapsed — bidirectional auto-flip would loop.
- **🔷** Expected: once expanded, stay expanded while any text remains; return to compact only when empty.

---

## Current behaviour

- **ℹ️** `ChatInput` decides chrome in `buffer.changed` and `update_entry` via:
  - `text.contains("\n")`, else
  - pango width vs `get_width() - play_w - margins`
- **ℹ️** Both directions: `want_expanded` false collapses; true expands.
- **ℹ️** `update_entry` sets `syncing` around buffer writes → `buffer.changed` chrome path skipped; chrome sync runs inline, often before width/yrange is ready.
- **ℹ️** Later `queue_fit` / `buffer_change` grows height but does not re-drive chrome.

---

## Root cause

- **✔️** Chrome is driven by an early pango / `\n` heuristic, not by the same post-layout fit that already knows one-line vs multi-line (`use_peer` / `content_h` in `ScrolledView.buffer_change`).
- **✔️** Bidirectional chrome from that heuristic fights width change when side play shows/hides (the sweet-spot loop).

---

## Proposed behaviour

- **🔷** Signal name: `lines_changed(int lines)`.
- **🔷** Line band after fit (computed only in `ScrolledView` from `end_off` / `use_peer`):
  - `0` — empty buffer (`end_off == 0`)
  - `1` — has content, one visual line (`use_peer`)
  - `2` — more than one visual line
- **ℹ️** Empty and “typing one line” both look like a peer-height row. The `0` vs `1` split is only so collapse happens on empty, not on shrink-to-one-line. That distinction lives in `ScrolledView`, not in `ChatInput`.
- **🔷** `ChatInput` must **not** use buffer / char count / pango / `\n` for chrome or placeholder.
- **🔷** `ChatInput` reacts only to `lines_changed` (shortest cases first):
  - placeholder: `lines == 0`
  - `lines == 1` → return
  - `lines == 0 && !expanded` → return
  - `lines == 0` → collapse
  - else (`lines > 1`) → if not expanded → expand
- **🔷** Remove the `buffer.changed` handler body that decided chrome (and placeholder). `update_entry` only writes the buffer + `focus_idle`; UI follows the later `lines_changed`.
- **🚫** Do not collapse on `lines == 1`.
- **🚫** Do not reintroduce Entry↔TextView flip.

---

## Proposed fix (code)

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `libollmchatgtk/ScrolledView.vala` — `lines_changed` + emit after fit

**Why:** One signal carries empty / one-line / multi for chrome hysteresis.

**Where:** class body (signal); end of `buffer_change` after `content_height` assignment on the successful yrange path.

**Depends on:** none.

#### Add — signal on class (after `line_peer` property)

Where: after `public Gtk.Widget? line_peer { get; set; default = null; }`.

What: notify listeners of line band after fit.

```vala
		/**
		 * After TextView yrange fit: {@link content_height} updated.
		 * {@code lines}: 0 empty, 1 one visual line, 2 more than one.
		 */
		public signal void lines_changed(int lines);
```

#### Add — emit whenever `buffer_change` knows a line band

**Trigger (not key-up):** `Gtk.TextBuffer.changed` → Idle `buffer_change` (same path as height fit). Covers typing, backspace, cut, paste, and programmatic `update_entry` buffer writes. `queue_fit` / width re-fit also call `buffer_change`.

**Certainty:**
- **✔️** Every buffer mutation schedules fit; cut/clear do too.
- **ℹ️** Emit is not “every key-up” — only when `buffer_change` finishes a pass that knows `end_off` / `use_peer`.
- **🔷** Must emit on the successful yrange path **and** on the empty interim peer path (layout not ready, `end_off == 0`) so clear/cut-to-empty still collapses chrome.
- **🔷** When layout not ready and `end_off > 0`: keep `need_fit`; do **not** emit a fake `1`/`2` — wait for the later successful pass (`vadjustment.changed` already re-calls `buffer_change`).

Where: (a) successful path after `content_height = target`; (b) empty branch of the `h0 < 1 || line_h < 1` block before `return false`.

What: `0` / `1` / `2`.

**Keep** — start of not-ready block (unchanged):

```vala
			if (h0 < 1 || line_h < 1) {
				if (peer_h > 0) {
					this.content_height = peer_h;
					this.pin_end = false;
					this.vadjustment.value = 0;
				}
				if (end_off > 0) {
					this.need_fit = true;
					return false;
				}
				this.need_fit = false;
```

**Add** — before empty `return false` / `return true` in that block:

```vala
				this.lines_changed(0);
```

**Add** — successful path, after `yrange_h <= target` block, before `return false`:

```vala
			this.lines_changed(end_off == 0 ? 0 : (use_peer ? 1 : 2));
```

---

### 2. `libollmchatgtk/ChatInput.vala` — UI only from `lines_changed`

**Why:** Empty vs one-line vs multi is `ScrolledView`’s job. `ChatInput` must not re-read the buffer for chrome or placeholder.

**Where:** `construct` — replace `buffer.changed` chrome block with `lines_changed`; strip chrome/placeholder from `update_entry`.

**Depends on:** §1.

#### Add — connect `scrolled.lines_changed` (after `line_peer` assign)

Where: after `this.scrolled.line_peer = this.inline_play;`, **replace** the whole `this.buffer.changed.connect(…)` registration (remove that connect).

What: placeholder + chrome from `lines` only.

```vala
			this.scrolled.lines_changed.connect((lines) => {
				this.placeholder.visible = lines == 0;
				if (lines == 1) {
					return;
				}
				if (lines == 0 && !this.is_expanded) {
					return;
				}
				if (lines == 0) {
					this.is_expanded = false;
					this.inline_play.visible = true;
					this.remove_css_class("is-expanded");
					this.expanded_changed(false);
					return;
				}
				if (this.is_expanded) {
					return;
				}
				this.is_expanded = true;
				this.inline_play.visible = false;
				this.add_css_class("is-expanded");
				this.expanded_changed(true);
			});
```#### Remove — entire `buffer.changed.connect` handler

```vala
			this.buffer.changed.connect(() => {
				if (this.syncing) {
					return;
				}
				Gtk.TextIter start_iter;
				Gtk.TextIter end_iter;
				this.buffer.get_start_iter(out start_iter);
				this.buffer.get_end_iter(out end_iter);
				var text = this.buffer.get_text(start_iter, end_iter, false);
				this.placeholder.visible = this.buffer.get_char_count() == 0;
				/* Compact vs expanded: inline below (same as update_entry). */
				var want_expanded = text.contains("\n");
				if (!want_expanded && this.get_width() > 0) {
					var play_min = 0;
					var play_nat = 0;
					this.inline_play.measure(Gtk.Orientation.HORIZONTAL, -1,
						out play_min, out play_nat, null, null);
					var play_w = play_nat > 0 ? play_nat : play_min;
					var avail = this.get_width() - play_w
						- this.text_view.left_margin - this.text_view.right_margin;
					if (avail > 0) {
						var layout = this.text_view.create_pango_layout(text);
						var text_w = 0;
						var text_h = 0;
						layout.get_pixel_size(out text_w, out text_h);
						want_expanded = text_w > avail;
					}
				}
				if (want_expanded == this.is_expanded) {
					return;
				}
				this.is_expanded = want_expanded;
				this.inline_play.visible = !want_expanded;
				this.remove_css_class("is-expanded");
				if (want_expanded) {
					this.add_css_class("is-expanded");
				}
				this.expanded_changed(want_expanded);
			});
```

#### Remove — placeholder + chrome in `update_entry`

```vala
			this.placeholder.visible = text.length == 0;

			var want_expanded = text.contains("\n");
			if (!want_expanded && this.get_width() > 0) {
				var play_min = 0;
				var play_nat = 0;
				this.inline_play.measure(Gtk.Orientation.HORIZONTAL, -1,
					out play_min, out play_nat, null, null);
				var play_w = play_nat > 0 ? play_nat : play_min;
				var avail = this.get_width() - play_w
					- this.text_view.left_margin - this.text_view.right_margin;
				if (avail > 0) {
					var layout = this.text_view.create_pango_layout(text);
					var text_w = 0;
					var text_h = 0;
					layout.get_pixel_size(out text_w, out text_h);
					want_expanded = text_w > avail;
				}
			}
			if (want_expanded != this.is_expanded) {
				this.is_expanded = want_expanded;
				this.inline_play.visible = !want_expanded;
				this.remove_css_class("is-expanded");
				if (want_expanded) {
					this.add_css_class("is-expanded");
				}
				this.expanded_changed(want_expanded);
			}
			GLib.Idle.add(this.focus_idle);
```

#### Replace with — write buffer only; UI via later `lines_changed`

```vala
			GLib.Idle.add(this.focus_idle);
```

`focus_idle` → `queue_fit` → `buffer_change` → `lines_changed` sets placeholder + chrome.
---

## Verify

- **✅** User confirmed fixed.

---

## Attempts / changelog

- **✔️** Renamed signal to `lines_changed`; band is `0` / `1` / `2` so chrome is signal-only.
- **✔️** Applied: `ScrolledView.lines_changed` emit; `ChatInput` chrome/placeholder from signal only; build OK.
- **✅** Archived to `docs/bugs/done/2026-07-19-FIXED-composer-chrome-hysteresis.md`.
