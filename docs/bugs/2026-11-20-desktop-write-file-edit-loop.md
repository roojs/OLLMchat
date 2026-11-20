# Desktop Agent Pi `write` test spins instead of creating file via edit mode

**Status:** ⏳ OPEN — edit-mode re-call loop and tool copy. Related: [stream-handler criticals](2026-11-20-edit-mode-stream-handler-criticals.md), [`active_tools` growth](2026-11-20-active-tools-stack.md).

**Started:** 2026-11-20

**Pointer:** `docs/bug-fix-process.md`

## Problem

- 🔷 Desktop harness test in project `gtktest1`: ask Agent Pi (`ornith-1.5:35b`) to create `test-file.txt` with ~50 lines of random text via the `write` tool.
- 🔷 Expected: one `write` call with `edit_mode=complete_file`, assistant streams a fenced code block, harness applies it, chat stops.
- 🔷 Actual: chat stayed on “waiting for ornith…” for ~3 minutes, UI felt stuck. Agent never finished cleanly; user stopped the run at **09:15:20**.
- 🔷 File on disk exists but was created by **`bash`** heredocs in the sandbox, not by streamed edit-mode fences.

## Reproduction (as run)

1. Open OLLMchat on desktop with `--debug` → `~/.cache/ollmchat/ollmchat.debug.log`.
2. Project: `/home/alan/gitlive/gtktest1` (no git repo; sandbox overlay).
3. Agent: `agent-pi`, model `ornith-1.5:35b`.
4. Prompt (session `2026-11-20-09-13-04`): create a test file with ~50 random lines for harness editing tests.
5. Observe: repeated tool activity, no clean completion; stop when stuck.

## Evidence

- ℹ️ Logs: `~/.cache/ollmchat/ollmchat.debug.log`, `~/.cache/ollmchat/ollmfilesd.debug.log` (2026-11-20 **09:12–09:15**).
- ✔️ **09:13:21** — first `write` fails validation (`RequestBase.vala:217`, tool id `H8AXhgFV…`). The tool message sent back to the model, in full, was:

```
ERROR: edit_mode must be one of: ast_path, line_numbers, complete_file
```

  - ✔️ That is the whole tool result (70 characters). The next assistant tool call used `edit_mode=complete_file`. The reply named the three legal values and the model followed it.
  - ✔️ Assistant text: `I'll create a test file with about 50 lines of random text.`
  - ✔️ Arguments only: `file_path=/home/alan/gitlive/gtktest1/test-file.txt`, `edit_mode=curry-combined`, `overwrite=false`. No file body in the tool call. `curry-combined` is not a mode name the schema lists.
  - ✔️ That string is not in the outbound prompt, the tool list, or this repo. Web search finds no agent tool with that mode. The closest published sentence is the Curry language report: "Curry combines in a seamless way…". The next assistant turn already used `edit_mode=complete_file`. Later log hits of `curry-combined` are that first tool call replayed in history.
  - ✔️ Schema sent to the model (`edit_mode` is a free string, description says default `ast_path`): `One of: ast_path, line_numbers, complete_file. Default is ast_path.`
- ✔️ **09:13:23** — second `write` succeeds with `edit_mode=complete_file`; tool reply is “Edit mode activated for file: …/test-file.txt” (455 chars).
- ℹ️ **09:13:23** — eight `edit_mode_stream_*` criticals on the stream between failed and successful `write`: see [2026-11-20-edit-mode-stream-handler-criticals.md](2026-11-20-edit-mode-stream-handler-criticals.md).
- ✔️ **09:13:23 – 09:13:40** — at least **10** back-to-back cycles: assistant `message_completed` with `active_tools.size=1`, `content_total=0`, then `Executing tool 'write'` and `Tool.activate_request: Cleaning up existing request for file …/test-file.txt`. Each cycle re-activates edit mode without applying fenced content.
- ✔️ **09:13:38+** — model switches to **`bash`**; sandbox `bwrap` runs `cat > …/test-file.txt << 'EOF'` (50-line heredoc in `ollmfilesd.debug.log` **09:14:55**). Further bash verify/rewrite at **09:15:01** and **09:15:15**.
- ✔️ **09:13:39 / 09:15:09** — `markdown_gtk_render_tool_output_output: assertion 'self != NULL' failed` (non-fatal; process kept running).
- ℹ️ **09:13:51 – 09:15:15** — `active_tools.size` climbs **2 → 7 → 11** — see [`active_tools` stack bug](2026-11-20-active-tools-stack.md) (mostly finished tools never unregistered, not many edit monitors at once).
- ✔️ **09:15:20** — stop/cancel: many `Connection was cancelled`, burst of `Request.reply_with_errors: Removed request from active_requests (remaining=0, file=…/test-file.txt)`.
- ✔️ **Disk:** `/home/alan/gitlive/gtktest1/test-file.txt` — **2081 bytes, 48 lines**, mtime **09:15** (not 50 lines; last bash rewrite).
- ✔️ **SQLite** (`~/.local/share/ollmchat/files.sqlite`): path `…/test-file.txt` — **1** `file_history` `added` + **6** `modified` rows, all `reviewed=0` (pending review from overlay writes, not from `write` tool apply).

