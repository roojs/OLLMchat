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

namespace OLLMchat.UI
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
			CONTENT,
			CODE_BLOCK
		}

		private ChatWidget? chat_widget = null;
		private Gtk.ScrolledWindow scrolled_window;
		internal Gtk.TextView text_view { get; private set; }
		internal Gtk.TextBuffer buffer { get; private set; }
		private Gtk.Box text_view_box;
		private MarkdownGtk.Render assistant_renderer;
		private string last_line = "";
		private int last_chunk_start = 0;
		private Gtk.TextMark? current_block_start = null;
		private Gtk.TextMark? current_block_end = null;
		private MarkdownGtk.Render? current_block_renderer = null;
		private bool is_assistant_message = false;
		private bool is_thinking = false;
		private ContentState content_state = ContentState.NONE;
		private bool is_waiting = false;
		private Gtk.TextMark? waiting_mark = null;
		private uint waiting_timer = 0;
		private int waiting_dots = 0;
		private string? code_block_language = null;
		private GtkSource.View? current_source_view = null;
		private GtkSource.Buffer? current_source_buffer = null;
		private Gtk.TextMark? code_block_end_mark = null;
		private Gee.ArrayList<Gtk.Widget> message_widgets = new Gee.ArrayList<Gtk.Widget>();
		private double last_scroll_pos = 0.0;

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

			// Load CSS from resource file
			var css_provider = new Gtk.CssProvider();
			try {
				css_provider.load_from_resource("/ollmchat/style.css");
			} catch (GLib.Error e) {
				GLib.warning("Failed to load CSS resource: %s", e.message);
			}
			Gtk.StyleContext.add_provider_for_display(
				Gdk.Display.get_default(),
				css_provider	,
				Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
				);
	
			this.text_view = new Gtk.TextView() {
				editable = false,
				cursor_visible = false,
				wrap_mode = Gtk.WrapMode.WORD,
				hexpand = true,
				vexpand = true
			};
			// Add CSS class for main chat view styling
			this.text_view.set_left_margin(10);
			this.buffer = this.text_view.buffer;

			// Create a box to wrap the text view with margins
			this.text_view_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = true,
			};
			this.text_view_box.append(this.text_view);

			// Create single Render instance for assistant messages (uses text_view_box)
			this.assistant_renderer = new MarkdownGtk.Render.with_box(this.text_view_box);

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
		 * @param message The MessageInterface object (ChatResponse for assistant messages)
		 * @since 1.0
		 */
		public void append_user_message(string text, Ollama.MessageInterface message)
		{
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
				vexpand = false
			};
			// Set internal padding (space between text and TextView edges)
			user_text_view.set_left_margin(12);
			user_text_view.set_right_margin(12);
			user_text_view.set_top_margin(8);
			user_text_view.set_bottom_margin(8);
			// Add CSS class to ensure proper background styling
			user_text_view.add_css_class("user-message-text");
			user_text_view.buffer.text = text;

			// Wrap in Frame for visibility and styling (like code blocks)
			var user_frame = new Gtk.Frame(null) {
				margin_top = 16,
				hexpand = true
			};
			user_frame.set_child(user_text_view);

			// Style the frame with white background and rounded corners
			// CSS is loaded from resource file in constructor
			user_frame.add_css_class("user-message-box");

			// Calculate height based on content
			// Estimate height: ~20px per line + margins
			var lines = text.split("\n").length;
			var estimated_height = (lines * 20) + 16; // 16px for margins
			// Minimum height to ensure text is visible
			user_text_view.height_request = estimated_height > 25 ? estimated_height : 25;
			
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
		 * @param message The MessageInterface object (ChatResponse for assistant messages)
		 * @since 1.0
		 */
		public void append_assistant_chunk(string new_text, Ollama.MessageInterface message)
		{
			var response = (Ollama.ChatResponse) message;

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
		private void initialize_assistant_message(Ollama.ChatResponse response)
		{
			this.is_assistant_message = true;
			this.last_chunk_start = 0;
			this.is_thinking = response.is_thinking;
			this.content_state = ContentState.NONE;

			Gtk.TextIter start_iter, end_iter;
			this.buffer.get_start_iter(out start_iter);
			this.buffer.get_end_iter(out end_iter);
			
			// Add blank line before assistant message if buffer is not empty
			if (!start_iter.equal(end_iter)) {
				this.buffer.insert(ref end_iter, "\n", -1);
			}
			this.buffer.get_end_iter(out end_iter);
			this.current_block_start = this.buffer.create_mark(null, end_iter, true);
			this.current_block_end = this.buffer.create_mark(null, end_iter, true);
		}

		/**
		* Processes new chunk from message.content using state machine.
		* Splits content into complete lines vs incomplete line and processes accordingly.
		*/
		private void process_new_chunk(string new_text, Ollama.ChatResponse response)
		{
			// Check if state changed (thinking vs content)
			// If state changed, end the current block
			if (this.is_thinking != response.is_thinking) {
				// End the current block if we're in one (end_block uses current is_thinking for formatting)
				if (this.content_state != ContentState.NONE) {
					this.end_block(response);
					// Add extra line breaks to visually separate the old block from the new one
					Gtk.TextIter end_iter;
					this.buffer.get_end_iter(out end_iter);
					this.buffer.insert(ref end_iter, "\n\n", -1);
				}
				// Update thinking state AFTER ending block (so block is formatted with old status)
				this.is_thinking = response.is_thinking;
				// New text will start a new block when process_add_text is called
			}
					
			// Process the incoming text - split into lines
			string[] lines = new_text.split("\n");
			
			// Process all complete lines (with newlines)
			for (int i = 0; i < lines.length - 1; i++) {
				this.process_add_text(lines[i], response);
				this.process_new_line(response);
			}
			
			// Process remaining incomplete line (no newline)
			string remaining_text = lines[lines.length - 1];
			if (remaining_text != "") {
				this.process_add_text(remaining_text, response);
			}
		}
		
		/**
		* Appends text to current markdown content based on current state.
		*/
		private void process_add_text(string text, Ollama.ChatResponse response)
		{
			// Append text to last_line (text does not contain newlines)
			this.last_line += text;
			
			switch (this.content_state) {
				case ContentState.CODE_BLOCK:
					// Append directly to code block buffer (current_markdown_content not used for code blocks)
					if (this.current_source_buffer == null) {
						return;
					}
					Gtk.TextIter end_iter;
					this.current_source_buffer.get_end_iter(out end_iter);
					this.current_source_buffer.insert(ref end_iter, text, -1);
					return;
					
				case ContentState.THINKING:
				case ContentState.CONTENT:
					// Ensure renderer exists (create if missing)
					if (this.current_block_renderer == null) {
						this.start_block(response);
					}
					// Send new text directly to progressive renderer
					this.current_block_renderer.add(text);
					// Update end_mark
					Gtk.TextIter end_iter;
					this.buffer.get_iter_at_mark(out end_iter, this.current_block_renderer.end_mark);
					this.buffer.move_mark(this.current_block_end, end_iter);
					return;
					
				case ContentState.NONE:
					// Start a new markdown block
					this.content_state = response.is_thinking ? ContentState.THINKING : ContentState.CONTENT;
					this.start_block(response);
					// Send text to renderer
					this.current_block_renderer.add(text);
					// Update end_mark
					Gtk.TextIter end_iter;
					this.buffer.get_iter_at_mark(out end_iter, this.current_block_renderer.end_mark);
					this.buffer.move_mark(this.current_block_end, end_iter);
					return;
			}
		}
		
		/**
		* Processes a newline, delegating to state-specific handlers.
		*/
		private void process_new_line(Ollama.ChatResponse response)
		{
			switch (this.content_state) {
				case ContentState.CODE_BLOCK:
					this.process_new_line_code_block(response);
					break;
					
				case ContentState.THINKING:
					this.process_new_line_thinking(response);
					break;
					
				case ContentState.CONTENT:
					this.process_new_line_content(response);
					break;
					
				case ContentState.NONE:
					// Just output a line break in NONE state (no renderer yet)
					break;
			}
			
			// Reset last_line after processing newline (line is now complete)
			this.last_line = "";
		}
		
		/**
		* Handles newline when in CODE_BLOCK state.
		*/
		private void process_new_line_code_block(Ollama.ChatResponse response)
		{
			// Check for closing code block marker (trim first to handle spaces before ```)
			if (!this.last_line.strip().has_prefix("```")) {
				// Insert newline into source buffer (current_markdown_content not used for code blocks)
				if (this.current_source_buffer != null) {
					Gtk.TextIter end_iter;
					this.current_source_buffer.get_end_iter(out end_iter);
					this.current_source_buffer.insert(ref end_iter, "\n", -1);
				}
				return;
			}
			
			// Closing marker detected - check last line in source buffer and remove it if it's ```
			if (this.current_source_buffer != null) {
				Gtk.TextIter start_iter, end_iter;
				this.current_source_buffer.get_bounds(out start_iter, out end_iter);
				if (!start_iter.equal(end_iter)) {
					int line_count = this.current_source_buffer.get_line_count();
					if (line_count > 0) {
						Gtk.TextIter last_line_start, last_line_end;
						this.current_source_buffer.get_iter_at_line(out last_line_start, line_count - 1);
						last_line_end = last_line_start;
						last_line_end.forward_to_line_end();
						
						// Get the text of the last line
						string last_line_text = this.current_source_buffer.get_text(last_line_start, last_line_end, false);
						
						// If it starts with ```, remove it
						if (last_line_text.strip().has_prefix("```")) {
							this.remove_last_source_view_line();
						}
					}
				}
			}
			
			this.end_block(response); // End code block first
			this.content_state = ContentState.NONE; // Set to NONE after ending
			// Reset source view references as we're no longer working with the code block
			this.current_source_view = null;
			this.current_source_buffer = null;
			// Add newline to outer textview after closing code block
			Gtk.TextIter end_iter;
			this.buffer.get_end_iter(out end_iter);
			this.buffer.insert(ref end_iter, "\n", -1);
		}
		
		/**
		* Removes the last line from the source view buffer.
		*/
		private void remove_last_source_view_line()
		{
			if (this.current_source_buffer == null) {
				return;
			}
			
			Gtk.TextIter start_iter, end_iter;
			this.current_source_buffer.get_bounds(out start_iter, out end_iter);
			if (start_iter.equal(end_iter)) {
				return; // Buffer is empty
			}
			
			// Get line count and go directly to the start of the last line
			int line_count = this.current_source_buffer.get_line_count();
			if (line_count <= 1) {
				// Single line or empty - clear entire buffer
				this.current_source_buffer.delete(ref start_iter, ref end_iter);
				return;
			}
			
			// Get iterator at start of last line (line_count - 1 is the last line, 0-indexed)
			Gtk.TextIter last_line_start;
			this.current_source_buffer.get_iter_at_line(out last_line_start, line_count - 1);
			
			// Delete from start of last line to end
			this.current_source_buffer.delete(ref last_line_start, ref end_iter);
		}
		
		/**
		* Handles newline when in THINKING state.
		*/
		private void process_new_line_thinking(Ollama.ChatResponse response)
		{
			// Check if thinking state changed to not thinking
			if (!response.is_thinking) {
				// End thinking block (end_block will reset content_state to NONE)
				if (this.current_block_renderer != null) {
					this.current_block_renderer.add("\n");
				}
				this.end_block(response);
				return;
			}
			
			// Empty lines are just regular content - add newline and continue
			// Ensure renderer exists (create if missing)
			if (this.current_block_renderer == null) {
				this.start_block(response);
			}
			// Send newline to renderer
			this.current_block_renderer.add("\n");
			// Update end_mark
			Gtk.TextIter end_iter;
			this.buffer.get_iter_at_mark(out end_iter, this.current_block_renderer.end_mark);
			this.buffer.move_mark(this.current_block_end, end_iter);
		}
		
		/**
		* Handles newline when in CONTENT state.
		*/
		private void process_new_line_content(Ollama.ChatResponse response)
		{
			// Check for code block marker (trim first to handle spaces before ```)
			if (this.last_line.strip().has_prefix("```")) {
				// Extract language before ending content block
				string language = "";
				if (this.last_line.strip().length > 3) {
					language = this.last_line.strip().substring(3).strip();
				}
				// Use language mapping kludge to get reasonable language value
				var mapped_language = this.map_language_id(language);
				this.code_block_language = mapped_language ?? language;
				
				// Ensure renderer exists (should already exist since we're in CONTENT state)
				if (this.current_block_renderer == null) {
					this.start_block(response);
				}
				
				// TODO: Remove the marker from the buffer (it was already rendered)
				// Temporarily disabled - will revisit later
				// if (this.current_source_view == null) {
				// 	// Remove last_line.length characters from the end of rendered content
				// 	Gtk.TextIter start_iter, end_iter;
				// 	this.buffer.get_iter_at_mark(out end_iter, this.current_block_renderer.end_mark);
				// 	start_iter = end_iter;
				// 	start_iter.backward_chars(this.last_line.length);
				// 	this.buffer.delete(ref start_iter, ref end_iter);
				// 	// Update renderer's end_mark to point to the new end position (so end_block() reads correct position)
				// 	this.buffer.move_mark(this.current_block_renderer.end_mark, start_iter);
				// }
				// Now end the content block and start code block
				this.end_block(response);
				this.content_state = ContentState.CODE_BLOCK;
				this.start_block(response);
				return;
			}
			
			// Empty lines are just regular content - add newline and continue
			// Ensure renderer exists (create if missing)
			if (this.current_block_renderer == null) {
				this.start_block(response);
			}
			this.current_block_renderer.add("\n");
			// Update end_mark
			Gtk.TextIter end_iter;
			this.buffer.get_iter_at_mark(out end_iter, this.current_block_renderer.end_mark);
			this.buffer.move_mark(this.current_block_end, end_iter);
		}
		/**
		* Starts a new block based on current state.
		*/
		private void start_block(Ollama.ChatResponse response)
		{
			switch (this.content_state) {
				case ContentState.THINKING:
				case ContentState.CONTENT:
					// Thinking and content blocks start with marks at current position
					Gtk.TextIter end_iter;
					this.buffer.get_end_iter(out end_iter);
					
					// Always move marks to current end position (create if null, move if exists)
					if (this.current_block_end == null) {
						this.current_block_end = this.buffer.create_mark(null, end_iter, true);
					} else {
						this.buffer.move_mark(this.current_block_end, end_iter);
					}
					if (this.current_block_start == null) {
						this.current_block_start = this.buffer.create_mark(null, end_iter, true);
					} else {
						this.buffer.move_mark(this.current_block_start, end_iter);
					}
					
					// Create Render instance for progressive rendering
					this.current_block_renderer = new MarkdownGtk.Render(
						this.buffer, 
						this.current_block_start
					);
					
					// Set up styling for thinking/content blocks using TextTags
					if (this.is_thinking) {
						// Create span state for green color
						var color_state = this.current_block_renderer.current_state.add_state();
						color_state.style.foreground = "green";
						// Create italic state nested inside
						var italic_state = color_state.add_state();
						italic_state.style.style = Pango.Style.ITALIC;
					} else {
						// Create span state for blue color
						var color_state = this.current_block_renderer.current_state.add_state();
						color_state.style.foreground = "blue";
					}
					
					this.last_chunk_start = 0;
					return;
						
				case ContentState.CODE_BLOCK:
					// Use the language already extracted in process_new_line_content
					// (code_block_language should already be set)
					if (this.code_block_language == null) {
						// Fallback: extract from last_line if not already set (trim first to handle spaces)
						string language = "";
						if (this.last_line.strip().length > 3) {
							language = this.last_line.strip().substring(3).strip();
						}
						var mapped_language = this.map_language_id(language);
						this.code_block_language = mapped_language ?? language;
					}
					this.open_code_block(this.code_block_language ?? "");
				return;
						
				case ContentState.NONE:
					// Nothing to start
					return;
			}
		}
		
		/**
		* Ends the current block based on state.
		*/
		private void end_block(Ollama.ChatResponse response)
		{
			switch (this.content_state) {
				case ContentState.THINKING:
				case ContentState.CONTENT:
					// Finalize the current markdown block
					if (this.current_block_renderer == null) {
						// No renderer means no content was rendered
						this.last_line = "";
						this.content_state = ContentState.NONE;
						return;
					}
					
					// Ensure content ends with newline if last_line has content (incomplete line)
					if (this.last_line.length > 0) {
						// Send final newline to renderer
						this.current_block_renderer.add("\n");
					}
					
					// Flush renderer to finalize
					this.current_block_renderer.flush();
					
					// Update marks to end of rendered content for finalization
					Gtk.TextIter end_iter;
					this.buffer.get_iter_at_mark(out end_iter, this.current_block_renderer.end_mark);
					if (this.current_block_start != null) {
						this.buffer.move_mark(this.current_block_start, end_iter);
					}
					this.buffer.move_mark(this.current_block_end, end_iter);
					
					// Clean up renderer
					this.current_block_renderer = null;
					
					// Call assistant_renderer.end_block() to create new TextView for next block
					this.assistant_renderer.end_block();
					
					// Reset last_line for next block
					this.last_line = "";
					// Reset content_state to NONE so new blocks can be started
					this.content_state = ContentState.NONE;
					return;
				case ContentState.CODE_BLOCK:
					this.close_code_block();
					this.code_block_language = null;
					return;
					
				case ContentState.NONE:
					// Nothing to end
					return;
			}
		}
		
		/**
		 * Finalizes the current assistant message.
		 * 
		 * Ensures the final chunk is rendered and resets tracking state.
		 * 
		 * @since 1.0
		 */
		public void finalize_assistant_message(Ollama.ChatResponse? response = null)
		{
			if (!this.is_assistant_message) {
				return;
			}

			// End current block if we're in one
			if (this.content_state != ContentState.NONE) {
				if (response != null) {
					this.end_block(response);
				}
			}

			// If we're still in a code block, close it
			if (this.content_state == ContentState.CODE_BLOCK) {
				this.close_code_block();
				this.code_block_language = null;
			}

			// Display performance metrics if response is available and done
			if (response != null && response.done && response.eval_duration > 0) {
				this.append_tool_message(
					"Total Duration: %.2fs | Tokens In: %d Out: %d | %.2f t/s".printf(
						response.total_duration_s,
						response.prompt_eval_count,
						response.eval_count,
						response.tokens_per_second
					)
				);
			} else {
				// Add final newline if no summary
				Gtk.TextIter end_iter;
				this.buffer.get_end_iter(out end_iter);
				this.buffer.insert(ref end_iter, "\n", -1);
			}

			// Reset state
			this.is_assistant_message = false;
			this.last_chunk_start = 0;
			this.current_block_start = null;
			this.current_block_end = null;
			this.current_block_renderer = null;
			this.content_state = ContentState.NONE;
			this.code_block_language = null;
			this.current_source_view = null;
			this.current_source_buffer = null;
		}

		/**
		 * Clears all content from the chat view.
		 * 
		 * @since 1.0
		 */
		public void clear()
		{
			Gtk.TextIter start_iter, end_iter;
			this.buffer.get_start_iter(out start_iter);
			this.buffer.get_end_iter(out end_iter);
			this.buffer.delete(ref start_iter, ref end_iter);

			this.last_chunk_start = 0;
			this.is_assistant_message = false;
			this.current_block_start = null;
			this.current_block_end = null;
			this.current_block_renderer = null;
			this.content_state = ContentState.NONE;
			this.code_block_language = null;
			this.current_source_view = null;
			this.current_source_buffer = null;
			if (this.code_block_end_mark != null) {
				this.buffer.delete_mark(this.code_block_end_mark);
				this.code_block_end_mark = null;
			}
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
		 * If a widget is provided and it's a Gtk.Widget, it will be wrapped in a Frame
		 * (with the message as the title) and added as a framed widget instead of inserting markdown text.
		 * 
		 * @param message The tool status message to display (may contain markdown).
		 *                 If a widget is provided, this will be used as the Frame title.
		 * @param widget Optional widget parameter (default null). If it's a Gtk.Widget,
		 *               it will be wrapped in a Frame and added as a framed widget.
		 *               Expected to be a Gtk.Widget, but typed as Object? since the Ollama
		 *               base library should work without Gtk. A cast will be needed when using this parameter.
		 * @since 1.0
		 */
		public void append_tool_message(string message, Object? widget = null)
		{
			// If widget is provided and it's a Gtk.Widget, wrap it in a Frame and add it
			if (widget is Gtk.Widget) {
				
				// Create Frame with message as title
				var frame = new Gtk.Frame(message == "" ? null : message) {
					hexpand = true,
					margin_start = 5,
					margin_end = 5,
					margin_top = 5,
					margin_bottom = 5
				};
				frame.set_child( (Gtk.Widget) widget);
				frame.add_css_class("code-block-box");
				
				// Add the framed widget
				this.add_widget_frame(frame);
				this.scroll_to_bottom();
				return;
			}
			
			// Get end position for insertion
			Gtk.TextIter end_iter;
			this.buffer.get_end_iter(out end_iter);
			
			// Create PangoRender instance and convert to Pango markup
			var renderer = new Markdown.PangoRender();
			this.buffer.insert_markup(
				ref end_iter,
				"<span size=\"small\" color=\"#1a1a1a\">"
					 + renderer.toPango(message) + "</span>\n",
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

			Gtk.TextIter end_iter;
			this.buffer.get_end_iter(out end_iter);
			
			// Create PangoRender instance and convert to Pango markup
			var renderer = new Markdown.PangoRender();
			this.buffer.insert_markup(
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
			Gtk.TextIter start_iter, end_iter;
			this.buffer.get_start_iter(out start_iter);
			this.buffer.get_end_iter(out end_iter);
			
			// Add blank line before waiting indicator if buffer is not empty
			if (!start_iter.equal(end_iter)) {
				this.buffer.insert(ref end_iter, "\n", -1);
			}
			this.buffer.get_end_iter(out end_iter);
			this.waiting_mark = this.buffer.create_mark(null, end_iter, true);
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
		public void clear_waiting_indicator(Ollama.ChatResponse? response = null)
		{
			if (!this.is_waiting) {
				return;
			}

			if (this.waiting_timer != 0) {
				GLib.Source.remove(this.waiting_timer);
				this.waiting_timer = 0;
			}

			// Get position where waiting indicator starts (after "Assistant:" label)
			Gtk.TextIter mark_pos;
			if (this.waiting_mark != null) {
				this.buffer.get_iter_at_mark(out mark_pos, this.waiting_mark);
			} else {
				this.buffer.get_end_iter(out mark_pos);
			}

		// Delete waiting indicator content (from mark to end)
			if (this.waiting_mark != null) {
				Gtk.TextIter end_iter;
				this.buffer.get_end_iter(out end_iter);
				
				if (mark_pos.get_offset() < end_iter.get_offset()) {
					this.buffer.delete(ref mark_pos, ref end_iter);
				}
				this.buffer.delete_mark(this.waiting_mark);
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

			Gtk.TextIter current_end;
			this.buffer.get_end_iter(out current_end);
			this.current_block_start = this.buffer.create_mark(null, current_end, true);
			this.current_block_end = this.buffer.create_mark(null, current_end, true);
		}

		private bool update_waiting_dots()
		{
			if (this.waiting_mark == null) {
				return false; // Stop timer
			}

			// Update dots (cycle through 1-6)
			this.waiting_dots = (this.waiting_dots % 6) + 1;
			string dots = string.nfill(this.waiting_dots, '.');

			// Delete old waiting text and insert new
			Gtk.TextIter start_iter, end_iter;
			this.buffer.get_iter_at_mark(out start_iter, this.waiting_mark);
			this.buffer.get_end_iter(out end_iter);

			if (start_iter.get_offset() < end_iter.get_offset()) {
				this.buffer.delete(ref start_iter, ref end_iter);
			}

			// Create PangoRender instance and convert to Pango markup
			var renderer = new Markdown.PangoRender();
			this.buffer.insert_markup(
				ref start_iter,
				renderer.toPango(
					"<span color=\"green\">waiting for a reply" + dots + "</span>"),
				-1
			);

			return true; // Continue timer
		}

		public void scroll_to_bottom()
		{
			// Use timeout to scroll after layout is updated (500ms delay)
			GLib.Timeout.add(500, () => {
				// Set vertical adjustment to 100% (maximum value)
				var vadjustment = this.scrolled_window.vadjustment;
				

				if (vadjustment == null) {
					GLib.debug("ChatView: scroll_to_bottom: vadjustment is null");
					return false;
				}

				// Set value higher than upper to force scroll to maximum
				// This ensures we scroll to bottom even if layout hasn't fully updated
				vadjustment.value = vadjustment.upper + 1000.0;
				this.last_scroll_pos = vadjustment.upper + 1000.0;
			//	GLib.debug("vadjustment.value=%f, vadjustment.upper=%f", vadjustment.value, vadjustment.upper);
			
				return false;
			});
		}

		/**
		 * Maps language identifiers to GtkSource language IDs.
		 * Handles common mistakes like 'val' -> 'vala', and matches val* patterns.
		 * 
		 * @param lang_id The language identifier from markdown code block
		 * @return The mapped language ID for GtkSource, or null if not found
		 */
		private string? map_language_id(string lang_id)
		{
			// Map val* patterns to vala (handles val, vala, valac, etc.)
			if (lang_id.has_prefix("val")) {
				return "vala";
			}
			return lang_id;
		}

		/**
		 * Creates a SourceView widget for code blocks.
		 * 
		 * @param language_id The language identifier for syntax highlighting
		 * @return A configured SourceView widget
		 */
		[CCode (return_value_type = "GtkSourceView*", transfer = "full")]
		public GtkSource.View create_source_view(string? language_id)
		{
			// Create buffer with language if specified
			GtkSource.Buffer source_buffer;
			if (language_id != null && language_id != "") {
				var mapped_id = this.map_language_id(language_id);
				var lang_manager = GtkSource.LanguageManager.get_default();
				var language = lang_manager.get_language(mapped_id);
				if (language != null) {
					source_buffer = new GtkSource.Buffer.with_language(language);
				} else {
					source_buffer = new GtkSource.Buffer(null);
				}
			} else {
				source_buffer = new GtkSource.Buffer(null);
			}

			// Create view
			var source_view = new GtkSource.View() {
				editable = false,
				cursor_visible = false,
				show_line_numbers = false,
				wrap_mode = Gtk.WrapMode.WORD,
				hexpand = true,
				vexpand = false,
				can_focus = false,  // Prevent sourceview from grabbing focus
				focus_on_click = false,  // Prevent focus on click
				css_classes = { "code-editor" }
			};
			source_view.set_buffer(source_buffer);
			
			// Prevent clicks in sourceview from causing textview to scroll
			// Store scroll position before any interaction and restore it
			var click_controller = new Gtk.GestureClick();
			double stored_scroll_pos = 0.0;
			click_controller.pressed.connect((n_press, x, y) => {
				// Store current scroll position
				var vadjustment = this.scrolled_window.vadjustment;
				if (vadjustment != null) {
					stored_scroll_pos = vadjustment.value;
				}
			});
			click_controller.released.connect((n_press, x, y) => {
				// Restore scroll position after click to prevent jump
				var vadjustment = this.scrolled_window.vadjustment;
				if (vadjustment != null) {
					GLib.Idle.add(() => {
						if (vadjustment != null) {
							vadjustment.value = stored_scroll_pos;
						}
						return false;
					});
				}
			});
			source_view.add_controller(click_controller);
			
			// Connect to buffer changes to ensure TextView scrolls correctly
			// When SourceView content changes, scroll TextView to show the bottom of the SourceView
			source_buffer.changed.connect(() => {
				// Use Idle to scroll after layout is updated
				GLib.Idle.add(() => {
					// Scroll to the end mark which is positioned right after the SourceView widget
					// This ensures we show the bottom of the SourceView as it grows
					if (this.code_block_end_mark != null) {
						Gtk.TextIter mark_iter;
						this.buffer.get_iter_at_mark(out mark_iter, this.code_block_end_mark);
						// Scroll with vertical alignment at bottom (1.0) to show bottom of SourceView
						this.text_view.scroll_to_iter(mark_iter, 0.0, false, 0.0, 1.0);
					} else {
						// Fallback: scroll to bottom
						this.scroll_to_bottom();
					}
					return false;
				});
			});

			// Set monospace font for code display using CSS
			// CSS is loaded from resource file in constructor
			source_view.add_css_class("code-editor");

			return source_view;
		}

		/**
		 * Handles opening a code block by creating and inserting a SourceView widget.
		 */
		private void open_code_block(string language_id)
		{
			// Create SourceView widget
			this.current_source_view = this.create_source_view(language_id);
			this.current_source_buffer = (GtkSource.Buffer) this.current_source_view.buffer;

			// Create a vertical container box for button header and SourceView
			var container_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = false
			};
			
			// Create horizontal box for button at top-right
			var button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true,
				vexpand = false
			};
			
			// Add spacer to push button to the right
			button_box.append(new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true
			});
			
			// Create Copy to Clipboard button
			// Capture the specific source_buffer for this code block (not the class member)
			var source_buffer_for_button = this.current_source_buffer;
			var copy_button = new Gtk.Button.with_label("Copy to Clipboard") {
				hexpand = false,
				margin_start = 5,
				margin_end = 5,
				margin_top = 5,
				margin_bottom = 2,
				can_focus = false,  // Prevent button from grabbing focus
				focus_on_click = false  // Prevent focus on click
			};
			
			// Set cursor to pointer (fixes issue with TextView showing text cursor)
			var cursor = new Gdk.Cursor.from_name("pointer", null);
			if (cursor != null) {
				copy_button.set_cursor(cursor);
			}
			
			// Connect button click handler - use the captured buffer, not the class member
			copy_button.clicked.connect(() => {
				// Store current scroll position to restore it after copy
				var vadjustment = this.scrolled_window.vadjustment;
				double scroll_position = 0.0;
				if (vadjustment != null) {
					scroll_position = vadjustment.value;
				}
				
				// Copy to clipboard
				this.copy_source_view_to_clipboard(source_buffer_for_button);
				
				// Restore scroll position after a brief delay to prevent jump
				GLib.Idle.add(() => {
					if (vadjustment != null) {
						vadjustment.value = scroll_position;
					}
					return false;
				});
			});
			
			// Add button to button box (right side)
			button_box.append(copy_button);
			
			// Add button box to container
			container_box.append(button_box);
			
			// Add SourceView to container (expanding)
			this.current_source_view.hexpand = true;
			this.current_source_view.vexpand = true;
			container_box.append(this.current_source_view);

			// Wrap in Frame for visibility and styling
			var frame = new Gtk.Frame(null) {
				hexpand = true,
				margin_start = 5,
				margin_end = 5,
				margin_top = 5,
				margin_bottom = 5
			};
			frame.set_child(container_box);
			
			// Style the frame with white background and rounded corners
			frame.add_css_class("code-block-box");

			// Add frame directly to assistant_renderer.box
			// Track this frame for width updates
			this.message_widgets.add(frame);
			
			// Add frame to box
			this.assistant_renderer.box.append(frame);
			
			frame.set_visible(true);
			
			// Scroll to bottom to show new content
			this.scroll_to_bottom();
			
			// No anchor needed for box-based approach
			this.code_block_end_mark = null;

			// Set reasonable size for code block (smaller for single-line content)
			this.current_source_view.height_request = 25;
			this.current_source_view.set_visible(true);
		}

		/**
		 * Copies the content of a SourceView buffer to the clipboard.
		 * 
		 * @param source_buffer The SourceView buffer to copy from
		 */
		private void copy_source_view_to_clipboard(GtkSource.Buffer? source_buffer)
		{
			if (source_buffer == null) {
				return;
			}
			
			// Get all text from the buffer
			Gtk.TextIter start_iter, end_iter;
			source_buffer.get_start_iter(out start_iter);
			source_buffer.get_end_iter(out end_iter);
			string text = source_buffer.get_text(start_iter, end_iter, false);
			
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
		 * Handles closing a code block by cleaning up state.
		 */
		private void close_code_block()
		{
			// Debug: Print code block being finalized
			string lang_str = (this.code_block_language != null) ? this.code_block_language : "unknown";
			stdout.printf("[ChatView] Finalizing CODE_BLOCK: language='%s'\n", lang_str);
			
			// Update marks to point after the code block
			// Use code_block_end_mark if available, otherwise use end of buffer
			Gtk.TextIter end_iter;
			if (this.code_block_end_mark != null) {
				this.buffer.get_iter_at_mark(out end_iter, this.code_block_end_mark);
			} else {
				this.buffer.get_end_iter(out end_iter);
			}
			
			if (this.current_block_end != null) {
				this.buffer.move_mark(this.current_block_end, end_iter);
			} else {
				this.current_block_end = this.buffer.create_mark(null, end_iter, true);
			}
			if (this.current_block_start != null) {
				this.buffer.move_mark(this.current_block_start, end_iter);
			} else {
				this.current_block_start = this.buffer.create_mark(null, end_iter, true);
			}

			// Clean up code block marks
			if (this.code_block_end_mark != null) {
				this.buffer.delete_mark(this.code_block_end_mark);
				this.code_block_end_mark = null;
			}

			// SourceView widget will remain in TextView, just stop writing to it
			this.current_source_view = null;
			this.current_source_buffer = null;
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
			Gtk.TextIter start_iter, end_iter;
			this.buffer.get_start_iter(out start_iter);
			this.buffer.get_end_iter(out end_iter);
			
			// Add blank line if buffer is not empty
			if (!start_iter.equal(end_iter)) {
				this.buffer.insert(ref end_iter, "\n", -1);
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
			
			// Add frame directly to assistant_renderer.box
			this.assistant_renderer.box.append(frame);
			
			frame.set_visible(true);
			
			// Scroll to bottom to show new content
			this.scroll_to_bottom();
		}
		
		/**
		 * Removes a widget frame from the chat view.
		   THIS DOES NOT APPEAR TO BE USED.. - we might need it later for 'clear' operation though?
		 * 
		 * @param frame The frame widget to remove
		 * @param anchor The TextChildAnchor returned from add_widget_frame()
		 * @since 1.0
		 */
		public void remove_widget_frame(Gtk.Frame frame, Gtk.TextChildAnchor anchor)
		{
			// Remove from tracking
			this.message_widgets.remove(frame);
			
			// Hide the widget first to prevent snapshot issues
			frame.set_visible(false);
			
			// Remove the anchor and surrounding text from the buffer
			// This will automatically unparent the widget
			Gtk.TextIter start_iter, end_iter;
			this.buffer.get_iter_at_child_anchor(out start_iter, anchor);
			
			// Get the end iter (after the newline we inserted)
			end_iter = start_iter;
			end_iter.forward_char(); // Skip the anchor character
			if (!end_iter.is_end()) {
				end_iter.forward_char(); // Skip the newline
			}
			
			// Delete the anchor and newline from buffer
			// This will cause GTK to automatically unparent the widget
			this.buffer.delete(ref start_iter, ref end_iter);
			
			// Note: TextChildAnchor is automatically deleted when removed from buffer
		}
		
	}
}

