# Load Session into Chat Implementation Plan

## Overview

Add a `load_session()` method to `ChatWidget` that handles loading a history session into the chat interface. This method will:

1. Load the session's JSON file (if not already loaded)
2. Clear the current chat view
3. Set the current_chat to the session's chat
4. Render all messages from the session to ChatView

## Architecture Understanding

### Current State

- **ChatWidget** (`OLLMchatGtk/ChatWidget.vala`): Main widget that manages chat state
                                - Has `current_chat` property (type `Call.Chat?`)
                                - Has `chat_view` property (type `ChatView`)
                                - Has `clear_chat()` method that clears the view and resets `current_chat`

- **ChatView** (`OLLMchatGtk/ChatView.vala`): Display component for messages
                                - Has `append_user_message(string text, MessageInterface message)` for user messages
                                - Has `append_assistant_chunk(string new_text, MessageInterface message)` for assistant messages (streaming)
                                - Has `finalize_assistant_message(Response.Chat? response = null)` to finalize assistant messages
                                - Has `clear()` method to clear all content

- **Session** (`OLLMchat/History/Session.vala`): Wraps `Call.Chat` for history
                                - Has `chat` property (type `Call.Chat`)
                                - Has `messages` property that returns `this.chat.messages`
                                - Has `read()` async method to load messages from JSON file
                                - Messages are stored in `session.chat.messages` (type `Gee.ArrayList<Message>`)

### Key Challenge

`ChatView.append_assistant_chunk()` expects a `Response.Chat` object, which is created during streaming. For loaded messages, we need to render complete assistant messages without streaming.

## Implementation Plan

### 1. Add `load_session()` method to ChatWidget

**File**: `OLLMchatGtk/ChatWidget.vala`

Add a new async method:

```vala
/**
 * Loads a history session into the chat widget.
 * 
 * This method:
 * - Loads the session's JSON file (if not already loaded)
 * - Clears the current chat view
 * - Sets current_chat to the session's chat
 * - Renders all messages from the session to ChatView
 * 
 * @param session The session to load
 * @throws Error if loading fails
 * @since 1.0
 */
public async void load_session(OLLMchat.History.Session session) throws Error
```

**Implementation steps**:

1. **Cancel active streaming** (if any): Check `is_streaming_active` and cancel using `current_chat.cancellable.cancel()`, then finalize and clean up (see section 2.a)
2. Load session JSON file: `yield session.read()` (if messages are empty or need reloading)
3. Clear current chat: `this.clear_chat()` (this clears the view and resets `current_chat`)
4. **Reset markdown renderer**: Ensure renderer state is clean (see section 2.a)
5. Set current_chat: `this.current_chat = session.chat`
6. Iterate through messages and render:

                                                - For `role == "user"`: Call `chat_view.append_user_message(msg.content, msg)`
                                                - For `role == "assistant"`: Need to render complete message (see below)
                                                - For `role == "tool"`: Skip (tool messages are internal, not displayed)

### 2. Handle Assistant Messages

**Option A**: Create a helper method in ChatView to render complete assistant messages

- Add `append_complete_assistant_message(Message message)` to ChatView
- This method would:
                                - Initialize assistant message state
                                - Process content (handling thinking, code blocks, etc.)
                                - Finalize the message

**Option B**: Use existing methods with a synthetic Response.Chat

- Create a minimal `Response.Chat` object from the loaded message
- Call `append_assistant_chunk()` with full content, then `finalize_assistant_message()`

**Recommendation**: Option A is cleaner and more explicit. We'll add a new method to ChatView.

### 2.a. Cancel Active Streaming and Reset Renderer

Before loading a session, we must handle two critical cleanup tasks:

**Cancel Active Streaming**:

If the chat is currently streaming output, it must be cancelled before loading a new session. This prevents:
- Partial responses from being displayed
- Streaming callbacks from interfering with loaded content
- Resource leaks from abandoned network requests

**Implementation in `load_session()`**:

```vala
// Check if streaming is active and cancel it
if (this.is_streaming_active) {
    // Mark streaming as inactive to prevent callbacks from updating UI
    this.is_streaming_active = false;
    
    // Cancel the call's cancellable
    if (this.current_chat != null && this.current_chat.cancellable != null) {
        this.current_chat.cancellable.cancel();
    }
    
    // Finalize any ongoing assistant message
    this.chat_view.finalize_assistant_message();
    
    // Clean up streaming state
    this.chat_input.set_streaming(false);
}
```

**Reset Markdown Renderer**:

The markdown renderer (`ChatView.renderer`) maintains internal state (current TextView, buffer, parser state, etc.). When loading a new session, we need to ensure the renderer is in a clean state.

