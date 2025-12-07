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
		
		/**
		 * Creates a new HtmlRender instance.
		 */
		public HtmlRender()
		{
			base();
			this.html_output = new StringBuilder();
			this.open_tags = new Gee.ArrayList<string>();
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
				this.html_output.append("</" + tag + ">");
			}
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
			
			// Use parser to process markdown
			this.start();
			this.add(markdown_text);
			this.flush();
			
			// Close any remaining open tags
			while (this.open_tags.size > 0) {
				var tag = this.open_tags[this.open_tags.size - 1];
				this.close_tag(tag);
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
		
		public override void on_ul(bool is_start, bool is_tight, char mark)
		{
			if (!is_start) {
				this.close_tag("ul");
				return;
			}
			
			this.html_output.append("<ul>");
			this.open_tags.add("ul");
		}
		
		public override void on_ol(bool is_start, uint start, bool is_tight, char mark_delimiter)
		{
			if (!is_start) {
				this.close_tag("ol");
				return;
			}
			
			if (start != 1) {
				this.html_output.append("<ol start=\"" + start.to_string() + "\">");
			} else {
				this.html_output.append("<ol>");
			}
			this.open_tags.add("ol");
		}
		
		public override void on_li(bool is_start, bool is_task, char task_mark, uint task_mark_offset)
		{
			if (!is_start) {
				this.close_tag("li");
				return;
			}
			
			if (is_task) {
				// Task list item - use checkbox
				bool checked = (task_mark == 'x' || task_mark == 'X');
				this.html_output.append("<li><input type=\"checkbox\" disabled" + (checked ? " checked" : "") + ">");
			} else {
				this.html_output.append("<li>");
			}
			this.open_tags.add("li");
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
			if (lang != null && lang != "") {
				this.html_output.append("<pre><code class=\"language-" + GLib.Markup.escape_text(lang, -1) + "\">");
			} else {
				this.html_output.append("<pre><code>");
			}
			this.open_tags.add("code");
			this.open_tags.add("pre");
		}
		
		public override void on_quote(bool is_start)
		{
			if (!is_start) {
				this.close_tag("blockquote");
				return;
			}
			
			this.html_output.append("<blockquote>");
			this.open_tags.add("blockquote");
		}
		
		public override void on_hr()
		{
			this.html_output.append("<hr>");
		}
		
		public override void on_a(bool is_start, string href, string title, bool is_autolink)
		{
			if (!is_start) {
				this.close_tag("a");
				return;
			}
			
			// Link - escape href and title
			var escaped_href = GLib.Markup.escape_text(href, -1);
			var escaped_title = GLib.Markup.escape_text(title, -1);
			
			if (title != "") {
				this.html_output.append("<a href=\"" + escaped_href + "\" title=\"" + escaped_title + "\">");
			} else {
				this.html_output.append("<a href=\"" + escaped_href + "\">");
			}
			this.open_tags.add("a");
		}
		
		public override void on_img(string src, string? title)
		{
			// Image - escape src and title
			var escaped_src = GLib.Markup.escape_text(src, -1);
			if (title != null && title != "") {
				var escaped_title = GLib.Markup.escape_text(title, -1);
				this.html_output.append("<img src=\"" + escaped_src + "\" alt=\"" + escaped_title + "\" title=\"" + escaped_title + "\">");
			} else {
				this.html_output.append("<img src=\"" + escaped_src + "\" alt=\"\">");
			}
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
			if (attributes != "") {
				this.html_output.append("<" + tag + " " + attributes + ">");
			} else {
				this.html_output.append("<" + tag + ">");
			}
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
