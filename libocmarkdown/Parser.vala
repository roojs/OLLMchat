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

/*
 * STRING HANDLING IN VALA - IMPORTANT NOTES:
 *
 * Vala strings are UTF-8 encoded, which requires careful handling:
 *   - .length returns BYTE count (not character count)
 *   - substring(offset, len): offset is BYTE offset, len is BYTE length (both in bytes)
 *     See: https://valadoc.org/glib-2.0/string.substring.html
 *   - char_count() returns the number of characters (not bytes)
 *   - index_of_nth_char(n) converts character position to byte offset
 *   - get_char(byte_offset) gets a character at a byte offset
 *
 * KEY POINT: substring() uses byte offsets, not character positions.
 * This is why we must convert character counts to byte offsets.
 *
 * NAMING CONVENTIONS IN THIS FILE:
 *   - Variables ending in _byte_offset or _byte: byte offsets (for use with substring())
 *   - Variables ending in _char_pos or _char_count: character positions/counts
 *   - Variables ending in _length: usually character counts
 *   - Always convert character counts to byte offsets before using substring()
 *
 * EXAMPLE CONVERSION:
 *   int char_count = text.char_count();  // Get CHARACTER count
 *   int byte_offset = text.index_of_nth_char(char_count);  // Convert to BYTE offset
 *   string result = text.substring(byte_offset);  // substring() requires BYTE offset
 */

namespace Markdown
{
	
	
	
 
    public enum FormatType {
        NONE,
        ITALIC,
        BOLD,
        BOLD_ITALIC,
        /** Delimiter-preserving (document round-trip); base renderers map to ITALIC/BOLD. */
        ITALIC_ASTERISK,
        ITALIC_UNDERSCORE,
        BOLD_ASTERISK,
        BOLD_UNDERSCORE,
        BOLD_ITALIC_ASTERISK,
        BOLD_ITALIC_UNDERSCORE,
        CODE,
        STRIKETHROUGH,
		HIGHLIGHT,
		SUPERSCRIPT,
		SUBSCRIPT,
		INVALID,
		HTML,
		LITERAL,
		HEADING_1,
		HEADING_2,
		HEADING_3,
		HEADING_4,
		HEADING_5,
		HEADING_6,
		HORIZONTAL_RULE,
		PARAGRAPH,
		UNORDERED_LIST,
		ORDERED_LIST,
		CONTINUE_LIST,
		TASK_LIST,
		TASK_LIST_DONE,
		LINK,
		DEFINITION_LIST,
		INDENTED_CODE,
		FENCED_CODE_QUOTE,
		FENCED_CODE_TILD,
		BLOCKQUOTE,
		TABLE,
		TABLE_ROW,
		TABLE_HCELL,
		TABLE_CELL,
		LIST_ITEM,
		TEXT,
		IMAGE,
		BR,
		U,
		OTHER,
		CODE_TEXT,
		SOFTBR,
		ENTITY,
		/** For document model node_type discriminator (JSON polymorphic deserialization). */
		DOCUMENT,
		BLOCK,
		LIST,
		FORMAT
    }
	
	
	/**
	 * Parser for markdown text that calls specific callbacks on Render.
	 * 
	 * This is a placeholder implementation. Full parser implementation
	 * will be specified in a separate plan.
	 */
	public class Parser
	{
		internal RenderBase renderer { get; private set; }
		public FormatMap formatmap { get; set; }
		internal TableState? table_state { get; set; }
		public BlockMap blockmap { get; set; }
		public StartMap startmap { get; set; }
		public LeftMap leftmap { get; set; }
		public RightMap rightmap { get; set; }
		internal Gee.ArrayList<FormatType> state_stack {
			get; set; default = new Gee.ArrayList<FormatType>(); }

		public string leftover_chunk { get; set; default = ""; }
		public string is_literal { get; set; default = ""; }
		public FormatType last_line_block { get; set; default = FormatType.NONE; }
		public FormatType current_block { get; set; default = FormatType.NONE; }
		public bool at_line_start { get; set; default = true; }
		
