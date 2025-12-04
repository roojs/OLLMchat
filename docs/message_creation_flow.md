# Message Creation Flow

This document details at what point in the flow of chat/response we create messages, including any created by the front end. The main logic being we might need to think about rationalizing this to making implementing event handlers a bit more simpler.

## Message Creation Points

### 1. Frontend (UI) Message Creation

#### User Message Display (ChatWidget)
**Location:** `OLLMchatGtk/ChatWidget.vala:375-380`

**When:** User clicks send button or presses Enter

**What happens:**
```vala
// Create a temporary ChatCall for displaying the user message
// This is a workaround just so the interface works - the actual ChatCall
// will be created later in send_message()
var user_call = new OLLMchat.Call.Chat(this.manager.session.client) {
    chat_content = text
};

// Display user message
this.chat_view.append_user_message(text, user_call);
```

**Purpose:** Immediate UI feedback - shows user message in chat view before backend processing

**Note:** This creates a temporary `Call.Chat` object just for display purposes. The actual `Call.Chat` used for the API request is created later in the backend.

**Rationalization Consideration:** This temporary object creation could be simplified - we might be able to pass just the text and message_interface separately, or create a proper Message object here instead of a temporary ChatCall.

### 2. Backend Message Creation

#### Initial Chat Request (Call.Chat.exec_chat)
**Location:** `OLLMchat/Call/Chat.vala:312-344`

**When:** First message in a conversation (not a reply)

**Messages created:**
1. **System message** (if `system_content` is set):
   ```vala
   if (this.system_content != "") {
       this.messages.add(new Message(this, "system", this.system_content));
   }
   ```
   - Added to `chat.messages` array
   - Role: "system"
   - Used for API request

2. **User message**:
   ```vala
   var user_message = new Message(this, "user", this.chat_content);
   this.messages.add(user_message);
   ```
   - Added to `chat.messages` array
   - Role: "user"
   - Content: `chat_content` (may be modified by prompt engine)
   - Used for API request

**Purpose:** Build message array for API request

#### Reply Message (Call.Chat.reply)
**Location:** `OLLMchat/Call/Chat.vala:185-217`

**When:** Continuing an existing conversation

**Messages created:**
1. **Assistant message** (from previous response):
   ```vala
   if (previous_response.message.tool_calls.size > 0) {
       this.messages.add(previous_response.message);
   } else {
       this.messages.add(
           new Message(this, "assistant", previous_response.message.content,
            previous_response.message.thinking));
   }
   ```
   - Added to `chat.messages` array
   - Role: "assistant"
   - If tool_calls exist, uses the original message object; otherwise creates new message
   - Used for API request

2. **User message** (new):
   ```vala
   var user_message = new Message(this, "user", new_text);
   this.messages.add(user_message);
   ```
   - Added to `chat.messages` array
   - Role: "user"
   - Content: `new_text`
   - Used for API request

**Purpose:** Build message array for API request continuation

#### Tool Execution (Call.Chat.toolsReply)
**Location:** `OLLMchat/Call/Chat.vala:231-309`

**When:** Assistant response contains tool_calls

**Messages created:**
1. **Assistant message with tool_calls**:
   ```vala
   this.messages.add(response.message);
   ```
   - Added to `chat.messages` array
   - Role: "assistant"
   - Contains `tool_calls` array
   - Used for API request continuation

2. **Tool reply messages** (one per tool call):
   ```vala
   this.messages.add(
       new Message.tool_reply(
           this, tool_call.id, 
           tool_call.function.name,
           result
       ));
   ```
   - Added to `chat.messages` array
   - Role: "tool"
   - Contains tool execution result
   - Used for API request continuation

3. **Tool failure messages** (if tool execution fails):
   ```vala
   this.messages.add(new Message.tool_call_fail(this, tool_call, e));
   ```
   - Added to `chat.messages` array
   - Role: "tool"
   - Contains error message
   - Used for API request continuation

4. **Tool invalid messages** (if tool not found):
   ```vala
   this.messages.add(new Message.tool_call_invalid(this, tool_call));
   ```
   - Added to `chat.messages` array
   - Role: "tool"
   - Contains error message
   - Used for API request continuation

**Purpose:** Build message array for API request continuation after tool execution

### 3. Session Persistence Message Creation

#### User Message Capture (Session.on_chat_send)
**Location:** `OLLMchat/History/Session.vala:83-133`

**When:** `chat_send` signal is emitted (before API request is sent)

