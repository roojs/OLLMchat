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
		public OLLMchat.History.Session? session { get; private set; default = null; }
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
			this.chat_input = new ChatInput() {
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

			// Connect model dropdown to manager's base client
			this.chat_input.setup_model_dropdown(this.manager.base_client);
			
			// Update model dropdown when session is activated
			// this will enable us to sue sessions with clients from different servers.
			this.manager.session_activated.connect((session) => {
				this.chat_input.setup_model_dropdown(session.client);
			});

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
		public async void switch_to_session(OLLMchat.History.Session session)
		{
			// Finalize any active streaming (but don't cancel - we might switch back)
			this.chat_view.finalize_assistant_message();
			this.chat_input.set_streaming(false);
			this.is_streaming_active = false;
			this.chat_input.sensitive = false;
			// Deactivate old session (Manager disconnects its signals)
			this.session.deactivate();
			this.clear_chat();

			// Switch manager to new session (Manager connects its signals)
			this.manager.switch_to_session(session);
			this.session = session;
			
			// Manager signals are already connected in constructor
			// Model dropdown is updated via session_activated signal
			
			// Lock input while loading
 			
			try {
				// Load session data if needed
				//session read will initalize chat always.
				yield session.read();
				 
				
				  
				// Render all messages from the session
				 
				foreach (var msg in session.chat.messages) {
					if (msg.role == "user") {
						this.chat_view.append_user_message(msg.content, msg.message_interface);
					} else if (msg.role == "assistant") {
						this.chat_view.append_complete_assistant_message(msg);
					}
					// Skip tool messages - they're not displayed
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
		 * This method:
		 * - Cancels any active streaming
		 * - Loads the session's JSON file (if not already loaded)
		 * - Clears the current chat view
		 * - Sets current_chat to the session's chat
		 * - Renders all messages from the session to ChatView
		 * 
		 * @param session The session to load
		 * @throws Error if loading fails
		 * @since 1.0
		 */
		public async void load_session(OLLMchat.History.Session session) throws Error
		{
			// Step 1: Finalize any active streaming (but don't cancel - we might switch back)
			this.chat_view.finalize_assistant_message();
			this.chat_input.set_streaming(false);
			this.is_streaming_active = false;

			// Step 2: Load session JSON file if needed
			yield session.read();

			// Step 3: Clear current chat (clears view)
			// Note: clear_chat() calls chat_view.clear() which resets the renderer
			this.clear_chat();

			// Step 4: Iterate through messages and render
			foreach (var msg in session.chat.messages) {
				if (msg.role == "user") {
					this.chat_view.append_user_message(msg.content, msg.message_interface);
				} else if (msg.role == "assistant") {
					this.chat_view.append_complete_assistant_message(msg);
				}
				// Skip tool messages - they're not displayed
			}
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
			// Trim trailing line breaks from the message
			 

			// Store the text before clearing input (for error recovery)
			this.last_sent_text = text;

			// Ensure we have a session and client
			// KLUDGE: Create a temporary ChatCall for displaying the user message
			// This is a workaround just so the interface works - the actual ChatCall
			// will be created later in client.chat()
			var user_call = new OLLMchat.Call.Chat(this.session.client) {
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

			// Send chat request asynchronously (this will call client.chat())
			// The waiting indicator will be shown when send_starting signal is emitted
			this.send_chat_request.begin(text);
		}

		private async void send_chat_request(string text)
		{
			// Ensure we have a session
			if (this.session == null) {
				// Create a new session if we don't have one
				this.session = this.manager.create_new_session();
				this.manager.switch_to_session(this.session);
				// Manager signals are already connected in constructor
				// Model dropdown is updated via session_activated signal
			}
			
			// Check if we're sending the same question twice (backend duplicate check)
			if (this.last_sent_text != null && this.last_sent_text == text) {
				GLib.warning("[ChatWidget] Warning: Attempting to send the same message again: '%s'", 
					text.length > 50 ? text.substring(0, 50) + "..." : text);
			}
			
			// Set streaming on client
			this.session.client.stream = true;
			
			// Create cancellable for stop functionality
			var cancellable = new GLib.Cancellable();
			
			try {
				OLLMchat.Response.Chat response;
				
				// If we have a previous chat with a response, use reply() instead of chat()
				if (this.session.chat != null && 
					this.session.chat.streaming_response != null && 
					this.session.chat.streaming_response.done &&
					this.session.chat.streaming_response.call != null) {
					// Use reply to continue the conversation
					this.session.chat.cancellable = cancellable;
					response = yield this.session.chat.streaming_response.reply(text);
					return;
				}
				// First message or no previous response - use regular chat()
				response = yield this.session.client.chat(text, cancellable);
				
				// Get the call from the response and set cancellable
				if (response.call != null && response.call is OLLMchat.Call.Chat) {
					var chat = (OLLMchat.Call.Chat) response.call;
					chat.cancellable = cancellable;
				}
				
				
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
						error_msg = "Connection refused. Please ensure the Ollama server is running at " + this.session.client.url + ".";
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

			// Cancel the call's cancellable
			if (this.session.chat != null && this.session.chat.cancellable != null) {
				this.session.chat.cancellable.cancel();
			}

			// Finalize current message
			this.chat_view.finalize_assistant_message();
			this.chat_input.set_streaming(false);
			
			// Conversation history is preserved in session.chat
			// The user can continue the conversation after stopping
		}


	}
}

