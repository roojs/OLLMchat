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
	 * Marker map for delimiter runs that are valid at **start of line** only.
	 * Used when the preceding context is "start of line" (e.g. at_line_start).
	 * Contains only emphasis-style sequences (asterisk and underscore); no links, code, etc.
	 */
	public class StartMap : MarkerMap
	{
		private static Gee.HashMap<string, FormatType> mp;
		private Parser parser;

		private static void init()
		{
			if (mp != null) {
				return;
			}
			mp = new Gee.HashMap<string, FormatType>();

			// Asterisk sequences (valid opener at start of line)
			mp["*"] = FormatType.ITALIC;
			mp["**"] = FormatType.BOLD;
			mp["***"] = FormatType.BOLD_ITALIC;

			// Underscore sequences (valid opener at start of line)
			mp["_"] = FormatType.ITALIC;
			mp["__"] = FormatType.BOLD;
			mp["___"] = FormatType.BOLD_ITALIC;
		}

		public StartMap(Parser parser)
		{
			StartMap.init();
			base(StartMap.mp);
			this.parser = parser;
		}

		/**
		 * Peek for start-of-line delimiter. Calls base.eat() at current position.
		 */
		public int peek(
			string chunk,
			int chunk_pos,
			bool is_end_of_chunks,
			out FormatType matched_type,
			out int byte_length
		) {
			return base.eat(chunk, chunk_pos, is_end_of_chunks, out matched_type, out byte_length);
		}

		/**
		 * Handles start-of-line peek result. Caller calls peek() then this.
		 * Updates chunk_pos when a start-of-line format is consumed.
		 * @return true (need more characters; parser.leftover_chunk set), false to keep processing
		 */
		public bool handle_start_result(
			int match_result,
			FormatType matched_type,
			int byte_length,
			ref int chunk_pos,
			string chunk,
			int saved_chunk_pos,
			bool is_end_of_chunks
		) {
			if (match_result == -1) {
				this.parser.leftover_chunk = chunk.substring(
					saved_chunk_pos, chunk.length - saved_chunk_pos);
				return true;
			}
			if (match_result == 0) {
				return false;
			}
			this.parser.got_format(matched_type);
			chunk_pos = saved_chunk_pos + byte_length;
			this.parser.at_line_start = false;
			return false;
		}
	}
}