**Messages created:**
1. **"user-sent" message** (raw user text):
   ```vala
   if (chat.original_user_text != "") {
       var user_sent_msg = new Message(chat, "user-sent", chat.original_user_text);
       this.messages.add(user_sent_msg);
   }
   ```
   - Added to `session.messages` array (separate from `chat.messages`)
   - Role: "user-sent"
   - Content: `original_user_text` (raw text before prompt engine modification)
   - Purpose: Persist the original user input for history

2. **Standard messages** (copied from `chat.messages`):
   ```vala
   foreach (var msg in chat.messages) {
       switch (msg.role) {
           case "system":
           case "user":
           case "assistant":
           case "tool":
               // Copy to session.messages if not already present
               if (!found) {
                   this.messages.add(msg);
               }
               break;
       }
   }
   ```
   - Added to `session.messages` array
   - Roles: "system", "user", "assistant", "tool"
   - Purpose: Persist API-compatible messages for history

**Purpose:** Capture messages for session persistence (separate from API request messages)

#### Streaming Message Capture (Session.on_stream_chunk)
**Location:** `OLLMchat/History/Session.vala:139-196`

**When:** `stream_chunk` signal is emitted (during streaming response)

**Messages created:**
1. **"think-stream" or "content-stream" messages**:
   ```vala
   if (this.current_stream_message == null || this.current_stream_is_thinking != is_thinking) {
       string stream_role = is_thinking ? "think-stream" : "content-stream";
       this.current_stream_message = new Message(this.chat, stream_role, new_text);
       this.current_stream_is_thinking = is_thinking;
       this.messages.add(this.current_stream_message);
   } else {
       // Same stream type - append to existing message
       this.current_stream_message.content += new_text;
   }
   ```
   - Added to `session.messages` array
   - Role: "think-stream" or "content-stream"
   - Content: Accumulated streaming text
   - Purpose: Persist streaming output for history

2. **"end-stream" message** (when streaming completes):
   ```vala
   if (response.done) {
       var end_stream_msg = new Message(this.chat, "end-stream", "");
       this.messages.add(end_stream_msg);
   }
   ```
   - Added to `session.messages` array
   - Role: "end-stream"
   - Purpose: Signal to renderer that streaming is complete

3. **Final assistant message** (when streaming completes):
   ```vala
   foreach (var msg in chat.messages) {
       if (msg.role == "assistant" && response.message == msg) {
           this.messages.add(msg);
           break;
       }
   }
   ```
   - Added to `session.messages` array
   - Role: "assistant"
   - Purpose: Persist final complete assistant response

**Purpose:** Capture streaming output for session persistence

#### UI Message Capture (SessionBase.tool_message handler)
**Location:** `OLLMchat/History/SessionBase.vala:144-153`

**When:** `tool_message` signal is emitted (during tool execution)

**Messages created:**
1. **"ui" message**:
   ```vala
   if (this is Session) {
       var session = this as Session;
       var ui_msg = new Message(session.chat, "ui", message);
       this.messages.add(ui_msg);
   }
   ```
   - Added to `session.messages` array
   - Role: "ui"
   - Content: Tool status message
   - Purpose: Persist UI status messages for history

**Purpose:** Capture tool status messages for session persistence

### 4. Response Message Creation

#### Streaming Response (Response.Chat.addChunk)
**Location:** `OLLMchat/Response/Chat.vala:112-208`

**When:** JSON chunk is received from API during streaming

**Messages created/updated:**
1. **First chunk** (creates message):
   ```vala
   if (this.message == null) {
       this.message = msg;
       this.new_content = msg.content;
       this.new_thinking = msg.thinking;
   }
   ```
   - Creates `response.message` object
   - Role: "assistant"
   - Content: Accumulated from chunks
   - Purpose: Build complete message from streaming chunks

2. **Subsequent chunks** (updates message):
   ```vala
   if (msg.content != "") {
       this.new_content = msg.content;
       this.message.content += this.new_content;
   }
   if (msg.thinking != "") {
       this.new_thinking = msg.thinking;
       this.message.thinking += this.new_thinking;
   }
   ```
   - Updates `response.message` object
   - Appends new content/thinking to existing message
   - Purpose: Accumulate streaming content

**Purpose:** Build complete message object from streaming JSON chunks

#### Non-Streaming Response
**Location:** `OLLMchat/Call/Chat.vala:346-379`

**When:** Non-streaming API response is received

