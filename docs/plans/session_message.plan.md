# Enhanced Message Logging for Sessions

## Overview

Currently, the JSON log only contains raw data sent to the server and is missing responses, streaming output, and tool messages. This plan adds comprehensive message logging to sessions to capture all conversation data including streaming tokens, tool execution, and UI messages.

## Architecture Principles

- **Chat (`OLLMchat/Call/Chat`)**: Only fires signals, does NOT filter or manage special message types
- **Session (`OLLMchat/History/Session`)**: Maintains a separate `messages` list for serialization, listens to Chat signals and updates its own list
- **Separation of Concerns**: `chat.messages` contains only API-compatible messages (system, user, assistant, tool). `session.messages` contains all messages including special types for logging.

## Key Changes

1. **Remove `original_content` field** from `Message` class
2. **Add new message roles:**

- `"user-sent"` - Raw user message before prompt engine modification
- `"think-stream"` - Accumulated thinking tokens from streaming (created once, updated incrementally)
- `"content-stream"` - Accumulated content tokens from streaming (created once, updated incrementally)
- `"ui"` - UI-generated messages from tool_message signals
- `"end-stream"` - Flag message indicating end of streaming, signals renderer to ignore the next "done" message

3. **Session maintains separate message list** (`messages` property) for serialization
4. **Session listens to Chat signals** and updates its own message list
5. **Message filtering** happens in Session when loading messages back into `chat.messages` for API requests

## Implementation Details

### 1. Update Message Class

**File**: `OLLMchat/Message.vala`

- Remove `original_content` property (line 29)
- Remove `original_content` from serialization exclusion (line 167-169)
- Update constructor and any references to `original_content`
- Add support for new roles: "user-sent", "think-stream", "content-stream", "ui"

### 2. Update Session to Maintain Separate Message List

**File**: `OLLMchat/History/Session.vala`

#### 2.1 Update Session Message List

- Change `messages` property (line 206-210) to maintain its own list instead of returning `chat.messages`
- This list is separate from `chat.messages` and used for serialization

#### 2.2 Capture Raw Request Body

In `on_chat_send()`:

- Get raw request body from `chat.get_request_body()` before sending
- Create "user-sent" message with raw user text (before prompt engine modification)
- Add to `messages` list (NOT `chat.messages`)
- Chat continues to work normally with its own `chat.messages` list

#### 2.3 Capture Streaming Output

In `on_stream_chunk()`:

- Track streaming state: maintain reference to current stream message (either "think-stream" or "content-stream") in `messages`
- Track current stream type (thinking or content)
- On first chunk (when streaming starts):
  - Determine message type based on `is_thinking` parameter
  - Create message with role "think-stream" or "content-stream" accordingly
  - Add to `messages` (NOT `chat.messages`)
- On subsequent chunks:
  - If stream type changes (thinking → content or content → thinking):
    - Finalize current stream message
    - Create new message with the new type ("think-stream" or "content-stream")
    - Add new message to `messages`
  - If stream type stays the same:
    - Update existing stream message content (append new text)
- When `response.done == true`:
  - If streaming: create "end-stream" message and add to `messages` (signals renderer to ignore next "done" message)
  - Finalize current stream message if one exists
- Chat continues to manage its own `chat.messages` independently

#### 2.4 Capture UI Messages

The `client.tool_message` signal is already connected in `SessionBase.activate()` and relayed to the manager.

- Update the existing anonymous function connected to `client.tool_message` signal (in `SessionBase.activate()`, line 140-142):
  - Create "ui" role message with signal content
  - Add to `messages` list (NOT `chat.messages`)
  - Store widget reference if provided (may need to serialize widget state or skip)
  - Then relay to manager (existing behavior)

#### 2.5 Capture Standard Messages

When Chat adds messages to `chat.messages`:

