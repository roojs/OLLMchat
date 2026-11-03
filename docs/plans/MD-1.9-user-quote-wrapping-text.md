# MD-1.9 — User quote is type raw

**Status:** ✔️ applied — not checked in the app yet

> [`MD-1.0-summary.md`](MD-1.0-summary.md) is not updated until this plan is done and archived.

**Checklist:** [`docs/guide-to-writing-plans.md`](../guide-to-writing-plans.md) — Checklist for plans. Proposed Vala follows [`docs/coding-standards.md`](../coding-standards.md).

## Purpose

- 🔷 Quoted text from the input scrolls sideways. That was not wanted.
- 🔷 That quote does not need preformatted text. Use regular text for what the user said.
- 🔷 This is when they start a conversation, and they guess on a follow-up as well.
- 🔷 That block is different from coded markdown blocks.
- 🔷 Do not use the markdown type for this quote. Markdown is for markdown content.
- 🔷 Markdown tags typed inside the quote stay as characters.
- 🔷 The type name is `raw`.
- ℹ️ The quote is one fence from `Session.send`. Start and follow-up both use it.
- ℹ️ Horizontal scroll landed in [`docs/bugs/done/2026-10-28-FIXED-markdown-code-block-font-scroll.md`](../bugs/done/2026-10-28-FIXED-markdown-code-block-font-scroll.md). The quote is type `text`, so it took that same source view.

## Current behaviour

- ℹ️ `Session.send` stores the quote as `text.oc-frame-primary.oc-frame-user You said:`.
- ℹ️ Type `text` paints a `GtkSource.View` with `wrap_mode` `NONE`, class `code-editor`, and a horizontal bar.
- 🔷 A long line in that quote scrolls sideways.
- ℹ️ Type `markdown` paints the nested renderer and would format tags in the quote.

## Proposed behaviour

- 🔷 The fence type is `raw`. The body is the characters they typed.
- 🔷 The body wraps. It is not the preformatted code face, and it does not scroll sideways.
- 💩 Class `oc-raw` is that face: padding and a white ground, no monospace family.
- 💩 Copy and “Start new chat with this” stay. View source stays off, because that toggle is only for type `markdown`.
- 💩 A quote already saved as `text` … `oc-frame-user` is painted as `raw`. The stored fence is not rewritten.
- 💩 Other `text` frames stay preformatted. Tool output, errors, and the sample in `tests/markdown/oc-frame-info-format.md` do not carry `oc-frame-user`.
- 🔷 Coded markdown blocks keep the sideways scroll.

## Quote body

### 1. `libocmarkdowngtk/RenderSourceView.vala` — `body_widgets`: wrap type `raw`

**Why:** 💩 The source view is already the literal body. `raw` changes wrap, face, and the horizontal bar. It does not call the nested markdown renderer.

**Where:** `body_widgets`, after `this.source_scrolled.set_child(this.source_view)`, before the view is added to the stack.

**Depends on:** none.

#### Add — after `this.source_scrolled.set_child(this.source_view);`

Type `raw` wraps in the UI face and does not scroll sideways.

```vala
			if (this.code_language == "raw") {
				this.source_view.wrap_mode = Gtk.WrapMode.WORD;
				this.source_view.remove_css_class("code-editor");
				this.source_view.add_css_class("oc-raw");
				this.source_scrolled.hscrollbar_policy = Gtk.PolicyType.NEVER;
			}
```

### 2. `resources/style.css` — `.oc-raw`

**Why:** 💩 `code-editor` forces the fixed face. `raw` needs its own class so the quote does not inherit that.

**Where:** Immediately after the `.code-editor` rule.

**Depends on:** §1, which adds the class.

#### Add — immediately after `.code-editor`

UI face. No font family, so the quote is not monospace.

```css
/* User quote. UI face, not the code face. */
.oc-raw {
  padding: 4px;
  background-color: white;
}
```

### 3. `libocmarkdowngtk/RenderSourceView.vala` — constructor: saved user quotes

**Why:** 💩 Chats already stored say `text` and `oc-frame-user`. Painting those as `raw` wraps them without rewriting the session file.

**Where:** Constructor, immediately after `var is_user_frame = "oc-frame-user" in frame_theme_classes;`, before `body_widgets`.

**Depends on:** §1. `body_widgets` reads `this.code_language`.

#### Add — after `var is_user_frame = "oc-frame-user" in frame_theme_classes;`

A saved user quote whose type word is still `text` is painted as `raw`.

```vala
			if (is_user_frame && this.code_language == "text") {
				this.code_language = "raw";
			}
```

## Stored fence

### 4. `libollmchat/History/Session.vala` — `send`: new quote type

**Why:** 💩 A new turn, including a follow-up, stores type `raw`.

**Where:** The `Message.fenced` header in `send`, the user-message branch.

**Depends on:** none.

#### Remove

```vala
				Message.fenced("text.oc-frame-primary.oc-frame-user You said:", text));
```

#### Replace with

```vala
				Message.fenced("raw.oc-frame-primary.oc-frame-user You said:", text));
```

### 5. `libollmchat/History/SessionJson.vala` — migration: same header

**Why:** 💩 A session that still lacks the quote frame is filled with the same fence `send` writes.

**Where:** The `Message.fenced` call in the `user-sent` migration.

**Depends on:** none.

#### Remove

```vala
								Message.fenced("text.oc-frame-primary.oc-frame-user You said:", last_msg.content)));
```

#### Replace with

```vala
								Message.fenced("raw.oc-frame-primary.oc-frame-user You said:", last_msg.content)));
```

## LLM notes

- ℹ️ The view-source toggle is shown only when `this.code_language == "markdown"`. Type `raw` does not show it.
- ℹ️ `code_block_ended` passes the type word through. Nothing in this tree switches on `"text"` for that signal.
- 💩 Do not run the nested markdown renderer on type `raw`.
- 💩 Do not change `wrap_mode` or the horizontal policy on the source view except in the `raw` branch.
- 💩 Do not rewrite quote bodies already stored in session files. §3 paints the old `text` user quotes.
