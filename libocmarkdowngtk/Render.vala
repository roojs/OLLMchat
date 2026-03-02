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
		public TopState? top_state { get; internal set; default = null; }
		public State? current_state { get; internal set; default = null; }
		
		// Properties for Gtk.Box model
		public Gtk.Box? box { get; private set; default = null; }
		public Gtk.TextView? current_textview { get; internal set; default = null; }
		public Gtk.TextBuffer? current_buffer { get; internal set; default = null; }
		
		// Configuration
		public bool scroll_to_end { get; set; default = true; }
		
		// Default state to restore when new textviews are created (e.g., after code blocks)
		public State? default_state { get; set; default = null; }
		
		// Code block handlers (kept in array to prevent going out of scope)
		private Gee.ArrayList<RenderSourceView> source_view_handlers = new Gee.ArrayList<RenderSourceView>();
		private RenderSourceView? current_source_view_handler = null;
		
		// Indent levels: actual space_skip values we've seen (on_ul/on_ol), in ascending order
		private Gee.ArrayList<int> indent_levels = new Gee.ArrayList<int>();
		// List stack: same length as indent_levels; 0 = unordered, >0 = ordered (counter)
		private Gee.ArrayList<int> list_stack = new Gee.ArrayList<int>();
		
		// Track the current indentation level for the next on_li call
		private uint current_list_indentation = 0;
		
		// Table: current table when inside on_table(true)..on_table(false)
		internal Table? current_table { get; private set; default = null; }
		private Gtk.TextView? last_link_view = null;
		private string last_tooltip_markup = "";
		/** Emitted when the user activates a link. Connect to open URL or handle app-specific navigation. */
		public signal void link_clicked(string href, string title);
		// Signal emitted when code block ends (delegates to source_view_handler)
		public signal void code_block_ended(string content, string language);
		
		// Signal emitted when code block content is updated (for scrolling)
		public signal void code_block_content_updated();
		
		/**
		 * Creates a renderer that appends content to the given box.
		 *
		 * @param box Gtk.Box to add TextViews to
		 */
		public Render(Gtk.Box box)
		{
			base();
			this.box = box;
			var click_gesture = new Gtk.GestureClick();
			click_gesture.released.connect((n_press, x, y) => {
				this.on_link_click_released(x, y);
			});
			this.box.add_controller(click_gesture);
			var motion = new Gtk.EventControllerMotion();
			motion.motion.connect((x, y) => {
				this.on_link_motion(x, y);
			});
			motion.leave.connect(() => {
				this.on_link_leave();
			});
			this.box.add_controller(motion);
		}

		private void on_link_click_released(double x, double y)
		{
			Gtk.TextView? view;
			var tag = this.tag_at_iter(x, y, out view);
			if (tag == null) {
				return;
			}
			var href = tag.get_data<string>("href") ?? "";
			var title = tag.get_data<string>("title") ?? "";
			this.link_clicked(href, title);
		}

		private void on_link_motion(double x, double y)
		{
			Gtk.TextView? view;
			var tag = this.tag_at_iter(x, y, out view);
			if (view == null) {
				if (this.last_link_view != null) {
					this.last_link_view.tooltip_markup = null;
					this.last_link_view.set_cursor(null);
					this.last_link_view = null;
					this.last_tooltip_markup = "";
				}
				return;
			}
			if (tag != null) {
				this.last_link_view = view;
				var href = tag.get_data<string>("href") ?? "";
				var title = tag.get_data<string>("title") ?? "";
				var markup =
					(title != "" ? "<b>" + GLib.Markup.escape_text(title, -1) + "</b>\n" : "") +
					GLib.Markup.escape_text(href, -1);
				if (markup == this.last_tooltip_markup) {
					return;
				}
				this.last_link_view.tooltip_markup = markup;
				this.last_tooltip_markup = markup;
				var cursor = new Gdk.Cursor.from_name("pointer", null);
				if (cursor != null) {
					this.last_link_view.set_cursor(cursor);
				}
				return;
			}
			if (this.last_link_view != null) {
				this.last_link_view.tooltip_markup = null;
				this.last_link_view.set_cursor(null);
				this.last_link_view = null;
				this.last_tooltip_markup = "";
			}
		}

		private void on_link_leave()
		{
			if (this.last_link_view != null) {
				this.last_link_view.tooltip_markup = null;
				this.last_link_view.set_cursor(null);
				this.last_link_view = null;
				this.last_tooltip_markup = "";
			}
		}

		/** Returns the link tag at (x, y) in box coordinates, or null. Sets out_view to the TextView at (x, y) when over one. */
		private Gtk.TextTag? tag_at_iter(double x, double y, out Gtk.TextView? out_view)
		{
			out_view = null;
			var tv = this.box.pick((float) x, (float) y, Gtk.PickFlags.DEFAULT) as Gtk.TextView;
			if (tv == null) {
				return null;
			}
			out_view = tv;
			Graphene.Point pt = { (float) x, (float) y };
			Graphene.Point out_pt;
			this.box.compute_point(tv, pt, out out_pt);
			int buf_x = (int) out_pt.x;
			int buf_y = (int) out_pt.y;
			Gtk.TextIter iter;
			if (!tv.get_iter_at_location(out iter, buf_x, buf_y)) {
				return null;
			}
			var buf = tv.get_buffer();
			var link_tag = buf.get_tag_table().lookup("link");
			if (link_tag == null || !iter.has_tag(link_tag)) {
				return null;
			}
			var tags = iter.get_tags();
			if (tags == null || tags.length() < 1) {
				return null;
			}
			for (int i = (int) tags.length() - 1; i >= 0; i--) {
				var href = tags.nth_data(i).get_data<string>("href");
				if (href != null) {
					return tags.nth_data(i);
				}
			}
			return null;
		}
		
		/**
		 * Creates a new TextView and initializes TopState.
		 * 
		 * This is a helper method used by start() and when code blocks end.
		 * It does NOT reset the parser state (unlike start() which calls base.start()).
		 */
		private void create_textview()
		{
			// Create new TextView (tight margins so no extra padding below text)
			this.current_textview = new Gtk.TextView() {
				editable = false,
				cursor_visible = false,
				wrap_mode = Gtk.WrapMode.WORD,
				hexpand = true,
				vexpand = false,
				top_margin = 0,
				bottom_margin = 0,
				margin_top = 0,
				margin_bottom = 0
			};
			this.current_textview.add_css_class("oc-markdown-text");

			// Get the buffer from the TextView
			this.current_buffer = this.current_textview.buffer;
			
			// Add TextView to box at bottom
			this.box.append(this.current_textview);
			
			// Create TopState now that buffer is ready (will initialize tag/marks)
			this.top_state = new TopState(this);
			this.current_state = this.top_state;
			
			// Initialize TopState's tag and marks now that buffer is ready
			this.top_state.initialize();
			
			// If default_state is set, apply its style to the new top_state
			if (this.default_state != null && this.top_state != null) {
				// Create a new state under top_state and copy the default style
				var new_state = this.top_state.add_state();
				this.default_state.copy_style_to(new_state);
			}
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
			// End the current block first (safe to call even if already null)
			this.end_block();
			
			// Clear list stack and indent levels (keep in sync)
			this.indent_levels.clear();
			this.list_stack.clear();
			this.current_list_indentation = 0;
			
			// Initialize parser state
			base.start();
			
			// Create new TextView and TopState
			this.create_textview();
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
			
			// Clear TopState - will be recreated in start() when buffer is ready
			this.top_state = null;
			this.current_state = null;
		}
		
		/**
		 * Clears all state, including sourceviews.
		 * 
		 * Resets the renderer to a clean state, clearing all sourceview handlers.
		 */
		public void clear()
		{
			// Clear current sourceview handler
			this.current_source_view_handler = null;
			
			// Clear all sourceview handlers
			this.source_view_handlers.clear();
			
			// Clear current block state
			this.end_block();
		}
		
		/**
		 * Override add() to check that TextView is created (programming error if not).
		 * 
		 * Note: current_textview may be null when a code block is active,
		 * which is valid - code block text goes to the sourceview instead.
		 */
		public override void add(string text)
		{
			// Check that TextView is created OR a code block is active
			// (code blocks use sourceview instead of textview)
			if (this.current_textview == null && this.current_source_view_handler == null) {
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
		 * Resets all list numbers above the specified level to 0.
		 * 
		 * Actually, we don't want to reset parent list counters when nesting,
		 * as that would break continuation when returning to parent level.
		 * This method is kept for potential future use but currently does nothing.
		 * 
		 * @param level The indentation level (1-based) - resets levels above this
		 */
		private void reset_lists_above_level(uint level)
		{
			// Don't reset parent levels - we want to preserve their counters
			// so that when we return to a parent level, numbering continues correctly
			// (e.g., 1, 2, nested items, 3 should continue from 2, not reset to 1)
		}
		
		/**
		 * Closes lists deeper than the given indent (removes levels with indent > level).
		 *
		 * @param level space_skip (raw spaces) – keep only levels with indent <= level
		 */
		private void close_lists_to_level(uint level)
		{
			int l = (int)level;
			while (this.indent_levels.size > 0 && this.indent_levels.get(this.indent_levels.size - 1) > l) {
				this.indent_levels.remove_at(this.indent_levels.size - 1);
				this.list_stack.remove_at(this.list_stack.size - 1);
			}
		}
		
		/**
		 * Finds or inserts an indent level and returns its depth index (0-based).
		 */
		private int ensure_indent_level(int indentation)
		{
			int i = 0;
			while (i < this.indent_levels.size && this.indent_levels.get(i) < indentation) {
				i++;
			}
			if (i < this.indent_levels.size && this.indent_levels.get(i) == indentation) {
				return i;
			}
			this.indent_levels.insert(i, indentation);
			this.list_stack.insert(i, 0);
			return i;
		}
		
		public override void on_list(bool is_start)
		{
			if (!is_start) {
				this.current_state.close_state();
				this.current_state.add_text("\n");
			}
		}

		public override void on_li(bool is_start, int list_number = 0, uint space_skip = 0, int task_checked = -1)
		{
			if (!is_start) {
				this.current_state.close_state();
				this.current_state.add_text("\n");
				return;
			}

			this.close_lists_to_level(space_skip);
			int depth_index = this.ensure_indent_level((int)space_skip);
			this.list_stack.set(depth_index, list_number == 0 ? 0 : list_number);
			this.current_list_indentation = space_skip;

			this.current_state.add_text(string.nfill(depth_index + 1, '\t'));
			if (list_number == 0) {
				this.current_state.add_text("●");
			} else {
				string number_marker = list_number.to_string() + ".";
				var bold_state = this.current_state.add_state();
				bold_state.style.weight = Pango.Weight.BOLD;
				bold_state.add_text(number_marker);
				bold_state.close_state();
			}
			this.current_state.add_text("\t");
			this.current_state.add_state();
		}
		
		public override void on_task_list(bool is_start, bool is_checked)
		{
			if (!is_start) {
				return;
			}
			
			// Create a new state for the task marker with formatting
			var task_state = this.current_state.add_state();
			task_state.style.weight = Pango.Weight.BOLD;
			task_state.style.family = "monospace";
			
			// Task list item - add checkbox marker
			// Use ✅ (U+2705) for checked, [_] for unchecked
		 
			this.current_state.add_text(is_checked ? "✅" : "⬜");
			
			// Close the formatting state
			this.current_state.close_state();
		}
		
		/**
		 * Callback for code blocks.
		 * 
		 * @param lang The language identifier (may be null)
		 * @param fence_char The fence character used
		 */
		public override void on_code(bool is_start, string lang, char fence_char)
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
		public override void on_quote(bool is_start, uint level)
		{
			if (!is_start) {
				// End of blockquote line - add newline
			//  //	this.current_state.add_text("\n");
				return;
			}
			
			// For each level, create a state with light orange background
			// Add 3 spaces to that state, close it, then add 2 spaces to current state
			for (uint i = 0; i < level; i++) {
				var bg_state = this.current_state.add_state();
				bg_state.style.background = "#FFE5CC";
				bg_state.add_text(string.nfill(3, ' '));
				bg_state.close_state();
				this.current_state.add_text(string.nfill(2, ' '));
			}
		}
			
		/**
		* Callback for horizontal rule blocks.
		*/
		public override void on_hr()
		{
			// End the current block to finalize any pending text
			this.end_block();
			
			// Create a proper separator widget instead of text
			var separator = new Gtk.Separator(Gtk.Orientation.HORIZONTAL) {
				margin_top = 6,
				margin_bottom = 6,
				hexpand = true
			};
			
			// Add separator to the box
			this.box.append(separator);
			
			// Create a new textview for future text (similar to code block handling)
			// Don't call start() as that would reset the parser state
			this.create_textview();
		}
		
		public override void on_table(bool is_start)
		{
			if (is_start) {
				this.current_table = new Table(this);
				return;
			}
			this.clear();
			this.current_table = null;
			// Create new textview for content after the table (like on_hr / code block)
			this.create_textview();
		}

		public override void on_table_row(bool is_start)
		{
			if (this.current_table == null) {
				return;
			}
			this.current_table.on_row(is_start);
		}

		public override void on_table_hcell(bool is_start, int align)
		{
			if (this.current_table == null) {
				return;
			}
			this.current_table.on_hcell(is_start, align);
		}

		public override void on_table_cell(bool is_start, int align)
		{
			if (this.current_table == null) {
				return;
			}
			this.current_table.on_cell(is_start, align);
		}
		
		/**
		 * Callback for link spans. Renders link text with shared style and stores href/title on a per-link tag.
		 *
		 * @param is_start True for open, false for close
		 * @param href URL or reference label
		 * @param title Link title (may be empty)
		 * @param is_reference True if href is a reference label
		 */
		public override void on_a(bool is_start, string href, string title, bool is_reference)
		{
			if (!is_start) {
				this.current_state.close_state();
				this.current_state.close_state();
				return;
			}
			var link_tag = this.current_buffer.get_tag_table().lookup("link");
			if (link_tag == null) {
				link_tag = this.current_buffer.create_tag("link", null);
				link_tag.foreground = "blue";
				link_tag.underline = Pango.Underline.SINGLE;
			}
			this.current_state.add_state(link_tag);
			var inner = this.current_state.add_state();
			inner.style.set_data<string>("href", href);
			inner.style.set_data<string>("title", title);
		}
		
		/**
		 * Callback for image spans.
		 * 
		 * @param src The image source URL
		 * @param title The image title (may be null)
		 */
		public override void on_img(string src, string title)
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
			
			var del_state = this.current_state.add_state();
			del_state.style.strikethrough = true;
			del_state.style.strikethrough_set = true;
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
			
			var code_state = this.current_state.add_state();
			code_state.style.family = "monospace";
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
		
		// Code block callbacks
		public override void on_code_block(bool is_start, string lang)
		{
			if (!is_start) {
				// Code block ended - delegate to current_source_view_handler
				if (this.current_source_view_handler != null) {
					this.current_source_view_handler.end_code_block();
					// Keep handler in array so it doesn't go out of scope
					// (buttons and other handlers need to remain functional)
					this.current_source_view_handler = null;
				}
				
				// Textview and states were already created when code block started,
				// so they're ready for text that comes after the code block
				return;
			}
			
			// Code block started - clear old textview/buffer/states
			// During the code block, all text goes to sourceview, not textview
			this.current_textview = null;
			this.current_buffer = null;
			this.top_state = null;
			this.current_state = null;
			
			// Create new source_view_handler for the code block FIRST
			// (so it appears before the textview that will be created after)
			this.current_source_view_handler = new RenderSourceView(this, lang);
			
			// Keep handler in array so it doesn't go out of scope
			this.source_view_handlers.add(this.current_source_view_handler);
			
			// Create new textview and states immediately (ready for text after code block)
			// This will be added to the box AFTER the sourceview, which is correct
			this.create_textview();
		}
		
		public override void on_code_text(string text)
		{
			// Delegate to current_source_view_handler
			if (this.current_source_view_handler != null) {
				this.current_source_view_handler.add_code_text(text);
			}
		}
	}
}
