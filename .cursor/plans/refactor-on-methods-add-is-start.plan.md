# Refactor: Add `is_start` parameter to all `on_*` methods and remove `on_end()`

## Overview

Refactor the markdown parser API to add `bool is_start` as the first parameter to all `on_*` methods, and remove the generic `on_end()` method. This makes the API more explicit about which format is being started or ended.

## Current State

- Methods like `on_em()`, `on_strong()`, `on_code_span()`, `on_del()`, `on_other()`, `on_html()` are called when formats start
- Generic `on_end()` is called when any format ends
- The parser determines start vs end by checking if the format type is already on the stack

## Proposed Changes

### 1. Update `Markdown/RenderBase.vala`

- Change method signatures to add `bool is_start` as first parameter:
- `on_em()` → `on_em(bool is_start)`
- `on_strong()` → `on_strong(bool is_start)`
- `on_code_span()` → `on_code_span(bool is_start)`
- `on_del()` → `on_del(bool is_start)`
- `on_other(string tag_name)` → `on_other(string tag_name, bool is_start)`
- `on_html(string tag, string attributes)` → `on_html(string tag, string attributes, bool is_start)`
- Remove `on_end()` abstract method

### 2. Update `Markdown/Parser.vala`

- **`do_format_start()`**: Update all calls to pass `true`:
- `on_em(true)`, `on_strong(true)`, `on_code_span(true)`, `on_del(true)`
- For BOLD_ITALIC: `on_strong(true)` then `on_em(true)`
- For HTML: `on_other("html", true)`

- **`do_format_end()`**: Replace `on_end()` calls with specific format methods passing `false`:
- Add switch statement to determine which method to call based on `format_type`
- For BOLD_ITALIC: call `on_em(false)` then `on_strong(false)` (reverse order)
- For other formats: call the appropriate method with `false`

- **`add_html()`**: Update to pass `is_start` parameter:
- When `is_closing == false`: call `on_html(tag, attributes, true)`
- When `is_closing == true`: call `on_html(tag, attributes, false)`
- Remove the `on_end()` call for closing tags

### 3. Update `Markdown/PangoRender.vala`

- Update all `on_*` method implementations to handle `is_start`:
- When `is_start == true`: add opening tag and track it
- When `is_start == false`: close the most recently opened tag
- Remove `on_end()` implementation
- Fix `toPango()` method: The cleanup loop that calls `on_end()` needs to be replaced. Since we no longer know which format type each tag corresponds to, we have two options:
- Option A: Track format types separately (more complex)
- Option B: Keep a simple tag stack and close tags in reverse order (simpler, but less type-safe)
- **Recommendation**: Use Option B for now - iterate through `open_tags` and close them, but we'll need to call the appropriate `on_*` method. Actually, we can't do that without knowing the format type. Let's track both tag names and format types, or just close tags directly in the cleanup.

Actually, looking more carefully: `open_tags` contains tag names like "i", "b", "tt", "s", "span". We can map these back:

- "i" → `on_em(false)`
- "b" → `on_strong(false)`
- "tt" → `on_code_span(false)`
- "s" → `on_del(false)`
- "span" → `on_html("span", "", false)`

But this is a bit fragile. Better approach: track format types alongside tag names, or create a helper method.

**Simpler solution**: Since PangoRender is building markup strings, we can just append closing tags directly in the cleanup loop without calling the renderer methods. But that's inconsistent with the API.

**Best solution**: Track the format type or method type when opening tags, so we know which method to call when closing.

For now, let's use a mapping approach in the cleanup.

### 4. Update `MarkdownGtk/Render.vala`

- Update all `on_*` method implementations to handle `is_start`:
- When `is_start == true`: call `add_state()` to create new state
- When `is_start == false`: call `close_state()` on current state
- Remove `on_end()` implementation

### 5. Update `Markdown/DummyRenderer.vala`

- Update all `on_*` method implementations to handle `is_start`:
- When `is_start == true`: print "START:" and increment indent
- When `is_start == false`: decrement indent and print "END:"
- Remove `on_end()` implementation

## Implementation Details
1
### Special Case: BOLD_ITALIC

When `BOLD_ITALIC` format is detected:

- **Start**: Call `on_strong(true)` then `on_em(true)` (both added to stack)
- **End**: Call `on_em(false)` then `on_strong(false)` (reverse order, both removed from stack)

### Special Case: PangoRender cleanup

In `toPango()`, we need to close any remaining open tags. Since we track tag names but need to call the appropriate `on_*` method, we'll create a helper method or use a mapping to determine which method to call based on the tag name.

## Files to Modify

1. `Markdown/RenderBase.vala` - Method signatures
2. `Markdown/Parser.vala` - Call sites and logic
3. `Markdown/PangoRender.vala` - Implementations
4. `MarkdownGtk/Render.vala` - Implementations  
5. `Markdown/DummyRenderer.vala` - Implementations

## Testing

- Run `test-markdown-parser.vala` to verify behavior
- Test nested formats (e.g., bold inside italic)
- Test BOLD_ITALIC format
- Test HTML tags (opening and closing)
- Test cleanup in PangoRender.toPango()