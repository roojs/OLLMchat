# State-Based Markdown Renderer

## Overview

Replace MD4C dependency with a custom state-based markdown renderer. The system will consist of:

1. A `Render` class that takes a buffer and start mark, with main method `add(string text)`
2. A placeholder `Parser` class that parses text and calls specific callbacks on Render
3. A state-based renderer where each `State` represents a single styling element
4. States manage their own buffer and marks for tag positions (start_outer, start_inner, end_inner, end_outer)
5. States have methods: `add_text()`, `add_state()`, `close_state()` - states update top-level current_state
6. Renderer receives specific callbacks (on_h, on_ul, on_em, etc.) instead of generic enter/leave events
7. No enums needed - use specific callback methods for each block/span type

## Architecture

### State Class (`State`)

- Represents a single piece of styling (e.g., italic, bold, paragraph, header)
- Properties:
- `parent: State?` - pointer to parent state
- `cn: Gee.ArrayList<State>` - array of child states
- `buffer: StringBuilder` - accumulated text content
- `start_outer: Gtk.TextMark?` - mark where start tag begins
- `start_inner: Gtk.TextMark?` - mark where start tag ends (before inner content)
- `end_inner: Gtk.TextMark?` - mark where end tag starts (after inner content) - also used for insertion
- `end_outer: Gtk.TextMark?` - mark where end tag ends
- `tag_name: string` - the tag name (e.g., "em", "strong", "h1", "p")
- `render: Render` - reference to top-level Render for current_state updates
- Methods:
- `add_text(string text)` - adds text to current buffer
- `add_state(string tag, string attributes): State` - creates a new child state, updates Render's current_state
- `close_state()` - closes this state, pops to parent, updates Render's current_state

### TopState Class (`TopState`)

- Wraps `State` to handle special root state behavior
- Properties:
- `state: State` - wrapped State instance (no tag, no parent)
- `render: Render` - reference to Render for mark updates
- Methods:
- `add_text(string text)` - wraps State.add_text(), updates render's end_mark with state's end_inner
- `add_state(string tag, string attributes): State` - wraps State.add_state(), updates render's end_mark with state's end_inner
- `close_state()` - no-op (top_state cannot be closed)
- Updates render's start_mark/end_mark by copying state's start_outer/end_inner marks
- When state with no parent is inserted, modifies end_buffer of outer render

### Renderer Class (`Render`)

- Constructor: `Render(Gtk.TextBuffer buffer, Gtk.TextMark start_mark)` - creates Parser instance and TopState
- Main method: `add(string text)` - passes text to parser, which calls callbacks
- Properties:
- `buffer: Gtk.TextBuffer` - text buffer
- `start_mark: Gtk.TextMark` - start mark (updated by top_state)
- `end_mark: Gtk.TextMark` - end mark (updated by top_state)
- `top_state: TopState` - root state wrapper, manages buffer insertion and mark updates
- `current_state: State` - current active state (always points to a state, never null - defaults to top_state.state)
- `parser: Parser` - parser instance created in constructor
- Receives callbacks from parser
- Callbacks create/manage states via `add_state()` and `close_state()`
- States handle their own buffer insertion
- top_state wraps add_state and add_text to update render's start_mark/end_mark

### Parser Class (`Parser`)

- Constructor: `Parser(Render renderer)` - takes Render instance for callbacks
- Method: `add(string text)` - parses text and calls specific callbacks on Render (see Callback Methods section)
- Created when Render is constructed
- Simple state-based approach (no complex back-and-forth parsing logic)
- Parser implementation details will be specified later

## Implementation Steps

### 1. Remove MD4C Dependencies

- Remove MD4C-related code from `MarkdownGtk/Render.vala` (remove references, keep files)
- Remove MD4C static callback wrappers
- Update `meson.build` if MD4C dependency exists
- Note: Keep `vapi/md4c.vapi` file (may be useful for reference)

### 2. Create Callback Methods in Render

- No enums needed - use specific callback methods instead
- Block callbacks (with data):
- `on_h(uint level)` - header (level 1-6)
- `on_ul(bool is_tight, char mark)` - unordered list
- `on_ol(uint start, bool is_tight, char mark_delimiter)` - ordered list
- `on_li(bool is_task, char task_mark, uint task_mark_offset)` - list item
- `on_code(string? lang, char fence_char)` - code block
- Block callbacks (no data):
- `on_p()` - paragraph
- `on_quote()` - blockquote
- `on_hr()` - horizontal rule
- Span callbacks (with data):
- `on_a(string href, string? title, bool is_autolink)` - link
- `on_img(string src, string? title)` - image
- Span callbacks (no data):
- `on_em()` - emphasis/italic
- `on_strong()` - bold
- `on_u()` - underline
- `on_del()` - strikethrough
- `on_code_span()` - inline code
- Generic callback:
- `on_other(string tag_name)` - for unmapped block/span types
- Text callback:
- `on_text(string text)` - text content

### 3. Create State Class

- File: `MarkdownGtk/State.vala`
- Implement state management:
- Constructor takes parent state, tag name, and reference to Render
- Methods:
- `add_text(string text)` - adds text to current buffer
- `add_state(string tag, string attributes): State` - creates new child state, sets it as current_state on Render
- `close_state()` - closes this state, pops to parent, updates Render's current_state
- Internal methods for creating marks (start_outer, start_inner, end_inner, end_outer) and inserting tags
- end_inner is used for insertion point

