# Task list UI: second task shows “Skill_docsbase” instead of “Skill analyze_docsbase”

## Problem

- **Symptom:** When viewing a skill-runner session in the chat/history UI, the second task’s skill line appears like **Skill_docsbase** (or equivalent), instead of the catalog skill **analyze_docsbase** with a normal **Skill** label.
- **Source session (local history):** `~/.local/share/ollmchat/history/2026/04/06/10-20-23.json`
- **Agent:** `skill-runner` (`qwen3.5:35b`).
- **Expected:** A line in the strict task-list shape, e.g. `- **Skill** analyze_docsbase` (space after the closing `**`, full skill name from the catalog).
- **Actual in stored assistant output:** The model emitted a **malformed** skill line with **no space** between the bold label and the skill name, and a **truncated** skill token.

### Representative `content-stream` fragments (message with role `content-stream`, first and second attempts)

Malformed (try 1):

```markdown
- **Skill**_docsbase
```

- Same streams also have `- **Skill**_code` (want `analyze_code`), and `- **What is**` (want `- **What is needed**`).
- Retry: **Previous Proposal** in the user message can show correct `- **Skill** analyze_docsbase`.
- Retry: next **`content-stream`** still repeats malformed `- **Skill**_docsbase` (try 2).

## Analysis trace (data → parse → render)

- **Data:** `content-stream` body literally contains `- **Skill**_docsbase` — not a missing field in JSON; the string is wrong vs strict format (need space + full skill id).
- **Parse:** `ListItem.key_value()` (`libocmarkdown/document/ListItem.vala`) — first bold = key `Skill`, rest = value starting `_docsbase` → reads as Skill + _docsbase.
- **Render:** GTK markdown shows that text; no separate “Skill_docsbase” constant in app code.
- **Root cause:** Bad model line shape (missing space, truncated skill token), not the renderer inventing `analyze_docsbase`.

## Attempts / changelog

- **History JSON** — Malformed lines in `content-stream`; “Previous proposal” can be correct while stream repeats errors.
- **Task list parser** — `List.to_key_map()` / `key_value()` → `_docsbase` is the value tail after key `Skill`.
- **Streaming (`42c11111`) — call trace**
  - `handle_streaming_response` → `process_json_streaming` → `read_line_async` per NDJSON line → `process_json_chunk`.
  - `process_json_streaming` **ignores** return value of `process_json_chunk` → loop detection `false` from `Chat.process_streaming_chunk` does **not** stop stream on live Ollama path.
  - `process_streaming` + `read_chunk` (4 KB) **does** throw on `process_json_chunk` → `false` — but **`process_streaming` is never called** (dead).
  - Pre-test static note: no obvious byte-drop in NDJSON assembly — **superseded:** revert A/B confirms the **change still broke streaming** (exact failure mode: see testing notes / debug next).
- **Streaming — other**
  - `process_json_streaming`: `line_buffer` never appended; tail `if (line_buffer.len > 0)` is dead (old leftover).
  - `process_json_chunk`: if `!trimmed.has_suffix("}")`, whole line skipped → can drop only if line incomplete (unusual per line).

## Confirmed — revert A/B (`42c11111` vs revert)

- **Commit `42c11111` (“add recusions detection”) breaks streaming** in normal use (symptoms vs pre-change behavior).
- **Reverting that commit restores working streaming** (see `5cf198c2` Revert on `main`, plus doc-only restore `1cb170ea` if present).
- **Static code review before this test was wrong** to “rule out” that diff: the regression is real even though NDJSON `process_json_streaming` ignored the new `bool` return.
- **Mechanism (identified):** In `42c11111`, `check_back_token()` could `return false` **before** `stream_chunk` / `handle_stream_chunk` — Session/UI never got that delta while `addChunk` had already updated `message.content`.
- **Fix applied:** `libollmchat/Call/Chat.vala` — run `back_tokens` insert + `check_back_token()` **after** `stream_chunk` / `handle_stream_chunk` (same token from `addChunk`).

## Conclusions

- **Two separate things:**
  - **Skill line text** (`Skill_docsbase`): stored `content-stream` still shows **model malformed** `- **Skill**_docsbase` — that is **not** fixed by the streaming revert; it is bad token/text in the assistant body.
  - **Streaming behavior:** **Regressed by `42c11111`** — confirmed by revert test; **Chat ordering fix** (loop check after UI signals) applied; re-test with loop detection on.
- **Ruled in:** Model emits `- **Skill**_…` / `_docsbase` instead of full `analyze_docsbase` (history JSON).
- **Ruled out:** App builds a literal constant “Skill_docsbase” for display; system prompt lists `analyze_docsbase` correctly.
- **Still open:** Wire `process_json_streaming` to throw/stop on `process_json_chunk` → `false` per plan 6.13 (NDJSON path still ignores bool today).

## Open questions / next steps

- **Runner validation:** Reject `- **Skill**_docsbase`? If yes, UI may still show bad stream before validation; if no, tighten validation?
- **Prompt / template:** Add negative example: never `- **Skill**_name`; always space after `**` + full skill id.
- **Optional UI:** Warn when `Skill` value starts with `_` (product call; not a fix for bad model output).

## After a fix (when applicable)

- Re-run `build/oc-test-gtkmd --history ~/.local/share/ollmchat/history/2026/04/06/10-20-23.json` or a minimal markdown fixture with correct vs malformed lines.
- If code changes: note commit/plan here; remove any temporary debug logging per `docs/bug-fix-process.md`.
