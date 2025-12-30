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
	 * Dummy file buffer implementation for non-GTK contexts.
	 * 
	 * Uses in-memory lines array cache. No GTK dependencies.
	 */
	public class DummyFileBuffer : Object, FileBuffer
	{
		/**
		 * Reference to the file this buffer represents.
		 */
		public File file { get; construct; }
		
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
			Object(file: file);
		}
		
		/**
		 * Read file contents asynchronously.
		 * 
		 * Always reads from disk and updates cache.
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
		public bool is_loaded {
			get {
				return this.lines != null;
			}
		}
		
		/**
		 * Sync buffer contents to file on disk.
		 * 
		 * Not supported for DummyFileBuffer - this method is only for GTK SourceView.
		 * Use write() instead to update buffer and write to file.
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
	}
}

