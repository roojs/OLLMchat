# Buffer System Architecture

## Overview

The buffer system provides a unified interface for accessing file contents in OLLMchat, whether in GUI contexts (using GTK SourceView buffers) or non-GUI contexts (using in-memory buffers). This architecture ensures consistent file access patterns across the application while maintaining separation between GUI and non-GUI code.

## Core Components

### FileBuffer Interface

The `FileBuffer` interface (`libocfiles/FileBuffer.vala`) defines the contract for all buffer implementations:

```vala
public interface FileBuffer : Object {
    public abstract File file { get; set; }
    public abstract async string read_async() throws Error;
    public abstract string get_text(int start_line = 0, int end_line = -1);
    public abstract int get_line_count();
    public abstract string get_line(int line);
    public abstract void get_cursor(out int line, out int offset);
    public abstract string get_selection(out int cursor_line, out int cursor_offset);
    public abstract bool is_loaded { get; set; }
    public abstract async void write(string contents) throws Error;
    public abstract async void sync_to_file() throws Error;
    public abstract async void apply_edits(Gee.ArrayList<FileChange> changes) throws Error;
}
```

### Buffer Implementations

#### GtkSourceFileBuffer

**Location**: `liboccoder/GtkSourceFileBuffer.vala`

**Purpose**: GTK SourceView buffer implementation for GUI contexts.

**Features**:
- Extends `GtkSource.Buffer` directly
- Provides syntax highlighting via GtkSource.Language
- Tracks file modification time and auto-reloads if file changed on disk
- Supports cursor position and text selection
- Integrates with GTK SourceView widgets

**Read Behavior**:
- Tracks `last_read_timestamp` (Unix timestamp)
- On `read_async()`, compares file modification time vs `last_read_timestamp`
- If file was modified since last read, reloads buffer from disk
- Updates `last_read_timestamp` after successful read
- Returns current buffer contents

**Write Behavior**:
- Updates `GtkSource.Buffer.text` with new contents
- Creates backup if file is in database (id > 0)
- Writes to file on disk asynchronously
- Updates file metadata (last_modified, last_viewed)
- Updates `last_read_timestamp` to match file modification time

**Special Methods**:
- `sync_to_file()`: Syncs current buffer contents to disk (for SourceView auto-save)
- `apply_edits()`: Efficiently applies multiple edits using GTK buffer operations

#### DummyFileBuffer

**Location**: `libocfiles/DummyFileBuffer.vala`

**Purpose**: In-memory buffer implementation for non-GTK contexts (tools, CLI).

**Features**:
- Uses in-memory `string[]` array for line cache
- No GTK dependencies
- Always reads from disk (no timestamp checking)
- No cursor/selection support (returns defaults)

**Read Behavior**:
- Always reads file directly from disk via `read_async_real()`
- Updates lines array cache
- Returns file contents as string

**Write Behavior**:
- Updates lines array cache
- Creates backup if file is in database (id > 0)
- Writes to file on disk asynchronously
- Updates file metadata

**Special Methods**:
- `sync_to_file()`: Not supported (throws `IOError.NOT_SUPPORTED`)
- `apply_edits()`: Efficiently applies multiple edits using array manipulation

## Buffer Storage

Buffers are stored directly on `File` objects via the `buffer` property:

```vala
public class File : FileBase {
    public FileBuffer? buffer { get; set; default = null; }
    // ...
}
```

**Key Points**:
- Each `File` object has at most one buffer instance
- Buffer is created lazily when needed
- Buffer can be `null` if not yet created or after cleanup
- Buffer type depends on `BufferProvider` implementation (GTK vs non-GTK)

## BufferProvider System

### BufferProviderBase

**Location**: `libocfiles/BufferProviderBase.vala`

**Purpose**: Base implementation for non-GTK contexts.

**Methods**:
- `detect_language(File file)`: Detects language from file extension using static map
- `create_buffer(File file)`: Creates `DummyFileBuffer` instance, stores in `file.buffer`

**Buffer Cleanup**:
- Before creating new buffer, performs cleanup of old buffers
- Keeps buffers for:
  - Open files (`file.is_open == true`)
  - Top 10 most recently used files (by `file.last_viewed`)
