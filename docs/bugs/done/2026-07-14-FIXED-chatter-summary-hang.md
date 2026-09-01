# Chatter hangs after conversation summary (Stop required)

> Pointer: `docs/bug-fix-process.md` (emoji + code fences). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** FIXED (2026-07-18) — user confirmed.

**Related:**

- ℹ️ [`docs/plans/done/CHAT-2.31.1-DONE-chatter-summary-turn-queue.md`](../plans/done/CHAT-2.31.1-DONE-chatter-summary-turn-queue.md)
  — queue design (separate); hang is UI, not promise deadlock
- ℹ️ Log: `~/.cache/ollmchat/ollmchat.debug.log`

---

## Problem

- 🔷 After Chatter assistant stream ends, input briefly reappears.
- 🔷 Summarization starts → text window hides again; Stop shown.
- 🔷 Summary finishes in the backend, but Send stays blocked until Stop.
- 🔷 Summarize must run with the **text window open**.
- 🔷 Keep the animated **waiting indicator** — must **not** enter Stop / hide-input.

## Root cause (confirmed)

- ✔️ Backend did not hang; Summarizer emitted blocking `ui-waiting` after
  `is_running=false`; ChatWidget always called `streaming_state(true)`.

## Design applied

- 🔷 Exact `"ui-waiting"` → dots + hide input / Stop.
- 🔷 `"ui-waiting-bg"` → dots only (Summarizer).
- 🔷 Session: `role.has_prefix("ui-waiting")` for skip / restore / serialize.
- 🔷 On `summary`: clear waiting + `streaming_state(is_running)`.

## Suggested order

1. 🔷 ✔️ §1 — `Message.vala`
2. 🔷 ✔️ §2 — `Summarizer` → `ui-waiting-bg`
3. 🔷 ✔️ §3 — `ChatWidget` waiting family + `summary` cleanup
4. 🔷 ✔️ §4 — `Session` `has_prefix`
5. 🔷 ⏳ Manual verify
6. 💩 ⏳ Remove temporary hang-debug after ✅

## Files changed

- ✔️ `libollmchat/Message.vala`
- ✔️ `libollmchat/Agent/Summarizer.vala`
- ✔️ `libollmchatgtk/ChatWidget.vala`
- ✔️ `libollmchat/History/Session.vala`

## Next

_(Closed — user confirmed fixed 2026-07-18.)_