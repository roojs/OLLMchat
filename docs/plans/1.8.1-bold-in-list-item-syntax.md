# Plan 1.8.1: Bold in list item syntax — `- **bold** some other text` not parsed

## Summary

The markdown parser does not recognise bold when it appears at the **start of list item content**:

```markdown
- **bold** some other text
```

The `**bold**` segment is not parsed as bold; it is rendered as plain text (or the asterisks may be consumed incorrectly).

## Goal

Analyse why emphasis at the start of list item content is not recognised and propose a minimal, correct fix that aligns with CommonMark and existing parser design (StartMap / LeftMap / RightMap).

---

## 1. Analysis

### 1.1 How list item content is parsed

- **BlockMap** (e.g. in `handle_block_result`) matches list markers (`- `, `* `, `1. `, task `[ ]` / `[x]`).
- After consuming the marker, it sets:
  - `chunk_pos = seq_pos` (first character of the list item content, e.g. `*` in `**bold** ...`)
  - `this.parser.at_line_start = false`
- The main parser loop then continues from `chunk_pos` and treats the rest of the line as **inline** content.

### 1.2 How emphasis is recognised (inline)

Emphasis (bold/italic) is handled by three maps, not by the main FormatMap:

- **StartMap** — opening delimiters valid **only at start of line** (`at_line_start == true`). Used for `*`, `**`, `***`, `_`, `__`, `___`.
- **LeftMap** — opening delimiters when **preceded by whitespace** (peek requires a space at `chunk_pos` before the delimiter).
- **RightMap** — closing delimiters when followed by whitespace/newline (and not at line start when stack is empty).

So:

- `**` at **line start** → StartMap.
- `**` **after a space** → LeftMap.
- `**` at the **very start of list item content** (no preceding space) → currently **neither**: we are not at line start (parser set `at_line_start = false`), and there is no preceding space for LeftMap. So **bold is never opened**.

Relevant code:

- **BlockMap.vala** (lines 439–448, 446–447): when starting or continuing a list item, `this.parser.at_line_start = false` and `chunk_pos = seq_pos`.
- **Parser.vala** (lines 371–398): StartMap is only consulted when `this.at_line_start` is true; LeftMap is only used when current character is whitespace (and then peeks at the next position).

So the **root cause** is: **the first character of list item content is not treated as “start of line” for emphasis**, even though logically it is the start of the inline content for that line.

### 1.3 CommonMark / expected behaviour

In CommonMark, emphasis can open at:

- Start of line (or after block structure that doesn’t emit a character).
- After whitespace.
- In some cases after punctuation (left-flanking rules).

So `- **bold** some other text` should parse as: list item with content “**bold** some other text”, and `**bold**` should be bold. Our parser should treat the position immediately after the list marker as a valid “content start” for emphasis, i.e. equivalent to start of line for StartMap.

---

## 2. Proposed fix

### 2.1 Option A (recommended): Treat list item content start as line start for emphasis

**Change:** When BlockMap starts or continues a list item and advances `chunk_pos` to the first character of the list item content, set **`at_line_start = true`** instead of `false`.

**Location:** **BlockMap.vala** in `handle_block_result`, for the list cases (ORDERED_LIST, UNORDERED_LIST, TASK_LIST, TASK_LIST_DONE):

- Where we currently set `this.parser.at_line_start = false` and `chunk_pos = seq_pos`, set `this.parser.at_line_start = true` (and keep `chunk_pos = seq_pos`).

**Rationale:**

- The first character of list item content is the “start” of that line’s inline content; allowing StartMap to run there is consistent with “start of line” semantics.
- No new state or APIs; one flag change in one place.

**Block re-check: will we wrongly start a block?**

When we set `at_line_start = true` at list item content start, the next iteration runs **block peek** first. So we must not mis-detect a block at that position.

- At `chunk_pos` we have the first character of the content, e.g. `**bold** some other text`.
- **Unordered list `* `:** BlockMap matches list markers by `eat()` at the current position. That tries longest match: `*` → INVALID, `**` → INVALID, `***` → HORIZONTAL_RULE. The sequence is `*` then `*` (not space), so `* ` is never matched. So we do **not** start a new list.
- **Horizontal rule `***`:** We do get a match for `***`, but **BlockMap.peek** then requires the next character to be whitespace or newline (see “***Bold***” comment in BlockMap). Here the next character is `b`, so the rule returns 0 (no block). So we do **not** start an HR.
- **Other blocks** (heading `#`, `- ` for list, etc.) do not match at `*` or `**`.