## Timeline (short)

| Time | What happened |
|------|----------------|
| 09:12:42 | User prompt sent (duplicate-send warning at 09:13:04). |
| 09:13:21 | `write` #1 — invalid `edit_mode`. |
| 09:13:23 | `write` #2 — edit mode on; empty assistant body (criticals: sibling bug log). |
| 09:13:23–40 | `write` #3–#12+ — same file, cleanup/reactivate loop, no fences applied. |
| 09:13:38 | `bash` creates content via sandbox overlay. |
| 09:14–09:15 | More `write` + `bash` verify/overwrite. |
| 09:15:20 | User stop; cancelled HTTP + mass `reply_with_errors` cleanup. |

## Root cause (confirmed vs suspected)

### 1. Model loop — calls `write` again instead of streaming fences (user-visible “stuck”)

- ✔️ After each successful `write`, the harness starts the **next** chat completion immediately (`ChatCompletions.vala` right after tool result).
- ✔️ `ornith-1.5:35b` usually ends the next assistant turn with **another `write` tool call** and **`content_total=0`**, not a markdown code fence in message content.
- ✔️ `Tool.activate_request` (`liboctools/EditMode/Tool.vala:118–134`) **replaces** the prior edit-mode `Request` for the same path, so prior stream state is torn down before any fence is captured.
- 💩 The harness does not reject a second `write` for the same path while edit mode is already active (no “emit your fence in the current turn” guard).

### 2. Wrong path to a file on disk

- ✔️ Content reached disk only via **`bash`** + sandbox overlay RPCs, which enqueue **multiple unreviewed** `file_history` rows. That is a side effect of the loop, not the intended `complete_file` edit-mode apply path.

## Proposed fix (not applied)

- 🔷 **Harness guard:** If `edit_mode` is already active for `file_path`, return an error (or no-op with explicit instruction) instead of re-running `activate_request` when the model issues another `write` for the same path in the next turn.
- 🚫 **Aliasing `curry-combined`:** ruled out. The model sent a bad mode. The error reply already listed the three legal names, and the next call used `complete_file`. Add an alias only if a later run shows the same wrong name again and again.
- 🔷 **Richer tool error text on invalid args only:** Retry guidance and legal `edit_mode` values — **not** STOP / fence / streaming copy (that belongs on the success path only). See sections below.
- 🔷 **Success-path copy only:** STOP and fence rules live in the tool result after a **valid** `write`, not in invalid-mode errors.
- ℹ️ **Stream criticals / unregister:** [2026-11-20-edit-mode-stream-handler-criticals.md](2026-11-20-edit-mode-stream-handler-criticals.md).
- ℹ️ **`active_tools` map growth:** [2026-11-20-active-tools-stack.md](2026-11-20-active-tools-stack.md).

## Tool header (static API)

The model also sees `Write` tool `description` + parameters on every completion (see `liboctools/EditMode/Write.vala`) and a one-line Agent Pi system hint. That is the long-term API reference. It does **not** replace a targeted tool **result** on failure or the activation message on success.

## What happens when we send an invalid `edit_mode`

**Harness (today)**

- ✔️ `Request.execute_request` throws before `stream_handler` is created; edit mode is **not** on.
- ✔️ Failed request must not stay subscribed to the next stream (see [stream-handler bug](2026-11-20-edit-mode-stream-handler-criticals.md)).
- ✔️ Tool result to the model is **only**:

```
ERROR: edit_mode must be one of: ast_path, line_numbers, complete_file
```

- ✔️ In the gtktest1 session, ornith retried on the **next** turn with `edit_mode=complete_file` — so the one-line error was enough to recover the **mode** name, but not the streaming workflow (that arrived only after the second `write` succeeded).

