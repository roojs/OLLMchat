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
		
		// Configuration
		public bool scroll_to_end { get; set; default = true; }
		
		// Default state to restore when new textviews are created (e.g., after code blocks)
		public State? default_state { get; set; default = null; }
		
		// Code block handlers (kept in array to prevent going out of scope)
		private Gee.ArrayList<RenderSourceView> source_view_handlers = new Gee.ArrayList<RenderSourceView>();
		private RenderSourceView? current_source_view_handler = null;
		
		// List stack: stores list numbers at each indentation level
		// 0 = unordered list, >0 = ordered list (number is the counter)
		private Gee.ArrayList<int> list_stack = new Gee.ArrayList<int>();
		
		// Track the current indentation level for the next on_li call
		private uint current_list_indentation = 0;
		
		// Signal emitted when code block ends (delegates to source_view_handler)
		public signal void code_block_ended(string content, string language);
		
		// Signal emitted when code block content is updated (for scrolling)
		public signal void code_block_content_updated();
		
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
			
			// Don't create top_state here - wait until start() when buffer is ready
			// top_state will be null until start() is called
		}
		
		/**
		 * Creates a new TextView and initializes TopState.
		 * 
		 * This is a helper method used by start() and when code blocks end.
		 * It does NOT reset the parser state (unlike start() which calls base.start()).
		 */
		private void create_textview()
		{
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
			
			// Clear list stack
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
		 * Closes lists that are deeper than the specified indentation level.
		 * 
		 * @param level The indentation level - only closes lists deeper than this
		 */
		private void close_lists_to_level(uint level)
		{
			int min_index = (int)level - 1; // Convert to 0-based index
			GLib.debug("Render.close_lists_to_level: level=%u, min_index=%d, stack.size=%d", level, min_index, this.list_stack.size);
			// Only close lists that are deeper (stack size > min_index + 1)
			while (this.list_stack.size > min_index + 1) {
				var removed = this.list_stack.remove_at(this.list_stack.size - 1);
				GLib.debug("Render.close_lists_to_level: removed stack entry, new size=%d", this.list_stack.size);
			}
			GLib.debug("Render.close_lists_to_level: after closing, stack.size=%d", this.list_stack.size);
		}
		
		/**
		 * Callback for unordered list blocks.
		 * 
		 * @param indentation The indentation level
		 */
		public override void on_ul(bool is_start, uint indentation)
		{
			GLib.debug("Render.on_ul: is_start=%s, indentation=%u, list_stack.size=%d", is_start ? "true" : "false", indentation, this.list_stack.size);
			if (!is_start) {
				this.current_state.close_state();
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
			
			// Track the current indentation for the next on_li call
			this.current_list_indentation = indentation;
			
			GLib.debug("Render.on_ul: after setup, list_stack.size=%d, current_list_indentation=%u, stack[%d]=%d", 
				this.list_stack.size, this.current_list_indentation, target_index, this.list_stack.get(target_index));
			
			// Always open a list item when we see a list marker (like HTML renderer does)
			this.on_li(true);
			
			this.current_state.add_state();
		}
		
		/**
		 * Callback for ordered list blocks.
		 * 
		 * @param indentation The indentation level
		 */
		public override void on_ol(bool is_start, uint indentation)
		{
			GLib.debug("Render.on_ol: is_start=%s, indentation=%u, list_stack.size=%d", is_start ? "true" : "false", indentation, this.list_stack.size);
			if (!is_start) {
				this.current_state.close_state();
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
			// But only if it's already > 0 (continuing a list) or if we're starting fresh
			// Actually, we should always increment - if it's 0, it becomes 1, if it's > 0, it increments
			int old_value = this.list_stack.get(target_index);
			GLib.debug("Render.on_ol: before increment, stack[%d]=%d", target_index, old_value);
			// Only increment if this level was already an ordered list (> 0)
			// If it was 0 (unordered or new), start at 1
			if (old_value > 0) {
				this.list_stack.set(target_index, old_value + 1);
			} else {
				this.list_stack.set(target_index, 1);
			}
			
			// Reset all levels above this one
			this.reset_lists_above_level(indentation);
			
			// Track the current indentation for the next on_li call
			this.current_list_indentation = indentation;
			
			GLib.debug("Render.on_ol: after setup, list_stack.size=%d, current_list_indentation=%u, stack[%d]=%d (was %d)", 
				this.list_stack.size, this.current_list_indentation, target_index, this.list_stack.get(target_index), old_value);
			
			// Always open a list item when we see a list marker (like HTML renderer does)
			this.on_li(true);
			
			this.current_state.add_state();
		}
		
		/**
		 * Callback for list item blocks.
		 * 
		 * @param is_task Whether this is a task list item
		 * @param task_mark The task marker character
		 * @param task_mark_offset The offset of the task marker
		 */
		/**
		 * Handles list item start/end.
		 * 
		 * @param is_start Whether this is the start of a list item
		 */
		public override void on_li(bool is_start)
		{
			 
			if (!is_start) {
				this.current_state.close_state();
				return;
			}
			
			// Use the tracked indentation level from the last on_ul/on_ol call
			uint current_level = this.current_list_indentation;
			if (current_level == 0) {
				// No list context - just add state
				GLib.debug("Render.on_li: no list context (current_level=0), just adding state");
				this.current_state.add_state();
				return;
			}
			
			// Convert indentation (1-based) to array index (0-based)
			int target_index = (int)current_level - 1;
			
			// Ensure the stack has this level
			if (target_index >= this.list_stack.size) {
				// Stack not set up - just add state without marker
				GLib.debug("Render.on_li: stack not set up (target_index=%d >= stack.size=%d), adding state without marker", 
					target_index, this.list_stack.size);
				this.current_state.add_state();
				return;
			}
			
			// Get the list type and number for the current level
			int list_number = this.list_stack.get(target_index);
			
			GLib.debug("Render.on_li: current_level=%u, target_index=%d, list_number=%d", 
				current_level, target_index, list_number);
			
			// Add tabs for indentation
			// Level 1 gets 1 tab, level 2 gets 2 tabs, etc.
			uint indent_tabs = current_level;
			GLib.debug("Render.on_li: adding %u tabs for indentation (level %u)", indent_tabs, current_level);
			for (uint i = 0; i < indent_tabs; i++) {
				this.current_state.add_text("\t");
			}
			
			// Add marker based on list type
			if (list_number == 0) {
				// Unordered list - use bullet point (circle)
				GLib.debug("Render.on_li: adding unordered list bullet '•'");
				this.current_state.add_text("●");
			} else {
				// Ordered list - use number + "." with bold formatting
				string number_marker = list_number.to_string() + ".";
				GLib.debug("Render.on_li: adding ordered list marker '%s'", number_marker);
				// Create a new state with bold formatting for the number marker
				var bold_state = this.current_state.add_state();
				bold_state.style.weight = Pango.Weight.BOLD;
				bold_state.add_text(number_marker);
				bold_state.close_state();
			}
			
			// Add tab after marker before content
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
		public override void on_quote(bool is_start, uint level)
		{
			if (!is_start) {
				// End of blockquote line - add newline
			//  //	this.current_state.add_text("\n");
				return;
			}
			
			// For each level, create a state with light orange background
			// Add 2 spaces to that state, close it, then add 2 spaces to current state
			for (uint i = 0; i < level; i++) {
				// Create a new state
				var bg_state = this.current_state.add_state();
				bg_state.style.background = "#FFE5CC";
				bg_state.add_text("   ");
				bg_state.close_state();
				this.current_state.add_text("  ");
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
