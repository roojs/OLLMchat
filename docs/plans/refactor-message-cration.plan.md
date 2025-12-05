# Refactor Message Creation to Use message_created Signal

## Overview

Refactor the client-side message handling to use a unified `message_created(Message m)` signal as the primary driver for both persistence (Manager) and UI display. This will replace the current `on_chat_send` and `tool_message` handlers, creating dummy messages before prompt engine modification and ensuring the UI only has one entry per message (excluding chunks).

## Changes Required

### 1. Add message_created Signal to Client

- **File**: `OLLMchat/Client.vala`
- Add new signal: `public signal void message_created(Message m)`
- This signal will be the primary driver for message creation events

### 2. Refactor Client.chat() Method

- **File**: `OLLMchat/Client.vala`
- Remove `original_user_text` assignment
- Before calling `prompt_assistant.fill()`, create a dummy user-sent Message with the original text
- Emit `message_created` signal with this dummy message
- After `prompt_assistant.fill()`, if `system_content` is set, create a system Message and emit `message_created`
- The modified `chat_content` will still be used for the actual API call

### 3. Refactor Call.Chat.exec_chat()

- **File**: `OLLMchat/Call/Chat.vala`
- Remove the creation of system and user messages (they're now created earlier via signal)
- Keep the messages array building for API requests, but messages should already exist from signals

### 4. Refactor Call.Chat.reply()

- **File**: `OLLMchat/Call/Chat.vala`
- Add `prompt_assistant.fill()` call before creating messages
- Create dummy user-sent Message before `prompt_assistant.fill()` and emit `message_created`
- Handle system content message if set (emit via `message_created`)
- The modified content will be used for the actual API call

### 5. Replace tool_message with message_created

- **File**: `OLLMchat/Call/Chat.vala` (toolsReply method)
- Replace all `client.tool_message()` calls with creating Message objects and emitting `message_created`
- Create "ui" role messages for tool status messages
- **File**: `OLLMchat/Message.vala` (tool_call_invalid)
- Update to emit `message_created` instead of `tool_message`

### 6. Update SessionBase to Handle message_created

- **File**: `OLLMchat/History/SessionBase.vala`
- Remove `on_chat_send` handler connection
- Remove `tool_message` handler connection
- Add `message_created` handler connection in `activate()`
- Implement `on_message_created(Message m)` handler that:
- Adds message to `session.messages` (for Session instances)
- Relays to Manager via `manager.message_created(m)`

### 7. Update Session.on_chat_send() → on_message_created()

- **File**: `OLLMchat/History/Session.vala`
- Replace `on_chat_send()` with `on_message_created(Message m)`
- Simplify logic: just add message to `session.messages` and save
- Remove logic that creates "user-sent" messages (now created earlier)
- Remove logic that copies messages from `chat.messages` (messages come via signal)

### 8. Update Session.on_stream_chunk()

- **File**: `OLLMchat/History/Session.vala`
- Keep streaming chunk handling (chunks are separate from message_created)
- When response is done, ensure final assistant message is sent via `message_created` if not already sent

### 9. Update Manager to Handle message_created

- **File**: `OLLMchat/History/Manager.vala`
- Remove `chat_send` signal
- Remove `tool_message` signal
- Add `message_created` signal: `public signal void message_created(Message m)`
- Add `message_created(Message m)` method that emits the signal
- Update `SessionBase.activate()` to connect to Manager's `message_created` signal

### 10. Update ChatWidget to Use message_created

- **File**: `OLLMchatGtk/ChatWidget.vala`
- Remove `on_send_clicked()` logic that creates temporary ChatCall for display
- Connect to `manager.message_created` signal
- In handler, check `message.is_ui_visible` property:
- If `false`, skip the message (e.g., "system", "end-stream", "tool", "user")
- If `true`, display message based on role:
  - "user-sent": call `chat_view.append_user_message()`
  - "assistant": call `chat_view.append_complete_assistant_message()`
  - "ui": call `chat_view.append_tool_message()`
  - "think-stream" / "content-stream": call `chat_view.append_complete_assistant_message()` (convert to assistant message)
- Keep `load_messages()` for history loading (UI only, no signal emission)
- Update `load_messages()` to also use `is_ui_visible` for filtering

### 11. Remove original_user_text from Call.Chat

- **File**: `OLLMchat/Call/Chat.vala`
- Remove `original_user_text` property (no longer needed)
- Update serialization to exclude it

### 12. Update ChatWidget.on_send_clicked()

- **File**: `OLLMchatGtk/ChatWidget.vala`
- Remove the temporary ChatCall creation and immediate UI display
- The message will be displayed when `message_created` signal is received
- Keep the rest of the logic (clearing input, setting streaming state, etc.)

## Flow After Changes

### New Message Flow:

1. User sends message → `ChatWidget.on_send_clicked()`
2. `Client.chat()` called
3. **Before** `prompt_assistant.fill()`: Create dummy user-sent Message → emit `message_created`
4. `prompt_assistant.fill()` modifies `chat_content`
5. If `system_content` set: Create system Message → emit `message_created`
6. `Call.Chat.exec_chat()` builds API request with modified content
7. Response received → create assistant Message → emit `message_created`
8. `message_created` → Manager → Session (save to log) + UI (display)

### Reply Message Flow:

1. `Response.Chat.reply()` called
2. **Before** `prompt_assistant.fill()`: Create dummy user-sent Message → emit `message_created`
3. `prompt_assistant.fill()` modifies content
4. If `system_content` set: Create system Message → emit `message_created`
5. `Call.Chat.reply()` builds API request
6. Response received → create assistant Message → emit `message_created`

### History Loading Flow:

1. `ChatWidget.load_messages()` iterates `session.messages`
2. Displays messages directly (no signal emission)
3. UI only has one entry per message (excluding chunks)

## Benefits

- Single source of truth for message creation (`message_created` signal)
- Cleaner separation: messages created before prompt engine modification
- UI only displays messages once (via signal, not duplicate creation)
- Simplified persistence logic (just add message to list when signal received)
- Consistent message handling across all scenarios