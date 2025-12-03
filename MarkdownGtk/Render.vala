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

namespace MarkdownGtk
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
	public class Render : Markdown.RenderBase
	{
		public TopState? top_state { get; private set; default = null; }
		public State? current_state { get; internal set; default = null; }
		
		// Properties for Gtk.Box model
		public Gtk.Box? box { get; private set; default = null; }
		public Gtk.TextView? current_textview { get; private set; default = null; }
		public Gtk.TextBuffer? current_buffer { get; private set; default = null; }
		
		/**
		 * Creates a new Render instance with a Gtk.Box.
		 * 
		 * The Render will create TextViews as needed and add them to the box.
		 * 
		 * @param box The Gtk.Box to add TextViews to
		 */
		public Render(Gtk.Box box)
		{
			base();
			this.box = box;
			
			// Create top_state early (it won't initialize tag/marks until buffer is ready)
			this.top_state = new TopState(this);
			this.current_state = this.top_state;
		}
		
		/**
		 * Starts/initializes the renderer for a new block.
		 * 
		 * Creates the TextView and initializes TopState.
		 * Must be called before add() for each new block.
		 * 
		 * If a TextView already exists, ends the current block first.
		 */
		public void start()
		{
			// If TextView already exists, end the current block first
			if (this.current_textview != null) {
				this.end_block();
			}
			
			// Initialize parser state
			base.start();
			
			// Create new TextView
			this.current_textview = new Gtk.TextView() {
				editable = false,
				cursor_visible = false,
				wrap_mode = Gtk.WrapMode.WORD,
				hexpand = true,
				vexpand = false
			};
			
			// Get the buffer from the TextView
			this.current_buffer = this.current_textview.buffer;
			
			// Add TextView to box at bottom
			this.box.append(this.current_textview);
			
			// Initialize TopState's tag and marks now that buffer is ready
			this.top_state.initialize();
		}
		
		/**
		 * Ends the current block.
		 * 
		 * Clears the current TextView and TopState, preparing for a new block.
		 * Call start() separately when you want to start a new block.
		 */
		public void end_block()
		{
			// Clear current TextView and buffer
			this.current_textview = null;
			this.current_buffer = null;
			
			// Create new TopState (will be initialized when start() is called)
			this.top_state = new TopState(this);
			this.current_state = this.top_state;
		}
		
		/**
		 * Override add() to check that TextView is created (programming error if not).
		 */
		public override void add(string text)
		{
			// Check that TextView is created - this is a programming error if not
			if (this.current_textview == null) {
				GLib.error("Render.add() called before start() - TextView not initialized. Call start() before adding text.");
			}
			
			// Call parent add() to process the text
			base.add(text);
		}
		
		// Callback methods for parser
		
		/**
		 * Callback for header blocks.
		 * 
		 * @param level Header level (1-6)
		 */
		public override void on_h(bool is_start, uint level)
		{
			if (!is_start) {
				this.current_state.close_state();
				return;
			}
			
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
		public override void on_ul(bool is_start, bool is_tight, char mark)
		{
			if (!is_start) {
				this.current_state.close_state();
				return;
			}
			
			this.current_state.add_state();
		}
		
		/**
		 * Callback for ordered list blocks.
		 * 
		 * @param start The starting number
		 * @param is_tight Whether the list is tight
		 * @param mark_delimiter The delimiter character
		 */
		public override void on_ol(bool is_start, uint start, bool is_tight, char mark_delimiter)
		{
			if (!is_start) {
				this.current_state.close_state();
				return;
			}
			
			this.current_state.add_state();
		}
		
		/**
		 * Callback for list item blocks.
		 * 
		 * @param is_task Whether this is a task list item
		 * @param task_mark The task marker character
		 * @param task_mark_offset The offset of the task marker
		 */
		public override void on_li(bool is_start, bool is_task, char task_mark, uint task_mark_offset)
		{
			if (!is_start) {
				this.current_state.close_state();
				return;
			}
			
			this.current_state.add_state();
		}
		
		/**
		 * Callback for code blocks.
		 * 
		 * @param lang The language identifier (may be null)
		 * @param fence_char The fence character used
		 */
		public override void on_code(bool is_start, string? lang, char fence_char)
		{
			if (!is_start) {
				this.current_state.close_state();
				return;
			}
			
			this.current_state.add_state();
		}
		
		/**
		 * Callback for paragraph blocks.
		 */
		public override void on_p(bool is_start)
		{
			if (!is_start) {
				this.current_state.close_state();
				return;
			}
			
			this.current_state.add_state();
		}
		
		/**
		 * Callback for blockquote blocks.
		 */
		public override void on_quote(bool is_start)
		{
			if (!is_start) {
				this.current_state.close_state();
				return;
			}
			
			this.current_state.add_state();
		}
		
		/**
		 * Callback for horizontal rule blocks.
		 */
		public override void on_hr()
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
		public override void on_a(bool is_start, string href, string title, bool is_autolink)
		{
			if (!is_start) {
				this.current_state.close_state();
				return;
			}
			
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
		public override void on_img(string src, string? title)
		{
			// Images not fully supported - just add placeholder
			this.current_state.add_text("[IMG:");
		}
		
		/**
		 * Callback for emphasis/italic spans.
		 */
		public override void on_em(bool is_start)
		{
			if (!is_start) {
				this.current_state.close_state();
				return;
			}
			
			var em_state = this.current_state.add_state();
			em_state.style.style = Pango.Style.ITALIC;
		}
		
		/**
		 * Callback for strong/bold spans.
		 */
		public override void on_strong(bool is_start)
		{
			if (!is_start) {
				this.current_state.close_state();
				return;
			}
			
			var strong_state = this.current_state.add_state();
			strong_state.style.weight = Pango.Weight.BOLD;
		}
		
		/**
		 * Callback for underline spans.
		 */
		public override void on_u(bool is_start)
		{
			if (!is_start) {
				this.current_state.close_state();
				return;
			}
			
			this.current_state.add_state();
		}
		
		/**
		 * Callback for strikethrough spans.
		 */
		public override void on_del(bool is_start)
		{
			if (!is_start) {
				this.current_state.close_state();
				return;
			}
			
			this.current_state.add_state();
		}
		
		/**
		 * Callback for inline code spans.
		 */
		public override void on_code_span(bool is_start)
		{
			if (!is_start) {
				this.current_state.close_state();
				return;
			}
			
			this.current_state.add_state();
		}
		
		/**
		 * Generic callback for unmapped block/span types.
		 * 
		 * @param tag_name The tag name
		 */
		public override void on_other(bool is_start, string tag_name)
		{
			if (!is_start) {
				this.current_state.close_state();
				return;
			}
			
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
		public override void on_br()
		{
			this.current_state.add_text("\n");
		}
		
		/**
		 * Callback for soft line breaks.
		 * Inserts a space (or newline in code blocks).
		 */
		public override void on_softbr()
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
		public override void on_entity(string text)
		{
			this.current_state.add_text(text);
		}
		
		/**
		 * Callback for HTML tags.
		 * Parser sends the tag name and attributes, we create a new state,
		 * and parser will call on_html(false, ...) for the close tag.
		 * 
		 * @param tag The HTML tag name (e.g., "div", "span")
		 * @param attributes The HTML tag attributes (e.g., "class='test'")
		 */
		public override void on_html(bool is_start, string tag, string attributes)
		{
			if (!is_start) {
				this.current_state.close_state();
				return;
			}
			this.current_state.add_state();
			
		}
	}
}