		/**
		 * Creates a new Parser instance.
		 * 
		 * @param renderer The RenderBase instance to call callbacks on
		 */
		public Parser(RenderBase renderer)
		{
			this.renderer = renderer;
			this.formatmap = new FormatMap(this);
			this.blockmap = new BlockMap(this);
			this.startmap = new StartMap(this);
			this.leftmap = new LeftMap(this);
			this.rightmap = new RightMap(this);
		}
		

		public void flush()
		{
			this.is_literal = "";
			this.add("", true);
		}

		/**
		* Starts/initializes the parser for a new block.
		* 
		* Resets the parser's internal state, clears the state stack,
		* and sets the current state to NONE.
		*/
		public void start()
		{
			this.is_literal = "";
			this.leftover_chunk = "";
			this.state_stack.clear();
			this.last_line_block = FormatType.NONE;
			this.current_block = FormatType.NONE;
			this.at_line_start = true;
		}

		/**
		 * Checks if the character at the given position is a valid HTML tag start.
		 * 
		 * @param chunk The text chunk to examine
		 * @param chunk_pos The position in the chunk to check (should be after '<')
		 * @param is_end_of_chunks If true, format markers at the end are treated as definitive
		 * @return 1: Valid HTML tag start, 0: Not valid HTML, -1: Cannot determine (need more characters)
		 */
		public int peekHTML(string chunk, int chunk_pos, bool is_end_of_chunks)
		{
			// Check if we have a character after '<'
			if (chunk_pos >= chunk.length) {
				if (!is_end_of_chunks) {
					return -1; // Need more characters
				}
				return 0; // End of chunks and no next char - not valid HTML
			}
			
			var next_char = chunk.get_char(chunk_pos);
			
			// Valid HTML tag starts with a-z (opening tag) or '/' (closing tag)
			if (next_char.isalpha() || next_char == '/') {
				return 1; // Valid HTML tag start
			}
				
			return 0; // Not a valid HTML tag start
		}

