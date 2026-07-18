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

namespace OLLMchatGtk
{
	/**
	 * Chat view widget for displaying chat messages with markdown rendering.
	 * 
	 * This widget displays chat messages with efficient incremental updates.
	 * It uses chunk-based rendering to only re-render the current chunk being
	 * updated, improving performance during streaming.
	 * 
	 * @since 1.0
	 */
	public class ChatView : Gtk.Box
	{
		public enum ContentState
		{
			NONE,
			THINKING,
			CONTENT
		}
		
		private enum ResizeMode
		{
			INITIAL,    // Initial sizing: min(natural, max_height), hide button if fits
			EXPAND,     // Expand: natural height, vexpand = true
			COLLAPSE,   // Collapse: min(natural, max_height), vexpand = false
			FINAL       // Final sizing: min(natural, max_height), hide button if fits
		}

		private ChatWidget chat_widget;
		private Gtk.ScrolledWindow scrolled_window;
		private Gtk.Box text_view_box;
		private MarkdownGtk.Render renderer;
		private string last_line = "";
		private int last_chunk_start = 0;
		private bool is_assistant_message = false;
		private bool is_thinking = false;
		private ContentState content_state = ContentState.NONE;
		private bool is_waiting = false;
		/** Separate row below the markdown stack — avoids Gtk.TextMark on the render buffer (see clear()). */
		private Gtk.Widget? waiting_panel = null;
		private Gtk.Label? waiting_line_label = null;
		private uint waiting_timer = 0;
		private int waiting_dots = 0;
		private string waiting_caption = "waiting for a reply";
		private Gee.ArrayList<Gtk.Widget> widgets = new Gee.ArrayList<Gtk.Widget>();
		public MarkdownGtk.RenderBox render_box { get; private set; }
		private bool has_displayed_user_message = false;
		private double last_scroll_pos = 0.0;
		public bool scroll_enabled = true;
		/** When true, user has scrolled up so we temporarily disable autoscroll until they scroll back to bottom. */
		private bool autoscroll_paused_by_user = false;
		private bool programmatic_scroll_in_progress = false;
		/** Current thinking child frame (when streaming thinking into a framed box). */
		private MarkdownGtk.RenderSourceView? thinking_frame = null;

		/**
		 * Creates a new ChatView instance.
		 * 
		 * @param chat_widget The parent ChatWidget to access current chat state
		 * @since 1.0
		 */
		public ChatView(ChatWidget chat_widget)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			this.chat_widget = chat_widget;

			// Load CSS from resource files
			string[] css_files = { "pulldown.css", "style.css", "frame.css" };
			foreach (var css_file in css_files) {
				var css_provider = new Gtk.CssProvider();
				css_provider.load_from_resource("/ollmchat/" + css_file);
				Gtk.StyleContext.add_provider_for_display(
					Gdk.Display.get_default(),
					css_provider,
					Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
				);
			}
	
			// Create a box for assistant message content
			this.text_view_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = true,
				margin_start = 2,
				margin_end = 0
			};

			this.render_box = new MarkdownGtk.RenderBox();
			this.text_view_box.append(this.render_box);
			// Create single Render instance for assistant messages (uses render_box)
			this.renderer = new MarkdownGtk.Render(this.render_box) {
				scroll_to_end = this.scroll_enabled
			};

			this.renderer.link_clicked.connect((href, title) => {
				if (!href.has_prefix("http://") && !href.has_prefix("https://")) {
					return;
				}
				var win = this.get_root() as Gtk.Window;
				if (win == null) {
					return;
				}
				try {
					Gtk.show_uri(win, href, 0);
				} catch (GLib.Error e) {
					GLib.warning("Failed to open link %s: %s", href, e.message);
				}
			});
			
			// Connect to code block content updates to scroll when sourceviews receive content
			this.renderer.code_block_content_updated.connect(() => {
				/* GLib.debug("scroll_to_bottom_caller reason=code_block_content_updated"); */
				this.scroll_to_bottom();
			});
			this.renderer.start_new_chat_requested.connect((text) => {
				this.chat_widget.start_new_chat_with_text.begin(text);
			});

			this.scrolled_window = new Gtk.ScrolledWindow() {
				hexpand = true,
				vexpand = true
			};
			this.scrolled_window.set_child(text_view_box);
			this.append(this.scrolled_window);
			this.scrolled_window.add_css_class("chat-view-text");

			// Wheel scroll up over the chat area → pause autoscroll immediately (no threshold)
			var wheel_controller = new Gtk.EventControllerScroll(
				Gtk.EventControllerScrollFlags.VERTICAL |
				Gtk.EventControllerScrollFlags.DISCRETE |
				Gtk.EventControllerScrollFlags.KINETIC
			);
			wheel_controller.scroll.connect((dx, dy) => {
				// dy < 0 = content goes up = user wheeled up
				if (dy < 0) {
					this.autoscroll_paused_by_user = true;
				}
				return false;  // let scroll happen normally
			});
			this.scrolled_window.add_controller(wheel_controller);

