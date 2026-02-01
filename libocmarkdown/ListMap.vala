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
	 * Marker map for list-only block markers (CONTINUE_LIST, ORDERED_LIST, UNORDERED_LIST).
	 * Used by the parser (via BlockMap.peek) for list-block detection.
	 */
	public class ListMap : MarkerMap
	{
		private static Gee.HashMap<string, FormatType> mp;

		private static void init()
		{
			if (mp != null) {
				return;
			}
			mp = new Gee.HashMap<string, FormatType>();
			GLib.debug("ListMap.init: initializing static map");

			// Continue list: 2 spaces to continue list items
			mp[" "] = FormatType.INVALID;
			mp["  "] = FormatType.CONTINUE_LIST;

			// Unordered Lists: - item, * item, + item
			mp["-"] = FormatType.INVALID;
			mp["- "] = FormatType.UNORDERED_LIST;
			mp["*"] = FormatType.INVALID;
			mp["* "] = FormatType.UNORDERED_LIST;
			mp["+"] = FormatType.INVALID;
			mp["+ "] = FormatType.UNORDERED_LIST;
			mp[" -"] = FormatType.INVALID;
			mp[" - "] = FormatType.UNORDERED_LIST;
			mp[" *"] = FormatType.INVALID;
			mp[" * "] = FormatType.UNORDERED_LIST;
			mp[" +"] = FormatType.INVALID;
			mp[" + "] = FormatType.UNORDERED_LIST;

			mp["•"] = FormatType.INVALID;
			mp[" •"] = FormatType.INVALID;
			mp["• "] = FormatType.INVALID;
			mp[" • "] = FormatType.INVALID;

			// Ordered Lists: 1. item, 2. item, etc.
			mp["1"] = FormatType.INVALID;
			mp["1."] = FormatType.INVALID;
			mp["1. "] = FormatType.ORDERED_LIST;
			mp["11"] = FormatType.INVALID;
			mp["11."] = FormatType.INVALID;
			mp["11. "] = FormatType.ORDERED_LIST;
			mp[" 1"] = FormatType.INVALID;
			mp[" 1."] = FormatType.INVALID;
			mp[" 1. "] = FormatType.ORDERED_LIST;
			mp[" 11"] = FormatType.INVALID;
			mp[" 11."] = FormatType.INVALID;
			mp[" 11. "] = FormatType.ORDERED_LIST;
		}

		public ListMap()
		{
			ListMap.init();
			base(ListMap.mp);
		}

		/**
		 * Determines if characters at a given position match a list-related block tag.
		 * Only matches CONTINUE_LIST, ORDERED_LIST, or UNORDERED_LIST.
		 * If CONTINUE_LIST is found, recursively calls itself to check what follows.
		 */
		public int peek(
			string chunk,
			int chunk_pos,
			bool is_end_of_chunks,
			out FormatType matched_block,
			out int byte_length
		) {
			matched_block = FormatType.NONE;
			byte_length = 0;

			if (chunk_pos >= chunk.length) {
				return 0;
			}

			var first_char = chunk.get_char(chunk_pos);
			if (!first_char.isspace() && !first_char.isdigit() &&
			    first_char != '-' && first_char != '*' && first_char != '+') {
				return 0;
			}

			var ch = chunk.get_char(chunk_pos);
			var first_char_len = ch.to_string().length;
			if (chunk_pos + first_char_len >= chunk.length) {
				if (!is_end_of_chunks) {
					return -1;
				}
				return 0;
			}

			int max_match_length = 0;
			int char_count = 0;
			var sequence = "";

			for (var cp = chunk_pos; cp < chunk.length; ) {
				var char_at_cp = chunk.get_char(cp);
				sequence += char_at_cp.isdigit() ? "1" : char_at_cp.to_string();
				cp += char_at_cp.to_string().length;
				char_count++;

				if (!this.map.has_key(sequence)) {
					if (max_match_length > 0) {
						return max_match_length;
					}
					return 0;
				}

				var block_type = this.map.get(sequence);

				switch (block_type) {
					case FormatType.CONTINUE_LIST:
						var continue_byte_length = cp - chunk_pos;
						FormatType recursive_matched_block;
						int recursive_byte_length;
						var recursive_result = this.peek(
							chunk, 
							cp, 
							is_end_of_chunks,
							 out recursive_matched_block, 
							 out recursive_byte_length);
						if (recursive_result == -1) {
							return -1;
						}
						if (recursive_result > 0) {
							matched_block = recursive_matched_block;
							byte_length = continue_byte_length + recursive_byte_length;
							return continue_byte_length + recursive_result;
						}
						matched_block = recursive_matched_block;
						byte_length = continue_byte_length + recursive_byte_length;
						return continue_byte_length + recursive_result;

					case FormatType.ORDERED_LIST:
					case FormatType.UNORDERED_LIST:
						matched_block = block_type;
						byte_length = cp - chunk_pos;
						return char_count;

					default:
						if (block_type != FormatType.INVALID) {
							matched_block = FormatType.NONE;
							byte_length = 0;
							return 0;
						}
						break;
				}
			}

			if (!is_end_of_chunks) {
				return -1;
			}
			if (max_match_length > 0) {
				return max_match_length;
			}
			return 0;
		}
	}
}
