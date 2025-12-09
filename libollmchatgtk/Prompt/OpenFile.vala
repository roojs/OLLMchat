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

namespace OLLMchatGtk.Prompt
{
	/**
	 * Represents an open file in the editor.
	 * 
	 * Tracks file information and provides access to file contents,
	 * cursor position, selected code, and other editor state.
	 */
	public class OpenFile : Object
	{
		/**
		 * The file path.
		 */
		public string filename { get; construct; }
		
		/**
		 * Reference to the GTK SourceView widget (or null if not yet connected).
		 */
		public GtkSource.View? sourceview { get; set; default = null; }
		
		/**
		 * Whether this file is currently active.
		 */
		public bool active { get; set; default = false; }
		
		/**
		 * Signal handler ID for the active property monitor.
		 */
		public ulong active_monitor_id { get; set; default = 0; }
		
		/**
		 * Constructor.
		 * 
		 * @param filename The file path
		 */
		public OpenFile(string filename)
		{
			Object(filename: filename);
		}
		
		/**
		 * Gets file contents, optionally limited to first N lines.
		 * 
		 * @param max_lines Maximum number of lines to return (0 = all lines)
		 * @return File contents, or empty string if not available
		 */
		public string get_contents(int max_lines = 0)
		{
			if (this.sourceview == null) {
				return "";
			}
			
			var buffer = this.sourceview.buffer;
			if (buffer == null) {
				return "";
			}
			
			Gtk.TextIter start, end;
			buffer.get_bounds(out start, out end);
			
			if (max_lines > 0) {
				// Limit to first max_lines
				var line_end = start;
				line_end.forward_lines(max_lines - 1);
				if (!line_end.ends_line()) {
					line_end.forward_to_line_end();
				}
				return buffer.get_text(start, line_end, true);
			}
			
			return buffer.get_text(start, end, true);
		}
		
		/**
		 * Gets the total number of lines in the file.
		 * 
		 * @return Line count, or 0 if not available
		 */
		public int get_line_count()
		{
			if (this.sourceview == null) {
				return 0;
			}
			
			var buffer = this.sourceview.buffer;
			if (buffer == null) {
				return 0;
			}
			
			Gtk.TextIter start, end;
			buffer.get_bounds(out start, out end);
			return end.get_line() + 1;
		}
		
		/**
		 * Gets the file modification time from the filesystem.
		 * 
		 * @return File modification time, or 0 if not available
		 */
		public time_t get_mtime()
		{
			var file = File.new_for_path(this.filename);
			if (!file.query_exists()) {
				return 0;
			}
			
			try {
				var info = file.query_info("time::modified", FileQueryInfoFlags.NONE, null);
				return info.get_modification_time().tv_sec;
			} catch (GLib.Error e) {
				return 0;
			}
		}
		
		/**
		 * Gets the currently selected text (only valid for active file).
		 * 
		 * @return Selected text, or empty string if nothing is selected
		 */
		public string get_selected_code()
		{
			if (this.sourceview == null) {
				return "";
			}
			
			var buffer = this.sourceview.buffer;
			if (buffer == null) {
				return "";
			}
			
			Gtk.TextIter start, end;
			if (!buffer.get_selection_bounds(out start, out end)) {
				return "";
			}
			
			return buffer.get_text(start, end, true);
		}
		
		/**
		 * Gets the content of a specific line.
		 * 
		 * @param line Line number (0-based)
		 * @return Line content, or empty string if not available
		 */
		public string get_line_content(int line)
		{
			if (this.sourceview == null) {
				return "";
			}
			
			var buffer = this.sourceview.buffer;
			if (buffer == null) {
				return "";
			}
			
			Gtk.TextIter iter;
			if (!buffer.get_iter_at_line(out iter, line)) {
				return "";
			}
			
			var line_end = iter;
			if (!line_end.ends_line()) {
				line_end.forward_to_line_end();
			}
			
			return buffer.get_text(iter, line_end, true);
		}
		
		/**
		 * Gets the current cursor position (line number).
		 * 
		 * @return Line number (0-based), or -1 if not available
		 */
		public int get_cursor_position()
		{
			if (this.sourceview == null) {
				return -1;
			}
			
			var buffer = this.sourceview.buffer;
			if (buffer == null) {
				return -1;
			}
			
			Gtk.TextIter cursor;
			buffer.get_iter_at_mark(out cursor, buffer.get_insert());
			return cursor.get_line();
		}
	}
}
