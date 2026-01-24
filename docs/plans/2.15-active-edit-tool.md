# 2.15. Active Edit Tool

## Overview

Create an "active edit tool" that works like EditMode, except it does not require any parameters for tool calling. Instead, it modifies system messages to allow agents to edit files directly in their responses using a special format. Agents can decide to activate or not activate this tool when they start.

## Status

⏳ **NOT STARTED**

## Related Plans

- **2.4** - Edit File and Edit Mode Tool (current line-based implementation)
- **2.1.4** - AST Path EditFile Integration (AST path support for EditMode)
- **2.1.5** - AST Path Comment Support (optional enhancement)

## Purpose

Enable agents to edit files without explicit tool calls by:
- Adding instructions to system messages about the edit format
- Parsing edit directives from agent responses
- Reusing EditMode infrastructure for actual file editing
- Allowing agents to opt-in/opt-out of this capability

## Key Differences from EditMode

| Feature | EditMode | Active Edit Tool |
|---------|----------|------------------|
| Tool Call Required | Yes (with file_path parameter) | No (no parameters) |
| Activation | Explicit tool call | System message modification |
| Edit Format | Code blocks with line numbers/AST paths | Special format in response text |
| Agent Control | Always available | Agent can enable/disable |

## Edit Format

When the active edit tool is enabled, agents can include edits in their responses using this format:

```
---BEGIN---
Edit: {file_path}
ast-path: {ast_path}
action: {replace|remove|append|prepend}
---START---
{code content}
---END---
```

### Format Details

- **---BEGIN---**: Marks the start of an edit directive
- **Edit: {file_path}**: The path to the file to edit (relative to workspace or absolute)
- **ast-path: {ast_path}**: Optional AST path to the code element (e.g., `Namespace-Class-Method`)
- **action**: One of:
  - `replace`: Replace the code element with new content
  - `remove`: Remove the code element (no content needed)
  - `append`: Append content after the code element
  - `prepend`: Prepend content before the code element
- **---START---**: Marks the start of code content
- **{code content}**: The actual code to insert/replace
- **---END---**: Marks the end of the edit directive

### Examples

**Replace a method:**
```
---BEGIN---
Edit: libollmchat/Client.vala
ast-path: OLLMchat-Client-chat
action: replace
---START---
public async Response.Chat chat(string text, GLib.Cancellable? cancellable = null) throws Error
{
    // new implementation
}
---END---
```

**Remove a method:**
```
---BEGIN---
Edit: libollmchat/Client.vala
ast-path: OLLMchat-Client-oldMethod
action: remove
---END---
```

**Append after a method:**
```
---BEGIN---
Edit: libollmchat/Client.vala
ast-path: OLLMchat-Client-chat
action: append
---START---
// Helper method
private void helper() {
    // implementation
}
---END---
```

## Implementation Phases

### Phase 1: Tool Structure and Configuration
- [ ] Create `liboctools/ActiveEdit/Tool.vala` extending `BaseTool`
- [ ] Create `liboctools/ActiveEdit/Request.vala` extending `RequestBase`
- [ ] Add `active_edit_enabled` property to tool config (default: false)
- [ ] Tool should not require any parameters (empty `parameter_description`)
- [ ] Tool should not appear in tool list when serialized (if `active_edit_enabled=false`)

### Phase 2: System Message Modification
- [ ] Add method to check if active edit tool is enabled for an agent
- [ ] Modify `AgentFactory.system_message()` to append active edit instructions when enabled
- [ ] Instructions should explain the edit format and when to use it
- [ ] Instructions should reference AST path support (from 2.1.4) if available
- [ ] Format:
  ```vala
  if (active_edit_tool_enabled) {
      system_content += "\n\n<active_edit>\n" +
          "You can edit files directly in your responses using this format:\n" +
          "---BEGIN---\n" +
          "Edit: {file_path}\n" +
          "ast-path: {optional_ast_path}\n" +
          "action: {replace|remove|append|prepend}\n" +
          "---START---\n" +
          "{code}\n" +
          "---END---\n" +
          "\n</active_edit>";
  }
  ```

### Phase 3: Response Parsing
- [ ] Add response parser to detect edit directives in assistant messages
- [ ] Parse format: look for `---BEGIN---` markers
- [ ] Extract: file_path, ast_path (optional), action, code content
- [ ] Support multiple edit directives in a single response
- [ ] Validate format (required fields, valid actions)
- [ ] Create `ActiveEditRequest` instances for each parsed directive

### Phase 4: Integration with EditMode
- [ ] Reuse `EditMode/Request` infrastructure for actual file editing
- [ ] Convert parsed edit directives to EditMode operations:
  - `action: replace` → EditMode replace operation
  - `action: remove` → EditMode delete operation (empty replacement)
  - `action: append` → EditMode insert after operation
  - `action: prepend` → EditMode insert before operation
- [ ] Reuse AST path resolution from EditMode (if available)
- [ ] Reuse FileChange creation and application logic
- [ ] Share file permission handling

