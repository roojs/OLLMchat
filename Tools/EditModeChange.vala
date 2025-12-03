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

namespace OLLMchat.Tools
{
	/**
	 * Represents a single edit operation with range and replacement.
	 */
	public class EditModeChange : Object
	{
		public int start { get; set; default = -1; }
		public int end { get; set; default = -1; }
		public string replacement { get; set; default = ""; }
		public Gee.ArrayList<string> old_lines { get; set; default = new Gee.ArrayList<string>(); }
		
		/**
		 * Writes the replacement text to the output stream and skips old lines in the input stream.
		 * 
		 * @param output_stream The output stream to write replacement to
		 * @param input_stream The input stream to skip old lines from
		 * @param current_line Reference to current line number (will be updated)
		 * @throws Error if I/O operations fail
		 */
		public int apply_changes(
			GLib.DataOutputStream output_stream, 
			GLib.DataInputStream input_stream, 
			int current_line) throws Error
		{
			// Write replacement lines (skip if empty for deletion)
			if (this.replacement.strip() != "") {
				foreach (var new_line in this.replacement.split("\n")) {
					output_stream.put_string(new_line);
					output_stream.put_byte('\n');
				}
			}
			
			// Skip old lines in input stream until end of edit range (exclusive)
			string? line;
			size_t length;
			while (current_line < this.end - 1) {
				line = input_stream.read_line(out length, null);
				if (line == null) {
					break;
				}
				current_line++;
			}
			
			return current_line;
		}
		
		/**
		 * Writes the replacement text to the output stream for insertions at end of file.
		 * Only writes if this is an insertion (start == end) and it's past the current line.
		 * 
		 * @param output_stream The output stream to write replacement to
		 * @param current_line The current line number in the file
		 * @throws Error if I/O operations fail
		 */
		public void write_changes(GLib.DataOutputStream output_stream, int current_line) throws Error
		{
			// Only write if this is an insertion at end of file
			if (this.start != this.end || this.start <= current_line) {
				return;
			}
			
			// Write replacement lines (skip if empty for deletion)
			if (this.replacement.strip() != "") {
				foreach (var new_line in this.replacement.split("\n")) {
					output_stream.put_string(new_line);
					output_stream.put_byte('\n');
				}
			}
		}
	}
}

