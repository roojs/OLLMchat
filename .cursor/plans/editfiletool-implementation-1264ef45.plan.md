<!-- 1264ef45-b912-431b-b67b-64621029fd92 48525d1c-44e8-4eec-976a-3bdaee692c04 -->
# Edit Mode Refactoring

Refactor the `EditFile` tool into an "Edit Mode" system that works differently from the current implementation.

## Overview

The new system will:

1. Tool only accepts filename and activates "edit mode" for that file
2. While edit mode is active, code blocks with `type:startline:endline` format are automatically captured
3. When chat is done (response.done = true), all captured changes are applied
4. After applying, send a message detailing which file was updated and how many lines it now has

## Implementation Steps

### 1. Restore EditFileChange Class

- Restore `Tools/EditFileChange.vala` from git commit `aa36e4c`
- This class represents a single edit with `start`, `end`, `replacement`, and `old_lines` properties
- Includes methods: `apply_changes()`, `write_changes()`

### 2. Refactor EditFile to EditMode Tool

**File**: `Tools/EditFile.vala`

**Changes**:

- Rename tool from `"edit_file"` to `"edit_mode"`
- Remove `start_line` and `end_line` parameters - only accept `file_path`
- Add `monitoring` flag to track if edit mode is active for a file
- Add `Gee.HashMap<string, Gee.ArrayList<EditFileChange>>` to store changes per file path
- Connect to `stream_content` signal to capture code blocks when monitoring is active
- Connect to `stream_chunk` signal to detect when `response.done = true`
- Modify existing code block handling methods to parse language tags in format `type:startline:endline` (e.g., `python:10:15`)
- Store parsed code blocks as `EditFileChange` objects in the changes map
- When chat is done and changes exist, apply all changes and send message with file details
- If no changes were captured when chat is done, send error message

**Key Methods to Add/Modify**:

- `execute()`: Only request permission and set monitoring flag
- Modify existing code block handling methods to parse `type:startline:endline` format and create EditFileChange
- `on_chat_done()`: Apply all changes when response.done = true, or send error if no changes
- `apply_all_changes()`: Loop through changes and apply them using old EditFile logic, emit signal for each applied change
- `send_changes_done_reply()`: Send message with file name and line count via ChatCall.reply()

### 3. Update Tool Description

**File**: `Tools/EditFile.vala`

Update `description` property to:

- Explain that this tool turns on edit mode for a file
- Explain that code blocks after edit mode is turned on will be applied to the file
- Explain code block format: `type:startline:endline` (e.g., `python:10:15`)
- Explain that to apply changes, just end the chat (send chat done signal)

Update `parameter_description` to only mention `file_path` parameter.

### 4. Update Code Assistant Summary

**File**: `resources/ollmchat-agents/code-assistant/making_code_changes.md`

Update to explain:

- Code edits should be done using the edit mode tool
- Code is never sent directly to a tool
- The edit mode tool is only used to turn on edit mode
- After edit mode is active, code blocks with `type:startline:endline` format are automatically captured

### 5. Code Block Parsing Logic

Modify existing code block handling methods to parse markdown code block language tags:

- Format: `type:startline:endline` (e.g., `python:10:15`, `vala:1:5`)
- Extract: file type (optional, can be ignored), start line, end line
- When code block closes, create `EditFileChange` with:
- `start` = parsed start line
- `end` = parsed end line  
- `replacement` = code block content
- Store in changes map but do not emit signal yet (signal emitted when change is applied)

### 6. Chat Done Detection

Connect to `client.stream_chunk` signal and check `response.done`:

- When `response.done = true` and monitoring is active
- Check if there are any changes stored
- If yes, apply all changes using the old EditFile logic
- After applying, send message with file name and line count (e.g., "File 'path/to/file.vala' has been updated. It now has 150 lines.")
- If no changes were captured, send error message: "There was a problem applying the changes."
- Clear monitoring flag and changes

### 7. Permission Handling

- Request single WRITE permission when edit mode is activated (in `execute()`)
- No two-step READ/WRITE flow needed - keep current single permission approach
- Store permission state so changes can be applied later
- If permission denied, return error and don't activate monitoring

### 8. Change Tracking Signals

- Add signal: `public signal void change_done(string file_path, EditFileChange change)`
- Emit this signal each time a change is actually applied to the file (in `apply_all_changes()`)
- This allows UI components to track and preview changes as they are applied (non-blocking)
- Signal should include file path and the EditFileChange object with its range and content
- UI can offer a preview of changes without blocking the editing process
- After all editing has completed, user is free to review the changes

## Files to Modify

1. `Tools/EditFile.vala` - Complete refactor
2. `Tools/EditFileChange.vala` - Restore from git history
3. `resources/ollmchat-agents/code-assistant/making_code_changes.md` - Update documentation

## Key Implementation Details

- Use `Gee.HashMap<string, Gee.ArrayList<EditFileChange>>` to track changes per file
- Parse code block language tag: split on `:` to get `[type, start, end]`
- Reuse old `apply_edits()` logic from git commit `aa36e4c`
- Use `ChatCall.reply()` or similar to send message with file name and line count after applying changes
- Monitor `stream_content` signal only when `monitoring` flag is true for that file
- Modify existing code block handling methods rather than creating new `process_code_block()` method
- Emit `change_done` signal when each change is actually applied to the file (not when captured)

### To-dos

- [ ] Create Tools/EditFileTool.vala with class structure, properties, and constructor following ReadFileTool pattern
- [ ] Implement parameter_description property with @param format for file_path and edits array
- [ ] Implement prepare() method to parse file_path, count edits, build permission question, and set permission properties
- [ ] Implement parsing of edits array from Json.Object parameters (manually parse since readParams only handles simple types)
- [ ] Implement edit validation: check ranges are valid, edits are sorted, and edits are non-overlapping
- [ ] Implement file reading logic: normalize path, validate file exists, read entire file into memory
- [ ] Implement edit application logic: apply edits in reverse order, handle insertions/replacements, preserve newlines
- [ ] Implement file writing: write modified content back to file, send status message via client.tool_message()
- [ ] Add 'Tools/EditFileTool.vala' to meson.build sources list