**Implementation**:

The `ChatView.clear()` method already clears widgets and resets most state, but we should ensure the renderer is properly reset. The renderer maintains:
- `current_textview` and `current_buffer` references
- `top_state` and `current_state` for parser state
- Parser internal state (via `base.start()`)

**Action**: After `clear_chat()` is called, we should explicitly reset the renderer by calling `renderer.end_block()` if there's an active block. This ensures:
- `current_textview` and `current_buffer` are set to null
- A new `TopState` is created
- Parser state is reset

**Note**: The `clear()` method removes widgets from the box, but doesn't reset the renderer's internal state. We should add a call to `renderer.end_block()` in `ChatView.clear()`, or call it explicitly in `load_session()` after `clear_chat()`.

**Recommended approach**: Update `ChatView.clear()` to call `renderer.end_block()` if `renderer.current_textview != null`, ensuring the renderer is always reset when clearing the view.

### 3. Add `append_complete_assistant_message()` to ChatView

**File**: `OLLMchatGtk/ChatView.vala`

Add method to render a complete (non-streaming) assistant message:

```vala
/**
 * Appends a complete assistant message (not streaming).
 * Used when loading sessions from history.
 * 
 * @param message The complete Message object to display
 * @since 1.0
 */
public void append_complete_assistant_message(OLLMchat.Message message)
```

**Implementation**:

- Initialize assistant message state (similar to `initialize_assistant_message()`)
- Set `is_thinking` based on `message.thinking != ""`
- Process the content using existing chunk processing logic
- Handle thinking content if present
- Finalize the message

### 5. Handle Thinking Content

When loading assistant messages with thinking content:

- If `message.thinking != ""`, we need to render thinking content first
- Then render regular content
- Use the existing thinking state machine in ChatView

### 5. Integration with HistoryBrowser

**File**: `OLLMchatGtk/HistoryBrowser.vala`

The `session_selected` signal is already emitted when a session is selected. The parent window (TestWindow or future main window) should:

- Connect to `session_selected` signal
- Call `chat_widget.load_session.begin(session)` when a session is selected

## Files to Modify

1. **OLLMchatGtk/ChatWidget.vala**

                                                - Add `load_session()` async method

2. **OLLMchatGtk/ChatView.vala**

                                                - Add `append_complete_assistant_message()` method
                                                - May need to refactor existing chunk processing logic to be reusable
                                                - Update `clear()` method to reset renderer state by calling `renderer.end_block()` if `renderer.current_textview != null`

3. **TestWindow.vala** (or future main window)

                                                - Connect to HistoryBrowser's `session_selected` signal
                                                - Call `chat_widget.load_session.begin(session)` when session is selected

## Implementation Details

### Loading Session Messages

```vala
// In ChatWidget.load_session()

// Step 1: Cancel active streaming if any
if (this.is_streaming_active) {
    this.is_streaming_active = false;
    if (this.current_chat != null && this.current_chat.cancellable != null) {
        this.current_chat.cancellable.cancel();
    }
    this.chat_view.finalize_assistant_message();
    this.chat_input.set_streaming(false);
}

// Step 2: Load session JSON file if needed
yield session.read();

// Step 3: Clear current chat (clears view and resets current_chat)
this.clear_chat();

// Step 4: Reset markdown renderer (ensure clean state)
// Note: This should be handled by ChatView.clear(), but we ensure it here
if (this.chat_view.renderer.current_textview != null) {
    this.chat_view.renderer.end_block();
}

// Step 5: Set current_chat to session's chat
this.current_chat = session.chat;

// Step 6: Iterate through messages and render
foreach (var msg in session.chat.messages) {
    if (msg.role == "user") {
        this.chat_view.append_user_message(msg.content, msg);
    } else if (msg.role == "assistant") {
        this.chat_view.append_complete_assistant_message(msg);
    }
    // Skip tool messages - they're not displayed
}
```

### Rendering Complete Assistant Message

The `append_complete_assistant_message()` method should:

1. Initialize assistant message state
2. If thinking content exists, render it first (with thinking styling)
3. Render regular content (with content styling)
4. Handle code blocks, markdown, etc. using existing logic
5. Finalize the message

## Testing Considerations

- Test loading a session with only user messages
- Test loading a session with user and assistant messages
- Test loading a session with thinking content
- Test loading a session with code blocks
- Test loading a session with tool calls (should skip tool messages)
- Test loading an empty session
- Test error handling (file not found, invalid JSON, etc.)

## Future Enhancements

- Add visual indicator when a session is being loaded
- Add progress indication for large sessions
- Handle hidden messages (when that feature is implemented)
- Support for loading partial sessions (rewind feature)