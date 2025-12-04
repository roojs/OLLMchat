# Signal Flow and Listeners

This document describes all signals in the OLLMchat system, when they are emitted, and the tree of listeners connected to them.

## Signal Hierarchy

### 1. Client Signals (`OLLMchat.Client`)

These signals are emitted by the `Client` class and represent events from the Ollama API interaction layer.

#### `chat_send(Call.Chat chat)`
**When emitted:**
- Emitted in `Call.Chat.execute_streaming()` (line 384) just before sending the HTTP request
- Emitted in `Call.Chat.execute_non_streaming()` (line 349) just before sending the HTTP request
- Occurs for both initial chat requests and automatic continuations after tool execution

**Listeners:**
1. **SessionBase.on_chat_send()** (persistence handler)
   - Connected in `SessionBase.activate()` (line 128)
   - **Purpose:** Handles session creation and message capture for persistence
   - Implementation: `Session.on_chat_send()` creates "user-sent" messages and copies standard messages to `session.messages`

2. **Manager.chat_send()** (UI relay)
   - Connected via anonymous lambda in `SessionBase.activate()` (line 132-134)
   - **Purpose:** Relays signal from active session's client to Manager
   - Manager then emits its own `chat_send` signal (line 46)

3. **Manager.chat_send → ChatWidget** (UI consumption)
   - Not directly connected - Manager's signal is available but not currently used by ChatWidget
   - **Purpose:** Show the sending/waiting indicator when a chat request is sent
   - Intended to trigger `ChatView.show_waiting_indicator()` to display the animated "waiting for a reply..." indicator

#### `stream_chunk(string new_text, bool is_thinking, Response.Chat response)`
**When emitted:**
- Emitted in `Call.Chat.process_streaming_chunk()` (line 485-490) for each JSON chunk received
- Emitted when there's new content (thinking or regular) OR when `response.done == true` (even if no new content)
- Contains either `new_thinking` or `new_content` (never both in same emission)
- The `is_thinking` parameter indicates whether the chunk is thinking content

**Listeners:**
1. **SessionBase.on_stream_chunk()** (persistence handler)
   - Connected in `SessionBase.activate()` (line 129)
   - **Purpose:** Captures streaming output for session persistence
   - Implementation: `Session.on_stream_chunk()` creates "think-stream" or "content-stream" messages, tracks streaming state, and saves when done

2. **Manager.stream_chunk()** (UI relay)
   - Connected via anonymous lambda in `SessionBase.activate()` (line 135-137)
   - **Purpose:** Relays signal from active session's client to Manager
   - Manager then emits its own `stream_chunk` signal (line 47)

3. **Manager.stream_chunk → ChatWidget.on_stream_chunk_handler()** (UI consumption)
   - Connected in `ChatWidget` constructor (line 113)
   - **Purpose:** Updates UI with streaming chunks
   - Implementation: Calls `chat_view.append_assistant_chunk()` for each chunk, finalizes message when `response.done == true`

#### `stream_content(string new_text, Response.Chat response)`
**When emitted:**
- Emitted in `Call.Chat.process_streaming_chunk()` (line 467-470) only for content chunks (not thinking)
- Emitted when `new_content.length > 0` (regular content, not thinking)
- Used by tools to capture streaming messages and extract code blocks as they arrive

**Listeners:**
1. **Manager.stream_content()** (UI relay)
   - Connected via anonymous lambda in `SessionBase.activate()` (line 138-140)
   - **Purpose:** Relays signal from active session's client to Manager
   - Manager then emits its own `stream_content` signal (line 48)

2. **Tools (e.g., EditMode)**
   - Connected in `EditMode` constructor (line 91-95)
   - **Purpose:** Tools can capture streaming content to extract code blocks and build strings
   - Example: `EditMode` uses this to capture code as it streams in

#### `stream_start()`
**When emitted:**
- Emitted in `Call.Chat.process_streaming_chunk()` (line 460) when `streaming_response.message == null` (first chunk)
- Emitted in `Call.Chat.execute_non_streaming()` (line 359) when response is received (non-streaming mode)
- Indicates that the server has started sending data back