**Proposed tool result (invalid `edit_mode` — retry `write` only; no STOP, no fences)**

Edit mode is still off. Do not append success-path copy (`INSTRUCTIONS_*`, `CODE_BLOCK_REQUIREMENT`, STOP, or “file will be written”).

````text
ERROR: edit_mode must be one of: ast_path, line_numbers, complete_file (you sent: "curry-combined").

Retry write with a valid edit_mode only:

- ast_path — partial edits on existing code (symbol path on the fence opener).
- line_numbers — partial edits by line range (existing file).
- complete_file — create a new file or replace the entire file.

For a new file, use edit_mode=complete_file with the same file_path (overwrite=false unless replacing an existing file).

For an existing file, use ast_path or line_numbers for partial edits, or complete_file with overwrite=true to replace the whole file.
````

- 💩 Implement via edit-mode `RequestBase` wrapper or richer `throw` messages — **not** by pasting the success tail.

## What happens when `write` succeeds (valid `edit_mode`)

**Harness**

- ✔️ `stream_handler` is created; `activate_request` registers edit mode for that path; tool monitoring receives stream chunks for this turn.
- ✔️ Tool result: `Edit mode activated for file: …` + `INSTRUCTIONS_*` for the chosen mode + `CODE_BLOCK_REQUIREMENT` (STOP / chat output / tool reply when the message completes).
- ✔️ When the assistant message ends, captured fence(s) apply; a follow-up tool/user message reports apply result (`reply_with_errors` / success summary).

**Multiple blocks in one message**

| Mode | Blocks per message |
|------|-------------------|
| `complete_file` | **One** fence only; extra blocks are ignored (`Stream.vala`). |
| `ast_path`, `line_numbers` | **One or more** fences; all applied in that message. |

**Proposed success tool result (`complete_file`, e.g. gtktest1)**

````text
Edit mode activated for file: /path/to/file.txt

edit_mode=complete_file replaces the entire file. On the opening ``` fence, do not use a colon (no line ranges or symbol paths). A plain ``` opener is fine.

Edit mode is on for this path. In this same chat message, output the full file content, you must STOP after outputting the content.

Wrap the full content in one opening and one closing ``` fence. Example:

```
content to write
```

When this message completes, the file is written and you will get a tool reply telling you the result.
````

**Proposed success tail (`ast_path` / `line_numbers`) — 💩 split copy in code**

Same activation line + existing `INSTRUCTIONS_AST` / `INSTRUCTIONS_LINE_RANGE`, then a mode-specific tail (not “full file content”): stream **one or more** fenced edits per those instructions, **you must STOP** after the last edit, then wait for the tool reply. No second `write` in the same flow.

**`complete_file` fence note**

In `Stream.vala`, the opener may be plain ` ``` ` or a tag **without colons**. That is for the parser, not “pick a programming language.”

## Implementation sketch (error vs success copy)

- ✔️ 2026-11-20 — `INSTRUCTIONS_COMPLETE_FILE` + shared `CODE_BLOCK_REQUIREMENT` in `Request.vala` (success path only today).
- 💩 `EDIT_MODE_ENUM_HELP` (or similar) — used **only** on validation errors; never mixed with STOP/fence workflow.
- 💩 `CODE_BLOCK_REQUIREMENT_COMPLETE_FILE` vs `CODE_BLOCK_REQUIREMENT_PARTIAL` — attach **only** after successful `execute_request`.
- 💩 Invalid `edit_mode`: append enum + retry hint; **do not** append success tail until a call actually activates edit mode.

## Attempts / changelog

- ✔️ 2026-11-20 — Read `ollmchat.debug.log`, `ollmfilesd.debug.log`, `files.sqlite`, on-disk `test-file.txt`; traced `liboctools/EditMode/{Request,Tool,Stream}.vala`.
- ✔️ 2026-11-20 — success-path LLM instructions (`CODE_BLOCK_REQUIREMENT`, `INSTRUCTIONS_COMPLETE_FILE`) updated in `Request.vala`.

## Next

- ⏳ 🔷 Reproduce with a single scripted `write` + forced fence reply (automated test or `tests/test-edit-ops.sh` extension).
- ⏳ 💩 Stream critical verify: [2026-11-20-edit-mode-stream-handler-criticals.md](2026-11-20-edit-mode-stream-handler-criticals.md).
- ⏳ 🔷 User-verify: one `write`, streamed fence, file applied without bash, chat completes without manual stop.