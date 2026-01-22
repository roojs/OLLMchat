/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
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

namespace OLLMcoder
{
	/**
	 * GTK SourceView buffer implementation for GUI contexts.
	 * 
	 * Extends GtkSource.Buffer directly and provides FileBuffer interface.
	 * Provides syntax highlighting via GtkSource.Language, tracks file modification
	 * time and auto-reloads if file changed on disk, and supports cursor position
	 * and text selection. Integrates with GTK SourceView widgets.
	 * 
	 * == When to Use ==
	 * 
	 * Use GtkSourceFileBuffer when:
	 * 
	 *  * Working in GUI context (GTK application)
	 *  * Need syntax highlighting
	 *  * Need cursor position tracking
	 *  * Need text selection support
	 *  * Working with SourceView widgets
	 *  * Need auto-reload when file changes on disk
	 */
	public class GtkSourceFileBuffer : GtkSource.Buffer, OLLMfiles.FileBuffer
	{
		/**
		 * Reference to the file this buffer represents.
		 */
		public OLLMfiles.File file { get; set; }
		
		/**
		 * Last read timestamp (Unix timestamp).
		 * Used to detect if file was modified on disk since last read.
		 */
		public int64 last_read_timestamp { get; set; default = 0; }
		
		/**
		 * Whether the buffer has unsaved modifications.
		 * 
		 * Returns true if the buffer content has been modified since it was last
		 * loaded or saved, false otherwise.
		 */
		public bool is_modified { 
			get {
				var source_buffer = (GtkSource.Buffer) this;
				return source_buffer.get_modified();
			}
			set {
				var source_buffer = (GtkSource.Buffer) this;
				source_buffer.set_modified(value);
			}
		}
		
		/**
		* Whether the buffer has been loaded with file content.
		* 
		* Returns true if the buffer has been loaded from the file,
		* false if it needs to be loaded.
		*/
		public bool is_loaded { get; set; default = false; }
		
		/**
		* Whether the file uses tabs for indentation.
		*/
		public bool uses_tabs { get; private set; default = true; }
		
		/**
		* Number of spaces per indent level (0 if using tabs).
		*/
		public int indent_size { get; private set; default = 0; }
		
		/**
		* Whether indentation detection has been completed for this buffer.
		*/
		private bool detection_done = false;
					
			/**
		 * Constructor.
		 * 
		 * @param file The file this buffer represents
		 * @param language Optional language for syntax highlighting
		 */
		public GtkSourceFileBuffer(OLLMfiles.File file, GtkSource.Language? language = null)
		{
			if (language != null) {
				this.language = language;
			}
			this.file = file;
		}
		
		/**
		 * Read file contents asynchronously.
		 * 
		 * Checks file modification time and reloads buffer if file was modified
		 * since last read. Updates buffer text and last_read_timestamp.
		 * 
		 * == Behavior ==
		 * 
		 *  * Gets file modification time from filesystem
		 *  * Compares with last_read_timestamp
		 *  * If file was modified (or first read), reloads from disk using read_async_real()
		 *  * Updates buffer text and last_read_timestamp
		 *  * Sets is_loaded = true
		 *  * Returns current buffer contents
		 * 
		 * @return File contents as string
		 * @throws Error if file cannot be read
		 */
		public async string read_async() throws Error
		{
			var file_obj = GLib.File.new_for_path(this.file.path);
			if (!file_obj.query_exists()) {
				throw new GLib.FileError.NOENT("File not found: " + this.file.path);
			}
			
			// Get file modification time
			var file_info = file_obj.query_info(
				GLib.FileAttribute.TIME_MODIFIED,
				GLib.FileQueryInfoFlags.NONE,
				null
			);
			var mod_time = file_info.get_modification_date_time();
			var mod_timestamp = mod_time.to_unix();
			
			// Check if file was modified since last read
			if (this.last_read_timestamp == 0 || mod_timestamp > this.last_read_timestamp) {
				// Reload buffer from disk using shared method
				var contents = yield read_async_real();
				this.text = contents;
				this.last_read_timestamp = mod_timestamp;
				this.is_loaded = true;
				// Reset detection flag when file content changes
				this.detection_done = false;
				// Detect indentation after loading
				this.detect_indentation();
			}
			
			// Return buffer contents
			Gtk.TextIter start, end;
			this.get_bounds(out start, out end);
			return ((Gtk.TextBuffer) this).get_text(start, end, true);
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
			Gtk.TextIter start, end;
			this.get_bounds(out start, out end);
			
			if (end_line >= 0 && end_line >= start_line) {
				// Limit to specified line range
				var line_start = start;
				line_start.forward_lines(start_line);
				var line_end = start;
				if (end_line > start_line) {
					line_end.forward_lines(end_line);
				} else {
					line_end = line_start;
				}
				if (!line_end.ends_line()) {
					line_end.forward_to_line_end();
				}
				return ((Gtk.TextBuffer) this).get_text(line_start, line_end, true);
			}
			
			return ((Gtk.TextBuffer) this).get_text(start, end, true);
		}
		
