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
	 * Renders markdown content to a Gtk.TextBuffer using a
	 * state-based renderer.
	 * 
	 * Processes markdown blocks and spans, converting them to
	 * Pango markup and inserting them into the specified TextBuffer range.
	 * 
	 * ## Entry Points
	 * 
	 * The Render class provides three public methods for processing content:
	 * 
	 * - {@link add}: Adds text to be parsed and rendered incrementally. Use this
	 * for streaming content where you receive chunks over time.
	 * 
	 * - {@link add_start}: Starts a new chunk of content. This resets the parser's internal state and
	 * should be called when beginning a new content block. You should call {@link flush} before calling this if you've been
	 * adding content with {@link add}.
	 * 
	 * - {@link flush}: Finalizes the current chunk. Call this before starting a new chunk with {@link add_start} 
	 * to ensure all pending content is processed.
	 * 
	 * HTML tags embedded in the markdown content are automatically parsed and
	 * handled. The parser recognizes HTML tags and creates states for them. You
	 * only need to provide opening HTML tags in your content. The renderer
	 * automatically handles closing tags when the corresponding state is closed
	 * or when flush is called.
	 */
	public class Render : RenderBase
	{
		public Gtk.TextBuffer buffer { get; private set; }
		public Gtk.TextMark start_mark { get; private set; }
		public Gtk.TextMark end_mark { get; private set; }
		public Gtk.TextMark tmp_start { get; private set; }
		public Gtk.TextMark tmp_end { get; private set; }
		public TopState top_state { get; private set; }
		public State current_state { get; internal set; }
		
		/**
		 * Creates a new Render instance.
		 * 
		 * @param buffer The TextBuffer to render into
		 * @param start_mark Start mark for the range
		 */
		public Render(Gtk.TextBuffer buffer, Gtk.TextMark start_mark)
		{
			base();
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
			
			// Create top_state
			this.top_state = new TopState(this);
			
			// Initialize current_state to top_state (never null)
			this.current_state = this.top_state;
		}
		
		
		// Callback methods for parser
		
		/**
		 * Callback for header blocks.
		 * 
		 * @param level Header level (1-6)
		 */
		internal override void on_h(uint level)
		{
			var h_state = this.current_state.add_state();
			h_state.style.weight = Pango.Weight.BOLD;
			switch (level) {
				case 1:
					h_state.style.scale = Pango.Scale.XX_LARGE;
					break;
				case 2:
					h_state.style.scale = Pango.Scale.X_LARGE;
					break;
				case 3:
					h_state.style.scale = Pango.Scale.LARGE;
					break;
				default:
					// Level 4-6 just use bold, no size change
					break;
			}
		}
		
		/**
		 * Callback for unordered list blocks.
		 * 
		 * @param is_tight Whether the list is tight
		 * @param mark The list marker character
		 */
		internal override void on_ul(bool is_tight, char mark)
		{
			this.current_state.add_state();
		}
		
		/**
		 * Callback for ordered list blocks.
		 * 
		 * @param start The starting number
		 * @param is_tight Whether the list is tight
		 * @param mark_delimiter The delimiter character
		 */
		internal override void on_ol(uint start, bool is_tight, char mark_delimiter)
		{
			this.current_state.add_state();
		}
		
		/**
		 * Callback for list item blocks.
		 * 
		 * @param is_task Whether this is a task list item
		 * @param task_mark The task marker character
		 * @param task_mark_offset The offset of the task marker
		 */
		internal override void on_li(bool is_task, char task_mark, uint task_mark_offset)
		{
			this.current_state.add_state();
		}
		
		/**
		 * Callback for code blocks.
		 * 
		 * @param lang The language identifier (may be null)
		 * @param fence_char The fence character used
		 */
		internal override void on_code(string? lang, char fence_char)
		{
			this.current_state.add_state();
		}
		
		/**
		 * Callback for paragraph blocks.
		 */
		internal override void on_p()
		{
			this.current_state.add_state();
		}
		
		/**
		 * Callback for blockquote blocks.
		 */
		internal override void on_quote()
		{
			this.current_state.add_state();
		}
		
		/**
		 * Callback for horizontal rule blocks.
		 */
		internal override void on_hr()
		{
			var hr_state = this.current_state.add_state();
			hr_state.style.scale = Pango.Scale.LARGE;
			hr_state.add_text("━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
			hr_state.close_state();
		}
		
		/**
		 * Callback for link spans.
		 * 
		 * @param href The link URL
		 * @param title The link title 
		 * @param is_autolink Whether this is an autolink
		 */
		internal override void on_a(string href, string title, bool is_autolink)
		{
			// Add span state (blue, underlined) for the link
			var link_state = this.current_state.add_state();
			link_state.style.foreground = "blue";
			link_state.style.underline = Pango.Underline.SINGLE;
			
			// Add the href text
			link_state.add_text(href);
			
			// Close the link span
			link_state.close_state();
			this.current_state.add_text(" ");
			var bold_state = this.current_state.add_state();
			bold_state.style.weight = Pango.Weight.BOLD;
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
		internal override void on_img(string src, string? title)
		{
			// Images not fully supported - just add placeholder
			this.current_state.add_text("[IMG:");
		}
		
		/**
		 * Callback for emphasis/italic spans.
		 */
		public override void on_em()
		{
			var em_state = this.current_state.add_state();
			em_state.style.style = Pango.Style.ITALIC;
		}
		
		/**
		 * Callback for strong/bold spans.
		 */
		public override void on_strong()
		{
			var strong_state = this.current_state.add_state();
			strong_state.style.weight = Pango.Weight.BOLD;
		}
		
		/**
		 * Callback for underline spans.
		 */
		internal override void on_u()
		{
			this.current_state.add_state();
		}
		
		/**
		 * Callback for strikethrough spans.
		 */
		public override void on_del()
		{
			this.current_state.add_state();
		}
		
		/**
		 * Callback for inline code spans.
		 */
		public override void on_code_span()
		{
			this.current_state.add_state();
		}
		
		/**
		 * Generic callback for unmapped block/span types.
		 * 
		 * @param tag_name The tag name
		 */
		public override void on_other(string tag_name)
		{
			this.current_state.add_state();
		}
		
		/**
		 * Callback for normal text content.
		 * 
		 * @param text The text content
		 */
		public override void on_text(string text)
		{
			this.current_state.add_text(text);
		}
		
		/**
		 * Callback for line breaks (hard breaks).
		 */
		internal override void on_br()
		{
			this.current_state.add_text("\n");
		}
		
		/**
		 * Callback for soft line breaks.
		 * Inserts a space (or newline in code blocks).
		 */
		internal override void on_softbr()
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
		internal override void on_entity(string text)
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
		internal override void on_html(string tag, string attributes)
		{
			this.current_state.add_state();
		}
		
		/**
		 * Generic callback to close the current state.
		 * Used for closing blocks/spans.
		 */
		internal override void on_end()
		{
			this.current_state.close_state();
		}
	}
}
