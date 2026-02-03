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
	 * Simple renderer that converts markdown to HTML strings.
	 * 
	 * Extends RenderBase and uses the parser to handle markdown and HTML tags,
	 * building an HTML string output.
	 * 
	 * Supported markdown elements:
	 * - Headings (h1-h6)
	 * - Paragraphs
	 * - Lists (ordered and unordered)
	 * - Code blocks and inline code
	 * - Blockquotes
	 * - Links and images
	 * - Text formatting (bold, italic, strikethrough, underline)
	 */
	public class HtmlRender : RenderBase
	{
		private StringBuilder html_output;
		private Gee.ArrayList<string> open_tags;
		private Gee.ArrayList<int> list_stack; // Stack of open lists: 0 = ul, 1 = ol, index = indentation level - 1
		private uint current_blockquote_level = 0; // Track current blockquote nesting level (1-6)
		private bool prev_text_ended_with_newline = false; // Track if previous on_text call ended with \n
		private bool prev_line_was_empty = false; // Track if previous line was empty
		
		/**
		 * Gets the current indentation level based on open tags.
		 */
		private int get_indent_level()
		{
			int level = 0;
			foreach (var tag in this.open_tags) {
				if (tag == "ul" || tag == "ol" || tag == "li") {
					level++;
				}
			}
			return level;
		}
		
		/**
		 * Appends a newline and indentation based on current nesting level.
		 * 
		 * @param before_tag If true, indent before the tag (for closing tags), 
		 *                   if false, indent after (for opening tags with content)
		 */
		private void append_indent(bool before_tag = true)
		{
			this.html_output.append("\n");
			int level = this.get_indent_level();
			// For closing tags, use current level; for opening tags, use level - 1
			int indent_level = before_tag ? level : (level > 0 ? level - 1 : 0);
			for (int i = 0; i < indent_level; i++) {
				this.html_output.append("  ");
			}
		}
			
		/**
		 * Creates a new HtmlRender instance.
		 */
		public HtmlRender()
		{
			base();
			this.html_output = new StringBuilder();
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
			// Find the tag in the stack (search from end to start)
			for (int i = this.open_tags.size - 1; i >= 0; i--) {
				if (this.open_tags.get(i) == tag) {
					// Close all tags after this one first (in reverse order)
					while (this.open_tags.size > i + 1) {
						var tag_to_close = this.open_tags.get(this.open_tags.size - 1);
						this.open_tags.remove_at(this.open_tags.size - 1);
						this.append_indent();
						this.html_output.append("</" + tag_to_close + ">");
					}
					// Close the target tag
					this.open_tags.remove_at(i);
					this.append_indent();
					this.html_output.append("</" + tag + ">");
					return;
				}
			}
			// Tag not found in stack - this shouldn't happen, but don't crash
		}
		
		/**
		 * Converts markdown text to HTML string.
		 * 
		 * @param markdown_text The markdown text to convert
		 * @return HTML string
		 */
		public string toHtml(string markdown_text)
		{
			this.html_output = new StringBuilder();
			this.open_tags.clear();
			this.list_stack.clear();
			this.prev_text_ended_with_newline = false;
			this.prev_line_was_empty = false;
				
			// Use parser to process markdown
			this.start();
			this.add(markdown_text);
			this.flush();
			
			// Close any remaining open tags (including lists)
			while (this.open_tags.size > 0) {
				this.close_tag(this.open_tags.get(this.open_tags.size - 1));
			}
			
			return this.html_output.str;
		}
		
		// Block-level callbacks - convert to HTML
		public override void on_h(bool is_start, uint level)
		{
			if (!is_start) {
				this.close_tag("h" + level.to_string());
				return;
			}
			
			this.html_output.append("<h" + level.to_string() + ">");
			this.open_tags.add("h" + level.to_string());
		}
			
		public override void on_p(bool is_start)
		{
			if (!is_start) {
				this.close_tag("p");
				return;
			}
			
			this.html_output.append("<p>");
			this.open_tags.add("p");
		}
			
		public override void on_ul(bool is_start, uint indentation)
		{
			if (!is_start) {
				return;
			}
			
			// Handle list nesting based on indentation (0 = ul)
			this.handle_list_start(0, indentation);
			
			// Close previous list item if we're at the same or shallower indentation
			// (after closing deeper lists, so list_stack reflects current state)
			this.close_li_if_needed(indentation);
			
			// Always open a list item when we see a list marker
			this.on_li(true);
		}
			
		public override void on_ol(bool is_start, uint indentation)
		{
			if (!is_start) {
				return;
			}
			
			// Handle list nesting based on indentation (1 = ol)
			this.handle_list_start(1, indentation);
			
			// Close previous list item if we're at the same or shallower indentation
			// (after closing deeper lists, so list_stack reflects current state)
			this.close_li_if_needed(indentation);
			
			// Always open a list item when we see a list marker
			this.on_li(true);
		}
		
		/**
		 * Closes the current list item if we're starting a new list item at the same or shallower indentation.
		 * 
		 * @param new_indentation The indentation of the new list item
		 */
		private void close_li_if_needed(uint new_indentation)
		{
			// Early return if no open <li> tag
			if (this.open_tags.size == 0 || this.open_tags.get(this.open_tags.size - 1) != "li") {
				return;
			}
			
			// Check if the new indentation is the same or less than current list depth
			// Current list depth is list_stack.size (0-based index + 1 = 1-based level)
			uint current_level = (uint)this.list_stack.size;
			if (new_indentation > current_level) {
				return; // Deeper level - keep list item open
			}
			
			// Same or shallower level - close the previous list item
			this.on_li(false);
		}
		
		/**
		 * Handles starting a list (ul or ol) with proper nesting based on indentation.
		 * Closes lists that are at deeper indentation levels, and opens new ones as needed.
		 * 
		 * @param list_type The list type (0 = ul, 1 = ol)
		 * @param indentation The indentation level (1 = first level, 2 = nested, etc.)
		 */
		private void handle_list_start(int list_type, uint indentation)
		{
			// Convert indentation (1-based) to array index (0-based)
			// Cap at maximum of 5 levels to prevent excessive nesting
			int target_index = ((int)indentation > 6) ? 5 : (int)indentation - 1;
			
			// Close lists that are deeper than this indentation (does nothing if level is higher)
			this.close_lists_to_level(indentation);
			
			// Check if we're at an existing level
			if (target_index >= this.list_stack.size) {
				// New list at this level - may need to open multiple nested lists
				// Fill in any missing levels (for big jumps in indentation)
				while (this.list_stack.size < target_index) {
					// Use the same list type for intermediate levels
					this.open_list_tag(list_type);
				}
				// Add the final list at target level
				this.open_list_tag(list_type);
				return;
			}
			
			// Same level - check if we need to switch list type
			if (this.list_stack.get(target_index) == list_type) {
				return; // Same list type at same level - nothing to do
			}
			
			// Switch list type - close old, open new
			this.close_list_tag(this.list_stack.get(target_index));
			this.open_list_tag(list_type);
			// New list at this level - may need to open multiple nested lists
			// Fill in any missing levels (for big jumps in indentation)
			while (this.list_stack.size < target_index) {
				// Use the same list type for intermediate levels
				this.open_list_tag(list_type);
			}
			// Add the final list at target level
			this.open_list_tag(list_type);
			
		}
		
		/**
		 * Opens a list tag (ul or ol) and adds it to open_tags and list_stack.
		 * 
		 * @param list_type The list type (0 = ul, 1 = ol)
		 */
		private void open_list_tag(int list_type)
		{
			var tag = (list_type == 0) ? "ul" : "ol";
			this.append_indent(true);
			this.html_output.append("<" + tag + ">");
			this.open_tags.add(tag);
			this.list_stack.add(list_type);
		}
		
		/**
		 * Closes a list tag (ul or ol) by finding it in open_tags and closing it.
		 * Closes all list items that are direct children of this list before closing the list tag.
		 * 
		 * @param list_type The list type (0 = ul, 1 = ol)
		 */
		private void close_list_tag(int list_type)
		{
			// Remove from list_stack first
			if (this.list_stack.size > 0) {
				this.list_stack.remove_at(this.list_stack.size - 1);
			}
			
			// Convert list_type to tag string
			var tag = (list_type == 0) ? "ul" : "ol";
			
			// Find the list tag in open_tags
			var tag_index = -1;
			for (int i = this.open_tags.size - 1; i >= 0; i--) {
				if (this.open_tags.get(i) == tag) {
					tag_index = i;
					break;
				}
			}
			
			if (tag_index != -1) {
				// Close all tags after the list tag until we hit another list tag
				// This ensures we only close direct children (list items) and not parent list items
				while (this.open_tags.size > tag_index + 1) {
					var tag_to_close = this.open_tags.get(this.open_tags.size - 1);
					// Stop if we hit another list tag (ul or ol) - that's a nested list, not a child
					if (tag_to_close == "ul" || tag_to_close == "ol") {
						break;
					}
					// If it's a list item, use on_li to close it properly
					if (tag_to_close == "li") {
						this.on_li(false);
						continue;
					}
					this.close_tag(tag_to_close);
				}
				// Close the list tag itself (with proper indentation)
				this.append_indent();
				this.html_output.append("</" + tag + ">");
				// Remove from open_tags (close_tag would do this, but we're calling it directly)
				this.open_tags.remove_at(tag_index);
			}
		}
		
		/**
		 * Closes all lists deeper than the specified indentation level.
		 * 
		 * @param level The indentation level - only closes lists deeper than this
		 */
		private void close_lists_to_level(uint level)
		{
			int min_index = (int)level - 1; // Convert to 0-based index
			// Only close lists that are deeper (stack size > min_index + 1)
			while (this.list_stack.size > min_index + 1) {
				this.close_list_tag(this.list_stack.get(this.list_stack.size - 1));
			}
		}
		
		/**
		 * Closes all blockquotes deeper than the specified level.
		 * 
		 * @param level The blockquote level - only closes blockquotes deeper than this
		 */
		private void close_blockquotes_to_level(uint level)
		{
			// Close blockquotes that are deeper than the target level
			while (this.current_blockquote_level > level) {
				this.append_indent();
				this.html_output.append("</blockquote>");
				// Remove from open_tags
				for (int i = this.open_tags.size - 1; i >= 0; i--) {
					if (this.open_tags.get(i) == "blockquote") {
						this.open_tags.remove_at(i);
						break;
					}
				}
				this.current_blockquote_level--;
			}
		}
		
		public override void on_li(bool is_start)
		{
			if (!is_start) {
				this.close_tag("li");
				return;
			}
			
			this.append_indent(true);
			this.html_output.append("<li>");
			this.open_tags.add("li");
		}
		
		public override void on_task_list(bool is_start, bool is_checked)
		{
			if (!is_start) {
				return;
			}
			
			// Task list checkbox - add to current list item
			this.html_output.append("<input type=\"checkbox\" disabled" + (is_checked ? " checked" : "") + ">");
		}
		
		public override void on_code(bool is_start, string? lang, char fence_char)
		{
			// Inline code - handled by on_code_span
			this.on_code_span(is_start);
		}
		
		public override void on_code_text(string text)
		{
			// Code block text content - escape HTML
			var escaped = GLib.Markup.escape_text(text, -1);
			this.html_output.append(escaped);
		}
		
		public override void on_code_block(bool is_start, string lang)
		{
			if (!is_start) {
				this.close_tag("pre");
				this.close_tag("code");
				return;
			}
			
			// Code block - use <pre><code> with optional language class
			if (lang == null || lang == "") {
				this.html_output.append("<pre><code>");
				this.open_tags.add("code");
				this.open_tags.add("pre");
				return;
			}
			this.html_output.append("<pre><code class=\"language-" + GLib.Markup.escape_text(lang, -1) + "\">");
			this.open_tags.add("code");
			this.open_tags.add("pre");
		}
			
		public override void on_quote(bool is_start, uint level)
		{
			if (!is_start) {
				// End of blockquote line is meaningless - closing happens when
				// we see a new blockquote level or on blank lines
				return;
			}
			
			// Close blockquotes that are deeper than the new level
			this.close_blockquotes_to_level(level);
			
			// Open blockquotes to reach the target level
			while (this.current_blockquote_level < level) {
				this.current_blockquote_level++;
				this.append_indent(true);
				this.html_output.append("<blockquote>");
				this.open_tags.add("blockquote");
			}
		}
		
		public override void on_hr()
		{
			this.html_output.append("<hr>");
		}
		
		public override void on_table(bool is_start)
		{
			if (!is_start) {
				this.close_tag("table");
				return;
			}
			this.append_indent(false);
			this.html_output.append("<table>\n");
			this.open_tags.add("table");
		}
		
		public override void on_table_row(bool is_start)
		{
			if (!is_start) {
				this.close_tag("tr");
				return;
			}
			this.append_indent(false);
			this.html_output.append("<tr>\n");
			this.open_tags.add("tr");
		}
		
		public override void on_table_hcell(bool is_start, int align)
		{
			if (!is_start) {
				this.close_tag("th");
				return;
			}
			this.append_indent(false);
			this.html_output.append("<th style=\"text-align: "
				+ (align == 0 ? "center" : (align == 1 ? "right" : "left")) + "\">");
			this.open_tags.add("th");
		}
		
		public override void on_table_cell(bool is_start, int align)
		{
			if (!is_start) {
				this.close_tag("td");
				return;
			}
			this.append_indent(false);
			this.html_output.append("<td style=\"text-align: "
				+ (align == 0 ? "center" : (align == 1 ? "right" : "left")) + "\">");
			this.open_tags.add("td");
		}
		
		public override void on_a(bool is_start, string href, string title, bool is_reference)
		{
			if (!is_start) {
				this.close_tag("a");
				return;
			}
			
			// Link - escape href and title
			var escaped_href = GLib.Markup.escape_text(href, -1);
			if (title == "") {
				this.html_output.append("<a href=\"" + escaped_href + "\">");
				this.open_tags.add("a");
				return;
			}
			var escaped_title = GLib.Markup.escape_text(title, -1);
			this.html_output.append("<a href=\"" + escaped_href + "\" title=\"" + escaped_title + "\">");
			this.open_tags.add("a");
		}
		
		public override void on_img(string src, string? title)
		{
			// Image - escape src and title
			var escaped_src = GLib.Markup.escape_text(src, -1);
			if (title == null || title == "") {
				this.html_output.append("<img src=\"" + escaped_src + "\" alt=\"\">");
				return;
			}
			var escaped_title = GLib.Markup.escape_text(title, -1);
			this.html_output.append("<img src=\"" + escaped_src + "\" alt=\"" + escaped_title + "\" title=\"" + escaped_title + "\">");
		}
		
		public override void on_br()
		{
			this.html_output.append("<br>");
		}
		
		public override void on_softbr()
		{
			// Soft break - use space or newline depending on context
			this.html_output.append(" ");
		}
		
		// Inline formatting callbacks
		public override void on_em(bool is_start)
		{
			if (!is_start) {
				this.close_tag("em");
				return;
			}
			
			this.html_output.append("<em>");
			this.open_tags.add("em");
		}
		
		public override void on_strong(bool is_start)
		{
			if (!is_start) {
				this.close_tag("strong");
				return;
			}
			
			this.html_output.append("<strong>");
			this.open_tags.add("strong");
		}
		
		public override void on_code_span(bool is_start)
		{
			if (!is_start) {
				this.close_tag("code");
				return;
			}
			
			this.html_output.append("<code>");
			this.open_tags.add("code");
		}
		
		public override void on_del(bool is_start)
		{
			if (!is_start) {
				this.close_tag("del");
				return;
			}
			
			this.html_output.append("<del>");
			this.open_tags.add("del");
		}
		
		public override void on_u(bool is_start)
		{
			if (!is_start) {
				this.close_tag("u");
				return;
			}
			
			this.html_output.append("<u>");
			this.open_tags.add("u");
		}
		
		/**
		* Handles text content - escape and append to HTML.
		*/
		public override void on_text(string text)
		{
			// Check for empty line (just whitespace/newlines)
			var stripped = text.strip();
			this.prev_line_was_empty = (stripped.length == 0 && (text.contains("\n") || text == ""));
			
			// Check for double newline - if previous text ended with \n and current starts with \n
			// or if text contains \n\n, that indicates a new block - close list items and lists if open
			bool has_double_newline = (this.prev_text_ended_with_newline && text.has_prefix("\n")) || text.contains("\n\n");
			
			if (has_double_newline) {
				// Close all list items first
				while (this.open_tags.size > 0 && this.open_tags.get(this.open_tags.size - 1) == "li") {
					this.on_li(false);
				}
				// Close all lists on double newline (end of list block)
				if (this.list_stack.size > 0) {
					this.close_lists_to_level(0);
				}
				// Close all blockquotes on double newline (blank line)
				if (this.current_blockquote_level > 0) {
					this.close_blockquotes_to_level(0);
				}
			}
			
			// Track if this text ends with a newline for the next call
			this.prev_text_ended_with_newline = text.has_suffix("\n");
			
			// Escape special HTML characters
			var escaped = GLib.Markup.escape_text(text, -1);
			this.html_output.append(escaped);
		}
			
		/**
		 * Handles HTML entities (already decoded by parser).
		 */
		public override void on_entity(string text)
		{
			var escaped = GLib.Markup.escape_text(text, -1);
			this.html_output.append(escaped);
		}
		
		/**
		 * Handles HTML tags - pass through as-is (already valid HTML).
		 */
		public override void on_html(bool is_start, string tag, string attributes)
		{
			if (!is_start) {
				this.close_tag(tag);
				return;
			}
			
			// Opening tag - reconstruct from tag name and attributes
			if (attributes == "") {
				this.html_output.append("<" + tag + ">");
				this.open_tags.add(tag);
				return;
			}
			this.html_output.append("<" + tag + " " + attributes + ">");
			this.open_tags.add(tag);
		}
		
		/**
		* Handles other unmapped tags.
		*/
		public override void on_other(bool is_start, string tag_name)
		{
			// For unknown tags, we don't add HTML markup
			// So we'll just ignore unknown tags
		}
		
	}
}
