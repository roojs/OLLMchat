# Show the outbound LLM message in the chat UI

**Status:** 🚫 CLOSED — acceptable for now. The sending frame stays as implemented.

## Problem

- 🔷 The chat UI shows a waiting message after a request is sent to the LLM.
- 🔷 There is no preceding message that shows the actual assembled request, so it is difficult to understand which system prompt, user prompt, history, and other context the model received.
- 🔷 Expected: the UI adds the exact outbound message at the point it is sent, then keeps the waiting caption to show that a response is pending.
- 🔷 Actual: the UI shows only the waiting caption.

## Requested UI

- 🔷 The snapshot is one standard collapsed markdown frame, emitted with `OLLMchat.Message.fenced`, before the waiting indicator.
- 🔷 The frame title is `Sending message`. That title does not replace the waiting indicator.
- 🔷 Info string type is `markdown` and includes `oc-frame-info` and `collapsed`. The body renders as styled content. It is not type `text`, and it is not a custom container.
- 🔷 Add an extra CSS class on that frame so it can be styled differently later.
- 💩 Class token `oc-frame-sending`, beside `oc-frame-info` and `collapsed`, same pattern as `oc-frame-user`. No rules in `frame.css` until a style is chosen.
- 🔷 Expanding the frame shows the system message and the user message.
- 🚫 Tool definitions. They are not worth showing.
- 🔷 Keep the existing waiting indicator after the frame.
- 🔷 The waiting indicator remains visible while the UI is waiting for the model response to arrive.
- 🔷 The body is one markdown document. Do not split the request into tabs.
- 🔷 Show the system message first and the user message after it.
- 🔷 Put a double horizontal rule between the system and user message sections.
- 🔷 Include the complete assembled prompt content for those messages, not the shorter text shown in the normal user-message bubble.
- 🔷 Pass that body to `Message.fenced` raw. That call is the only escape, so a fence line in the prompt cannot split the surrounding markdown. Do not Markup-escape, backslash-escape, indent, or column-wrap the body first.
- 🔷 The expanded body uses the existing markdown-frame max height and scrolls inside it. Do not add a separate height limit.
- 🔷 The frame is UI-only. The system and user messages are already the session. Do not store this snapshot again.
- 🔷 The body is the outbound `system` messages, then a double horizontal rule, then the outbound `user` messages, each group in send order.
- 🚫 Prior assistant and tool messages. They are not part of this frame.
- 🔷 The frame stays in the live transcript after the response starts. The waiting indicator still clears when response content starts. A reload does not show the frame.

## Evidence

- ✔️ `libollmchatgtk/ChatView.vala` renders `ui-waiting` as a label with animated dots. It has no request-content child.
- ✔️ `libollmchatgtk/ChatWidget.vala` passes only the `ui-waiting` message content to `show_waiting_indicator`. Role `ui` paints fenced content through the markdown renderer.
- ✔️ `libollmchat/History/Session.vala` emits a transient `ui-waiting` message before it delegates to the agent. That message is `message_added` and is not added to `session.messages`.
- ✔️ `liboccoder/AgentPi/PendingMessage.vala` assembles the outbound message list, adds the system message and conversation messages, then passes that list to `chat().send`.
- ℹ️ The normal UI user message is a separate `ui` frame and is not the full model request.
- ✔️ `RenderSourceView` turns each dotted info-string part after the type into a CSS class on the frame. `get_max_collapsed_height` is half the parent height, or 300 when that height is unknown. The frame's scrolled window uses that cap, so a taller body scrolls.
- ✔️ `ChatView.append_complete_assistant_message` clears the waiting indicator before painting a `ui` message. The waiting row is a panel appended after `render_box`, so a later `ui-waiting` sits under the frame.
- ✔️ Agent chat is `Call.ChatCompletions`. `send` assigns `this.messages` before the request. Tool definitions stay on `this.tools`.

