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
	 * Renders markdown content to a Gtk.TextBuffer using a state-based renderer.
	 * 
	 * Processes markdown blocks and spans, converting them to Pango markup
	 * and inserting them into the specified TextBuffer range.
	 */
	public class Render : Object
	{
		public Gtk.TextBuffer buffer { get; private set; }
		public Gtk.TextMark start_mark { get; private set; }
		public Gtk.TextMark end_mark { get; private set; }
		public Gtk.TextMark tmp_start { get; private set; }
		public Gtk.TextMark tmp_end { get; private set; }
		public TopState top_state { get; private set; }
		public State current_state { get; internal set; }
		public Parser parser { get; private set; }
		
		/**
		 * Creates a new Render instance.
		 * 
		 * @param buffer The TextBuffer to render into
		 * @param start_mark Start mark for the range
		 */
		public Render(Gtk.TextBuffer buffer, Gtk.TextMark start_mark)
		{
			this.buffer = buffer;
			this.start_mark = start_mark;
			
			// Create end_mark at the same position as start_mark
			Gtk.TextIter iter;
			this.buffer.get_iter_at_mark(out iter, start_mark);
			this.end_mark = this.buffer.create_mark(null, iter, true);
			
			// Create temporary marks after end_mark for incremental parsing
			this.buffer.get_iter_at_mark(out iter, this.end_mark);
			this.tmp_start = this.buffer.create_mark(null, iter, true);
			this.tmp_end = this.buffer.create_mark(null, iter, true);
			
			// Create parser instance
			this.parser = new Parser(this);
			
			// Create top_state
			this.top_state = new TopState(this);
			
			// Initialize current_state to top_state (never null)
			this.current_state = this.top_state;
		}
		
		/**
		 * Main method: adds text to be parsed and rendered.
		 * Uses temporary buffer for incremental parsing - if parser returns 0 (success),
		 * temporary content is cleared. Otherwise, it's filled with parser.pending content.
		 * 
		 * @param text The markdown text to process
		 */
		public void add(string text)
		{
			// Parse the text (parser.add() is quick)
			if (this.parser.add(text) == 0) {
				// Success: clear any existing temporary content
				Gtk.TextIter iter;
				this.buffer.get_iter_at_mark(out iter, this.tmp_start);
				Gtk.TextIter end_iter;
				this.buffer.get_iter_at_mark(out end_iter, this.tmp_end);
				if (iter.equal(end_iter)) {
					return;
				}
				this.buffer.delete(ref iter, ref end_iter);
				// Reset tmp_end to tmp_start
				this.buffer.get_iter_at_mark(out iter, this.tmp_start);
				this.buffer.move_mark(this.tmp_end, iter);
				return;
			}
			
			// Error: add parser.pending content to temporary buffer
			Gtk.TextIter iter;
			this.buffer.get_iter_at_mark(out iter, this.tmp_start);
			// Clear any existing temp content first
			Gtk.TextIter end_iter;
			this.buffer.get_iter_at_mark(out end_iter, this.tmp_end);
			if (!iter.equal(end_iter)) {
				this.buffer.delete(ref iter, ref end_iter);
				this.buffer.get_iter_at_mark(out iter, this.tmp_start);
			}
			this.buffer.insert(ref iter, this.parser.pending.str, -1);
			// Update tmp_end
			iter.forward_chars(this.parser.pending.str.length);
			this.buffer.move_mark(this.tmp_end, iter);
		}
		
		// Callback methods for parser
		
		/**
		 * Callback for header blocks.
		 * 
		 * @param level Header level (1-6)
		 */
		internal void on_h(uint level)
		{
			string tag = "h" + level.to_string();
			string size_attr = "";
			switch (level) {
				case 1:
					size_attr = "size=\"xx-large\" weight=\"bold\"";
					break;
				case 2:
					size_attr = "size=\"x-large\" weight=\"bold\"";
					break;
				case 3:
					size_attr = "size=\"large\" weight=\"bold\"";
					break;
				default:
					size_attr = "weight=\"bold\"";
					break;
			}
			this.current_state.add_state(tag, size_attr);
		}
		
		/**
		 * Callback for unordered list blocks.
		 * 
		 * @param is_tight Whether the list is tight
		 * @param mark The list marker character
		 */
		internal void on_ul(bool is_tight, char mark)
		{
			this.current_state.add_state("ul", "");
		}
		
		/**
		 * Callback for ordered list blocks.
		 * 
		 * @param start The starting number
		 * @param is_tight Whether the list is tight
		 * @param mark_delimiter The delimiter character
		 */
		internal void on_ol(uint start, bool is_tight, char mark_delimiter)
		{
			this.current_state.add_state("ol", "");
		}
		
		/**
		 * Callback for list item blocks.
		 * 
		 * @param is_task Whether this is a task list item
		 * @param task_mark The task marker character
		 * @param task_mark_offset The offset of the task marker
		 */
		internal void on_li(bool is_task, char task_mark, uint task_mark_offset)
		{
			this.current_state.add_state("li", "");
		}
		
		/**
		 * Callback for code blocks.
		 * 
		 * @param lang The language identifier (may be null)
		 * @param fence_char The fence character used
		 */
		internal void on_code(string? lang, char fence_char)
		{
			this.current_state.add_state("code", "");
		}
		
		/**
		 * Callback for paragraph blocks.
		 */
		internal void on_p()
		{
			this.current_state.add_state("p", "");
		}
		
		/**
		 * Callback for blockquote blocks.
		 */
		internal void on_quote()
		{
			this.current_state.add_state("blockquote", "");
		}
		
		/**
		 * Callback for horizontal rule blocks.
		 */
		internal void on_hr()
		{
			this.current_state.add_text("<span size=\"large\">━━━━━━━━━━━━━━━━━━━━━━━━━━━━</span>\n");
		}
		
		/**
		 * Callback for link spans.
		 * 
		 * @param href The link URL
		 * @param title The link title 
		 * @param is_autolink Whether this is an autolink
		 */
		internal void on_a(string href, string title, bool is_autolink)
		{
			// Add span state (blue, underlined) for the link
			var link_state = this.current_state.add_state("
				span", "color=\"blue\" underline=\"single\"");
			
			// Add the href text
			link_state.add_text(href);
			
			// Close the link span
			link_state.close_state();
			this.current_state.add_text(" ");
			this.current_state.add_state("b", "");
			// If there's a title, add it in bold after a space (leave bold state open)
			if (title != "") {
			
				this.current_state.add_text(title);
			}
		}
		
		/**
		 * Callback for image spans.
		 * 
		 * @param src The image source URL
		 * @param title The image title (may be null)
		 */
		internal void on_img(string src, string? title)
		{
			// Images not fully supported - just add placeholder
			this.current_state.add_text("[IMG:");
		}
		
		/**
		 * Callback for emphasis/italic spans.
		 */
		internal void on_em()
		{
			this.current_state.add_state("i", "");
		}
		
		/**
		 * Callback for strong/bold spans.
		 */
		internal void on_strong()
		{
			this.current_state.add_state("b", "");
		}
		
		/**
		 * Callback for underline spans.
		 */
		internal void on_u()
		{
			this.current_state.add_state("u", "");
		}
		
		/**
		 * Callback for strikethrough spans.
		 */
		internal void on_del()
		{
			this.current_state.add_state("s", "");
		}
		
		/**
		 * Callback for inline code spans.
		 */
		internal void on_code_span()
		{
			this.current_state.add_state("tt", "");
		}
		
		/**
		 * Generic callback for unmapped block/span types.
		 * 
		 * @param tag_name The tag name
		 */
		internal void on_other(string tag_name)
		{
			this.current_state.add_state(tag_name, "");
		}
		
		/**
		 * Callback for normal text content.
		 * 
		 * @param text The text content
		 */
		internal void on_text(string text)
		{
			this.current_state.add_text(text);
		}
		
		/**
		 * Callback for line breaks (hard breaks).
		 */
		internal void on_br()
		{
			this.current_state.add_text("\n");
		}
		
		/**
		 * Callback for soft line breaks.
		 * Inserts a space (or newline in code blocks).
		 */
		internal void on_softbr()
		{
			// For now, just add a space (code block handling can be added later if needed)
			this.current_state.add_text(" ");
		}
		
		/**
		 * Callback for HTML entities.
		 * The entity is already decoded, so just add as text.
		 * 
		 * @param text The decoded entity text
		 */
		internal void on_entity(string text)
		{
			this.current_state.add_text(text);
		}
		
		/**
		 * Callback for HTML tags.
		 * Parser sends the tag name and attributes, we create a new state,
		 * and parser will call on_end() for the close tag.
		 * 
		 * @param tag The HTML tag name (e.g., "div", "span")
		 * @param attributes The HTML tag attributes (e.g., "class='test'")
		 */
		internal void on_html(string tag, string attributes)
		{
			this.current_state.add_state(tag, attributes);
		}
		
		/**
		 * Generic callback to close the current state.
		 * Used for closing blocks/spans.
		 */
		internal void on_end()
		{
			this.current_state.close_state();
		}
	}
}
