# FIXED: ChatCompletions migration — streamed assistant content missing in UI

**Status: FIXED** (2026-05-31)

**Resolution:** (1) Serialize `"stream":true` on v1 request JSON in `ChatCompletions.get_request_body()`. (2) Map `reasoning` / `reasoning_content` deltas in `Message.vala`. (3) Treat `finish_reason:null` as not done — only JSON string `finish_reason` (e.g. `"stop"`) sets `Chunk.done` in `Chunk.vala`. Streaming works in app and CLI. **Metrics** fixed → `docs/bugs/done/2026-05-31-FIXED-chatcompletions-v1-metrics-missing.md`.

**Started:** 2026-05-30

**Related change:** commit `8caf1fae` — agent path switched from **`Call.Chat`** to **`Call.ChatCompletions`**.

---

## Problem (original)

After the OpenAI-compat migration, live assistant text did not stream in the chat UI.

**Expected:** Incremental tokens in the chat view.

**Actual (pre-fix):** Empty UI or metrics-only; no streamed body.

---

## Root causes (verified)

| Issue | Evidence | Fix |
|-------|----------|-----|
| `stream` omitted from JSON body | CLI logged body without `"stream":true`; one non-SSE blob | `obj.set_boolean_member("stream", this.stream)` |
| `finish_reason:null` treated as done | Every delta finalized session | Only `Json.NodeType.VALUE` for `finish_reason` sets `done` |
| `reasoning` vs `reasoning_content` | Thinking deltas ignored | Fall-through in `Message.deserialize_property` |

---

## Attempts / changelog

| Date | Change | Result |
|------|--------|--------|
| 2026-05-30 | curl wire-format comparison | v1 SSE vs native NDJSON |
| 2026-05-30 | CLI `stream` + `reasoning` fixes | Streamed content; one `content-stream` per reply |
| 2026-05-30 | `Chunk.finish_reason` null vs `"stop"` | No per-token finalize |
| 2026-05-31 | App smoke | Streaming output visible |
| 2026-05-31 | `oc-test-cli --legacy` after `session_activated` hook | True `/api/chat` vs v1 A/B |

---

## Conclusions

- Primary break was **`stream` not on the wire** plus **`finish_reason:null`** mishandling.
- **SSE-only `exec_stream`** is correct for Ollama v1 when `stream:true`.
- **Do not** use `eval_duration` / native duration fields for v1 metrics — see metrics bug doc.