## Root cause

- ✔️ The waiting UI receives only display text.
- ✔️ The assembled outbound message list exists at the send call but is not represented by a UI message or passed to `ChatView`.
- ✔️ The waiting row is transient and is removed when response content starts. That remains the required waiting behavior.

## Proposed fix

- 🔷 Capture the `system` and `user` messages on the list `ChatCompletions.send` is about to transmit. Emit the frame, then emit `ui-waiting` again so the caption sits under the frame.
- 🔷 Do not add that frame to `session.messages`.
- 🔷 Let the existing frame cap size the body. The scrolled window already scrolls when the body is taller.
- 🚫 Do not escape the body before `Message.fenced`. Do not indent it. `fenced` lengthens the fence so the body cannot close the block. Indenting a `markdown` body turns it into a code block, and Markup-escaping it shows the entities in the frame.
- 🚫 Do not reconstruct the prompt later from session history. The display must reflect what was actually sent.
- 🚫 Do not replace or remove the waiting indicator. `Sending message` is the frame title.
- 🚫 Do not add separate System and User tabs.
- 🚫 Do not add a new height limit, and do not persist this frame.
- 🚫 Do not add a helper. The block stays inline in `send`.

### `libollmchat/Call/ChatCompletions.vala` — `send`: show the outbound system and user text

**Why:** `this.messages` is the list about to be sent. Painting the `ui` frame clears the waiting row, so the same method puts that row back underneath.

**Where:** `send`, after `this.messages = messages;` and before `if (this.stream)`.

**Depends on:** none.

#### Add — after `this.messages = messages;`

Emit the collapsed frame for the system and user text on this send, then show the waiting caption again. Skip the emit when neither role has content. Do not append the frame to `session.messages`.

```vala
			if (this.agent != null) {
				string[] system_parts = {};
				string[] user_parts = {};
				foreach (var msg in this.messages) {
					if (msg.role == "system") {
						if (msg.content == "") {
							continue;
						}
						system_parts += msg.content;
						continue;
					}
					if (msg.role != "user" || msg.content == "") {
						continue;
					}
					user_parts += msg.content;
				}
				if (system_parts.length > 0 || user_parts.length > 0) {
					var body = string.joinv("\n\n", system_parts);
					if (system_parts.length > 0 && user_parts.length > 0) {
						body += "\n\n---\n\n---\n\n";
					}
					if (user_parts.length > 0) {
						body += string.joinv("\n\n", user_parts);
					}
					this.agent.session.manager.message_added(
						new Message(
							"ui",
							Message.fenced(
								"markdown.oc-frame-info.oc-frame-sending.collapsed Sending message",
								body)),
						this.agent.session);
					this.agent.session.manager.message_added(
						new Message(
							"ui-waiting",
							"waiting for "
							+ (this.agent.session.model_usage.model != ""
								? this.agent.session.model_usage.display_name_with_size()
								: "Unknown model")
							+ " to reply"),
						this.agent.session);
				}
			}
```

## Attempts / changelog

- ℹ️ 2026-10-27: bug created and current waiting/send paths identified.
- ℹ️ 2026-10-27: nested-text row withdrawn. Snapshot is a `markdown.oc-frame-info.collapsed` frame from `Message.fenced`, body escaped once.
- ℹ️ 2026-10-27: `Sending message` is the frame title. It does not replace the waiting indicator. Body is the system message and the user message, not tool definitions. Extra class `oc-frame-sending`. Existing frame max height. UI-only.
- ℹ️ 2026-10-27: fences added in `ChatCompletions.send`.
- ✔️ 2026-10-27: fence applied in `libollmchat/Call/ChatCompletions.vala`. `ninja -C build` succeeded.
- ℹ️ 2026-10-27: closed. Acceptable for now. No further change this pass.
- ✔️ 2026-10-27: no stored previous text. A list longer than system + one user paints only the last message.
