# Refactor Client Management for Multi-Chat Support

## Overview

Refactor the UI-Client interaction architecture so Manager acts as a signal gateway, creating fresh clients per session. Sessions are created lazily (chat only created when deserializing JSON). Manager handles session activation/deactivation and tracks unread messages.

## Key Changes

### 1. Manager Constructor and Base Client

**File**: `OLLMchat/History/Manager.vala`

- Add `base_client` property to Manager constructor
- Remove `register_client()` method (no longer needed)
- Add `active_session` property to track currently active session
- Manager connects/disconnects its signals to/from session clients
- Add `switch_to_session(Session session)` method

### 2. Client Factory Method in Manager

**File**: `OLLMchat/History/Manager.vala`

- Add `create_client()` private method to Manager (NOT Client)
- Copy all properties from base_client:
  - url, api_key, model, stream, format, think, keep_alive
  - prompt_assistant (shared reference)
  - permission_provider (shared reference - MUST be shared)
  - runtime options (seed, temperature, top_p, top_k, num_predict, repeat_penalty, num_ctx, stop, timeout)
  - available_models (can be copied - shared model data)
- Create fresh tools using Object.new() with named parameters (trivial code, not a separate method)
- Document properties NOT copied and reasons:
  - streaming_response: Session-specific streaming state
  - session: Not applicable to new client instance
  - tools: Created fresh (each session needs its own tool instances)

**Implementation**:

```vala
private Client create_client()
{
    var client = new Client();
    
    // Copy all properties
    client.url = this.base_client.url;
    client.api_key = this.base_client.api_key;
    client.model = this.base_client.model;
    client.stream = this.base_client.stream;
    client.format = this.base_client.format;
    client.think = this.base_client.think;
    client.keep_alive = this.base_client.keep_alive;
    client.prompt_assistant = this.base_client.prompt_assistant; // Shared reference
    client.permission_provider = this.base_client.permission_provider; // Shared reference
    client.seed = this.base_client.seed;
    client.temperature = this.base_client.temperature;
    client.top_p = this.base_client.top_p;
    client.top_k = this.base_client.top_k;
    client.num_predict = this.base_client.num_predict;
    client.repeat_penalty = this.base_client.repeat_penalty;
    client.num_ctx = this.base_client.num_ctx;
    client.stop = this.base_client.stop;
    client.timeout = this.base_client.timeout;
    
    // Copy available_models (shared model data)
    foreach (var entry in this.base_client.available_models.entries) {
        client.available_models.set(entry.key, entry.value);
    }
    
    // Create fresh tools using Object.new() with named parameters
    foreach (var tool in this.base_client.tools.values) {
        var tool_type = tool.get_type();
        var new_tool = (Tool.Interface) Object.new(tool_type, client: client);
        client.addTool(new_tool);
    }
    
    // Properties NOT copied (and why):
    // - streaming_response: Session-specific streaming state
    // - session: Not applicable to new client instance
    // - tools: Created fresh above (each session needs its own tool instances)
    
    return client;
}
```

### 3. Session Constructor - Manager First, Optional Chat

**File**: `OLLMchat/History/Session.vala`