		/**
		 * Get the total number of lines in the buffer.
		 * 
		 * @return Line count, or 0 if not available
		 */
		public int get_line_count()
		{
			Gtk.TextIter start, end;
			this.get_bounds(out start, out end);
			return end.get_line() + 1;
		}
		
		/**
		 * Get the content of a specific line.
		 * 
		 * @param line Line number (0-based)
		 * @return Line content, or empty string if not available
		 */
		public string get_line(int line)
		{
			Gtk.TextIter iter;
			if (!this.get_iter_at_line(out iter, line)) {
				return "";
			}
			
			var line_end = iter;
			if (!line_end.ends_line()) {
				line_end.forward_to_line_end();
			}
			
			return ((Gtk.TextBuffer) this).get_text(iter, line_end, true);
		}
		
		/**
		 * Get the current cursor position.
		 * 
		 * @param line Output parameter for cursor line number
		 * @param offset Output parameter for cursor character offset
		 */
		public void get_cursor(out int line, out int offset)
		{
			line = 0;
			offset = 0;
			
			Gtk.TextIter cursor;
			this.get_iter_at_mark(out cursor, this.get_insert());
			line = cursor.get_line();
			offset = cursor.get_line_offset();
		}
		
		/**
		 * Get the currently selected text and cursor position.
		 * 
		 * @param cursor_line Output parameter for cursor line number
		 * @param cursor_offset Output parameter for cursor character offset
		 * @return Selected text, or empty string if nothing is selected
		 */
		public string get_selection(out int cursor_line, out int cursor_offset)
		{
			cursor_line = 0;
			cursor_offset = 0;
			
			// Update cursor position from buffer
			Gtk.TextIter cursor;
			this.get_iter_at_mark(out cursor, this.get_insert());
			cursor_line = cursor.get_line();
			cursor_offset = cursor.get_line_offset();
			
			Gtk.TextIter start, end;
			if (!this.get_selection_bounds(out start, out end)) {
				return "";
			}
			
			return ((Gtk.TextBuffer) this).get_text(start, end, true);
		}
		
		
		/**
		 * Sync buffer contents to file on disk.
		 * 
		 * Gets the current buffer contents and writes them to the file.
		 * Used when buffer contents have been modified via GTK operations
		 * (user typing, etc.) and need to be saved to disk.
		 * 
		 * == Process ==
		 * 
		 *  1. Get buffer content from GTK TextBuffer
		 *  2. Write to file (creates backup, writes, updates metadata)
		 *  3. Mark buffer as not modified
		 *  4. Update last_read_timestamp to match file modification time
		 * 
		 * This method is only supported for GTK buffers. For dummy buffers,
		 * use write() instead.
		 */
		public async void sync_to_file() throws Error
		{
			// Get buffer content
			Gtk.TextIter start, end;
			this.get_bounds(out start, out end);
			var contents = ((Gtk.TextBuffer) this).get_text(start, end, true);
			
			// Write to file (backup, write, update metadata)
			yield this.write_real(contents);
			
			// Mark buffer as not modified
			this.set_modified(false);
			
			// Update last_read_timestamp to match file modification time
			this.last_read_timestamp = GLib.File.new_for_path(this.file.path).query_info(
				GLib.FileAttribute.TIME_MODIFIED,
				GLib.FileQueryInfoFlags.NONE,
				null
			).get_modification_date_time().to_unix();
		}
		