### 4. Create TopState Class

- File: `MarkdownGtk/TopState.vala`
- Wraps State to handle root state behavior:
- Constructor takes Render instance and creates internal State (no tag, no parent)
- Methods:
- `add_text(string text)` - wraps State.add_text(), updates render's end_mark with state's end_inner
- `add_state(string tag, string attributes): State` - wraps State.add_state(), updates render's end_mark with state's end_inner
- `close_state()` - no-op (top_state cannot be closed)
- Updates render's start_mark/end_mark by copying state's start_outer/end_inner marks
- Provides access to wrapped state via `state` property

### 5. Create Parser Class

- File: `MarkdownGtk/Parser.vala`
- Constructor: `Parser(Render renderer)` - takes Render instance for callbacks
- Method: `add(string text)` - parses text and calls specific callbacks on Render
- Created in Render constructor
- Parser implementation details will be specified later
- Simple state-based parser (no complex back-and-forth logic for now)

### 6. Refactor Render Class

- Constructor: `Render(Gtk.TextBuffer buffer, Gtk.TextMark start_mark)` - creates Parser instance and TopState
- Main method: `add(string text)` - calls `parser.add(text)`, which calls callbacks
- Remove MD4C parser and callbacks (remove references, but keep files)
- Create `top_state: TopState` in constructor
- Initialize `current_state: State` to `top_state.state` (never null)
- Add `end_mark: Gtk.TextMark` property (updated by top_state)
- Add specific callback methods (on_h, on_ul, on_em, etc.) that create/manage states
- Callbacks call `current_state.add_state(tag, attributes)` to create child states
- Callbacks call `current_state.close_state()` to close states (resets to top_state.state if no parent)
- `on_text(string text)` calls `current_state.add_text(text)`
- top_state wraps add_state and add_text to update render's start_mark/end_mark
- Remove direct buffer insertion (states handle it)

## Files to Modify

- `MarkdownGtk/Render.vala` - refactor to use state system
- `meson.build` - remove MD4C dependency if present

## Files to Create

- `MarkdownGtk/State.vala` - state class
- `MarkdownGtk/TopState.vala` - top state wrapper class
- `MarkdownGtk/Parser.vala` - placeholder parser (full implementation in separate plan)

## Files to Keep (References Removed)

- `vapi/md4c.vapi` - MD4C VAPI file kept for reference (references removed from code)

## Mapped Block/Span Types

Based on current Render.vala implementation, the following types are actually mapped (excluding tables which are placeholders):

### Mapped Block Types

- **P** - Paragraph (on_p)
- **H** - Header (on_h with level parameter)
- **UL** - Unordered List (on_ul with is_tight and mark parameters)
- **OL** - Ordered List (on_ol with start, is_tight, and mark_delimiter parameters)
- **LI** - List Item (on_li with is_task, task_mark, and task_mark_offset parameters)
- **QUOTE** - Blockquote (on_quote)
- **CODE** - Code Block (on_code with lang and fence_char parameters)
- **HR** - Horizontal Rule (on_hr)

### Mapped Span Types

- **EM** - Emphasis/Italic (on_em)
- **STRONG** - Bold (on_strong)
- **U** - Underline (on_u)
- **DEL** - Strikethrough (on_del)
- **CODE** - Inline Code (on_code_span)
- **A** - Link (on_a with href, title, and is_autolink parameters)
- **IMG** - Image (on_img with src and title parameters)

### Unmapped Types (use on_other)

- Blocks: DOC, HTML, TABLE, THEAD, TBODY, TR, TH, TD
- Spans: LATEXMATH, LATEXMATH_DISPLAY, WIKILINK

## Key Design Decisions

1. States are responsible for inserting their own tags into the buffer
2. Text is accumulated in state's buffer until the state ends
3. State methods: `add_text()`, `add_state(string tag, string attributes)`, `close_state()`
4. Four marks track tag positions: start_outer, start_inner, end_inner, end_outer
5. end_inner is used for insertion point (no separate insertion_mark)
6. State stores only tag_name (no attributes stored)
7. Render constructor takes buffer and start_mark, creates Parser instance
8. Parser constructor takes Render instance for callbacks
9. Parser only has `add(string text)` method (other than constructor)
10. Main usage: `Render.add(string text)` -> `parser.add(text)` -> callbacks
11. Render has `top_state: TopState` (wraps State, cannot be closed) and `current_state: State` (never null, defaults to top_state.state)
12. TopState wraps State and handles special behaviors: updates render's start_mark/end_mark by copying state's marks
13. TopState wraps add_state and add_text to update render's end_mark with state's end_inner
14. When closing state with no parent, reset current_state to top_state.state (never null)
15. TopState wraps State with no tag_name (empty string), no parent (null), and cannot be closed
16. Specific callbacks instead of enums: on_h, on_ul, on_em, on_a, on_other(string), etc.
17. No BlockType/SpanType enums needed
18. Parser is separate from renderer for separation of concerns
19. Parser uses simple state-based approach (no complex back-and-forth logic)
20. Table handling removed for now (will be added later)
21. No testing section - this class will not work yet (implementation in progress)