			// Detect scroll position: when user scrolls back to bottom, resume autoscroll
			this.scrolled_window.vadjustment.value_changed.connect(() => {
				var vadj = this.scrolled_window.vadjustment;
				if (this.programmatic_scroll_in_progress) {
					/* GLib.debug(
						"vadj_trace prog value=%.2f upper=%.2f page=%.2f",
						vadj.value,
						vadj.upper,
						vadj.page_size); */
					this.programmatic_scroll_in_progress = false;
					return;
				}
				/* GLib.debug(
					"vadj_trace ambient value=%.2f upper=%.2f page=%.2f",
					vadj.value,
					vadj.upper,
					vadj.page_size); */
				// within a few px of bottom = "at bottom" → resume autoscroll; else pause (small scroll up = pause)
				this.autoscroll_paused_by_user = (vadj.value < vadj.upper - vadj.page_size - 3.0);
			});
		}

		/**
		 * Appends a streaming chunk from the assistant.
		 * 
		 * This method efficiently updates only the current chunk being streamed,
		 * re-rendering markdown from the last double line break to the end.
		 * 
		 * @param new_text The new text chunk to append
		 * @param message The ChatContentInterface object (ChatResponse for assistant messages)
		 * @since 1.0
		 */
		public int append_assistant_chunk(string new_text, OLLMchat.Response.Chat response)
		{

			if (!this.is_assistant_message) {
				this.initialize_assistant_message(response);
			}

			if (this.is_waiting) {
				this.clear_waiting_indicator(response);
			}

			// Process the incoming new_text chunk directly
			if (new_text.length > 0) {
				this.process_new_chunk(new_text, response);
			}

			// Final packet is often metrics-only (new_text empty, done=true). We still need to leave
			// thinking mode when the model emitted only thinking and no content chunk followed.
			if (response.done && this.is_assistant_message && this.content_state == ContentState.THINKING) {
				this.process_new_chunk_direct("", false);
			}

			if (response.done) {
				GLib.debug(
					"append assistant done content_state=%u content_len=%u resp_is_thinking=%s",
					(uint) this.content_state,
					response.message.content.length,
					response.is_thinking.to_string()
				);
			}

			/* GLib.debug("scroll_to_bottom_caller reason=append_assistant_chunk"); */
			this.scroll_to_bottom();
			return this.render_box.last_id;
		}

		/**
		* Initializes a new assistant message.
		*/
		/**
		 * Gets the current buffer from renderer, ensuring TextView is created.
		 */
		private Gtk.TextBuffer? get_current_buffer()
		{
			// Initialize renderer if needed (for operations like waiting indicator, tool messages, etc.)
			this.renderer.start();
			return this.renderer.current_buffer;
		}

		private void initialize_assistant_message(OLLMchat.Response.Chat response)
		{
			this.render_box.mark();
			this.is_assistant_message = true;
			this.last_chunk_start = 0;
			this.is_thinking = response.is_thinking;
			this.content_state = ContentState.NONE;
			// Initialize the renderer for the new assistant message
			this.renderer.start();
			this.renderer.is_streaming = response.message.is_stream || !response.done;
		}

		/**
		* Processes new chunk from message.content using state machine.
		* Splits content into complete lines vs incomplete line and processes accordingly.
		* Refactored to use direct methods internally.
		*/
		private void process_new_chunk(string new_text, OLLMchat.Response.Chat response)
		{
			// Extract is_thinking from response and delegate to direct method
			this.process_new_chunk_direct(new_text, response.is_thinking);
		}
		
		/**
		* Appends text to current markdown content based on current state.
		* Refactored to use direct methods internally.
		*/
		private void process_add_text(string text, OLLMchat.Response.Chat response)
		{
			// Extract is_thinking from response and delegate to direct method
			this.process_add_text_direct(text, response.is_thinking);
		}
		
		/**
		* Processes a newline, delegating to state-specific handlers.
		* Refactored to use direct methods internally.
		*/
		private void process_new_line(OLLMchat.Response.Chat response)
		{
			// Extract is_thinking from response and delegate to direct method
			this.process_new_line_direct(response.is_thinking);
		}
		
		
		/**
		* Handles newline when in THINKING state.
		* Refactored to use direct methods internally.
		*/
		private void process_new_line_thinking(OLLMchat.Response.Chat response)
		{
			// Extract is_thinking from response and delegate to direct method
			this.process_new_line_thinking_direct(response.is_thinking);
		}
		
		/**
		* Handles newline when in CONTENT state.
		* Refactored to use direct methods internally.
		*/
		private void process_new_line_content(OLLMchat.Response.Chat response)
		{
			// Delegate to direct method (doesn't need is_thinking parameter)
			this.process_new_line_content_direct();
		}
		/**
		* Starts a new block based on current state.
		* Refactored to use direct methods internally.
		*/
		private void start_block(OLLMchat.Response.Chat response)
		{
			// Extract is_thinking from response and delegate to direct method
			this.start_block_direct(response.is_thinking);
		}
		
		/**
		* Ends the current block based on state.
		* Refactored to use direct methods internally.
		*/
		private void end_block(OLLMchat.Response.Chat response)
		{
			// Extract is_thinking from response and delegate to direct method
			// Use current is_thinking state for formatting (not response.is_thinking)
			this.end_block_direct(this.is_thinking);
		}
		
		/**
		* Direct version of process_new_chunk that doesn't require Response.Chat.
		* Processes new chunk from message content using state machine.
		* Splits content into complete lines vs incomplete line and processes accordingly.
		* 
		* @param new_text The new text chunk to process
		* @param is_thinking Whether this chunk is thinking content
		*/
		private void process_new_chunk_direct(string new_text, bool is_thinking)
		{
			// Check if state changed (thinking vs content)
			// If state changed, end the current block
			if (this.is_thinking != is_thinking) {
				// End the current block if we're in one (end_block_direct uses current is_thinking for formatting)
				if (this.content_state != ContentState.NONE) {
					this.end_block_direct(this.is_thinking);
					// Add extra line breaks to visually separate the old block from the new one
					// With box model, Render will create new TextView on next add()
				}
				// Update thinking state AFTER ending block (so block is formatted with old status)
				this.is_thinking = is_thinking;
				// New text will start a new block when process_add_text_direct is called
			}
					
			// Process the incoming text - split into lines
			string[] lines = new_text.split("\n");
			
			// Process all complete lines (with newlines)
			for (int i = 0; i < lines.length - 1; i++) {
				this.process_add_text_direct(lines[i], is_thinking);
				this.process_new_line_direct(is_thinking);
			}
			
			// Process remaining incomplete line (no newline)
			string remaining_text = lines[lines.length - 1];
			if (remaining_text != "") {
				this.process_add_text_direct(remaining_text, is_thinking);
			}
		}
		
		/**
		* Direct version of process_add_text that doesn't require Response.Chat.
		* Appends text to current markdown content based on current state.
		* 
		* @param text The text to append (does not contain newlines)
		* @param is_thinking Whether this text is thinking content
		*/
		private void process_add_text_direct(string text, bool is_thinking)
		{
			// Append text to last_line (text does not contain newlines)
			this.last_line += text;
			switch (this.content_state) {
				case ContentState.THINKING:
					if (this.thinking_frame != null) {
						this.thinking_frame.add_code_text(text);
					} else {
						this.renderer.add(text);
					}
					return;
				case ContentState.CONTENT:
					this.renderer.add(text);
					return;
				case ContentState.NONE:
					this.content_state = is_thinking ? ContentState.THINKING : ContentState.CONTENT;
					this.start_block_direct(is_thinking);
					if (this.thinking_frame != null) {
						this.thinking_frame.add_code_text(text);
					} else {
						this.renderer.add(text);
					}
					return;
			}
		}
		
		/**
		* Direct version of process_new_line that doesn't require Response.Chat.
		* Processes a newline, delegating to state-specific handlers.
		* 
		* @param is_thinking Whether we're currently in thinking mode
		*/
		private void process_new_line_direct(bool is_thinking)
		{
			switch (this.content_state) {
				case ContentState.THINKING:
					this.process_new_line_thinking_direct(is_thinking);
					break;
					
				case ContentState.CONTENT:
					this.process_new_line_content_direct();
					break;
					
				case ContentState.NONE:
					// Just output a line break in NONE state (no renderer yet)
					break;
			}
			
			// Reset last_line after processing newline (line is now complete)
			this.last_line = "";
		}
		
		/**
		* Direct version of process_new_line_thinking that doesn't require Response.Chat.
		* Handles newline when in THINKING state.
		* 
		* @param is_thinking Whether we're currently in thinking mode
		*/
		private void process_new_line_thinking_direct(bool is_thinking)
		{
			if (!is_thinking) {
				if (this.thinking_frame != null) {
					this.thinking_frame.add_code_text("\n");
					this.renderer.on_code_block(false, "");
					this.thinking_frame = null;
				}
				this.renderer.add("\n");
				this.end_block_direct(this.is_thinking);
				return;
			}
			if (this.thinking_frame != null) {
				this.thinking_frame.add_code_text("\n");
			} else {
				this.renderer.add("\n");
			}
		}
		
		/**
		* Direct version of process_new_line_content that doesn't require Response.Chat.
		* Handles newline when in CONTENT state.
		*/
		private void process_new_line_content_direct()
		{
			// Code blocks are now automatically handled by Render/RenderSourceView
			// Just add newline - Render will detect and handle code blocks
			this.renderer.add("\n");
		}
		
		/**
		* Direct version of start_block that doesn't require Response.Chat.
		* Starts a new block based on current state.
		* 
		* @param is_thinking Whether this block is thinking content
		*/
		private void start_block_direct(bool is_thinking)
		{
			switch (this.content_state) {
				case ContentState.THINKING:
				case ContentState.CONTENT:
					// Initialize renderer if needed (creates TextView on first block)
					this.renderer.start();
					if (is_thinking) {
						this.renderer.on_code_block(true, 
							"markdown.oc-frame-info.thinking.collapsed-on-done Thinking...");
						this.thinking_frame = this.renderer.childview;
						this.last_chunk_start = 0;
						return;
					}
					// Set up styling for content block using TextTags
					// Note: default_state is set AFTER renderer.start() because we need a buffer
					// to create the TextTag. The default_state will be used for future TextViews
					// created after code blocks, not the current one.
					// Create span state for content color (#333333)
					var xstyle_state = this.renderer.current_state.add_state();
					xstyle_state.style.foreground = "#333333";
					// Store as default state (for future TextViews created after code blocks)
					this.renderer.default_state = xstyle_state;
					this.last_chunk_start = 0;
					return;
					
				case ContentState.NONE:
					// Nothing to start
					return;
			}
		}
		
		/**
		* Direct version of end_block that doesn't require Response.Chat.
		* Ends the current block based on state.
		* 
		* @param is_thinking Whether we're currently in thinking mode (used for formatting)
		*/
		private void end_block_direct(bool is_thinking)
		{
			switch (this.content_state) {
				case ContentState.THINKING:
					if (this.thinking_frame != null) {
						if (this.last_line.length > 0) {
							this.thinking_frame.add_code_text("\n");
						}
						this.renderer.on_code_block(false, "");
						this.thinking_frame = null;
					}
					this.last_line = "";
					this.content_state = ContentState.NONE;
					return;
				case ContentState.CONTENT:
					if (this.last_line.length > 0) {
						this.renderer.add("\n");
					}
					this.renderer.flush();
					this.renderer.end_block();
					this.renderer.default_state = null;
					this.last_line = "";
					this.content_state = ContentState.NONE;
					return;
				case ContentState.NONE:
					return;
			}
		}
		
		/**
		 * Direct version of finalize_assistant_message that doesn't require Response.Chat.
		 * Finalizes the current assistant message.
		 * 
		 * Ensures the final chunk is rendered and resets tracking state.
		 * Performance metrics are not displayed here - they should be in the messages array
		 * as "ui" role messages and will be displayed via append_tool_message().
		 * 
		 * @since 1.0
		 */
		private void finalize_assistant_message_direct()
		{
			if (!this.is_assistant_message) {
				return;
			}
			if (this.thinking_frame != null) {
				this.renderer.on_code_block(false, "");
				this.thinking_frame = null;
			}
			// End current block if we're in one (already adds trailing newline via renderer flush)
			if (this.content_state != ContentState.NONE) {
				this.end_block_direct(this.is_thinking);
			}

			// Reset state
			this.is_assistant_message = false;
			this.last_chunk_start = 0;
			this.content_state = ContentState.NONE;
			this.is_thinking = false;
		}
		
		/**
		 * Finalizes the current assistant message after streaming (or when aborting to waiting UI).
		 * Delegates to {@link finalize_assistant_message_direct}. The optional response is unused;
		 * token/duration lines are added as separate "ui" messages in Session.finalize_streaming().
		 *
		 * @since 1.0
		 */
		public void finalize_assistant_message(OLLMchat.Response.Chat? response = null)
		{
			this.finalize_assistant_message_direct();
		}

		/**
		 * Appends a complete assistant message (not streaming).
		 * Used when loading sessions from history.
		 * 
		 * @param message The complete Message object to display
		 * @param session The session that owns this message (provides client and chat)
		 * @since 1.0
		 */
		public int append_complete_assistant_message(OLLMchat.Message message, OLLMchat.History.SessionBase session)
		{
			// Debug: Print truncated content
			string content_preview = message.content.length > 20 ? message.content.substring(0, 20) + "..." : message.content;
			string thinking_preview = message.thinking.length > 20 ? message.thinking.substring(0, 20) + "..." : message.thinking;
			//GLib.debug("ChatView.append_complete_assistant_message: Adding assistant message (content='%s', thinking='%s')", 
			//	content_preview, thinking_preview);
			
			// Finalize any ongoing assistant message
			if (this.is_assistant_message) {
				this.finalize_assistant_message_direct();
			}

			// Ensure any open block is closed and flushed so the new content is parsed in a clean state.
			// (We used to add \n here to force state exit; we only end block when one is open to avoid extra blank lines.)
			if (this.content_state != ContentState.NONE) {
				this.end_block_direct(this.is_thinking);
			}

			// Clear any waiting indicator
			this.clear_waiting_indicator();

			// Work directly with Message object - no Chat/Response.Chat needed
			// Determine thinking state from message.thinking content
			bool is_thinking = message.thinking != "";

			// Initialize assistant message state
			this.render_box.mark();
			/* GLib.debug(
				"append_complete after mark first_id=%d by_id_n=%d",
				this.render_box.first_id,
				this.render_box.by_id.size); */
			this.is_assistant_message = true;
			this.last_chunk_start = 0;
			this.content_state = ContentState.NONE;
			this.is_thinking = is_thinking;
			this.renderer.is_streaming = false;
			// Don't call renderer.start() here - let start_block_direct() handle it
			// so default_state can be set before TextView creation

			// Process thinking content first if present
			if (message.thinking != "") {
				this.process_new_chunk_direct(message.thinking, true);  // true = is_thinking
				// Ensure thinking block is finalized
				if (this.content_state != ContentState.NONE) {
					this.end_block_direct(true);  // true = is_thinking
				}
			}

			// Process regular content
			if (message.content != "") {
				this.is_thinking = false;
				this.process_new_chunk_direct(message.content, false);  // false = is_thinking
			}

			/* GLib.debug(
				"append_complete before finalize tail=%u n=%u tv=%s msg=%p",
				this.render_box.by_id.size > 0 ? (uint) (this.render_box.by_id.size - 1) : 0u,
				(uint) this.render_box.by_id.size,
				this.renderer.current_textview != null ? this.renderer.current_textview.get_type().name() : "-",
				message); */

			// Finalize the message (no response needed - metrics will be in messages array as "ui" messages after Step 1b)
			this.finalize_assistant_message_direct();
			/* GLib.debug(
				"append_complete return last_id=%d first_id=%d by_id_n=%d msg=%p",
				this.render_box.last_id,
				this.render_box.first_id,
				this.render_box.by_id.size,
				message); */
			return this.render_box.last_id;
		}

		/**
		 * Clears all content from the chat view.
		 * 
		 * @since 1.0
		 */
		public void clear()
		{
			// Reset flags when clearing chat
			this.has_displayed_user_message = false;
			this.scroll_enabled = true;
			this.autoscroll_paused_by_user = false;
			/* GLib.debug("clear by_id_n=%u", (uint) this.render_box.by_id.size); */
			this.widgets.clear();

			// Remove waiting row before tearing down markdown widgets.
			this.clear_waiting_indicator();

			// Clear renderer state (includes sourceview handlers)
			this.renderer.clear();

			// Clear all widgets from the box
			var children = this.text_view_box.get_first_child();
			while (children != null) {
				var next = children.get_next_sibling();
				this.text_view_box.remove(children);
				children = next;
			}

			this.render_box = new MarkdownGtk.RenderBox();
			this.text_view_box.append(this.render_box);
			this.renderer.disconnect_box();
			this.renderer.box = this.render_box;
			this.renderer.box.on_link_click_released.connect(this.renderer.on_link_click_released);
			this.renderer.box.on_link_motion.connect(this.renderer.on_link_motion);
			this.renderer.box.on_link_leave.connect(this.renderer.on_link_leave);

			// Reset state (indicator already cleared above)
			this.last_chunk_start = 0;
			this.is_assistant_message = false;
			this.content_state = ContentState.NONE;
		}

		/**
		 * Appends a tool message to the chat view in grey format (same as summary).
		 * Tool messages are processed as markdown before display.
		 * 
		 * This method checks if the message is a GTK Message with a widget attached,
		 * and extracts the widget if present. If a widget is provided, it will be wrapped
		 * in a Frame (with the message content as the title) and added as a framed widget
		 * instead of inserting markdown text.
		 * 
		 * @param message The Message object to display
		 * @since 1.0
		 */
		public int append_tool_message(OLLMchat.Message message)
		{
			// Debug: Print truncated content
			string content_preview = message.content.length > 20 ? message.content.substring(0, 20) + "..." : message.content;
			//GLib.debug("ChatView.append_tool_message: Adding tool message (content='%s')", content_preview);
			
			// Get end position for insertion
			var buffer = this.get_current_buffer();
			if (buffer == null) {
				return this.render_box.last_id;
			}
			
			Gtk.TextIter end_iter;
			buffer.get_end_iter(out end_iter);
			
			// Create PangoRender instance and convert to Pango markup
			//GLib.debug("ChatView.append_tool_message: Input message: %s", message.content);
			var renderer = new Markdown.PangoRender();
			var pango_result = renderer.toPango(message.content);
			//GLib.debug("ChatView.append_tool_message: Pango result: %s", pango_result);
			buffer.insert_markup(
				ref end_iter,
				"<span size=\"small\">"
					 + pango_result + "</span>\n",
				-1
			);

			/* GLib.debug(
				"idx_map tool tail=%u n=%u tv=%s msg=%p (idx set in ChatWidget after return)",
				this.render_box.by_id.size > 0 ? (uint) (this.render_box.by_id.size - 1) : 0u,
				(uint) this.render_box.by_id.size,
				this.renderer.current_textview != null ? this.renderer.current_textview.get_type().name() : "-",
				message); */

			/* GLib.debug("scroll_to_bottom_caller reason=append_tool_message"); */
			this.scroll_to_bottom();
			return this.render_box.last_id;
		}

		/**
		 * Shows an animated "waiting..." indicator.
		 * The label is shown with cycling dots (e.g. "waiting for a reply..."); it is cleared when
		 * the first content chunk arrives or clear_waiting_indicator() is called.
		 *
		 * @param label Text to show before the dots (default: "waiting for a reply"); use e.g. "Refining" for refinement flows
		 * @since 1.0
		 */
		public void show_waiting_indicator(string label = "waiting for a reply")
		{
			// Clear any existing indicator BEFORE setting is_waiting=true
			// (otherwise clear_waiting_indicator will see is_waiting=true and clear it)
			this.clear_waiting_indicator();

			this.waiting_caption = label;
			this.is_waiting = true;

			// Finalize any ongoing assistant message
			if (this.is_assistant_message) {
				this.finalize_assistant_message();
			}

			var line = new Gtk.Label("") {
				use_markup = true,
				hexpand = true,
				halign = Gtk.Align.START,
				xalign = 0,
				margin_start = 2,
				margin_top = 4,
				margin_bottom = 2
			};
			var panel = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			panel.append(line);
			this.waiting_line_label = line;
			this.waiting_panel = panel;
			this.text_view_box.append(panel);

			this.waiting_dots = 1;
			this.refresh_waiting_markup();

			this.waiting_timer = GLib.Timeout.add_seconds(1, () => {
				if (!this.is_waiting || this.waiting_line_label == null) {
					return false;
				}
				this.waiting_dots = (this.waiting_dots % 6) + 1;
				this.refresh_waiting_markup();
				return true;
			});

			/* GLib.debug("scroll_to_bottom_caller reason=show_waiting_indicator"); */
			this.scroll_to_bottom();
		}

		/**
		 * Removes the waiting row from the layout and stops the dots timer.
		 * Does not use the markdown {@link Gtk.TextBuffer} (avoids marks on the render buffer).
		 *
		 * @param response Reserved for callers; parameters kept for API compatibility.
		 * @since 1.0
		 */
		public void clear_waiting_indicator(OLLMchat.Response.Chat? _response = null)
		{
			if (this.waiting_timer != 0) {
				GLib.Source.remove(this.waiting_timer);
				this.waiting_timer = 0;
			}

			if (!this.is_waiting && this.waiting_panel == null) {
				return;
			}

			if (this.waiting_panel != null) {
				this.text_view_box.remove(this.waiting_panel);
				this.waiting_panel = null;
			}
			this.waiting_line_label = null;
			this.waiting_dots = 0;
			this.is_waiting = false;
		}

		private void refresh_waiting_markup()
		{
			if (this.waiting_line_label == null) {
				return;
			}
			string dots = string.nfill(this.waiting_dots, '.');
			string escaped = GLib.Markup.escape_text(this.waiting_caption, -1);
			this.waiting_line_label.set_markup("<span color=\"green\">" + escaped + dots + "</span>");
		}

		public void scroll_to_bottom()
		{
			/* GLib.debug(
				"scroll_to_bottom enter enabled=%s paused=%s",
				this.scroll_enabled.to_string(),
				this.autoscroll_paused_by_user.to_string()); */
			// Skip scrolling if disabled (e.g., when loading history) or user has scrolled up
			if (!this.scroll_enabled || this.autoscroll_paused_by_user) {
				/* GLib.debug("scroll_to_bottom skip early"); */
				return;
			}
			
			// Use Idle to scroll after layout is updated, with retry logic
			GLib.Idle.add(() => {
				// Check if scrolling is still enabled (might have been disabled during loading)
				if (!this.scroll_enabled || this.autoscroll_paused_by_user) {
					/* GLib.debug("scroll_to_bottom idle skip"); */
					return false;
				}
				
				// Set vertical adjustment to 100% (maximum value)
				var vadjustment = this.scrolled_window.vadjustment;
				
				if (vadjustment == null) {
					//GLib.debug("ChatView: scroll_to_bottom: vadjustment is null");
					return false;
				}
				
				// Check if layout is ready by verifying upper bound is reasonable
				// If upper is 0 or very small, layout might not be complete yet
				if (vadjustment.upper < 100.0) {
					// Layout not ready yet, try again on next idle (but only if scrolling is still enabled)
					return this.scroll_enabled && !this.autoscroll_paused_by_user;
				}
				
				// Mark as programmatic so the value_changed handler does not set autoscroll_paused_by_user
				this.programmatic_scroll_in_progress = true;
				/* GLib.debug(
					"chat_vadj_assign reason=bottom_idle upper=%.2f value_before=%.2f",
					vadjustment.upper,
					vadjustment.value); */
				// Set value higher than upper to force scroll to maximum
				// This ensures we scroll to bottom even if layout hasn't fully updated
				vadjustment.value = vadjustment.upper + 1000.0;
				this.last_scroll_pos = vadjustment.upper + 1000.0;
				
				// Also use a timeout as backup in case Idle doesn't catch all layout updates
				GLib.Timeout.add(100, () => {
					// Check if scrolling is still enabled (might have been disabled during loading)
					if (!this.scroll_enabled || this.autoscroll_paused_by_user) {
						return false;
					}
					
					if (vadjustment != null && vadjustment.upper > 100.0) {
						this.programmatic_scroll_in_progress = true;
						/* GLib.debug(
							"chat_vadj_assign reason=bottom_timeout_100ms upper=%.2f value_before=%.2f",
							vadjustment.upper,
							vadjustment.value); */
						vadjustment.value = vadjustment.upper + 1000.0;
						this.last_scroll_pos = vadjustment.upper + 1000.0;
					}
					return false;
				});
				
				return false;
			});
		}

		/** Scroll so row idx sits near the viewport top; if translate fails, try idx-1 … until idx-4. */
		public void scroll_to_idx(int idx)
		{
			if (idx < 0 || idx >= this.render_box.by_id.size) {
				/* GLib.debug(
					"scroll_idx skip idx=%d n=%u",
					idx,
					this.render_box.by_id.size); */
				return;
			}
			GLib.Idle.add(() => {
				var vadj = this.scrolled_window.vadjustment;
				if (vadj.upper < 100.0) {
					/* GLib.debug(
						"scroll_idx retry upper=%.0f idx=%d",
						vadj.upper,
						idx); */
					return true;
				}
				var t = idx;
				var w = this.render_box.by_id.get(t);
				var dx = 0.0;
				var y = 0.0;
				while (t > idx - 4 && t > -1 && w != null
						&& !w.translate_coordinates(this.text_view_box,
							 0, 0, out dx, out y)) {
					w = (t > idx - 3) && (t > 0) ?
						 this.render_box.by_id.get(--t) : null;
				}
				if (w == null) {
					/* GLib.debug(
						"scroll_idx fail idx=%d t=%d",
						idx,
						t); */
					return false;
				}
				/* GLib.debug(
					"scroll_idx ok requested=%d used_t=%d y=%.0f w=%s %p map=%s real=%s css=%s",
					idx,
					t,
					y,
					w.get_type().name(),
					w,
					w.get_mapped().to_string (),
					w.get_realized().to_string (),
					string.joinv(" ", w.get_css_classes())); */
				var target = y - 20.0;
				var max_val = double.max(vadj.lower,
					vadj.upper - vadj.page_size);
				var clamped = target.clamp(vadj.lower, max_val);
				/* GLib.debug(
					"scroll_idx vadj before idx=%d lower=%.2f value=%.2f upper=%.2f page=%.2f target=%.2f max=%.2f set=%.2f",
					idx,
					vadj.lower,
					vadj.value,
					vadj.upper,
					vadj.page_size,
					target,
					max_val,
					clamped); */
				this.programmatic_scroll_in_progress = true;
				/* GLib.debug(
					"chat_vadj_assign reason=scroll_idx idx=%d set=%.2f upper=%.2f value_before=%.2f",
					idx,
					clamped,
					vadj.upper,
					vadj.value); */
				vadj.value = clamped;
				/* GLib.debug(
					"scroll_idx vadj right_after idx=%d value=%.2f upper=%.2f",
					idx,
					vadj.value,
					vadj.upper); */
				GLib.Idle.add(() => {
					var v2 = this.scrolled_window.vadjustment;
					/* GLib.debug(
						"scroll_idx vadj idle_after idx=%d value=%.2f upper=%.2f page=%.2f",
						idx,
						v2.value,
						v2.upper,
						v2.page_size); */
					return false;
				});
				return false;
			});
		}

		/**
		* Copies text to the clipboard.
		* 
		* @param text The text to copy
		*/
		private void copy_text_to_clipboard(string text)
		{
			if (text.length == 0) {
				return;
			}
			
			// Get the clipboard and set the text
			var display = Gdk.Display.get_default();
			if (display == null) {
				return;
			}
			
			var clipboard = display.get_clipboard();
			clipboard.set_text(text);
		}

		/**
		* Gets the maximum height for collapsed view (50% of window height).
		* 
		* @return Maximum height in pixels, or -1 if window height cannot be determined
		*/
		private int get_max_collapsed_height()
		{
			// Get the window height from the scrolled window
			if (this.scrolled_window == null) {
				return -1;
			}
			
			// Get the allocation height of the scrolled window
			int window_height = this.scrolled_window.get_allocated_height();
			if (window_height <= 0) {
				// If not allocated yet, try to get from parent
				var parent = this.scrolled_window.get_parent();
				if (parent != null) {
					window_height = parent.get_allocated_height();
				}
			}
			
			if (window_height <= 0) {
				return -1;
			}
			
			// Return 50% of window height
			return (int)(window_height * 0.5);
		}
		
		/**
		* Generic function to handle resize calculations for widgets.
		* 
		* This function creates an Idle callback that measures a widget and resizes
		* a ScrolledWindow based on the specified mode.
		* 
		* @param widget The widget to measure (e.g., TextView, SourceView)
		* @param scrolled_window The ScrolledWindow to resize
		* @param mode The resize mode (INITIAL, EXPAND, COLLAPSE, or FINAL)
		* @param expand_button Optional expand button to show/hide based on content size
		* @return A function suitable for use with GLib.Idle.add()
		*/
		private bool resize_widget_callback(Gtk.Widget? widget, Gtk.ScrolledWindow scrolled_window, ResizeMode mode, Gtk.Button? expand_button = null)
		{
			// Check if widget is valid and realized
			if (widget == null || !widget.get_realized()) {
				return true; // Try again next time
			}
			
			// Get preferred height of the widget
			int min_natural = 0;
			int nat_natural = 0;
			widget.measure(Gtk.Orientation.VERTICAL, -1, out min_natural, out nat_natural, null, null);
			int natural_height = nat_natural;
			
			switch (mode) {
				case ResizeMode.EXPAND:
					// Set height to natural height to show all content
					scrolled_window.set_size_request(-1, natural_height > 0 ? natural_height : -1);
					scrolled_window.vexpand = true; // Allow expansion to natural height
					return false;
					
				case ResizeMode.INITIAL:
				case ResizeMode.COLLAPSE:
				case ResizeMode.FINAL:
					// Get max height (50% of window)
					int max_height = this.get_max_collapsed_height();
					if (max_height < 0) {
						max_height = 300; // Fallback
					}
					
					// Use the smaller of max_height (50% window) or natural height for collapsed state
					int target_height = (natural_height > 0 && natural_height < max_height) ? natural_height : max_height;
					scrolled_window.set_size_request(-1, target_height);
					scrolled_window.vexpand = false; // Prevent expansion in collapsed state
					
					// Hide expand button if content fits in collapsed view (for INITIAL and FINAL modes)
					if ((mode == ResizeMode.INITIAL || mode == ResizeMode.FINAL) && expand_button != null) {
						if (natural_height > 0 && natural_height <= max_height) {
							expand_button.visible = false;
						}
					}
					
					return false;
			}
			
			return false;
		}


		/**
		 * Updates the width of a single user message widget to match available space.
		 */
		/**
		 * Adds a blank line at the end of the buffer if the buffer is not empty.
		 * 
		 * @since 1.0
		 */
		public void add_blank_line()
		{
			// With box model, add blank line to current buffer
			var buffer = this.get_current_buffer();
			if (buffer == null) {
				return;
			}
			
			Gtk.TextIter start_iter, end_iter;
			buffer.get_start_iter(out start_iter);
			buffer.get_end_iter(out end_iter);
			
			// Add blank line if buffer is not empty
			if (!start_iter.equal(end_iter)) {
				buffer.insert(ref end_iter, "\n", -1);
			}
		}
		
		/**
		 * Adds a widget frame to the end of the chat view.
		 * 
		 * The widget will be automatically resized when the chat view is resized.
		 * The widget must be a Gtk.Frame.
		 * 
		 * @param frame The frame widget to add
		 * @since 1.0
		 */
		public void add_widget_frame(Gtk.Frame frame)
		{
			// Ensure frame is unparented before adding (required for GTK4)
			if (frame.get_parent() != null) {
				frame.unparent();
			}
			
			// Track this frame for width updates
			this.widgets.add(frame);
			
			// Add frame directly to renderer.box
			this.renderer.box.appender(frame);
			
			frame.set_visible(true);
			
			// Scroll to bottom immediately (for widgets that are already ready)
			/* GLib.debug("scroll_to_bottom_caller reason=add_widget_frame_immediate"); */
			this.scroll_to_bottom();
			
			// Also schedule delayed scrolls to catch when widget content is loaded
			// This is especially important for SourceViews that receive content asynchronously
			GLib.Idle.add(() => {
				/* GLib.debug("scroll_to_bottom_caller reason=add_widget_frame_idle"); */
				this.scroll_to_bottom();
				return false;
			});
			
			// Additional delayed scroll after a short timeout to catch late content updates
			GLib.Timeout.add(100, () => {
				/* GLib.debug("scroll_to_bottom_caller reason=add_widget_frame_timeout_100ms"); */
				this.scroll_to_bottom();
				return false; // Don't repeat
			});
		}
		
	}
}