		/**
		* Parses text and calls specific callbacks on Render.
		* Uses peekFormat to detect format sequences.
		* 
		* @param in_chunk The markdown text to parse
		* @param is_end_of_chunks If true, format markers at the end are treated as definitive (no more data coming)
		*/
		public void add(string in_chunk, bool is_end_of_chunks = false)
		{
			var chunk = this.leftover_chunk + in_chunk; // Prepend leftover_chunk so it's processed first
			this.leftover_chunk = ""; // Clear leftover_chunk after using it
			var chunk_pos = 0;
			var saved_chunk_pos = 0;
			var escape_next = false;
			// Accumulated plain inline text since last flush (no format markers * _ ` [ <).
			// Flushed on format match, newline, need-more-input, or end of add();
			// never contains newlines.
			var str = "";
			//GLib.debug("  [str] INIT: str='%s' (empty)", str);
			
			while (chunk_pos < chunk.length) {
				saved_chunk_pos = chunk_pos;
				var c = chunk.get_char(chunk_pos);
				
				// Handle newline - end current block and prepare for next line
				//GLib.debug("chunk_pos=%d, c='%s', at_line_start=%s, current_block=%s",
				//	 chunk_pos, c.to_string(), this.at_line_start.to_string(), this.current_block.to_string());
				if (c == '\n') {
					this.handle_line_break(ref chunk_pos, ref str);
					escape_next = false;
					continue;
				}
				
				
				// If we're in a fenced code block, check for closing fence only at line start
				if (this.current_block == FormatType.FENCED_CODE_QUOTE
					 || this.current_block == FormatType.FENCED_CODE_TILD) {
					if (!this.at_line_start) {
						if (this.blockmap.check_fenced_newline(ref chunk_pos, chunk)) {
							assert(str == "");
							return;
						}
						continue;
					}
					// At line start - check for closing fence
					var fence_result = this.blockmap.peekFencedEnd(chunk, ref chunk_pos, this.current_block, is_end_of_chunks);
					if (this.blockmap.handle_fence_result(fence_result, ref chunk_pos, chunk)) {
						assert(str == "");
						return;
					}
					continue;
				}
				
				
				 
				
				// In table: at line start, consume one full line and either feed as row or end table
				if (this.at_line_start && this.current_block == FormatType.TABLE) {
					if (this.table_state.handle_line_start(ref chunk_pos, chunk, is_end_of_chunks)) {
						assert(str == "");
						return;
					}
					continue;
				}

				// this makes more sense as a location to check of rescaping - before we do block.
				if (escape_next) {
					var char_str = c.to_string();
					str += char_str;
					escape_next = false;
					chunk_pos += c.to_string().length;
					this.at_line_start = false;
					continue;
				}
				if (c == '\\') {
					escape_next = true;
					chunk_pos += c.to_string().length;
					this.at_line_start = false;
					continue;
				}

				if (this.is_literal != "") {
					var result = this.formatmap.peek_literal(chunk, chunk_pos, is_end_of_chunks, this.is_literal);
					if (result == -1) {
						this.leftover_chunk = str + chunk.substring(chunk_pos, chunk.length - chunk_pos);
						str = "";
						return;
					}
					if (result == 0) {
						str += c.to_string();
						chunk_pos += c.to_string().length;
						this.at_line_start = false;
						continue;
					}
					this.renderer.on_node(FormatType.TEXT, false, str);
					str = "";
					this.state_stack.remove_at(this.state_stack.size - 1);
					this.do_format(false, this.is_literal.length == 1 ? FormatType.LITERAL : FormatType.CODE);
					this.is_literal = "";
					chunk_pos += result;
					this.at_line_start = false;
					continue;
				}

				// At line start - check for block markers
				if (this.at_line_start) {
					string block_lang = "";
					FormatType matched_block = FormatType.NONE;
					int byte_length = 0;
					int space_skip = 0;
					var block_match = this.blockmap.peek(
						chunk,
						chunk_pos,
						is_end_of_chunks,
						this.last_line_block,
						out block_lang,
						out matched_block,
						out byte_length,
						out space_skip
					);
					if (this.blockmap.handle_block_result(
						block_match,
						block_lang,
						matched_block,
						byte_length,
						space_skip,
						ref chunk_pos,
						chunk,
						saved_chunk_pos,
						is_end_of_chunks
					)) {
						assert(str == "");
						return;
					}
					// Only continue when we consumed a block (chunk_pos advanced);
					// else fall through to process current char as inline
					if (chunk_pos != saved_chunk_pos) {
						continue;
					}
				}

				// At line start - check for start-of-line emphasis (*, _)
				if (this.at_line_start) {
					FormatType matched_format = FormatType.NONE;
					int byte_length = 0;
					var match_result = this.startmap.peek(
						chunk,
						chunk_pos,
						is_end_of_chunks,
						out matched_format,
						out byte_length
					);
					if (this.startmap.handle_start_result(
						match_result,
						matched_format,
						byte_length,
						ref chunk_pos,
						chunk,
						saved_chunk_pos,
						is_end_of_chunks
					)) {
						assert(str == "");
						return;
					}
					if (chunk_pos != saved_chunk_pos) {
						continue;
					}
					// let the next tests try and match...
				}

				// Left (opening) delimiter: must be preceded by whitespace; peek + handle
				// If str is empty and current char is space, flush str and leave space in chunk for left check
				if (str.length != 0 && c.isspace()) {
					this.renderer.on_node(FormatType.TEXT, false, str);
					str = "";
				}
				FormatType left_matched = FormatType.NONE;
				int left_byte_length = 0;
				var left_match = this.leftmap.peek(
					chunk,
					chunk_pos,
					is_end_of_chunks,
					out left_matched,
					out left_byte_length
				);
				if (this.leftmap.handle_left_result(
					left_match,
					left_matched,
					left_byte_length,
					ref chunk_pos,
					ref str,
					chunk,
					saved_chunk_pos,
					is_end_of_chunks
				)) {
					assert(str == "");
					return;
				}
				if (chunk_pos != saved_chunk_pos) {
					continue;
				}

				// Right (closing) delimiter: peek fails if at line start or stack empty; must be followed by whitespace/newline
				FormatType right_matched = FormatType.NONE;
				int right_byte_length = 0;
				var right_match = this.rightmap.peek(
					chunk,
					chunk_pos,
					is_end_of_chunks,
					out right_matched,
					out right_byte_length
				);
				if (this.rightmap.handle_right_result(
					right_match,
					right_matched,
					right_byte_length,
					ref chunk_pos,
					ref str,
					chunk,
					saved_chunk_pos,
					is_end_of_chunks
				)) {
					assert(str == "");
					return;
				}
				if (chunk_pos != saved_chunk_pos) {
					continue;
				}

				// Use formatmap.eat to detect format sequences
				FormatType matched_format = FormatType.NONE;
				int unused_byte_length;
				var match_len = this.formatmap.eat(
					chunk,
					chunk_pos,
					is_end_of_chunks,
					out matched_format,
					out unused_byte_length
				);

				if (this.formatmap.handle_format_result(
					match_len,
					matched_format,
					c, 
					ref chunk_pos, 
					ref str, 
					ref chunk, 
					is_end_of_chunks)) {
					assert(str == "");
					return;
				}
				// If we consumed (chunk_pos advanced), continue; else no match - advance here
				if (chunk_pos != saved_chunk_pos) {
					this.at_line_start = false;
					continue;
				}
				str += c.to_string();
				chunk_pos += c.to_string().length;
				this.at_line_start = false;
				continue;
			}
			


			// Flush any remaining text
			//GLib.debug("  [str] FINAL FLUSH: str='%s'", str);
			this.renderer.on_node(FormatType.TEXT, false, str);
			if (this.current_block != FormatType.NONE) {
				this.do_block(false, this.current_block);
				this.last_line_block = this.current_block;
				this.current_block = FormatType.NONE;
			}
		}
	

