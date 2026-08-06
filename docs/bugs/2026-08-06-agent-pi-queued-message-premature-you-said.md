# Agent Pi: queued follow-up shows "You said" before inject

**Status:** ⏳ root cause confirmed; fix proposed — await apply approval

## Problem

🔷 Mid-run second (queued) message appears in the chat as **"You said:"** immediately, even though it is only in the pending queue strip and has not been injected into the Agent Pi loop yet.

🔷 When the message is later injected, there is **no** chat mention of the inject — only a silent `role=user` API row.

## Evidence

ℹ️ Session `/home/alan/.local/share/ollmchat/history/2026/08/06/08-28-15.json` (`agent-pi`):

- ✔️ `003`/`004` — second prompt already stored as `user-sent` + `You said:` UI
- ✔️ `005`–`007` — first turn still thinking / duration (queue had not drained)
- ✔️ `008` — same text appears again as `role=user` when actually injected — **no** new UI fence
- ✔️ Same pattern for third prompt at `012`/`014` then `role=user` later

ℹ️ Code path:

- ✔️ `Session.send` always adds `user-sent` + fenced `You said:` + `ui-waiting` **before** `agent.send_async`
- ✔️ `AgentPi.Agent.send_async` when `is_running` only `message_queue.append` and returns
- ✔️ Inject sites (`PendingMessage` stop-drain, `execute_tools` urgent) call `add_message` / append `role=user` with **no** `You said:` UI

## Root cause

✔️ Chat display of the user turn is owned by `Session.send` and runs **unconditionally**. Agent Pi mid-run only queues; inject never re-emits the UI fence. So the UI lies early, then stays silent at the real inject point.

## Proposed fix

🔷 Defer `user-sent` / `You said:` / `ui-waiting` when the session is already running (mid-run queue path). Show `You said:` when Agent Pi actually injects.

### 1. `libollmchat/History/Session.vala` — `send`: skip UI when running

**Why:** Mid-run composer only stays open for agents that queue; premature `You said:` is wrong for that path.

**Where:** `public override async void send` — user-message branch.

**Depends on:** none.

##### Part 1 — early queue path before You said

#### Add — After `var text = message.content.strip();`, before the current `user-sent` / `You said:` block: if running, hand off to agent only.

```vala
			var text = message.content.strip();
			if (this.is_running) {
				this.ensure_agent_handler();
				if (this.agent == null) {
					throw new OllmError.INVALID_ARGUMENT("No agent available for session");
				}
				yield this.agent.send_async(new Message("user", text), cancellable);
				return;
			}
```

(Leave the existing idle `user-sent` / `You said:` / `ui-waiting` / `send_async` block unchanged below.)

### 2. `liboccoder/AgentPi/PendingMessage.vala` — stop-drain inject UI

**Why:** When the whole queue drains after the turn stops, chat must show the follow-up as a user turn.

**Where:** follow-batch loop that currently does `follow.role = "user"; agent.add_message(follow);`.

**Depends on:** §1.

#### Remove

```vala
						follow.role = "user";
						agent.add_message(follow);
						follow_batch.add(follow);
```

#### Replace with

```vala
						var follow_text = follow.content.strip();
						agent.session.messages.add(new OLLMchat.Message("user-sent", follow_text));
						var follow_ui = new OLLMchat.Message("ui",
							OLLMchat.Message.fenced(
								"text.oc-frame-primary.oc-frame-user You said:",
								follow_text));
						agent.session.messages.add(follow_ui);
						agent.session.manager.message_added(follow_ui, agent.session);
						follow.role = "user";
						follow.content = follow_text;
						agent.add_message(follow);
						follow_batch.add(follow);
```

### 3. `liboccoder/AgentPi/Agent.vala` — urgent inject UI

**Why:** Same contract when an escalated urgent row is drained post-tool.

**Where:** `execute_tools` urgent while-loop body.

**Depends on:** §1.

#### Remove

```vala
				var msg = (OLLMchat.Message) urgent.get_item(urgent.get_n_items() - 1);
				this.message_queue.remove(msg);
				msg.role = "user";
				reply_messages.add(msg);
```

#### Replace with

```vala
				var msg = (OLLMchat.Message) urgent.get_item(urgent.get_n_items() - 1);
				this.message_queue.remove(msg);
				var urgent_text = msg.content.strip();
				this.session.messages.add(new OLLMchat.Message("user-sent", urgent_text));
				var urgent_ui = new OLLMchat.Message("ui",
					OLLMchat.Message.fenced(
						"text.oc-frame-primary.oc-frame-user You said:",
						urgent_text));
				this.session.messages.add(urgent_ui);
				this.session.manager.message_added(urgent_ui, this.session);
				msg.role = "user";
				msg.content = urgent_text;
				reply_messages.add(msg);
```

## Attempts / changelog

- ✔️ 2026-08-06 — Reproduced from session JSON; no code change yet.

## Next

⏳ 🔷 Await approval to apply §1–§3.
