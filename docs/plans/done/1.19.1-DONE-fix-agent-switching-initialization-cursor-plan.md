---
name: Fix agent switching initialization
overview: Fix the crash when switching agents where Chat is created with an empty model string. The issue occurs in Agent.Base constructor when model_usage has an empty model or invalid connection. Add validation and proper error handling.
todos:
  - id: validate-model-usage
    content: Add validation in Agent.Base constructor to check model_usage.model and connection before creating Chat
    status: pending
  - id: fallback-default-usage
    content: Implement fallback to default_model_usage if session model_usage is invalid
    status: pending
  - id: validate-connection
    content: Ensure connection is properly set with fallback to default connection if needed
    status: pending
  - id: validate-activate-agent
    content: Add validation in EmptySession.activate_agent() before creating agent
    status: pending
  - id: error-handling
    content: Add descriptive error messages for invalid model_usage scenarios
    status: pending
---

# Fix Agent Switching Initialization Issue

## Problem

When switching agents, the application crashes with "Model is required" error at `Chat.vala:182`. The stack trace shows:

1. `EmptySession.activate_agent()` creates a new agent
2. `Agent.Base` constructor tries to create a `Chat` object
3. `Chat` constructor receives an empty model string from `session.model_usage.model`
4. `Chat` constructor throws error because model is required

## Root Cause

In `Agent.Base` constructor (`libollmchat/Agent/Base.vala:86-109`):

- Gets model from `session.model_usage.model` without validation
- Connection handling only sets `this.connection` if `usage.connection != ""` and exists in config
- If `model_usage.model` is empty or `model_usage.connection` is invalid, Chat creation fails

The `model_usage` comes from `SessionBase` constructor which copies from `manager.default_model_usage`, but there's no validation that it's valid before agent creation.

## Solution

Add validation and error handling in `Agent.Base` constructor:

1. **Validate model_usage before creating Chat**:

   - Check that `usage.model` is not empty
   - Check that `usage.connection` is not empty and exists in config
   - If invalid, fall back to `manager.default_model_usage` or throw a descriptive error

2. **Ensure connection is properly set**:

   - If `usage.connection` is empty or not found, use default connection from manager
   - Ensure `this.connection` is never null when creating Chat

3. **Add defensive checks**:

   - Validate model_usage in `activate_agent()` before creating agent
   - Provide better error messages if model_usage is invalid

## Files to Modify

- `libollmchat/Agent/Base.vala` - Add validation in constructor before creating Chat
- `libollmchat/History/EmptySession.vala` - Validate model_usage in `activate_agent()` before creating agent
- `libollmchat/History/SessionBase.vala` - Consider adding validation in constructor or ensure default_model_usage is always valid

## Implementation Details

### In `Agent.Base` constructor:

```vala
// Get model and options from session.model_usage
var usage = this.session.model_usage;

// Validate model_usage - fallback to default if invalid
if (usage.model == "" || usage.connection == "") {
    GLib.warning("Session model_usage is invalid (model='%s', connection='%s'), using default_model_usage", 
        usage.model, usage.connection);
    usage = this.session.manager.default_model_usage;
    if (usage == null || usage.model == "" || usage.connection == "") {
        throw new OllmError.INVALID_ARGUMENT("Invalid model_usage: model and connection must be set");
    }
}

// Get connection from model_usage - ensure it exists in config
if (usage.connection != "" && this.session.manager.config.connections.has_key(usage.connection)) {
    this.connection = this.session.manager.config.connections.get(usage.connection);
} else {
    // Fallback to default connection
    var default_conn = this.session.manager.config.default_connection();
    if (default_conn != null) {
        this.connection = default_conn;
        GLib.warning("Connection '%s' not found, using default connection", usage.connection);
    } else {
        throw new OllmError.INVALID_ARGUMENT("No valid connection available");
    }
}

// Validate model is not empty before creating Chat
if (usage.model == "") {
    throw new OllmError.INVALID_ARGUMENT("Model is required but model_usage.model is empty");
}

// Create Chat instance...
```

### In `EmptySession.activate_agent()`:

Add validation before creating agent:

```vala
// Validate model_usage before creating agent
if (this.model_usage == null || this.model_usage.model == "" || this.model_usage.connection == "") {
    GLib.warning("EmptySession model_usage is invalid, using default_model_usage");
    this.model_usage = this.manager.default_model_usage;
    if (this.model_usage == null || this.model_usage.model == "" || this.model_usage.connection == "") {
        throw new OllmError.INVALID_ARGUMENT("Cannot activate agent: invalid model_usage");
    }
}
```

## Testing

1. Test agent switching on EmptySession with valid model_usage
2. Test agent switching when model_usage has empty model
3. Test agent switching when model_usage has invalid connection
4. Test agent switching when default_model_usage is also invalid (should show proper error)
5. Test normal agent creation flow to ensure no regressions