		/**
		 * Handles format markers by checking the stack.
		 * If the same format is on top of stack, removes it and calls on_end.
		 * If different, adds to stack and calls the appropriate do_XXX method.
		 * 
		 * @param format_type The format type detected
		 */
		internal void got_format(FormatType format_type)
		{
			// some format types dont have start and end flags..
			switch (format_type) {
				case FormatType.LINK:
					return; // Handled in formatmap.handle_format_result / process_inline; never pushed via got_format
				case FormatType.TASK_LIST:
				case FormatType.TASK_LIST_DONE:
					//GLib.debug("got_format: TASK_LIST_DONE called");
					this.do_format(true, format_type);
					return;
				default:
					break;
			}
			
			// Check if stack is empty or top is different
			if (this.state_stack.size == 0 
				|| this.state_stack.get(this.state_stack.size - 1) != format_type) {
				// Different state - add to stack and call do_XXX
				this.state_stack.add(format_type);
				this.do_format(true, format_type);
				return;
			}
			
			// Same state - remove from stack and call do_end
			this.state_stack.remove_at(this.state_stack.size - 1);
			this.do_format(false, format_type);
		}
		
		/**
		 * Calls the appropriate renderer method based on format type.
		 * Delimiter-preserving types (ITALIC_ASTERISK, etc.) pass through to the renderer.
		 *
		 * @param is_start True to start the format, false to end it
		 * @param format_type The format type
		 */
		internal void do_format(bool is_start, FormatType format_type)
		{
			switch (format_type) {
				case FormatType.ITALIC_ASTERISK:
				case FormatType.ITALIC_UNDERSCORE:
				case FormatType.BOLD_ASTERISK:
				case FormatType.BOLD_UNDERSCORE:
				case FormatType.BOLD_ITALIC_ASTERISK:
				case FormatType.BOLD_ITALIC_UNDERSCORE:
					this.renderer.on_node(format_type, is_start);
					break;
				case FormatType.ITALIC:
					this.renderer.on_node(FormatType.ITALIC, is_start);
					break;
				case FormatType.BOLD:
					this.renderer.on_node(FormatType.BOLD, is_start);
					break;
				case FormatType.CODE:
					if (is_start) {
						this.is_literal = "``";
					} else {
						this.is_literal = "";
					}
					this.renderer.on_node(FormatType.CODE, is_start);
					break;
				case FormatType.LITERAL:
					if (is_start) {
						this.is_literal = "`";
					} else {
						this.is_literal = "";
					}
					this.renderer.on_node(FormatType.CODE, is_start);
					break;
				case FormatType.STRIKETHROUGH:
					this.renderer.on_node(FormatType.STRIKETHROUGH, is_start);
					break;
				case FormatType.TASK_LIST:
					// Task lists only send start (end is handled by list item)
					if (is_start) {
						this.renderer.on_node(FormatType.TASK_LIST, true);
					}
					break;
				case FormatType.TASK_LIST_DONE:
					// Task lists only send start (end is handled by list item)
					if (is_start) {
						this.renderer.on_node(FormatType.TASK_LIST_DONE, true);
					}
					break;
				case FormatType.LINK:
					// Handled in formatmap.eat_link(); no stack push
					break;
				case FormatType.HTML:
					if (is_start) {
						// HTML needs special handling - for now use OTHER
						// TODO: Parse HTML tag and attributes
						this.renderer.on_node(FormatType.OTHER, true, "html");
					}
					// HTML closing is handled in add_html()
					break;
				case FormatType.INVALID:
					// Should not reach here
					break;
				default:
					// Unknown format type
					break;
			}
		}

