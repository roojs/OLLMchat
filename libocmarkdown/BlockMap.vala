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
	 * Used by the parser for handle_block_result().
	 */
	public class BlockMap : MarkerMap
	{
		private static Gee.HashMap<string, FormatType> mp;

		private ListMap listmap = new ListMap();
		private Parser parser;

		/** The whole matched string that opened the fenced block (e.g. "```" or "   ```"). Set by peek() when matching fenced code. */
		public string fence_open { get; private set; }

		private static void init()
		{
			if (mp != null) {
				return;
			}
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
			//mp[" -"] = FormatType.INVALID;
			//mp[" - "] = FormatType.UNORDERED_LIST;
			//mp[" *"] = FormatType.INVALID;
			//mp[" * "] = FormatType.UNORDERED_LIST;
			//mp[" +"] = FormatType.INVALID;
			//mp[" + "] = FormatType.UNORDERED_LIST;

			mp["•"] = FormatType.INVALID;
			//mp[" •"] = FormatType.INVALID;
			mp["• "] = FormatType.INVALID;
			//mp[" • "] = FormatType.INVALID;

			// Ordered Lists: 1. item, 2. item, etc.
			mp["1"] = FormatType.INVALID;
			mp["1."] = FormatType.INVALID;
			mp["1. "] = FormatType.ORDERED_LIST;
			mp["11"] = FormatType.INVALID;
			mp["11."] = FormatType.INVALID;
			mp["11. "] = FormatType.ORDERED_LIST;
			//mp[" 1"] = FormatType.INVALID;
			//mp[" 1."] = FormatType.INVALID;
			//mp[" 1. "] = FormatType.ORDERED_LIST;
			//mp[" 11"] = FormatType.INVALID;
			//mp[" 11."] = FormatType.INVALID;
			//mp[" 11. "] = FormatType.ORDERED_LIST;

			// Fenced Code: ``` or ~~~ with optional language; indented case handled by skipping leading spaces before eat
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

			// Table: | at line start (validated in peek() with 3-line rule)
			mp["|"] = FormatType.TABLE;
		}

		public BlockMap(Parser parser)
		{
			BlockMap.init();
			base(BlockMap.mp);
			this.parser = parser;
		}

		/**
		 * Block-level peek: skips leading spaces then base.eat(); on no match with indent in list, delegates to listmap. Handles fenced code (newline/lang), table, etc.
		 * @param last_line_block Used when delegating to listmap (only after ORDERED_LIST or UNORDERED_LIST).
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
			this.fence_open = "";

			// Line at chunk_pos (to next \n or end); used for pre-eat and space_skip
			var line_end = chunk.index_of_char('\n', chunk_pos);
			var line_len = (line_end == -1) ? (int) chunk.length - chunk_pos : line_end - chunk_pos;
			var line = chunk_pos < chunk.length ? chunk.substring(chunk_pos, line_len) : "";

			// Pre eat: if line is only whitespace we need more or have no block
			if (line.length > 0 && line.strip() == "") {
				if (line_end != -1 || is_end_of_chunks || line.length > 8) {
					return 0;
				}
				return -1;
			}

			var stripped = line.strip();
			var space_skip = (stripped.length > 0) ? line.index_of(stripped) : 0;

			int result = base.eat(
				chunk,
				chunk_pos + space_skip,
				is_end_of_chunks,
				out matched_block,
				out byte_length);

			if (result == -1) {
				return -1;
			}
			if (result == 0) {
				// No block matched; if leading indent and inside a list, let listmap interpret
				if (
					space_skip > 0
					&& (
						last_line_block == FormatType.ORDERED_LIST || 
						last_line_block == FormatType.UNORDERED_LIST)
				) {
					var list_result = this.listmap.peek(
						chunk,
						chunk_pos,
						is_end_of_chunks,
						out matched_block,
						out byte_length);
					return list_result;
				}
				return 0;
			}

			// Match: byte_length from eat is relative to (chunk_pos + space_skip); revert and add space_skip so chunk_pos is unchanged
			byte_length = space_skip + byte_length;

			// Fenced code: only 0 or 3 spaces allowed before fence
			if (
				(matched_block == FormatType.FENCED_CODE_QUOTE || matched_block == FormatType.FENCED_CODE_TILD)
				&& space_skip != 0
				&& space_skip != 3
			) {
				return 0;
			}

			// Fenced code: need newline and optional language; store whole match for matching closing fence
			if (matched_block == FormatType.FENCED_CODE_QUOTE 
				|| matched_block == FormatType.FENCED_CODE_TILD) {
				this.fence_open = chunk.substring(chunk_pos, space_skip + 3);
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

			// TABLE: need 3 full lines (header, separator, first body row); verify progressively
			if (matched_block == FormatType.TABLE) {
				var rest = chunk.substring(chunk_pos);
				var lines = rest.split("\n");
				// Wait for first \n so we have a complete line 1 before checking
				if (lines.length < 2) {
					if (is_end_of_chunks) {
						return 0;
					}
					return -1;
				}
				// Line 1 must start and end with | (trim for generosity)
				if (!lines[0].strip().has_prefix("|") || !lines[0].strip().has_suffix("|")) {
					return 0;
				}
				// If we have the second line and it doesn't start with |, reject
				if (lines[1].strip() != "" && !lines[1].strip().has_prefix("|")) {
					return 0;
				}
				if (lines.length < 3) {
					if (is_end_of_chunks) {
						return 0;
					}
					return -1;
				}
				// Then validate separator (only space, |, -, :)
				try {
					if (!(new GLib.Regex("^[- |:]*$").match(lines[1].strip()))) {
						return 0;
					}
				} catch (GLib.RegexError e) {
					return 0;
				}
				// Third line: not empty and must start with |
				if (lines[2].strip() != "" && !lines[2].strip().has_prefix("|")) {
					return 0;
				}
				// Wait for third newline so we have 3 complete lines
				if (lines.length < 4) {
					if (is_end_of_chunks) {
						return 0;
					}
					return -1;
				}
				// Line 3 must end with |
				if (!lines[2].strip().has_suffix("|")) {
					return 0;
				}
				// byte_length = 3 lines including newlines (support multi-byte newline)
				var nl_byte_len = rest.length > lines[0].length
					? rest.get_char(lines[0].length).to_string().length
					: 1;
				byte_length = lines[0].length + nl_byte_len
					+ lines[1].length + nl_byte_len
					+ lines[2].length + nl_byte_len;
				return 1;
			}

			// Horizontal rule (***, ---, ___): next char must be whitespace or newline; else treat as inline (e.g. ***Bold***)
			if (matched_block == FormatType.HORIZONTAL_RULE) {
				if (is_end_of_chunks) {
					return result;
				}
				var seq_pos = chunk_pos + byte_length;
				if (seq_pos >= chunk.length) {
					return -1;
				}
				var next_char = chunk.get_char(seq_pos);
				if (next_char != '\n' && !next_char.isspace()) {
					return 0;
				}
			}

			return result;
		}

		/**
		 * Handles block peek result. Caller calls peek() then this.
		 * Updates chunk_pos when a block is consumed.
		 * @return true (need more characters; parser.leftover_chunk set), false (to keep processing the rest of the chunk)
		 */
		public bool handle_block_result(
			int block_match,
			string block_lang,
			FormatType matched_block,
			int byte_length,
			ref int chunk_pos,
			string chunk,
			int saved_chunk_pos,
			bool is_end_of_chunks
		) {
			if (block_match == -1) {
				this.parser.leftover_chunk = chunk.substring(saved_chunk_pos, chunk.length - saved_chunk_pos);
				return true;
			}
			if (block_match == 0) {
				// No block detected - start a paragraph (caller sets at_line_start when falling through)
				if (this.parser.current_block == FormatType.NONE) {
					this.parser.current_block = FormatType.PARAGRAPH;
					this.parser.do_block(true, FormatType.PARAGRAPH);
				}
				return false;
			}
			var seq_pos = chunk_pos + byte_length;
			switch (matched_block) {
				case FormatType.HORIZONTAL_RULE:
					var newline_pos = chunk.index_of_char('\n', seq_pos);
					var rest = newline_pos != -1
						? chunk.substring(seq_pos, newline_pos - seq_pos)
						: chunk.substring(seq_pos, chunk.length - seq_pos);
					if (rest.strip() != "") {
						if (this.parser.current_block == FormatType.NONE) {
							this.parser.current_block = FormatType.PARAGRAPH;
							this.parser.do_block(true, FormatType.PARAGRAPH);
						}
						this.parser.at_line_start = false;
						return false;
					}
					if (newline_pos == -1 && !is_end_of_chunks) {
						this.parser.leftover_chunk = chunk.substring(saved_chunk_pos, chunk.length - saved_chunk_pos);
						return true;
					}
					this.parser.do_block(true, matched_block);
					if (newline_pos != -1) {
						var newline_char = chunk.get_char(newline_pos);
						this.parser.at_line_start = true;
						chunk_pos = newline_pos + newline_char.to_string().length;
					} else {
						this.parser.at_line_start = true;
						chunk_pos = (int) chunk.length;
					}
					return false;

				case FormatType.FENCED_CODE_QUOTE:
				case FormatType.FENCED_CODE_TILD:
					this.parser.current_block = matched_block;
					this.parser.do_block(true, matched_block, block_lang);
					this.parser.at_line_start = true;
					chunk_pos = seq_pos;
					return false;

				case FormatType.BLOCKQUOTE:
					if (this.parser.current_block != FormatType.NONE) {
						this.parser.at_line_start = false;
						return false;
					}
					this.parser.current_block = matched_block;
					var marker_string = chunk.substring(chunk_pos, byte_length);
					this.parser.do_block(true, matched_block, marker_string);
					chunk_pos = seq_pos;
					return false;

				case FormatType.ORDERED_LIST:
				case FormatType.UNORDERED_LIST:
					this.parser.current_block = matched_block;
					var list_marker = chunk.substring(chunk_pos, byte_length);
					this.parser.do_block(true, matched_block, list_marker);
					this.parser.at_line_start = false;
					chunk_pos = seq_pos;
					return false;

				case FormatType.TABLE:
					this.parser.current_block = FormatType.TABLE;
					this.parser.table_state = new TableState(this.parser);
					var consumed_block = chunk.substring(chunk_pos, byte_length);
					var lines = consumed_block.split("\n");
					this.parser.table_state.feed_line(lines[0]);
					this.parser.table_state.feed_line(lines[1]);
					this.parser.table_state.feed_line(lines[2]);
					this.parser.at_line_start = true;
					chunk_pos = seq_pos;
					return false;

				default:
					this.parser.current_block = matched_block;
					this.parser.do_block(true, matched_block, block_lang);
					this.parser.at_line_start = false;
					chunk_pos = seq_pos;
					return false;
			}
		}

		/**
		 * Checks if we're at a closing fenced code fence. Uses fence_open so the closing
		 * line must start with the same whole match that opened the block {{{(e.g. "   ```")}}}
		 *
		 * @param chunk The text chunk
		 * @param chunk_pos The position to check; may be advanced by 3 when indented content line (fence_open.length > 3 and line starts with "   ")
		 * @param fence_type The type of fence we're looking for (FENCED_CODE_QUOTE or FENCED_CODE_TILD)
		 * @param is_end_of_chunks If true, end of stream indicator
		 * @return -1 if need more data, 0 if not a match, >0 byte length consumed (through newline) if match
		 */
		public int peekFencedEnd(
			string chunk,
			ref int chunk_pos,
			FormatType fence_type,
			bool is_end_of_chunks)
		{
			if (chunk_pos >= chunk.length) {
				return 0;
			}

			if (chunk_pos + this.fence_open.length > chunk.length) {
				if (is_end_of_chunks) {
					return 0;
				}
				return -1;
			}

			var at_marker = chunk.substring(chunk_pos, this.fence_open.length);
			if (at_marker != this.fence_open) {
				if (this.fence_open.length > 3 && at_marker.has_prefix("   ")) {
					chunk_pos += 3;
				}
				return 0;
			}

			var pos = chunk_pos + this.fence_open.length;
			if (pos >= chunk.length) {
				if (is_end_of_chunks) {
					return this.fence_open.length;
				}
				return -1;
			}

			var newline_pos = chunk.index_of_char('\n', pos);
			if (newline_pos == pos) {
				var nl_char = chunk.get_char(newline_pos);
				return this.fence_open.length + nl_char.to_string().length;
			}

			if (newline_pos != -1) {
				var between = chunk.substring(pos, newline_pos - pos);
				if (between.strip().length == 0) {
					var nl_char = chunk.get_char(newline_pos);
					return newline_pos - chunk_pos + nl_char.to_string().length;
				}
				return 0;
			}

			var remaining = chunk.substring(pos);
			if (remaining.strip().length == 0) {
				if (is_end_of_chunks) {
					return (int) chunk.length - chunk_pos;
				}
				return -1;
			}

			return 0;
		}

		/**
		 * When in fenced code block and not at line start: collect code text up to next newline (or all remaining).
		 * @param chunk_pos Updated to position after consumed code text (at newline if found)
		 * @param chunk The current chunk
		 * @return true (flushed and need to return from add), false to continue loop
		 */
		public bool check_fenced_newline(ref int chunk_pos, string chunk)
		{
			var remaining = chunk.substring(chunk_pos, chunk.length - chunk_pos);
			if (!remaining.contains("\n")) {
				this.parser.renderer.on_node(FormatType.CODE_TEXT, false, remaining);
				return true;
			}
			var newline_pos = chunk.index_of_char('\n', chunk_pos);
			var code_text = chunk.substring(chunk_pos, newline_pos - chunk_pos);
			this.parser.renderer.on_node(FormatType.CODE_TEXT, false, code_text);
			chunk_pos = newline_pos;
			return false;
		}

		/**
		 * Handles fenced-code closing fence result. Caller calls peekFencedEnd() then this.
		 * Updates chunk_pos when consuming input.
		 * @param fence_result Result from peekFencedEnd (-1 need more, 0 not fence, >0 bytes consumed)
		 * @param chunk_pos Updated to position after consumed input
		 * @param chunk The current chunk
		 * @return true (need more characters or flushed text; parser.leftover_chunk may be set), false to keep processing the rest of the chunk
		 */
		public bool handle_fence_result(int fence_result, ref int chunk_pos, string chunk)
		{
			if (fence_result == -1) {
				this.parser.leftover_chunk = chunk.substring(chunk_pos, chunk.length - chunk_pos);
				return true;
			}
			if (fence_result == 0) {
				var remaining = chunk.substring(chunk_pos, chunk.length - chunk_pos);
				if (!remaining.contains("\n")) {
					this.parser.renderer.on_node(FormatType.CODE_TEXT, false, remaining);
					return true;
				}
				var newline_pos = chunk.index_of_char('\n', chunk_pos);
				var code_text = chunk.substring(chunk_pos, newline_pos - chunk_pos);
				this.parser.renderer.on_node(FormatType.CODE_TEXT, false, code_text);
				chunk_pos = newline_pos;
				this.parser.at_line_start = false;
				return false;
			}
			// fence_result > 0: found closing fence - end the block (fence_result is byte length consumed)
			chunk_pos += fence_result;
			this.parser.do_block(false, this.parser.current_block);
			this.parser.last_line_block = this.parser.current_block;
			this.parser.current_block = FormatType.NONE;
			this.parser.is_literal = "";
			this.parser.at_line_start = true;
			return false;
		}
	}
}
