# `write` tool — LLM result copy (validation + success STOP)

**Status:** ✅ 2026-11-23. User closed. Applied 2026-11-21 in `liboctools/EditMode/Request.vala`.

**Started:** 2026-11-21

**Pointer:** `docs/bug-fix-process.md`

**Related:** [gtktest1 edit-loop](2026-11-20-FIXED-desktop-write-file-edit-loop.md) (why this matters). Harness bugs: [stream-handler criticals](2026-11-21-FIXED-edit-mode-stream-handler-criticals.md).

## Problem

- 🔷 After a **valid** `write`, the model should stream fence(s) in the **same assistant message**, then **STOP** (no more tool calls until the **agent** sends a **confirmation message**). gtktest1 (`ornith-1.5:35b`) often called `write` again or `bash` with `content_total=0`.
- 🔷 After an **invalid** `edit_mode`, the tool result is a **one-line** `ERROR:` — enough to fix the enum name, not enough to pick the right mode for “new file vs partial edit.”
- 🔷 **Success copy today** uses one shared `CODE_BLOCK_REQUIREMENT` for every mode, including “output the **full file content**” on `ast_path` / `line_numbers`.

## Output map (what the model sees)

| Situation | Edit mode on? | Source |
|-----------|----------------|--------|
| Invalid `edit_mode` (or other throw before `stream_handler`) | No | `RequestBase.execute` → `ERROR: ` + exception message |
| Valid `write` | Yes | `Request.execute_request` return string (constants + path line) |
| Apply finished / errors | N/A | Agent **`reply_with_errors`** / **`send_append`** → next turn includes a **confirmation message** (user role on the wire) — **not** another `write` tool call. |

Static tool schema (`Write.vala` description + parameters) is unchanged here.

### After you STOP (terminology for LLM copy vs wire format)

| Audience | Terminology |
|----------|-------------|
| **LLM instructions** (tool result text) | **The agent** will send a **confirmation message** (edits applied / file written), then **you may continue** — not “we”, not “tool reply”. |
| **Wire / history** (implementers) | `reply_with_errors` → `send_append` adds a **user**-role chat message with the confirmation text (e.g. file updated, line count). That is **not** a second `write` tool result. |
| **Avoid** | “Tool reply”, “whether the file was written” (sounds like another tool call); “we will send you” (wrong voice). |

---

## 1. Invalid `edit_mode`

**Where:** `liboctools/EditMode/Request.vala` — `execute_request()` validation throw.

**Why:** Edit mode stays off. Retry `write` with a legal mode only — **no** STOP, no fence workflow.

### Before (tool result today)

````text
ERROR: edit_mode must be one of: ast_path, line_numbers, complete_file
````

### After (proposed tool result)

````text
ERROR: edit_mode must be one of: ast_path, line_numbers, complete_file (you sent: "<actual>").

Retry write with a valid edit_mode only:

- ast_path — partial edits on existing code (symbol path on the fence opener).
- line_numbers — partial edits by line range (existing file).
- complete_file — create a new file or replace the entire file.

For a new file, use edit_mode=complete_file with the same file_path (overwrite=false unless replacing an existing file).

For an existing file, use ast_path or line_numbers for partial edits, or complete_file with overwrite=true to replace the whole file.
````

### Remove

```vala
			if (this.edit_mode != "ast_path"
				&& this.edit_mode != "line_numbers"
				&& this.edit_mode != "complete_file") {
				throw new GLib.IOError.INVALID_ARGUMENT(
					"edit_mode must be one of: ast_path, line_numbers, complete_file");
			}
```

### Replace with

```vala
			if (this.edit_mode != "ast_path"
				&& this.edit_mode != "line_numbers"
				&& this.edit_mode != "complete_file") {
				throw new GLib.IOError.INVALID_ARGUMENT(
					"edit_mode must be one of: ast_path, line_numbers, complete_file (you sent: \""
					+ this.edit_mode + "\").\n\n"
					+ "Retry write with a valid edit_mode only:\n\n"
					+ "- ast_path — partial edits on existing code (symbol path on the fence opener).\n"
					+ "- line_numbers — partial edits by line range (existing file).\n"
					+ "- complete_file — create a new file or replace the entire file.\n\n"
					+ "For a new file, use edit_mode=complete_file with the same file_path "
					+ "(overwrite=false unless replacing an existing file).\n\n"
					+ "For an existing file, use ast_path or line_numbers for partial edits, "
					+ "or complete_file with overwrite=true to replace the whole file.");
			}
```

- 💩 Optional later: shared `private const string EDIT_MODE_ENUM_HELP` — same text, thrown from one place; **not** mixed into success tail.

---

## 2. Success — `complete_file`

**Where:** `Request.vala` constants + `execute_request()` assembly (`llm_message += …`).

**Why:** gtktest1 case (new file, whole body in one fence). Emphasize **this message only**, **STOP**, **no second `write`**, **no shell tools** for this file until apply reply.

