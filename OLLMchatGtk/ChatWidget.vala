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

namespace OLLMchatGtk
{
	/**
	 * Reusable chat widget that can be embedded anywhere in the project.
	 * 
	 * This widget provides a complete chat interface with markdown rendering
	 * and streaming support. The caller must pass an OLLMchat.Client instance
	 * to the constructor.
	 * 
	 * @since 1.0
	 */
	public class ChatWidget : Gtk.Box
	{
		[CCode (type = "OLLMchatUIChatView*", transfer = "none")]
		public ChatView chat_view { get; private set; }
		[CCode (type = "OLLMchatUIChatPermission*", transfer = "none")]
		public ChatPermission permission_widget { get; private set; }
		private ChatInput chat_input;
		private Gtk.Paned paned;
		public OLLMchat.History.Manager manager { get; private set; }
		
		private bool is_streaming_active = false;
		private string? last_sent_text = null;
		private int min_bottom_size = 115;

		/**
		* Default message text to display in the input field.
		* 
		* @since 1.0
		*/
		public string default_message { get; set; default = ""; }

		/**
		 * Whether to show the model selection dropdown.
		 * 
		 * If true, the dropdown will be displayed and models will be loaded.
		 * Default is true.
		 * 
		 * @since 1.0
		 */
		public bool show_models { get; set; default = true; }

		/**
	 	* Emitted when a message is sent by the user.
		 * 
		 * @param text The message text that was sent
		 * @since 1.0
		 */
		public signal void message_sent(string text);

		/**
		 * Emitted when a response is received from the assistant.
		 * 
		 * @param text The complete response text
		 * @since 1.0
		 */
		public signal void response_received(string text);

		/**
		 * Emitted when an error occurs during chat operations.
		 * 
		 * @param error The error message
		 * @since 1.0
		 */
		public signal void error_occurred(string error);

		/**
		 * Creates a new ChatWidget instance.
		 * 
		 * @param manager The history manager instance
		 * @since 1.0
		 */
		public ChatWidget(OLLMchat.History.Manager manager)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);

			this.manager = manager;

			// Create paned widget to allow resizing between chat view and input area
			this.paned = new Gtk.Paned(Gtk.Orientation.VERTICAL) {
				hexpand = true,
				vexpand = true
			};

			// Create chat view with reference to this widget
			this.chat_view = new ChatView(this) {
				hexpand = true,
				vexpand = true
			};
			this.paned.set_start_child(this.chat_view);
			// Allow start child to resize when paned resizes (top pane should grow/shrink)
			this.paned.set_resize_start_child(true);
			
			// Connect to manager signals (which relay from active session)
			this.manager.stream_chunk.connect(this.on_stream_chunk_handler);
			this.manager.tool_message.connect(this.chat_view.append_tool_message);

