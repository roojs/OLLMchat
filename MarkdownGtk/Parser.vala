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
		HTML
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
		
		 
		static construct {
			setup_format_map();
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
			format_map["`"] = FormatType.CODE;
			format_map["``"] = FormatType.CODE; // Some parsers support double backtick
			
			// Strikethrough (GFM)
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

		
		private Render renderer;
		private Gee.ArrayList<FormatType> state_stack { set; get; default = new Gee.ArrayList<FormatType>(); }
	 
		private string leftover_chunk = "";
	
		/**
		 * Creates a new Parser instance.
		 * 
		 * @param renderer The Render instance to call callbacks on
		 */
		public Parser(Render renderer)
		{
			this.renderer = renderer;
		}
		

		public void flush()
		{
			this.add("", true);
		}

		public void add_start(string in_chunk, bool is_end_of_chunks = false)
		{
			this.leftover_chunk = "";
			this.add(in_chunk, is_end_of_chunks);
		}

		 
		/**
		 * Parses text and calls specific callbacks on Render.
		 * 
		 * @param in_chunk The markdown text to parse
		 * @param is_end_of_chunks If true, format markers at the end are treated as definitive (no more data coming)
		 */
		public void add(string in_chunk, bool is_end_of_chunks = false)
		{
			var chunk = in_chunk + this.leftover_chunk;
			var chunk_pos = 0;
			var escape_next = false;
			var str = "";
			
			while (chunk_pos < chunk.length) {
				unichar c = chunk[chunk_pos];
				
				if (escape_next) {
					str += c.to_string();
					escape_next = false;
					chunk_pos++;
					continue;
				}
				
				if (c == '\\') {
					escape_next = true;
					chunk_pos++;
					continue;
				}
				
				// Check if this could be the start of a formatting sequence
				if (!format_map.has_key(c.to_string())) {
					str += c.to_string();
					chunk_pos++;
					continue;
				}
				// If we're at the end, check format type to determine if we need lookahead
				if (chunk_pos == chunk.length - 1) {
					var fk = format_map[c.to_string()];
					
					switch (fk) {
						case FormatType.HTML:
							// HTML at end of chunks - treat as text (no more characters to check)
							if (is_end_of_chunks) {
								str += c.to_string();
								chunk_pos++;
								continue;
							}
							// Not end of chunks - continue processing (check if next char is alpha)
							break;
							
						case FormatType.INVALID:
							// Invalid format - if end of chunks, treat as text; otherwise save to leftover_chunk
							if (is_end_of_chunks) {
								str += c.to_string();
								chunk_pos++;
								continue;
							}
							// Flush accumulated text before saving to leftover_chunk
							this.renderer.on_text(str);
							this.leftover_chunk = c.to_string();
							return;
						
						
						
						default:
							// All other formats can have multi-character sequences
							// Save to leftover_chunk if not end of chunks (might need lookahead)
							if (!is_end_of_chunks) {
								// Flush accumulated text before saving to leftover_chunk
								this.renderer.on_text(str);
								this.leftover_chunk = chunk.substring(chunk_pos, chunk.length - chunk_pos);
								return;
							}
							// End of chunks - process as single character format
							break;
					}
				}
				
				var fk = format_map[c.to_string()];
				
				// If we're at the end and it IS end of chunks, continue processing normally
				// (format marker is definitive - no need to save to leftover_chunk)

				// Check bounds before accessing next character
				if (chunk_pos + 1 >= chunk.length && is_end_of_chunks) {
					// At end of chunk and end of chunks - treat format marker as text
					str += c.to_string();
					chunk_pos++;
					continue;
				}
				if (chunk_pos + 1 >= chunk.length) {
					// Not end of chunks - save to leftover_chunk for next call
					this.renderer.on_text(str);
					this.leftover_chunk = chunk.substring(chunk_pos, chunk.length - chunk_pos);
					return;
				}

				var next_char = chunk[chunk_pos + 1];

				if (fk == FormatType.HTML) {
					// check if next char is a-z (opening tag) or '/' (closing tag)
					if (!next_char.isalpha() && next_char != '/') {
						str += c.to_string();
						chunk_pos++;
						continue;
					}
					// Output accumulated text before processing HTML tag
					this.renderer.on_text(str);
					str = "";
					// now we are reading 
					chunk_pos++;
					chunk = this.add_html(chunk.substring(chunk_pos, chunk.length - chunk_pos));
					chunk_pos = 0;
					if (chunk.length > 0 && chunk[0] == '<' && is_end_of_chunks) {
						// End of chunks - continue processing the chunk (treat incomplete HTML as text)
						// The loop will handle it as text or format markers
						continue;
					}
					if (chunk.length > 0 && chunk[0] == '<') {
						// Not end of chunks - save for next call when we might have more data
						this.leftover_chunk = chunk;
						return;
					}
					// if it could not read the html tag, then we can leave it to the next call
					continue;
				}
				
				var two_char_seq = c.to_string() + next_char.to_string();
				if (!format_map.has_key(two_char_seq)) {
					this.renderer.on_text(str);
					str = "";
					this.got_format(fk);
					chunk_pos++;
					continue;
				}
				var fk2 = format_map[two_char_seq];
				// Check for third character sequence
				if (chunk_pos + 2 >= chunk.length) {
					this.renderer.on_text(str);
					str = "";
					this.got_format(fk2);
					chunk_pos += 2;
					continue;
				}
				
				var third_char = chunk[chunk_pos + 2];
				var three_char_seq = two_char_seq + third_char.to_string();
				
				if (!format_map.has_key(three_char_seq)) {
					this.renderer.on_text(str);
					str = "";
					this.got_format(fk2);
					chunk_pos += 2;
					continue;
				}
				// Three-character sequence found (e.g., *** or ___)
				this.renderer.on_text(str);
				str = "";
				
				this.got_format(format_map[three_char_seq]);
				chunk_pos += 3;
				continue;
			}
			
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
			var is_closing = chunk[pos] == '/';
			
			// Check if this is a closing tag (starts with '/')
			if (is_closing) {
				pos++;
			}
			
			// Read all alphabetic characters - that's our tag
			while (pos < chunk.length && chunk[pos].isalpha()) {
				tag += chunk[pos].to_string();
				pos++;
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
			while (pos < chunk.length && chunk[pos] == ' ') {
				got_ws = true;
				pos++;
			}
			// at this point we have the tag.. either we are looking for attributes or a closing tag <span> </span>

			// Next char should be '>' or space
			if (chunk[pos] == '>') {
				// we got tag then '>' so we either fire on_html with the tag and an empty attribute or on_end
				if (is_closing) {
					this.renderer.on_end();
				} else {
					this.renderer.on_html(tag, "");
				}
				return chunk.substring(pos + 1, chunk.length - pos - 1);
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
			while (pos < chunk.length && chunk[pos] != '>' && chunk[pos] != '\n' && chunk[pos] != '\r') {
				attributes += chunk[pos].to_string();
				pos++;
			}
			
			if (pos >= chunk.length) {
				// not got there yet - still reading attributes
				return "<" + chunk;
			}
			
			if (chunk[pos] == '>') {
				this.renderer.on_html(tag, attributes);
				return chunk.substring(pos + 1, chunk.length - pos - 1);
			}
			
			// chunk[pos] == '\n' || chunk[pos] == '\r'
			this.renderer.on_text("<" + chunk.substring(0, pos));
			return chunk.substring(pos, chunk.length - pos);
		}
 

	}
    // Mapping of character sequences to format types
    
     
    
     
    
} 