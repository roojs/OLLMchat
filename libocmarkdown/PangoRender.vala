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
	/**
	 * Simple renderer that converts markdown and HTML tags to Pango markup strings.
	 * 
	 * Extends Render and uses the parser to handle markdown and HTML tags, but instead
	 * of rendering to a buffer, it builds a Pango markup string.
	 * 
	 * Supported markdown tags:
	 * - *text* or _text_ - Italic text (<i>)
	 * - **text** or __text__ - Bold text (<b>)
	 * - ~~text~~ - Strikethrough text (<s>)
	 * - `text` - Code/monospace text (<tt>)
	 * 
	 * Supported HTML tags:
	 * - <b>, <strong> - Bold text
	 * - <i>, <em> - Italic text
	 * - <u> - Underlined text
	 * - <s>, <del> - Strikethrough text
	 * - <code> - Monospace text
	 * - <small> - Small text
	 * - <span> - Generic span (no styling by default)
	 */
	public class PangoRender : RenderBase
	{
		private StringBuilder pango_markup;
		private Gee.ArrayList<string> open_tags;
		private Gee.ArrayList<int> list_stack; // Stack of list numbers: 0 = ul, >0 = ol (number is the counter)
		
		/**
		 * Creates a new PangoRender instance.
		 */
		public PangoRender()
		{
			base();
			this.pango_markup = new StringBuilder();
			this.open_tags = new Gee.ArrayList<string>();
			this.list_stack = new Gee.ArrayList<int>();
		}
		
		/**
		 * Closes a tag by removing it from the open tags stack and appending the closing tag.
		 * 
		 * @param tag The tag name to close
		 */
		private void close_tag(string tag)
		{
			if (this.open_tags.size > 0) {
				this.open_tags.remove_at(this.open_tags.size - 1);
				this.pango_markup.append("</" + tag + ">");
			}
		}
		
		/**
		 * Converts Markup text to Pango string.
		 * 
		 * @param html_text The HTML text to convert
		 * @return Pango markup string
		 */
		public string toPango(string html_text)
		{
			this.pango_markup = new StringBuilder();
			this.open_tags.clear();
			this.list_stack.clear();
			
			// Use parser to process HTML tags
			this.start();
			this.add(html_text);
			this.flush();
			
			// Close any remaining open tags
			// Map tag names back to the appropriate method calls
			while (this.open_tags.size > 0) {
				var tag = this.open_tags[this.open_tags.size - 1];
				switch (tag) {
					case "i":
						this.on_em(false);
						break;
					case "b":
						this.on_strong(false);
						break;
					case "tt":
						this.on_code_span(false);
						break;
					case "s":
						this.on_del(false);
						break;
					case "span":
						this.on_html(false, "span", "");
						break;
					default:
						// Unknown tag - close it directly
						this.close_tag(tag);
						break;
				}
			}
			
			return this.pango_markup.str;
		}
		
		// Support all markdown formatting tags - convert to Pango markup
		public override void on_em(bool is_start)
		{
			if (!is_start) {
				this.close_tag("i");
				return;
			}
			
			this.pango_markup.append("<i>");
			this.open_tags.add("i");
		}
		
		public override void on_strong(bool is_start)
		{
			if (!is_start) {
				this.close_tag("b");
				return;
			}
			
			this.pango_markup.append("<b>");
			this.open_tags.add("b");
		}
		
		public override void on_code_span(bool is_start)
		{
			if (!is_start) {
				this.close_tag("tt");
				return;
			}
			
			this.pango_markup.append("<tt>");
			this.open_tags.add("tt");
		}
		
		public override void on_del(bool is_start)
		{
			if (!is_start) {
				this.close_tag("s");
				return;
			}
			
			this.pango_markup.append("<s>");
			this.open_tags.add("s");
		}
		
		/**
		 * Handles other unmapped tags.
		 */
		public override void on_other(bool is_start, string tag_name)
		{
			// For unknown tags, we don't add Pango markup
			// So we'll just ignore unknown tags
		}
		
		/**
		 * Handles HTML tags and converts them to Pango markup.
		 */
		public override void on_html(bool is_start, string tag, string attributes)
		{
			if (!is_start) {
				// Closing tag - close the most recently opened tag
				// We need to determine which tag was opened, so we'll use the tag parameter
				var tag_lower = tag.down();
				string? pango_tag = null;
				
				// Map HTML tag to Pango tag
				switch (tag_lower) {
					case "b":
					case "strong":
						pango_tag = "b";
						break;
					case "i":
					case "em":
						pango_tag = "i";
						break;
					case "u":
						pango_tag = "u";
						break;
					case "s":
					case "del":
						pango_tag = "s";
						break;
					case "code":
						pango_tag = "tt";
						break;
					case "small":
						pango_tag = "small";
						break;
					case "span":
						pango_tag = "span";
						break;
					default:
						// Unknown tag - try to close using the tag name as-is
						pango_tag = tag_lower;
						break;
				}
				
				if (pango_tag != null) {
					this.close_tag(pango_tag);
				}
				return;
			}
			
			// Opening tag
			var tag_lower = tag.down();
			string? pango_tag = null;
			
			// Convert HTML tags to Pango markup
			switch (tag_lower) {
				case "b":
				case "strong":
					pango_tag = "b";
					break;
					
				case "i":
				case "em":
					pango_tag = "i";
					break;
					
				case "u":
					pango_tag = "u";
					break;
					
				case "s":
				case "del":
					pango_tag = "s";
					break;
					
				case "code":
					pango_tag = "tt";
					break;
					
				case "small":
					pango_tag = "small";
					break;
					
				case "span":
					// Handle span with attributes (assume attributes are valid Pango markup)
					if (attributes != "") {
						this.pango_markup.append("<span " + attributes + ">");
					} else {
						this.pango_markup.append("<span>");
					}
					this.open_tags.add("span");
					return;
					
				default:
					// Unknown tag - ignore
					return;
			}
			
			if (pango_tag != null) {
				this.pango_markup.append("<" + pango_tag + ">");
				this.open_tags.add(pango_tag);
			}
		}
		
		/**
		 * Handles text content - escape and append to Pango markup.
		 */
		public override void on_text(string text)
		{
			// Escape special Pango markup characters
			var escaped = GLib.Markup.escape_text(text, -1);
			this.pango_markup.append(escaped);
		}
		
		/**
		 * Handles HTML entities (already decoded by parser).
		 */
		public override void on_entity(string text)
		{
			var escaped = GLib.Markup.escape_text(text, -1);
			this.pango_markup.append(escaped);
		}
		
		// Block-level callbacks - convert to Pango markup
		public override void on_h(bool is_start, uint level)
		{
			if (!is_start) {
				this.close_tag("span");
				this.pango_markup.append("\n");
				return;
			}
			
			// Use span with size attribute based on heading level
			string size_attr = "";
			switch (level) {
				case 1:
					size_attr = "size=\"xx-large\"";
					break;
				case 2:
					size_attr = "size=\"x-large\"";
					break;
				case 3:
					size_attr = "size=\"large\"";
					break;
				case 4:
					size_attr = "size=\"medium\"";
					break;
				case 5:
					size_attr = "size=\"small\"";
					break;
				case 6:
					size_attr = "size=\"x-small\"";
					break;
				default:
					size_attr = "size=\"large\"";
					break;
			}
			
			this.pango_markup.append("<span " + size_attr + " weight=\"bold\">");
			this.open_tags.add("span");
		}
		
		public override void on_p(bool is_start)
		{
			if (!is_start) {
				this.pango_markup.append("\n\n");
				return;
			}
			// Paragraph start - no markup needed, just content
		}
		
		/**
		 * Resets all list numbers above the specified level to 0.
		 * 
		 * @param level The indentation level (1-based) - resets levels above this
		 */
		private void reset_lists_above_level(uint level)
		{
			// Convert to 0-based index
			int target_index = (int)level - 1;
			// Reset all levels above this one (indices < target_index)
			for (int i = 0; i < target_index && i < this.list_stack.size; i++) {
				this.list_stack.set(i, 0);
			}
		}
		
		/**
		 * Closes lists that are deeper than the specified indentation level.
		 * 
		 * @param level The indentation level - only closes lists deeper than this
		 */
		private void close_lists_to_level(uint level)
		{
			int min_index = (int)level - 1; // Convert to 0-based index
			// Only close lists that are deeper (stack size > min_index + 1)
			while (this.list_stack.size > min_index + 1) {
				this.list_stack.remove_at(this.list_stack.size - 1);
			}
		}
		
		public override void on_ul(bool is_start, uint indentation)
		{
			if (!is_start) {
				this.pango_markup.append("\n");
				return;
			}
			
			// Close lists that are deeper than this indentation
			this.close_lists_to_level(indentation);
			
			// Convert indentation (1-based) to array index (0-based)
			int target_index = (int)indentation - 1;
			
			// Ensure we have enough levels in the stack
			while (this.list_stack.size <= target_index) {
				this.list_stack.add(0);
			}
			
			// Set this level to 0 (unordered list)
			this.list_stack.set(target_index, 0);
			
			// Reset all levels above this one
			this.reset_lists_above_level(indentation);
		}
		
		public override void on_ol(bool is_start, uint indentation)
		{
			if (!is_start) {
				this.pango_markup.append("\n");
				return;
			}
			
			// Close lists that are deeper than this indentation
			this.close_lists_to_level(indentation);
			
			// Convert indentation (1-based) to array index (0-based)
			int target_index = (int)indentation - 1;
			
			// Ensure we have enough levels in the stack
			while (this.list_stack.size <= target_index) {
				this.list_stack.add(0);
			}
			
			// If this is an ordered list, increment the counter
			this.list_stack.set(target_index, this.list_stack.get(target_index) + 1);
			
			// Reset all levels above this one
			this.reset_lists_above_level(indentation);
		}
		
		public override void on_li(bool is_start, bool is_task, char task_mark, uint task_mark_offset)
		{
			if (!is_start) {
				this.pango_markup.append("\n");
				return;
			}
			
			// Get the current indentation level (based on list_stack size)
			uint current_level = (uint)this.list_stack.size;
			if (current_level == 0) {
				// No list context - just add content
				return;
			}
			
			// Get the list type and number for the current level
			int list_number = this.list_stack.get((int)(current_level - 1));
			
			// Add tabs for indentation (1 + indent size)
			// indent size is current_level - 1 (since level 1 has 0 indent)
			uint indent_tabs = 1 + (current_level - 1);
			for (uint i = 0; i < indent_tabs; i++) {
				this.pango_markup.append("\t");
			}
			
			// Add marker based on list type
			if (is_task) {
				// Task list item - add checkbox marker
				// Use ✅ (U+2705) for checked, [_] for unchecked
				string marker = (task_mark == 'x' || task_mark == 'X') ? "✅" : "[_]";
				this.pango_markup.append(marker);
			} else if (list_number == 0) {
				// Unordered list - use bullet point
				this.pango_markup.append("•");
			} else {
				// Ordered list - use number + "."
				this.pango_markup.append(list_number.to_string() + ".");
			}
			
			// Add tab after marker before content
			this.pango_markup.append("\t");
		}
		
		public override void on_code(bool is_start, string? lang, char fence_char)
		{
			// Inline code - handled by on_code_span
			// This is for compatibility
			this.on_code_span(is_start);
		}
		
		public override void on_code_text(string text)
		{
			// Code block text content - escape and add as monospace
			var escaped = GLib.Markup.escape_text(text, -1);
			this.pango_markup.append(escaped);
		}
		
		public override void on_code_block(bool is_start, string lang)
		{
			if (!is_start) {
				this.close_tag("tt");
				this.pango_markup.append("\n");
				return;
			}
			
			// Code block start - use monospace font
			this.pango_markup.append("<tt>");
			this.open_tags.add("tt");
		}
		
		public override void on_quote(bool is_start)
		{
			if (!is_start) {
				this.close_tag("span");
				this.pango_markup.append("\n");
				return;
			}
			
			// Blockquote - use italic style and add quote marker
			this.pango_markup.append("<span style=\"italic\">");
			this.open_tags.add("span");
		}
		
		public override void on_hr()
		{
			// Horizontal rule - use a line of characters
			this.pango_markup.append("<span>━━━━━━━━━━━━━━━━━━━━━━━━━━━━</span>\n");
		}
		
		public override void on_a(bool is_start, string href, string title, bool is_autolink)
		{
			if (!is_start) {
				this.close_tag("span");
				return;
			}
			
			// Link - use blue color and underline
			this.pango_markup.append("<span foreground=\"blue\" underline=\"single\">");
			this.open_tags.add("span");
			// Add the href text
			var escaped_href = GLib.Markup.escape_text(href, -1);
			this.pango_markup.append(escaped_href);
			this.close_tag("span");
			// If there's a title, add it after
			if (title != "") {
				this.pango_markup.append(" ");
				var escaped_title = GLib.Markup.escape_text(title, -1);
				this.pango_markup.append("<b>" + escaped_title + "</b>");
			}
		}
		
		public override void on_img(string src, string? title)
		{
			// Image - use placeholder text
			var escaped_src = GLib.Markup.escape_text(src, -1);
			if (title != null && title != "") {
				var escaped_title = GLib.Markup.escape_text(title, -1);
				this.pango_markup.append("[IMG: " + escaped_title + " (" + escaped_src + ")]");
			} else {
				this.pango_markup.append("[IMG: " + escaped_src + "]");
			}
		}
		
		public override void on_br()
		{
			// Hard line break
			this.pango_markup.append("\n");
		}
		
		public override void on_softbr()
		{
			// Soft line break - use space (or newline in some contexts)
			this.pango_markup.append(" ");
		}
		
		public override void on_u(bool is_start)
		{
			if (!is_start) {
				this.close_tag("u");
				return;
			}
			
			// Underline
			this.pango_markup.append("<u>");
			this.open_tags.add("u");
		}
	}
}

