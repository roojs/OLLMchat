# Desktop Agent Pi `write` test spins instead of creating file via edit mode

**Status:** ✅ Closed 2026-11-21 — harness fixes landed; LLM copy in [write-tool-llm-copy](2026-11-21-FIXED-write-tool-llm-copy.md). Related: [stream-handler criticals](2026-11-21-FIXED-edit-mode-stream-handler-criticals.md), [monitored-requests](2026-11-21-FIXED-monitored-requests-stack.md), [stacked diff baseline](2026-11-21-FIXED-test-file-stacked-add-diff-baseline.md).

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
- ℹ️ **09:13:23** — eight `edit_mode_stream_*` criticals on the stream between failed and successful `write`: see [done/2026-11-21-FIXED-edit-mode-stream-handler-criticals.md](done/2026-11-21-FIXED-edit-mode-stream-handler-criticals.md).
- ✔️ **09:13:23 – 09:13:40** — at least **10** back-to-back cycles: assistant `message_completed` with `active_tools.size=1`, `content_total=0`, then `Executing tool 'write'` and `Tool.activate_request: Cleaning up existing request for file …/test-file.txt`. Each cycle re-activates edit mode without applying fenced content.
- ✔️ **09:13:38+** — model switches to **`bash`**; sandbox `bwrap` runs `cat > …/test-file.txt << 'EOF'` (50-line heredoc in `ollmfilesd.debug.log` **09:14:55**). Further bash verify/rewrite at **09:15:01** and **09:15:15**.
- ✔️ **09:13:39 / 09:15:09** — `markdown_gtk_render_tool_output_output: assertion 'self != NULL' failed` (non-fatal; process kept running).
- ℹ️ **09:13:51 – 09:15:15** — map size climbs **2 → 7 → 11** — see [monitored-requests stack](done/2026-11-21-FIXED-monitored-requests-stack.md) (mostly finished tools never unregistered, not many edit monitors at once).
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
- ✔️ When the model calls `write` again for the same path, `Tool.activate_request` (`liboctools/EditMode/Tool.vala:118–134`) **replaces** the prior `Request` — intentional so a single agent can **restart** edit mode (e.g. new mode or a fresh attempt). That is not a harness bug.
- ✔️ gtktest1 symptom: the model **never streamed fences** between those `write` calls (`content_total=0`), then used `bash` — wrong workflow, not “forbidden second `write`.”

### 2. Wrong path to a file on disk

- ✔️ Content reached disk only via **`bash`** + sandbox overlay RPCs, which enqueue **multiple unreviewed** `file_history` rows. That is a side effect of the loop, not the intended `complete_file` edit-mode apply path.

## Fix direction

- 🔷 **Tool result copy only** — before/after and Vala **Remove / Replace** in [2026-11-21-FIXED-write-tool-llm-copy.md](2026-11-21-FIXED-write-tool-llm-copy.md).
- 🚫 **Duplicate-`write` guard** — ruled out (2026-11-21); repeat `write` + `activate_request` cleanup stays allowed.
- ℹ️ Harness fixes (stream monitor, `monitored_requests`) — done in sibling bug logs.

## Attempts / changelog

- ✔️ 2026-11-20 — Read `ollmchat.debug.log`, `ollmfilesd.debug.log`, `files.sqlite`, on-disk `test-file.txt`; traced `liboctools/EditMode/{Request,Tool,Stream}.vala`.
- ✔️ 2026-11-20 — success-path LLM instructions (`CODE_BLOCK_REQUIREMENT`, `INSTRUCTIONS_COMPLETE_FILE`) updated in `Request.vala`.

## Next

- ✅ LLM copy — [2026-11-21-FIXED-write-tool-llm-copy.md](2026-11-21-FIXED-write-tool-llm-copy.md) closed 2026-11-23.
- ⏳ 💩 Optional: scripted harness test with forced fence reply.