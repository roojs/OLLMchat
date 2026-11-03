# Markdown parser aborts on an empty HTML element

**Status:** ✅ 2026-11-03. Opening a markdown file stays up. HTML elements in the file do not abort the process.

## Problem

- 🔷 Tapping a markdown file name on the tablet reads the file, then the app dies. The file never stays open.
- 🔷 `README.md` is enough. The demo line is a `<video …></video>` element.
- 🔷 Expected: the markdown view shows the file. A parse error in one tag does not abort the process.

## Evidence

- ✔️ Tablet, Pixel Tablet emulator, `org.roojs.ollmchat.androidpoc` pid 7636, 2026-10-31 14:57:29. Tap on `README.md` in the file sheet.
  - `File.read` of `/home/alan/gitlive/OLLMchat/README.md` returned, `loaded=true`, `chars=9977`.
  - Then `markdown_parser_add` aborted. Tombstone `tombstone_05`. Signal 6. Stack frame `oll_mcoder_doc_view_show_file`.
- ✔️ `MarkdownView.show_file` feeds `file.buffer` through one `add` and then `flush`. That is the same pair `oc-markdown-test` uses.
- ✔️ `build/examples/oc-markdown-test README.md` aborts at `Parser.vala:582` after it has emitted the opening `<video …>` node.
- ✔️ The abort is not any HTML. Same binary:
  - `<div></div>` parses.
  - `Before <span>x</span>` parses.
  - `<div align="center">` then a newline parses.
  - `Before <div></div>` aborts at `Parser.vala:582`.
  - `Hello`, then a newline, then `<div></div>` aborts at `Parser.vala:582`.
  - `Before <video src="a.mp4"></video> after` aborts at `Parser.vala:582`.

- ✔️ `tests/markdown/repro-html-empty-element.md` is the short case. `repro-*` is already skipped by `tests/test-markdown-doc.sh`.
- 🚫 A plain `<div>` at the start of the file is not this bug. `text_start_pos` is already 0, so the assert happens to pass.

## Root cause

- ✔️ `add` keeps the start of the current text run in `text_start_pos`. Before `handle_format_result`, that index is moved up to the `<`.
- ✔️ `FormatMap.handle_format_result` emits that text, then `add_html` consumes the opening tag. For `<div></div>` the tail it returns is `</div>…`, which starts with `<`.
- ✔️ That call is not the end of the input (`add` of the whole file, `is_end_of_chunks` false). The branch at `FormatMap.vala:339` treats “tail starts with `<`” as “need more input”, stores the tail as `leftover_chunk`, sets `chunk_pos` to 0, and returns true.
- ✔️ The caller then asserts `str == "" && text_start_pos == chunk_pos`. `str` is empty. `text_start_pos` is still the old offset of `<`, and `chunk_pos` is 0. Vala `assert` is fatal.
- ✔️ A tag at byte 0 survives because those two indexes are both 0. `flush` then parses the leftover close tag. That is why `<div></div>` alone works.
- ✔️ Text between the brackets (`<span>x</span>`) never takes this branch. The tail starts with `x`, not `<`.
- ✔️ `README.md` hits it because the `<video` is not byte 0 of the chunk (the chunk is the whole file) and the next byte after `>` is `<` of `</video>`.

## Proposed fix

- 💩 `handle_format_result` treats every tail that starts with `<` as “need more input”.
  - A finished tag hands back the next tag, such as `</div>`.
  - That is not an unfinished tag.
  - Return true only when `add_html` hands back `"<"` or `"<" +` the string it was given.

### 1. `libocmarkdown/FormatMap.vala` — `handle_format_result`: finished HTML tag keeps parsing

**Why:**
- `add_html` on `<div></div>` returns `</div>`.
- The current branch stores that tail and returns true.
- `Parser.add` then asserts `text_start_pos == chunk_pos`.
- `text_start_pos` is still the offset of the opening `<`.
- `chunk_pos` is 0.
- A false return lets the existing loop set `text_start_pos = chunk_pos` and keep parsing.

**Where:** `handle_format_result`, the HTML branch after `peekHTML` accepts a tag. From `chunk_pos = seq_pos` through the final `return false`.

**Depends on:** none.

#### Remove

```vala
			chunk_pos = seq_pos;
			chunk = this.parser.add_html(chunk.substring(chunk_pos, chunk.length - chunk_pos));
			chunk_pos = 0;
			if (chunk.length > 0 && chunk.get_char(0) == '<' && is_end_of_chunks) {
				return false;
			}
			if (chunk.length > 0 && chunk.get_char(0) == '<') {
				this.parser.leftover_chunk = str + chunk; // a bit werid as we have modified chunk in here
				return true;
			}
			return false;
```

#### Replace with

Return true only when the tail is an unfinished tag. `html_in` is the string passed to `add_html`. `chunk` is overwritten by the return, so the input has to be kept for the unfinished check.

```vala
			chunk_pos = seq_pos;
			var html_in = chunk.substring(chunk_pos, chunk.length - chunk_pos);
			chunk = this.parser.add_html(html_in);
			chunk_pos = 0;
			if (chunk.length == 0 || chunk.get_char(0) != '<') {
				return false;
			}
			if (is_end_of_chunks) {
				return false;
			}
			if (chunk != "<" && chunk != "<" + html_in) {
				return false;
			}
			this.parser.leftover_chunk = str + chunk;
			return true;
```

- 🚫 A chunk split inside an unfinished tag (`Before <di` then `v>`) still returns true and can still hit the same assert. The tablet path sends the whole file in one `add`. That split is not this bug.

## Attempts / changelog

- ✔️ 2026-11-01: applied the `FormatMap.handle_format_result` fence in `libocmarkdown/FormatMap.vala`.
- ✔️ `ninja -C build examples/oc-markdown-test examples/oc-markdown-doc-test examples/oc-md2html` succeeded.
- ✔️ `build/examples/oc-markdown-test tests/markdown/repro-html-empty-element.md` exit 0. Trace has `START: <div>`, `END: <div>`, and `=== END TRACE ===`.
- ✔️ `build/examples/oc-markdown-test README.md` exit 0. Trace has `START` / `END` for both `<video>` elements and `=== END TRACE ===`.
- ✔️ `meson test -C build --suite markdown`: `test-markdown-parser` OK, `test-markdown-doc` OK.

## Next

- ✅ 2026-11-03 — user confirmed markdown files open and stay open.
