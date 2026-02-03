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
		DEFINITION_LIST,
		INDENTED_CODE,
		FENCED_CODE_QUOTE,
		FENCED_CODE_TILD,
		BLOCKQUOTE,
		TABLE
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
		public FormatMap formatmap { get; set; default = new FormatMap(); }
		internal TableState? table_state { get; set; }
		public BlockMap blockmap { get; set; default = new BlockMap(); }
		internal Gee.ArrayList<FormatType> state_stack {
			get; set; default = new Gee.ArrayList<FormatType>(); }

		private string leftover_chunk = "";
		private bool in_literal = false;
		private FormatType last_line_block = FormatType.NONE;
		private FormatType current_block = FormatType.NONE;
		private bool at_line_start = true;
		
		/**
		 * Creates a new Parser instance.
		 * 
		 * @param renderer The RenderBase instance to call callbacks on
		 */
		public Parser(RenderBase renderer)
		{
			this.renderer = renderer;
		}
		

		public void flush()
		{
			this.in_literal = false;
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
			this.in_literal = false;
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
		private int peekHTML(string chunk, int chunk_pos, bool is_end_of_chunks)
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
			//GLib.debug("add(%s)", in_chunk);
			var chunk = this.leftover_chunk + in_chunk; // Prepend leftover_chunk so it's processed first
			this.leftover_chunk = ""; // Clear leftover_chunk after using it
			var chunk_pos = 0;
			var escape_next = false;
			var str = "";
			//GLib.debug("  [str] INIT: str='%s' (empty)", str);
			
			while (chunk_pos < chunk.length) {
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
					//GLib.debug("  [code] In code block, at_line_start=%s, chunk_pos=%d, char='%s'", this.at_line_start.to_string(), chunk_pos, chunk_pos < chunk.length ? chunk.get_char(chunk_pos).to_string() : "EOF");
					if (!this.at_line_start) {
						// Not at line start - collect code text
						// First check if remaining chunk doesn't contain newline - send everything and return
						var remaining = chunk.substring(chunk_pos, chunk.length - chunk_pos);
						if (!remaining.contains("\n")) {
							this.renderer.on_code_text(remaining);
							return;
						}
						
						// Remaining chunk contains newline - get text before newline and send it
						var newline_pos = chunk.index_of_char('\n', chunk_pos);
						var code_text = chunk.substring(chunk_pos, newline_pos - chunk_pos);
						this.renderer.on_code_text(code_text);
						// Move pos to newline (will be handled in next iteration)
						chunk_pos = newline_pos;
						continue;
					}
					
					// At line start - check for closing fence
					var fence_result = this.blockmap.peekFencedEnd(chunk, chunk_pos, this.current_block, is_end_of_chunks);
					if (this.handle_fence_result(fence_result, ref chunk_pos, chunk)) {
						return;
					}
					continue;
				}
				
		
				 
				
				// In table: at line start, consume one full line and either feed as row or end table
				if (this.at_line_start && this.current_block == FormatType.TABLE) {
					var newline_pos = chunk.index_of_char('\n', chunk_pos);
					if (newline_pos == -1) {
						if (!is_end_of_chunks) {
							// If we already have content and it doesn't start with |, this line can't be a table row – exit table now
							var rest = chunk.substring(chunk_pos, chunk.length - chunk_pos);
							var stripped = rest.strip();
							if (stripped != "" && !stripped.has_prefix("|")) {
								this.do_block(false, FormatType.TABLE);
								this.current_block = FormatType.NONE;
								this.in_literal = false;
								continue;
							}
							this.leftover_chunk = chunk.substring(chunk_pos, chunk.length - chunk_pos);
							return;
						}
						newline_pos = chunk.length;
					}
					var line_len = newline_pos - chunk_pos;
					var line = chunk.substring(chunk_pos, line_len);
					if (line.contains("|")) {
						this.table_state.feed_line(line);
						chunk_pos = newline_pos;
						if (chunk_pos < chunk.length) {
							chunk_pos += chunk.get_char(chunk_pos).to_string().length;
						}
						this.at_line_start = true;
						continue;
					}
					this.do_block(false, FormatType.TABLE);
					this.current_block = FormatType.NONE;
					this.in_literal = false;
					// do_block(TABLE, false) clears table_state; do not advance chunk_pos – re-process this line as non-table
					continue;
				}

				// At line start - check for block markers
				if (this.at_line_start) {
					var saved_chunk_pos = chunk_pos;
					string block_lang = "";
					FormatType matched_block = FormatType.NONE;
					int byte_length = 0;
					var block_match = this.blockmap.peek(
						chunk,
						chunk_pos,
						is_end_of_chunks,
						this.last_line_block,
						out block_lang,
						out matched_block,
						out byte_length
					);
					if (this.handle_block_result(
						block_match,
						block_lang,
						matched_block,
						byte_length,
						ref chunk_pos,
						chunk,
						saved_chunk_pos,
						is_end_of_chunks
					)) {
						return;
					}
					continue;
				}
				
				
				if (escape_next) {
					var char_str = c.to_string();
					str += char_str;
					//GLib.debug("  [str] ADD escaped char '%s': str='%s'", char_str.replace("\n", "\\n").replace("\r", "\\r"), str);
					escape_next = false;
					chunk_pos += c.to_string().length;
					continue;
				}
				
				if (c == '\\') {
					escape_next = true;
					chunk_pos += c.to_string().length;
					continue;
				}
				
				// Use formatmap.eat to detect format sequences (needed even in literal mode for backtick toggle)
				FormatType matched_format = FormatType.NONE;
				int unused_byte_length;
				var match_len = this.formatmap.eat(
					chunk,
					chunk_pos,
					is_end_of_chunks,
					out matched_format,
					out unused_byte_length
				);
				// If in literal mode, ignore all matches except LITERAL (to close literal mode)
				if (this.in_literal) {
					match_len = (matched_format != FormatType.LITERAL) ? 0 : 1;
				}

				if (this.handle_format_result(
					match_len,
					matched_format,
					c, 
					ref chunk_pos, 
					ref str, 
					ref chunk, 
					is_end_of_chunks)) {
					return;
				}
				continue;
			}
			
			// Flush any remaining text
			//GLib.debug("  [str] FINAL FLUSH: str='%s'", str);
			this.renderer.on_text(str);
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
		 * For BOLD_ITALIC, handles both bold and italic states correctly.
		 * 
		 * @param is_start True to start the format, false to end it
		 * @param format_type The format type
		 */
		internal void do_format(bool is_start, FormatType format_type)
		{
			switch (format_type) {
				case FormatType.BOLD_ITALIC:
					if (is_start) {
						// Push both bold and italic states
						this.renderer.on_strong(true);
						this.renderer.on_em(true);
					} else {
						// BOLD_ITALIC opened two states, so close both in reverse order
						this.renderer.on_em(false); // Close italic
						this.renderer.on_strong(false); // Close bold
					}
					break;
				case FormatType.ITALIC:
					this.renderer.on_em(is_start);
					break;
				case FormatType.BOLD:
					this.renderer.on_strong(is_start);
					break;
				case FormatType.CODE:
					this.renderer.on_code_span(is_start);
					break;
				case FormatType.LITERAL:
					// Toggle in_literal flag when entering/leaving code span
					this.in_literal = is_start;
					this.renderer.on_code_span(is_start);
					break;
				case FormatType.STRIKETHROUGH:
					this.renderer.on_del(is_start);
					break;
				case FormatType.TASK_LIST:
					// Task lists only send start (end is handled by list item)
					if (is_start) {
						//GLib.debug("Parser.do_format: TASK_LIST called");
						this.renderer.on_task_list(true, false);
					}
					break;
				case FormatType.TASK_LIST_DONE:
					// Task lists only send start (end is handled by list item)
					if (is_start) {
						//GLib.debug("Parser.do_format: TASK_LIST_DONE called");
						this.renderer.on_task_list(true, true);
					}
					break;
				case FormatType.HTML:
					if (is_start) {
						// HTML needs special handling - for now use on_other
						// TODO: Parse HTML tag and attributes
						this.renderer.on_other(true, "html");
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
				this.renderer.on_code_text("\n");
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
			if (str != "") {
				this.renderer.on_text(str);
				str = "";
			}
			if (this.current_block != FormatType.NONE) {
				this.do_block(false, this.current_block);
				this.last_line_block = this.current_block;
				this.current_block = FormatType.NONE;
				this.in_literal = false;
			}
			this.renderer.on_text("\n");
			this.at_line_start = true;
			chunk_pos += 1;
		}
		
		/**
		 * Handles block peek result. Caller calls blockmap.peek() then this.
		 * Updates chunk_pos when a block is consumed.
		 * @return true (need more characters; leftover_chunk set), false (to keep processing the rest of the chunk)
		 */
		private bool handle_block_result(
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
				this.leftover_chunk = chunk.substring(saved_chunk_pos, chunk.length - saved_chunk_pos);
				return true;
			}
			if (block_match == 0) {
				// No block detected - start a paragraph
				if (this.current_block == FormatType.NONE) {
					this.current_block = FormatType.PARAGRAPH;
					this.do_block(true, FormatType.PARAGRAPH);
				}
				this.at_line_start = false;
				return false;
			}
			var seq_pos = chunk_pos + byte_length;
			switch (matched_block) {
				case FormatType.HORIZONTAL_RULE:
					// HR only if rest of line (after ***/___/---) is whitespace. Otherwise treat as paragraph.
					var newline_pos = chunk.index_of_char('\n', seq_pos);
					var rest = newline_pos != -1
						? chunk.substring(seq_pos, newline_pos - seq_pos)
						: chunk.substring(seq_pos, chunk.length - seq_pos);
					if (rest.strip() != "") {
						if (this.current_block == FormatType.NONE) {
							this.current_block = FormatType.PARAGRAPH;
							this.do_block(true, FormatType.PARAGRAPH);
						}
						this.at_line_start = false;
						return false;
					}
					if (newline_pos == -1 && !is_end_of_chunks) {
						this.leftover_chunk = chunk.substring(saved_chunk_pos, chunk.length - saved_chunk_pos);
						return true;
					}
					this.do_block(true, matched_block);
					if (newline_pos != -1) {
						var newline_char = chunk.get_char(newline_pos);
						this.at_line_start = true;
						chunk_pos = newline_pos + newline_char.to_string().length;
					} else {
						this.at_line_start = true;
						chunk_pos = (int) chunk.length;
					}
					return false;

				case FormatType.FENCED_CODE_QUOTE:
				case FormatType.FENCED_CODE_TILD:
					this.current_block = matched_block;
					this.do_block(true, matched_block, block_lang);
					this.at_line_start = true;
					chunk_pos = seq_pos;
					return false;

				case FormatType.BLOCKQUOTE:
					if (this.current_block != FormatType.NONE) {
						this.at_line_start = false;
						return false;
					}
					this.current_block = matched_block;
					var marker_string = chunk.substring(chunk_pos, byte_length);
					this.do_block(true, matched_block, marker_string);
					chunk_pos = seq_pos;
					return false;

				case FormatType.ORDERED_LIST:
				case FormatType.UNORDERED_LIST:
					this.current_block = matched_block;
					var list_marker = chunk.substring(chunk_pos, byte_length);
					this.do_block(true, matched_block, list_marker);
					this.at_line_start = false;
					chunk_pos = seq_pos;
					return false;

				case FormatType.TABLE:
					this.current_block = FormatType.TABLE;
					this.table_state = new TableState(this);
					var consumed_block = chunk.substring(chunk_pos, byte_length);
					var lines = consumed_block.split("\n");
					// BlockMap guarantees 3 lines; ensure we have at least 3
					this.table_state.feed_line(lines[0]);
					this.table_state.feed_line(lines[1]);
					this.table_state.feed_line(lines[2]);
					this.at_line_start = true;
					chunk_pos = seq_pos;
					return false;

				default:
					this.current_block = matched_block;
					this.do_block(true, matched_block, block_lang);
					this.at_line_start = false;
					chunk_pos = seq_pos;
					return false;
			}
		}

		/**
		 * Handles fenced-code closing fence result. Updates chunk_pos when consuming input.
		 * @param fence_result Result from blockmap.peekFencedEnd (-1 need more, 0 not fence, 3 match)
		 * @param chunk_pos Updated to position after consumed input
		 * @param chunk The current chunk
		 * @return true (need more characters or flushed text; leftover_chunk may be set), false to keep processing the rest of the chunk
		 */
		private bool handle_fence_result(int fence_result, ref int chunk_pos, string chunk)
		{
			if (fence_result == -1) {
				this.leftover_chunk = chunk.substring(chunk_pos, chunk.length - chunk_pos);
				return true;
			}
			if (fence_result == 0) {
				var remaining = chunk.substring(chunk_pos, chunk.length - chunk_pos);
				if (!remaining.contains("\n")) {
					this.renderer.on_code_text(remaining);
					return true;
				}
				var newline_pos = chunk.index_of_char('\n', chunk_pos);
				var code_text = chunk.substring(chunk_pos, newline_pos - chunk_pos);
				this.renderer.on_code_text(code_text);
				chunk_pos = newline_pos;
				this.at_line_start = false;
				return false;
			}
			// fence_result > 0: found closing fence - end the block
			var after_fence = chunk_pos + 3;
			var rest = chunk.substring(after_fence, chunk.length - after_fence);
			var newline_pos_in_substring = rest.index_of_char('\n');
			chunk_pos = (newline_pos_in_substring != -1) ? 
				(after_fence + newline_pos_in_substring + 1) : after_fence;
			this.do_block(false, this.current_block);
			this.last_line_block = this.current_block;
			this.current_block = FormatType.NONE;
			this.in_literal = false;
			this.at_line_start = true;
			return false;
		}

		/**
		 * Handles format-match result from formatmap.eat. Updates chunk_pos, str, and chunk when consuming input.
		 * @param match_len Result length (-1 need more, 0 no match, >0 match)
		 * @param matched_format The matched format type
		 * @param c Current character (used when match_len == 0)
		 * @param chunk_pos Updated to position after consumed input
		 * @param str Accumulated text buffer (flushed on match, appended to on no match)
		 * @param chunk May be replaced when processing HTML; caller uses updated chunk
		 * @param is_end_of_chunks End-of-stream indicator
		 * @return true (need more characters or flushed; leftover_chunk may be set), false to keep processing the rest of the chunk
		 */
		private bool handle_format_result(
			int match_len,
			FormatType matched_format,
			unichar c,
			ref int chunk_pos,
			ref string str,
			ref string chunk,
			bool is_end_of_chunks
		) {
			if (match_len == -1) {
				this.renderer.on_text(str);
				this.leftover_chunk = chunk.substring(chunk_pos, chunk.length - chunk_pos);
				return true;
			}
			if (match_len == 0) {
				var char_str = c.to_string();
				str += char_str;
				chunk_pos += c.to_string().length;
				return false;
			}
			this.renderer.on_text(str);
			str = "";
			var seq_pos = chunk_pos;
			for (int i = 0; i < match_len; i++) {
				var ch = chunk.get_char(seq_pos);
				seq_pos += ch.to_string().length;
			}
			if (matched_format != FormatType.HTML) {
				this.got_format(matched_format);
				chunk_pos = seq_pos;
				return false;
			}
			var html_res = this.peekHTML(chunk, seq_pos, is_end_of_chunks);
			if (html_res == -1) {
				this.leftover_chunk = chunk.substring(chunk_pos, chunk.length - chunk_pos);
				return true;
			}
			if (html_res == 0) {
				var html_text = chunk.substring(chunk_pos, seq_pos - chunk_pos);
				str += html_text;
				chunk_pos = seq_pos;
				return false;
			}
			chunk_pos = seq_pos;
			chunk = this.add_html(chunk.substring(chunk_pos, chunk.length - chunk_pos));
			chunk_pos = 0;
			if (chunk.length > 0 && chunk.get_char(0) == '<' && is_end_of_chunks) {
				return false;
			}
			if (chunk.length > 0 && chunk.get_char(0) == '<') {
				this.leftover_chunk = chunk;
				return true;
			}
			return false;
		}

		/**
		 * Handles block start/end by calling the appropriate renderer method.
		 * 
		 * @param is_start True to start the block, false to end it
		 * @param block_type The block type
		 * @param lang Language for fenced code blocks (only used when is_start is true)
		 */
		private void do_block(bool is_start, FormatType block_type, string lang = "")
		{
			var sl = lang.strip().length;

			switch (block_type) {
				case FormatType.HEADING_1:
					this.renderer.on_h(is_start, 1);
					break;
				case FormatType.HEADING_2:
					this.renderer.on_h(is_start, 2);
					break;
				case FormatType.HEADING_3:
					this.renderer.on_h(is_start, 3);
					break;
				case FormatType.HEADING_4:
					this.renderer.on_h(is_start, 4);
					break;
				case FormatType.HEADING_5:
					this.renderer.on_h(is_start, 5);
					break;
				case FormatType.HEADING_6:
					this.renderer.on_h(is_start, 6);
					break;
				case FormatType.PARAGRAPH:
					this.renderer.on_p(is_start);
					break;

				// we are going to send 1 as to lowest level of indentation
				// to make it a bit easier for the users to indent correctly.		
				case FormatType.UNORDERED_LIST:
					this.renderer.on_ul(is_start, (uint)((lang.length - sl + 1) / 2));
					break;
				case FormatType.ORDERED_LIST:
					this.renderer.on_ol(is_start, (uint)((lang.length - sl + 1) / 2));
				break;
				case FormatType.FENCED_CODE_QUOTE:
				case FormatType.FENCED_CODE_TILD:
					this.renderer.on_code_block(is_start, lang);
					break;
				case FormatType.HORIZONTAL_RULE:
					this.renderer.on_hr();
					break;
				case FormatType.BLOCKQUOTE:
			
					this.renderer.on_quote(is_start, lang.length /2 );
					break;
				case FormatType.TABLE:
					// Table start is handled by TableState (feed_line emits on_table(true) when emitting the first body row)
					if (!is_start) {
						this.renderer.on_table(false);
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

		internal string add_html(string chunk)
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
				this.renderer.on_text("<");
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
				// we got tag then '>' so we either fire on_html with the tag and an empty attribute or on_end
				if (is_closing) {
					this.renderer.on_html(false, tag, "");
				} else {
					this.renderer.on_html(true, tag, "");
				}
				var ch = chunk.get_char(pos);
				var next_pos = pos + ch.to_string().length;
				return chunk.substring(next_pos, chunk.length - next_pos);
			}
			
			// if we are in closing and have got to this point then it's rubbish and we need to add it as text and return the left overs
			if (is_closing) {
				this.renderer.on_text("</" + tag);
				return chunk.substring(pos, chunk.length - pos);
			}
			
			// if we did not get white space and it's not > then it's rubbish and we need to add it as text and return the left overs
			if (!got_ws) {
				this.renderer.on_text("<" + chunk.substring(0, pos));
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
				this.renderer.on_html(true, tag, attributes);
				var ch = chunk.get_char(pos);
				var next_pos = pos + ch.to_string().length;
				return chunk.substring(next_pos, chunk.length - next_pos);
			}
			
			// chunk[pos] == '\n' || chunk[pos] == '\r'
			this.renderer.on_text("<" + chunk.substring(0, pos));
			return chunk.substring(pos, chunk.length - pos);
		}
 

	}
    // Mapping of character sequences to format types
    
     
    
     
    
} 