		/**
		 * Handles a newline: in fenced code sends it as code text; otherwise flushes
		 * accumulated text, ends the current block, and sends the newline as text.
		 * Updates chunk_pos and str (clears str when flushed).
		 */
		private void handle_line_break(ref int chunk_pos, ref string str)
		{
			if (this.current_block == FormatType.FENCED_CODE_QUOTE
				|| this.current_block == FormatType.FENCED_CODE_TILD) {
				this.renderer.on_node(FormatType.CODE_TEXT, false, "\n");
				this.at_line_start = true;
				chunk_pos += 1;
				return;
			}
			if (this.current_block == FormatType.TABLE) {
				this.do_block(false, FormatType.TABLE);
				this.current_block = FormatType.NONE;
				this.at_line_start = true;
				chunk_pos += 1;
				return;
			}
			// Reset inline formatting so next block starts clean (CommonMark: inline scoped per block)
			if (str != "") {
				this.renderer.on_node(FormatType.TEXT, false, str);
				str = "";
			}
			this.state_stack.clear();

			if (this.current_block != FormatType.NONE) {
				// Keep list open across newlines; we'll end it when we see a non-list line
				if (this.current_block != FormatType.ORDERED_LIST 
						&& this.current_block != FormatType.UNORDERED_LIST) {
					this.do_block(false, this.current_block);
					this.last_line_block = this.current_block;
					this.current_block = FormatType.NONE;
					this.is_literal = "";
				}
			}
			// Don't emit newline as TEXT when in a list (list items would get trailing \n and round-trip gets extra blank lines)
			if (this.current_block != FormatType.ORDERED_LIST && this.current_block != FormatType.UNORDERED_LIST) {
				this.renderer.on_node(FormatType.TEXT, false, "\n");
			}
			this.at_line_start = true;
			chunk_pos += 1;
		}
		
