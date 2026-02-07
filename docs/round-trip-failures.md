# Round-trip failures: markdown → document JSON → markdown

**Test:** `tests/test-markdown-doc.sh` — for each `tests/markdown/*.md`, run md→JSON (into build dir), then JSON→md, then diff original vs round-trip.

**Result:** Round-trip output differs from input. Summary of causes (no fixes applied).

---

## 1. Heading: extra space after `#`

- **Input:** `# Heading 1`, `## Heading 2`
- **Round-trip:** `#  Heading 1`, `##  Heading 2` (two spaces between `#` and text).

**Cause:** The parser stores the heading *content* including a leading space (e.g. `" Heading 1"`). `Block.to_markdown()` does `sharp + " " + inner`, so it emits `"# " + " Heading 1"` → `"#  Heading 1"`. The leading space in the stored text is redundant with the single space added by `to_markdown()`.

---

## 2. List items: content missing (items appear empty)

- **Input:** `- Unordered item A`, `- Unordered item B`, `1. Ordered first`, `2. Ordered second`
- **Round-trip:** List structure is there but item text is gone; items show as blank lines or only the list marker.

**Cause:** In `Render.vala`, `current_block_with_inlines` is set only when pushing a **Block** with kind PARAGRAPH, HEADING_1..6, TABLE_CELL, or TABLE_HCELL. When the parser opens a LIST_ITEM it pushes a **ListItem** onto the block stack but does *not* set `current_block_with_inlines`. Inline content (TEXT, etc.) is always added via `add_format_to_current` to `current_block_with_inlines`. So text that the parser emits while inside a list item is attached to whichever block was last set as `current_block_with_inlines` (e.g. the previous paragraph), not to the list item. In the document tree, list items therefore have no (or wrong) children, and `ListItem.to_markdown()` / `List.to_markdown()` output empty content for each item.

---

## 3. Blockquote: line text missing

- **Input:** `> Blockquote line one.`, `> Blockquote line two.`
- **Round-trip:** `> ` and `> ` with no text, plus extra blank lines.

**Cause:** Same mechanism as list items. BLOCKQUOTE is a Block, but BLOCKQUOTE is not one of the kinds that set `current_block_with_inlines` in `push_block()`. So when the parser emits the paragraph/text inside the blockquote, it is added to the previous `current_block_with_inlines` (e.g. the last paragraph or heading), not to the blockquote block. The blockquote block thus has no (or wrong) children; `Block.to_markdown()` for BLOCKQUOTE still emits `"> " + inner.replace("\n", "\n> ")`, but `inner` is empty.

---

## 4. Extra blank lines from empty blocks

- **Observed:** Many consecutive blank lines in the round-trip where the input had list items or blockquote lines.

**Cause:** Lists and blockquotes are present as blocks in the tree, but their children (list items or blockquote paragraphs) have no content because inlines were routed elsewhere. So each such block emits a short line (e.g. `- `, `> `) or empty content. `Document.to_markdown()` joins every top-level child with `"\n\n"`, so each of these blocks contributes blank-line separation. The result is more blank lines than in the original and “ghost” list/blockquote markers with no text.

---

## 5. Fenced code: closing fence and newlines

