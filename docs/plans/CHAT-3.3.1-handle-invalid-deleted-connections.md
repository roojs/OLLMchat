# 3.3.1. Handle Invalid and Deleted Connections

## Overview

Handle cases where chat history sessions reference connections that have been deleted or modified in the configuration system. Ensure sessions can load gracefully even when their referenced connections no longer exist.

**Parent Plan**: [3.3. Chat History System](./3.3-DONE-chat-history-system.md)

## Status

⏳ **PENDING** - Not yet implemented

## Problem

Currently, sessions store `model_usage` which references a connection by name. When loading a session:

1. If the connection name no longer exists in config, the session may fail to load
2. If the connection exists but has been modified (different URL, API key, etc.), the session may not restore correctly
3. There's no validation or graceful handling for missing connections

## Current Implementation

**File**: `libollmchat/History/SessionBase.vala`

The `reconstruct_model_usage_from_model()` method searches for the model in available connections:

```vala
public void reconstruct_model_usage_from_model()
{
    // Search for model in connection_models
    var found_usage = this.manager.connection_models.find_model_by_name(this.model_usage_model);
    if (found_usage != null) {
        // Clone the found usage
        var usage = found_usage.clone();
        // ...
        this.model_usage = usage;
        return;
    }
    
    // Model not found, create new ModelUsage with default connection
    var default_connection = this.manager.config.default_connection();
    // ...
}
```

**Issues**:
- If connection is deleted, `find_model_by_name()` may fail
- No validation that the connection still exists
- No user notification when connection is missing
- No option to update session to use a different connection

## Goals

1. **Validation**: Check that referenced connections exist when loading sessions
2. **Graceful Degradation**: Handle missing connections without crashing
3. **User Notification**: Inform users when sessions reference deleted connections
4. **Recovery Options**: Allow users to update sessions to use available connections
5. **Connection URL Storage**: Consider storing connection URL/identifier in session JSON for better recovery

## Implementation Plan

### Phase 1: Connection Validation

1. **Add Connection Validation in Session Loading**
   - In `SessionPlaceholder.load()` and `Session.read()`, validate that the connection referenced in `model_usage` still exists
   - Check `manager.config.connections.has_key(connection_name)`

2. **Handle Missing Connections**
   - If connection is missing, log a warning
   - Attempt to find an alternative connection that has the same model available
   - If no alternative found, use default connection
   - Mark session as having a connection issue (add flag/property)

### Phase 2: User Notification

1. **Visual Indicators**
   - Add visual indicator in HistoryBrowser for sessions with connection issues
   - Show warning icon or badge on affected sessions
   - Display tooltip explaining the issue

2. **Error Messages**
   - When user tries to load a session with missing connection, show informative dialog
   - Explain which connection is missing
   - Offer to update session to use a different connection

### Phase 3: Recovery Options

1. **Connection Update Dialog**
   - When loading session with missing connection, show dialog with:
     - List of available connections that have the required model
     - Option to update session to use selected connection
     - Option to cancel and keep session as-is (marked with warning)

2. **Session Update**
   - Add method to update session's `model_usage` to use a different connection
   - Update both database and JSON file when connection is changed

### Phase 4: Enhanced Storage (Optional)

1. **Store Connection URL**
   - Add `connection_url` field to session JSON
   - Use URL as fallback identifier when connection name is missing
   - Attempt to match URL to existing connections when loading

## Files to Modify

- `libollmchat/History/SessionBase.vala` - Add connection validation
- `libollmchat/History/SessionPlaceholder.vala` - Validate on load
- `libollmchat/History/Session.vala` - Validate on read
- `libollmchatgtk/HistoryBrowser.vala` - Add visual indicators
- `ollmapp/Window.vala` - Handle connection update dialogs

## Related Plans

- [3.3. Chat History System](./3.3-DONE-chat-history-system.md) - Parent plan
- [1.3. Configuration Overview](./1.3-DONE-configuration-overview.md) - Connection management