- Sets `file.buffer = null` for all other files to free memory

### BufferProvider (GTK)

**Location**: `liboccoder/BufferProvider.vala`

**Purpose**: GTK implementation for GUI contexts.

**Methods**:
- `detect_language(File file)`: Uses `GtkSource.LanguageManager` to detect language
- `create_buffer(File file)`: Creates `GtkSourceFileBuffer` instance, stores in `file.buffer`

**Buffer Cleanup**:
- Same cleanup logic as `BufferProviderBase`
- Keeps GTK buffers for open files and top 10 most recent

## When to Use Each Buffer Type

### Use GtkSourceFileBuffer When:
- Working in GUI context (GTK application)
- Need syntax highlighting
- Need cursor position tracking
- Need text selection support
- Working with `SourceView` widgets
- Need auto-reload when file changes on disk

### Use DummyFileBuffer When:
- Working in non-GUI context (CLI tools, background processing)
- No GTK dependencies available
- Simple file read/write operations
- Line range extraction
- Batch file processing

## Buffer Lifecycle

### Creation

1. **Lazy Creation**: Buffers are created on-demand when first accessed
2. **Provider Selection**: `ProjectManager.buffer_provider` determines which provider to use
3. **Cleanup Before Creation**: Old buffers are cleaned up before creating new ones
4. **Storage**: Buffer is stored in `file.buffer` property

**Example**:
```vala
// Buffer is created automatically when needed
if (file.buffer == null) {
    file.manager.buffer_provider.create_buffer(file);
}

// Now file.buffer is available
var contents = yield file.buffer.read_async();
```

### Usage

1. **Read Operations**: Use `file.buffer.read_async()` or `file.buffer.get_text()`
2. **Write Operations**: Use `file.buffer.write()` or `file.buffer.apply_edits()`
3. **Line Access**: Use `file.buffer.get_line()` or `file.buffer.get_line_count()`
4. **Last Viewed Update**: Buffer operations automatically update `file.last_viewed`

### Cleanup

1. **Automatic Cleanup**: Triggered before creating new buffers
2. **Criteria**: Keeps buffers for open files and top 10 most recent
3. **Memory Management**: Setting `file.buffer = null` frees buffer memory
4. **Manual Cleanup**: Can be triggered by calling `create_buffer()` on any file

## Line Range Operations

### Line Numbering

- **Internal (0-based)**: All buffer methods use 0-based line numbers
- **External (1-based)**: File operations and user-facing APIs use 1-based line numbers
- **Conversion**: Tools must convert between 1-based (user input) and 0-based (buffer API)

### get_text() Method

```vala
string get_text(int start_line = 0, int end_line = -1)
```

**Parameters**:
- `start_line`: Starting line (0-based, inclusive)
- `end_line`: Ending line (0-based, inclusive), or -1 for all lines

**Examples**:
```vala
// Get entire file
var all = buffer.get_text();

// Get lines 0-9 (first 10 lines)
var first10 = buffer.get_text(0, 9);

// Get lines 5-14 (convert from 1-based: lines 6-15)
var range = buffer.get_text(5, 14);

// Get single line (line 5, 0-based)
var line5 = buffer.get_line(5);
```

### Line Range Extraction in Tools

When tools receive 1-based line numbers from user input:

```vala
// User provides: start_line=6, end_line=15 (1-based)
// Convert to 0-based for buffer API
int start = start_line - 1;  // 5
int end = end_line - 1;      // 14
var snippet = file.buffer.get_text(start, end);
```

## Read Operations

### read_async()

Reads file contents asynchronously and updates buffer.

**GtkSourceFileBuffer**:
- Checks file modification time
- Reloads from disk if file was modified since last read
- Updates `last_read_timestamp`
- Returns buffer contents

**DummyFileBuffer**:
- Always reads from disk
- Updates lines array cache
- Returns file contents

**Usage**:
```vala
try {
    var contents = yield file.buffer.read_async();
    // Use contents...
} catch (Error e) {
    // Handle error (file not found, permission denied, etc.)
}
```

### get_text() and get_line()

