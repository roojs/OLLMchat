# 2026-07-21 — Browser tool missing UI frames + no waiting on tool-reply LLM round

**Status:** ✔️ agent applied — await user ✅

## Problem

- 🔷 After Gemma successfully called `browser` (search), the chat showed **no** request/reply **oc-frame** UI (what was sent / what came back). Other tools (e.g. `google_search`, `web_fetch`) do show those frames.
- 🔷 After the tool returned, sending the tool result back to the model took a while, but the normal **“waiting for … to reply”** indicator (brief animated row that appears then clears) did **not** show for that follow-up LLM call.

## Evidence

- ℹ️ Session `~/.local/share/ollmchat/history/2026/07/21/11-50-52.json` (and `11-49-12.json`):
  - Has `assistant` + `tool_calls` + `tool` result content
  - **No** `ui` messages with `oc-frame-info` / `oc-frame-success` for the browser call
  - **No** `ui-waiting` between tool result and next think/content stream
- ✔️ `libocwebkit/Request.vala` — `execute_request()` never calls `agent.add_message` with fenced frames (unlike `liboctools/GoogleSearch/Request.vala` and `liboctools/WebFetch/Request.vala`)
- ✔️ `libollmchat/History/Session.vala` `send()` — emits transient `ui-waiting` only for the **initial user** turn via `manager.message_added` (not persisted)
- ✔️ `libollmchat/Call/ChatBase.vala` `toolsReply()` — after `execute_tools`, calls `send_append` with **no** `ui-waiting` emit

## Root cause

- ✔️ **Frames:** browser Request never implemented the standard tool UI fence pattern.
- ✔️ **Waiting:** tool-reply continuation never re-emits `ui-waiting`; that path was never wired (not a regression of Session’s user-send waiting). Waiting clears on the next stream chunk (`ChatView.clear_waiting_indicator`), so re-emitting before `send_append` is enough.

## Proposed fix

### 1. Browser Request — request + reply frames (mirror WebFetch / GoogleSearch)

**Where:** `libocwebkit/Request.vala` — `execute_request()`, and tighten `to_summary()`.

#### Replace — `to_summary()` body

```vala
	public override string to_summary()
	{
		switch (this.action.strip().down()) {
			case "help":
			case "":
				if (this.topic.strip() != "") {
					return "help topic=" + this.topic.strip();
				}
				return "help";
			case "search":
				return "search " + this.query.strip();
			case "fetch":
			case "download":
				return this.action.strip().down() + " " + this.url.strip();
			case "press":
				return "press " + this.press.to_string();
			case "whereami":
				return "whereami";
			default:
				return "action=" + this.action;
		}
	}
```

#### Add — at start of `execute_request()` (after resolving `act` / `fmt`, before `switch`)

```vala
		this.agent.add_message(new OLLMchat.Message("ui",
			OLLMchat.Message.fenced(
				"text.oc-frame-info.collapsed browser " + this.to_summary(),
				this.to_summary())));
```

#### Add — before each successful `return` of page/help content (not on throw)

Use fence type from `fmt`: `markdown` → `markdown.oc-frame-success…`, else `text.oc-frame-success…`:

```vala
		var reply_prefix = (fmt == "markdown") ? "markdown" : "text";
		this.agent.add_message(new OLLMchat.Message("ui",
			OLLMchat.Message.fenced(
				reply_prefix + ".oc-frame-success.collapsed browser reply",
				result)));
		return result;
```

(💩 Inline per successful branch, or assign `result` then one fence+return at end of switch — prefer one exit path if it stays flat.)

### 2. Re-emit `ui-waiting` before tool-reply LLM round

**Where:** `libollmchat/Call/ChatBase.vala` — `toolsReply()`, after tool replies are added, **before** `yield this.send_append(...)`.

Same transient pattern as `Session.send` (emit via `manager.message_added`, **do not** `session.add_message` — avoids persisting waiting rows).

#### Add — before `var next_response = yield this.send_append(messages_to_send);`

```vala
				this.agent.session.manager.message_added(
					new Message(
						"ui-waiting",
						"waiting for "
						+ (this.agent.session.model_usage.model != ""
							? this.agent.session.model_usage.display_name_with_size()
							: "Unknown model")
						+ " to reply"),
					this.agent.session);
```

## Next

- ✔️ Applied: `libocwebkit/Request.vala` frames + `ChatBase.toolsReply` ui-waiting
- ⏳ 🔷 User verify: Gemma PAX search shows request/reply frames and waiting on tool-reply round
