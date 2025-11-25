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

using Gee;
using Xml;

namespace Markdown
{
	// HTML parser function from libxml2
	[CCode (cname = "htmlSAXParseDoc", cheader_filename = "libxml/HTMLparser.h")]
	public unowned Doc* htmlSAXParseDoc(uint8[] cur, unowned string encoding, SAXHandler* sax, void* user_data);
	/**
	 * Converts HTML to Markdown format.
	 */
	public class FromHTML : Object
	{
		// Options as properties
		public bool compress_whitespace { get; set; default = true; }
		public bool escape_numbered_list { get; set; default = true; }
		public bool force_left_trim { get; set; default = false; }
		public bool include_title { get; set; default = true; }
		public bool split_lines { get; set; default = true; }
		public int soft_break { get; set; default = 80; }
		public int hard_break { get; set; default = 120; }
		public char unordered_list { get; set; default = '-'; }
		public char ordered_list { get; set; default = '.'; }

		// Converter properties (public for tag handlers)
		public string html;
		public Writer writer;
		public Gee.HashMap<string, TagIgnored> tags;
		public string current_tag = "";
		public string prev_tag = "";
		public bool is_in_pre = false;
		public bool is_in_code = false;
		public bool is_in_list = false;
		public bool is_in_ordered_list = false;
		public bool is_in_p = false;
		public char prev_ch_in_html = 0;
		public int index_blockquote = 0;
		public int index_li = 0;
		public int index_ol = 0;
		
		// Tag stack for tracking nested tags
		private Gee.ArrayList<string> tag_stack;
		// Current attributes for extract_attribute()
		private Gee.HashMap<string, string>? current_attributes;
		// Track if we've converted already
		private bool converted = false;

		/**
		 * Constructor.
		 *
		 * @param html Input HTML string to convert
		 */
		public FromHTML(string html)
		{
			this.html = html;
			this.writer = new Writer();
			this.tags = new Gee.HashMap<string, TagIgnored>();
			this.tag_stack = new Gee.ArrayList<string>();
			this.current_attributes = null;

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

			// Create SAX handler
			SaxHandler sax_handler = SaxHandler();
			sax_handler.start_document = this.sax_start_document;
			sax_handler.end_document = this.sax_end_document;
			sax_handler.start_element = this.sax_start_element;
			sax_handler.end_element = this.sax_end_element;
			sax_handler.characters = this.sax_characters;

			// Parse HTML with libxml2 HTML parser
			unowned uint8[] data = this.html.data;
			var doc = htmlSAXParseDoc(data, "UTF-8", &sax_handler, this);
			if (doc != null) {
				xmlFreeDoc(doc);
			}

			this.writer.clean_up_markdown();
			this.converted = true;

			return this.writer.to_string();
		}
 

		 


		/**
		 * Check if conversion is in clean state.
		 */
		public bool ok()
		{
			return !this.is_in_pre && !this.is_in_list && !this.is_in_p &&
				this.tag_stack.size == 0 && this.index_blockquote == 0 && this.index_li == 0;
		}



		/**
		 * Extract attribute value from tag.
		 */
		public string extract_attribute(string attr)
		{
			if (this.current_attributes == null) {
				return "";
			}

			// Case-insensitive lookup
			var attr_lower = attr.down();
			foreach (var key in this.current_attributes.keys) {
				if (key.down() == attr_lower) {
					return this.current_attributes.get(key);
				}
			}

			return "";
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
		 * SAX callback: Start of document.
		 */
		private void sax_start_document(void* ctx)
		{
			// Nothing to do
		}

		/**
		 * SAX callback: End of document.
		 */
		private void sax_end_document(void* ctx)
		{
			// Nothing to do
		}

		/**
		 * SAX callback: Start element.
		 */
		private void sax_start_element(void* ctx, unowned string name, unowned string[] attrs)
		{
			var converter = (FromHTML)ctx;
			converter.writer.update_prev_ch();

			var tag_name = name.down();
			
			// Store attributes for extract_attribute()
			converter.current_attributes = new Gee.HashMap<string, string>();
			for (int i = 0; attrs[i] != null; i += 2) {
				if (attrs[i + 1] != null) {
					converter.current_attributes.set(attrs[i], attrs[i + 1]);
				}
			}

			// Check for hidden attributes
			if (converter.tag_contains_attributes_to_hide_from_map(converter.current_attributes)) {
				converter.current_attributes = null;
				return;
			}

			// Update tag stack
			if (converter.tag_stack.size > 0) {
				converter.prev_tag = converter.tag_stack[converter.tag_stack.size - 1];
			} else {
				converter.prev_tag = "";
			}
			converter.current_tag = tag_name;
			converter.tag_stack.add(tag_name);

			// Get tag handler
			var tag = converter.tags.get(tag_name);
			if (tag != null) {
				tag.open(converter);
			}

			converter.current_attributes = null;
		}

		/**
		 * SAX callback: End element.
		 */
		private void sax_end_element(void* ctx, unowned string name)
		{
			var converter = (FromHTML)ctx;
			converter.writer.update_prev_ch();

			var tag_name = name.down();
			converter.current_tag = tag_name;

			// Get tag handler
			var tag = converter.tags.get(tag_name);
			if (tag != null) {
				tag.close(converter);
			}

			// Update tag stack
			if (converter.tag_stack.size > 0 && converter.tag_stack[converter.tag_stack.size - 1] == tag_name) {
				converter.tag_stack.remove_at(converter.tag_stack.size - 1);
			}

			// Update current_tag and prev_tag from stack
			if (converter.tag_stack.size > 0) {
				converter.current_tag = converter.tag_stack[converter.tag_stack.size - 1];
				if (converter.tag_stack.size > 1) {
					converter.prev_tag = converter.tag_stack[converter.tag_stack.size - 2];
				} else {
					converter.prev_tag = "";
				}
			} else {
				converter.current_tag = "";
				converter.prev_tag = "";
			}
		}

		/**
		 * SAX callback: Character data.
		 */
		private void sax_characters(void* ctx, unowned string ch, int len)
		{
			var converter = (FromHTML)ctx;
			var text = ch.substring(0, len);

			// Process character by character to preserve existing logic
			unowned uint8[] data = text.data;
			for (int i = 0; i < data.length && i < len; i++) {
				char c = (char)data[i];
				converter.process_character(c);
			}
		}

		/**
		 * Process a single character (moved from parse_char_in_tag_content).
		 */
		private void process_character(char ch)
		{
			if (this.is_in_code) {
				this.writer.append(ch);

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

			switch (ch)
			{
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
					
					this.writer.append(ch);
					
					break;
				default:
					this.writer.append(ch);
					break;
			}

			if (this.writer.chars_in_curr_line > this.soft_break && !this.is_in_list &&
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
			return this.writer.replace_previous_space_in_line_by_newline();
				 
		}

		/**
		 * Reset converter state.
		 */
		private void reset()
		{
			this.writer.reset();
			this.tag_stack.clear();
			this.current_attributes = null;
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
		}

		// Public methods for tag handlers
	}
}