Access buffer contents without reading from disk.

**Important**: Buffer must be loaded first (via `read_async()` or automatic loading).

**GtkSourceFileBuffer**: Uses GTK buffer contents (may be stale if file changed on disk)

**DummyFileBuffer**: Uses cached lines array (may be stale if file changed on disk)

## Write Operations

### write()

Writes contents to buffer and file on disk.

**Process**:
1. Update buffer contents (GTK buffer text or lines array)
2. Create backup if file is in database (id > 0)
3. Write to file on disk asynchronously
4. Update file metadata (last_modified, last_viewed)
5. Save to database
6. Emit `file.changed()` signal

**Backup Creation**:
- Path: `~/.cache/ollmchat/edited/{id}-{date YY-MM-DD}-{basename}`
- Only creates backup if file has `id > 0` (in database)
- Only creates one backup per day (skips if backup exists for today)
- Updates `file.last_approved_copy_path` with backup path

**Usage**:
```vala
try {
    yield file.buffer.write(new_contents);
    // File written and backup created (if needed)
} catch (Error e) {
    // Handle error
}
```

### apply_edits()

Efficiently applies multiple edits to the buffer.

**Process**:
1. Ensure buffer is loaded
2. Apply edits in reverse order (from end to start) to preserve line numbers
3. For GTK buffers: Uses GTK TextBuffer operations
4. For dummy buffers: Uses array manipulation
5. Syncs to file (creates backup, writes, updates metadata)

**FileChange Format**:
- Line numbers are 1-based (inclusive start, exclusive end)
- `start == end` indicates insertion
- `start != end` indicates replacement

**Usage**:
```vala
var changes = new Gee.ArrayList<FileChange>();
changes.add(new FileChange(10, 12, "new line 10\nnew line 11\n"));
changes.add(new FileChange(5, 6, "replacement for line 5\n"));

// Sort descending by start line (required)
changes.sort((a, b) => {
    if (a.start > b.start) return -1;
    if (a.start < b.start) return 1;
    return 0;
});

try {
    yield file.buffer.apply_edits(changes);
} catch (Error e) {
    // Handle error
}
```

### sync_to_file()

Syncs current buffer contents to file (GTK buffers only).

**Purpose**: Used when buffer contents have been modified via GTK operations (user typing, etc.) and need to be saved to disk.

**Process**:
1. Get current buffer contents
2. Create backup if needed
3. Write to file on disk
4. Mark buffer as not modified
5. Update file metadata

**Usage**:
```vala
// For GTK buffers only
if (file.buffer is GtkSourceFileBuffer) {
    yield file.buffer.sync_to_file();
}
```

## File Backup System

### Backup Location

Backups are stored in: `~/.cache/ollmchat/edited/`

### Backup Naming

Format: `{id}-{date YY-MM-DD}-{basename}`

Example: `123-25-01-15-MainWindow.vala`

### Backup Rules

1. **Only for Database Files**: Backups are only created for files with `id > 0` (in database)
2. **One Per Day**: Only one backup is created per file per day
3. **Automatic**: Backups are created automatically before writing
4. **Metadata**: Backup path is stored in `file.last_approved_copy_path`

### Backup Cleanup

Old backups (>3 days) are automatically cleaned up:
- Triggered after backup creation (runs at most once per day)
- Static method: `ProjectManager.cleanup_old_backups()`
- Can also be called manually

## File Class Integration

The `File` class provides convenience methods that delegate to the buffer:

```vala
public class File : FileBase {
    public FileBuffer? buffer { get; set; }
    
    // Convenience methods that use file.buffer
    public string get_contents(int max_lines = 0);
    public int get_line_count();
    public string get_line_content(int line);
    public string get_selected_code();
    public void get_cursor_position(out int line, out int offset);
}
```

**Important**: These methods require `file.buffer` to be non-null. Ensure buffer is created before use:

```vala
if (file.buffer == null) {
    file.manager.buffer_provider.create_buffer(file);
}
var contents = file.get_contents();
```

## Usage Examples

### Reading a File