**Listeners:**
1. **Manager.stream_start()` (UI relay)
   - Connected via anonymous lambda in `SessionBase.activate()` (line 141-143)
   - **Purpose:** Relays signal from active session's client to Manager
   - Manager then emits its own `stream_start` signal (line 49)

2. **Tools (e.g., EditMode)**
   - Connected in `EditMode` constructor (line 81-89)
   - **Purpose:** Tools can initialize state when streaming starts
   - Example: `EditMode` resets its state when streaming starts

#### `tool_message(string message, Object? widget = null)`
**When emitted:**
- Emitted by tools during execution to show status messages
- Emitted in `Call.Chat.toolsReply()` (line 255, 261, 283) when tools are executed
- Emitted in `Message.tool_call_invalid()` (line 100) when a tool is not found
- The `widget` parameter is optional and expected to be a `Gtk.Widget` (typed as `Object?` for library independence)

**Listeners:**
1. **SessionBase.tool_message handler** (persistence + UI relay)
   - Connected in `SessionBase.activate()` (line 144-153)
   - Disconnected in `SessionBase.deactivate()` (line 176)
   - Purpose: Captures UI messages as "ui" role messages in `session.messages` (for Session instances), then relays to Manager
   - Implementation: Creates "ui" message and adds to `session.messages`, then relays to Manager

2. **Manager.tool_message()** (UI relay)
   - Manager emits its own `tool_message` signal (line 50) after receiving from SessionBase

3. **Manager.tool_message → ChatWidget.chat_view.append_tool_message()** (UI consumption)
   - Connected in `ChatWidget` constructor (line 114)
   - Purpose: Displays tool status messages in the chat view

### 2. Manager Signals (`OLLMchat.History.Manager`)

These signals are emitted by the `Manager` class and represent session management events and UI relay signals.

#### `session_added(SessionBase session)`
**When emitted:**
- Emitted in `Manager.create_new_session()` (line 189) when a new session is created
- Emitted in `Session.on_chat_send()` (line 126) when a session is first tracked

**Listeners:**
1. **HistoryBrowser.on_session_added()**
   - Connected in `HistoryBrowser` constructor (line 104)
   - Purpose: Updates UI when a new session is added to the history

#### `session_removed(SessionBase session)`
**When emitted:**
- Currently not emitted (placeholder for future functionality)

**Listeners:**
- None currently

#### `session_activated(SessionBase session)`
**When emitted:**
- Emitted in `Manager.switch_to_session()` (line 176) when switching to a new session
- Emitted in `EmptySession.send_message()` (line 111) when EmptySession converts to Session

**Listeners:**
1. **ChatInput.model_dropdown update**
   - Connected in `ChatInput` constructor (line 432)
   - Purpose: Updates model dropdown when session is activated

#### Manager Relay Signals

The Manager also relays client signals from the active session:
- `chat_send(Call.Chat chat)` - Relayed from active session's client
- `stream_chunk(string new_text, bool is_thinking, Response.Chat response)` - Relayed from active session's client
- `stream_content(string new_text, Response.Chat response)` - Relayed from active session's client
- `stream_start()` - Relayed from active session's client
- `tool_message(string message, Object? widget = null)` - Relayed from active session's client

### 3. ChatWidget Signals (`OLLMchatGtk.ChatWidget`)

These signals are emitted by the `ChatWidget` class and represent user-facing events.

#### `message_sent(string text)`
**When emitted:**
- Emitted in `ChatWidget.on_send_clicked()` (line 384) when user sends a message

**Listeners:**
1. **TestWindow.message_sent handler**
   - Connected in `TestWindow` constructor (line 201)
   - Purpose: Logs or handles message sent events (example usage)

#### `response_received(string text)`
**When emitted:**
- Emitted in `ChatWidget.on_stream_chunk_handler()` (line 364) when final response is received (no tool_calls)
- Only emitted for final responses, not intermediate tool call responses

**Listeners:**
1. **TestWindow.response_received handler**
   - Connected in `TestWindow` constructor (line 205)
   - Purpose: Logs or handles response received events (example usage)

#### `error_occurred(string error)`
**When emitted:**
- Emitted in `ChatWidget.handle_error()` (line 468) when an error occurs during chat operations

**Listeners:**
1. **TestWindow.error_occurred handler**
   - Connected in `TestWindow` constructor (line 215)
   - Purpose: Logs or handles error events (example usage)

## Signal Flow Diagram

```
Client (OLLMchat.Client)
├── chat_send
│   ├──→ SessionBase.on_chat_send() [persistence]
│   └──→ Manager.chat_send() [relay]
│       └──→ (available for UI consumption)
│
├── stream_chunk
│   ├──→ SessionBase.on_stream_chunk() [persistence]
│   └──→ Manager.stream_chunk() [relay]
│       └──→ ChatWidget.on_stream_chunk_handler() [UI]
│
├── stream_content
│   └──→ Manager.stream_content() [relay]
│       └──→ Tools (e.g., EditMode) [tool consumption]
│
├── stream_start
│   └──→ Manager.stream_start() [relay]
│       └──→ Tools (e.g., EditMode) [tool initialization]
│
└── tool_message
    └──→ SessionBase.tool_message handler [persistence + relay]
        └──→ Manager.tool_message() [relay]
            └──→ ChatWidget.chat_view.append_tool_message() [UI]

Manager (OLLMchat.History.Manager)
├── session_added
│   └──→ HistoryBrowser.on_session_added() [UI]
│
├── session_activated
│   └──→ ChatInput.model_dropdown update [UI]
│
└── (relay signals from active session's client)
    ├── chat_send
    ├── stream_chunk
    ├── stream_content
    ├── stream_start
    └── tool_message

ChatWidget (OLLMchatGtk.ChatWidget)
├── message_sent
│   └──→ TestWindow.message_sent handler [example]
│
├── response_received
│   └──→ TestWindow.response_received handler [example]
│
└── error_occurred
    └──→ TestWindow.error_occurred handler [example]
```

## Signal Connection Lifecycle

1. **Session Activation** (`SessionBase.activate()`):
   - Connects client signals to persistence handlers (`on_chat_send`, `on_stream_chunk`)
   - Connects client signals to Manager relay (anonymous lambdas)
   - Each connection stores handler ID for later disconnection

2. **Session Deactivation** (`SessionBase.deactivate()`):
   - Disconnects all client signal handlers
   - Prevents signals from inactive sessions from reaching UI

3. **Manager Relay**:
   - Manager always has relay signals available
   - Only the active session's client signals are relayed
   - UI components connect to Manager signals (not directly to Client)

## Notes

- **Signal Routing**: Signals flow from Client → SessionBase (persistence) → Manager (relay) → UI components
- **Active Session Only**: Only the active session's client signals are relayed to the UI
- **Persistence vs UI**: SessionBase handlers capture data for persistence, while Manager relays handle UI updates
- **Tool Integration**: Tools can connect directly to client signals or use Manager relay signals
- **Disconnection**: All signal connections are properly cleaned up when sessions are deactivated

