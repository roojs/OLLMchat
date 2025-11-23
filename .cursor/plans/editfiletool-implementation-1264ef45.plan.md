<!-- 1264ef45-b912-431b-b67b-64621029fd92 48525d1c-44e8-4eec-976a-3bdaee692c04 -->
# EditFileTool Implementation Plan

## Overview

Create `EditFileTool.vala` in the `Tools/` directory following the same pattern as `ReadFileTool.vala`. The tool will apply a list of edits (each with a range and replacement text) to a file, with validation to ensure edits are non-overlapping and sorted.

## Files to Create/Modify

### 1. Create `Tools/EditFileTool.vala`

- Extend `Ollama.Tool` base class
- Implement required abstract properties: `name`, `description`, `parameter_description`
- Implement `prepare()` method for permission handling
- Implement `execute_tool()` method for applying edits

### 2. Update `meson.build`

- Add `'Tools/EditFileTool.vala'` to the sources list (after ReadFileTool.vala)

## Implementation Details

### Tool Structure

- **Name**: `"edit_file"`
- **Description**: From the JSON schema in needed_tools.md (lines 337)
- **Parameters**:
- `file_path` (string, required): Path to file to edit
- `edits` (array of objects, required): List of edits, each with:
- `range` (array of 2 integers): [start, end] where start is inclusive, end is exclusive (1-based)
- `replacement` (string): Replacement text

### Parameter Description Format

Use the `@param` format for `parameter_description`:

- `@param file_path {string} [required] The path to the file to edit.`
- `@param edits {array} [required] List of edits to apply. Each edit has 'range' [start, end] and 'replacement' text.`

### Key Implementation Requirements

1. **Parameter Parsing**:

- `file_path` can use `readParams()` (simple parameter)
- `edits` must be manually parsed from `Json.Object` since it's an array (readParams only handles simple types)
- Parse `edits` as `Json.Array` and extract each edit object

2. **Edit Validation** (in `execute_tool()`):

- Validate all edits have valid ranges (start >= 1, end > start, end <= file_length+1)
- Validate edits are sorted in ascending order by start line
- Validate edits are non-overlapping (end of edit[i] <= start of edit[i+1])
- Throw appropriate errors if validation fails

3. **File Reading**:

- Read entire file into memory (as array of lines or single string)
- Use `normalize_file_path()` helper from base class
- Validate file exists and is regular file

4. **Edit Application**:

- Apply edits in reverse order (from end to start) to avoid line number shifting issues
- For each edit with range [start, end]:
- If range is [n, n]: Insert replacement before line n
- If range is [n, n+1]: Replace line n with replacement
- If range is [n, m] where m > n+1: Replace lines n through m-1 with replacement
- Handle newlines in replacement text correctly

5. **Two-Step Permission Handling**:

**Important**: If we don't have READ permission, we need two permission requests:

1. First: Request READ permission to read the file and generate the diff
2. Second: Request WRITE permission showing the generated diff

**Implementation Approach**:

- Override `execute()` method in `EditFileTool` (instead of relying on base class `execute()`)
- Step 1 - READ Permission:
- Check if we have READ permission for the file
- If not, request READ permission with question: `"Read file 'path' to preview changes?"`
- If denied, abort with error
- If granted, read the file (streaming) and generate diff preview
- Step 2 - WRITE Permission:
- Generate unified diff from file content and edits
- Request WRITE permission with question: `"Edit file 'path' with N edits?"` and pass diff content
- If denied, abort with error
- If granted, proceed to `execute_tool()`
- If we already have READ permission (from storage), skip step 1 and go directly to step 2

**Alternative**: Handle in `prepare()` by checking permission storage first, but this requires async operations which `prepare()` doesn't support. Overriding `execute()` is cleaner.

**Note**: The base class `execute()` method calls `prepare()` then checks permission. We'll override it to handle the two-step flow.

6. **Status Messages**:

- Use `this.client.tool_message()` to send status updates
- Example: `"Edited file path/to/file.vala (3 edits)"`

7. **Error Handling**:

- Throw `GLib.IOError` for file I/O errors
- Throw `GLib.IOError.INVALID_ARGUMENT` for validation errors
- Errors will be caught by base class and formatted as `"ERROR: ..."`

### Code Structure Reference

Follow the pattern from `ReadFileTool.vala`:

- Constructor takes `Ollama.Client client` and calls `base(client)`
- `prepare()` validates parameters and builds permission question
- `execute_tool()` performs the actual file editing operation
- Use helper methods: `normalize_file_path()`, `readParams()` (for simple params)

