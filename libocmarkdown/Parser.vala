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

namespace Markdown
{
	
	
	
 
    private enum FormatType {
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
		ORDERED_LIST_1,
		ORDERED_LIST__1,
		ORDERED_LIST___1,
		ORDERED_LIST____1,
		ORDERED_LIST_____1,
		ORDERED_LIST_11,
		ORDERED_LIST__11,
		ORDERED_LIST___11,
		ORDERED_LIST____11,
		ORDERED_LIST_____11,
		CONTINUE_LIST,
		TASK_LIST,
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
		
		private static Gee.HashMap<string, FormatType> format_map;
		private static Gee.HashMap<string, FormatType> block_map;
		
	 
		static construct {
			setup_maps();
		}
		
		private static void setup_maps() {
			format_map = new Gee.HashMap<string, FormatType>();
			
			// Asterisk sequences (most common)
			format_map["*"] = FormatType.ITALIC;
			format_map["**"] = FormatType.BOLD;
			format_map["***"] = FormatType.BOLD_ITALIC;
			
			// Underscore sequences (alternative syntax)
			format_map["_"] = FormatType.ITALIC;
			format_map["__"] = FormatType.BOLD;
			format_map["___"] = FormatType.BOLD_ITALIC;
			
			// Code and inline code
			format_map["`"] = FormatType.LITERAL;
			format_map["``"] = FormatType.CODE; // Some parsers support double backtick
			
			// Strikethrough (GFM)
			format_map["~"] = FormatType.INVALID;
			format_map["~~"] = FormatType.STRIKETHROUGH;
			
			// Highlight (some markdown flavors)
			// format_map["=="] = FormatType.HIGHLIGHT;
			// format_map["="] = FormatType.INVALID;
			
			// Superscript/subscript (some flavors)
			// format_map["^"] = FormatType.SUPERSCRIPT;
			// Note: "~" for subscript conflicts with "~~" for strikethrough
			// Single "~" is not valid, so we don't map it
			
			// Task list checkboxes: [ ], [x] (GFM)
			format_map["[ ]"] = FormatType.TASK_LIST;
			format_map["[x]"] = FormatType.TASK_LIST;
			
			format_map["<"] = FormatType.HTML;
			
			block_map = new Gee.HashMap<string, FormatType>();
			
			// Headings: # Heading 1 to ###### Heading 6
			block_map["#"] = FormatType.HEADING_1;
			block_map["##"] = FormatType.HEADING_2;
			block_map["###"] = FormatType.HEADING_3;
			block_map["####"] = FormatType.HEADING_4;
			block_map["#####"] = FormatType.HEADING_5;
			block_map["######"] = FormatType.HEADING_6;
			
			// Horizontal Rules: ---, ***, ___
			block_map["--"] = FormatType.INVALID;
			block_map["---"] = FormatType.HORIZONTAL_RULE;
			block_map["**"] = FormatType.INVALID;
			block_map["***"] = FormatType.HORIZONTAL_RULE;
			block_map["__"] = FormatType.INVALID;
			block_map["___"] = FormatType.HORIZONTAL_RULE;
			
			// Paragraphs: Any text separated by blank lines
			// (handled implicitly, no marker needed)
			
			// Unordered Lists: - item, * item, + item
			block_map["-"] = FormatType.INVALID;
			block_map["- "] = FormatType.UNORDERED_LIST;
			block_map["* "] = FormatType.UNORDERED_LIST;
			block_map["+"] = FormatType.INVALID;
			block_map["+ "] = FormatType.UNORDERED_LIST;
			
			// Ordered Lists: 1. item, 2. item, etc. (treat any number as 1.)
			// Need both "1." and "11." to handle single and double digit numbers
			block_map["1"] = FormatType.INVALID;
			block_map["1."] = FormatType.INVALID;
			block_map["1. "] = FormatType.ORDERED_LIST_1;
			block_map["11"] = FormatType.INVALID;
			block_map["11."] = FormatType.INVALID;
			block_map["11. "] = FormatType.ORDERED_LIST_11;
			// Indented versions: 1-4 spaces before number
			block_map[" 1"] = FormatType.INVALID;
			block_map[" 1."] = FormatType.INVALID;
			block_map[" 1. "] = FormatType.ORDERED_LIST__1;
			block_map["  1"] = FormatType.INVALID;
			block_map["  1."] = FormatType.INVALID;
			block_map["  1. "] = FormatType.ORDERED_LIST___1;
			block_map["   1"] = FormatType.INVALID;
			block_map["   1."] = FormatType.INVALID;
			block_map["   1. "] = FormatType.ORDERED_LIST____1;
			block_map["    1"] = FormatType.INVALID;
			block_map["    1."] = FormatType.INVALID;
			block_map["    1. "] = FormatType.ORDERED_LIST_____1;
			block_map[" 11"] = FormatType.INVALID;
			block_map[" 11."] = FormatType.INVALID;
			block_map[" 11. "] = FormatType.ORDERED_LIST__11;
			block_map["  11"] = FormatType.INVALID;
			block_map["  11."] = FormatType.INVALID;
			block_map["  11. "] = FormatType.ORDERED_LIST___11;
			block_map["   11"] = FormatType.INVALID;
			block_map["   11."] = FormatType.INVALID;
			block_map["   11. "] = FormatType.ORDERED_LIST____11;
			block_map["    11"] = FormatType.INVALID;
			block_map["    11."] = FormatType.INVALID;
			block_map["    11. "] = FormatType.ORDERED_LIST_____11;
			
			// Continue list: 2 spaces to continue list items
			block_map[" "] = FormatType.INVALID;
			block_map["  "] = FormatType.CONTINUE_LIST;
			
			// Task Lists: - [ ], - [x] (GFM)
			// (handled by pattern matching with - [)
			
			// Definition Lists: (some flavors)
			// (handled by pattern matching)
			
			// Indented Code: 4 spaces or 1 tab
			// block_map["   "] = FormatType.INVALID;
			// block_map["    "] = FormatType.INDENTED_CODE;
			// block_map["\t"] = FormatType.INDENTED_CODE;
			
			// Fenced Code: ``` or ~~~ with optional language
			block_map["`"] = FormatType.INVALID;
			block_map["``"] = FormatType.INVALID;
			block_map["```"] = FormatType.FENCED_CODE_QUOTE;
			block_map["~"] = FormatType.INVALID;
			block_map["~~"] = FormatType.INVALID;
			block_map["~~~"] = FormatType.FENCED_CODE_TILD;
			
			// Code Attributes: ```python, ``` {.language-python}
			// (handled as part of FENCED_CODE processing)
			
			// Blockquotes: > quote text
			// block_map[">"] = FormatType.INVALID;
			// block_map["> "] = FormatType.BLOCKQUOTE;
			
			// Tables: | Header | Header | with | --- | --- | (GFM)
			// block_map["|"] = FormatType.INVALID;
			// block_map["| "] = FormatType.TABLE;
		} 

		
	private RenderBase renderer;
	private Gee.ArrayList<FormatType> state_stack { set; get; default = new Gee.ArrayList<FormatType>(); }
 
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
		 * Determines if characters at a given position match a format tag.
		 * Uses a loop-based approach to handle variable-length format sequences.
		 * 
		 * @param chunk The text chunk to examine
		 * @param chunk_pos The position in the chunk to check
		 * @param is_end_of_chunks If true, format markers at the end are treated as definitive
		 * @param matched_format Output parameter for the matched format type (NONE if no match)
		 * @return 1-N: Length of the match, 0: No match found, -1: Cannot determine (need more characters)
		 */
		private int peekFormat(
			string chunk, 
			int chunk_pos, 
			bool is_end_of_chunks,
			out FormatType matched_format
		) {
			matched_format = FormatType.NONE;
			// Check bounds
			if (chunk_pos >= chunk.length) {
				return 0;
			}
			
			// Check if single character is in format_map
			var first_char = chunk.get_char(chunk_pos);
			var single_char = first_char.to_string();
			// Optimize: skip has_key check if character is alphabetic (format markers are typically punctuation)
			if (first_char.isalpha() || !format_map.has_key(single_char)) {
				return 0; // No match
			}
			
			// Handle LITERAL (backtick) - return match length 1, don't add to text
			if (format_map.get(single_char) == FormatType.LITERAL) {
				matched_format = FormatType.LITERAL;
				return 1; // Return 1 to indicate match, but don't add backtick to text
			}
			
			// If in literal mode, ignore all other format matches
			if (this.in_literal) {
				return 0; // Return 0 so caller will treat as text
			}
			
			// Edge case: At end of chunk
			var ch = chunk.get_char(chunk_pos);
			var next_pos = chunk_pos + ch.to_string().length;
			if (next_pos >= chunk.length) {
				if (!is_end_of_chunks) {
					return -1; // Might be longer match
				}
				// At end of chunks - check if single char FormatType is INVALID → return 0
				matched_format = format_map.get(single_char);
				if (matched_format == FormatType.INVALID) {
					return 0;
				}
				return 1; // Definitive single char match
			}
			
			// Loop-based sequence matching
			int max_match_length = 0;
			int char_count = 0;
			var sequence = "";
			
			for (var cp = chunk_pos; cp < chunk.length; ) {
				// Build sequence incrementally by appending current character
				var char_at_cp = chunk.get_char(cp);
				sequence += char_at_cp.to_string();
				cp += char_at_cp.to_string().length;
				char_count++;
				
				// Optimize: skip has_key check if last character is alphabetic
				var last_char = char_at_cp;
				if (last_char.isalpha() || !format_map.has_key(sequence)) {
					// Sequence not in format_map - return longest valid match found (0 if none)
					return max_match_length;
				}
				
				// Sequence is in format_map
				matched_format = format_map.get(sequence);
 				
				// If FormatType is NOT INVALID, update max_match_length
				if (matched_format != FormatType.INVALID) {
					max_match_length = char_count;
				}
			}
			
			// Reached end of chunk
			if (!is_end_of_chunks) {
				// Not end of chunks - might be longer match
				return -1;
			}
			// At end of chunks - return what we found (0 if only INVALID matches)
			return max_match_length;
		}