			// Create a box for the bottom pane containing permission widget and input
			var bottom_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = true  // Allow vertical expansion
			};
			// Set minimum size request on the bottom box to enforce minimum height
			// GTK4 Paned respects child widget size requests
			bottom_box.set_size_request(-1, this.min_bottom_size);

			// Create permission widget (hidden by default)
			this.permission_widget = new ChatPermission() {
				vexpand = false
			};
			bottom_box.append(this.permission_widget);

			// Create chat input
			this.chat_input = new ChatInput(this.manager) {
				vexpand = true,
				show_models = this.show_models
			};
			this.chat_input.send_clicked.connect(this.on_send_clicked);
			this.chat_input.stop_clicked.connect(this.on_stop_clicked);
			bottom_box.append(this.chat_input);

			// Set bottom box as end child of paned
			this.paned.set_end_child(bottom_box);
			// Prevent end child from resizing when paned resizes - maintain fixed size
			this.paned.set_resize_end_child(false);
			// Set shrink-end-child to false to prevent shrinking below size request
			// This ensures the bottom pane maintains its minimum height
			this.paned.set_shrink_end_child(false);
			
			// Calculate minimum size based on component minimums:
			// - ScrolledWindow minimum: 60px (from ChatInput scrolled.set_size_request)
			// - Button box: ~50px (button height ~35px + margins 10px top + 5px bottom)
			// - Spacing: 5px (from ChatInput spacing)
			// - Permission widget: 0px (hidden by default)
			// Total: ~115px minimum
			// The minimum size is enforced via set_size_request() on bottom_box
			// and set_shrink_end_child(false) on the paned

			// Add paned to this widget
			this.append(this.paned);

			// Set up model dropdown
			this.chat_input.setup_model_dropdown();

			// Connect to notify signal to propagate default_message when property is set
			// messy but usefull for testing.
			this.notify["default-message"].connect(() => {
				GLib.debug("[ChatWidget] default_message property set to '%s' (length=%d)", this.default_message, this.default_message.length);
				if (this.chat_input != null) {
					this.chat_input.default_message = this.default_message;
				}
			});
		}
		
		/**
		* Switches to a new session, deactivating the current one and activating the new one.
		* 
		* @param session The session to switch to
		* @since 1.0
		*/
		public async void switch_to_session(OLLMchat.History.SessionBase session)
		{
			// Finalize any active streaming (but don't cancel - we might switch back)
			this.chat_view.finalize_assistant_message();
			this.chat_input.set_streaming(false);
			this.is_streaming_active = false;
			this.chat_input.sensitive = false;
			
			// Switch manager to new session (Manager handles deactivation/activation)
			this.manager.switch_to_session(session);
			this.clear_chat();
			
			// Manager signals are already connected in constructor
			// Model dropdown is updated via session_activated signal
			
			// Lock input while loading
			try {
				// Load session data if needed (no-op for already loaded sessions)
				yield this.manager.session.load();
				
				// Render messages from session.messages with filtering for UI display
				// Display special session types: "think-stream", "content-stream", "user-sent", "ui"
				// Handle "end-stream" message: when encountered, flag to ignore the next message if it's a "done" message from streaming
				// Skip certain chat message types: "system" (not displayed in UI), "tool" (already handled), "user" (use "user-sent" instead)
				bool ignore_next_done = false;
				foreach (var msg in this.manager.session.messages) {
					switch (msg.role) {
						case "end-stream":
							// Flag to ignore the next "done" message from streaming
							ignore_next_done = true;
							break;
						case "assistant":
							// Skip messages flagged by "end-stream" (empty assistant messages after streaming)
							if (ignore_next_done && msg.content == "") {
								ignore_next_done = false;
								break;
							}
							ignore_next_done = false;
							this.chat_view.append_complete_assistant_message(msg);
							break;
						case "user-sent":
							ignore_next_done = false;
							this.chat_view.append_user_message(msg.content, msg.message_interface);
							break;
						case "think-stream":
						case "content-stream":
							ignore_next_done = false;
							// Render streaming messages as assistant messages
							var stream_msg = new OLLMchat.Message(msg.message_interface, "assistant", msg.content);
							this.chat_view.append_complete_assistant_message(stream_msg);
							break;
						case "ui":
							ignore_next_done = false;
							// UI messages are already handled via tool_message signal, but we can display them if needed
							// For now, skip them as they're handled by the tool_message signal
							break;
						default:
							ignore_next_done = false;
							// Skip: "system" (not displayed), "tool" (already handled), "user" (use "user-sent" instead)
							break;
					}
				}
				
			} catch (Error e) {
				GLib.warning("Error loading session: %s", e.message);
			}
			
			// Unlock input after loading
			this.chat_input.sensitive = true;
		}

		/**
		 * Sends a message programmatically.
		 * 
		 * @param text The message text to send
		 * @since 1.0
		 */
		public void send_message(string text)
		{
			if (text.strip().length == 0) {
				return;
			}

			this.on_send_clicked(text);
		}

		/**
		 * Clears the chat history.
		 * 
		 * @since 1.0
		 */
		public void clear_chat()
		{
			this.chat_view.clear();
			this.last_sent_text = null;
		}

		/**
		 * Loads a history session into the chat widget.
		 * 
		 * This method switches to the session and loads its data.
		 * 
		 * @param session The session to load
		 * @throws Error if loading fails
		 * @since 1.0
		 */
		public async void load_session(OLLMchat.History.SessionBase session) throws Error
		{
			// load_session() is essentially the same as switch_to_session()
			// Delegate to switch_to_session() which handles all the logic
			yield this.switch_to_session(session);
		}

		/**
		 * Requests permission from the user for a tool operation.
		 * 
		 * @param tool The tool requesting permission
		 * @return The user's permission response
		 * @since 1.0
		 */
		public async OLLMchat.ChatPermission.PermissionResponse request_permission(OLLMchat.Tool.Interface tool)
		{
			return yield this.permission_widget.request(tool.permission_question);
		}

	
		private void on_stream_chunk_handler(string new_text, bool is_thinking, OLLMchat.Response.Chat response)
		{
			// Check if streaming is still active (might have been stopped)
			if (!this.is_streaming_active) {
				return;
			}

			// Process chunk (even if done, there might be final text to process)
			if (new_text.length > 0) {
				this.chat_view.append_assistant_chunk(new_text, response);
			}

			// If response is not done, continue waiting
			if (!response.done) {
				return;
			}

			// Response is done - if we have tool_calls but no content was received, we still need to initialize
			// the assistant message state so statistics can be displayed in finalize_assistant_message
			// (append_assistant_chunk safely handles empty text and won't re-initialize if already initialized)
			if (response.message.tool_calls.size > 0 && response.message.content.length == 0) {
				this.chat_view.append_assistant_chunk("", response);
			}

			// Response is done - finalize the message
			this.chat_view.finalize_assistant_message(response);
			
			// Check if this response has tool_calls - if so, tools will be executed and conversation will continue
			// Don't stop streaming yet if tools are being executed (they will auto-continue)
			if (response.message.tool_calls.size > 0) {
				// Clear waiting indicator so permission widgets can be shown
				this.chat_view.clear_waiting_indicator();
				
				// Tools will be executed and conversation will continue automatically
				// Keep streaming active so we can receive the final response
				// Don't emit response_received signal yet - wait for final response after tool execution
				GLib.debug("ChatWidget: Response has tool_calls, waiting for tool execution and continuation");
				// Don't set streaming to false yet - tools will execute and continue
				// Don't emit response_received - this is not the final response
				return;
			}

			// No tool calls - this is the final response
			this.chat_input.set_streaming(false);
			this.is_streaming_active = false;
			
			// Clear last_sent_text on successful response
			this.last_sent_text = null;
			
			// Emit response received signal only for final responses (no tool_calls)
			this.response_received(response.message.content);
		}

		private void on_send_clicked(string text)
		{
			// Store the text before clearing input (for error recovery)
			this.last_sent_text = text;

			// Create a temporary ChatCall for displaying the user message
			// This is a workaround just so the interface works - the actual ChatCall
			// will be created later in send_message()
			var user_call = new OLLMchat.Call.Chat(this.manager.session.client) {
				chat_content = text
			};
			
			// Display user message
			this.chat_view.append_user_message(text, user_call);
			this.chat_input.clear_input();

			// Emit message sent signal
			this.message_sent(text);

			// Set streaming state
			this.chat_input.set_streaming(true);
			this.is_streaming_active = true;

			// Send chat request asynchronously (EmptySession will convert to Session on first message)
			// The waiting indicator will be shown when send_starting signal is emitted
			this.send_chat_request.begin(text);
		}

		private async void send_chat_request(string text)
		{
			// Check if we're sending the same question twice (backend duplicate check)
			if (this.last_sent_text != null && this.last_sent_text == text) {
				GLib.warning("[ChatWidget] Warning: Attempting to send the same message again: '%s'", 
					text.length > 50 ? text.substring(0, 50) + "..." : text);
			}
			
			// Create cancellable for stop functionality
			var cancellable = new GLib.Cancellable();
			
			try {
				// Use session.send_message() - EmptySession will convert to Session on first message
				// Session.send_message() handles streaming, reply() vs chat(), and cancellable
				yield this.manager.session.send_message(text, cancellable);
				
				// Response is handled by streaming callback
			} catch (GLib.IOError e) {
				// Check if this was a user-initiated cancellation
				if (e.code == GLib.IOError.CANCELLED) {
					// User cancelled - don't show error, just clean up state
					this.cleanup_streaming_state();
					return;
				}
				// Handle other IO errors with specific messages
				string error_msg = "";
				switch (e.code) {
					case GLib.IOError.CONNECTION_REFUSED:
						error_msg = "Connection refused. Please ensure the Ollama server is running at " + this.manager.session.client.url + ".";
						break;
					case GLib.IOError.TIMED_OUT:
						error_msg = "Request timed out. Please check your network connection and try again.";
						break;
					case GLib.IOError.HOST_UNREACHABLE:
						error_msg = "Host unreachable. Please check your network connection and server URL.";
						break;
					case GLib.IOError.NETWORK_UNREACHABLE:
						error_msg = "Network unreachable. Please check your internet connection.";
						break;
					default:
						error_msg = @"Network error: $(e.message)";
						break;
				}
				this.handle_error(error_msg);
			} catch (OLLMchat.OllamaError e) {
				// Provide specific error messages for different error types
				string error_msg = "";
				if (e is OLLMchat.OllamaError.INVALID_ARGUMENT) {
					error_msg = @"Invalid request: $(e.message). Please check your request parameters.";
				} else if (e is OLLMchat.OllamaError.FAILED) {
					error_msg = @"Request failed: $(e.message)";
				} else {
					error_msg = @"Error: $(e.message)";
				}
				this.handle_error(error_msg);
			} catch (GLib.Error e) {
				// Generic error handling
				this.handle_error(@"Unexpected error: $(e.message)");
			}
		}

		private void handle_error(string error_msg)
		{
			// Finalize any ongoing assistant message before showing error
			if (this.is_streaming_active) {
				this.chat_view.finalize_assistant_message();
			}
			
			// Clear any partial response content if streaming was active
			// This ensures we don't show incomplete responses
			// Note: We keep partial response content as it may have content the user wants to see
			
			this.chat_view.append_error(error_msg);
			this.error_occurred(error_msg);
			this.cleanup_streaming_state();
			
			// Auto-fill the input with the last sent text so user can retry easily
			if (this.last_sent_text != null && this.last_sent_text.length > 0) {
				this.chat_input.set_default_text(this.last_sent_text);
			}
			
			// Conversation history is preserved in session.chat
			// User can retry or continue the conversation after the error
		}

		private void cleanup_streaming_state()
		{
			// Reset all streaming-related state
			this.chat_input.set_streaming(false);
			this.is_streaming_active = false;
			// Conversation history is preserved in session.chat
			// Only clear if explicitly requested via clear_chat()
		}

		private void on_stop_clicked()
		{
			// Mark streaming as inactive to prevent callbacks from updating UI
			this.is_streaming_active = false;

			// Cancel the current request via session
			this.manager.session.cancel_current_request();

			// Finalize current message
			this.chat_view.finalize_assistant_message();
			this.chat_input.set_streaming(false);
			
			// Conversation history is preserved in session
			// The user can continue the conversation after stopping
		}


	}
}