### Signal Implementation

Add two signals to `EditFileTool` to allow other tools/components to intercept and potentially block file changes:

1. **`before_change` signal**:

- Signature: `public signal bool before_change(string file_path, Json.Array edits)`
- Emitted before applying edits to the file (after validation, before reading/applying edits)
- Handlers can return `false` to block the change
- If any handler returns `false`, the edit operation is aborted with `GLib.IOError.PERMISSION_DENIED`
- If all handlers return `true` (or no handlers), proceed with edit

2. **`after_change` signal**:

- Signature: `public signal void after_change(string file_path, Json.Array edits)`
- Emitted after successfully applying edits and writing the file
- Notification-only signal (no return value)

**Signal Usage in execute_tool()**:

- Emit `before_change` after validation but before reading/applying edits
- Check return value: if any handler returned `false`, throw `GLib.IOError.PERMISSION_DENIED`
- Emit `after_change` after successful file write

**Note**: Update error handling section to include `GLib.IOError.PERMISSION_DENIED` for signal-blocked operations.

### Diff Display in Permission Widget

Add ability to show file diffs in the permission approval widget using SourceView:

1. **ChatWidget Changes**:

- Add property: `public bool show_diffs { get; set; default = false; }`
- Pass this property to `ChatPermission` widget (or check it when requesting permission)

2. **ChatPermission Widget Changes** (`UI/ChatPermission.vala`):

- Add optional `GtkSource.View?` widget for displaying diffs
- Add `GtkSource.Buffer` for diff content
- Position SourceView between `question_label` and `button_box` in the container
- Update `request()` method signature to accept optional diff content: `public async PermissionResponse request(string question, string? diff_content = null)`
- When `diff_content` is provided and non-empty:
- Show SourceView widget
- Set diff content in SourceView buffer
- Configure SourceView: read-only, syntax highlighting (unified diff format), reasonable height
- When `diff_content` is null or empty:
- Hide SourceView widget
- Use `GtkSource.View` with `GtkSource.Buffer` (similar to how ChatView creates SourceView for code blocks)

3. **EditFileTool Integration**:

- In `prepare()` method, generate diff preview before requesting permission
- Read the file (or affected sections) to generate before/after diff
- Format as unified diff (or similar readable format)
- Pass diff content to permission request via `ChatPermission.ChatView.request_user()`
- Update `ChatPermission.ChatView.request_user()` to extract diff from tool and pass to widget

4. **Diff Generation**:

- Read file sections that will be edited (streaming approach)
- Generate unified diff format showing:
- Lines being removed (with `-` prefix)
- Lines being added (with `+` prefix)
- Context lines around changes
- Format: Unified diff format or simple before/after view

**Files to Modify**:

- `UI/ChatWidget.vala` - Add `show_diffs` property
- `UI/ChatPermission.vala` - Add SourceView for diff display, update `request()` method
- `ChatPermission/ChatView.vala` - Update `request_user()` to extract and pass diff content
- `Tools/EditFileTool.vala` - Generate diff preview in `prepare()` method

### Memory-Efficient Implementation (Streaming Approach)

**Important**: Do NOT load the entire file into memory. Use a streaming line-by-line approach:

1. **First Pass - Validation**:

- Read file line by line using `DataInputStream` (like ReadFileTool does)
- Count total lines to validate edit ranges
- Close file after counting

2. **Second Pass - Apply Edits**:

- Open input file for reading (line by line)
- Open temporary file for writing (or use `StringBuilder` if file is small)
- Track current line number and current edit index
- For each line:
- If before edit range: write line as-is
- If at start of edit: write replacement, skip to end of range
- If within edit range: skip (already handled)
- If after all edits: write line as-is
- Replace original file with temporary file after successful write

3. **Benefits**:

- Memory usage is O(1) regardless of file size (only current line in memory)
- Works efficiently for very large files
- Follows same pattern as ReadFileTool for consistency

### Testing Considerations

- Test with single edit
- Test with multiple non-overlapping edits
- Test with insertion ([n, n] range)
- Test with line replacement ([n, n+1] range)
- Test with multi-line replacement ([n, m] where m > n+1)
- Test validation: overlapping edits, unsorted edits, invalid ranges
- Test permission denial handling
- Test `before_change` signal blocking (handler returns false) - should abort with PERMISSION_DENIED error
- Test `before_change` signal allowing (handler returns true or no handlers) - should proceed normally
- Test `after_change` signal emission after successful edit
- Test with large files to verify memory efficiency (streaming approach)

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