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
 * Lesser General Public License along with this library; if not, write to the
 * Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA  02110-1301  USA
 */

namespace OLLMchat.Prompt
{
	/**
	 * Base handler for agent requests.
	 * 
	 * Created per message/request and manages the lifecycle of a single request.
	 * Wraps the client and handles signal relaying for that specific request.
	 * 
	 * This is the default handler for simple agents (like JustAsk) that don't need
	 * special system message handling. For agents that need system message regeneration
	 * (like CodeAssistant), use a specialized handler.
	 */
	public class AgentHandler : Object
	{
		/**
		 * The agent that created this handler.
		 * 
		 * Protected so subclasses can access it.
		 */
		protected BaseAgent agent;
		
		/**
		 * The client instance for this request.
		 * 
		 * Protected so subclasses can access it.
		 */
		protected OLLMchat.Client client;
		
		/**
		 * Reference to Session for accessing Manager and tools (Phase 3: tools stored on Manager).
		 * 
		 * Protected so subclasses can access it.
		 */
		public History.SessionBase session;
		
		/**
		 * Signal handler IDs for client signals.
		 */
		private ulong stream_chunk_id = 0;
		// stream_content_id removed - replaced with stream_chunk + is_thinking check
		private ulong stream_start_id = 0;
		// chat_send_id removed - callers handle state directly after calling send()
		
		/**
		 * Signal emitted when a streaming chunk is received.
		 */
		public signal void stream_chunk(string new_text, bool is_thinking, OLLMchat.Response.Chat response);
		
		/**
		 * Signal emitted when streaming content (not thinking) is received.
		 */
		public signal void stream_content(string new_text, OLLMchat.Response.Chat response);
		
		/**
		 * Signal emitted when a chat request is sent to the server.
		 */
		public signal void chat_send(OLLMchat.Call.Chat chat);
		
		/**
		 * Signal emitted when streaming starts.
		 */
		public signal void stream_start();
		
		/**
		 * Constructor.
		 * 
		 * @param agent The agent that created this handler
		 * @param client The client instance for this request
		 * @param session The session instance (for accessing Manager and tools)
		 */
		public AgentHandler(BaseAgent agent, OLLMchat.Client client, History.SessionBase session)
		{
			this.agent = agent;
			this.client = client;
			this.session = session;
			
			// Set up signal connections from client to handler
			this.stream_chunk_id = this.client.stream_chunk.connect((new_text, is_thinking, response) => {
				this.handle_stream_chunk(new_text, is_thinking, response);
				// Relay stream_content for non-thinking chunks (replaces stream_content signal)
				if (!is_thinking) {
					this.stream_content(new_text, response);
				}
			});
			
			// stream_content connection removed - replaced with stream_chunk + is_thinking check above
			
			this.stream_start_id = this.client.stream_start.connect(() => {
				this.stream_start();
			});
			
			// chat_send connection removed - callers handle state directly after calling send()
		}
		
		/**
		 * Destructor - automatically disconnects all client signal connections.
		 */
		~AgentHandler()
		{
			this.client.disconnect(this.stream_chunk_id);
			// stream_content_id removed - no longer connecting to this signal
			this.client.disconnect(this.stream_start_id);
			// chat_send_id removed - no longer connecting to this signal
		}
		
		/**
		 * Handles a streaming chunk from the client and relays it via signal.
		 * 
		 * Made protected so subclasses can access it.
		 */
		protected void handle_stream_chunk(string chunk, bool is_thinking, OLLMchat.Response.Chat response)
		{
			this.stream_chunk(chunk, is_thinking, response);
		}
		
		/**
		 * Sends a message asynchronously with streaming support.
		 * 
		 * Base implementation for simple agents that don't need system message handling.
		 * For agents that need system message regeneration (like CodeAssistant),
		 * override this method in a specialized handler.
		 * 
		 * @param user_input The user's input text
		 * @param cancellable Optional cancellable for canceling the request
		 * @throws Error if the request fails
		 */
		public virtual async void send_message_async(string user_input, GLib.Cancellable? cancellable = null) throws GLib.Error
		{
			// Get model from session (Phase 3: model stored on Session, not Client)
			var model = this.session.model;
			if (model == "" && this.client.config != null) {
				model = this.client.config.get_default_model();
			}
			if (model == "") {
				throw new OllamaError.INVALID_ARGUMENT("Model is required. Set session.model or client.config.");
			}
			
			// Create and prepare Chat object with real properties (Phase 3: use defaults, no Client properties)
			var call = new OLLMchat.Call.Chat(this.client.connection, model) {
				cancellable = cancellable,
				stream = true,  // Default to streaming
				think = true,    // Default to thinking
				// format and keep_alive default to null
				agent = this     // Set agent reference so tools can access session
			};
			
			// Configure tools for this chat (Phase 3: tools stored on Manager, accessed via Session)
			// Copy tools from Manager to Chat
			foreach (var tool in this.session.manager.tools.values) {
				call.add_tool(tool);
			}
			// Agent can also configure/filter tools if needed
			this.agent.configure_tools(call);
			
			// Generate prompts and set on chat (sets chat_content, may set system_content)
			this.agent.fill(call, user_input);
			
			// User-sent message with original text (preserved before prompt engine modification)
			// message_created signal emission removed - callers handle state directly when creating messages
			var user_sent_msg = new OLLMchat.Message(call, "user-sent", user_input);
			
			// Prepare messages array for API request (required by exec_chat())
			// Base handler does NOT add system messages - specialized handlers can override
			// Add the user message with chat_content (for API request)
			call.messages.add(new OLLMchat.Message(call, "user", call.chat_content));
			
			// Execute chat
			// Signals are already connected and will relay automatically
			var response = yield call.exec_chat();
			
			// Handle final reply - emit stream_chunk with empty chunk and done response
			// This allows UI to know the response is complete
			if (call.stream) {
				this.handle_stream_chunk("", false, response);
			}
		}
	}
}

