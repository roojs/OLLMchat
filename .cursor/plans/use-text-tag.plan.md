# TextTag-Based Styling Refactor

## Overview

Replace the Pango markup approach with Gtk.TextTag objects. Each State will create its own TextTag in the constructor with a unique name (using a static counter), expose it as a `style` property, and apply it to text ranges after insertion. This removes the need for outer/inner marks - we'll just use start/end marks.

## Key Changes

1. **State.vala**:

   - Add static counter for unique tag names (`style-0`, `style-1`, etc.)
   - Create `Gtk.TextTag` in constructor with unique name
   - Expose tag as `style` property (public getter)
   - Remove `tag_name` property
   - Remove `insert_tags()` method (no more Pango markup)
   - Simplify marks: remove `start_outer`, `start_inner`, `end_inner`, `end_outer` → use `start` and `end` marks
   - Update `add_text()` to apply the tag to the inserted text range
   - Remove `attributes` parameter handling (keep parameter but ignore it)
   - Update constructor to create tag and register it with buffer's tag table

2. **TopState.vala**:

   - Update to also create a TextTag (TopState should have a tag too)
   - Simplify marks to just `start` and `end`
   - Update `add_text()` and `add_state()` to work with simplified marks
   - Remove `insert_tags()` override

3. **Render.vala**:

   - Update callbacks that set attributes (like `on_h`, `on_a`) to set TextTag properties directly instead
   - Remove attribute string construction (e.g., `"size=\"xx-large\" weight=\"bold\""`)

## Implementation Details

### State Constructor Changes

- Add static `uint tag_counter = 0`
- Generate unique tag name: `"style-%u".printf(tag_counter++)`
- Create `Gtk.TextTag` with that name
- Register tag with buffer's tag table: `this.render.buffer.create_tag(tag_name, null)`
- Store tag in private field, expose as `style` property
- Create `start` and `end` marks at insertion point (from parent's `end` mark)

### add_text() Changes

- Insert plain text (no escaping needed - TextBuffer handles it)
- After insertion, apply tag to the range: `buffer.apply_tag(this.style, start_iter, end_iter)`
- Update `end` mark to point after inserted text

### add_state() Changes

- No changes needed - just creates state, tag is created in constructor
- Users can then access `new_state.style.foreground = "..."` etc.

### Mark Simplification

- Replace four marks (`start_outer`, `start_inner`, `end_inner`, `end_outer`) with two (`start`, `end`)
- `start` marks the beginning of the state's text range
- `end` marks the end (and is used as insertion point)

### Render Callback Updates

- `on_h()`: Instead of `"size=\"xx-large\" weight=\"bold\""`, do:
  ```vala
  var h_state = this.current_state.add_state("h" + level.to_string());
  h_state.style.scale = Pango.Scale.XX_LARGE;
  h_state.style.weight = Pango.Weight.BOLD;
  ```

- `on_a()`: Instead of `"color=\"blue\" underline=\"single\""`, do:
  ```vala
  var link_state = this.current_state.add_state("span");
  link_state.style.foreground = "blue";
  link_state.style.underline = Pango.Underline.SINGLE;
  ```


## Files to Modify

- `MarkdownGtk/State.vala` - major refactor to use TextTags
- `MarkdownGtk/TopState.vala` - update for TextTags and simplified marks
- `MarkdownGtk/Render.vala` - update callbacks to set TextTag properties directly

## Notes

- TextTags support nesting automatically, so nested states will work correctly
- No need to escape text - TextBuffer handles plain text insertion
- Tag names are unique per State instance (using static counter), so there's no conflict
- All semantic tag information (like "h1", "em", "strong") is removed - styling is done purely through TextTag properties