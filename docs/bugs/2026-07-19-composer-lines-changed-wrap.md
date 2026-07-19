# Composer `lines_changed`: soft-wrap stays at 1

> Pointer: `docs/bug-fix-process.md` (emoji + code fences). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ⏳ OPEN — fix proposed (Android-common; desktop hard to repro)

**Started:** 2026-07-19

**Process:** `docs/bug-fix-process.md`

**Related:**

- ℹ️ `docs/bugs/done/2026-07-19-FIXED-composer-chrome-hysteresis.md` — `lines_changed` 0/1/2 from `use_peer`
- ℹ️ `docs/bugs/done/2026-07-18-FIXED-composer-plus-no-resize.md` — height from yrange vs peer
- ℹ️ `docs/bugs/2026-07-18-android-poc-completion.md` — Android composer / plus path
- ℹ️ `libollmchatgtk/ScrolledView.vala` — `buffer_change` / `lines_changed`
- ℹ️ `libollmchatgtk/ChatInput.vala` — chrome from `lines_changed` only

---

## Purpose

- **🔷** `lines_changed` must reflect **effective / visual** lines (soft wrap), not hard `\n` count.
- **🔷** Plus / programmatic fill that wraps to two visual lines must emit `2` so chrome expands.

---

## Problem

### Symptom

- **🔷** Plus Indicator fills a long single-paragraph string that **soft-wraps to two lines**.
- **🔷** Composer does **not** treat it as two lines (side play stays; footer chrome does not take over).
- **🔷** Expected: second visual line → `lines_changed(2)` → expand.
- **🔷** Common on **Android**; hard to see on **desktop**.

### Why desktop vs Android

- **ℹ️** Band `1` is `use_peer` (`content_h <= peer_h`), not “one glyph row”.
- **ℹ️** Desktop play button ≈ one text line → soft wrap usually pushes `content_h > peer_h` → luckily emits `2`.
- **ℹ️** Android touch-sized play button ≫ one text line + narrower width → two wrapped rows still `content_h <= peer_h` → emits `1` while text looks like two lines.

### Current code (band vs height)

- **ℹ️** Height fit: `use_peer = peer_h > 0 && content_h <= peer_h` (yrange paragraph height).
- **ℹ️** Signal: `lines_changed(end_off == 0 ? 0 : (use_peer ? 1 : 2))`.

---

## Evidence

### Code read

- **✔️** No `\n` heuristic in `ScrolledView` / `ChatInput` chrome path.
- **✔️** `content_h` comes from `get_line_yrange` (paragraph height, includes wrap per GTK).
- **✔️** `lines_changed` is tied to `use_peer`, not to “taller than one glyph row”.

### Runtime

- **✔️** Debug in `buffer_change` logs `content_h`, `peer_h`, `glyph_h`, `use_peer`, current `lines`.
- **ℹ️** Desktop repro may never show `content_h > glyph_h && use_peer` — that gap is the Android case.
- **⏳** Optional: confirm on Android APK with `--debug` / logcat after plus-fill.

---

## Root cause

- **✔️** Chrome band conflates **peer-row fit** (height chrome) with **visual line count**. On Android, peer taller than one text line → wrapped paragraph still `use_peer` → `lines=1`.

---

## Proposed fix

- **🔷** Keep `use_peer` for **viewport height** only.
- **🔷** Drive `lines_changed` from yrange vs **one glyph-row height** (`get_iter_location` at start):
  - `0` — `end_off == 0`
  - `1` — content, `content_h <= glyph.height`
  - `2` — `content_h > glyph.height`
- **🚫** Do not reintroduce pango / `\n` chrome heuristics in `ChatInput`.
- **🚫** Do not collapse on `lines == 1` (hysteresis unchanged).

### 1. `libollmchatgtk/ScrolledView.vala` — band from glyph height

**Where:** `buffer_change` successful path (after `content_h`; keep `use_peer` for margins / `target`).

**Depends on:** none.

#### Replace with — compute `lines` from glyph row; keep `use_peer` for height; drop temporary debug once verified

```vala
			this.need_fit = false;
			var content_h = y + line_h;
			Gdk.Rectangle glyph;
			this.text_view.get_iter_location(size_start, out glyph);
			/* yrange is paragraph height (GTK); peer only when content fits the play-button row. */
			var use_peer = peer_h > 0 && content_h <= peer_h;
			var lines = 0;
			if (end_off > 0) {
				lines = (glyph.height > 0 && content_h > glyph.height) ? 2 : 1;
			}
			GLib.debug(
				"scrolledview fit end_off=%d content_h=%d peer_h=%d glyph_h=%d use_peer=%s → lines=%d",
				end_off, content_h, peer_h, glyph.height, use_peer.to_string(), lines);
			if (use_peer) {
				var extra = peer_h - content_h;
				if (extra < 0) {
					extra = 0;
				}
				var top = extra / 2;
				this.text_view.top_margin = top;
				this.text_view.bottom_margin = extra - top;
			}
			if (!use_peer) {
				this.text_view.top_margin = 4;
				this.text_view.bottom_margin = 4;
			}
			var yrange_h = content_h + this.text_view.top_margin + this.text_view.bottom_margin;
			var target = use_peer ? peer_h : yrange_h;
			if (target < 1) {
				target = 1;
			}
			if (this.max_height > 0 && target > this.max_height) {
				target = this.max_height;
			}
			this.pin_end = this.text_view.buffer.cursor_position >= this.text_view.buffer.get_char_count();
			this.content_height = target;
			if (yrange_h <= target) {
				this.vadjustment.value = 0;
				this.pin_end = false;
			}
			this.lines_changed(lines);
			return false;
```

#### Replace with — signal docblock (class body)

```vala
		/**
		 * After TextView yrange fit: {@link content_height} updated.
		 * ''lines'': 0 empty, 1 one visual line (yrange ≤ glyph row), 2 more than one.
		 * Height may still use {@link line_peer} when content fits the play-button row.
		 */
		public signal void lines_changed(int lines);
```

---

## Attempts / changelog

- **✔️** 2026-07-19 — Bug log opened; diagnosis from code; debug added.
- **✔️** 2026-07-19 — User: hard on desktop, common on Android → peer vs glyph gap.
- **⏳** Apply Replace fences after approval; verify on Android; remove `GLib.debug`.

---

## Next

- **⏳** 🔷 Approve / apply §1.
- **⏳** 🔷 Android plus-fill: wrapped text expands chrome (`lines=2`).
- **⏳** Remove debug after ✅.
