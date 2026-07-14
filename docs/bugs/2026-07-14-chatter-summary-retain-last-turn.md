# Chatter summarizes the last turn — lose full previous exchange

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ⏳ design stated — diagnose + propose fences next; no code yet

**Related:**

- ℹ️ [`docs/plans/2.31-just-ask-summary-history.md`](../plans/2.31-just-ask-summary-history.md)
  / [`2.31.1-chatter-summary-turn-queue.md`](../plans/2.31.1-chatter-summary-turn-queue.md)
  — summarize-after-every-turn + queue
- ℹ️ [`docs/bugs/2026-07-14-chatter-summary-hang.md`](2026-07-14-chatter-summary-hang.md)
  — UI hang (separate); same summarize pipeline
- ℹ️ Session example: `~/.local/share/ollmchat/history/2026/07/14/09-05-44.json`
  — HF download turn summarized; follow-up lost full tool reply detail and
  fell into weaker rediscovery (google_search / bad `model_ref`)

---

## Problem

- 🔷 Today we summarize **every completed turn**, including the turn that just
  finished. The next user send then sees mostly a **compressed summary**, not
  the full previous exchange.
- 🔷 Desired shape: outbound context is always roughly
  **summary (older history) + at least one full previous turn** (raw
  messages). Do **not** fold the latest completed turn into the summary until
  a newer turn has finished after it.
- 🔷 Symptom: follow-ups that need exact prior tool output (repo ids, file
  lists, help/mandates) lean on a lossy summary + `session_fetch`, and the
  model often re-searches or guesses instead of continuing from the live last
  turn.

## Current behaviour (code)

- ℹ️ After each chat queue item finishes, `PendingMessage.run_summarize` runs
  `Summarizer` on the turn that just completed
  (`libollmchat/Chatter/PendingMessage.vala`, `Agent/Summarizer.vala`).
- ℹ️ `Agent.Base.create_summary()` clears the slice at every `role == "summary"`
  and returns **[latest summary] + messages after it**. So once a turn is
  summarized, its assistant/tool rows are **behind** the boundary and are
  **not** sent as full messages on the next request—only via
  `{conversation_summary}` text (+ optional `session_fetch`).
- ℹ️ `chatter_followup.md` assumes that model: summary in the system slot,
  then only the new turn’s API messages after the boundary.

## Desired behaviour

- 🔷 Keep **≥1 full previous completed turn** as unsummarized session messages
  (API roles: user / assistant / tool — whatever `create_summary` already keeps).
- 🔷 Rolling summary covers only history **before** that retained full turn.
- 🔷 After turn N completes: summarize material that is now “older than the
  last full turn” (typically finish folding turn N−1 into the summary); leave
  turn N as the full previous for the next send. Do **not** summarize turn N
  immediately so turn N+1 still has the full previous.
- 🔷 First completed turn: no need to summarize yet (nothing older than “last”).
- 💩 Exact edge cases (tools mid-turn, Stop mid-turn, empty turns) — confirm
  when proposing fences.

## Evidence (symptom, not yet instrumented for this bug)

- ✔️ Same-day HF chat (`09-05-44`): after first summarize, Mandated block
  insisted on hub-only; second user ask for larger Gemma still lacked the
  prior **full** search/detail payload in-context; model used `google_search`
  (0 hits) then failed `detail` on guessed refs. Consistent with “last turn
  already rolled into summary only.”
- ⏳ Need debug of outbound assembly: sizes of summary vs post-boundary
  messages on turn 2+ to confirm mechanically (pending).

## Root cause (working — confirm with debug)

- 💩 Policy bug / product mismatch: summarize-after-every-turn +
  `create_summary` boundary = **no full previous turn** on the next request.
  Not a random model failure; the window we build drops the raw prior turn.

## Suggested order

1. 🔷 ⏳ Debug: log outbound after `create_summary` on follow-up sends
   (summary length / char preview; count of user|assistant|tool after boundary;
   index of last `user-sent` vs last `summary`).
2. 🔷 ⏳ Agree retention rule (one full previous turn = from last
   `user-sent` … end of that turn).
3. 🔷 ⏳ Change when Summarizer runs / what slice it summarizes (skip the
   newest completed turn; fold only older).
4. 💩 ⏳ Adjust `create_summary` / followup prompt if needed so retained full
   turn is always included after the summary blob.
5. 🔷 ⏳ Manual verify: two-turn HF (or similar) — turn 2 request contains full
   turn-1 tool replies, not summary-only.
6. 💩 ⏳ Remove debug; FIXED archive after ✅.

## Proposed fix

⏳ Concrete **Remove** / **Replace with** / **Add** fences after step 1–2
(user approve retention rule). Likely touch:

- ℹ️ `libollmchat/Agent/Summarizer.vala` — which message index range becomes
  `{turn_references}` / when to write a new `summary`
- ℹ️ `libollmchat/Chatter/PendingMessage.vala` — when to enqueue summarize
- ℹ️ `libollmchat/Agent/Base.vala` — `create_summary()` if the boundary must
  sit **before** the retained full turn rather than after the latest summary
  only

🚫 Do not “fix” by stuffing more into the Mandated summary prose alone —
  keep a real full previous turn on the wire.

## Attempts / changelog

- ✔️ 2026-07-14 — User stated: always summary + full last; do not summarize
  the last. Filed this bug (no code).

## Next

1. 🔷 ⏳ Approve debug targets (or retention rule wording) → add minimal
   `GLib.debug` on outbound assembly.
2. 🔷 ⏳ One follow-up Chatter turn with `--debug`; paste outbound sizes into
   this log.
3. 🔷 ⏳ Propose fences; await apply approval.
