# Show the outbound LLM message in the chat UI

**Status:** ⏳ open — UI requirement captured; lifecycle and wire details need
investigation

## Problem

- 🔷 The chat UI shows a waiting message after a request is sent to the LLM.
- 🔷 There is no preceding message that shows the actual assembled request, so
  it is difficult
  to understand which system prompt, user prompt, history, and other context
  the model received.
- 🔷 Expected: the UI adds the exact outbound message at the point it is sent,
  then keeps the waiting caption to show that a response is pending.
- 🔷 Actual: the UI shows only the waiting caption.

## Requested UI

- 🔷 Add `Sending message` before the waiting indicator.
- 🔷 `Sending message` is a collapsed nested-text row containing the outbound
  request snapshot.
- 🔷 Expanding the row shows the actual outbound LLM message.
- 🔷 Keep the existing waiting indicator after `Sending message`.
- 🔷 The waiting indicator remains visible while the UI is waiting for the
  model response to arrive.
- 🔷 Use one markdown view. Do not split the request into tabs.
- 🔷 Show the system prompt first and the user prompt after it.
- 🔷 Put a double horizontal rule between the system and user prompt sections.
- 🔷 Include the complete assembled prompt content, not the shorter text shown
  in the normal user-message bubble.

## Evidence

- ✔️ `libollmchatgtk/ChatView.vala` renders `ui-waiting` as a label with
  animated dots. It has no request-content child.
- ✔️ `libollmchatgtk/ChatWidget.vala` passes only the `ui-waiting` message
  content to `show_waiting_indicator`.
- ✔️ `libollmchat/History/Session.vala` emits a transient `ui-waiting` message
  before it delegates to the agent.
- ✔️ `liboccoder/AgentPi/PendingMessage.vala` assembles the outbound message
  list, adds the system message and conversation messages, then passes that
  list to `chat().send`.
- ℹ️ The normal UI user message is a separate `ui` frame and is not the full
  model request.

## Root cause

- ✔️ The waiting UI receives only display text.
- ✔️ The assembled outbound message list exists at the send call but is not
  represented by a UI message or passed to `ChatView`.
- ✔️ The waiting row is transient and is removed when response content starts.
  That remains the required waiting behavior.

## Open questions

- 🔷 ⏳ Confirm whether the expanded view shows only message-role content or
  the complete provider request including tool definitions and options.
- 🔷 ⏳ Confirm how prior assistant and tool messages are labelled within the
  single markdown view.
- 🔷 ⏳ Decide whether the collapsed `Sending message` row remains after the
  response starts. This does not change the waiting indicator's lifecycle.
- 💩 ⏳ Check whether large prompts need an internal height limit while
  expanded.
- 💩 ⏳ Check whether the displayed snapshot should be stored in session
  history or remain UI-only.

## Proposed fix

- 🔷 ⏳ Capture the final assembled request immediately before the model send
  and expose that same snapshot to the chat UI.
- 🔷 ⏳ Render the snapshot under the collapsed `Sending message` row using
  the existing markdown rendering path.
- 🔷 ⏳ Show the existing waiting indicator after the request snapshot and
  keep it until response content starts.
- 🔷 ⏳ Keep the system and user content in one view with the requested double
  rule separator.
- 🚫 Do not reconstruct the prompt later from session history. The display
  must reflect what was actually sent.
- 🚫 Do not replace or remove the waiting indicator.
- 🚫 Do not add separate System and User tabs.
- ℹ️ Concrete Vala edits wait until the open lifecycle and payload questions
  above are settled.

## Attempts / changelog

- ℹ️ 2026-10-27: bug created and current waiting/send paths identified.
- ℹ️ No product code or debug instrumentation changed.

## Next

- 🔷 ⏳ Capture one Agent Pi send and enumerate every part of the provider
  request that should appear in the expanded row.
- 🔷 ⏳ Decide the row's post-response lifetime.
- 🔷 ⏳ Add a concrete code proposal after those two decisions.