		/**
		 * Write contents to buffer and file.
		 * 
		 * Updates GtkSource.Buffer.text with new contents and writes to file on disk.
		 * For files in database, creates backup before writing.
		 * 
		 * == Process ==
		 * 
		 *  1. Update buffer text property
		 *  2. Write to file (creates backup, writes, updates metadata)
		 *  3. Update last_read_timestamp to match file modification time
		 * 
		 * @param contents Contents to write
		 * @throws Error if file cannot be written
		 */
		public async void write(string contents) throws Error
		{
			// Update buffer
			this.text = contents;
			// Reset detection flag when content changes
		
			
			// Write to file (backup, write, update metadata)
			yield this.write_real(contents);
			
			// Update last_read_timestamp to match file modification time
			this.last_read_timestamp = GLib.File.new_for_path(this.file.path).query_info(
				GLib.FileAttribute.TIME_MODIFIED,
				GLib.FileQueryInfoFlags.NONE,
				null
			).get_modification_date_time().to_unix();
		}
		
		/**
		 * Clear buffer contents to empty.
		 * 
		 * Clears the GTK TextBuffer contents, reflecting that the file has been deleted.
		 * 
		 * @throws Error if clearing fails
		 */
		public async void clear() throws Error
		{
			Gtk.TextIter start, end;
			this.get_bounds(out start, out end);
			this.delete(ref start, ref end);
			this.is_loaded = true;
			// Reset detection flag when content is cleared
			this.detection_done = false;
		}
		
		/**
		 * Update indentation to use spaces based on space counts and return.
		 * 
		 * Sets uses_tabs to false and indent_size to the most common space count.
		 * 
		 * @param space_counts Map of normalized space counts to their frequencies
		 */
		private void update_indent_size(Gee.HashMap<int, int> space_counts)
		{
			this.uses_tabs = false;
			var most_common = 4;
			var max_count = 0;
			foreach (var entry in space_counts.entries) {
				if (entry.value > max_count) {
					max_count = entry.value;
					most_common = entry.key;
				}
			}
			this.indent_size = most_common;
		}
		
		/**
		 * Detect indentation style from buffer content.
		 * 
		 * Analyzes first 100 lines (or all lines if fewer) to determine:
		 * - Whether file uses tabs or spaces
		 * - If spaces, how many spaces per indent level
		 * 
		 * Stops early once 10 lines with tabs or 10 lines with spaces are found.
		 */
		private void detect_indentation()
		{
			// If already detected, skip (NOOP)
			if (this.detection_done) {
				return;
			}
		
			
			
			var line_count = this.get_line_count();
			if (line_count == 0) {
				return;
			}
			// Reset to defaults before detection 
			// (needed because some code paths return early without setting values)
			// except when we have an empty file - then we just use the old defaults.
			
			this.indent_size = 0;
			this.uses_tabs = true;
			var max_lines = (line_count < 100) ? line_count : 100;
			var tab_count = 0;
			var space_count = 0;
			var space_counts = new Gee.HashMap<int, int>();
			
			for (var i = 0; i < max_lines; i++) {
				var line = this.get_line(i);
				if (line.strip().length == 0) {
					continue;
				}
				
				// Get prefix using chug
				var prefix_length = line.length - line.chug().length;
				if (prefix_length == 0) {
					continue;
				}
				
				var prefix = line.substring(0, prefix_length);
				
				// Count tabs and spaces in prefix
				var tabs_in_prefix = prefix.replace(" ", "").length;
				var spaces_in_prefix = prefix.replace("\t", "").length;
				
				if (line.has_prefix("\t") || tabs_in_prefix > 0) {
					tab_count++;
					if (tab_count >= 10) {
						this.detection_done = true;
						return;
					}
				}
				
				if (spaces_in_prefix > 0 && tabs_in_prefix == 0) {
					space_count++;
					// Track space counts (normalize to common values)
					var normalized = 
						(spaces_in_prefix % 4 == 0) ? 4 : (
							(spaces_in_prefix % 2 == 0) ? 2 : (
								(spaces_in_prefix % 8 == 0) ? 8 : spaces_in_prefix));
					var current_count = space_counts.has_key(normalized) ? 
						space_counts.get(normalized) : 0;
					space_counts.set(normalized, current_count + 1);
					
				if (space_count >= 10) {
					this.update_indent_size(space_counts);
					this.detection_done = true;
					return;
				}
				}
			}
			
			// Determine from collected statistics
			if (tab_count > 0) {
				this.detection_done = true;
				return;
			}
			
			if (space_count > 0) {
				this.update_indent_size(space_counts);
				this.detection_done = true;
				return;
			}
			
			// No indentation found, keep defaults
			this.detection_done = true;
		}
		