		/**
		 * Parse a string as inline only (no block handling). Uses formatmap.eat(), on_text, got_format, add_html;
		 * escape and code-span literal as in main parser; at end pops state_stack and emits closing format callbacks.
		 * Used for link text and table cells.
		 */
		public void process_inline(string text)
		{
			var pos = 0;
			var str = "";
			this.at_line_start = true;
			while (pos < text.length) {
				// Escape: \ + next char → emit next as literal, advance by 1 + next char byte length
				if (text.get_char(pos) == '\\' && pos + 1 < text.length) {
					this.renderer.on_node(FormatType.TEXT, false, str);
					str = "";
					this.renderer.on_node(FormatType.TEXT, false, text.get_char(pos + 1).to_string());
					pos += 1 + text.get_char(pos + 1).to_string().length;
					this.at_line_start = false;
					continue;
				}
				var saved_pos = pos;
				var c = text.get_char(pos);

				if (this.is_literal != "") {
					var result = this.formatmap.peek_literal(text, pos, true, this.is_literal);
					if (result == -1) {
						result = 0;
					}
					if (result == 0) {
						str += c.to_string();
						pos += c.to_string().length;
						this.at_line_start = false;
						continue;
					}
					this.renderer.on_node(FormatType.TEXT, false, str);
					str = "";
					this.state_stack.remove_at(this.state_stack.size - 1);
					this.do_format(false, this.is_literal.length == 1 ? FormatType.LITERAL : FormatType.CODE);
					this.is_literal = "";
					pos += result;
					this.at_line_start = false;
					continue;
				}

				// At line start - check start-of-line emphasis (*, _)
				if (this.at_line_start) {
					FormatType start_matched = FormatType.NONE;
					int start_byte_length = 0;
					var start_result = this.startmap.peek(text, pos, true, out start_matched, out start_byte_length);
					if (start_result > 0) {
						this.renderer.on_node(FormatType.TEXT, false, str);
						str = "";
						this.startmap.handle_start_result(start_result, start_matched, start_byte_length, ref pos, text, saved_pos, true);
						continue;
					}
				}

				// Left (opening) delimiter: must be preceded by whitespace
				if (str.length != 0 && c.isspace()) {
					this.renderer.on_node(FormatType.TEXT, false, str);
					str = "";
				}
				FormatType left_matched = FormatType.NONE;
				int left_byte_length = 0;
				var left_match = this.leftmap.peek(text, pos, true, out left_matched, out left_byte_length);
				if (left_match > 0) {
					this.leftmap.handle_left_result(left_match, left_matched, left_byte_length, ref pos, ref str, text, saved_pos, true);
					continue;
				}

				// Right (closing) delimiter: must be followed by whitespace or newline
				FormatType right_matched = FormatType.NONE;
				int right_byte_length = 0;
				var right_match = this.rightmap.peek(text, pos, true, out right_matched, out right_byte_length);
				if (right_match > 0) {
					this.rightmap.handle_right_result(right_match, right_matched, right_byte_length, ref pos, ref str, text, saved_pos, true);
					continue;
				}

				var matched_format = FormatType.NONE;
				var byte_length = 0;
				var match_len = this.formatmap.eat(text, pos, true, out matched_format, out byte_length);
				if (match_len == -1) {
					this.renderer.on_node(FormatType.TEXT, false, str);
					str = "";
					this.renderer.on_node(FormatType.TEXT, false, c.to_string());
					pos += c.to_string().length;
					this.at_line_start = false;
					continue;
				}
				if (match_len == 0) {
					str += c.to_string();
					pos += c.to_string().length;
					this.at_line_start = false;
					continue;
				}
				this.renderer.on_node(FormatType.TEXT, false, str);
				str = "";
				if (matched_format == FormatType.LINK) {
					// Inline context (e.g. table cell): try full link; if no match, emit 3 chars as literal.
					var seq_pos = pos + byte_length;
					var link_result = this.formatmap.eat_link(text, pos, seq_pos, true);
					if (link_result == -1) {
						this.renderer.on_node(FormatType.TEXT, false, c.to_string());
						pos += c.to_string().length;
						this.at_line_start = false;
						continue;
					}
					if (link_result == 0) {
						this.renderer.on_node(FormatType.TEXT, false, text.substring(pos, byte_length));
						pos += byte_length;
						this.at_line_start = false;
						continue;
					}
					this.formatmap.handle_link(text, pos, seq_pos, link_result);
					pos = link_result;
					this.at_line_start = false;
					continue;
				}
				if (matched_format != FormatType.HTML) {
					this.got_format(matched_format);
					pos += byte_length;
					this.at_line_start = false;
					continue;
				}
				var sub = text.substring(pos + byte_length);
				var rest = this.add_html(sub);
				pos += byte_length + (sub.length - rest.length);
				this.at_line_start = false;
			}
			for (var i = this.state_stack.size - 1; i >= 0; i--) {
				this.do_format(false, this.state_stack.get(i));
			}
			this.state_stack.clear();
			if (str != "") {
				this.renderer.on_node(FormatType.TEXT, false, str);
			}
		}