- **Input:** Code block ends with `}\n```` and often a final newline after the closing ```` ``` ````.
- **Round-trip:** Can show an extra newline before the closing fence (`}\n\n````) and/or missing final newline at end of file.

**Cause:** `Block.to_markdown()` for FENCED_CODE_QUOTE/TILD does `"\n" + this.code_text + "\n" + fence`. Whether that matches the source depends on how `code_text` is stored (e.g. with or without trailing newline). `Document.to_markdown()` does not append a trailing newline, so if the original file ended with a newline after the last block, the round-trip will not.

---

## 6. Summary table

| Issue | Location | Root cause |
|-------|----------|------------|
| Heading `#  ` (double space) | Parser stores heading text with leading space; Block.to_markdown() adds another space | Parser / Block.to_markdown() |
| List item text missing | Inlines added only to current_block_with_inlines; ListItem never set as current | Render.vala push_block / LIST_ITEM handling |
| Blockquote text missing | Same: BLOCKQUOTE not in current_block_with_inlines set | Render.vala push_block |
| Extra blank lines | Empty or nearly empty list/blockquote blocks still joined with `\n\n` | Document.to_markdown() + wrong tree shape |
| Code block / final newline | Joining and no trailing newline from Document | Block.to_markdown() + Document.to_markdown() |

---

**Conclusion:** The main failures are (1) **structural**: list and blockquote content is attached to the wrong parent because only certain block kinds set `current_block_with_inlines`, and (2) **formatting**: heading space, block separation, and final newline. Fixing the round-trip would require addressing both the renderer’s handling of list items and blockquotes (so their inlines attach to the right node) and the small formatting differences in headings and newlines.

---

## Proposed fixes (concrete code changes)

### Fix 1. Heading: single space after `#`

**Standard (CommonMark):** [ATX headings](https://spec.commonmark.org/0.31.2/#atx-headings) require the opening `#` sequence to be followed by spaces or tabs (or end of line). The spec says: *"The raw contents of the heading are **stripped of leading and trailing space or tabs** before being parsed as inline content."* So the space after `#` is syntax, not content — the stored heading text must be the trimmed run (e.g. `"Heading 1"`, not `" Heading 1"`).

**Fix (parser, in peek only):** The fix must be in the **peek** (block-matching) code, not in `handle_block_result()`. Use a left-strip of the remainder and validate that there is real content; never advance position with a character-by-character loop over space/tab.

**Coding standard:** Never loop over characters (e.g. advancing with `get_char()` and `to_string().length`). Use string methods (strip, substring, index_of, etc.) instead.

**File:** `libocmarkdown/BlockMap.vala`

In `peek()`, after a match for `HEADING_1`..`HEADING_6` (same pattern as the existing **horizontal rule** check: validate the remainder of the line before returning the match):

1. **Remainder:** From `chunk_pos + byte_length` to the end of the current line (next `\n` or end of chunk), take the substring — that is the raw remainder after the `#` run.
2. **Left-strip:** Use the string **strip** method (or left-strip) to get the heading content. CommonMark: raw contents are stripped of leading and trailing space before being parsed as inline.
3. **Validate:** If the stripped remainder is **empty**, or its **first character is not alphanumeric** (letters and digits allowed; check spec for any other allowed starters), then treat as “not enough”: return **-1** (need more) unless `is_end_of_chunks`, in which case return **0** (not a heading).
4. **Include leading space in byte_length:** Add to `byte_length` the number of characters (bytes) of leading space/tab that were stripped, so that `chunk_pos + byte_length` points at the first character of the stripped content. The inline parser then sees no leading space; no change is needed in `handle_block_result()`.

Example shape (after the existing `byte_length = space_skip + byte_length` and before the fenced-code/table/HR checks):

```vala
// ATX heading: require non-empty stripped content starting with alphanumeric (digits allowed); include leading space in byte_length
if (matched_block >= FormatType.HEADING_1 && matched_block <= FormatType.HEADING_6) {
	var rest_start = chunk_pos + byte_length;
	var rest_len = (line_end != -1) ? line_end - rest_start : (int)chunk.length - rest_start;
	var rest = rest_len > 0 ? chunk.substring(rest_start, rest_len) : "";
	var stripped = rest.strip();
	if (stripped.length == 0 || !stripped.get_char(0).isalnum()) {
		if (is_end_of_chunks) {
			return 0;
		}
		return -1;
	}
	var lead_skip = rest.index_of(stripped);
	if (lead_skip > 0) {
		byte_length += lead_skip;
	}
}
```

No change in `handle_block_result()` or in `Block.to_markdown()` / document renderer.

---

### Fix 2. List items and blockquote: route inlines to the right node

**Idea:** Use a single “current node that accepts inlines” typed as `Node?`, set it for BLOCKQUOTE and for ListItem, and use a stack so that when we pop (list item or block), we restore the previous target.

**File:** `libocmarkdown/document/Render.vala`

**2a) Type and stack**

Replace the single “current block” with a node reference and a stack so we can restore when leaving list items and blocks.

**ArrayList conventions:** Use a property with `get; set; default = new Gee.ArrayList<...>(comparison);`. All `Gee.ArrayList` constructors in this codebase should pass an equality function (e.g. for `Node` use `(a, b) => a.uid == b.uid`). Use **`ArrayList<Node>`**, not `ArrayList<Node?>`: only push the previous inline target when it is non-null; when popping, set the current target to the popped value or to `null` if the stack is empty.

```vala
// Replace:
private Block? current_block_with_inlines = null;

// with:
private Node? current_block_with_inlines = null;
private Gee.ArrayList<Node> inline_target_stack { get; set;
	default = new Gee.ArrayList<Node>((a, b) => a.uid == b.uid); }
```

**2b) When setting the current inline target**

Whenever we set `current_block_with_inlines`, push the old value first (only if non-null, since the stack is `ArrayList<Node>`); when we clear it on pop, pop the previous value or set to `null` if stack is empty.

In `push_block()`:

```vala
private void push_block(Block b)
{
	this.add_block_to_current(b);
	this.block_stack.add(b);
	if (b.kind == FormatType.PARAGRAPH
	    || (b.kind >= FormatType.HEADING_1 && b.kind <= FormatType.HEADING_6)
	    || b.kind == FormatType.TABLE_CELL
	    || b.kind == FormatType.TABLE_HCELL
	    || b.kind == FormatType.BLOCKQUOTE) {
		if (this.current_block_with_inlines != null) {
			this.inline_target_stack.add(this.current_block_with_inlines);
		}
		this.current_block_with_inlines = b;
	}
}
```

