/*
 * Copyright (C) 2025 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMfiles
{
	/**
	 * Interface for file buffer operations.
	 * 
	 * Provides a unified interface for accessing file contents in OLLMchat, whether
	 * in GUI contexts (using GTK SourceView buffers) or non-GUI contexts (using
	 * in-memory buffers). This architecture ensures consistent file access patterns
	 * across the application while maintaining separation between GUI and non-GUI code.
	 * 
	 * The buffer system provides:
	 * 
	 *  * Unified Interface: Same API for GTK and non-GTK contexts
	 *  * Type Safety: No set_data/get_data - buffers are properly typed
	 *  * Separation of Concerns: GUI code in liboccoder, non-GUI code in libocfiles
	 *  * Memory Management: Automatic cleanup of old buffers
	 *  * File Tracking: Automatic last_viewed timestamp updates
	 *  * Backup System: Automatic backups for database files
	 *  * Modtime Checking: GTK buffers auto-reload when files change on disk
	 * 
	 * Buffers are stored directly on File objects via the buffer property. Each
	 * File object has at most one buffer instance, created lazily when needed.
	 * Buffer type depends on BufferProvider implementation (GTK vs non-GTK).
	 * 
	 * == Line Numbering ==
	 * 
	 * All buffer methods use 0-based line numbers internally. External APIs and
	 * user-facing operations use 1-based line numbers. Tools must convert between
	 * 1-based (user input) and 0-based (buffer API).
	 * 
	 * Example:
	 * {{{
	 * // User provides: start_line=6, end_line=15 (1-based)
	 * // Convert to 0-based for buffer API
	 * int start = start_line - 1;  // 5
	 * int end = end_line - 1;      // 14
	 * var snippet = file.buffer.get_text(start, end);
	 * }}}
	 */
	public interface FileBuffer : Object
	{
		/**
		 * Reference to the file this buffer represents.
		 */
		public abstract File file { get; set; }
		
		/**
		 * Read file contents asynchronously and update buffer.
		 * 
		 * Reads file contents asynchronously and updates buffer. For GTK buffers,
		 * checks file modification time and reloads from disk if file was modified
		 * since last read. For dummy buffers, always reads from disk.
		 * 
		 * == GtkSourceFileBuffer Behavior ==
		 * 
		 *  * Tracks last_read_timestamp (Unix timestamp)
		 *  * On read_async(), compares file modification time vs last_read_timestamp
		 *  * If file was modified since last read, reloads buffer from disk
		 *  * Updates last_read_timestamp after successful read
		 *  * Returns current buffer contents
		 * 
		 * == DummyFileBuffer Behavior ==
		 * 
		 *  * Always reads from disk
		 *  * Updates lines array cache
		 *  * Returns file contents
		 * 
		 * Usage:
		 * {{{
		 * try {
		 *     var contents = yield file.buffer.read_async();
		 *     // Use contents...
		 * } catch (Error e) {
		 *     // Handle error (file not found, permission denied, etc.)
		 * }
		 * }}}
		 * 
		 * @return File contents as string
		 * @throws Error if file cannot be read
		 */
		public abstract async string read_async() throws Error;
		
		/**
		 * Internal method: Read file from disk and update last_viewed timestamp.
		 * 
		 * Shared implementation for reading file contents. Updates file.last_viewed.
		 * 
		 * @return File contents as string
		 * @throws Error if file cannot be read
		 */
		protected async string read_async_real() throws Error
		{
			var file_obj = GLib.File.new_for_path(this.file.path);
			if (!file_obj.query_exists()) {
				throw new GLib.FileError.NOENT("File not found: " + this.file.path);
			}
			
			uint8[] data;
			string etag;
			yield file_obj.load_contents_async(null, out data, out etag);
			
			// Update last_viewed timestamp
			this.file.last_viewed = new GLib.DateTime.now_local().to_unix();
			
			return (string)data;
		}
		
		/**
		 * Get text from buffer, optionally limited to a line range.
		 * 
		 * Access buffer contents without reading from disk. Buffer must be loaded
		 * first (via read_async() or automatic loading).
		 * 
		 * == Important ==
		 * 
		 * Buffer must be loaded first. For GTK buffers, uses GTK buffer contents
		 * (may be stale if file changed on disk). For dummy buffers, uses cached
		 * lines array (may be stale if file changed on disk).
		 * 
		 * == Line Numbering ==
		 * 
		 * All parameters use 0-based line numbers (internal format).
		 * 
		 * Examples:
		 * {{{
		 * // Get entire file
		 * var all = buffer.get_text();
		 * 
		 * // Get lines 0-9 (first 10 lines)
		 * var first10 = buffer.get_text(0, 9);
		 * 
		 * // Get lines 5-14 (convert from 1-based: lines 6-15)
		 * var range = buffer.get_text(5, 14);
		 * 
		 * // Get single line (line 5, 0-based)
		 * var line5 = buffer.get_line(5);
		 * }}}
		 * 
		 * @param start_line Starting line number (0-based, inclusive)
		 * @param end_line Ending line number (0-based, inclusive), or -1 for all lines
		 * @return The buffer text, or empty string if not available
		 */
		public abstract string get_text(int start_line = 0, int end_line = -1);
		
		/**
		 * Get the total number of lines in the buffer.
		 * 
		 * @return Line count, or 0 if not available
		 */
		public abstract int get_line_count();
		
		/**
		 * Get the content of a specific line.
		 * 
		 * @param line Line number (0-based)
		 * @return Line content, or empty string if not available
		 */
		public abstract string get_line(int line);
		
		/**
		 * Get the current cursor position.
		 * 
		 * @param line Output parameter for cursor line number
		 * @param offset Output parameter for cursor character offset
		 */
		public abstract void get_cursor(out int line, out int offset);
		
		/**
		 * Get the currently selected text and cursor position.
		 * 
		 * @param cursor_line Output parameter for cursor line number
		 * @param cursor_offset Output parameter for cursor character offset
		 * @return Selected text, or empty string if nothing is selected
		 */
		public abstract string get_selection(out int cursor_line, out int cursor_offset);
		
		/**
		 * Whether the buffer has been loaded with file content.
		 * 
		 * Returns true if the buffer has been loaded from the file,
		 * false if it needs to be loaded.
		 */
		public abstract bool is_loaded { get; set; }
		
		/**
		 * Whether the buffer has unsaved modifications.
		 * 
		 * Returns true if the buffer content has been modified since it was last
		 * loaded or saved, false otherwise.
		 * 
		 * For GTK buffers, this tracks user edits. For dummy buffers, this always
		 * returns false (dummy buffers don't track modification state).
		 */
		public abstract bool is_modified { get; set; }
		
		/**
		 * Get the timestamp when the buffer was last read from disk.
		 * 
		 * Returns the Unix timestamp of when the buffer was last successfully
		 * read from the file on disk. This is used to detect if the file has
		 * been modified externally since the buffer was loaded.
		 * 
		 * Returns 0 if the buffer has never been read or if the timestamp
		 * is not available.
		 */
		public abstract int64 last_read_timestamp { get; set; }
		
		/**
		 * Write contents to buffer and file on disk.
		 * 
		 * Updates buffer contents and writes to file on disk. For files in database,
		 * creates backup before writing.
		 * 
		 * == Process ==
		 * 
		 *  1. Update buffer contents (GTK buffer text or lines array)
		 *  2. Create backup if file is in database (id > 0)
		 *  3. Write to file on disk asynchronously
		 *  4. Update file metadata (last_modified, last_viewed)
		 *  5. Save to database
		 *  6. Emit file.changed() signal
		 * 
		 * == Backup Creation ==
		 * 
		 *  * Path: ~/.cache/ollmchat/edited/{id}-{date YY-MM-DD}-{basename}
		 *  * Only creates backup if file has id > 0 (in database)
		 *  * Only creates one backup per day (skips if backup exists for today)
		 *  * Updates file.last_approved_copy_path with backup path
		 * 
		 * Usage:
		 * {{{
		 * try {
		 *     yield file.buffer.write(new_contents);
		 *     // File written and backup created (if needed)
		 * } catch (Error e) {
		 *     // Handle error
		 * }
		 * }}}
		 * 
		 * @param contents Contents to write
		 * @throws Error if file cannot be written
		 */
		public abstract async void write(string contents) throws Error;
		
		/**
		 * Sync current buffer contents to file (GTK buffers only).
		 * 
		 * Gets the current buffer contents and writes them to the file. Used when
		 * buffer contents have been modified via GTK operations (user typing, etc.)
		 * and need to be saved to disk.
		 * 
		 * == Process ==
		 * 
		 *  1. Get current buffer contents
		 *  2. Create backup if needed
		 *  3. Write to file on disk
		 *  4. Mark buffer as not modified
		 *  5. Update file metadata
		 * 
		 * == Support ==
		 * 
		 *  * GTK buffers: Fully supported
		 *  * Dummy buffers: Not supported - throws IOError.NOT_SUPPORTED
		 * 
		 * Usage:
		 * {{{
		 * // For GTK buffers only
		 * if (file.buffer is GtkSourceFileBuffer) {
		 *     yield file.buffer.sync_to_file();
		 * }
		 * }}}
		 * 
		 * @throws Error if file cannot be written or method is not supported
		 */
		public abstract async void sync_to_file() throws Error;
		
		/**
		 * Efficiently apply multiple edits to the buffer.
		 * 
		 * Applies edits in reverse order (from end to start) to preserve line numbers.
		 * For GTK buffers: Uses GTK TextBuffer operations for efficient chunk editing.
		 * For dummy buffers: Works with in-memory lines array manipulation.
		 * 
		 * == Process ==
		 * 
		 *  1. Ensure buffer is loaded
		 *  2. Apply edits in reverse order (from end to start) to preserve line numbers
		 *  3. For GTK buffers: Uses GTK TextBuffer operations
		 *  4. For dummy buffers: Uses array manipulation
		 *  5. Syncs to file (creates backup, writes, updates metadata)
		 * 
		 * == FileChange Format ==
		 * 
		 *  * Line numbers are 1-based (inclusive start, exclusive end)
		 *  * start == end indicates insertion
		 *  * start != end indicates replacement
		 * 
		 * == Important ==
		 * 
		 * Changes must be sorted descending by start line before calling.
		 * 
		 * Usage:
		 * {{{
		 * var changes = new Gee.ArrayList<FileChange>();
		 * changes.add(new FileChange(10, 12, "new line 10\nnew line 11\n"));
		 * changes.add(new FileChange(5, 6, "replacement for line 5\n"));
		 * 
		 * // Sort descending by start line (required)
		 * changes.sort((a, b) => {
		 *     if (a.start > b.start) return -1;
		 *     if (a.start < b.start) return 1;
		 *     return 0;
		 * });
		 * 
		 * try {
		 *     yield file.buffer.apply_edits(changes);
		 * } catch (Error e) {
		 *     // Handle error
		 * }
		 * }}}
		 * 
		 * @param changes List of FileChange objects to apply (must be sorted descending by start)
		 * @throws Error if edits cannot be applied
		 */
		public abstract async void apply_edits(Gee.ArrayList<FileChange> changes) throws Error;
		
		/**
		 * Clear buffer contents to empty.
		 * 
		 * Used when file is deleted - buffer should reflect empty state.
		 * 
		 * @throws Error if clearing fails
		 */
		public abstract async void clear() throws Error;
		
		/**
		 * Write contents to file on disk (sync buffer to file).
		 * 
		 * Creates backup if needed, writes to disk, and updates file metadata.
		 * This is used when the buffer already has the contents and we just need
		 * to sync it to the file. Unlike write(), this does not update the buffer contents.
		 * 
		 * @param contents Contents to write
		 * @throws Error if file cannot be written
		 */
		public async void write_real(string contents) throws Error
		{
			// Create backup if needed
			yield this.file.create_backup();
			
			// Write to file
			yield this.write_to_disk(contents);
			
			// Update file metadata
			this.update_file_metadata_after_write();
		}
		
		/**
		 * Internal method: Write contents to file on disk.
		 * 
		 * @param contents Contents to write
		 * @throws Error if file cannot be written
		 */
		protected async void write_to_disk(string contents) throws Error
		{
			var dirname = GLib.Path.get_dirname(this.file.path);
			var dir_file = GLib.File.new_for_path(dirname);
			if (!dir_file.query_exists()) {
				dir_file.make_directory_with_parents(null);
			}
			
			var file_obj = GLib.File.new_for_path(this.file.path);
			var output_stream = yield file_obj.replace_async(
				null,
				false,
				GLib.FileCreateFlags.NONE,
				GLib.Priority.DEFAULT,
				null
			);
			
			// Write contents asynchronously
			uint8[] data = contents.data;
			size_t bytes_written;
			yield output_stream.write_all_async(data, GLib.Priority.DEFAULT, null, out bytes_written);
			
			// Close stream asynchronously
			yield output_stream.close_async(GLib.Priority.DEFAULT, null);
		}
		
		/**
		 * Internal method: Update file metadata after writing.
		 * 
		 * Updates last_modified, saves to database, updates last_viewed, and notifies ProjectManager
		 * that file contents have changed (triggers background scanning).
		 */
		protected void update_file_metadata_after_write()
		{
			// Update last_modified from filesystem after writing
			this.file.last_modified = this.file.mtime_on_disk();
			
			// Save to database with sync to disk
			if (this.file.manager.db != null) {
				this.file.saveToDB(this.file.manager.db, null, true);
			}
			
			// Update last_viewed timestamp
			this.file.last_viewed = new GLib.DateTime.now_local().to_unix();
			
			// Notify ProjectManager that file contents have changed (triggers background scanning)
			this.file.manager.on_file_contents_change(this.file);
			
			// Keep file.changed() signal for backward compatibility (though nothing currently listens to it)
			this.file.changed();
		}
	}
}

