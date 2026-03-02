# 1.8.2 Renderer – thinking mode issues

- **Goal:** Fix renderer behaviour so thinking-mode content keeps correct styling (grey, italic) in all block types, including bullet lists.
- **Status:** open (plan only).

---

## Issue: thinking colour lost on bullet points

- **Symptom:** When in thinking mode and the model outputs bullet points, the list item content loses the grey thinking colour and appears in default (black) text.
- **Likely cause: state cleared when list block ends.** We may already inherit state (or the block-level thinking state is correct), but something **clears** it. Search for code that clears or resets state.

---

## Code that clears state

- **libocmarkdowngtk/Render.vala**
  - **`on_list(false)`** (lines 408–414): when a list block ends, calls `this.current_state.close_state()` then `add_text("\n")`. The list block never opens a state in the GTK renderer (`on_list(true)` is a no-op). So the state being closed is the **block-level** state (thinking or content) that ChatView pushed, not a list-owned state. After the list ends, `current_state` becomes `top_state` and the grey/italic is lost for any following content in the same thinking block.
  - **`end_block()`** (lines 283–291): sets `current_state = null`, `top_state = null` (only used when ending the whole block, not mid-stream list).
  - **`create_textview()`** (line 239): sets `current_state = this.top_state` when creating a new TextView (after code block, etc.).
- **libocmarkdowngtk/TopState.vala** (line 72): `close_state()` sets `current_state = top_state` (TopState cannot be closed).
- **libollmchatgtk/ChatView.vala** (line 660): `end_block_direct()` sets `this.renderer.default_state = null` when the block ends (intended).

---

## Proposed fix (state clearing)

- In **libocmarkdowngtk/Render.vala**, **`on_list(false)`**: do **not** call `close_state()`. Only add the newline if desired. The list block does not open a state in this renderer (only `on_li(true)` opens a state for the list item content), so closing "the current state" when the list ends is wrong — it closes the thinking/content block state. After this change, when a list ends we stay in the block-level state and subsequent content keeps the grey.
- **Files to change:** `libocmarkdowngtk/Render.vala` – remove or guard the `close_state()` in `on_list(false)`.

---

## Alternative / additional cause (to verify)

- **Inheritance:** `on_li(true)` calls `current_state.add_state()` for the list item content; that new state gets a new tag with no inherited foreground. So list item *content* might be black even before the list ends. If so, also consider inheriting parent style in **State.add_state()** when `use_tag == null` (copy_style_to the new state).
