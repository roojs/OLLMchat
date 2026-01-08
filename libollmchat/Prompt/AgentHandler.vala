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
		 * Chat instance created in constructor and reused for all requests.
		 * Can be updated if model, options, or other properties change.
		 */
		public OLLMchat.Call.Chat chat;
		
		// Signal handler IDs removed - agent usage now uses direct method calls
		
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
			
			// Get model and options from session.model_usage
			// Create a default ModelUsage if not set (shouldn't happen in normal flow)
			var mu = this.session.model_usage != null ? this.session.model_usage : 
				new Settings.ModelUsage();
			
			// Use ModelUsage from session (already has options overlaid from config)
			var model = mu.model;
			var options = mu.options.clone();
			// Get connection from manager
			var connection = this.session.manager.config.connections.get(mu.connection);
			  
			 
			// Create Chat instance in constructor - reused for all requests
			// Can be updated if model, options, or other properties change
			this.chat = new OLLMchat.Call.Chat(connection, model) {
				stream = true,
				think = true,
				options = options,
				agent = this  // Set agent reference so tools can access session
			};
			
			// Configure tools for this chat (Phase 3: tools stored on Manager, accessed via Session)
			// Copy tools from Manager to Chat
			foreach (var tool in this.session.manager.tools.values) {
				this.chat.add_tool(tool);
			}
			// Agent can also configure/filter tools if needed
			this.agent.configure_tools(this.chat);
			
			// Signal connections removed - agent usage now uses direct method calls from Chat
		}
		
		/**
		 * Destructor - signal disconnections removed (no longer connecting to client signals).
		 */
		~AgentHandler()
		{
			// Signal disconnections removed - agent usage now uses direct method calls from Chat
		}
		
		/**
		 * Called by Chat when streaming starts.
		 * Agent handler should relay to Session.
		 */
		public virtual void handle_stream_started()
		{
			// Relay to session (agent is always connected to session)
			this.session.handle_stream_started();
		}
		
		/**
		 * Called by Chat when a streaming chunk is received.
		 * Agent handler should relay to Session.
		 */
		public virtual void handle_stream_chunk(string new_text, bool is_thinking, Response.Chat response)
		{
			// Relay to session (agent is always connected to session)
			this.session.handle_stream_chunk(new_text, is_thinking, response);
		}
		
		/**
		 * Called by Chat when a tool sends a status message.
		 * Agent handler should relay to Session.
		 */
		public virtual void handle_tool_message(Message message)
		{
			// Relay to session (agent is always connected to session)
			this.session.handle_tool_message(message);
		}
		
		/**
		 * Sends a Message object asynchronously with streaming support.
		 * 
		 * This is the new method for sending messages. Builds full message history from
		 * session.messages, filters to get API-compatible messages, and sends to Chat.
		 * 
		 * @param message The message object to send (the user message that was just added to session)
		 * @param cancellable Optional cancellable for canceling the request
		 * @throws Error if the request fails
		 */
		public virtual async void send_async(Message message, GLib.Cancellable? cancellable = null) throws GLib.Error
		{
			// Build full message history from this.session
			var messages = new Gee.ArrayList<Message>();
			
			// Build system prompt at this point in time (simple implementation in base, CodeAssistantHandler overrides)
			// BaseAgent.generate_system_prompt() returns empty string by default, so this does nothing for basic agents
			string system_content = this.agent.generate_system_prompt();
			if (system_content != "") {
				messages.add(new Message(this.chat, "system", system_content));
			}
			
			// Filter and add messages from this.session.messages (full conversation history)
			// Filter to get API-compatible messages (system, user, assistant, tool)
			// Exclude non-API message types (user-sent, ui, etc.)
			foreach (var msg in this.session.messages) {
				// Filter: only include API-compatible message roles
				if (msg.role == "system" || msg.role == "user" 
					|| msg.role == "assistant" || msg.role == "tool") {
					messages.add(msg);
				}
				// Skip: "user-sent", "ui", "think-stream", "content-stream", "end-stream", "done", etc.
				// (these are for UI/persistence only)
			}
			
			// Model and options should not be set here - this is too late in the flow and breaks the chain.
			// They should be set when the chat is created in the constructor or when session properties change,
			// not at the last step before sending a message. See 1.2.7 cleanup plan for decision on where
			// model/options get set properly.
			
			// Update cancellable for this request
			this.chat.cancellable = cancellable;
			
			// Send full message array using new send() method
			var response = yield this.chat.send(messages, cancellable);
			
			// Process response and add assistant messages to session via session.send()
			// This is handled via streaming callbacks/handlers - the response will be processed
			// through Chat's direct method calls to agent.handle_stream_chunk() which relays to
			// session.handle_stream_chunk() for persistence and UI updates
		}
		
	}
}

