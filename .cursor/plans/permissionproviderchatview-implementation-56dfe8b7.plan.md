<!-- 56dfe8b7-227b-413c-bd88-da762428729d b1890391-d432-43c1-81eb-6f77cac51c23 -->
# ChatPermission ChatView Implementation

## Overview

Reorganize permission provider classes into a new `ChatPermission/` folder at the top level, make the permission request chain async, and create a `ChatView` provider that displays permission requests as interactive widgets in the `ChatView`.

## Key Changes Required

### 1. Reorganize Permission Provider Classes

- Create new folder: `ChatPermission/` (at top level, not under Tools)
- Move `Tools/PermissionProvider.vala` → `ChatPermission/Provider.vala`
    - Rename class from `PermissionProvider` to `Provider`
    - Update namespace to `OLLMchat.ChatPermission`
    - Keep all enums (Operation, PermissionResult, PermissionResponse) in the same file
- Move `Tools/PermissionProviderDummy.vala` → `ChatPermission/Dummy.vala`
    - Rename class from `PermissionProviderDummy` to `Dummy`
    - Update namespace to `OLLMchat.ChatPermission`
    - Update base class reference to `Provider`
- Create new class: `ChatPermission/ChatView.vala`
    - Extends `Provider` (renamed from `PermissionProvider`)
    - Stores reference to `UI.ChatView` instance
    - Implements async `request_user()` method
    - Manages permission widget lifecycle (show/hide)

### 2. Make Permission Request Chain Async

- Change `Provider.request_user()` from synchronous to async
    - Signature: `protected abstract async PermissionResponse request_user(Ollama.Tool tool)`
- Change `Provider.request()` to async
    - Signature: `public async bool request(Ollama.Tool tool)`
    - Update to await `request_user()`
- Update `Tool.execute()` to async and await permission requests
    - Signature: `public async string execute(Json.Object parameters)`
    - Await `permission_provider.request()`
- Update `ChatCall.toolsReply()` to await tool execution
    - Change `tool.execute()` calls to `yield tool.execute()`

### 3. Create Permission Widget UI

- Widget structure:
    - Question text (from `tool.permission_question`)
    - Button row with 5 buttons:
        - "Deny Always" → `DENY_ALWAYS` (red button, tooltip: "Permanently deny this permission")
        - "Deny" → `DENY_SESSION` (red button, tooltip: "Deny for this session only")
        - "Allow" → `ALLOW_SESSION` (green button, tooltip: "Allow for this session only")
        - "Allow Once" → `ALLOW_ONCE` (green button, tooltip: "Allow this one time only")
        - "Allow Always" → `ALLOW_ALWAYS` (green button, tooltip: "Permanently allow this permission")
- Widget styling:
    - Light yellow background (distinct from user messages)
    - Rounded corners (similar to user messages)
    - Green buttons for allow actions, red buttons for deny actions
    - Tooltips on all buttons explaining their behavior
- Widget added to end of ChatView buffer using child anchor (like user messages)

### 4. Async Permission Request Flow

- When `request_user()` is called, show widget and wait for user response
- Use async/await pattern with a `SourceFunc` callback
- When user clicks a button:
    - Set the permission response
    - Hide/remove the widget
    - Resume the async function to return the response

### 5. Integration Points

- Update all references to `Tools.PermissionProvider` to `ChatPermission.Provider`
- Update `Ollama.Client.permission_provider` property type
- Set `ChatPermission.ChatView` on client after `ChatWidget` is created
- In `TestWindow.vala` or wherever `ChatWidget` is instantiated:
    - Create `ChatWidget` first
    - Create `ChatPermission.ChatView` with reference to `chat_widget.chat_view`
    - Set `client.permission_provider = permission_provider_chat_view`

## Files to Modify

1. **ChatPermission/Provider.vala** (moved from `Tools/PermissionProvider.vala`)

      - Rename class to `Provider`
      - Update namespace to `OLLMchat.ChatPermission`
      - Change `request_user()` signature to `protected abstract async PermissionResponse request_user(Ollama.Tool tool)`
      - Change `request()` to `public async bool request(Ollama.Tool tool)`
      - Update `request()` to await `request_user()`

2. **ChatPermission/Dummy.vala** (moved from `Tools/PermissionProviderDummy.vala`)

      - Rename class to `Dummy`
      - Update namespace to `OLLMchat.ChatPermission`
      - Update base class reference to `Provider`
      - Update `request_user()` to async (can remain simple for dummy)

3. **ChatPermission/ChatView.vala** (NEW)

      - Implement async `request_user()` method
      - Create permission widget UI
      - Handle button clicks and async completion
      - Manage widget lifecycle (add/remove from ChatView)

4. **Ollama/Tool/Tool.vala**

      - Change `execute()` to `public async string execute(Json.Object parameters)`
      - Await `permission_provider.request()`

5. **Ollama/Call/ChatCall.vala**

      - Update `toolsReply()` to await `tool.execute()` calls

6. **Ollama/Client.vala**

      - Update `permission_provider` property type from `Tools.PermissionProvider` to `ChatPermission.Provider`

7. **TestWindow.vala** (or wherever ChatWidget is created)

      - Update import/namespace references
      - Create `ChatPermission.ChatView` after `ChatWidget` creation
      - Set it on the client

8. **meson.build**

      - Update source file paths for moved files
      - Add new `ChatPermission/ChatView.vala` file

## Implementation Details

### Permission Widget Structure

```vala
- Gtk.Frame (light yellow background, rounded corners)
 - Gtk.Box (vertical)
  - Gtk.Label (question text)
  - Gtk.Box (horizontal, button row)
   - "Deny Always" Gtk.Button (red, tooltip)
   - "Deny" Gtk.Button (red, tooltip)
   - "Allow" Gtk.Button (green, tooltip)
   - "Allow Once" Gtk.Button (green, tooltip)
   - "Allow Always" Gtk.Button (green, tooltip)
```

### CSS Styling

Add CSS classes for permission widget:

- `.permission-widget` - light yellow background
- `.permission-button-allow` - green styling
- `.permission-button-deny` - red styling

### Async Pattern

Use `SourceFunc` callback pattern:

- Store `SourceFunc` in permission provider
- When button clicked, call `SourceFunc()` to resume async function
- Return the selected `PermissionResponse`

### Widget Management

- Add widget to ChatView using `create_child_anchor()` and `add_child_at_anchor()`
- Track widget reference to remove it after user responds
- Update question text when showing widget (reuse same widget instance)