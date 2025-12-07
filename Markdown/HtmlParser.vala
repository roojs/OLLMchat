/*
 * Copyright (c) 2025 Alan Knowles <alan@roojs.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 * This code is based on the HTML to Markdown converter originally written by
 * Tim Gromeyer (https://github.com/tim-gromeyer/html2md).
 * Ported to Vala and modified by Alan Knowles.
 */

namespace Markdown
{
	
	
	/**
	* SAX callback: Start of document.
	*/
	public void sax_start_document(void* ctx)  {}
	
	/**
	* SAX callback: End of document.
	*/
	public void sax_end_document(void* ctx) {  }

	/**
	* SAX callback: Start element.
	*/
	public void sax_start_element(void* ctx, unowned string name, unowned string[] attrs)
	{
		var converter = (HtmlParser)ctx;
		converter.start_element(name, attrs);
		
	}

	/**
	* SAX callback: End element.
	*/
	public void sax_end_element(void* ctx, unowned string name)
	{
		var converter = (HtmlParser)ctx;
		converter.end_element(name);
	}
	/**
	* SAX callback: Character data.
	*/
	private void sax_characters(void* ctx, unowned string ch, int len)
	{
		var converter = (HtmlParser)ctx;
		
		// Process character by character
		for (int i = 0; i < len; i++) {
			converter.process_char(ch[i].to_string());
		}
	}


/**
	* Converts HTML to Markdown format.
	*/
	public class HtmlParser : Object
	{
		// Options as properties
		public bool compress_whitespace { get; set; default = true; }
		public bool escape_numbered_list { get; set; default = true; }
		public bool force_left_trim { get; set; default = false; }
		public bool include_title { get; set; default = true; }
		public bool split_lines { get; set; default = true; }
		public bool format_table { get; set; default = true; }
		public int soft_break { get; set; default = 80; }
		public int hard_break { get; set; default = 120; }
		public char unordered_list { get; set; default = '-'; }
		public char ordered_list { get; set; default = '.'; }

		// Converter properties (public for tag handlers)
		public string html;
		public Writer writer { get; set; default = new Writer(); }
		public Gee.HashMap<string, TagIgnored> tags { get; set; default = new Gee.HashMap<string, TagIgnored>(); }
		public string current_tag = "";
		public string prev_tag = "";
		public bool is_in_pre = false;
		public bool is_in_code = false;
		public bool is_in_list = false;
		public bool is_in_ordered_list = false;
		public bool is_in_p = false;
		public bool is_in_table = false;
		public char prev_ch_in_html = 0;
		public int index_blockquote = 0;
		public int index_li = 0;
		public int index_ol = 0;
		
		// Tag stack for tracking nested tags
		private Gee.ArrayList<string> tag_stack;
		// Current attributes for tag handlers
		public Gee.HashMap<string, string> attr { get; set;
				 default = new Gee.HashMap<string, string>(); }
		// Track if we've converted already
		private bool converted = false;

		/**
		 * Constructor.
		 *
		 * @param html Input HTML string to convert
		 */
		public HtmlParser(string html)
		{
			this.html = html;
			this.tag_stack = new Gee.ArrayList<string>();

			this.initialize_tag_registry();
		}

		/**
		 * Main conversion method.
		 *
		 * @return Converted markdown string
		 */
		public string convert()
		{
			// We already converted
			if (this.converted) {
				return this.writer.to_string();
			}

			this.reset();

			// Create SAX 
			Xml.SAXHandler sax_handler = Xml.SAXHandler();
			sax_handler.startDocument = sax_start_document;
			sax_handler.endDocument = sax_end_document;
			sax_handler.startElement = sax_start_element;
			sax_handler.endElement = sax_end_element;
			sax_handler.characters = sax_characters;

			// Parse HTML with libxml2 HTML parser
			var doc = Html.Doc.sax_parse_doc(this.html, "UTF-8", &sax_handler, (void*)this);
			if (doc != null) {
				delete doc;
			}

			this.writer.clean_up_markdown();
			this.converted = true;

			return this.writer.to_string();
		}
		public void start_element(string name, string[]? attrs)
		{ 
			this.writer.update_prev_ch();
	
			var tag_name = name.down();
			
			// Store attributes for tag handlers
			this.attr = new Gee.HashMap<string, string>();
			if (attrs != null) {
				for (int i = 0; attrs[i] != null; i += 2) {
					if (attrs[i + 1] != null) {
						this.attr.set(attrs[i], attrs[i + 1]);
					}
				}
			}

			// Check for hidden attributes
			if (this.tag_contains_attributes_to_hide_from_map(this.attr)) {
				this.attr = new Gee.HashMap<string, string>();
				return;
			}

			// Update tag stack
			if (this.tag_stack.size > 0) {
				this.prev_tag = this.tag_stack[this.tag_stack.size - 1];
			} else {
				this.prev_tag = "";
			}
			this.current_tag = tag_name;
			this.tag_stack.add(tag_name);

			// Get tag handler
			var tag = this.tags.get(tag_name);
			if (tag != null) {
				tag.open(this);
			}

			this.attr =  new Gee.HashMap<string, string>();
		}	
		public void end_element(string name)
		{
 
			var tag_name = name.down();
			this.current_tag = tag_name;

			// Get tag handler
			var tag = this.tags.get(tag_name);
			if (tag == null) {
				// Continue with stack update
			} else {
				tag.close(this);
			}

			// Update tag stack
			if (this.tag_stack.size > 0 && this.tag_stack[this.tag_stack.size - 1] == tag_name) {
				this.tag_stack.remove_at(this.tag_stack.size - 1);
			}

			// Update current_tag and prev_tag from stack
			if (this.tag_stack.size == 0) {
				this.current_tag = "";
				this.prev_tag = "";
			} else {
				this.current_tag = this.tag_stack[this.tag_stack.size - 1];
				if (this.tag_stack.size > 1) {
					this.prev_tag = this.tag_stack[this.tag_stack.size - 2];
				} else {
					this.prev_tag = "";
				}
			}
		}

 

