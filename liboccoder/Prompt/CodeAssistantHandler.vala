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

namespace OLLMcoder.Prompt
{
	/**
	 * Handler for CodeAssistant agent requests.
	 * 
	 * Extends the base AgentHandler to handle system message regeneration
	 * on each call (including replies). The system prompt must be regenerated
	 * to include current context (open files, workspace, etc.).
	 */
	public class CodeAssistantHandler : OLLMchat.Prompt.AgentHandler
	{
		/**
		 * Constructor.
		 * 
		 * @param agent The CodeAssistant agent that created this handler
		 * @param client The client instance for this request
		 * @param session The session instance (for accessing Manager and tools)
		 */
		public CodeAssistantHandler(OLLMchat.Prompt.BaseAgent agent, OLLMchat.Client client, OLLMchat.History.SessionBase session)
		{
			base(agent, client, session);
		}
		
		/**
		 * Sends a Message object asynchronously with streaming support.
		 * 
		 * For CodeAssistant, this regenerates the system prompt on each call
		 * to include current context. Overrides base implementation to build
		 * complex system prompt with current context.
		 * 
		 * @param message The message object to send (the user message that was just added to session)
		 * @param cancellable Optional cancellable for canceling the request
		 * @throws Error if the request fails
		 */
		public override async void send_async(OLLMchat.Message message, GLib.Cancellable? cancellable = null) throws GLib.Error
		{
			// Build full message history from this.session
			var messages = new Gee.ArrayList<OLLMchat.Message>();
			
			// Build system prompt at this point in time with current context
			// CodeAssistant regenerates system prompt on each call to include current context
			// Use agent.system_message() to get system prompt with current context
			// This regenerates the system prompt with current context (open files, workspace, etc.)
			// Pass this handler so agent can access session, client, etc.
			string system_content = this.agent.system_message(this);
			if (system_content != "") {
				messages.add(new OLLMchat.Message(this.chat, "system", system_content));
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
			// through the client's stream_chunk signal which is connected to handle_stream_chunk()
			// The final assistant message will be added to session via on_stream_chunk() or similar
		}
		
		/**
		 * Sends a message asynchronously with streaming support.
		 * 
		 * For CodeAssistant, this regenerates the system prompt on each call
		 * to include current context. For replies, it rebuilds conversation history
		 * and updates the system message.
		 * 
		 * @param user_input The user's input text
		 * @param cancellable Optional cancellable for canceling the request
		 * @throws Error if the request fails
		 */
		public override async void send_message_async(string user_input, GLib.Cancellable? cancellable = null) throws GLib.Error
		{
			// Get model from session (Phase 3: model stored on Session, not Client)
			var model = this.session.model;
			if (model == "" && this.client.config != null) {
				model = this.client.config.get_default_model();
			}
			if (model == "") {
				throw new OLLMchat.OllamaError.INVALID_ARGUMENT("Model is required. Set session.model or client.config.");
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
			
			// Generate prompts and set on chat (sets system_content and chat_content)
			// This regenerates the system prompt with current context on each call
			this.agent.fill(call, user_input);
			
			// Create messages for UI/persistence (via message_created signal)
			// System message first (if system_content is set)
			if (call.system_content != "") {
				// message_created signal emission removed - callers handle state directly when creating messages
				var system_msg = new OLLMchat.Message(call, "system", call.system_content);
				this.session.add_message(system_msg);
			}
			
			// User-sent message with original text (preserved before prompt engine modification)
			// message_created signal emission removed - callers handle state directly when creating messages
			var user_sent_msg = new OLLMchat.Message(call, "user-sent", user_input);
			this.session.add_message(user_sent_msg);
			
			// Prepare messages array for API request (required by exec_chat())
			// System message first (if system_content is set)
			// For CodeAssistant, system message is regenerated on each call with current context
			if (call.system_content != "") {
				call.messages.add(new OLLMchat.Message(call, "system", call.system_content));
			}
			
			// Add the user message with chat_content (for API request)
			// Note: "user-sent" message was already created via signal with original text
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

