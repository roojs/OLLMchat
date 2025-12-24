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

namespace OLLMcoder.Files
{
	/**
	 * GTK implementation of buffer provider for File operations.
	 */
	public class BufferProvider : OLLMfiles.BufferProviderBase
	{
		public override string? detect_language(OLLMfiles.File file)
		{
			var lang_manager = GtkSource.LanguageManager.get_default();
			var language = lang_manager.guess_language(file.path, null);
			return language?.get_id();
		}
		
		public override void create_buffer(OLLMfiles.File file)
		{
			// Early exit: no language specified
			if (file.language == null || file.language == "") {
				var buffer = new GtkSource.Buffer(null);
				file.set_data<GtkSource.Buffer>("buffer", buffer);
				return;
			}
			
			// Try to get language object
			var language =  GtkSource.LanguageManager.get_default()
						.get_language(file.language);
			
			// Early exit: language not found
			if (language == null) {
				var buffer = new GtkSource.Buffer(null);
				file.set_data<GtkSource.Buffer>("buffer", buffer);
				return;
			}
			
			// Success: create buffer with language
			var buffer = new GtkSource.Buffer.with_language(language);
			file.set_data<GtkSource.Buffer>("buffer", buffer);
		}
		
		public override string get_buffer_text(OLLMfiles.File file, int start_line = 0, int end_line = -1)
		{
			var buffer = file.get_data<GtkSource.Buffer>("buffer");
			if (buffer == null) {
				return "";
			}
			
			Gtk.TextIter start, end;
			buffer.get_bounds(out start, out end);
			
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
				return buffer.get_text(line_start, line_end, true);
			}
			
			return buffer.get_text(start, end, true);
		}
		
		public override int get_buffer_line_count(OLLMfiles.File file)
		{
			var buffer = file.get_data<GtkSource.Buffer>("buffer");
			if (buffer == null) {
				return 0;
			}
			
			Gtk.TextIter start, end;
			buffer.get_bounds(out start, out end);
			return end.get_line() + 1;
		}
		
		public override string get_buffer_selection(
			OLLMfiles.File file, 
			out int cursor_line, 
			out int cursor_offset)
		{
			cursor_line = 0;
			cursor_offset = 0;
			
			var buffer = file.get_data<GtkSource.Buffer>("buffer");
			if (buffer == null) {
				return "";
			}
			
			// Update cursor position from buffer
			Gtk.TextIter cursor;
			buffer.get_iter_at_mark(out cursor, buffer.get_insert());
			cursor_line = cursor.get_line();
			cursor_offset = cursor.get_line_offset();
			
			Gtk.TextIter start, end;
			if (!buffer.get_selection_bounds(out start, out end)) {
				return "";
			}
			
			return buffer.get_text(start, end, true);
		}
		
		public override string get_buffer_line(OLLMfiles.File file, int line)
		{
			var buffer = file.get_data<GtkSource.Buffer>("buffer");
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
		
		public override void get_buffer_cursor(OLLMfiles.File file, out int line, out int offset)
		{
			line = 0;
			offset = 0;
			
			var buffer = file.get_data<GtkSource.Buffer>("buffer");
			if (buffer == null) {
				return;
			}
			
			Gtk.TextIter cursor;
			buffer.get_iter_at_mark(out cursor, buffer.get_insert());
			line = cursor.get_line();
			offset = cursor.get_line_offset();
		}
		
		public override bool has_buffer(OLLMfiles.File file)
		{
			var buffer = file.get_data<GtkSource.Buffer>("buffer");
			return buffer != null;
		}
	}
}