```vala
// Ensure buffer exists
if (file.buffer == null) {
    file.manager.buffer_provider.create_buffer(file);
}

// Read entire file
var contents = yield file.buffer.read_async();

// Or use convenience method
var contents2 = file.get_contents();
```

### Reading Line Range

```vala
// User provides 1-based line numbers: lines 10-20
int start = 10 - 1;  // Convert to 0-based: 9
int end = 20 - 1;    // Convert to 0-based: 19

// Ensure buffer is loaded
if (file.buffer == null || !file.buffer.is_loaded) {
    yield file.buffer.read_async();
}

// Get line range
var snippet = file.buffer.get_text(start, end);
```

### Writing a File

```vala
// Ensure buffer exists
if (file.buffer == null) {
    file.manager.buffer_provider.create_buffer(file);
}

// Write new contents (creates backup automatically)
yield file.buffer.write(new_contents);
```

### Applying Multiple Edits

```vala
// Ensure buffer exists and is loaded
if (file.buffer == null) {
    file.manager.buffer_provider.create_buffer(file);
}
if (!file.buffer.is_loaded) {
    yield file.buffer.read_async();
}

// Create edits (1-based line numbers)
var changes = new Gee.ArrayList<FileChange>();
changes.add(new FileChange(5, 7, "replacement\nfor\nlines\n"));
changes.add(new FileChange(10, 10, "insertion\nat\nline\n10\n"));

// Sort descending by start line
changes.sort((a, b) => {
    if (a.start > b.start) return -1;
    if (a.start < b.start) return 1;
    return 0;
});

// Apply edits
yield file.buffer.apply_edits(changes);
```

### Working with GTK Buffers

```vala
// Cast to GtkSourceFileBuffer for GTK-specific features
if (file.buffer is GtkSourceFileBuffer) {
    var gtk_buffer = (GtkSourceFileBuffer) file.buffer;
    
    // Access underlying GtkSource.Buffer
    var source_buffer = (GtkSource.Buffer) gtk_buffer;
    
    // Use GTK-specific features
    source_buffer.set_highlight_syntax(true);
    
    // Sync to file (for auto-save)
    yield gtk_buffer.sync_to_file();
}
```

## Best Practices

1. **Always Check for Null**: Check `file.buffer == null` before using buffer methods
2. **Load Before Access**: Ensure buffer is loaded (`is_loaded == true`) before using `get_text()` or `get_line()`
3. **Use read_async() First**: Call `read_async()` before accessing buffer contents to ensure data is current
4. **Handle Errors**: Always wrap buffer operations in try-catch blocks
5. **Convert Line Numbers**: Remember to convert between 1-based (user input) and 0-based (buffer API)
6. **Sort Edits**: When using `apply_edits()`, sort changes descending by start line
7. **Buffer Cleanup**: Don't manually set `file.buffer = null` unless necessary (cleanup is automatic)

## Architecture Benefits

1. **Unified Interface**: Same API for GTK and non-GTK contexts
2. **Type Safety**: No `set_data/get_data` - buffers are properly typed
3. **Separation of Concerns**: GUI code in `liboccoder`, non-GUI code in `libocfiles`
4. **Memory Management**: Automatic cleanup of old buffers
5. **File Tracking**: Automatic `last_viewed` timestamp updates
6. **Backup System**: Automatic backups for database files
7. **Modtime Checking**: GTK buffers auto-reload when files change on disk

## Migration Notes

### From Direct File I/O

**Old**:
```vala
string contents;
FileUtils.get_contents(path, out contents);
```

**New**:
```vala
var file = manager.get_file(path);
if (file.buffer == null) {
    manager.buffer_provider.create_buffer(file);
}
var contents = yield file.buffer.read_async();
```

### From BufferProvider Methods

**Old**:
```vala
var text = buffer_provider.get_buffer_text(file, start, end);
```

**New**:
```vala
if (file.buffer == null) {
    buffer_provider.create_buffer(file);
}
var text = file.buffer.get_text(start, end);
```

### From File.read_async()

**Old**:
```vala
var contents = yield file.read_async();
```

**New**:
```vala
if (file.buffer == null) {
    file.manager.buffer_provider.create_buffer(file);
}
var contents = yield file.buffer.read_async();
```

