# session_fetch: no index listing when the model lacks a tag

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✔️ applied — ⏳ await ✅ verify

**Started:** 2026-07-24

**Related:**

- ℹ️ Retain-last-turn (separate): [`2026-07-14-chatter-summary-retain-last-turn.md`](2026-07-14-chatter-summary-retain-last-turn.md)
- ℹ️ Pman.Ai already has omit/`index`/`*` → one-line listing
  (`Pman.Ai.Tool.session_fetch.js`) — **🚫** do not edit Pman.Ai; port the
  behaviour here only.

---

## Problem

🔷 With summarized Chatter history, the model often **guesses** tags or cannot
rediscover what to fetch. `session_fetch` today **requires** a `role-N`
reference; empty/bad calls only return short errors — no list of available
messages.

🔷 Desired: pass `reference` as `"index"` → markdown listing of every available
tag + one-line preview. Invalid / out-of-range references should **point the
model at `"index"`** (not dump the full listing into the error).

---

## Fix applied

✔️ `liboctools/SessionFetch/Request.vala` — `"index"` returns tag listing;
bad refs hint to use `"index"`.
✔️ `liboctools/SessionFetch/Tool.vala` — description / `@param` updated.
✔️ `resources/chat-prompts/chatter_followup.md` + `chatter_summary.md` — one
line each about `"index"`.

---

## Next

1. ⏳ 🔷 Verify: `"index"` → listing; bad tag → short hint to use `"index"`.
2. ⏳ When ✅: move to `docs/bugs/done/` with `FIXED`.
