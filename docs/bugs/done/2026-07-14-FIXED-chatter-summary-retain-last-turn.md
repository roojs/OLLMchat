# FIXED — Chatter summarizes the last turn — lose full previous exchange

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✅ FIXED — user closed 2026-07-25

**Related:**

- ℹ️ [`docs/plans/done/CHAT-2.31-DONE-just-ask-summary-history.md`](../plans/done/CHAT-2.31-DONE-just-ask-summary-history.md)
  / [`CHAT-2.31.1-DONE-chatter-summary-turn-queue.md`](../plans/done/CHAT-2.31.1-DONE-chatter-summary-turn-queue.md)
- ℹ️ [`docs/bugs/done/2026-07-14-FIXED-chatter-summary-hang.md`](2026-07-14-FIXED-chatter-summary-hang.md)
- ℹ️ Separate: [`docs/bugs/done/2026-07-24-FIXED-session-fetch-index-listing.md`](2026-07-24-FIXED-session-fetch-index-listing.md)
  — `session_fetch` discoverability (not this bug)

---

## Problem

🔷 After each Chatter turn we summarize **that turn immediately**. The next
send then gets mostly a compressed summary — **not** the full previous
exchange.

🔷 Desired: compress only history **before** the previous (latest completed)
turn. Outbound stays **summary + full previous turn**.

---

## Root cause

✔️ `Summarizer.run` built `{turn_references}` from the **latest** `user-sent`
through `messages.size`. That folded the turn that should stay raw into the
summary boundary used by `create_summary()`.

---

## Fix applied

✔️ `libollmchat/Agent/Summarizer.vala` — summarize `[prev_user_sent, last_user_sent)`;
skip when there is only one completed turn.

---

## Next

Archived to `docs/bugs/done/` as FIXED (user closed 2026-07-25).
