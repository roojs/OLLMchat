---
name: Add table parsing support
overview: Add table parsing support to the markdown parser by implementing a handleTable method that processes table content incrementally, similar to how fenced code blocks are handled. The method will track table parsing state, accumulate table content, and handle parsing failures gracefully.
todos:
  - id: add-table-state-vars
    content: Add table state tracking variables to Parser class (table_string, table_state, table_column_count, table_alignments)
    status: pending
  - id: create-table-state-enum
    content: Create TableState enum (NONE, HEADER, ALIGNMENT, ROWS) and TableAlignment enum (LEFT, CENTER, RIGHT)
    status: pending
  - id: implement-handle-table
    content: Implement handleTable method with state machine for parsing header, alignment, and data rows
    status: pending
  - id: integrate-table-handling
    content: Integrate handleTable into main add() loop, similar to fenced code block handling
    status: pending
  - id: add-table-detection
    content: Add table detection in peekBlockHandler to detect lines starting with |
    status: pending
  - id: add-renderer-methods
    content: Add table callback methods to RenderBase (on_table, on_table_end, on_table_remove, on_table_cell, on_table_cell_end)
    status: pending
  - id: update-do-block
    content: Add TABLE case to do_block method to call renderer.on_table
    status: pending
---

# Add Table Support to Markdown Parser

## Overview

Add table parsing support to `Parser.vala` by implementing a `handleTable` method that processes table content incrementally, similar to fenced code blocks. The method will track parsing state, accumulate content, and handle failures gracefully.

## Implementation Details

### 1. Add Table State Tracking Variables

Add to the Parser class (around line 256-260):

- `table_string: string` - Accumulates table content as it's parsed
- `table_state: TableState` enum - Tracks current parsing state (NONE, HEADER, ALIGNMENT, ROWS)
- `table_column_count: int` - Number of columns detected
- `table_alignments: Gee.ArrayList<TableAlignment>` - Column alignments (LEFT, CENTER, RIGHT)

### 2. Create TableState Enum

Add enum definition (around line 25-57, near FormatType):

```vala
private enum TableState {
    NONE,
    HEADER,      // Parsing header row
    ALIGNMENT,   // Parsing alignment row (| --- | --- |)
    ROWS         // Parsing data rows
}
```

### 3. Implement handleTable Method

Create new method `handleTable` (around line 1340, after `peekFencedEnd`):

- **Signature**: `private int handleTable(string chunk, int chunk_pos, bool is_end_of_chunks)`
- **Returns**: Number of characters consumed, or -1 if need more data
- **Behavior**:
  - If `current_block != FormatType.TABLE`, check if line starts with `|` to detect table start
  - If starting new table, set `current_block = FormatType.TABLE`, emit `on_table(start, column_count)`
  - Accumulate content in `table_string`
  - Parse table rows line by line:
    - Header row: Parse cells, count columns, emit cell start/end with alignment
    - Alignment row: Parse `| :--- | :---: | ---: |` to determine alignments
    - Data rows: Parse cells, emit cell start/end, parse cell content with inline formatting
  - On parsing failure:
    - If `on_table(start, 0)` was already called, emit `on_table_end()` and `on_table_remove()`
    - Clear table state variables
    - Set `current_block = FormatType.NONE`
    - Return number of characters NOT eaten (remaining chunk)
  - On success: Return number of characters consumed

### 4. Integrate handleTable into Main Loop

Modify `add()` method (around line 760-831, in the fenced code block handling section):

- Add check after fenced code block handling:
  ```vala
  // If we're in a table block, handle table content
  if (this.current_block == FormatType.TABLE) {
      var table_result = this.handleTable(chunk, chunk_pos, is_end_of_chunks);
      if (table_result == -1) {
          // Need more data
          this.leftover_chunk = chunk.substring(chunk_pos, chunk.length - chunk_pos);
          return;
      }
      if (table_result == 0) {
          // Table parsing failed or table ended
          // handleTable already cleaned up state
          continue;
      }
      // Table consumed characters
      chunk_pos += table_result;
      // Check if still in table after handling
      if (this.current_block == FormatType.TABLE) {
          // Still in table - assume all characters were eaten
          continue;
      }
      // Table ended - continue with normal processing
      continue;
  }
  ```


### 5. Add Table Detection in peekBlockHandler

Modify `peekBlockHandler` (around line 1082-1186):

- Add case for detecting table start when `at_line_start` is true
- Check if line starts with `|` (after optional whitespace)
- If yes, set `current_block = FormatType.TABLE` and call `handleTable`
- Return bytes consumed

### 6. Add Table Renderer Methods

Add to `RenderBase.vala` (around line 70-98):

- `public virtual void on_table(bool is_start, uint column_count) {}`
- `public virtual void on_table_end() {}`
- `public virtual void on_table_remove() {}`
- `public virtual void on_table_cell(bool is_start, uint column, TableAlignment alignment) {}`
- `public virtual void on_table_cell_end() {}`

### 7. Handle Table in do_block

Add case in `do_block` method (around line 1195-1248):

```vala
case FormatType.TABLE:
    this.renderer.on_table(is_start, this.table_column_count);
    break;
```

## Table Parsing Logic

### Table Structure

- Header row: `| Header 1 | Header 2 | Header 3 |`
- Alignment row (optional): `| :--- | :---: | ---: |` (left, center, right)
- Data rows: `| Cell 1 | Cell 2 | Cell 3 |`

### Parsing Steps

1. **Detect table start**: Line starts with `|` (after optional whitespace)
2. **Parse header row**: Split by `|`, trim cells, count columns
3. **Parse alignment row**: Check if next line matches `| [-:]+ |` pattern
4. **Parse data rows**: Continue until line doesn't start with `|`
5. **Cell content**: Use existing `parseFormat` loop for inline formatting within cells

### Error Handling

- If any row has different column count → fail, emit cleanup callbacks
- If alignment row is malformed → treat as data row or fail
- If cell parsing fails → fail entire table
- Always clean up state on failure

## Files to Modify

1. `libocmarkdown/Parser.vala` - Main implementation
2. `libocmarkdown/RenderBase.vala` - Add table callback methods

## Testing Considerations

- Test with various table formats (with/without alignment row)
- Test table parsing failure scenarios
- Test incremental chunk processing
- Test table ending and cleanup