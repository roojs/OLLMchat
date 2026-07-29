# 06. Steer / follow-up

Status: ⏳ proposed

ℹ️ Checklist: `docs/guide-to-writing-plans.md` — Checklist for plans.  
ℹ️ Parent: [02-pi-like-agent.md](02-pi-like-agent.md). Prior: [01 §9](01-pi-agent.md#9-steer--follow-up-requirement-not-the-headline), [04](04-pi-harness-what-it-actually-does.md).  
ℹ️ Split: **Phase 6a** = Agent Pi loop (greenfield; implement when locked). **Phase 6b** = UI (reserved — propose only; do not ship without review).

## Purpose

- 🔷 Mid-run message queues inside the Agent Pi loop (context timeline), not output QA.
- 🔷 Two inject moments (Pi vocabulary):
  - **Steer** — after current tool batch, before next LLM call.
  - **Follow-up** — when the agent would otherwise stop (no more tool calls).
- 🔷 Split agent plumbing from UI: agent can land first behind a programmatic API; composer / keys / badges need explicit approval.
- ℹ️ Chatter FIFO = whole turns (chat then summarize). **≠** between-tool-batch steer.
- 🚫 Not skill compliance / plan gates — see [04](04-pi-harness-what-it-actually-does.md).

---

## Loop (reminder)

```
prompt(user)
  loop:
    [drain steers → inject as user msgs]
    stream assistant
    if toolCalls → run tools → continue
    else if follow-ups → inject → continue
    else stop
```

| Queue | When drained |
|-------|----------------|
| Steer | After `execute_tools` batch, before `send_append` / next model call |
| Follow-up | When assistant turn finished with **no** tool calls (would stop) |

---

## Phase 6a — Agent loop (greenfield)

🔷 `⏳` Implement on **`OLLMcoder.AgentPi`** only. Do not change Chatter / JustAsk / Skill.Runner queues for this.

### API (lock before implement)

- 🔷 `⏳` Two FIFO lists on `AgentPi.Agent` (or adjacent Agent-Pi-owned type):
  - `steer_messages` — text (or `OLLMchat.Message`) waiting for next post-tool inject.
  - `followup_messages` — waiting for would-stop inject.
- 🔷 `⏳` Public enqueue methods (names **💩** at implement; intent locked):
  - enqueue steer while a turn is in flight.
  - enqueue follow-up while a turn is in flight.
- 🔷 `⏳` Drain steers → append as normal `user` messages to session (+ include in the next outbound `send_append` payload) after each tool batch.
- 🔷 `⏳` Drain follow-ups → same inject path when the model returns with empty `tool_calls` and queues are non-empty; then continue the toolsReply / chat loop instead of returning “done.”
- ℹ️ Injected rows are real transcript messages (visible in history), not silent system nudges.
- 🚫 Do not reuse `pending_messages` (whole-turn FIFO) as the steer queue — different lifetime and drain points.
- 💩 Whether enqueue while **not** running becomes a normal `send_async` (or errors) — confirm at implement; default proposal: if idle, treat as ordinary send (no special queue).

### Hook points

- 🔷 `⏳` Post-tool: today `Call.ChatBase.toolsReply` runs tools then `send_append`. Agent Pi needs a drain-steers hook **between** tool results and the next model call.
  - 💩 Prefer Agent-Pi override / callback over editing shared `toolsReply` for all agents — confirm so JustAsk/Chatter stay unchanged.
- 🔷 `⏳` Pre-stop: when response has no tool calls, poll follow-ups before treating the turn as finished (`PendingMessage.run` / chat completion path).
- ℹ️ Compaction (Phase 5) still runs on its threshold after a successful deliver; steer/follow-up injects count as normal user text toward context.

### Tests / acceptance (agent)

- 🔷 `⏳` While tools running: enqueue steer → next LLM call sees tool results **and** steer text.
- 🔷 `⏳` Model about to stop + follow-up queued → inject and another model call; empty follow-up queue → stop.
- 🔷 `⏳` Multiple steers preserve FIFO order.
- 🚫 No UI required for 6a acceptance (call enqueue from tests / temporary debug).

---

## Phase 6b — UI (reserved — propose)

🚫 Do **not** implement until this section is reviewed and promoted **🔷** where needed.

### Problem

While Agent Pi is `is_running`, today’s composer typically waits for idle (or only feeds the whole-turn FIFO). Pi lets the user type mid-run and choose **steer** vs **follow-up**.

### Proposal (for review)

- 💩 Mid-run composer stays editable when `agent-pi` + `session.is_running`.
- 💩 **Enter** (or primary send) while running → enqueue **steer** (Phase 6a API), show the user bubble immediately (or “queued steer” affordance).
- 💩 **Alt+Enter** (or secondary action) while running → enqueue **follow-up**.
- 💩 Idle (not running) → both keys / send behave as today’s `send_async` (unchanged).
- 💩 Optional badge / status: “N steers · M follow-ups” in header or under composer — only if cheap; not required for v1.
- 💩 Cancel / stop: clearing queues vs leaving them for resume — **💩** exact policy.
- 🚫 Do not invent a third “interrupt cancel and replace turn” path in this plan unless asked.
- 🚫 Do not change global ChatView send wiring for non–Agent-Pi agents in the same patch without an explicit go-ahead.

### Why reserved

- ℹ️ Composer, keybindings, and “send while streaming” touch shared `ollmapp` paths; easy to break other agents.
- 🔷 Agent 6a can ship and be exercised without 6b; UI is the product surface that needs a deliberate pass.

---

## Out of this plan

- 🚫 Output QA / skill-must-read / plan gate ([04](04-pi-harness-what-it-actually-does.md)).
- 🚫 Porting Pi TUI / RPC / extensions.
- 🚫 Replacing Chatter’s chat+summarize FIFO with steer semantics.

---

## Suggested order

1. Lock Phase 6a API + hook placement (Agent Pi only).
2. Implement + test 6a without UI.
3. Review Phase 6b proposal → promote bullets → implement UI.

---

## LLM notes

- ℹ️ Spec source: [01 §9](01-pi-agent.md#9-steer--follow-up-requirement-not-the-headline).
- ℹ️ Rationale vs “real harness”: [04](04-pi-harness-what-it-actually-does.md) § Phase 6.
- 🔷 Namespace / agent: `OLLMcoder.AgentPi` / `agent-pi`.
- 🚫 Do not implement Phase 6b until user approves the UI proposal.
