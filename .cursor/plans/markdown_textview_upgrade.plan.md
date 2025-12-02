# Refactor Render to use GtkBox model and reorganize namespaces

## Overview

This refactoring is broken into 12 independent steps that can be reviewed separately while keeping the code compiling and working at each step.

## Step-by-Step Implementation Plan

### Step 1: Move Parser to Markdown namespace ✓

**Files**: `MarkdownGtk/Parser.vala` → `Markdown/Parser.vala`, `MarkdownGtk/RenderBase.vala`, `meson.build`, `test-markdown-parser.vala`

**Changes**:

- Move file from `MarkdownGtk/` to `Markdown/` directory
- Change namespace from `OLLMchat.MarkdownGtk` to `OLLMchat.Markdown`
- Update `RenderBase.vala` to use `Markdown.Parser` instead of `Parser`
- Update `meson.build` to move Parser from `ollmchat_markdowngtk_src` to base library sources
- Update test file references from `MarkdownGtk.Parser` to `Markdown.Parser`

**Verification**: Code compiles, tests pass

---

### Step 2: Move PangoRender to Markdown namespace ✓

**Files**: `MarkdownGtk/PangoRender.vala` → `Markdown/PangoRender.vala`, `UI/ChatView.vala`, `meson.build`

**Changes**:

- Move file from `MarkdownGtk/` to `Markdown/` directory
- Change namespace from `OLLMchat.MarkdownGtk` to `OLLMchat.Markdown`
- Update `ChatView.vala` to use `Markdown.PangoRender` instead of `MarkdownGtk.PangoRender`
- Update `meson.build` to move PangoRender from `ollmchat_markdowngtk_src` to base library sources

**Verification**: Code compiles, ChatView still works

---

### Step 3: Move DummyRenderer to Markdown namespace (keep old API) ✓

**Files**: `MarkdownGtk/DummyRenderer.vala` → `Markdown/DummyRenderer.vala`, `test-markdown-parser.vala`, `meson.build`

**Changes**:

- Move file from `MarkdownGtk/` to `Markdown/` directory
- Change namespace from `OLLMchat.MarkdownGtk` to `OLLMchat.Markdown`
- Keep constructor signature `DummyRenderer(Gtk.TextBuffer, Gtk.TextMark)` for now (will update in Step 12)
- Update test file references from `MarkdownGtk.DummyRenderer` to `Markdown.DummyRenderer`
- Update `meson.build` to move DummyRenderer from `ollmchat_markdowngtk_src` to test sources

**Verification**: Code compiles, tests pass

---

### Step 4: Update visibility modifiers for library API ✓

**Files**: `Markdown/Parser.vala`, `Markdown/PangoRender.vala`, `Markdown/DummyRenderer.vala`, `MarkdownGtk/RenderBase.vala`

**Changes**:

- In `Parser.vala`: Review methods - keep public API public, internal callbacks can stay internal
- In `PangoRender.vala`: Change `internal override` to `public override` for callback methods (on_em, on_strong, on_code_span, on_del, on_other, on_html, on_end, on_text, on_entity)
- In `DummyRenderer.vala`: Change `internal override` to `public override` for callback methods
- In `RenderBase.vala`: Ensure `parser` property and public methods remain public

**Verification**: Code compiles, no visibility errors

---

### Step 5: Add Gtk.Box support to Render (additive changes) ✓

**Files**: `MarkdownGtk/Render.vala`

**Changes**:

- Add `box` property: `public Gtk.Box box { get; private set; }`
- Add `current_textview` property: `public Gtk.TextView? current_textview { get; private set; }`
- Add `current_buffer` property: `public Gtk.TextBuffer? current_buffer { get; private set; }`
- Keep existing `buffer`, `start_mark`, `end_mark` properties (will remove later)
- Add constructor overload: `public Render(Gtk.Box box)` that stores box and initializes new properties to null
- Keep old constructor `public Render(Gtk.TextBuffer buffer, Gtk.TextMark start_mark)` for backward compatibility

**Verification**: Code compiles, both constructors work

---

### Step 6: Implement lazy TextView creation in Render ✓

**Files**: `MarkdownGtk/Render.vala`

**Changes**:

