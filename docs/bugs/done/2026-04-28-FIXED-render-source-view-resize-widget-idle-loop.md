# FIXED: `RenderSourceView.resize_widget_callback` — unbounded idle reschedule (`for_width <= 0`, `REVEAL_BODY` + unrealized)

**Status: FIXED** (2026-05-08)

## Problem

`MarkdownGtk.RenderSourceView.resize_widget_callback` could drive **tight main-loop churn**: when used as the callback for **`GLib.Idle.add`**, returning **`true`** causes that idle source to **run again as soon as possible**, without yielding in a meaningful way. Two branches did this:

1. **`for_width <= 0`** after measuring width from **`Gtk.ScrolledWindow`** (and **`REVEAL_BODY`** width helpers), the function **`return true`** so layout would retry once width exists.
2. **`ResizeMode.REVEAL_BODY`** while **`!widget.get_realized()`**, the function **`return mode == ResizeMode.REVEAL_BODY`** → **`true`**, retrying until realization.

While **`for_width`** stayed zero or the widget stayed unrealized (hidden stack page, revealer not laid out yet, etc.), the idle could fire **every main-loop iteration** → high CPU, noisy **`G_MESSAGES_DEBUG`** if anything logs per entry, and behaviour similar to **unbounded recursion** from the caller’s perspective.

**Related prior fix:** **`scroll_bottom`** used to reschedule indefinitely when **`vadjustment.upper < 10`**; that was bounded with **`try_again`** (see **`docs/bugs/done/2026-04-08-FIXED-large-session-history-post-load-100pct-cpu.md`**).

## Expected

If width or realization is not yet available, rescheduling should be **bounded** or **rare**, and should **not** spin the main loop at full rate when the condition never becomes true in the same frame.

## Actual (before fix)

**`return true`** from a **`GLib.Idle.add`** callback ran the same function again on the next idle opportunity, as long as the condition remained. **`for_width`** often stayed **`0`** until **`Gtk.ScrolledWindow`** / revealer chain had allocation; **`REVEAL_BODY`** before realization matched **mode + unrealized** branch.

## Root cause

Same class of issue as **`scroll_bottom`**: propagating **`true`** from **`resize_widget_callback`** back to **`GLib.Idle.add`** without bounding retries, combined with **`for_width`** not yet resolveable from the scrolled window alone early in layout.

## Fix (summary)

**`libocmarkdowngtk/RenderSourceView.vala` — `resize_widget_callback`:** For **`ResizeMode.REVEAL_BODY`**, **`for_width`** is resolved in order from **`body_revealer`** (**`get_allocated_width`**, then **`get_width`**), then from **`renderer.box`**’s allocated width when still **`≤ 0`**, so height-for-width measurement usually gets a positive width without repeated idle spins when the **`Gtk.ScrolledWindow`** alone has not allocated yet.

The unrealized **`REVEAL_BODY`** path may still reschedule on idle until realization; combined with the width fallbacks and normal GTK layout, manual verification shows acceptable CPU and no regression on frame expand, fenced markdown, and **`end_code_block`** **`FINAL`** idles.

## Verification

Manual exercise: frame expand/collapse, nested fenced markdown, **`end_code_block`** timing, **`G_MESSAGES_DEBUG`** / temporary trace — no main-loop flood from **`resize_widget_callback`** on these paths.

---

## Affected code (historical)

**File:** `libocmarkdowngtk/RenderSourceView.vala`

**Tight-reschedule entry point (unrealized + `REVEAL_BODY`):**

```512:515:libocmarkdowngtk/RenderSourceView.vala
			if (!widget.get_realized()) {
				// REVEAL_BODY may run before layout; retry on idle. SourceView FINAL when unrealized is handled by ctor realize one-shot + INITIAL.
				return mode == ResizeMode.REVEAL_BODY;
			}
```

**`REVEAL_BODY` width chain (reduces `for_width <= 0` retries):**

```516:528:libocmarkdowngtk/RenderSourceView.vala
			var  for_width = this.scrolled_window.get_width();
			if (mode == ResizeMode.REVEAL_BODY) {
				for_width = this.body_revealer.get_allocated_width();
			 	if (for_width <= 0) {
					for_width = this.body_revealer.get_width();
				}
				if (for_width <= 0 && this.renderer.box != null) {
					for_width = this.renderer.box.get_allocated_width();
				}
			}
			if (for_width <= 0) {
				return true;
```

**Callers that forward the bool to `GLib.Idle`:** e.g. collapse **reveal** path, view-source toggle, **`fill_widgets`**, newline chunk resize, **`end_code_block`** FINAL idle.

**Example — FINAL idle forwards `resize_widget_callback`’s return value:**

```680:687:libocmarkdowngtk/RenderSourceView.vala
			GLib.Idle.add(() => {
				if (!this.body_revealer.reveal_child) {
					return false;
				}
				var result = this.resize_widget_callback(this.source_view, ResizeMode.FINAL);
				this.scroll_bottom(this.source_scrolled);
				return result;
			});
```

## reproduction / signals (checklist)

- Enable debug that logs on each **`resize_widget_callback`** entry (**`G_MESSAGES_DEBUG=all`** plus any temporary trace, or uncommented **`GLib.debug`**): stderr should **not** flood.
- **`for_width`** can remain **`0`** until **`Gtk.ScrolledWindow`** / revealer chain has allocation; **`REVEAL_BODY`** before realization matches **mode + unrealized** branch.

## Fix direction (historical — candidates considered)

Candidates (not prescriptions): widen **`for_width`** resolution (**`get_allocated_width`**, parent box) before deferring; **`try_again`-style** second pass like **`scroll_bottom`**; **`GLib.Timeout.add`** with backoff or max attempts; one-shot **`notify["width"]`** / **`size-allocate`** retry; **`queue_allocate`** alignment with GTK lifecycle.

Closing this bug included a **manual** note (frame expand, fenced markdown nested path, **`end_code_block`** timing) so **`FINAL`** / **`INITIAL`** idles do not regress layout.
