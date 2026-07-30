# 06. Urgent / follow-up messages

Status: ⏳ proposed — Phase **6a** ✔️ agent (Agent Pi only; no `libollmchat`); Phase **6b** reserved

ℹ️ Checklist: `docs/guide-to-writing-plans.md` — Checklist for plans.  
ℹ️ Parent: [02-pi-like-agent.md](02-pi-like-agent.md). Prior: [01 §9](01-pi-agent.md#9-urgent--follow-up-requirement-not-the-headline), [04](04-pi-harness-what-it-actually-does.md).  
ℹ️ Split: **Phase 6a** = Agent Pi loop (greenfield; implement when locked). **Phase 6b** = UI (reserved — propose only; do not ship without review).  
ℹ️ Pi called post-tool inject **steer** and defaulted Enter → steer. We use **urgent** / **follow-up**, and default mid-run send like **Cursor**: follow-up first, upgrade to urgent.

## Purpose

- 🔷 Mid-run **message** queues inside the Agent Pi loop (context timeline), not output QA.
- 🔷 Queue elements are **`OLLMchat.Message`** (arrays / lists of messages), not plain text — ready for images / richer content later.
- 🔷 Two inject moments:
  - **Follow-up** — when the agent would otherwise stop (no more tool calls); **default** mid-run send.
  - **Urgent** — after the current tool batch, before the next LLM call — **upgrade** from a queued follow-up (not the default send).
- 🔷 Entry point: **`send_async`** — idle → normal turn; running → queue follow-up **in memory only** (no `message_added` yet).
- 🔷 UI escalates with **upgrade** (same `Message` → urgent list), not a second parallel “queue as urgent” send path.
- 🔷 **When injected** (follow-up at stop / urgent after tools): `add_message` + send to LLM together — transcript gets the row at send time, not while queued.
- 🔷 Pending visibility (hold zone like the skills tree; optional session pending section) is **UI / possibly Manager** — Phase **6b** (or later). Do not dump queued rows into the live chat stream early (they scroll off).
- 🔷 Split agent plumbing from UI: agent 6a can land first; composer / pending zone / upgrade need explicit approval (6b).
- ℹ️ Chatter FIFO = whole turns (chat then summarize). **≠** mid-run follow-up / urgent inject.
- 🚫 Not Pi’s “Enter dumps everything into steer/urgent.”
- 🚫 Not skill compliance / plan gates — see [04](04-pi-harness-what-it-actually-does.md).
- 🚫 Do not change `History.Manager` / session pending sections in 6a — anything core-facing for pending UI waits for 6b+.

---

## Loop (reminder)

```
prompt(user)
  loop:
    [drain urgent → inject as user msgs]
    stream assistant
    if toolCalls → run tools → continue
    else if follow-ups → inject → continue
    else stop
```

| Queue | When drained | How it gets filled |
|-------|----------------|-------------------|
| Follow-up | Assistant finished with **no** tool calls | Mid-run `send_async` (default) |
| Urgent | After `execute_tools` batch, before next model call | `upgrade_urgent` on a queued follow-up (or same Message while running) |

---

## Phase 6a — Agent loop (greenfield)

- ✔️ `urgent_messages` / `followup_messages` on `AgentPi.Agent`
- ✔️ `send_async`: idle → full turn; running → follow-up queue (return; do not start a second whole turn)
- ✔️ `upgrade_urgent(Message)`: remove from follow-up if present → urgent (idle → normal send)
- ✔️ Urgent drain: override `execute_tools`
- ✔️ Follow-up drain: `PendingMessage.run` after `send`
- 🔷 `⏳` Phase 6b UI (reserved)

### API

- ✔️ Two FIFO lists: `urgent_messages`, `followup_messages` — `Gee.ArrayList<OLLMchat.Message>`.
- 🔷 Queues hold **`Message` objects**, not bare strings.
- ✔️ **`send_async`** is the product entry for mid-run follow-up + idle send.
- ✔️ **`upgrade_urgent`** promotes the same Message (Cursor-style escalation).
- 🚫 Do not make primary mid-run send default to urgent (that was Pi Enter→steer).
- 🚫 Do not store `string` queues.
- 🚫 Do not reuse `pending_messages` (whole-turn FIFO) as the follow-up / urgent queues.

### Hook points

- ✔️ Post-tool: `execute_tools` override appends drained `urgent_messages` (shared `toolsReply` unchanged).
- ✔️ Pre-stop: `PendingMessage.run` drains `followup_messages` via `send_append` / `toolsReply`.
- 🚫 Do **not** modify `libollmchat` for this feature.

### Tests / acceptance (agent)

- 🔷 `⏳` While running: `send_async` → follow-up only; turn stop injects it.
- 🔷 `⏳` `upgrade_urgent` on that Message → next tool batch sees it as urgent.
- 🔷 `⏳` Idle `send_async` still starts a normal turn.
- 🚫 No UI required for 6a acceptance.

---

## Phase 6b — UI (reserved — propose)

🚫 Do **not** implement until this section is reviewed and promoted **🔷** where needed.

### Problem

While Agent Pi is `is_running`, composer should accept mid-run sends as **follow-up**, with a way to **upgrade to urgent** (Cursor-like). Queued rows must be visible somewhere that does **not** scroll away in the main transcript before inject.

### Proposal (for review)

- 🔷 Mid-run composer stays editable when `agent-pi` + `session.is_running`.
- 🔷 **Enter** / primary send while running → `send_async` → **follow-up** queue (agent already does this; no transcript insert until inject).
- 🔷 **Pending zone** (skills-tree-like) lists queued follow-ups / urgents for upgrade / cancel — not the main chat scrollback.
- 🔷 UI control to **upgrade** a queued message → `upgrade_urgent`.
- 🔷 On inject: existing `add_message` path shows the row in transcript as it goes to the LLM.
- 🔷 Idle → `send_async` as today’s new turn.
- 💩 Whether Manager gains a first-class “pending” section vs Agent Pi–local UI binding the agent lists — confirm in 6b; **bump any core Manager/session API** out of 6a.
- 💩 Optional badge counts — cheap; not required for v1.
- 💩 Cancel / stop: clearing queues vs leaving them — exact policy later.
- ℹ️ Attachments / images use the same `Message` shape once supported.
- 🚫 Do not default mid-run Enter to urgent.
- 🚫 Do not `message_added` queued follow-ups into the live stream before inject.
- 🚫 Do not invent a third “interrupt cancel and replace turn” path unless asked.
- 🚫 Do not change global ChatView send wiring for non–Agent-Pi agents without an explicit go-ahead.

### Why reserved

- ℹ️ Composer / upgrade affordance touch shared `ollmapp` paths.
- 🔷 Agent 6a can ship without 6b.

---

## Out of this plan

- 🚫 Output QA / skill-must-read / plan gate ([04](04-pi-harness-what-it-actually-does.md)).
- 🚫 Porting Pi TUI / RPC / extensions.
- 🚫 Replacing Chatter’s chat+summarize FIFO with urgent/follow-up semantics.

---

## Suggested order

1. Lock Phase 6a API (done — Cursor-style default).
2. Implement + test 6a without UI (agent path ✔️).
3. Review Phase 6b → promote → implement UI.

---

## LLM notes

- ℹ️ Spec source: [01 §9](01-pi-agent.md#9-urgent--follow-up-requirement-not-the-headline) (timing); **product default** follows Cursor (follow-up + upgrade), not Pi Enter→steer.
- ℹ️ Rationale vs “real harness”: [04](04-pi-harness-what-it-actually-does.md) § Phase 6.
- 🔷 Namespace / agent: `OLLMcoder.AgentPi` / `agent-pi`.
- 🚫 Do not modify `libollmchat` for Phase 6a.
- 🚫 Do not implement Phase 6b until user approves the UI proposal.
- 🚫 Do not revive `steer` as the primary product name or default mid-run send to urgent.
- 🚫 Do not implement urgent/follow-up queues as `string` lists.