		/**
		 * Apply multiple edits to the buffer efficiently using GTK buffer operations.
		 * 
		 * Uses GTK TextBuffer's text manipulation for efficient chunk editing.
		 * Applies edits in reverse order (from end to start) to preserve line numbers.
		 * 
		 * == Process ==
		 * 
		 *  1. Ensure buffer is loaded (calls read_async() if needed)
		 *  2. Apply changes in reverse order (from end to start) to preserve line numbers
		 *  3. For each change:
		 *     * Handle insertion case (start == end): Insert at existing line or end of file
		 *     * Handle edit case (start != end): Delete range and insert replacement
		 *  4. Sync buffer to file (creates backup, writes, updates metadata)
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
		public async void apply_edits(Gee.ArrayList<OLLMfiles.FileChange> changes) throws Error
		{
			// Ensure buffer is loaded
			if (!this.is_loaded) {
				yield this.read_async();
			}
			
			// Apply changes in reverse order (from end to start) to preserve line numbers
			foreach (var change in changes) {
				// Get base indentation for normalization
				var line_number = change.start - 1;
				var base_indent = "";
				
				// Extract base indentation if line exists
				if (line_number >= 0 && line_number < this.get_line_count()) {
					var line = this.get_line(line_number);
					var prefix_length = line.length - line.chug().length;
					if (prefix_length > 0) {
						base_indent = line.substring(0, prefix_length);
					}
				}
				
				// Normalize indentation of replacement text
				change.normalize_indentation(base_indent);
				
				// Get iterators for the range
				Gtk.TextIter start_iter;
				Gtk.TextIter end_iter;
				
				// Handle insertion case (start == end) - normal insertion at existing line
				var has_start = this.get_iter_at_line(out start_iter, change.start - 1);
				if (change.start == change.end && has_start) {
					end_iter = start_iter;
					this.delete(ref start_iter, ref end_iter);
					this.insert(ref start_iter, change.replacement, -1);
					continue;
				}
				
				// Handle insertion case (start == end) - insertion at end of file
				if (change.start == change.end && (change.start - 1) == this.get_line_count()) {
					this.get_end_iter(out start_iter);
					end_iter = start_iter;
					this.delete(ref start_iter, ref end_iter);
					this.insert(ref start_iter, change.replacement, -1);
					continue;
				}
				
				// Handle insertion case (start == end) - invalid line range
				if (change.start == change.end) {
					throw new GLib.IOError.INVALID_ARGUMENT(
						"Invalid line range: start=" + change.start.to_string() + 
						" (file has " + this.get_line_count().to_string() + " lines)");
				}
				
				// Handle edit case (start != end) - get start iterator
				if (!this.get_iter_at_line(out start_iter, change.start - 1)) {
					throw new GLib.IOError.INVALID_ARGUMENT(
						"Invalid line range: start=" + change.start.to_string() + 
						" (file has " + this.get_line_count().to_string() + " lines)");
				}
				
				// Handle edit case - get end iterator (end line exists)
				if (this.get_iter_at_line(out end_iter, change.end - 1)) {
					this.delete(ref start_iter, ref end_iter);
					this.insert(ref start_iter, change.replacement, -1);
					continue;
				}
				
				// Handle edit case - get end iterator (end line doesn't exist, use end of buffer)
				this.get_end_iter(out end_iter);
				this.delete(ref start_iter, ref end_iter);
				this.insert(ref start_iter, change.replacement, -1);
			}
			
			// Sync buffer to file (creates backup, writes, updates metadata)
			yield this.sync_to_file();
		}
	}
}

