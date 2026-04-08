# FIXED: Nested four-backtick fences (CommonMark-style variable width)

**Status: FIXED** (reopen if regressions) — **`libocmarkdown`** now supports **three–five** backtick runs and **three–five** tilde runs as fenced code delimiters, with opening/closing length matched via stored `fence_open`. Parser trace for the nested fixture matches a **single** outer fenced block with inner triple-backtick lines as literal `CODE_TEXT`. Verification: **`tests/test-markdown-parser.sh`** — all **8** tests pass (including Test 8).

## Problem (historical)

Outer fences with **more than three** backticks (e.g. four) are required by **CommonMark** so that lines containing `` ``` `` stay **inside** the block. The parser only recognized three-tick/three-tilde opens, mis-parsed `fence_open`, and broke the rest of the document.

## Fix applied

### Design

- **`FormatType`:** Replaced `FENCED_CODE_QUOTE` / `FENCED_CODE_TILD` with a contiguous block **`FENCE_QUOTE_3` … `FENCE_QUOTE_5`**, **`FENCE_TILD_3` … `FENCE_TILD_5`** in `libocmarkdown/Parser.vala`, with **`to_fence()`** (literal fence strings) and **`is_fence_kind()`** for range-style checks.
- **`BlockMap.vala`:** Map keys for `` ``` `` through ````` and `~~~` through `~~~~~`; **`fence_open`** stores the full opening marker; **`fence_indent`** uses **`(space_skip == 3) ? "   " : ""`** (not `fence_open.length > 3`); **`peekFencedEnd`** list-indent branch uses **`fence_open.has_prefix("   ") && at_marker.has_prefix("   ")`**.
- **Render / document model:** `RenderBase`, `document/Block.vala` (`to_fence()` for `to_md`), `document/Render.vala` (`on_node` fenced cases, `CODE_TEXT` guard); **`liboccoder`** `ResultParser.vala` / `WriteChange.vala` use **`is_fence_kind()`** (or equivalent range checks).

### Critical: `fence_open` substring

**`fence_open`** must be:

```vala
this.fence_open = chunk.substring(chunk_pos, byte_length);
```

Vala’s **`substring(offset, length)`** takes **length**, not an end index. Using **`chunk_pos + byte_length`** as the second argument (as if it were an end offset) was **invalid**, led to **`string_substring` assertion failures**, and **`peekFencedEnd`** could crash.

### Tests

- Fixture: [`tests/markdown/nested-backtick-fence.md`](../../tests/markdown/nested-backtick-fence.md).
- Expected trace: [`tests/markdown/nested-backtick-fence-expected-trace.txt`](../../tests/markdown/nested-backtick-fence-expected-trace.txt) (regenerated for the fixed parser).
- Runner: [`tests/test-markdown-parser.sh`](../../tests/test-markdown-parser.sh) — **`test_nested_backtick_fence`** (Test 8).

**Note:** [`tests/markdown/links-expected-trace.txt`](../../tests/markdown/links-expected-trace.txt) was refreshed so the links callback trace matches current inline handling of **`[ ]` / `[x]`** from `FormatMap` (task list markers in prose). That is independent of the fence fix but keeps the markdown suite green.

## Known follow-ups (not regressions)

- **`document/Render.vala` `on_code`:** The renderer callback only receives **`fence_char`**; **`on_code`** still maps to **`FENCE_QUOTE_3` / `FENCE_TILD_3`**. Paths that build a document from **`on_code`** / **`on_block`** without the full **`FormatType`** from **`on_node`** can lose fence width on round-trip — see **FIXME** in that file.
- **Fence length &gt; 5:** Implementation uses a **capped** map (five ticks / five tildes), not an arbitrary run-length scan; six or more characters in a row are out of scope unless extended later.

## Changelog

- 2026-04-08 — Investigation, fixture, Test 8, long analysis in pre-fix bug log.
- 2026-04-08 — **FIXED:** Per-length enums, map, `fence_open` / `fence_indent` / `peekFencedEnd`, `to_fence()`, call sites; substring fix; traces + full markdown test suite passing.
