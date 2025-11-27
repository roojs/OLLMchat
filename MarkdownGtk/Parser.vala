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
	/**
	 * Parser for markdown text that calls specific callbacks on Render.
	 * 
	 * This is a placeholder implementation. Full parser implementation
	 * will be specified in a separate plan.
	 */
	public class Parser
	{
		private Render renderer;
		public StringBuilder pending;
		
		/**
		 * Creates a new Parser instance.
		 * 
		 * @param renderer The Render instance to call callbacks on
		 */
		public Parser(Render renderer)
		{
			this.renderer = renderer;
			this.pending = new StringBuilder();
		}
		
		/**
		 * Parses text and calls specific callbacks on Render.
		 * 
		 * @param text The markdown text to parse
		 * @return 0 on success, non-zero on error
		 */
		public int add(string chunk)
		{
			
    
			 
				this.current_chunk = chunk;
				this.chunk_pos = 0;
				var escape_next = false; // I guess used to markup chars..
				var str= "";
				while (this.chunk_pos < this.current_chunk.length) {
					unichar c = current_chunk[chunk_pos];
					
					// escped chars
					if (escape_next) {
						str += c;
						escape_next = false;
						this.chunk_pos++;
						continue;
					}
					
					if (c == '\\') {
						escape_next = true;
						this.chunk_pos++;
						continue;
					}
					



					// Check if this could be the start of a formatting sequence
					if (is_format_char(c)) {
						// Peek ahead to get the full sequence
						string sequence = peek_format_sequence();
						
						if (sequence != null) {
							// We found a formatting sequence - flush text and handle it
							flush_text();
							handle_format_sequence(sequence);
							chunk_pos += sequence.length;
							continue;
						}
					}
					
					// Not a formatting sequence, just accumulate text
					current_text.append_unichar(c);
					chunk_pos++;
				}
				
				current_chunk = "";
				chunk_pos = 0;
			}
			// Placeholder implementation - full parser will be implemented later
			// For now, just pass text through as plain text
			if (text.length > 0) {
				this.renderer.on_text(text);
			}
			// Return 0 for success
			return 0;
		}
	}
}
 
 
    private enum FormatType {
        ITALIC,
        BOLD,
        BOLD_ITALIC,
        CODE,
        STRIKETHROUGH,
		HIGHLIGHT,
		SUPERSCRIPT,
		SUBSCRIPT,
		ST_INVALID,
		EQ_INVALID,
		HTML
    }
	private static Gee.HashMap<string, FormatType> {
		get; set ; default = new Gee.HashMap<string, FormatType>()
	};
    
	 
	static construct {
		
        // Asterisk sequences
		private void setup_format_map() {
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
			format_map["~"] = FormatType.ST_INVALID;
			
			// Highlight (some markdown flavors)
			format_map["=="] = FormatType.HIGHLIGHT;
			format_map["="] = FormatType.EQ_INVALID;
			
			// Superscript/subscript (some flavors)
			format_map["^"] = FormatType.SUPERSCRIPT;
			format_map["~"] = FormatType.SUBSCRIPT;
			format_map["<"] = FormatType.HTML;
		}
	}

    private Gee.Stack<FormatType> state_stack { set; get; default = new Gee.Stack<FormatType>(); };
    private string current_chunk = "";
    private int chunk_pos = 0;
     
    // Mapping of character sequences to format types
    
     
    
    public void parse_chunk(string chunk) {
        this.current_chunk = chunk;
        this.chunk_pos = 0;
        var escape_next = false;
		var str = "";
        
        while (chunk_pos < current_chunk.length) {
            unichar c = current_chunk[chunk_pos];
            
            if (escape_next) {
                current_text.append_unichar(c);
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
            if (!format_map.has_key(c.to_string()))


			}
                // Peek ahead to get the full sequence
                string sequence = peek_format_sequence();
                
                if (sequence != null) {
                    // We found a formatting sequence - flush text and handle it
                    flush_text();
                    handle_format_sequence(sequence);
                    chunk_pos += sequence.length;
                    continue;
                }
            }
            
            // Not a formatting sequence, just accumulate text
            current_text.append_unichar(c);
            chunk_pos++;
        }
        
        current_chunk = "";
        chunk_pos = 0;
    }
    
    public void finish() {
        flush_text();
    }
    
    private bool is_format_char(unichar c) {
        return c == '*' || c == '_' || c == '`' || c == '~';
    }
    
    private string peek_format_sequence() {
        int start_pos = chunk_pos;
        unichar start_char = current_chunk[chunk_pos];
        StringBuilder sequence = new StringBuilder();
        
        // Consume consecutive identical formatting characters
        while (chunk_pos < current_chunk.length && 
               current_chunk[chunk_pos] == start_char) {
            sequence.append_unichar(start_char);
            chunk_pos++;
            
            // Check if this sequence is in our format map
            string seq_str = sequence.str;
            if (format_map.has_key(seq_str)) {
                // We found a valid sequence, reset chunk_pos for actual consumption
                chunk_pos = start_pos;
                return seq_str;
            }
        }
        
        // No valid sequence found, reset position
        chunk_pos = start_pos;
        return null;
    }
    
    private void handle_format_sequence(string sequence) {
        FormatType format_type = format_map[sequence];
        FormatType current_state = state_stack.size > 0 ? state_stack.peek() : FormatType.ITALIC;
        
        // Check if we're closing the current formatting
        if (state_stack.size > 0 && current_state == format_type) {
            // Matching close - end the format
            state_stack.pop();
            format_end(get_format_name(format_type));
        } else {
            // New format starting
            state_stack.push(format_type);
            format_begin(get_format_name(format_type));
        }
    }
    
    private string get_format_name(FormatType format_type) {
        switch (format_type) {
            case FormatType.ITALIC:
                return "italic";
            case FormatType.BOLD:
                return "bold";
            case FormatType.BOLD_ITALIC:
                return "bold_italic";
            case FormatType.CODE:
                return "code";
            case FormatType.STRIKETHROUGH:
                return "strikethrough";
            default:
                return "plain";
        }
    }
    
    private void flush_text() {
        if (current_text.len > 0) {
            text(current_text.str);
            current_text = new StringBuilder();
        }
    }
}

