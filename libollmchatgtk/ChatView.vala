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

		private ChatWidget? chat_widget = null;
		private Gtk.ScrolledWindow scrolled_window;
		private Gtk.Box text_view_box;
		private MarkdownGtk.Render renderer;
		private string last_line = "";
		private int last_chunk_start = 0;
		private bool is_assistant_message = false;
		private bool is_thinking = false;
		private ContentState content_state = ContentState.NONE;
		private bool is_waiting = false;
		private Gtk.TextMark? waiting_mark = null;
		private uint waiting_timer = 0;
		private int waiting_dots = 0;
		private Gee.ArrayList<Gtk.Widget> message_widgets = new Gee.ArrayList<Gtk.Widget>();
		private bool has_displayed_user_message = false;
		private double last_scroll_pos = 0.0;
		public bool scroll_enabled = true;
		

		/**
		 * Creates a new ChatView instance.
		 * 
		 * @param chat_widget The parent ChatWidget to access current chat state
		 * @since 1.0
		 */
		public ChatView(ChatWidget? chat_widget = null)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			this.chat_widget = chat_widget;

			// Load CSS from resource files
			string[] css_files = { "pulldown.css", "style.css" };
			foreach (var css_file in css_files) {
				var css_provider = new Gtk.CssProvider();
				try {
					css_provider.load_from_resource(@"/ollmchat/$(css_file)");
					Gtk.StyleContext.add_provider_for_display(
						Gdk.Display.get_default(),
						css_provider,
						Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
					);
				} catch (GLib.Error e) {
					GLib.warning("Failed to load %s resource: %s", css_file, e.message);
				}
			}
	
			// Create a box for assistant message content
			this.text_view_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = true,
				margin_start = 2,
				margin_end = 0
			};

			// Create single Render instance for assistant messages (uses text_view_box)
			this.renderer = new MarkdownGtk.Render(this.text_view_box) {
				scroll_to_end = this.scroll_enabled
			};
			
			// Connect to code block content updates to scroll when sourceviews receive content
			this.renderer.code_block_content_updated.connect(() => {
				this.scroll_to_bottom();
			});

			this.scrolled_window = new Gtk.ScrolledWindow() {
				hexpand = true,
				vexpand = true
			};
			this.scrolled_window.set_child(text_view_box);
			this.append(this.scrolled_window);
			this.scrolled_window.add_css_class("chat-view-text");

			
			
		}

		/**
		 * Appends a message to the chat view.
		 * 
		 * @param text The message text to display
		 * @param session The session that owns this message (provides client and chat)
		 * @since 1.0
		 */
		public void append_user_message(string text, OLLMchat.History.SessionBase session)
		{
			// Debug: Print truncated content
			string content_preview = text.length > 20 ? text.substring(0, 20) + "..." : text;
			GLib.debug("ChatView.append_user_message: Adding user message (content='%s')", content_preview);
			
			// Finalize any ongoing assistant message
			if (this.is_assistant_message) {
				this.finalize_assistant_message();
			}

			// Clear any waiting indicator
			this.clear_waiting_indicator();

			// Create TextView for user message
			var user_text_view = new Gtk.TextView() {
				editable = false,
				cursor_visible = false,
				wrap_mode = Gtk.WrapMode.WORD,
				hexpand = true,
				vexpand = true
			};
			// Set internal padding (space between text and TextView edges)
			user_text_view.set_left_margin(12);
			user_text_view.set_right_margin(12);
			user_text_view.set_top_margin(8);
			user_text_view.set_bottom_margin(8);
			// Add CSS class to ensure proper background styling
			user_text_view.add_css_class("oc-user-message-text");
			user_text_view.buffer.text = text;

			// Create ScrolledWindow for the TextView with height constraints
			var user_scrolled = new Gtk.ScrolledWindow() {
				hexpand = true,
				vexpand = false
			};
			user_scrolled.set_child(user_text_view);
			user_scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);

			// Track expanded state
			bool is_expanded = false;
			
			// Check if this is the first user message we've displayed
			bool is_first_message = !this.has_displayed_user_message;
			this.has_displayed_user_message = true;
			
			// Create header box with title on left and buttons on right
			var header_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true,
				vexpand = false,
				margin_start = 0,
				margin_end = 0,
				margin_top = 0,
				margin_bottom = 0
			};
			header_box.add_css_class("oc-frame-header");
			
			// Add title label on the left
			var title_label = new Gtk.Label("You said:") {
				hexpand = false,
				halign = Gtk.Align.START,
				valign = Gtk.Align.CENTER,
				margin_start = 5
			};
			title_label.add_css_class("oc-user-frame-title");
			header_box.append(title_label);
			
			// Add spacer to push buttons to the right
			header_box.append(new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true
			});
			
			// Create horizontal box for buttons at top-right
			var button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = false,
				vexpand = false
			};
			
			// Create Copy to Clipboard button with icon
			var copy_button = new Gtk.Button() {
				icon_name = "edit-copy-symbolic",
				tooltip_text = "Copy to Clipboard",
				hexpand = false,
				margin_start = 5,
				margin_end = 0,
				margin_top = 0,
				margin_bottom = 0,
				can_focus = false,
				focus_on_click = false
			};
			
			// Connect copy button click handler
			copy_button.clicked.connect(() => {
				this.copy_text_to_clipboard(text);
			});
			
			// Create Expand/Collapse button with icon
			var expand_button = new Gtk.Button() {
				icon_name = "pan-down-symbolic",
				tooltip_text = "Expand",
				hexpand = false,
				margin_start = 5,
				margin_end = 5,
				margin_top = 0,
				margin_bottom = 0,
				can_focus = false,
				focus_on_click = false
			};
			
			// Calculate natural height of the text content
			// Use Idle to wait for layout, then set height based on natural size
			GLib.Idle.add(() => {
				return this.resize_widget_callback(user_text_view, user_scrolled, ResizeMode.INITIAL, expand_button);
			});
			
			// Connect expand/collapse button click handler
			expand_button.clicked.connect(() => {
				is_expanded = !is_expanded;
				if (is_expanded) {
					expand_button.icon_name = "pan-up-symbolic";
					expand_button.tooltip_text = "Collapse";
					// Set height to natural height of content
					GLib.Idle.add(() => {
						return this.resize_widget_callback(user_text_view, user_scrolled, ResizeMode.EXPAND);
					});
					return;
				} 
				expand_button.icon_name = "pan-down-symbolic";
				expand_button.tooltip_text = "Expand";
				// Recalculate natural height and set collapsed height
				GLib.Idle.add(() => {
					return this.resize_widget_callback(user_text_view, user_scrolled, ResizeMode.COLLAPSE);
				});
			});
			
			// Add buttons to button box
			button_box.append(copy_button);
			
			// Add "Start new chat with this" button if this is the first message (before expand button)
			if (is_first_message && this.chat_widget != null) {
				var new_chat_button = new Gtk.Button() {
					icon_name = "list-add-symbolic",
					tooltip_text = "Start new chat with this",
					hexpand = false,
					margin_start = 5,
					margin_end = 5,
					can_focus = false,
					focus_on_click = false
				};
				
				// Connect new chat button click handler
				new_chat_button.clicked.connect(() => {
					this.chat_widget.start_new_chat_with_text.begin(text);
				});
				
				button_box.append(new_chat_button);
			}
			
			button_box.append(expand_button);
			
			// Add button box to header
			header_box.append(button_box);
			
			// Create vertical container box for header and ScrolledWindow
			var container_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = false
			};
			
			// Add header box to container
			container_box.append(header_box);
			
			// Add ScrolledWindow to container
			container_box.append(user_scrolled);

			// Wrap in Frame for visibility and styling (like code blocks)
			var user_frame = new Gtk.Frame(null) {
				margin_top = 0,
				margin_bottom = 0,
				hexpand = true
			};
			user_frame.set_child(container_box);

			// Style the frame with white background and rounded corners
			// CSS is loaded from resource file in constructor
			// Use CSS class matching the chat role name
			user_frame.add_css_class("oc-user-sent-frame");
			
			user_text_view.set_visible(true);
			
			// Add blank line and frame at end
			this.add_blank_line();
			this.add_widget_frame(user_frame);
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
		public void append_assistant_chunk(string new_text, OLLMchat.Response.Chat response)
		{

			if (this.is_waiting) {
				this.clear_waiting_indicator(response);
			}

			if (!this.is_assistant_message) {
				this.initialize_assistant_message(response);
			}

			// Process the incoming new_text chunk directly
			if (new_text.length > 0) {
				this.process_new_chunk(new_text, response);
			}

			this.scroll_to_bottom();
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
			this.is_assistant_message = true;
			this.last_chunk_start = 0;
			this.is_thinking = response.is_thinking;
			this.content_state = ContentState.NONE;
			// Initialize the renderer for the new assistant message
			this.renderer.start();
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
				case ContentState.CONTENT:
					// Send new text directly to progressive renderer (handles code blocks automatically)
					this.renderer.add(text);
					// No need to update end_mark anymore (box model handles it)
					return;
					
				case ContentState.NONE:
					// Start a new markdown block
					this.content_state = is_thinking ? ContentState.THINKING : ContentState.CONTENT;
					this.start_block_direct(is_thinking);
					// Send text to renderer
					this.renderer.add(text);
					// No need to update end_mark anymore (box model handles it)
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
			// Check if thinking state changed to not thinking
			if (!is_thinking) {
				// End thinking block (end_block_direct will reset content_state to NONE)
				this.renderer.add("\n");
				this.end_block_direct(this.is_thinking);
				return;
			}
			
			// Empty lines are just regular content - add newline and continue
			// Send newline to renderer
			this.renderer.add("\n");
			// No need to update end_mark anymore (box model handles it)
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
					
					// Set up styling for thinking/content blocks using TextTags
					// Note: default_state is set AFTER renderer.start() because we need a buffer
					// to create the TextTag. The default_state will be used for future TextViews
					// created after code blocks, not the current one.
					if (is_thinking) {
						// Create span state for thinking with both color (#767676) and italic
						var style_state = this.renderer.current_state.add_state();
						style_state.style.foreground = "#767676";
						style_state.style.style = Pango.Style.ITALIC;
						// Store as default state (for future TextViews created after code blocks)
						this.renderer.default_state = style_state;
						this.last_chunk_start = 0;
						return;
					} 
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
				case ContentState.CONTENT:
					// Ensure content ends with newline if last_line has content (incomplete line)
					if (this.last_line.length > 0) {
						// Send final newline to renderer
						this.renderer.add("\n");
					}
					
					// Flush renderer to finalize
					this.renderer.flush();
					
					// Call renderer.end_block() to end current block
					// (start() will be called when starting the next block)
					this.renderer.end_block();
					
					// Clear default state when block ends
					this.renderer.default_state = null;
					
					// Reset last_line for next block
					this.last_line = "";
					// Reset content_state to NONE so new blocks can be started
					this.content_state = ContentState.NONE;
					return;
					
				case ContentState.NONE:
					// Nothing to end
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

			// End current block if we're in one
			if (this.content_state != ContentState.NONE) {
				this.end_block_direct(this.is_thinking);
			}

			// Add final newline
			var buffer = this.get_current_buffer();
			if (buffer != null) {
				Gtk.TextIter end_iter;
				buffer.get_end_iter(out end_iter);
				buffer.insert(ref end_iter, "\n", -1);
			}

			// Reset state
			this.is_assistant_message = false;
			this.last_chunk_start = 0;
			this.content_state = ContentState.NONE;
		}
		
		/**
		 * Finalizes the current assistant message.
		 * 
		 * Ensures the final chunk is rendered and resets tracking state.
		 * 
		 * For streaming responses, performance metrics are now stored as "ui" messages
		 * in the messages array (see Session.finalize_streaming()). For backward compatibility,
		 * this method still displays metrics from response if provided, but metrics should
		 * already be in the messages array for history loading.
		 * 
		 * @since 1.0
		 */
		public void finalize_assistant_message(OLLMchat.Response.Chat? response = null)
		{
			if (!this.is_assistant_message) {
				return;
			}

			// End current block if we're in one
			if (this.content_state != ContentState.NONE) {
				this.end_block_direct(this.is_thinking);
			}

			// Note: Performance metrics are now stored as "ui" messages in Session.finalize_streaming()
			// and displayed via the message_created signal flow (ChatWidget.on_message_created()),
			// so we don't need to display them here anymore.
			// Add final newline
			var buffer = this.get_current_buffer();
			if (buffer != null) {
				Gtk.TextIter end_iter;
				buffer.get_end_iter(out end_iter);
				buffer.insert(ref end_iter, "\n", -1);
			}

			// Reset state
			this.is_assistant_message = false;
			this.last_chunk_start = 0;
			this.content_state = ContentState.NONE;
		}

		/**
		 * Appends a complete assistant message (not streaming).
		 * Used when loading sessions from history.
		 * 
		 * @param message The complete Message object to display
		 * @param session The session that owns this message (provides client and chat)
		 * @since 1.0
		 */
		public void append_complete_assistant_message(OLLMchat.Message message, OLLMchat.History.SessionBase session)
		{
			// Debug: Print truncated content
			string content_preview = message.content.length > 20 ? message.content.substring(0, 20) + "..." : message.content;
			string thinking_preview = message.thinking.length > 20 ? message.thinking.substring(0, 20) + "..." : message.thinking;
			GLib.debug("ChatView.append_complete_assistant_message: Adding assistant message (content='%s', thinking='%s')", 
				content_preview, thinking_preview);
			
			// Finalize any ongoing assistant message
			if (this.is_assistant_message) {
				this.finalize_assistant_message_direct();
			}

			// Clear any waiting indicator
			this.clear_waiting_indicator();

			// Work directly with Message object - no Chat/Response.Chat needed
			// Determine thinking state from message.thinking content
			bool is_thinking = message.thinking != "";

			// Initialize assistant message state
			this.is_assistant_message = true;
			this.last_chunk_start = 0;
			this.content_state = ContentState.NONE;
			this.is_thinking = is_thinking;
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

			// Finalize the message (no response needed - metrics will be in messages array as "ui" messages after Step 1b)
			this.finalize_assistant_message_direct();
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
			
			// Clear renderer state (includes sourceview handlers)
			this.renderer.clear();
			
			// Clear all widgets from the box
			var children = this.text_view_box.get_first_child();
			while (children != null) {
				var next = children.get_next_sibling();
				this.text_view_box.remove(children);
				children = next;
			}
			
			// Reset state
			this.last_chunk_start = 0;
			this.is_assistant_message = false;
			this.content_state = ContentState.NONE;
			this.clear_waiting_indicator();
		}

		/**
		 * Displays an error message in the chat view.
		 * 
		 * @param error The error message to display
		 * @since 1.0
		 */

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
		public void append_tool_message(OLLMchat.Message message)
		{
			// Debug: Print truncated content
			string content_preview = message.content.length > 20 ? message.content.substring(0, 20) + "..." : message.content;
			GLib.debug("ChatView.append_tool_message: Adding tool message (content='%s')", content_preview);
			
			// Get end position for insertion
			var buffer = this.get_current_buffer();
			if (buffer == null) {
				return;
			}
			
			Gtk.TextIter end_iter;
			buffer.get_end_iter(out end_iter);
			
			// Create PangoRender instance and convert to Pango markup
			GLib.debug("ChatView.append_tool_message: Input message: %s", message.content);
			var renderer = new Markdown.PangoRender();
			var pango_result = renderer.toPango(message.content);
			GLib.debug("ChatView.append_tool_message: Pango result: %s", pango_result);
			buffer.insert_markup(
				ref end_iter,
				"<span size=\"small\" color=\"#1a1a1a\">"
					 + pango_result + "</span>\n",
				-1
			);
			
			this.scroll_to_bottom();
		}

		public void append_error(string error)
		{
			// Clear any waiting indicator first to prevent it from deleting the error later
			this.clear_waiting_indicator();
			
			// Finalize any ongoing assistant message
			if (this.is_assistant_message) {
				this.finalize_assistant_message();
			}

			// Get end position for insertion
			var buffer = this.get_current_buffer();
			if (buffer == null) {
				return;
			}
			
			Gtk.TextIter end_iter;
			buffer.get_end_iter(out end_iter);
			
			// Create PangoRender instance and convert to Pango markup
			var renderer = new Markdown.PangoRender();
			buffer.insert_markup(
				ref end_iter,
				renderer.toPango("<span color=\"red\"><b>Error:</b> " +
					 GLib.Markup.escape_text(error, -1) + "</span>\n\n"),
				-1
			);

			this.scroll_to_bottom();
		}


		/**
		 * Shows an animated "waiting..." indicator.
		 * 
		 * @since 1.0
		 */
		public void show_waiting_indicator()
		{
			// Clear any existing indicator BEFORE setting is_waiting=true
			// (otherwise clear_waiting_indicator will see is_waiting=true and clear it)
			this.clear_waiting_indicator();

			// Set waiting state AFTER clearing
			this.is_waiting = true;

			// Finalize any ongoing assistant message
			if (this.is_assistant_message) {
				this.finalize_assistant_message();
			}

			// Insert waiting indicator
			var buffer = this.get_current_buffer();
			if (buffer == null) {
				return;
			}
			
			Gtk.TextIter start_iter, end_iter;
			buffer.get_start_iter(out start_iter);
			buffer.get_end_iter(out end_iter);
			
			// Add blank line before waiting indicator if buffer is not empty
			if (!start_iter.equal(end_iter)) {
				buffer.insert(ref end_iter, "\n", -1);
			}
			buffer.get_end_iter(out end_iter);
			this.waiting_mark = buffer.create_mark("waiting-indicator", end_iter, true);
			this.waiting_dots = 0;
			this.update_waiting_dots();

			// Start timer to update dots every 1 second (2x speed)
			this.waiting_timer = GLib.Timeout.add_seconds(1, () => {
				this.update_waiting_dots();
				return true; // Continue timer
			});

			this.scroll_to_bottom();
		}

		/**
		 * Clears the waiting indicator and resets assistant message state if needed.
		 * 
		 * @param response Optional ChatResponse to initialize state when clearing waiting
		 * @since 1.0
		 */
		public void clear_waiting_indicator(OLLMchat.Response.Chat? response = null)
		{
			if (!this.is_waiting) {
				return;
			}

			if (this.waiting_timer != 0) {
				GLib.Source.remove(this.waiting_timer);
				this.waiting_timer = 0;
			}

			// Get position where waiting indicator starts (after "Assistant:" label)
			var buffer = this.renderer.current_buffer;
			if (buffer == null) {
				this.waiting_mark = null;
				this.is_waiting = false;
				return;
			}
			
			Gtk.TextIter mark_pos;
			if (this.waiting_mark != null) {
				buffer.get_iter_at_mark(out mark_pos, this.waiting_mark);
			} else {
				buffer.get_end_iter(out mark_pos);
			}

			// Delete waiting indicator content (from mark to end)
			if (this.waiting_mark != null) {
				Gtk.TextIter end_iter;
				buffer.get_end_iter(out end_iter);
				
				if (mark_pos.get_offset() < end_iter.get_offset()) {
					buffer.delete(ref mark_pos, ref end_iter);
				}
				buffer.delete_mark(this.waiting_mark);
				this.waiting_mark = null;
			}
			this.waiting_dots = 0;


			this.is_waiting = false;
			if (response == null) {
				return;
			}
			
			this.is_assistant_message = true;
			this.last_chunk_start = 0;
			this.is_thinking = response.is_thinking;
			this.content_state = ContentState.NONE;
			// With box model, no need to create marks - Render handles it
		}

		private bool update_waiting_dots()
		{
			if (this.waiting_mark == null) {
				return false; // Stop timer
			}
			if (!this.is_waiting) {
				return false; // Stop timer
			}

			var buffer = this.renderer.current_buffer;
			if (buffer == null) {
				return false; // Stop timer if buffer is gone
			}

			// Check if mark is still valid (hasn't been deleted)
			var mark = buffer.get_mark("waiting-indicator");
			if (mark == null || mark != this.waiting_mark) {
				this.waiting_mark = null;
				return false; // Stop timer
			}

			// Update dots (cycle through 1-6)
			this.waiting_dots = (this.waiting_dots % 6) + 1;
			string dots = string.nfill(this.waiting_dots, '.');

			// Delete old waiting text and insert new
			Gtk.TextIter start_iter, end_iter;
			buffer.get_iter_at_mark(out start_iter, this.waiting_mark);
			buffer.get_end_iter(out end_iter);

			if (start_iter.get_offset() < end_iter.get_offset()) {
				buffer.delete(ref start_iter, ref end_iter);
			}

			// Create PangoRender instance and convert to Pango markup
			var renderer = new Markdown.PangoRender();
			buffer.insert_markup(
				ref start_iter,
				renderer.toPango(
					"<span color=\"green\">waiting for a reply" + dots + "</span>"),
				-1
			);

			return true; // Continue timer
		}

		public void scroll_to_bottom()
		{
			// Skip scrolling if disabled (e.g., when loading history)
			if (!this.scroll_enabled) {
				return;
			}
			
			// Use Idle to scroll after layout is updated, with retry logic
			GLib.Idle.add(() => {
				// Check if scrolling is still enabled (might have been disabled during loading)
				if (!this.scroll_enabled) {
					return false;
				}
				
				// Set vertical adjustment to 100% (maximum value)
				var vadjustment = this.scrolled_window.vadjustment;
				
				if (vadjustment == null) {
					GLib.debug("ChatView: scroll_to_bottom: vadjustment is null");
					return false;
				}
				
				// Check if layout is ready by verifying upper bound is reasonable
				// If upper is 0 or very small, layout might not be complete yet
				if (vadjustment.upper < 100.0) {
					// Layout not ready yet, try again on next idle (but only if scrolling is still enabled)
					return this.scroll_enabled;
				}
				
				// Set value higher than upper to force scroll to maximum
				// This ensures we scroll to bottom even if layout hasn't fully updated
				vadjustment.value = vadjustment.upper + 1000.0;
				this.last_scroll_pos = vadjustment.upper + 1000.0;
				
				// Also use a timeout as backup in case Idle doesn't catch all layout updates
				GLib.Timeout.add(100, () => {
					// Check if scrolling is still enabled (might have been disabled during loading)
					if (!this.scroll_enabled) {
						return false;
					}
					
					if (vadjustment != null && vadjustment.upper > 100.0) {
						vadjustment.value = vadjustment.upper + 1000.0;
						this.last_scroll_pos = vadjustment.upper + 1000.0;
					}
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
			this.message_widgets.add(frame);
			
			// Add frame directly to renderer.box
			this.renderer.box.append(frame);
			
			frame.set_visible(true);
			
			// Scroll to bottom immediately (for widgets that are already ready)
			this.scroll_to_bottom();
			
			// Also schedule delayed scrolls to catch when widget content is loaded
			// This is especially important for SourceViews that receive content asynchronously
			GLib.Idle.add(() => {
				this.scroll_to_bottom();
				return false;
			});
			
			// Additional delayed scroll after a short timeout to catch late content updates
			GLib.Timeout.add(100, () => {
				this.scroll_to_bottom();
				return false; // Don't repeat
			});
		}
		
		/**
		 * Removes a widget frame from the chat view.
		   THIS DOES NOT APPEAR TO BE USED.. - we might need it later for 'clear' operation though?
		 * 
		 * @param frame The frame widget to remove
		 * @param anchor The TextChildAnchor returned from add_widget_frame() (unused with box model)
		 * @since 1.0
		 */
		public void remove_widget_frame(Gtk.Frame frame, Gtk.TextChildAnchor anchor)
		{
			// Remove from tracking
			this.message_widgets.remove(frame);
			
			// Hide the widget first to prevent snapshot issues
			frame.set_visible(false);
			
			// With box model, just remove the frame from its parent
			if (frame.get_parent() != null) {
				frame.unparent();
			}
		}
		
	}
}