		/**
		 * Determines if characters at a given position match a block tag.
		 * Uses a loop-based approach to handle variable-length block sequences.
		 * Includes number normalization for ordered lists.
		 * 
		 * @param chunk The text chunk to examine
		 * @param chunk_pos The position in the chunk to check
		 * @param is_end_of_chunks If true, format markers at the end are treated as definitive
		 * @param lang_out Output parameter for fenced code language (empty string if not present)
		 * @param matched_block Output parameter for the matched block type (NONE if no match)
		 * @return 1-N: Length of the match, 0: No match found, -1: Cannot determine (need more characters)
		 */
		private int peekBlock(
			string chunk, 
			int chunk_pos, 
			bool is_end_of_chunks,
			out string lang_out,
			out FormatType matched_block,
			out int byte_length
		) {
			lang_out = "";
			matched_block = FormatType.NONE;
			byte_length = 0;
			// Check bounds
			if (chunk_pos >= chunk.length) {
				return 0;
			}
			
			// Check if single character is in block_map
			var first_char = chunk.get_char(chunk_pos);
			var single_char = first_char.isdigit() ? "1" : first_char.to_string();
			// Optimize: skip has_key check if character is alphabetic (block markers are typically punctuation/spaces)
			// Note: we allow digits and spaces as they can be part of block markers (ordered lists, indented code)
			if (first_char.isalpha() || !block_map.has_key(single_char)) {
				return 0; // No match
			}
			
			// Edge case: At end of chunk
			var ch = chunk.get_char(chunk_pos);
			var next_pos = chunk_pos + ch.to_string().length;
			if (next_pos >= chunk.length) {
				if (!is_end_of_chunks) {
					return -1; // Might be longer match
				}
				// At end of chunks - check if single char FormatType is INVALID → return 0
				matched_block= block_map.get(single_char);
				if (matched_block == FormatType.INVALID) {
					return 0;
				}
				byte_length = next_pos - chunk_pos;
				return 1; // Definitive single char match
			}
			
			// Loop-based sequence matching
			int max_match_length = 0;
			int char_count = 0;
			var sequence = "";
			
			for (var cp = chunk_pos; cp < chunk.length; ) {
				// Build sequence incrementally by appending current character
				var char_at_cp = chunk.get_char(cp);
				// Normalize digits to '1' for ordered list matching
				sequence += char_at_cp.isdigit() ? "1" : char_at_cp.to_string();
				cp += char_at_cp.to_string().length;
				char_count++;
				
				// Optimize: skip has_key check if last character is alphabetic
				// Note: we allow digits and spaces as they can be part of block markers
				var last_char = char_at_cp;
				if (last_char.isalpha() || !block_map.has_key(sequence)) {
					// Sequence not in block_map - return longest valid match found (0 if none)
					return max_match_length;
				}
				
				// Sequence is in block_map
				
				matched_block = block_map.get(sequence);
				
				// Special handling for fenced code blocks - need to see newline
				if (matched_block == FormatType.FENCED_CODE_QUOTE
					 || matched_block == FormatType.FENCED_CODE_TILD) {
					// Check if chunk contains a newline - if not, need more data
					if (!chunk.contains("\n")) {
						return -1;
					}
					
					// Find the newline position
					var newline_pos = chunk.index_of_char('\n', chunk_pos);
					if (newline_pos == -1) {
						return -1;
					}
					
					// Extract language if present (substring from after fence to before \n)
					var newline_char = chunk.get_char(newline_pos);
					var newline_byte_len = newline_char.to_string().length;
					byte_length = newline_pos + newline_byte_len - chunk_pos;
					if (cp >= newline_pos) {
						// No language, just return the length to consume
						return newline_pos - chunk_pos + 1;
					}
					
					var unstripped_lang = chunk.substring(cp, newline_pos - cp);
					
					lang_out = unstripped_lang.strip();
					
					// Return the length to consume: from chunk_pos to after newline
					// Use byte positions directly
					return newline_pos - chunk_pos + 1;
				}
				
				// Check if CONTINUE_LIST is valid (only if last line was ORDERED_LIST or UNORDERED_LIST)
				if (matched_block == FormatType.CONTINUE_LIST) {
					if (this.last_line_block != FormatType.ORDERED_LIST && 
					    this.last_line_block != FormatType.ORDERED_LIST_1 &&
					    this.last_line_block != FormatType.ORDERED_LIST__1 &&
					    this.last_line_block != FormatType.ORDERED_LIST___1 &&
					    this.last_line_block != FormatType.ORDERED_LIST____1 &&
					    this.last_line_block != FormatType.ORDERED_LIST_____1 &&
					    this.last_line_block != FormatType.ORDERED_LIST_11 &&
					    this.last_line_block != FormatType.ORDERED_LIST__11 &&
					    this.last_line_block != FormatType.ORDERED_LIST___11 &&
					    this.last_line_block != FormatType.ORDERED_LIST____11 &&
					    this.last_line_block != FormatType.ORDERED_LIST_____11 &&
					    this.last_line_block != FormatType.UNORDERED_LIST) {
						// CONTINUE_LIST not valid - return longest valid match found (0 if none)
						return max_match_length;
					}
				}
				
				// If FormatType is NOT INVALID, update max_match_length
				if (matched_block != FormatType.INVALID) {
					max_match_length = char_count;
					byte_length = cp - chunk_pos;
				}
			}
			
			// Reached end of chunk
			if (!is_end_of_chunks) {
				// Not end of chunks - might be longer match
				return -1;
			}
			// At end of chunks - return what we found (0 if only INVALID matches)
			return max_match_length;
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
			GLib.debug("add(%s)", in_chunk);
			var chunk = this.leftover_chunk + in_chunk; // Prepend leftover_chunk so it's processed first
			this.leftover_chunk = ""; // Clear leftover_chunk after using it
			var chunk_pos = 0;
			var escape_next = false;
			var str = "";
			GLib.debug("  [str] INIT: str='%s' (empty)", str);
			
			while (chunk_pos < chunk.length) {
				var c = chunk.get_char(chunk_pos);
				
				// Handle newline - end current block and prepare for next line
				if (c == '\n') {
					// If we're in a fenced code block, send the newline as code text and set at_line_start
					if (this.current_block == FormatType.FENCED_CODE_QUOTE || this.current_block == FormatType.FENCED_CODE_TILD) {
						this.renderer.on_code_text("\n");
						this.at_line_start = true;
						chunk_pos += 1; // \n is always 1 byte
						escape_next = false;
						continue;
					}
					
				// Not in fenced code - flush any accumulated text before closing block
				GLib.debug("  [str] NEWLINE: str='%s', current_block=%s", str, this.current_block.to_string());
				if (str != "") {
					GLib.debug("  [str] FLUSH before block close: str='%s'", str);
					this.renderer.on_text(str);
					str = "";
					GLib.debug("  [str] RESET after flush: str='%s'", str);
				} else {
					GLib.debug("  [str] EMPTY at newline - nothing to flush");
				}
				
				// End current block if any
				if (this.current_block != FormatType.NONE) {
					this.do_block(false, this.current_block);
					this.last_line_block = this.current_block;
					this.current_block = FormatType.NONE;
				}
					
					// Pass the newline as text to the renderer
					this.renderer.on_text("\n");
					
					// Set at_line_start for next iteration
					this.at_line_start = true;
					chunk_pos += 1; // \n is always 1 byte
					escape_next = false;
					continue;
				}
				
				// If we're in a fenced code block, check for closing fence only at line start
				if (this.current_block == FormatType.FENCED_CODE_QUOTE || this.current_block == FormatType.FENCED_CODE_TILD) {
					GLib.debug("  [code] In code block, at_line_start=%s, chunk_pos=%d, char='%s'", this.at_line_start.to_string(), chunk_pos, chunk_pos < chunk.length ? chunk.get_char(chunk_pos).to_string() : "EOF");
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
					var fence_result = this.peekFencedEnd(chunk, chunk_pos, this.current_block, is_end_of_chunks);
					if (fence_result == -1) {
						// Need more data - standard -1 behavior: save to leftover_chunk and return
						this.leftover_chunk = chunk.substring(chunk_pos, chunk.length - chunk_pos);
						return;
					}
					if (fence_result == 0) {
						// Not a closing fence - send text up to newline (or end of chunk) to on_code_text
						var remaining = chunk.substring(chunk_pos, chunk.length - chunk_pos);
						GLib.debug("  [code] At line start, not closing fence, remaining='%s'", remaining.replace("\n", "\\n"));
						if (!remaining.contains("\n")) {
							// No newline - send everything and return
							GLib.debug("  [code] No newline, sending all: '%s'", remaining);
							this.renderer.on_code_text(remaining);
							return;
						}
						
						// Has newline - send text before newline
						var newline_pos = chunk.index_of_char('\n', chunk_pos);
						var code_text = chunk.substring(chunk_pos, newline_pos - chunk_pos);
						GLib.debug("  [code] Sending line: '%s'", code_text);
						this.renderer.on_code_text(code_text);
						// Move pos to newline (will be handled in next iteration)
						chunk_pos = newline_pos;
						this.at_line_start = false;
						continue;
					}
					// fence_result > 0: Found closing fence - end the block
					// Find the newline after the fence (fence is 3 chars, so start after it)
					var after_fence = chunk_pos + 3;
					var remaining = chunk.substring(after_fence, chunk.length - after_fence);
					var newline_pos_in_substring = remaining.index_of_char('\n');
					if (newline_pos_in_substring != -1) {
						// Skip to after the newline
						chunk_pos = after_fence + newline_pos_in_substring + 1;
					} else {
						// No newline found (shouldn't happen if is_closing_fence validated correctly)
						chunk_pos = after_fence;
					}
					
					this.do_block(false, this.current_block);
					this.last_line_block = this.current_block;
					this.current_block = FormatType.NONE;
					this.at_line_start = true;
					continue;
				}
				
		
				
				// At line start - check for block markers
				if (this.at_line_start) {
					var saved_chunk_pos = chunk_pos;
					var block_result = this.peekBlockHandler(chunk, chunk_pos, is_end_of_chunks);
					if (block_result == -1) {
						// Need more data - standard -1 behavior: save to leftover_chunk and return
						this.leftover_chunk = chunk.substring(saved_chunk_pos, chunk.length - saved_chunk_pos);
						return;
					}
					if (block_result == 0) {
						// No block detected - start a paragraph
						if (this.current_block == FormatType.NONE) {
							this.current_block = FormatType.PARAGRAPH;
							this.do_block(true, FormatType.PARAGRAPH);
						}
						this.at_line_start = false;
						// Pass control back to main loop to handle span formatting (inline formatting)
						continue;
					}
					// Block processed - advance chunk_pos by the returned byte length
					chunk_pos += block_result;
					// After block handling, continue with normal processing
					continue;
				}
				
				
				if (escape_next) {
					var char_str = c.to_string();
					str += char_str;
					GLib.debug("  [str] ADD escaped char '%s': str='%s'", char_str.replace("\n", "\\n").replace("\r", "\\r"), str);
					escape_next = false;
					chunk_pos += c.to_string().length;
					continue;
				}
				
				if (c == '\\') {
					escape_next = true;
					chunk_pos += c.to_string().length;
					continue;
				}
				
				// Use peekFormat to detect format sequences (needed even in literal mode for backtick toggle)
				FormatType matched_format = FormatType.NONE;
				var match_len = this.peekFormat(chunk, chunk_pos, is_end_of_chunks, out matched_format);
				
				if (match_len == -1) {
					// Cannot determine - need more characters
					// Flush accumulated text and save to leftover_chunk
					GLib.debug("  [str] FLUSH (need more data): str='%s'", str);
					this.renderer.on_text(str);
					this.leftover_chunk = chunk.substring(chunk_pos, chunk.length - chunk_pos);
					return;
				}
				
				if (match_len == 0) {
					// No match - add as text and consume the character
					var char_str = c.to_string();
					str += char_str;
					//GLib.debug("  [str] ADD char '%s': str='%s'", char_str.replace("\n", "\\n").replace("\r", "\\r"), str);
					chunk_pos += c.to_string().length;
					continue;
				}
				
				// We have a match - flush accumulated text first
				GLib.debug("  [str] FLUSH (format match): str='%s'", str);
				this.renderer.on_text(str);
				str = "";
				GLib.debug("  [str] RESET after format flush: str='%s'", str);
				
				// Calculate byte length for advancing chunk_pos
				var seq_pos = chunk_pos;
				for (int i = 0; i < match_len; i++) {
					var ch = chunk.get_char(seq_pos);
					seq_pos += ch.to_string().length;
				}
				
				// Handle HTML specially
				if (matched_format == FormatType.HTML) {
					var html_res = this.peekHTML(chunk, seq_pos, is_end_of_chunks);
					
					if (html_res == -1) {
						// Need more characters to determine if it's HTML
						this.leftover_chunk = chunk.substring(chunk_pos, chunk.length - chunk_pos);
						return;
					}
					
					if (html_res == 0) {
						// Not a valid HTML tag start - treat as text
						var html_text = chunk.substring(chunk_pos, seq_pos - chunk_pos);
						str += html_text;
						GLib.debug("  [str] ADD HTML-as-text '%s': str='%s'", html_text, str);
						chunk_pos = seq_pos;
						continue;
					}
					
					// Valid HTML tag - process it
					chunk_pos = seq_pos;
					chunk = this.add_html(chunk.substring(chunk_pos, chunk.length - chunk_pos));
					chunk_pos = 0;
					if (chunk.length > 0 && chunk.get_char(0) == '<' && is_end_of_chunks) {
						// End of chunks - continue processing the chunk (treat incomplete HTML as text)
						continue;
					}
					if (chunk.length > 0 && chunk.get_char(0) == '<') {
						// Not end of chunks - save for next call
						this.leftover_chunk = chunk;
						return;
					}
					// HTML tag processed successfully
					continue;
				}
				
				// Handle other format types
				this.got_format(matched_format);
				chunk_pos = seq_pos;
			}
			
			// Flush any remaining text
			GLib.debug("  [str] FINAL FLUSH: str='%s'", str);
			this.renderer.on_text(str);
		}
	