// Example usage
public class SimpleRenderer : Object {
    public void on_text(string text) {
        print(text);
    }
    
    public void on_format_begin(string format_type) {
        switch (format_type) {
            case "italic":
                print("<i>");
                break;
            case "bold":
                print("<b>");
                break;
            case "bold_italic":
                print("<b><i>");
                break;
            case "code":
                print("<code>");
                break;
            case "strikethrough":
                print("<s>");
                break;
        }
    }
    
    public void on_format_end(string format_type) {
        switch (format_type) {
            case "italic":
                print("</i>");
                break;
            case "bold":
                print("</b>");
                break;
            case "bold_italic":
                print("</i></b>");
                break;
            case "code":
                print("</code>");
                break;
            case "strikethrough":
                print("</s>");
                break;
        }
    }
}

int main() {
    var parser = new MarkdownSpanParser();
    var renderer = new SimpleRenderer();
    
    parser.text.connect(renderer.on_text);
    parser.format_begin.connect(renderer.on_format_begin);
    parser.format_end.connect(renderer.on_format_end);
    
    // Test cases
    string[] test_inputs = {
        "Hello *world*",
        "This is **bold** and ***bold italic***",
        "`code` and ~~strikethrough~~",
        "Mixed **bold *and italic* inside**"
    };
    
    foreach (string test in test_inputs) {
        print("Input: %s\nOutput: ", test);
        parser.parse_chunk(test);
        parser.finish();
        print("\n\n");
    }
    
    return 0;
}