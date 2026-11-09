# Bash output wraps; code fences stay on one line

**Status:** 🚫 CLOSED 2026-11-06. Live bash already scrolls sideways. Further bash output rendering is [`2026-11-05-CLOSED-restore-bash-tool-output.md`](2026-11-05-CLOSED-restore-bash-tool-output.md). The missing row is [`2026-11-08-bash-frame-not-in-chat.md`](../2026-11-08-bash-frame-not-in-chat.md).

## Problem

- 🔷 Bash output wraps inside the pane.
- 🔷 Bash does not word-wrap. A long line extends to the right and scrolls sideways.
- 🔷 Vala, Python, and other code fences do not wrap. A long line scrolls sideways.
- 🔷 Markdown output wraps. The raw text quote wraps.
- 🔷 Fixing one must leave the other alone.

## Evidence

- ℹ️ Live bash is `OLLMchatGtk.ToolOutput`. `wrap_mode` is `Gtk.WrapMode.CHAR`, so each line breaks at the pane width. There is no sideways scroll.
- ℹ️ Fenced code is `MarkdownGtk.RenderSourceView`. The source view starts at `Gtk.WrapMode.NONE` with a horizontal bar. Type `raw` (user quotes) already sets `Gtk.WrapMode.WORD` and hides that bar.
- ℹ️ Restored bash is a `text` frame (`Execution results`), not the live pane. Type `text` is also file reads and other preformatted frames.
- ℹ️ Chat fences and the file-preview fences are the same `RenderSourceView`.

## Root cause

- ✔️ The live pane wraps on purpose (`CHAR`). That is the opposite of the bash rule. Code fences are a different widget, so a bash-only change does not make them wrap, and a fence change does not make the live pane scroll.

## Proposed fix

- 🔷 Live bash: `Gtk.WrapMode.NONE`, horizontal bar on, natural width not propagated. Same sideways pattern the source scroller already uses.
- 🔷 Type `raw` stays word wrap, UI face, no sideways bar.
- 🔷 Markdown body stays on the nested renderer, which already wraps.
- 🔷 Vala, Python, and every other code fence stay `Gtk.WrapMode.NONE` with the horizontal bar.
- 🔷 Type `text` stays one line and scrolls sideways. That keeps restored bash results and the other preformatted frames.
- 🚫 Wrapping every fence that is not `raw` or `text`. That made Vala and Python wrap.
- 🚫 A single wrap mode on both widgets.

**Where:** `libollmchatgtk/ToolOutput.vala`, the `TextView` and `ScrolledWindow` in the constructor.

#### Replace with

```vala
			this.view = new Gtk.TextView() {
				editable = false,
				cursor_visible = false,
				wrap_mode = Gtk.WrapMode.NONE,
				monospace = true,
				hexpand = true,
				css_classes = { "tool-output" }
			};
			this.view.buffer.text = command + "\n";
			this.scroll = new Gtk.ScrolledWindow() {
				min_content_height = 200,
				max_content_height = 480,
				propagate_natural_height = true,
				propagate_natural_width = false,
				hscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
				hexpand = true,
				vexpand = false,
				margin_top = 4,
				margin_bottom = 4,
				margin_start = 4,
				margin_end = 4,
				css_classes = { "tool-output" }
			};
```

## Attempts / changelog

- ✔️ 2026-11-05 — live bash scrolls sideways. A first pass also wrapped every code fence.
- ✔️ 2026-11-05 — that fence wrap is removed. Vala and Python scroll sideways again. Markdown and `raw` still wrap.
- 🚫 2026-11-06 — closed. The remaining bash output work is the restore log.

## Next

- 🚫 2026-11-06 — closed.
