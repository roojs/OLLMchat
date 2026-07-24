# Chatter summarizes the last turn — lose full previous exchange

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✔️ applied — ⏳ await ✅ verify

**Related:**

- ℹ️ [`docs/plans/2.31-just-ask-summary-history.md`](../plans/2.31-just-ask-summary-history.md)
  / [`2.31.1-chatter-summary-turn-queue.md`](../plans/2.31.1-chatter-summary-turn-queue.md)
- ℹ️ [`docs/bugs/done/2026-07-14-FIXED-chatter-summary-hang.md`](done/2026-07-14-FIXED-chatter-summary-hang.md)
- ℹ️ Separate: [`2026-07-24-session-fetch-index-listing.md`](2026-07-24-session-fetch-index-listing.md)
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

1. ⏳ 🔷 Verify two-turn Chatter: turn 2 outbound includes full turn-1 rows.
2. ⏳ When ✅: archive under `docs/bugs/done/` with `FIXED`.