### Phase 5: Agent Activation Control
- [ ] Add `active_edit_enabled` setting to agent configuration
- [ ] Allow agents to enable/disable this tool independently
- [ ] Check tool's `active` property and config's `enabled` property
- [ ] Only modify system messages when tool is both active and enabled
- [ ] Update UI to show active edit tool status

### Phase 6: Error Handling and Validation
- [ ] Validate file paths (must exist or be creatable)
- [ ] Validate AST paths (if provided, must resolve to valid code element)
- [ ] Validate actions (must be one of: replace, remove, append, prepend)
- [ ] Show clear error messages for invalid directives
- [ ] Continue processing other edits if one fails
- [ ] Report success/failure for each edit directive

### Phase 7: UI Integration
- [ ] Show edit directives in UI as they're parsed
- [ ] Display file path, action, and AST path (if provided)
- [ ] Show preview of changes before applying
- [ ] Request permission for file modifications (reuse EditMode permission system)
- [ ] Show success/error messages for each applied edit

### Phase 8: Documentation and Testing
- [ ] Document the edit format in tool description
- [ ] Test all action types (replace, remove, append, prepend)
- [ ] Test with and without AST paths
- [ ] Test multiple edits in single response
- [ ] Test error handling (invalid paths, invalid AST paths, invalid actions)
- [ ] Test agent enable/disable functionality

## Files to Create

### Active Edit Tool
- `liboctools/ActiveEdit/Tool.vala` - Tool class (extends BaseTool)
- `liboctools/ActiveEdit/Request.vala` - Request handler (extends RequestBase)
- `liboctools/ActiveEdit/Parser.vala` - Response parser for edit directives (optional, could be in Request)

## Files to Modify

### System Message Generation
- `liboccoder/AgentFactory.vala` - Add active edit instructions to `system_message()` when enabled

### Agent Configuration
- `libollmchat/Settings/BaseToolConfig.vala` or new config class - Add `active_edit_enabled` property

### Response Processing
- `liboccoder/Agent.vala` or `libollmchat/Agent/Base.vala` - Parse assistant responses for edit directives
- Integration point: After assistant message is received, before sending to UI

### EditMode Integration
- `liboctools/EditMode/Request.vala` - May need to expose some methods for reuse, or create shared base class

## Code Reuse Strategy

Since Active Edit Tool will reuse EditMode infrastructure:

1. **Option A: Shared Base Class**
   - Create `EditBase` class with common functionality
   - `EditMode/Request` and `ActiveEdit/Request` both extend `EditBase`
   - Share: AST path resolution, FileChange creation, file permission handling

2. **Option B: Composition**
   - `ActiveEdit/Request` creates internal `EditMode/Request` instance
   - Delegates actual editing to EditMode
   - Parses format and converts to EditMode calls

3. **Option C: Direct Reuse**
   - `ActiveEdit/Request` directly uses EditMode's private methods
   - Requires making some EditMode methods public or protected
   - Less clean but simpler

**Recommendation**: Start with Option B (composition) for simplicity, refactor to Option A if needed.

## Example Usage Flow

1. **Agent starts with active edit tool enabled:**
   - System message includes active edit format instructions
   - Agent sees instructions and knows it can edit files directly

2. **Agent responds with edit directive:**
   ```
   I'll update the chat method to add error handling.
   
   ---BEGIN---
   Edit: libollmchat/Client.vala
   ast-path: OLLMchat-Client-chat
   action: replace
   ---START---
   public async Response.Chat chat(string text, GLib.Cancellable? cancellable = null) throws Error
   {
       try {
           // existing code with error handling
       } catch (Error e) {
           // handle error
       }
   }
   ---END---
   ```

3. **System parses directive:**
   - Detects `---BEGIN---` marker
   - Extracts file_path, ast_path, action, code
   - Creates ActiveEditRequest

4. **Request processes edit:**
   - Resolves AST path to line range (if provided)
   - Creates FileChange based on action
   - Requests permission if needed
   - Applies change to file

5. **UI shows result:**
   - Displays edit applied successfully
   - Shows file path and action taken

## Error Handling

**Invalid Format:**
- Missing `---BEGIN---` or `---END---` markers
- Missing required fields (Edit:, action:)
- Invalid action value
- Response: Show error message, skip directive

**File Errors:**
- File not found (for replace/remove/append/prepend on existing code)
- Permission denied
- Response: Show error message, skip directive

**AST Path Errors:**
- AST path not found
- AST path ambiguous
- Response: Show error message, skip directive (fall back to line numbers if possible)

**Code Block Errors:**
- Missing `---START---` when action requires content
- Empty code block when action is replace/append/prepend
- Response: Show error message, skip directive

## Future Enhancements

- Support line number ranges as alternative to AST paths
- Support multiple files in single directive
- Support conditional edits (only apply if condition met)
- Support edit templates/variables
- Integration with code review/approval system
