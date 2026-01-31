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
	 * Marker map for block-level markers (headings, HR, lists, fenced code, blockquote, etc.).
	 * Used by the parser for peekBlock().
	 */
	public class BlockMap : MarkerMap
	{
		private static Gee.HashMap<string, FormatType> mp;

		private ListMap listmap = new ListMap();

		static construct
		{
			mp = new Gee.HashMap<string, FormatType>();

			// Headings: # Heading 1 to ###### Heading 6
			mp["#"] = FormatType.HEADING_1;
			mp["##"] = FormatType.HEADING_2;
			mp["###"] = FormatType.HEADING_3;
			mp["####"] = FormatType.HEADING_4;
			mp["#####"] = FormatType.HEADING_5;
			mp["######"] = FormatType.HEADING_6;

			// Horizontal Rules: ---, ***, ___
			mp["--"] = FormatType.INVALID;
			mp["---"] = FormatType.HORIZONTAL_RULE;
			mp["**"] = FormatType.INVALID;
			mp["***"] = FormatType.HORIZONTAL_RULE;
			mp["__"] = FormatType.INVALID;
			mp["___"] = FormatType.HORIZONTAL_RULE;

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

			// Continue list: 2 spaces to continue list items
			mp[" "] = FormatType.INVALID;
			mp["  "] = FormatType.CONTINUE_LIST;

			// Fenced Code: ``` or ~~~ with optional language
			mp["`"] = FormatType.INVALID;
			mp["``"] = FormatType.INVALID;
			mp["```"] = FormatType.FENCED_CODE_QUOTE;
			mp["~"] = FormatType.INVALID;
			mp["~~"] = FormatType.INVALID;
			mp["~~~"] = FormatType.FENCED_CODE_TILD;

			// Blockquotes: > quote text (up to 6 levels deep)
			mp[">"] = FormatType.INVALID;
			mp["> "] = FormatType.BLOCKQUOTE;
			mp["> >"] = FormatType.INVALID;
			mp["> > "] = FormatType.BLOCKQUOTE;
			mp["> > >"] = FormatType.INVALID;
			mp["> > > "] = FormatType.BLOCKQUOTE;
			mp["> > > >"] = FormatType.INVALID;
			mp["> > > > "] = FormatType.BLOCKQUOTE;
			mp["> > > > >"] = FormatType.INVALID;
			mp["> > > > > "] = FormatType.BLOCKQUOTE;
			mp["> > > > > >"] = FormatType.INVALID;
			mp["> > > > > > "] = FormatType.BLOCKQUOTE;
		}

		public BlockMap()
		{
			base(BlockMap.mp);
		}

		/**
		 * Block-level peek: wraps base.eat() then handles fenced code (newline/lang) and CONTINUE_LIST (delegates to listmap).
		 * @param last_line_block Used to validate CONTINUE_LIST (only valid after ORDERED_LIST or UNORDERED_LIST).
		 */
		public int peek(
			string chunk,
			int chunk_pos,
			bool is_end_of_chunks,
			FormatType last_line_block,
			out string lang_out,
			out FormatType matched_block,
			out int byte_length
		) {
			lang_out = "";
			matched_block = FormatType.NONE;
			byte_length = 0;

			int result = base.eat(
				chunk, 
				chunk_pos, 
				is_end_of_chunks, 
				out matched_block, 
				out byte_length);

			if (result < 1) {
				return result;
			}

			// Fenced code: need newline and optional language
			if (matched_block == FormatType.FENCED_CODE_QUOTE 
				|| matched_block == FormatType.FENCED_CODE_TILD) {
				if (!chunk.contains("\n")) {
					return -1;
				}
				var newline_pos = chunk.index_of_char('\n', chunk_pos);
				if (newline_pos == -1) {
					return -1;
				}
				var fence_end_pos = chunk_pos + byte_length;
				var newline_char = chunk.get_char(newline_pos);
				var newline_byte_len = newline_char.to_string().length;
				byte_length = newline_pos + newline_byte_len - chunk_pos;
				if (fence_end_pos >= newline_pos) {
					return newline_pos - chunk_pos + 1;
				}
				var unstripped_lang = chunk.substring(fence_end_pos, newline_pos - fence_end_pos);
				lang_out = unstripped_lang.strip();
				return newline_pos - chunk_pos + 1;
			}

			// CONTINUE_LIST: only valid after list block; then delegate to listmap
			if (matched_block == FormatType.CONTINUE_LIST) {
				if (last_line_block != FormatType.ORDERED_LIST && last_line_block != FormatType.UNORDERED_LIST) {
					return 0;
				}
				var continue_end_pos = chunk_pos + byte_length;
				var continue_length = byte_length;
				var list_result = this.listmap.peek(
					chunk, 
					continue_end_pos,
					 is_end_of_chunks, 
					 out matched_block, 
					 out byte_length);
				if (list_result == -1) {
					return -1;
				}
				byte_length += continue_length;
				return continue_length + list_result;
			}

			return result;
		}

		/**
		 * Checks if we're at a closing fenced code fence.
		 *
		 * @param chunk The text chunk
		 * @param chunk_pos The position to check
		 * @param fence_type The type of fence we're looking for (FENCED_CODE_QUOTE or FENCED_CODE_TILD)
		 * @param is_end_of_chunks If true, end of stream indicator
		 * @return -1 if need more data, 0 if not a match, 3 if match found
		 */
		public int peekFencedEnd(
			string chunk, 
			int chunk_pos, 
			FormatType fence_type, 
			bool is_end_of_chunks)
		{
			if (!chunk.contains("\n") && !is_end_of_chunks) {
				return -1;
			}

			if (chunk_pos >= chunk.length) {
				return 0;
			}

			var fence_str = (fence_type == FormatType.FENCED_CODE_QUOTE) ? "```" : "~~~";
			var fence_char = fence_str.substring(0, 1);

			var first_char = chunk.get_char(chunk_pos);
			if (first_char.to_string() != fence_char) {
				return 0;
			}

			if (chunk_pos + 3 > chunk.length) {
				if (is_end_of_chunks) {
					return 0;
				}
				return -1;
			}

			var match_str = chunk.substring(chunk_pos, 3);
			if (match_str != fence_str) {
				return 0;
			}

			var pos = chunk_pos + 3;
			if (pos >= chunk.length) {
				if (is_end_of_chunks) {
					return 3;
				}
				return -1;
			}

			var newline_pos = chunk.index_of_char('\n', pos);
			if (newline_pos == pos) {
				return 3;
			}

			if (newline_pos != -1) {
				var between = chunk.substring(pos, newline_pos - pos);
				if (between.strip().length == 0) {
					return 3;
				}
				return 0;
			}

			var remaining = chunk.substring(pos);
			if (remaining.strip().length == 0) {
				if (is_end_of_chunks) {
					return 3;
				}
				return -1;
			}

			return 0;
		}
	}
}