In `pop_block()`:

```vala
if (top == this.current_block_with_inlines) {
	this.current_block_with_inlines = this.inline_target_stack.size > 0
		? this.inline_target_stack.remove_at(this.inline_target_stack.size - 1)
		: null;
}
```

**2c) List item: set and restore**

When starting a list item, push current target (if non-null) and set it to the item; when ending the list item, restore from stack.

LIST_ITEM start (inside `on_node`, case `FormatType.LIST_ITEM`):

```vala
if (is_start) {
	var item = new ListItem() {
		task_checked = this.last_task_checked
	};
	item.uid = this.document.uid_count++;
	this.last_task_checked = false;
	var parent = this.block_stack.get(this.block_stack.size - 1) as List;
	parent.adopt(item);
	this.block_stack.add(item);
	if (this.current_block_with_inlines != null) {
		this.inline_target_stack.add(this.current_block_with_inlines);
	}
	this.current_block_with_inlines = item;
	this.current_list_item = item;
	return;
}
```

LIST_ITEM end:

```vala
this.block_stack.remove_at(this.block_stack.size - 1);
this.current_block_with_inlines = this.inline_target_stack.size > 0
	? this.inline_target_stack.remove_at(this.inline_target_stack.size - 1)
	: null;
this.current_list_item = null;
return;
```

**2d) `add_format_to_current`**

No change: it already does `this.current_block_with_inlines.children.add(f)` and `Node` has `children`, so `Node?` is enough.

---

### Fix 3. Extra blank lines

Resolved by Fix 2: list items and blockquotes will have the correct children, so they emit real content and no longer produce “ghost” blocks. No extra code beyond Fix 2.

---

### Fix 4. Fenced code and final newline

**4a) Trailing newline at end of document**

**File:** `libocmarkdown/document/Document.vala`

Join with `"\n\n"` because markdown block-level elements (paragraphs, headings, lists, blockquotes, code blocks) are separated by a blank line. Append a final `"\n"` so the document ends with a newline when the source did.

```vala
public override string to_markdown()
{
	string[] parts = {};
	foreach (var child in this.children) {
		parts += child.to_markdown();
	}
	return string.joinv("\n\n", parts) + "\n";
}
```

**4b) Code block: avoid double newline before closing fence**

If the parser stores `code_text` with a trailing newline, then `"\n" + this.code_text + "\n" + fence` can become `…\n\n````. Normalise so there is exactly one newline before the closing fence.

**File:** `libocmarkdown/document/Block.vala`

```vala
case FormatType.FENCED_CODE_QUOTE:
case FormatType.FENCED_CODE_TILD:
	var fence = this.kind == FormatType.FENCED_CODE_QUOTE ? "```" : "~~~";
	string code = this.code_text;
	if (code.has_suffix("\n"))
		code = code.substring(0, code.length - 1);
	return fence + (this.lang != "" ? this.lang : "") +
		 "\n" + code + "\n" + fence;
```

(Alternatively, fix the parser so `code_text` does not include a trailing newline, and keep Block as-is.)

---

### Fix 5. ListItem.to_markdown() for non-task items

**File:** `libocmarkdown/document/ListItem.vala`

Currently every item is emitted with a task prefix:

```vala
result += this.task_checked ? "[x] " : "[ ] ";
```

So plain lists (e.g. `- Unordered item A`) round-trip as `- [ ] Unordered item A`. The list marker is added by `List.to_markdown()`; the item body should only get a task prefix when the list is a task list.

**Option A — add `task_list` on List:**

- In `List`, add e.g. `public bool task_list { get; set; }` (set by the renderer when it sees `FormatType.TASK_LIST`).
- In `List.to_markdown()` when building the item string, only pass a task prefix when `this.task_list` is true.
- That might require: `ListItem` to expose `task_checked` and `List` to pass it through, or `ListItem.to_markdown()` to accept an "emit task prefix" flag (signature change or List does the prefix itself).

**Option B — add `is_task_item` on ListItem:**

- In `ListItem`, add e.g. `public bool is_task_item { get; set; default = false; }`.
- The renderer sets it true only when the current list was opened as a task list (TASK_LIST).
- In `ListItem.to_markdown()` (use `var` not `string` for the local):

```vala
public override string to_markdown()
{
	var result = this.is_task_item ? (this.task_checked ? "[x] " : "[ ] ") : "";
	foreach (var child in this.children) {
		result += child.to_markdown();
	}
	return result;
}
```

Render sets `is_task_item = true` on each ListItem when the list was started with TASK_LIST (e.g. track “current list is task list” in the renderer and set it on the item in the LIST_ITEM start branch).
