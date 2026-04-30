# OPEN: `RenderSourceView.resize_widget_callback` — unbounded idle reschedule (`for_width <= 0`, `REVEAL_BODY` + unrealized)

**Status: OPEN**

## Problem

`MarkdownGtk.RenderSourceView.resize_widget_callback` can drive **tight main-loop churn**: when used as the callback for **`GLib.Idle.add`**, returning **`true`** causes that idle source to **run again as soon as possible**, without yielding in a meaningful way. Two branches do this:

1. **`for_width <= 0`** after measuring width from **`Gtk.ScrolledWindow`** (and the **`REVEAL_BODY`** width helpers), the function **`return true`** so layout would retry once width exists.
2. **`ResizeMode.REVEAL_BODY`** while **`!widget.get_realized()`**, the function **`return mode == ResizeMode.REVEAL_BODY`** → **`true`**, retrying until realization.

While **`for_width`** stays zero or the widget stays unrealized (hidden stack page, revealer not laid out yet, etc.), the idle can fire **every main-loop iteration** → high CPU, noisy **`G_MESSAGES_DEBUG`** if anything logs per entry, and behaviour similar to **unbounded recursion** from the caller’s perspective.

**Related prior fix:** **`scroll_bottom`** used to reschedule indefinitely when **`vadjustment.upper < 10`**; that was bounded with **`try_again`** (see **`docs/bugs/2026-04-08-FIXED-large-session-history-post-load-100pct-cpu.md`**). That doc noted **`resize_widget_callback`** was **not** the measured flood site next to **`upper < 10`**, but the **return-true** pattern here is the same class of bug.

## Expected

If width or realization is not yet available, rescheduling should be **bounded** (at most N follow-ups, or a single deferred pass, or a one-shot **map** / **size-allocate** / **notify:width** hook) and should **not** spin the main loop at full rate when the condition never becomes true in the same frame.

## Actual

**`return true`** from a **`GLib.Idle.add`** callback runs the same function again on the next idle opportunity, as long as the condition remains. **No cap** and no **backoff** in **`resize_widget_callback`**.

## Affected code

**File:** `libocmarkdowngtk/RenderSourceView.vala`

**Tight-reschedule entry point (unrealized + `REVEAL_BODY`):**

```512:515:libocmarkdowngtk/RenderSourceView.vala
			if (!widget.get_realized()) {
				// REVEAL_BODY may run before layout; retry on idle. SourceView FINAL when unrealized is handled by ctor realize one-shot + INITIAL.
				return mode == ResizeMode.REVEAL_BODY;
			}
```

**Tight-reschedule entry point (`for_width <= 0`):**

```527:528:libocmarkdowngtk/RenderSourceView.vala
			if (for_width <= 0) {
				return true;
```

**Callers that forward the bool to `GLib.Idle` (so **`return true` propagates**):** e.g. collapse **reveal** path, view-source toggle, **`fill_widgets`**, newline chunk resize, **`end_code_block`** FINAL idle.

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

## reproduction / signals

- Enable debug that logs on each **`resize_widget_callback`** entry (**`G_MESSAGES_DEBUG=all`** plus any temporary trace, or uncommented **`GLib.debug`**): stderr **floods**.
- **`for_width`** can remain **`0`** until **`Gtk.ScrolledWindow`** / revealer chain has allocation; **`REVEAL_BODY`** before realization matches **mode + unrealized** branch.

## Fix direction (leave to implementation)

Candidates (not prescriptions): widen **`for_width`** resolution (**`get_allocated_width`**, parent box) before deferring; **`try_again`-style** second pass like **`scroll_bottom`**; **`GLib.Timeout.add`** with backoff or max attempts; one-shot **`notify["width"]`** / **`size-allocate`** retry; **`queue_allocate`** alignment with GTK lifecycle.

Closing this bug should include a **manual** note (frame expand, fenced markdown nested path, **`end_code_block`** timing) so **`FINAL`** / **`INITIAL`** idles do not regress layout.