		/**
		 * Check if conversion is in clean state.
		 */
		public bool ok()
		{
			return !this.is_in_pre && !this.is_in_list && !this.is_in_p && !this.is_in_table &&
				this.tag_stack.size == 0 && this.index_blockquote == 0 && this.index_li == 0;
		}

 
		/**
		 * Convert line to H1.
		 */
		public void turn_line_into_header1()
		{
			if (this.is_in_ignored_tag()) {
				return;
			}
			if (this.index_blockquote != 0) {
				if (this.is_in_pre) {
					this.writer.append("\n");
					this.writer.append_repeat("> ", this.index_blockquote);
				}
			} else {
				this.writer.append("\n");
			}

			this.writer.append_repeat("=", this.writer.chars_in_curr_line);
			this.writer.append("\n\n");
			this.writer.chars_in_curr_line = 0;
		}

		/**
		 * Convert line to H2.
		 */
		private void turn_line_into_header2()
		{
			if (this.is_in_ignored_tag()) {
				return;
			}
			if (this.index_blockquote != 0) {
				if (this.is_in_pre) {
					this.writer.append("\n");
					this.writer.append_repeat("> ", this.index_blockquote);
				}
			} else {
				this.writer.append("\n");
			}
			this.writer.append_repeat("-", this.writer.chars_in_curr_line);
			this.writer.append("\n\n");
			this.writer.chars_in_curr_line = 0;
		}

		
		/**
		 * Process a string of characters (moved from parse_char_in_tag_content).
		 */
		public void process_char(string text)
		{
			// Extract character from string for comparisons
			char ch = (text.length > 0) ? text[0] : '\0';
			string char_str = text;
			
			if (this.is_in_code) {
				this.writer.append(char_str);

				if (this.index_blockquote != 0 && ch == '\n') {
					if (this.is_in_ignored_tag()) {
						return;
					}
					this.writer.append_repeat("> ", this.index_blockquote);
				}

				return;
			}

			if (this.compress_whitespace && !this.is_in_pre) {
				if (ch == '\t') {
					ch = ' ';
					char_str = " ";
				}

				if (ch == ' ') {
					this.writer.update_prev_ch();
					if (this.writer.prev_ch_in_md == ' ' || this.writer.prev_ch_in_md == '\n') {
						return;
					}
				}
			}

			if (this.is_in_ignored_tag() || this.current_tag == "link") {
				this.prev_ch_in_html = ch;
				return;
			}

			if (ch == '\n') {
				if (this.index_blockquote != 0) {
					this.writer.append("\n");
					if (this.is_in_ignored_tag()) {
						return;
					}
					this.writer.append_repeat("> ", this.index_blockquote);
				}
				return;
			}

			switch (ch) {
				case '*':
					if (this.is_in_ignored_tag()) {
						break;
					}
					this.writer.append("\\*");
					break;
				case '`':
					if (this.is_in_ignored_tag()) {
						break;
					}
					this.writer.append("\\`");
					break;
				case '\\':
					if (this.is_in_ignored_tag()) {
						break;
					}
					this.writer.append("\\\\");
					break;
				case '.':
					bool is_ordered_list_start = false;
					if (this.writer.chars_in_curr_line > 0) {
						size_t start_idx = this.writer.md.len - this.writer.chars_in_curr_line;
						size_t idx = start_idx;
						// Skip spaces
						while (idx < this.writer.md.len && this.writer.md.str[(int)idx].isspace()) {
							idx++;
						}
						// Check digits
						bool has_digits = false;
						while (idx < this.writer.md.len && this.writer.md.str[(int)idx].isdigit()) {
							has_digits = true;
							idx++;
						}
						// If we reached the end and had digits, it's a match
						if (has_digits && idx == this.writer.md.len) {
							is_ordered_list_start = true;
						}
					}

					if (is_ordered_list_start && this.escape_numbered_list) {
						if (!this.is_in_ignored_tag()) {
							this.writer.append("\\.");
						}
						break;
					}
					
					this.writer.append(char_str);
					
					break;
				default:
					this.writer.append(char_str);
					break;
			}

			if (this.writer.chars_in_curr_line > this.soft_break && !this.is_in_table && !this.is_in_list &&
				this.current_tag != "img" && this.current_tag != "a" &&
				this.split_lines) {
				if (ch == ' ') { // If the next char is - it will become a list
					this.writer.append("\n");
				} else if (this.writer.chars_in_curr_line > this.hard_break) {
					this.replace_previous_space_in_line_by_newline();
				}
			}
		}

