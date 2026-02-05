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
	 * Marker map for delimiter runs that are valid as closing delimiters (must be followed by whitespace or newline).
	 * peek() wraps eat() and rejects the match if the next character is not whitespace or newline.
	 * Contains only emphasis-style sequences (asterisk and underscore); no links, code, etc.
	 */
	public class RightMap : MarkerMap
	{
		private static Gee.HashMap<string, FormatType> mp;
		private Parser parser;

		private static void init()
		{
			if (mp != null) {
				return;
			}
			mp = new Gee.HashMap<string, FormatType>();

			// Asterisk sequences (closer when followed by whitespace/newline; peek enforces that)
			mp["*"] = FormatType.ITALIC;
			mp["**"] = FormatType.BOLD;
			mp["***"] = FormatType.BOLD_ITALIC;

			// Underscore sequences (closer when followed by whitespace/newline)
			mp["_"] = FormatType.ITALIC;
			mp["__"] = FormatType.BOLD;
			mp["___"] = FormatType.BOLD_ITALIC;
		}

		public RightMap(Parser parser)
		{
			RightMap.init();
			base(RightMap.mp);
			this.parser = parser;
		}

		/**
		 * Like eat() but fails instantly if at line start or stack empty; and only accepts when next char is whitespace or newline.
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
			if (this.parser.at_line_start || this.parser.state_stack.size == 0) {
				return 0;
			}
			int result = base.eat(chunk, chunk_pos, is_end_of_chunks, out matched_type, out byte_length);
			if (result < 1) {
				return result;
			}
			var seq_pos = chunk_pos + byte_length;
			if (seq_pos >= chunk.length) {
				return is_end_of_chunks ? result : -1;
			}
			var next_char = chunk.get_char(seq_pos);
			if (next_char == '\n' || next_char.isspace() || !next_char.isalpha()) {
				return result;
			}
			return 0;
		}

		/**
		 * Handles right (closing) delimiter result. Caller calls peek() then this.
		 * @return true (need more; parser.leftover_chunk set), false to keep processing
		 */
		public bool handle_right_result(
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
				this.parser.leftover_chunk = str + chunk.substring(saved_chunk_pos, chunk.length - saved_chunk_pos);
				str = "";
				return true;
			}
			if (match_result == 0) {
				return false;
			}
			this.parser.renderer.on_text(str);
			str = "";
			this.parser.state_stack.remove_at(this.parser.state_stack.size - 1);
			this.parser.do_format(false, matched_type);
			chunk_pos = saved_chunk_pos + byte_length;
			this.parser.at_line_start = false;
			return false;
		}
	}
}
