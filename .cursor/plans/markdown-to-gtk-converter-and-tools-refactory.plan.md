# Markdown to GTK Converter and Tools Refactoring

## Overview

This plan implements a new md4c-based markdown to GTK TextView converter and refactors the Tools namespace by renaming RunTerminalCommand to RunCommand and creating a new ToolsUI namespace for GTK-specific tools.

## Tasks

### 1. Rename RunTerminalCommand to RunCommand

- Rename `Tools/RunTerminalCommand.vala` → `Tools/RunCommand.vala`
- Update class name from `RunTerminalCommand` to `RunCommand`
- Update tool name from `"run_terminal_command"` to `"run_command"`
- Update all internal references and comments

### 2. Create ToolsUI/RunCommand.vala

- Create new file `ToolsUI/RunCommand.vala` in `OLLMchat.ToolsUI` namespace
- Extend `Tools.RunCommand` (with full namespace)
- Rename `Tools/RunTerminalCommandGtk.vala` → `ToolsUI/RunCommand.vala` (GTK-specific functionality already exists, just needs rename and namespace change)
- Update all references in meson.build

### 3. Create MarkdownGtk/Render.vala with MarkdownGtk namespace

- Create new directory `MarkdownGtk/` and file `MarkdownGtk/Render.vala` in `OLLMchat.MarkdownGtk` namespace
- Implement md4c parser callbacks for:
- Block types: paragraphs, headers, lists, blockquotes, code blocks, tables, horizontal rules
- Span types: emphasis, strong, links, images, inline code, strikethrough, underline
- Text types: normal, line breaks, entities
- Constructor takes `Gtk.TextBuffer` and manages text marks for ranges
- Methods:
- `process_block(string markdown, Gtk.TextMark start_mark, Gtk.TextMark end_mark)` - processes markdown block and updates TextView range
- Handle code blocks as preformatted text (using `<tt>` Pango markup)
- Handle tables by creating `Gtk.Frame` with `Gtk.Grid` inside, inserting via `TextChildAnchor`
- Map other markdown features to Pango markup (bold, italic, links, etc.) - see https://docs.gtk.org/Pango/pango_markup.html for supported markup
- Track table state during parsing to build complete table structure
- **Error handling**: If table parsing encounters an error (e.g., partial table from input), show the content as unformatted text instead of failing silently
- Use md4c flags: `FLAG_TABLES`, `FLAG_STRIKETHROUGH`, `FLAG_UNDERLINE`, `FLAG_TASKLISTS`

### 4. Update meson.build

- Add md4c dependency to `ui_deps` (pkg-config name: `md4c`, path: `/usr/lib/x86_64-linux-gnu/pkgconfig/md4c.pc`)
- Update `ollmchat_tools_src` to use `RunCommand.vala` instead of `RunTerminalCommand.vala`
- Update `ollmchat_tools_ui_src` to use `ToolsUI/RunCommand.vala` instead of `RunTerminalCommandGtk.vala`
- Add `MarkdownGtk/Render.vala` to `ollmchat_ui_src` (only built with UI library)
- Ensure md4c.vapi is accessible (already in Markdown folder)

### 5. Update any code references

- Check `TestWindow.vala` and other files for `RunTerminalCommand` references
- Update if any code instantiates these classes directly
- Tool registration should work automatically if tool name stays the same

## Implementation Notes

### md4c Integration

- md4c uses callback-based parsing with `MD_PARSER` struct
- Callbacks receive block/span types and text ranges
- Need to track state (current table, list nesting, etc.)
- Text ranges are provided as offsets into input string
- pkg-config path: `/usr/lib/x86_64-linux-gnu/pkgconfig/md4c.pc`

### Pango Markup

- Reference: https://docs.gtk.org/Pango/pango_markup.html
- Use Pango markup tags for formatting (bold, italic, links, etc.)
- Supported tags include: `<b>`, `<i>`, `<u>`, `<s>`, `<tt>`, `<span>`, `<a>`, etc.
- Use `Gtk.TextBuffer.insert_with_tags()` or `insert_markup()` for formatted text

### Table Handling

- When entering `MD_BLOCK_TABLE`, create `Gtk.Frame`
- Inside frame, create `Gtk.Grid` with appropriate columns
- Process `MD_BLOCK_TR`, `MD_BLOCK_TH`, `MD_BLOCK_TD` to populate grid
- Insert frame via `TextChildAnchor` at current position
- Use `BlockTDDetail` for alignment information
- **Error handling**: If table parsing fails or receives partial/incomplete table data, fall back to displaying the raw markdown text as unformatted text in the TextView

### Code Block Handling

- For `MD_BLOCK_CODE`, output as preformatted text using `<tt>` Pango markup
- Extract language from `BlockCodeDetail` if needed (but don't create SourceView)
- Let ChatView handle code blocks separately if needed

### Range Management

- Use `Gtk.TextMark` objects to track start/end of blocks being updated
- Delete old content between marks before inserting new content
- Update marks after insertion to track new positions

## Files to Create/Modify

**Create:**

- `MarkdownGtk/Render.vala` (new file)

**Modify:**

- `Tools/RunTerminalCommand.vala` → `Tools/RunCommand.vala` (rename + update)
- `Tools/RunTerminalCommandGtk.vala` → `ToolsUI/RunCommand.vala` (rename + namespace change to `OLLMchat.ToolsUI`)
- `meson.build` (update file lists, add md4c dependency)
- Any files that reference `RunTerminalCommand` classes

**Note:** Documentation files in `docs/` will be regenerated automatically, so no manual updates needed.