		/**
		 * Handles block start/end by calling the appropriate renderer method.
		 * 
		 * @param is_start True to start the block, false to end it
		 * @param block_type The block type
		 * @param lang Language for fenced code blocks (only used when is_start is true)
		 * @param fence_indent Leading indent for fenced code (e.g. "   "); only used when starting FENCED_CODE_QUOTE/TILD
		 */
		public void do_block(
			bool is_start,
			FormatType block_type,
			string lang = "", 
			string fence_indent = "", 
			int list_indent = 0)
		{
			var sl = lang.strip().length;

			switch (block_type) {
				case FormatType.HEADING_1:
					this.renderer.on_node(FormatType.HEADING_1, is_start);
					break;
				case FormatType.HEADING_2:
					this.renderer.on_node(FormatType.HEADING_2, is_start);
					break;
				case FormatType.HEADING_3:
					this.renderer.on_node(FormatType.HEADING_3, is_start);
					break;
				case FormatType.HEADING_4:
					this.renderer.on_node(FormatType.HEADING_4, is_start);
					break;
				case FormatType.HEADING_5:
					this.renderer.on_node(FormatType.HEADING_5, is_start);
					break;
				case FormatType.HEADING_6:
					this.renderer.on_node(FormatType.HEADING_6, is_start);
					break;
				case FormatType.PARAGRAPH:
					this.renderer.on_node(FormatType.PARAGRAPH, is_start);
					break;

				// we are going to send 1 as to lowest level of indentation
				// to make it a bit easier for the users to indent correctly.		
				case FormatType.UNORDERED_LIST:
					if (!is_start) {
						this.renderer.on_li(false);
						this.renderer.on_node_int(FormatType.LIST_ITEM, false, 0);
					}
					this.renderer.on_node_int(FormatType.UNORDERED_LIST, is_start, list_indent);
					break;
				case FormatType.ORDERED_LIST:
					if (!is_start) {
						this.renderer.on_li(false);
						this.renderer.on_node_int(FormatType.LIST_ITEM, false, 0);
					}
					this.renderer.on_node_int(FormatType.ORDERED_LIST, is_start, list_indent);
					break;
				case FormatType.FENCED_CODE_QUOTE:
				case FormatType.FENCED_CODE_TILD:
					this.renderer.on_node(block_type, is_start, lang, fence_indent);
					break;
				case FormatType.HORIZONTAL_RULE:
					this.renderer.on_node(FormatType.HORIZONTAL_RULE, false);
					break;
				case FormatType.BLOCKQUOTE:
					this.renderer.on_node_int(FormatType.BLOCKQUOTE, is_start, (int)(lang.length / 2));
					break;
				case FormatType.TABLE:
					// Table start is handled by TableState (feed_line emits on_table via on_node when emitting the first body row)
					if (!is_start) {
						this.renderer.on_node(FormatType.TABLE, false);
						this.table_state = null;
					}
					break;
				case FormatType.NONE:
					// No block to handle
					break;
				default:
					// Unknown block type
					break;
			}
		}