- Modify `add()` method to check if `current_textview` is null
- If null and `box` is set, create new TextView, add to box at bottom, create buffer and marks
- Initialize `TopState` with the new buffer
- Update `current_textview` and `current_buffer`
- Ensure old constructor path still works

**Verification**: Code compiles, Render with box creates TextView on first add()

---

### Step 7: Add end_block() method to Render ✓

**Files**: `MarkdownGtk/Render.vala`

**Changes**:

- Add `public void end_block()` method
- Method creates new TextView, adds to box at bottom
- Sets as `current_textview` and `current_buffer`
- Creates new marks for the new buffer
- Resets `TopState` to work with new buffer
- Method only works when `box` is set (not for old constructor)

**Verification**: Code compiles, end_block() can be called (not yet used by ChatView)

---

### Step 8: Update ChatView to create Render with Gtk.Box ✓

**Files**: `UI/ChatView.vala`

**Changes**:

- Create a `Gtk.Box` property for assistant message content
- Create single `Render` instance in constructor using new `Render(Gtk.Box)` constructor
- Keep existing `text_view` and `buffer` properties temporarily
- Add box to scrolled window or appropriate container
- Render should create first TextView on first add() call

**Verification**: Code compiles, ChatView displays messages using new Render

---

### Step 9: Update ChatView to call end_block() and add frames to box ✓

**Files**: `UI/ChatView.vala`

**Changes**:

- In `end_block()` method, call `render.end_block()` when ending markdown blocks
- Modify `add_widget_frame()` to add frames directly to `render.box` instead of using TextChildAnchor
- Update `open_code_block()` to add frames to `render.box`
- Keep TextChildAnchor code temporarily commented or as fallback

**Verification**: Code compiles, frames appear correctly in box

---

### Step 10: Remove old TextBuffer-based properties from Render ✓

**Files**: `MarkdownGtk/Render.vala`, `MarkdownGtk/State.vala`, `MarkdownGtk/TopState.vala`, `MarkdownGtk/Table.vala`, `UI/ChatView.vala`

**Changes**:

- Remove `buffer`, `start_mark`, `end_mark`, `tmp_start`, `tmp_end` properties
- Update `State` and `TopState` to use `render.current_buffer` instead of `render.buffer`
- Update all mark operations to use `current_buffer`
- Remove old constructor `Render(Gtk.TextBuffer, Gtk.TextMark)`
- Update `State` constructor to get buffer from `render.current_buffer`
- Update `Table.vala` to use `current_buffer` instead of `buffer`
- Update `ChatView` to use `assistant_renderer` instead of creating new Render instances
- Remove end_mark tracking code from ChatView (box model handles it)

**Verification**: Code compiles, all rendering works correctly

---

### Step 11: Remove old TextView/buffer management from ChatView

**Files**: `UI/ChatView.vala`

**Changes**:

- Remove `text_view` and `buffer` properties
- Update scrolling logic to work with box model (scroll the box or scrolled window)
- Remove TextChildAnchor-based frame management code
- Update any remaining references to old text_view/buffer
- Update `add_blank_line()` if needed (may not be needed with box model)

**Verification**: Code compiles, all functionality works

---

### Step 12: Update DummyRenderer for new Render API

**Files**: `Markdown/DummyRenderer.vala`, `test-markdown-parser.vala`

**Changes**:

- Update `DummyRenderer` constructor to work like pango - no gtk references (change it's extends etc..?)
- Update test file to create a box and pass to DummyRenderer
- Ensure DummyRenderer still extends Render and works correctly

**Verification**: Code compiles, tests pass

---

## Summary

This plan breaks the refactoring into 12 reviewable steps:

- Steps 1-4: Namespace reorganization (independent, can be done first) ✓
- Steps 5-7: Render refactoring (additive, maintains backward compatibility initially) ✓
- Steps 8-9: ChatView integration (uses new Render API) ✓
- Step 10: Cleanup (removes old TextBuffer properties) ✓
- Step 11: Cleanup (removes old TextView/buffer management from ChatView) - TODO
- Step 12: Test updates (final cleanup) - TODO

Each step keeps the code compiling and functional, allowing for incremental review and testing.

**Progress: 10/12 steps completed (83%)**