		/**
		 * Replace last space with newline.
		 */
		public bool replace_previous_space_in_line_by_newline()
		{
			if (this.current_tag == "p") {
				return false;
			}
			if (this.is_in_table && this.prev_tag != "code" && this.prev_tag != "pre") {
				return false;
			}
			return this.writer.replace_previous_space_in_line_by_newline();
				 
		}

		/**
		 * Reset converter state.
		 */
		private void reset()
		{
			this.writer.reset();
			this.tag_stack.clear();
			this.attr = null;
			this.current_tag = "";
			this.prev_tag = "";
			this.converted = false;
		}

		/**
		 * Check if in ignored tag.
		 */
		private bool is_in_ignored_tag()
		{
			if (this.current_tag == "title" && !this.include_title) {
				return true;
			}

			return this.is_ignored_tag(this.current_tag);
		}

		/**
		 * Check for hidden attributes from attribute map.
		 */
		private bool tag_contains_attributes_to_hide_from_map(Gee.HashMap<string, string> attrs)
		{
			// Check for hidden attribute (e.g., style="display:none")
			if (attrs.has_key("style")) {
				var style = attrs.get("style");
				if (style != null && style.index_of("display:none") != -1) {
					return true;
				}
			}
			return false;
		}

		/**
		 * Check if tag should be ignored.
		 */
		private bool is_ignored_tag(string tag)
		{
			return tag == "head" || tag == "meta" || tag == "nav" ||
				tag == "noscript" || tag == "script" || tag == "style" ||
				tag == "template";
		}

		 

 


		/**
		 * Initialize tag registry.
		 */
		private void initialize_tag_registry()
		{
			// non-printing tags
			var tag_ignored = new TagIgnored(this.writer);
			this.tags.set("head", tag_ignored);
			this.tags.set("meta", tag_ignored);
			this.tags.set("nav", tag_ignored);
			this.tags.set("noscript", tag_ignored);
			this.tags.set("script", tag_ignored);
			this.tags.set("style", tag_ignored);
			this.tags.set("template", tag_ignored);

			// printing tags
			this.tags.set("a", new TagAnchor(this.writer));
			this.tags.set("br", new TagBreak(this.writer));
			this.tags.set("div", new TagDiv(this.writer));
			this.tags.set("h1", new TagSimpleWithBreak(this.writer, "\n# ", "\n"));
			this.tags.set("h2", new TagSimpleWithBreak(this.writer, "\n## ", "\n"));
			this.tags.set("h3", new TagSimpleWithBreak(this.writer, "\n### ", "\n"));
			this.tags.set("h4", new TagSimpleWithBreak(this.writer, "\n#### ", "\n"));
			this.tags.set("h5", new TagSimpleWithBreak(this.writer, "\n##### ", "\n"));
			this.tags.set("h6", new TagSimpleWithBreak(this.writer, "\n###### ", "\n"));
			this.tags.set("li", new TagListItem(this.writer));
			this.tags.set("option", new TagOption(this.writer));
			this.tags.set("ol", new TagOrderedList(this.writer));
			this.tags.set("pre", new TagPre(this.writer));
			this.tags.set("code", new TagCode(this.writer));
			this.tags.set("p", new TagParagraph(this.writer));
			this.tags.set("span", new TagSimple(this.writer, ""));
			this.tags.set("ul", new TagUnorderedList(this.writer));
			this.tags.set("title", new TagTitle(this.writer));
			this.tags.set("img", new TagImage(this.writer));
			this.tags.set("hr", new TagSeperator(this.writer));

			// Text formatting
			var tag_bold = new TagSimple(this.writer, "**");
			this.tags.set("b", tag_bold);
			this.tags.set("strong", tag_bold);

			var tag_italic = new TagSimple(this.writer, "*");
			this.tags.set("i", tag_italic);
			this.tags.set("em", tag_italic);
			this.tags.set("dfn", tag_italic);
			this.tags.set("cite", tag_italic);

			this.tags.set("u", new TagUnderline(this.writer));

			var tag_strikethrough = new TagSimple(this.writer, "~");
			this.tags.set("s", tag_strikethrough);
			this.tags.set("del", tag_strikethrough);

			this.tags.set("blockquote", new TagBlockquote(this.writer));

			// Tables
			this.tags.set("table", new TagTable(this.writer));
			this.tags.set("tr", new TagTableRow(this.writer));
			this.tags.set("th", new TagTableHeader(this.writer));
			this.tags.set("td", new TagTableData(this.writer));
		}

		// Public methods for tag handlers
	}
}

+

