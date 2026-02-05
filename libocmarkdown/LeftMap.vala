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

namespace Markdown
{
	/**
	 * Marker map for delimiter runs that are valid as opening delimiters (must be preceded by whitespace).
	 * peek() wraps eat() and fails if at line start or the character before is not whitespace.
	 * Contains only emphasis-style sequences (asterisk and underscore); no links, code, etc.
	 */
	public class LeftMap : MarkerMap
	{
		private static Gee.HashMap<string, FormatType> mp;
		private Parser parser;

		private static void init()
		{
			if (mp != null) {
				return;
			}
			mp = new Gee.HashMap<string, FormatType>();

			// Asterisk sequences (opener when preceded by whitespace; peek enforces that)
			mp["*"] = FormatType.ITALIC;
			mp["**"] = FormatType.BOLD;
			mp["***"] = FormatType.BOLD_ITALIC;

			// Underscore sequences (opener when preceded by whitespace)
			mp["_"] = FormatType.ITALIC;
			mp["__"] = FormatType.BOLD;
			mp["___"] = FormatType.BOLD_ITALIC;
		}

		public LeftMap(Parser parser)
		{
			LeftMap.init();
			base(LeftMap.mp);
			this.parser = parser;
		}

		/**
		 * Current pos must be " " (whitespace); then eat delimiter at chunk_pos + 1. No backwards scanning.
		 */
		public int peek(
			string chunk,
			int chunk_pos,
			bool is_end_of_chunks,
			out FormatType matched_type,
			out int byte_length
		) {
			matched_type = FormatType.NONE;
			byte_length = 0;
			var c = chunk.get_char(chunk_pos);
			if (!c.isspace()) {
				return 0;
			}
			var space_len = c.to_string().length;
			// Need space + at least one delimiter char; any less is -1 (need more) or 0 (end of chunks)
			if (chunk.length - chunk_pos < space_len + 1) {
				return is_end_of_chunks ? 0 : -1;
			}
			var result = base.eat(chunk, chunk_pos + space_len, is_end_of_chunks, out matched_type, out byte_length);
			if (result > 0) {
				byte_length = space_len + byte_length;
			}
			return result;
		}

		/**
		 * Handles left (opening) delimiter result. Caller calls peek() then this.
		 * @return true (need more; parser.leftover_chunk set), false to keep processing
		 */
		public bool handle_left_result(
			int match_result,
			FormatType matched_type,
			int byte_length,
			ref int chunk_pos,
			ref string str,
			string chunk,
			int saved_chunk_pos,
			bool is_end_of_chunks
		) {
			if (match_result == -1) {
				this.parser.leftover_chunk = chunk.substring(saved_chunk_pos, chunk.length - saved_chunk_pos);
				return true;
			}
			if (match_result == 0) {
				return false;
			}
			this.parser.renderer.on_text(str + " ");
			str = "";
			this.parser.got_format(matched_type);
			chunk_pos = saved_chunk_pos + byte_length;
			this.parser.at_line_start = false;
			return false;
		}
	}
}
