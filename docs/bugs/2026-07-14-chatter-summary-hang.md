# Chatter hangs after conversation summary (Stop required)

**Status:** OPEN — evidence partial; need completion-path debug before fix

**Related (wrong framing):** `docs/plans/2.31.1-chatter-summary-turn-queue.md`
was treated as a feature/plan. The failing behaviour is a **hang after the
summary stream** and should follow `docs/bug-fix-process.md` (debug →
evidence → root cause → propose → approve → fix). The queue plan may stay for
FIFO design; it is **not** the bug log.

## Problem

After a Chatter turn finishes (assistant stream ends), the app shows
**"summarizing conversation"** and stays in that state until the user presses
**Stop**. Send/input stay blocked (Stop visible).

Expected: summary finishes (or fails visibly), waiting UI clears, Send returns
without requiring Stop.

## Reproduction

1. Run main app with `--debug`.
2. Start a Chatter session that completes a normal (or tool) turn.
3. Wait for assistant stream to end; observe summarizing waiting UI.
4. Leave it; UI does not recover until Stop.

Log from 2026-07-14 ~08:08 session (`~/.cache/ollmchat/ollmchat.debug.log`):

## Evidence already in log (no guess)

Session: gemma/huggingface tool turn → then summary request.

| Time | What log shows |
|------|----------------|
| 08:09:12.957 | Final **chat** stream finished (`content_total=760`) |
| 08:09:12.970 | **Summary** `ChatCompletions` started (system prompt = Chatter conversation summariser) |
| 08:09:22.586 | **Summary** stream finished (`content_total=759`) |
| 08:09:22.596–610 | `Session` save / saved |
| *(~1.7 min silence)* | No further summary/queue debug (there is none today) |
| 08:11:05.190 | `Session.vala:547: Stopping running` (user Stop) |

So the hang is **not** “summary never starts” and **not** “summary HTTP stream
never finishes”. The LLM summary call **did** complete. Something **after**
that point (backend and/or UI) leaves the session looking busy until Stop.

## Not yet known (must debug — do not assume)

Whether any of these completed after 08:09:22:

1. `Summarizer.run` returned after `yield chat_call.send`
2. Validation / early `return` / `done.set_value` in `run_summarize`
3. Chatter `Agent.send_async` drain loop finished and `wait_async` returned
4. `Session.send` returned to the UI caller

Whether Stop only cleared **UI** (`streaming_state` via `agent_status_change`)
while a `yield` was still stuck, or truly unblocked the agent path.

## UI clue (hypothesis — not confirmed root cause)

From code reading (needs confirm with debug):

- `Summarizer.handle_stream_started` → `message_added(ui-waiting, "summarizing…")`
- `ChatWidget` on `ui-waiting`: `show_waiting_indicator` **and**
  `streaming_state(true)` (forces Stop / hides input)
- Chat path clears `session.is_running` when chat `send` finishes; summarizer
  does **not** toggle `is_running`
- Completion of summary adds `role=summary` via `message_added`; that case
  **does not** call `streaming_state(false)` or clear waiting via the
  `agent_status_change` path unless `is_running` flips again
- Stop → `cancel_current_request` → `is_running = false` +
  `agent_status_change` → `streaming_state(false)` — matches “fixed by Stop”

This can explain **Stop as the only recovery** even if the backend already
finished. It does **not** by itself prove the backend is idle; we need
completion logs.

## Attempts / changelog

- 2026-07-14 — Read `~/.cache/ollmchat/ollmchat.debug.log` for last hang.
  Captured timeline above. **No code change yet.**

## Debug to add (proposed — await approval)

Minimal `GLib.debug` only (file/line already in output; no class spam):

1. `libollmchat/Chatter/PendingMessage.vala`
   - enter/leave `run` with `is_chat`
   - enter/leave `run_summarize` + after `done.set_value`
2. `libollmchat/Agent/Summarizer.vala` — `run`
   - after `yield chat_call.send` (draft empty? / ok)
   - validation issue string or success `return`
   - early returns (`user_sent_index`, no connection)
3. `libollmchat/Chatter/Agent.vala` — `send_async`
   - after drain `while`, before/after `wait_async`
4. Optional UI: `ChatWidget` when handling `ui-waiting` and `summary` —
   log `streaming=` and `is_running=` so we see sticky Stop state

How to capture: rebuild, run app `--debug`, one Chatter turn, wait for hang,
then `tail` / search `~/.cache/ollmchat/ollmchat.debug.log` for the new lines
before any Stop, and again after Stop if still used.

## Conclusions

- Ruled **in**: summary HTTP stream completes; hang is post-stream.
- Ruled **out**: “summarizer never called” for this repro.
- Root cause: **not certain** until completion-path debug shows where
  control stops (backend await vs UI sticky `streaming_state`).

## Next

1. Approve debug above → add → re-run one hang.
2. From new lines, name the exact stuck site.
3. Propose a single root-cause fix; apply only after approval.
