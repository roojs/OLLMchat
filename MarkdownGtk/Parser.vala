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

namespace OLLMchat.MarkdownGtk
{
	
	
	
 
    private enum FormatType {
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
		LITERAL
    }
	
	private enum BlockType {
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
		TASK_LIST,
		DEFINITION_LIST,
		INDENTED_CODE,
		FENCED_CODE,
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
		private static Gee.HashMap<string, BlockType> block_map;
		
		 
		static construct {
			setup_format_map();
			setup_block_map();
		}
		
		private static void setup_format_map() {
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
			
			format_map["<"] = FormatType.HTML;
		}

		
		private RenderBase renderer;
		private Gee.ArrayList<FormatType> state_stack { set; get; default = new Gee.ArrayList<FormatType>(); }
	 
		private string leftover_chunk = "";
		private bool in_literal = false;
	
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

		public void add_start(string in_chunk, bool is_end_of_chunks = false)
		{
			this.in_literal = false;
			this.leftover_chunk = "";
			this.add(in_chunk, is_end_of_chunks);
		}

		/**
		 * Determines if characters at a given position match a format tag.
		 * Uses a loop-based approach to handle variable-length format sequences.
		 * 
		 * @param format_map The format map to check against
		 * @param chunk The text chunk to examine
		 * @param chunk_pos The position in the chunk to check
		 * @param is_end_of_chunks If true, format markers at the end are treated as definitive
		 * @return 1-N: Length of the match, 0: No match found, -1: Cannot determine (need more characters)
		 */
		private int peekMatch(
			Gee.HashMap<string, FormatType> format_map, 
			string chunk, 
			int chunk_pos, 
			bool is_end_of_chunks
		) {
			// Check bounds
			if (chunk_pos >= chunk.length) {
				return 0;
			}
			
			// Check if single character is in format_map
			var single_char = chunk.get_char(chunk_pos).to_string();
			if (!format_map.has_key(single_char)) {
				return 0; // No match
			}
			
			// Handle LITERAL (backtick) - toggle in_literal and return 0
			if (format_map.get(single_char) == FormatType.LITERAL) {
				this.in_literal = !this.in_literal;
				return 0; // Return 0 so caller will consume the char
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
				 
				if (format_map.get(single_char) == FormatType.INVALID) {
					return 0;
				}
				return 1; // Definitive single char match
			}
			
			// Loop-based sequence matching
			int max_match_length = 0;
			var sequence = "";
			
			for (var cp = chunk_pos; cp < chunk.length; ) {
				// Build sequence incrementally by appending current character
				var char_at_cp = chunk.get_char(cp);
				sequence += char_at_cp.to_string();
				cp += char_at_cp.to_string().length;
				 
				if (!format_map.has_key(sequence)) {
					// Sequence not in format_map - return longest valid match found (0 if none)
					return max_match_length;
				}
				
				// Sequence is in format_map
 				
				// If FormatType is NOT INVALID, update max_match_length
				if (format_map.get(sequence) != FormatType.INVALID) {
					// Count characters, not bytes
					int char_count = 0;
					for (var i = chunk_pos; i < cp; ) {
						var char_at_i = chunk.get_char(i);
						i += char_at_i.to_string().length;
						char_count++;
					}
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
		 * Uses peekMatch to detect format sequences.
		 * 
		 * @param in_chunk The markdown text to parse
		 * @param is_end_of_chunks If true, format markers at the end are treated as definitive (no more data coming)
		 */
		public void add(string in_chunk, bool is_end_of_chunks = false)
		{
			GLib.debug("Parser.add: %s", in_chunk);
			
			var chunk = this.leftover_chunk + in_chunk; // Prepend leftover_chunk so it's processed first
			this.leftover_chunk = ""; // Clear leftover_chunk after using it
			var chunk_pos = 0;
			var escape_next = false;
			var str = "";
			
			while (chunk_pos < chunk.length) {
				var c = chunk.get_char(chunk_pos);
				
				if (escape_next) {
					str += c.to_string();
					escape_next = false;
					chunk_pos += c.to_string().length;
					continue;
				}
				
				if (c == '\\') {
					escape_next = true;
					chunk_pos += c.to_string().length;
					continue;
				}
				
				// Use peekMatch to detect format sequences (needed even in literal mode for backtick toggle)
				var match_len = this.peekMatch(format_map, chunk, chunk_pos, is_end_of_chunks);
				
				if (match_len == -1) {
					// Cannot determine - need more characters
					// Flush accumulated text and save to leftover_chunk
					this.renderer.on_text(str);
					this.leftover_chunk = chunk.substring(chunk_pos, chunk.length - chunk_pos);
					return;
				}
				
				if (match_len == 0) {
					// No match or LITERAL (backtick) or in_literal mode - add as text and consume the character
					// For LITERAL, peekMatch already toggled in_literal
					str += c.to_string();
					chunk_pos += c.to_string().length;
					continue;
				}
				
				// We have a match - flush accumulated text first
				this.renderer.on_text(str);
				str = "";
				
				// Get the format type from the matched sequence
				var matched_sequence = "";
				var seq_pos = chunk_pos;
				for (int i = 0; i < match_len; i++) {
					var ch = chunk.get_char(seq_pos);
					matched_sequence += ch.to_string();
					seq_pos += ch.to_string().length;
				}
				var format_type = format_map.get(matched_sequence);
				
				// Handle HTML specially
				if (format_type == FormatType.HTML) {
					var html_res = this.peekHTML(chunk, seq_pos, is_end_of_chunks);
					
					if (html_res == -1) {
						// Need more characters to determine if it's HTML
						this.leftover_chunk = chunk.substring(chunk_pos, chunk.length - chunk_pos);
						return;
					}
					
					if (html_res == 0) {
						// Not a valid HTML tag start - treat as text
						str += matched_sequence;
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
				this.got_format(format_type);
				chunk_pos = seq_pos;
			}
			
			// Flush any remaining text
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
				this.do_format_start(format_type);
				return;
			}
			
			// Same state - remove from stack and call do_end
			this.state_stack.remove_at(this.state_stack.size - 1);
			this.do_format_end(format_type);
		}
		
		/**
		 * Calls the appropriate end method based on format type.
		 * For BOLD_ITALIC, calls on_end twice since we opened two states.
		 * 
		 * @param format_type The format type to end
		 */
		private void do_format_end(FormatType format_type)
		{
			if (format_type == FormatType.BOLD_ITALIC) {
				// BOLD_ITALIC opened two states, so close both
				this.renderer.on_end(); // Close italic
			}
			
			// Single state, close once
			this.renderer.on_end();
		}
		
		/**
		 * Calls the appropriate renderer method based on format type.
		 * Highlights formats that don't have renderer support.
		 * 
		 * @param format_type The format type to start
		 */
		private void do_format_start(FormatType format_type)
		{
			switch (format_type) {
				case FormatType.ITALIC:
					this.renderer.on_em();
					break;
				case FormatType.BOLD:
					this.renderer.on_strong();
					break;
				case FormatType.BOLD_ITALIC:
					// Push both bold and italic states
					this.renderer.on_strong();
					this.renderer.on_em();
					break;
				case FormatType.CODE:
					this.renderer.on_code_span();
					break;
				case FormatType.STRIKETHROUGH:
					this.renderer.on_del();
					break;
				// case FormatType.HIGHLIGHT:
				// 	// HIGHLIGHT not supported in renderer - use on_other
				// 	this.renderer.on_other("highlight");
				// 	break;
				// case FormatType.SUPERSCRIPT:
				// 	// SUPERSCRIPT not supported in renderer - use on_other
				// 	this.renderer.on_other("sup");
				// 	break;
				// case FormatType.SUBSCRIPT:
				// 	// SUBSCRIPT not supported in renderer - use on_other
				// 	this.renderer.on_other("sub");
				// 	break;
				case FormatType.HTML:
					// HTML needs special handling - for now use on_other
					// TODO: Parse HTML tag and attributes
					this.renderer.on_other("html");
					break;
				case FormatType.INVALID:
					// Should not reach here
					break;
			}
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
					this.renderer.on_end();
				} else {
					this.renderer.on_html(tag, "");
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
				this.renderer.on_html(tag, attributes);
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