### Before (assembled tool result today)

````text
Edit mode activated for file: /path/to/file.txt

edit_mode=complete_file replaces the entire file. On the opening ``` fence, do not use a colon (no line ranges or symbol paths). A plain ``` opener is fine.

After write succeeds, edit mode is on for this path. In this same chat message, output the full file content, you must STOP after outputting the content.

Wrap the full content in one opening and one closing ``` fence. Example:

```
content to write
```

When this message completes, the file is written and you will get a tool reply telling you the result.
````

_Inaccurate:_ follow-up is a **user** notification after apply, not a second `write` tool result.

### After (proposed)

````text
Edit mode activated for file: /path/to/file.txt

edit_mode=complete_file replaces the entire file. On the opening ``` fence, do not use a colon (no line ranges or symbol paths). A plain ``` opener is fine.

Edit mode is on for this path. In this same assistant message only:

1. Output the full file content inside one opening and one closing ``` fence.
2. Do not call write again or any other tool for this file in this message.
3. STOP generating when the closing fence is done — the agent will send a confirmation message that the file has been written, and you may continue then.

Example:

```
content to write
```
````

### Remove

```vala
		private const string CODE_BLOCK_REQUIREMENT = """
After write succeeds, edit mode is on for this path. In this same chat message, output the full file content, you must STOP after outputting the content.

Wrap the full content in one opening and one closing ``` fence. Example:

```
content to write
```

When this message completes, the file is written and you will get a tool reply telling you the result.
""";
```

### Replace with

```vala
		private const string CODE_BLOCK_REQUIREMENT_COMPLETE_FILE = """
Edit mode is on for this path. In this same assistant message only:

1. Output the full file content inside one opening and one closing ``` fence.
2. Do not call write again or any other tool for this file in this message.
3. STOP generating when the closing fence is done — the agent will send a confirmation message that the file has been written, and you may continue then.

Example:

```
content to write
```
""";
```

### Remove

```vala
			llm_message += "\n" + CODE_BLOCK_REQUIREMENT;
```

### Replace with

```vala
			llm_message += "\n" + (this.edit_mode == "complete_file"
				? CODE_BLOCK_REQUIREMENT_COMPLETE_FILE
				: CODE_BLOCK_REQUIREMENT_PARTIAL);
```

(Introduce `CODE_BLOCK_REQUIREMENT_PARTIAL` in section 3 before applying this hunk.)

---

## 3. Success — `ast_path` / `line_numbers`

**Where:** same file — new partial constant; same `execute_request` branch as §2.

**Why:** Partial modes allow **one or more** fenced edits, not “full file content.” Same STOP / no extra tools in **this** message.

### Before

Same tail as `complete_file` today (`CODE_BLOCK_REQUIREMENT` — “full file content”).

### After (proposed partial tail only)

````text
Edit mode is on for this path. In this same assistant message only:

1. Output one or more fenced edits per the instructions above.
2. Do not call write again or any other tool for this file in this message.
3. STOP generating after the last fence — the agent will send a confirmation message that your edits have been applied, and you may continue then.
````

### Add

```vala
		private const string CODE_BLOCK_REQUIREMENT_PARTIAL = """
Edit mode is on for this path. In this same assistant message only:

1. Output one or more fenced edits per the instructions above.
2. Do not call write again or any other tool for this file in this message.
3. STOP generating after the last fence — the agent will send a confirmation message that your edits have been applied, and you may continue then.
""";
```

- ✔️ Keep existing `INSTRUCTIONS_AST` and `INSTRUCTIONS_LINE_RANGE` as-is unless a later pass tightens them.

---

## 4. Unchanged / out of scope

| Output | Note |
|--------|------|
| `file_path` empty, read failures, permission deny | Keep current short `ERROR:` lines unless a separate pass requests richer copy. |
| `to_summary()` / UI frame | Stays human-oriented; not the LLM tool result body. |
| `OVERWRITE_MESSAGE` | Still appended only when `overwrite && !creating_file`. |
| Repeat `write` on same path | **Allowed** — `activate_request` may replace prior monitor; no guard. |

## Ruled out

- 🚫 Duplicate-`write` guard while edit mode active — see [gtktest1 log](2026-11-20-FIXED-desktop-write-file-edit-loop.md).
- 🚫 Alias bogus mode names (e.g. `curry-combined`).

## Attempts / changelog

- ✔️ 2026-11-20 — gtktest1 logs; partial success-path update (`INSTRUCTIONS_COMPLETE_FILE`, first `CODE_BLOCK_REQUIREMENT` draft).
- ℹ️ 2026-11-21 — Split tidy copy spec (this file); split complete vs partial STOP tails.
- ✔️ 2026-11-21 — Applied §1–§3 in `Request.vala` per Remove/Replace blocks above.

## Next

- ✅ 2026-11-23 — User confirmed done; archived.