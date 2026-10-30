# Markdown code blocks: proportional font, no horizontal scroll

**Status:** ⏳ fix applied — desktop check below; Android font still needs a device look

## Problem

- 🔷 File-view markdown preview: fenced code blocks are not monospace on Android.
- 🔷 Desktop was not checked by the user.
- 🔷 A long line should scroll sideways inside the code box, not wrap or widen the page.

## Evidence

- ℹ️ Preview is `OLLMcoder.MarkdownView`, which uses `MarkdownGtk.Render`. Fences are `RenderSourceView`: a `GtkSource.View` with CSS class `code-editor`.
- ℹ️ `resources/style.css` `.code-editor` set `font-family: monospace`.
- ℹ️ Same failure, already fixed for the editor: [`done/2026-09-28-FIXED-android-source-view-usability.md`](done/2026-09-28-FIXED-android-source-view-usability.md). Android has `Droid Sans Mono`. The generic family `monospace` does not resolve, so the UI face is used. Desktop has a real `monospace` and looks fine.
- ℹ️ That log left chat and tool output on generic `monospace`. File preview fences are the `code-editor` case of that leftover.
- ✔️ `RenderSourceView.body_widgets` sets `wrap_mode = WORD` and both scrolled windows use horizontal policy `NEVER`. A long line wraps inside the fence. There is no sideways scroll.

## Root cause

- ✔️ Font: `.code-editor` asks for `monospace`, which Android does not have. The editor already requests `Droid Sans Mono`, then `monospace`.
- ✔️ Scroll: the fence wraps and refuses a horizontal bar, so the line cannot move inside the box.

## Proposed fix

- 🔷 Use the editor font list on `.code-editor`.
- 🔷 Stop wrapping the fence. Scroll horizontally inside the source scrolled window, the same way tables keep a wide child inside the page (`propagate_natural_width = false`, horizontal policy `AUTOMATIC`).
- ℹ️ Chat fences use this same widget, so they get the same font and inner scroll.
- 🚫 Inline `` `spans` `` stay on the Pango family `monospace`. They are not the text box. A single Pango family cannot list a fallback the way CSS can.

### `resources/style.css`

#### Replace with

```css
/* Code blocks. Same Android face as .source-view. */
.code-editor {
  font-family: "Droid Sans Mono", monospace;
  padding: 4px;
  background-color: white;
}
```

### `libocmarkdowngtk/RenderSourceView.vala`

#### Replace with

```vala
			this.source_view = new GtkSource.View() {
				editable = false,
				cursor_visible = false,
				show_line_numbers = false,
				wrap_mode = Gtk.WrapMode.NONE,
				hexpand = true,
				vexpand = false,
				can_focus = false,
				focus_on_click = false,
				css_classes = { "code-editor" }
			};
```

#### Replace with

```vala
			this.source_scrolled = new Gtk.ScrolledWindow() {
				hexpand = true,
				vexpand = true,
				margin_start = 2,
				hscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
				vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
				propagate_natural_width = false
			};
			this.source_scrolled.set_child(this.source_view);
```

## Height

- 🔷 2026-10-28: the short fence in the desktop preview is too squat. About twice the current height.
- ℹ️ The fitted height is the source view’s natural height (`resize_widget_callback`). The two-line sample frame was 63px.
- 🔷 Use twice that fitted height. Still stop at half the window.

#### Replace with

```vala
int target_ht = natural_height * 2;
if (natural_height <= 0 || target_ht >= max_ht) {
    target_ht = max_ht;
}
```

#### Replace with

```vala
int target_height = natural_height * 2;
if (natural_height <= 0 || target_height >= max_height) {
    target_height = max_height;
}
```

## Preview size

- 🔷 2026-10-30: preview fences are a little large. About two points smaller. Chat stays as it is.
- ℹ️ Desktop theme is Cantarell 11. `.code-editor` with no size is 11pt (14.667px). 11pt minus 2pt is 9pt.
- 🚫 Do not set `font-size` on `.code-editor`. Chat fences use that class.

### `liboccoder/MarkdownView.vala`

#### Add — immediately after `Object(...)` in the constructor

```vala
			this.add_css_class("markdown-preview");
```

### `resources/style.css`

#### Add — immediately after `.code-editor`

```css
/* File preview fences only. Theme size is 11pt; chat stays there. */
.markdown-preview .code-editor {
  font-size: 9pt;
}
```

## Attempts / changelog

- ✔️ 2026-10-28: CSS font list and inner horizontal scroll applied as above.
- ✔️ 2026-10-28: fitted code-box height is twice the text height, still capped at half the window.
- ✔️ 2026-10-30: preview fences are 9pt. Chat fences stay at the theme size.

## Next

- ⏳ User checks a fenced block in the Android file preview: fixed face, long line scrolls inside the box.
- ⏳ User checks the desktop file preview: fence text is about two points smaller than chat.
