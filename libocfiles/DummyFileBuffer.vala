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

#if !G_OS_WIN32
[CCode (cname = "strcasestr", cheader_filename = "string.h")]
extern unowned string? strcasestr (string haystack, string needle);
#endif

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
			
			// Handle line range (0-based inclusive; ''end_line == -1'' = through last line)
			if (start_line < 0 || start_line >= this.lines.length) {
				return "";
			}
			int el = end_line == -1 ? this.lines.length - 1 : 
				(end_line >= this.lines.length ? this.lines.length - 1 : end_line);
			if (el < start_line) {
				return "";
			}
			return string.joinv("\n", this.lines[start_line:el + 1]);
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
		
		private int index_of_caseless (string haystack, string needle, int start_index = 0)
		{
			if (needle.length == 0) {
				return start_index;
			}
			if (start_index < 0 || start_index > haystack.length) {
				return -1;
			}
			var tail = haystack.substring (start_index);
#if !G_OS_WIN32
			if (Posix.memchr ((void*) needle, 0x80, needle.length) == null) {
				unowned string? hit = strcasestr (tail, needle);
				if (hit == null) {
					return -1;
				}
				return start_index + (int) tail.pointer_to_offset (hit);
			}
#endif
			var i = tail.casefold ().index_of (needle.casefold ());
			return i < 0 ? -1 : start_index + i;
		}
		
		/**
		 * Append to result every match of needle in the current window whose end lies
		 * on or before the safe search limit (full window at EOF; otherwise exclude the
		 * carry tail so a match spanning the next chunk is not committed early).
		 * Map value is full line(s) covering the match (expand span to line boundaries).
		 *
		 * @return true if the caller should slide the window (drop prefix, advance
		 * line_base): i.e. not at EOF and window is longer than the needle.
		 */
		private bool locate_in_window(
			string window,
			string needle,
			long line_base,
			bool eof,
			bool case_sensitive,
			Gee.HashMap<int, string> result
		)
		{
			var search_limit = eof
				? window.length
				: (window.length > needle.length ? window.length - needle.length : 0);
			var pos = 0;
			var prev = 0;
			long nl_before_match = 0;
			while (true) {
				var found = case_sensitive
					? window.index_of(needle, pos)
					: this.index_of_caseless(window, needle, pos);
				if (found < 0) {
					break;
				}
				if (found + (int) needle.length > search_limit) {
					break;
				}
				nl_before_match += found > prev
					? window.substring(prev, found - prev).split("\n").length - 1
					: 0;
				var match_end = found + (int) needle.length;
				var prev_nl = found > 0 ? window.substring(0, found).last_index_of("\n") : -1;
				var line_start = prev_nl >= 0 ? prev_nl + 1 : 0;
				var rest = window.substring(match_end);
				var nl_after = rest.index_of("\n");
				var line_end = nl_after >= 0 ? match_end + nl_after + 1 : window.length;
				result.set(
					(int) (line_base + nl_before_match),
					window.substring(line_start, line_end - line_start)
				);
				prev = found;
				pos = found + (int) needle.length;
			}
			return !eof && window.length > needle.length;
		}

		public Gee.HashMap<int, string> locate(string needle, bool match_trimmed, bool case_sensitive)
		{
			var result = new Gee.HashMap<int, string>();
			if (needle.strip() == "") {
				return result;
			}
			/* Trimmed multiline not implemented on dummy; same as literal search. */
			var path_file = GLib.File.new_for_path(this.file.path);
			GLib.FileInputStream stream;
			try {
				if (!path_file.query_exists()) {
					return result;
				}
				stream = path_file.read(null);
			} catch (GLib.Error e) {
				GLib.debug("DummyFileBuffer.locate: %s", e.message);
				return result;
			}
			var window = "";
			long line_base = 0;
			if (needle.length < 1) {
				return result;
			}
			var eof = false;
			var chunk_buf = new uint8[65536];
			while (!eof) {
				ssize_t n_read;
				try {
					n_read = stream.read(chunk_buf);
				} catch (GLib.Error e) {
					GLib.debug("DummyFileBuffer.locate: %s", e.message);
					break; /* continuation: fall through to return partial result */
				}
				if (n_read < 0) {
					break; /* same: best-effort map so far */
				}
				eof = eof || n_read == 0;
				window = n_read > 0 ? window + (string) chunk_buf[0:n_read] : window;
				if (this.locate_in_window(window, needle, line_base, eof, case_sensitive, result)) {
					var keep_from = window.length - needle.length;
					line_base += keep_from > 0
						? window.substring(0, keep_from).split("\n").length - 1
						: 0;
					window = window.substring(keep_from);
				}
			}
			return result;
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
		 * Clear buffer contents to empty.
		 * 
		 * Sets the lines array to an empty array, reflecting that the file has been deleted.
		 * 
		 * @throws Error if clearing fails
		 */
		public async void clear() throws Error
		{
			this.lines = new string[0];
			this.is_loaded = true;
		}
		
		/**
		 * Apply a single edit to the buffer.
		 * 
		 * This performs the actual edit operation on the buffer.
		 * Does NOT sync to file - that should be done by the caller.
		 * 
		 * @param change The FileChange to apply
		 * @throws Error if edit cannot be applied (invalid line ranges, etc.)
		 */
		public async void apply_edit(FileChange change) throws Error
		{
			// Ensure buffer is loaded
			if (this.lines == null) {
				yield this.read_async();
			}
			
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
			var lines_before = this.lines[0:start_idx];
			// Empty replacement must not use split alone ("" yields one line).
			var replacement_lines = change.replacement.split("\n");
			if (!is_insertion && change.replacement == "") {
				replacement_lines = {};
			}
			var lines_after = this.lines[end_idx:this.lines.length];
			
			// Build new lines array efficiently using GLib.Array
			var array = new GLib.Array<string>(false, true, sizeof(string));
			array.append_vals(lines_before, lines_before.length);
			array.append_vals(replacement_lines, replacement_lines.length);
			array.append_vals(lines_after, lines_after.length);
			
			// Take ownership to avoid array copying
			this.lines = (owned) array.data;
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
		 *  3. For each change: calls apply_edit()
		 *  4. Join lines back into content string
		 *  5. Write to file (backup, write, updates metadata)
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
			
			// Sort changes by start line (descending) so we can apply them in reverse order
			changes.sort((a, b) => {
				if (a.start < b.start) return 1;
				if (a.start > b.start) return -1;
				return 0;
			});
			
			// Apply changes using apply_edit() for each change
			foreach (var change in changes) {
				yield this.apply_edit(change);
			}
			
			// Join lines back into content string
			var new_content = string.joinv("\n", this.lines);
			
			// Write to file (backup, write, update metadata)
			yield this.write_real(new_content);
		}
	}
}