- May need to add a signal to detect when messages are added to `chat.messages`
- Alternatively, signal into existing message creation points in Chat (e.g., in `exec_chat()`, `reply()`, `toolsReply()`)
- Copy standard messages (system, user, assistant, tool) to `messages` when they're added to `chat.messages`
- This ensures `messages` has a complete record of all conversation messages

### 3. Update Message Loading

There are two separate actions when loading messages:

#### 3.1 Load Messages into Chat (for API requests)

**File**: `OLLMchat/History/SessionPlaceholder.vala`

In `load()` method:

- When loading from JSON, restore `messages` from file
- Filter `messages` to populate `chat.messages`:
  - Filter out special session message types: "think-stream", "content-stream", "user-sent", "ui", "end-stream"
  - Only include standard roles: "system", "user", "assistant", "tool"
  - This ensures `chat.messages` only contains API-compatible messages

#### 3.2 Load Messages into UI (for rendering)

**File**: `OLLMchatGtk/ChatWidget.vala`

In `switch_to_session()` method (line 200-207):

- When rendering messages, iterate over `session.messages`
- Filter messages for UI display:
  - Display special session types: "think-stream", "content-stream", "user-sent", "ui" (these should be rendered)
  - Handle "end-stream" message: when encountered, flag to ignore the next message if it's a "done" message from streaming
  - Skip certain chat message types: "system" (not displayed in UI), "tool" (already handled), "user" (use "user-sent" instead), messages with "done" flag that follow "end-stream" (see above)
  - Display: "user-sent" (instead of "user"), "assistant" messages (excluding those flagged by "end-stream")

### 4. Update Message Serialization

**File**: `OLLMchat/History/Session.vala`

In `serialize_property()` for "messages":

- Serialize `messages` property instead of `chat.messages`
- This ensures all special message types are saved to JSON

In `deserialize_property()` for "messages":

- Deserialize into `messages` property
- After deserialization, filter `messages` to populate `chat.messages` with API-compatible messages only

**File**: `OLLMchat/Message.vala`

- Ensure new roles ("user-sent", "think-stream", "content-stream", "ui") are properly serialized/deserialized
- No special handling needed - they're just different role values

### 5. Remove original_content References

Search and update all references to `original_content`:

- `OLLMchat/Call/Chat.vala` - lines 69, 200, 328-329
- `OLLMchat/History/Session.vala` - line 177
- Any other files that reference `original_content`

### 6. Chat Signals (No Changes to Chat)

**File**: `OLLMchat/Call/Chat.vala`

- **NO CHANGES** - Chat continues to work exactly as before
- Chat fires signals: `chat_send`, `stream_chunk`, `stream_content`, `stream_start`, `tool_message`
- Chat manages its own `chat.messages` list with only API-compatible messages
- Session listens to these signals and updates its own `messages` property

## Files to Modify

1. **OLLMchat/Message.vala** - Remove original_content, add new role support
2. **OLLMchat/History/Session.vala** - Update `messages` property to maintain its own list (instead of wrapping `chat.messages`), capture messages from signals, filter on load
3. **OLLMchat/History/SessionBase.vala** - Connect to tool_message signal
4. **OLLMchat/History/SessionPlaceholder.vala** - Filter `messages` when loading into chat.messages
5. **OLLMchatGtk/ChatWidget.vala** - Filter messages when rendering
6. **OLLMchat/Call/Chat.vala** - Remove original_content references only (NO filtering changes)

## Implementation Notes

- **Chat is unchanged** - it only fires signals and manages its own `chat.messages` list
- **Session maintains separate list** - `messages` property is independent from `chat.messages`
- **Signal-based updates** - Session listens to Chat signals and updates `messages` accordingly
- **Filtering on load** - When loading from JSON, Session filters `messages` to populate `chat.messages` with only API-compatible messages
- **Streaming messages** are created once when streaming starts and updated incrementally in `messages`
- **All tool_message signals** are captured as "ui" messages in `messages`
- **JSON logs** will contain complete conversation history including all streaming and UI messages via `messages` property