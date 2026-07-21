# 2026-07-21 — Markdown stream hang on ATX heading starting with `**`

**Status:** ✔️ fixed in tree — await user verify

## Problem

- 🔷 While Gemma answered the IKEA PAX search, the chat **appeared frozen / blocked** until the model finished streaming.
- 🔷 User saw the model emit something like **“hash hash hash … 1. Simple …”** (`### **1. Simple Frames/Basic Units**`) — that line confused the markdown parser and held output until flush at end of stream.

## Evidence

- ℹ️ Session: `~/.local/share/ollmchat/history/2026/07/21/12-04-40.json` (`fid` `2026-07-21-12-04-40`, model `gemma4:26b`)
- ✔️ `content-stream` body contains these ATX lines (exact):

```markdown
### **1. Simple Frames/Basic Units**
### **2. Mid-Range Combinations**
### **3. Large or High-End Combinations**
### **Summary Tip:**
```

- ℹ️ Prior similar hang (emoji-led ATX): [`done/2026-07-18-FIXED-android-poc-completion-batch.md`](done/2026-07-18-FIXED-android-poc-completion-batch.md) **C2**
- ✔️ Before fix: `build/oc-markdown-test tests/markdown/repro-heading-bold.md` → `START: <p>` + literal `###`
- ✔️ After fix: same → `START: <h3>` (emoji fixture still `<h1>`/`<h2>`/`<h3>`)

## Standards (CommonMark ATX)

- ✔️ Heading body is inline content until EOL; any first char is fine.
- 🔷 Gate: wait only when **no content yet**; do not filter first char.

## Root cause

- ✔️ `BlockMap` ATX gate rejected non-`isalnum` / non-`>=0x80` first content char → mid-stream `-1` until flush.

## Fix applied

`libocmarkdown/BlockMap.vala` — drop first-char filter; wait only on empty incomplete line.

#### Remove

```vala
			// ATX heading: non-empty content starting with alphanumeric or non-ASCII (emoji); 
			// include leading space in byte_length
			if (matched_block >= FormatType.HEADING_1 && matched_block <= FormatType.HEADING_6) {
				var rest_start = chunk_pos + byte_length;
				var rest_len = (line_end != -1) ? line_end - rest_start : (int)chunk.length - rest_start;
				var rest = rest_len > 0 ? chunk.substring(rest_start, rest_len) : "";
				var heading_stripped = rest.strip();
				if (heading_stripped.length == 0 || 
						!(heading_stripped.get_char(0).isalnum() ||
						heading_stripped.get_char(0) >= 0x80)) {
					if (is_end_of_chunks) {
						return 0;
					}
					return -1;
				}
				var lead_skip = rest.index_of(heading_stripped);
				if (lead_skip > 0) {
					byte_length += lead_skip;
				}
			}
```

#### Replace with

```vala
			// ATX heading: any content until EOL; wait only when no content yet (incomplete line)
			if (matched_block >= FormatType.HEADING_1 && matched_block <= FormatType.HEADING_6) {
				var rest_start = chunk_pos + byte_length;
				var rest_len = (line_end != -1) ? line_end - rest_start : (int)chunk.length - rest_start;
				var rest = rest_len > 0 ? chunk.substring(rest_start, rest_len) : "";
				var heading_stripped = rest.strip();
				if (heading_stripped.length == 0) {
					if (is_end_of_chunks || line_end != -1) {
						return 0;
					}
					return -1;
				}
				var lead_skip = rest.index_of(heading_stripped);
				if (lead_skip > 0) {
					byte_length += lead_skip;
				}
			}
```

Fixture: `tests/markdown/repro-heading-bold.md`

```bash
build/oc-markdown-test tests/markdown/repro-heading-bold.md
```

## Follow-up (not this hang)

- ℹ️ `# **bold lead**` still emits literal `**` inside `<h1>` (mid-heading `**bold**` works). Separate from stream leftover.

## Next

- ⏳ 🔷 User verify stream no longer freezes on bold-led ATX
- ⏳ Optional: bold-at-start-of-heading inline parse
