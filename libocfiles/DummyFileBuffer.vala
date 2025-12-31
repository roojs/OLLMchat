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
	 * In-memory buffer implementation for non-GTK contexts (tools, CLI).
	 * 
	 * Uses in-memory string[] array for line cache. No GTK dependencies.
	 * Always reads from disk (no timestamp checking). No cursor/selection support
	 * (returns defaults). sync_to_file() is not supported (throws IOError.NOT_SUPPORTED).
	 * 
	 * == When to Use ==
	 * 
	 * Use DummyFileBuffer when:
	 * 
	 *  * Working in non-GUI context (CLI tools, background processing)
	 *  * No GTK dependencies available
	 *  * Simple file read/write operations
	 *  * Line range extraction
	 *  * Batch file processing
	 */
	public class DummyFileBuffer : Object, FileBuffer
	{
		/**
		 * Reference to the file this buffer represents.
		 */
		public File file { get; set; }
		
		/**
		 * Cached lines array.
		 */
		private string[]? lines = null;
		
		/**
		 * Constructor.
		 * 
		 * @param file The file this buffer represents
		 */
		public DummyFileBuffer(File file)
		{
			this.file = file;
		}
		
		/**
		 * Read file contents asynchronously.
		 * 
		 * Always reads from disk and updates cache. Unlike GtkSourceFileBuffer,
		 * does not check file modification time - always reads fresh from disk.
		 * 
		 * == Process ==
		 * 
		 *  1. Reads file from disk using read_async_real()
		 *  2. Splits contents into lines array cache
		 *  3. Sets is_loaded = true
		 *  4. Returns file contents
		 * 
		 * @return File contents as string
		 * @throws Error if file cannot be read
		 */
		public async string read_async() throws Error
		{
			var contents = yield read_async_real();
			this.lines = contents.split("\n");
			return contents;
		}
		
		/**
		 * Get text from buffer, optionally limited to a line range.
		 * 
		 * @param start_line Starting line number (0-based, inclusive)
		 * @param end_line Ending line number (0-based, inclusive), or -1 for all lines
		 * @return The buffer text, or empty string if not available
		 */
		public string get_text(int start_line = 0, int end_line = -1)
		{
			// Ensure cache is loaded
			if (this.lines == null) {
				try {
					// Load synchronously for get_text (caller should use read_async first)
					var file_obj = GLib.File.new_for_path(this.file.path);
					if (!file_obj.query_exists()) {
						return "";
					}
					
					string contents;
					GLib.FileUtils.get_contents(this.file.path, out contents);
					this.lines = contents.split("\n");
				} catch (GLib.Error e) {
					GLib.debug("DummyFileBuffer.get_text: Failed to read file %s: %s", this.file.path, e.message);
					return "";
				}
			}
			
			// Handle line range
			start_line = start_line < 0 ? 0 : start_line;
			end_line = end_line == -1 ? this.lines.length - 1 : (end_line >= this.lines.length ? this.lines.length - 1 : end_line);
			
			if (start_line > end_line) {
				return "";
			}
			
			// Extract lines and join
			return string.joinv("\n", this.lines[start_line:end_line+1]);
		}
		
		/**
		 * Get the total number of lines in the buffer.
		 * 
		 * @return Line count, or 0 if not available
		 */
		public int get_line_count()
		{
			if (this.lines == null) {
				// Try to load cache
				try {
					var file_obj = GLib.File.new_for_path(this.file.path);
					if (!file_obj.query_exists()) {
						return 0;
					}
					
					string contents;
					GLib.FileUtils.get_contents(this.file.path, out contents);
					this.lines = contents.split("\n");
				} catch (GLib.Error e) {
					return 0;
				}
			}
			
			return this.lines.length;
		}
		
		/**
		 * Get the content of a specific line.
		 * 
		 * @param line Line number (0-based)
		 * @return Line content, or empty string if not available
		 */
		public string get_line(int line)
		{
			if (this.lines == null) {
				// Try to load cache
				try {
					var file_obj = GLib.File.new_for_path(this.file.path);
					if (!file_obj.query_exists()) {
						return "";
					}
					
					string contents;
					GLib.FileUtils.get_contents(this.file.path, out contents);
					this.lines = contents.split("\n");
				} catch (GLib.Error e) {
					return "";
				}
			}
			
			if (line < 0 || line >= this.lines.length) {
				return "";
			}
			
			return this.lines[line];
		}
		
		/**
		 * Get the current cursor position.
		 * 
		 * Dummy buffers don't track cursor position, so returns 0,0.
		 * 
		 * @param line Output parameter for cursor line number
		 * @param offset Output parameter for cursor character offset
		 */
		public void get_cursor(out int line, out int offset)
		{
			line = 0;
			offset = 0;
		}
		
		/**
		 * Get the currently selected text and cursor position.
		 * 
		 * Dummy buffers don't support selection, so returns empty string.
		 * 
		 * @param cursor_line Output parameter for cursor line number
		 * @param cursor_offset Output parameter for cursor character offset
		 * @return Selected text, or empty string if nothing is selected
		 */
		public string get_selection(out int cursor_line, out int cursor_offset)
		{
			cursor_line = 0;
			cursor_offset = 0;
			return "";
		}
		
		/**
		 * Whether the buffer has been loaded with file content.
		 * 
		 * Returns true if the buffer has been loaded from the file,
		 * false if it needs to be loaded.
		 */
		public bool is_loaded { get; set; default = false; }
		
		/**
		 * Whether the buffer has unsaved modifications.
		 * 
		 * Dummy buffers don't track modification state, so always returns false.
		 */
		public bool is_modified { get; set; default = false; }
		
		/**
		 * Get the timestamp when the buffer was last read from disk.
		 * 
		 * Dummy buffers don't track this, so always returns 0.
		 */
		public int64 last_read_timestamp { get; set; default = 0; }
		
		/**
		 * Sync buffer contents to file on disk.
		 * 
		 * Not supported for DummyFileBuffer - this method is only for GTK SourceView
		 * buffers where the buffer contents may have been modified via GTK operations.
		 * 
		 * For DummyFileBuffer, use write() instead to update buffer and write to file.
		 * 
		 * @throws Error Always throws IOError.NOT_SUPPORTED
		 */
		public async void sync_to_file() throws Error
		{
			throw new GLib.IOError.NOT_SUPPORTED("sync_to_file() is only supported for GtkSourceFileBuffer, not DummyFileBuffer. Use write() instead.");
		}
		
		/**
		 * Write contents to buffer and file.
		 * 
		 * Updates buffer contents and writes to file on disk.
		 * For files in database, creates backup before writing.
		 * 
		 * @param contents Contents to write
		 * @throws Error if file cannot be written
		 */
		public async void write(string contents) throws Error
		{
			// Update cache
			this.lines = contents.split("\n");
			
			// Write to file (backup, write, update metadata)
			yield this.write_real(contents);
		}
		
		/**
		 * Apply multiple edits to the buffer efficiently using in-memory lines array.
		 * 
		 * Applies edits in reverse order (from end to start) to preserve line numbers.
		 * Works with in-memory lines array for efficient manipulation.
		 * 
		 * == Process ==
		 * 
		 *  1. Ensure buffer is loaded (calls read_async() if needed)
		 *  2. Apply changes in reverse order (from end to start) to preserve line numbers
		 *  3. For each change:
		 *     * Convert 1-based (inclusive start, exclusive end) to 0-based array indices
		 *     * Validate range (insertion vs edit)
		 *     * Build new lines array using array slicing
		 *  4. Join lines back into content string
		 *  5. Write to file (creates backup, writes, updates metadata)
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
		 * @param changes List of FileChange objects to apply (must be sorted descending by start)
		 * @throws Error if edits cannot be applied
		 */
		public async void apply_edits(Gee.ArrayList<FileChange> changes) throws Error
		{
			// Ensure buffer is loaded
			if (this.lines == null) {
				yield this.read_async();
			}
			
			// Apply changes in reverse order (from end to start) to preserve line numbers
			foreach (var change in changes) {
				// Convert 1-based (inclusive start, exclusive end) to 0-based array indices
				int start_idx = change.start - 1;
				int end_idx = change.end - 1;
				
				// Validate range
				bool is_insertion = (change.start == change.end);
				if (start_idx < 0 || end_idx < start_idx) {
					throw new GLib.IOError.INVALID_ARGUMENT(
						"Invalid line range: start=" + change.start.to_string() + 
						", end=" + change.end.to_string() + 
						" (file has " + this.lines.length.to_string() + " lines)");
				}
				// For insertions, allow start_idx == lines.length (insert at end)
				// For edits, start_idx must be < lines.length
				if (!is_insertion && start_idx >= this.lines.length) {
					throw new GLib.IOError.INVALID_ARGUMENT(
						"Invalid line range: start=" + change.start.to_string() + 
						", end=" + change.end.to_string() + 
						" (file has " + this.lines.length.to_string() + " lines)");
				}
				if (is_insertion && start_idx > this.lines.length) {
					throw new GLib.IOError.INVALID_ARGUMENT(
						"Invalid line range: start=" + change.start.to_string() + 
						", end=" + change.end.to_string() + 
						" (file has " + this.lines.length.to_string() + " lines)");
				}
				
				// Get array slices using array slicing syntax
				string[] lines_before = this.lines[0:start_idx];
				string[] replacement_lines = change.replacement.split("\n");
				string[] lines_after = this.lines[end_idx:this.lines.length];
				
				// Build new lines array efficiently using GLib.Array
				var array = new GLib.Array<string>(false, true, sizeof(string));
				array.append_vals(lines_before, lines_before.length);
				array.append_vals(replacement_lines, replacement_lines.length);
				array.append_vals(lines_after, lines_after.length);
				
				// Take ownership to avoid array copying
				this.lines = (owned) array.data;
			}
			
			// Join lines back into content string
			var new_content = string.joinv("\n", this.lines);
			
			// Write to file (backup, write, update metadata)
			yield this.write_real(new_content);
		}
	}
}

