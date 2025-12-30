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

namespace OLLMcoder
{
	/**
	 * GTK SourceView buffer implementation.
	 * 
	 * Extends GtkSource.Buffer and provides FileBuffer interface.
	 * Tracks file modification time and reloads buffer if file changed on disk.
	 */
	public class GtkSourceFileBuffer : GtkSource.Buffer, OLLMfiles.FileBuffer
	{
		/**
		 * Reference to the file this buffer represents.
		 */
		public OLLMfiles.File file { get; construct; }
		
		/**
		 * Last read timestamp (Unix timestamp).
		 * Used to detect if file was modified on disk since last read.
		 */
		private int64 last_read_timestamp = 0;
		
		/**
		 * Whether the buffer has been loaded with file content.
		 * 
		 * Returns true if the buffer has been loaded from the file,
		 * false if it needs to be loaded.
		 */
		public bool is_loaded { get; private set; default = false; }
		
		/**
		 * Constructor.
		 * 
		 * @param file The file this buffer represents
		 * @param language Optional language for syntax highlighting
		 */
		public GtkSourceFileBuffer(OLLMfiles.File file, GtkSource.Language? language = null)
		{
			if (language != null) {
				base.with_language(language);
			}
			Object(file: file);
		}
		
		/**
		 * Read file contents asynchronously.
		 * 
		 * Checks file modification time and reloads buffer if file was modified
		 * since last read. Updates buffer text and last_read_timestamp.
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
			}
			
			// Return buffer contents
			Gtk.TextIter start, end;
			this.get_bounds(out start, out end);
			return this.get_text(start, end, true);
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
				return this.get_text(line_start, line_end, true);
			}
			
			return this.get_text(start, end, true);
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
			
			return this.get_text(iter, line_end, true);
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
			
			return this.get_text(start, end, true);
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
		public void write(string contents) throws Error
		{
			// Create backup if needed
			create_backup_if_needed();
			
			// Update buffer
			this.text = contents;
			
			// Write to file
			write_to_disk(contents);
			
			// Update last_read_timestamp to match file modification time
			var file_obj = GLib.File.new_for_path(this.file.path);
			var file_info = file_obj.query_info(
				GLib.FileAttribute.TIME_MODIFIED,
				GLib.FileQueryInfoFlags.NONE,
				null
			);
			var mod_time = file_info.get_modification_date_time();
			this.last_read_timestamp = mod_time.to_unix();
			
			// Update file metadata
			update_file_metadata_after_write();
		}
	}
}