- Modify Session constructor: Manager first, optional Call.Chat second
- Do NOT create Call.Chat in constructor - only create when deserializing JSON
- Store client reference (created from Manager's create_client())
- Add lazy `chat` property that creates Call.Chat only when needed (e.g., during JSON deserialization)
- Add `activate()` method to connect Manager signals
- Add `deactivate()` method to disconnect Manager signals
- Add `unread_count` property for inactive sessions

**Changes**:

```vala
public class Session : Object
{
    public Client client { get; private set; }
    private Call.Chat? _chat = null;
    
    public Call.Chat chat {
        get {
            if (this._chat == null) {
                this._chat = new Call.Chat(this.client);
            }
            return this._chat;
        }
        set {
            this._chat = value;
            if (this._chat != null) {
                this._chat.client = this.client;
            }
        }
    }
    
    public int unread_count { get; set; default = 0; }
    public bool is_active { get; private set; default = false; }
    
    public Session(Manager manager, Call.Chat? chat = null)
    {
        this.manager = manager;
        this.client = manager.create_client(); // Manager creates client
        
        // Only set chat if provided (e.g., from JSON deserialization)
        // Do NOT create chat in constructor - create lazily when needed
        if (chat != null) {
            this.chat = chat;
        }
    }
    
    public void activate()
    {
        if (this.is_active) return;
        this.is_active = true;
        this.unread_count = 0;
        this.manager.connect_session_signals(this);
    }
    
    public void deactivate()
    {
        if (!this.is_active) return;
        this.is_active = false;
        this.manager.disconnect_session_signals(this);
    }
}
```

### 4. Manager Signal Gateway

**File**: `OLLMchat/History/Manager.vala`

- Add `connect_session_signals(Session session)` method
- Add `disconnect_session_signals(Session session)` method
- Manager connects to session's client signals (chat_send, stream_chunk)
- Track unread messages when session is inactive

**Implementation**:

```vala
private void connect_session_signals(Session session)
{
    session.client.chat_send.connect(this.on_chat_send);
    session.client.stream_chunk.connect(this.on_stream_chunk);
}

private void disconnect_session_signals(Session session)
{
    session.client.chat_send.disconnect(this.on_chat_send);
    session.client.stream_chunk.disconnect(this.on_stream_chunk);
}

public void switch_to_session(Session session)
{
    // Deactivate current session
    if (this.active_session != null) {
        this.active_session.deactivate();
    }
    
    // Activate new session
    this.active_session = session;
    session.activate();
}

private void on_chat_send(Call.Chat chat)
{
    // Find or create session for this chat
    var session = this.sessions_by_fid.get(chat.fid);
    if (session == null) {
        // Session should already exist - this is a continuation
        return;
    }
    
    session.chat = chat; // Update chat reference
    session.save_async.begin();
    session.notify_property("display_info");
    session.notify_property("display_title");
}

private void on_stream_chunk(string new_text, bool is_thinking, Response.Chat response)
{
    var session = this.sessions_by_fid.get(response.call.fid);
    if (session == null) return;
    
    // If session is inactive, increment unread count
    if (!session.is_active) {
        session.unread_count++;
        session.notify_property("unread_count");
    }
    
    // Save when response is done
    if (response.done) {
        session.save_async.begin();
        session.notify_property("display_info");
        session.notify_property("title");
    }
}
```

### 5. Manager Session Creation - Rethink Required

**File**: `OLLMchat/History/Manager.vala`

- **IMPORTANT**: Since UI will talk to Session directly, Manager no longer needs to auto-create sessions from chat_send signals
- UI will create new sessions when needed (e.g., "New Chat" button)
- Manager's role is to:
  - Provide `create_client()` factory method
  - Connect/disconnect signals when sessions activate/deactivate
  - Track active session
  - Handle session persistence (save/load)
- **TBD**: Need to clarify session creation flow with UI interaction
  - How does UI create new sessions?
  - When does Manager detect new chats?
  - How are sessions associated with chats?

### 6. ChatWidget Session-Based Interface

**File**: `OLLMchatGtk/ChatWidget.vala`

- Change to work with Session and Manager instead of direct Client
- Add `session` property, `client` becomes computed property
- Add `switch_to_session(Session session)` method
- **Simplified**: Just call session.deactivate()/activate() - don't manage individual client signals
- Manager handles signal connection/disconnection via session activate/deactivate

**Changes**:

```vala
public class ChatWidget : Gtk.Box
{
    public Session? session { get; private set; default = null; }
    public Manager manager { get; private set; }
    
    public Client? client {
        get { return this.session?.client; }
    }
    
    public ChatWidget(Manager manager)
    {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        this.manager = manager;
        this.setup_signal_handlers();
    }
    
    public void switch_to_session(Session session)
    {
        // Deactivate old session (Manager disconnects signals)
        if (this.session != null) {
            this.session.deactivate();
        }
        
        // Switch manager to new session (Manager connects signals)
        this.manager.switch_to_session(session);
        this.session = session;
        
        // Update ChatInput
        if (this.session.client != null) {
            this.chat_input.setup_model_dropdown(this.session.client);
        }
    }
    
    private void setup_signal_handlers()
    {
        // These will connect to session.client when session is activated
        // Manager handles the connection via connect_session_signals()
        // ChatWidget just needs to handle UI updates from signals
    }
}
```

### 7. Session Chat Loading

**File**: `OLLMchat/History/Session.vala`

- When loading from JSON, create Call.Chat during deserialization
- Only create chat when deserializing JSON - not in constructor
- Chat property getter creates lazily if not set (for new chats)

### 8. TestWindow Updates

**File**: `TestWindow.vala`

- Update Manager constructor to pass base_client
- Remove `register_client()` call
- Update ChatWidget constructor to take Manager
- Update history browser to use Manager's `switch_to_session()`

## Implementation Order

1. Add `create_client()` method to Manager (with tool creation using Object.new())
2. Update Session constructor (Manager first, optional chat, add activate/deactivate)
3. Update Manager (add base_client, signal gateway methods, switch_to_session)
4. Rethink Manager session creation flow (how UI creates sessions)
5. Update ChatWidget (session-based interface, simplified signal handling)
6. Update TestWindow
7. Test session switching and unread tracking

## Files to Modify

- `OLLMchat/History/Manager.vala` - Add create_client(), signal gateway, session switching
- `OLLMchat/History/Session.vala` - Constructor update, lazy chat, activate/deactivate
- `OLLMchatGtk/ChatWidget.vala` - Session-based interface, simplified signal handling
- `TestWindow.vala` - Update initialization

## Open Questions

1. **Session Creation Flow**: How does UI create new sessions? Does Manager provide a method, or does UI create Session directly?
2. **Chat Detection**: How does Manager detect new chats if not auto-creating from signals? Does it listen to session clients?
3. **Session Persistence**: When UI creates a new session, when does it get saved to database?