So block peek returns 0, we fall through to StartMap, which matches `**` and opens bold. **No spurious block start.**

**Edge cases to confirm:**

- Ordered list: `1. **bold**` — same behaviour; content start is after `1. `.
- Task list: `- [ ] **bold**` — content start is after the space after `]`; `**` at content start should still get `at_line_start = true`.
- Nested lists: content of the inner item is again “after” the inner marker; setting `at_line_start = true` for that content is correct.

### 2.2 Option B: Explicit “content start” or “inline start” flag

Introduce a parser flag (e.g. `at_inline_content_start`) that is set when we begin list item content (and cleared after the first character is processed). StartMap would run when `at_line_start || at_inline_content_start`. This is more invasive and duplicates the idea of “start of content” with “start of line”; Option A is simpler.

### 2.3 Option C: Allow StartMap when in list and no characters consumed yet on this line

Conceptually similar to A but requires tracking “no inlines yet on this list item line”, which the parser may not already have. Option A achieves the same effect with less state.

### 2.4 Implications of *not* eating the space after the list marker

**Current behaviour:** The list marker is matched as a whole (e.g. `- `, `* `, `1. `, `- [ ] `). `byte_length` includes the space, so `chunk_pos = seq_pos` leaves the parser at the first character of the content (e.g. `*` in `**bold** ...`). So we **do** eat the space.

**If we did *not* eat the space:** We would advance only past `-` (or `*`, etc.) and leave the space in the stream. Then the first character of “content” would be that space.

- **Pro:** Bold would work without any `at_line_start` change. Content would be ` **bold** ...`; the space would be emitted as TEXT, then **LeftMap** would see space + `**` and open bold. So the bug would be fixed by changing how much we consume, not by setting `at_line_start = true`.
- **Cons:**
  - **Leading space in every list item:** Every item’s content would start with a TEXT node `" "`. **ListItem.key_value()** expects the *first child* to be BOLD_ASTERISK when the item is key-value style (`- **key** value`). If the first child is TEXT(`" "`), `key_value()` returns `""` and the key is lost. So not eating the space would **break key_value()** for items that start with bold.
  - **Display / round-trip:** Rendered content would have a leading space before the first word. Round-trip would produce `-  **bold**` (two spaces); spec-wise the single space after `-` is usually considered part of the marker, so content is defined to start *after* it.
  - **Consistent semantics:** “Content” is defined as what follows the marker; in CommonMark the required space after `-`/`*`/`+` is part of the marker, so content starts after that space. Keeping that and fixing bold via `at_line_start = true` is the smaller, semantics-preserving change.

**Conclusion:** We keep eating the space (current behaviour) and fix bold by setting `at_line_start = true` at list item content start (Option A). We do **not** change what we consume after the list marker.

---

## 3. Implementation checklist (for Option A)

1. **BlockMap.vala**  
   In `handle_block_result`, for the list branch (ORDERED_LIST / UNORDERED_LIST / TASK_LIST / TASK_LIST_DONE):
   - When setting `chunk_pos = seq_pos` after consuming the list marker, set `this.parser.at_line_start = true` instead of `false` (both for “already in list” and “new list” cases).

2. **Tests**
   - Add or extend a test that parses `- **bold** some other text` and asserts that the list item’s first inline segment is bold (e.g. BOLD_ASTERISK format with content “bold”), and that “ some other text” is following text.
   - Same for `1. **bold** text` and `- [ ] **bold** text`.

3. **Regression**
   - Ensure existing list and emphasis tests still pass (e.g. emphasis elsewhere, nested lists, task lists).

---

## 4. References

- **StartMap.vala** — start-of-line emphasis; only runs when `at_line_start` is true.
- **LeftMap.vala** — emphasis after whitespace.
- **Parser.vala** — main loop: block peek → StartMap → LeftMap → RightMap → FormatMap; `at_line_start` is set in BlockMap and on newlines.
- **BlockMap.vala** — list marker handling and `at_line_start` assignment (lines 439–448).
- **Plan 1.8.3** (underscore emphasis) — different issue (intraword); same emphasis pipeline (StartMap / LeftMap / RightMap).

---

## 5. Status

- **Status:** open.
- **Next step:** Implement Option A in BlockMap and add tests; then mark plan done.