**Messages created:**
- Message is deserialized from JSON response:
  ```vala
  var response_obj = Json.gobject_from_data(typeof(Response.Chat), json_str, -1) as Response.Chat;
  response_obj.message = // deserialized from JSON
  ```
  - Creates `response.message` object
  - Role: "assistant"
  - Content: Complete message from API
  - Purpose: Create message object from complete API response

## Message Arrays

### chat.messages
**Location:** `OLLMchat/Call/Chat.vala:71`

**Purpose:** Messages for API requests (Ollama-compatible format)

**Contains:**
- "system" messages
- "user" messages
- "assistant" messages
- "tool" messages

**Used for:**
- Building API request JSON
- Conversation history for API

**Modified by:**
- `Call.Chat.exec_chat()` - adds system and user messages
- `Call.Chat.reply()` - adds assistant and user messages
- `Call.Chat.toolsReply()` - adds assistant (with tool_calls) and tool messages

### session.messages
**Location:** `OLLMchat/History/SessionBase.vala:89`

**Purpose:** Messages for session persistence (includes UI-specific types)

**Contains:**
- "system" messages (copied from chat.messages)
- "user" messages (copied from chat.messages)
- "user-sent" messages (raw user text before prompt engine)
- "assistant" messages (copied from chat.messages or created from streaming)
- "tool" messages (copied from chat.messages)
- "think-stream" messages (streaming thinking content)
- "content-stream" messages (streaming regular content)
- "end-stream" messages (streaming completion marker)
- "ui" messages (tool status messages)

**Used for:**
- Session persistence (JSON file)
- Loading messages for UI display
- History browsing

**Modified by:**
- `Session.on_chat_send()` - adds user-sent and standard messages
- `Session.on_stream_chunk()` - adds streaming messages and final assistant message
- `SessionBase.tool_message handler` - adds UI messages

## Streaming Handling

### Current Implementation

**Streaming uses text and bool parameters:**
- `stream_chunk(string new_text, bool is_thinking, Response.Chat response)`
- `stream_content(string new_text, Response.Chat response)`

**Flow:**
1. `Call.Chat.process_streaming_chunk()` receives JSON chunk
2. `Response.Chat.addChunk()` processes chunk and updates `response.message`
3. `process_streaming_chunk()` extracts `new_content` or `new_thinking` from response
4. Signal emitted with text string and bool flag
5. UI components receive text and append to display
6. Session receives text and creates "think-stream" or "content-stream" messages

### Potential Rationalization

**Current Issues:**
- Text is passed as string, requiring UI to accumulate
- Session creates separate "think-stream"/"content-stream" messages
- Response object is passed but message content is extracted as text
- Multiple message objects created for same streaming content

**Potential Improvement:**
- Use Message objects directly in streaming signals instead of text + bool
- Signal could be: `stream_chunk(Message chunk, Response.Chat response)`
- Message object would have role "assistant" with content/thinking already set
- UI could append Message objects directly
- Session could use Message objects directly instead of creating new ones
- Would simplify event handlers - they receive Message objects instead of text + bool

**Benefits:**
- Single source of truth (Message object)
- No need to create separate "think-stream"/"content-stream" messages
- UI can work with Message objects directly
- Easier to track message state
- Simpler event handler signatures

**Considerations:**
- Message objects are mutable (content accumulates)
- Need to ensure Message objects are properly initialized
- May need to handle partial messages differently

## Message Creation Summary

| Location | When | Messages Created | Purpose |
|----------|------|------------------|---------|
| ChatWidget.on_send_clicked | User sends message | Temporary ChatCall | UI display |
| Call.Chat.exec_chat | First message | System, User | API request |
| Call.Chat.reply | Reply message | Assistant, User | API request |
| Call.Chat.toolsReply | Tool execution | Assistant (tool_calls), Tool replies | API request |
| Session.on_chat_send | Before API request | user-sent, Standard messages | Persistence |
| Session.on_stream_chunk | During streaming | think-stream, content-stream, end-stream, Assistant | Persistence |
| SessionBase.tool_message | Tool status | ui | Persistence |
| Response.Chat.addChunk | Streaming chunk | Assistant (accumulated) | Response building |

## Rationalization Opportunities

1. **Frontend Message Creation**: Replace temporary ChatCall with proper Message object or simplify interface
2. **Streaming Signals**: Use Message objects instead of text + bool parameters
3. **Session Message Types**: Consider if "think-stream"/"content-stream" are necessary or if we can use standard "assistant" messages
4. **Message Duplication**: Reduce duplication between chat.messages and session.messages
5. **Event Handler Simplification**: Standardize on Message objects throughout the flow