		public string add_html(string chunk)
		{
			// If chunk is empty, return "<" to be picked up next time
			if (chunk.length == 0) {
				return "<";
			}
			var pos = 0;
			var tag = "";
			var is_closing = chunk.get_char(pos) == '/';
			
			// Check if this is a closing tag (starts with '/')
			if (is_closing) {
				var ch = chunk.get_char(pos);
				pos += ch.to_string().length;
			}
			
			// Read all alphabetic characters - that's our tag
			while (pos < chunk.length) {
				var ch = chunk.get_char(pos);
				if (!ch.isalpha()) {
					break;
				}
				tag += ch.to_string();
				pos += ch.to_string().length;
			}
 
			// If we didn't get any tag (first char after '<' is not alpha), error condition
			if (tag.length == 0) {
				this.renderer.on_node(FormatType.TEXT, false, "<");
				return chunk;
			}
			
			// Check if we've reached the end
			if (pos >= chunk.length) {
				// let the next part call with it.
				return "<" + chunk;
			}
			
			// at this point we should eat white space
			var got_ws = false;
			while (pos < chunk.length) {
				var ch = chunk.get_char(pos);
				if (ch != ' ') {
					break;
				}
				got_ws = true;
				pos += ch.to_string().length;
			}
			// at this point we have the tag.. either we are looking for attributes or a closing tag <span> </span>

			// Next char should be '>' or space
			if (pos < chunk.length && chunk.get_char(pos) == '>') {
				// we got tag then '>' so we either fire on_node(HTML) with the tag and an empty attribute or on_end
				if (is_closing) {
					this.renderer.on_node(FormatType.HTML, false, tag, "");
				} else {
					this.renderer.on_node(FormatType.HTML, true, tag, "");
				}
				var ch = chunk.get_char(pos);
				var next_pos = pos + ch.to_string().length;
				return chunk.substring(next_pos, chunk.length - next_pos);
			}
			
			// if we are in closing and have got to this point then it's rubbish and we need to add it as text and return the left overs
			if (is_closing) {
				this.renderer.on_node(FormatType.TEXT, false, "</" + tag);
				return chunk.substring(pos, chunk.length - pos);
			}
			
			// if we did not get white space and it's not > then it's rubbish and we need to add it as text and return the left overs
			if (!got_ws) {
				this.renderer.on_node(FormatType.TEXT, false, "<" + chunk.substring(0, pos));
				return chunk.substring(pos, chunk.length - pos);
			}

			var attributes = "";
			// we are looking for two things now
			//   '>'  indicates end of the tag (we are not going to be clever and read the attribute format)
			//   '\n'  indicates the whole thing is rubbish and we need to add it as text and return the left overs
			// everything else is an attribute
			while (pos < chunk.length) {
				var ch = chunk.get_char(pos);
				if (ch == '>' || ch == '\n' || ch == '\r') {
					break;
				}
				attributes += ch.to_string();
				pos += ch.to_string().length;
			}
			
			if (pos >= chunk.length) {
				// not got there yet - still reading attributes
				return "<" + chunk;
			}
			
			if (chunk.get_char(pos) == '>') {
				this.renderer.on_node(FormatType.HTML, true, tag, attributes);
				var ch = chunk.get_char(pos);
				var next_pos = pos + ch.to_string().length;
				return chunk.substring(next_pos, chunk.length - next_pos);
			}
			
			// chunk[pos] == '\n' || chunk[pos] == '\r'
			this.renderer.on_node(FormatType.TEXT, false, "<" + chunk.substring(0, pos));
			return chunk.substring(pos, chunk.length - pos);
		}
 

	}
    // Mapping of character sequences to format types
    
     
    
     
    
} 