		/**
		 * Handles format markers by checking the stack.
		 * If the same format is on top of stack, removes it and calls on_end.
		 * If different, adds to stack and calls the appropriate do_XXX method.
		 * 
		 * @param format_type The format type detected
		 */
		private void got_format(FormatType format_type)
		{
			// Check if stack is empty or top is different
			if (this.state_stack.size == 0 || this.state_stack.get(this.state_stack.size - 1) != format_type) {
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
		private void do_format(bool is_start, FormatType format_type)
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
		 * Handles block detection when at line start.
		 * 
		 * @param chunk The text chunk
		 * @param chunk_pos Current position
		 * @param is_end_of_chunks If true, format markers at the end are treated as definitive
		 * @return -1 if need more data, 0 if no block detected, >0 byte length to advance if block processed
		 */
		private int peekBlockHandler(string chunk, int chunk_pos, bool is_end_of_chunks)
		{
			string block_lang = "";
			FormatType matched_block = FormatType.NONE;
			int byte_length = 0;
			var block_match = this.peekBlock(chunk, chunk_pos, is_end_of_chunks, out block_lang, out matched_block, out byte_length);
			
			if (block_match < 1) {
				// Need more data (-1) or no block detected (0) - return for caller to handle
				return block_match;
			}
			
			// Block detected - use byte_length from peekBlock
			var seq_pos = chunk_pos + byte_length;
			
			switch (matched_block) {
				case FormatType.HORIZONTAL_RULE:
					this.do_block(true, matched_block);
					// Skip the rule and any whitespace until newline
					var pos = seq_pos;
					
					// Check if chunk contains newline or is end of stream first
					if (!chunk.contains("\n") && !is_end_of_chunks) {
						// Need more data
						return -1;
					}
					
					var newline_pos = chunk.index_of_char('\n', pos);
					if (newline_pos != -1) {
						// Found newline - skip to after it
						var newline_char = chunk.get_char(newline_pos);
						this.at_line_start = true;
						return newline_pos + newline_char.to_string().length - chunk_pos;
					}
					
					// No newline found - check if end of chunks
					if (!is_end_of_chunks) {
						// Need more data
						return -1;
					}
					
					// End of stream - check if only whitespace remains
					while (pos < chunk.length) {
						var ch = chunk.get_char(pos);
						if (!ch.isspace()) {
							// Invalid - horizontal rule must be followed by newline or whitespace
							return -1;
						}
						pos += ch.to_string().length;
					}
					
					// Only whitespace found - valid at end of stream
					this.at_line_start = true;
					return pos - chunk_pos;
				
				case FormatType.FENCED_CODE_QUOTE:
				case FormatType.FENCED_CODE_TILD:
					// Start the new block
					this.current_block = matched_block;
					this.do_block(true, matched_block, block_lang);
					
					// seq_pos is already after the opening fence, language, and newline
					// (peekBlock includes the newline in byte_length)
					// So seq_pos points to the first character of the code content
					// We just need to advance to seq_pos and set at_line_start
					GLib.debug("  [code] Starting code block, chunk_pos=%d, seq_pos=%d, byte_length=%d, next_char='%s'", chunk_pos, seq_pos, byte_length, seq_pos < chunk.length ? chunk.get_char(seq_pos).to_string() : "EOF");
					this.at_line_start = true;
					return seq_pos - chunk_pos;
				
				default:
					// Start the new block
					this.current_block = matched_block;
					this.do_block(true, matched_block, block_lang);
					
					// For other blocks, continue with normal inline processing
					this.at_line_start = false;
					return seq_pos - chunk_pos;
			}
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
				case FormatType.UNORDERED_LIST:
					this.renderer.on_ul(is_start, false, '-');
					break;
				case FormatType.ORDERED_LIST:
				case FormatType.ORDERED_LIST_1:
				case FormatType.ORDERED_LIST__1:
				case FormatType.ORDERED_LIST___1:
				case FormatType.ORDERED_LIST____1:
				case FormatType.ORDERED_LIST_____1:
				case FormatType.ORDERED_LIST_11:
				case FormatType.ORDERED_LIST__11:
				case FormatType.ORDERED_LIST___11:
				case FormatType.ORDERED_LIST____11:
				case FormatType.ORDERED_LIST_____11:
					this.renderer.on_ol(is_start, 1, false, '.');
					break;
				case FormatType.FENCED_CODE_QUOTE:
				case FormatType.FENCED_CODE_TILD:
					this.renderer.on_code_block(is_start, lang);
					break;
				case FormatType.HORIZONTAL_RULE:
					this.renderer.on_hr();
					break;
				case FormatType.NONE:
					// No block to handle
					break;
				default:
					// Unknown block type
					break;
			}
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
		private int peekFencedEnd(string chunk, int chunk_pos, FormatType fence_type, bool is_end_of_chunks)
		{
			// Does string have \n (or end of stream indicator)?
			if (!chunk.contains("\n") && !is_end_of_chunks) {
				return -1;
			}
			
			if (chunk_pos >= chunk.length) {
				return 0;
			}
			
			var fence_str = (fence_type == FormatType.FENCED_CODE_QUOTE) ? "```" : "~~~";
			var fence_char = fence_str.substring(0, 1);
			
			// Is first char the same as opener?
			var first_char = chunk.get_char(chunk_pos);
			if (first_char.to_string() != fence_char) {
				return 0;
			}
			
			// Check if we have at least 3 bytes available for the fence string
			// If chunk_pos + 3 > chunk.length, we don't have enough bytes
			if (chunk_pos + 3 > chunk.length) {
				// Not enough bytes available
				if (is_end_of_chunks) {
					// At end of stream - definitely not a match (we need 3 bytes but don't have them)
					return 0;
				}
				// More data might come - need to wait to see if we get the remaining bytes
				return -1;
			}
			
			// Do the first 3 chars match our end of block?
			// Fence strings are ASCII (3 bytes), so we can use substring directly
			var match_str = chunk.substring(chunk_pos, 3);
			
			if (match_str != fence_str) {
				// Not a match - return 0
				return 0;
			}
			
			// Match found - check if followed by whitespace and newline
			var pos = chunk_pos + 3;
			if (pos >= chunk.length) {
				// At end of chunk - if is_end_of_chunks, it's valid
				if (is_end_of_chunks) {
					return 3;
				}
				return -1;
			}
			
			// Find newline position
			var newline_pos = chunk.index_of_char('\n', pos);
			if (newline_pos == pos) {
				// Starts with newline - valid
				return 3;
			}
			
			if (newline_pos != -1) {
				// Found newline - check if everything between pos and newline is whitespace
				var between = chunk.substring(pos, newline_pos - pos);
				if (between.strip().length == 0) {
					// All whitespace before newline - valid
					return 3;
				}
				// Non-whitespace found before newline - invalid
				return 0;
			}
			
			// No newline found - check if remaining is all whitespace
			var remaining = chunk.substring(pos);
			if (remaining.strip().length == 0) {
				// All whitespace - valid if end of chunks
				if (is_end_of_chunks) {
					return 3;
				}
				return -1;
			}
			
			// Non-whitespace found - invalid
			return 0;
		}

		private string add_html(string chunk)
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

