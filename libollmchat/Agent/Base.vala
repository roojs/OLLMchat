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
 * Lesser General Public License along with this library; if not, write to the
 * Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA  02110-1301  USA
 */

namespace OLLMchat.Agent
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
	public class Base : Object, Interface
	{
		/**
		 * The factory that created this agent.
		 * 
		 * Protected so subclasses can access it.
		 */
		protected Factory factory;
		
		/**
		 * Connection for this request (obtained from manager.base_client).
		 * 
		 * Protected so subclasses can access it.
		 */
		protected OLLMchat.Settings.Connection connection;
		
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
		protected OLLMchat.Call.Chat chat_call;
		
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
		public signal void chat_send(OLLMchat.Call.Chat chat_call);
		
		/**
		 * Signal emitted when streaming starts.
		 */
		public signal void stream_start();
		
		/**
		 * Signal emitted when a message is completed.
		 * Used by tools to know when message is done and they can process/finalize.
		 */
		public signal void message_completed(OLLMchat.Response.Chat response);
		
		/**
		 * Registry of active tool requests for monitoring streaming chunks.
		 * Keyed by request_id (auto-generated int).
		 */
		private Gee.HashMap<int, OLLMchat.Tool.RequestBase> active_tools { 
			get; set; default = new Gee.HashMap<int, OLLMchat.Tool.RequestBase>(); }
		
		/**
		 * Constructor.
		 * 
		 * @param factory The factory that created this agent
		 * @param session The session instance (for accessing Manager and tools)
		 */
		public Base(Factory factory, History.SessionBase session)
		{
			this.factory = factory;
			this.session = session;
			
		// Get model and options from session.model_usage
			var usage = this.session.model_usage;
			
			// Get connection from model_usage
			if (usage.connection != "" &&
					this.session.manager.config.connections.has_key(usage.connection)) {
				this.connection = this.session.manager.config.connections.get(usage.connection);
			}
		
			// Determine if model supports thinking
			bool supports_thinking = false;
			if (usage.model_obj != null) {
				supports_thinking = usage.model_obj.is_thinking;
			}
			 
			// Create Chat instance in constructor - reused for all requests
			// Can be updated if model, options, or other properties change
			this.chat_call = new OLLMchat.Call.Chat(this.connection, usage.model) {
				stream = true,
				think = supports_thinking,  // Based on model capabilities
				options = usage.options,  // No cloning - Chat just references the Options object
				agent = this  // Set agent reference so tools can access session
			};
			
			// Only add tools when the model supports tool calling (verified here, not at request time)
			if (usage.model_obj == null || !usage.model_obj.can_call) {
				return;
			}
			foreach (var tool in this.session.manager.tools.values) {
				this.chat_call.add_tool(tool);
			}
			this.factory.configure_tools(this.chat_call);
			
			// Signal connections removed - agent usage now uses direct method calls from Chat
		}
		
		/**
		 * Destructor - signal disconnections removed (no longer connecting to client signals).
		 */
		~Base()
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
			// Emit signal for active tool requests (they're connected via register_tool_monitoring)
			// This allows tools like EditMode to receive streaming chunks in real-time
			// Use existing stream_chunk signal (already defined in Agent.Base)
			this.stream_chunk(new_text, is_thinking, response);
			
			// If response is done, emit message_completed signal for active tool requests
			// This allows tools to know when the message is complete and they can process/finalize
			if (response.done && response.message != null) {
				GLib.debug("Agent.handle_stream_chunk: Emitting message_completed signal (response.done=%s, message.role=%s, message.is_done=%s, active_tools.size=%zu)", 
					response.done.to_string(), response.message.role, response.message.is_done.to_string(), this.active_tools.size);
				this.message_completed(response);
			}
			
			// Relay to session (existing code - for persistence and UI updates)
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
		 * Executes all tool calls and returns tool reply messages.
		 * 
		 * Called by Chat when tool calls are detected. Agent handler manages
		 * tool execution flow including:
		 * - Iterating through all tool calls
		 * - Tool lookup and validation
		 * - UI messages (execution start, errors)
		 * - Tool execution
		 * - Creating tool reply messages
		 * - Error handling (creates tool_call_fail message on error, continues with next tool)
		 * 
		 * @param tool_calls The list of tool calls to execute
		 * @return Array of tool reply messages (tool_reply or tool_call_fail messages)
		 */
		public virtual async Gee.ArrayList<Message> execute_tools(Gee.ArrayList<Response.ToolCall> tool_calls)
		{
			var reply_messages = new Gee.ArrayList<Message>();
			
			foreach (var tool_call in tool_calls) {
				GLib.debug("Executing tool '%s' (id='%s')",
					tool_call.function.name, tool_call.id);
				
				// Get tool from chat_call.tools (tools defaults to empty HashMap, never null)
				if (!this.chat_call.tools.has_key(tool_call.function.name)) {
					var available_tools_str = "";
					if (this.chat_call.tools.size > 0) {
						available_tools_str = "'" + string.joinv("', '", this.chat_call.tools.keys.to_array()) + "'";
					}
					
					var err_message = "ERROR: You requested a tool called '" + tool_call.function.name + 
						" ', however we only have these tools: " + available_tools_str;
					
					var error_msg = new Message("ui", err_message);
					this.handle_tool_message(error_msg);
					reply_messages.add(new Message.tool_call_invalid(tool_call, err_message));
					continue; // Continue to next tool call
				}
				
				var tool = this.chat_call.tools.get(tool_call.function.name);
				
				// Show message that tool is being executed
				var exec_msg = new Message("ui", "Executing tool: `" + tool_call.function.name + "`");
				this.handle_tool_message(exec_msg);
				
				try {
					// Execute the tool - tool.execute() will set request.agent = chat_call.agent
					var result = yield tool.execute(this.chat_call, tool_call);
					
					// Log result summary (truncate if too long)
					var result_summary = result.length > 100 ? result.substring(0, 100) + "..." : result;
					
					// Check if result is an error and display it in UI
					if (result.has_prefix("ERROR:")) {
						GLib.debug("Tool '%s' returned error result: %s",
							tool_call.function.name, result);
						var error_msg = new Message("ui", result);
						this.handle_tool_message(error_msg);
					} else {
						GLib.debug("Tool '%s' executed successfully, result length: %zu, preview: %s",
							tool_call.function.name, result.length, result_summary);
					}
					
					// Create tool reply message
					var tool_reply = new Message.tool_reply(
						tool_call.id, 
						tool_call.function.name,
						result
					);
					GLib.debug("Created tool reply message: role='%s', tool_call_id='%s', name='%s', content length=%zu",
						tool_reply.role, tool_reply.tool_call_id, tool_reply.name, tool_reply.content.length);
					reply_messages.add(tool_reply);
				} catch (Error e) {
					GLib.debug("Error executing tool '%s' (id='%s'): %s", 
						tool_call.function.name, tool_call.id, e.message);
					var error_msg = new Message("ui", "Error executing tool '" + tool_call.function.name + "': " + e.message);
					this.handle_tool_message(error_msg);
					reply_messages.add(new Message.tool_call_fail(tool_call, e));
					continue; // Continue to next tool call
				}
			}
			
			// Set is_running = true when tool replies will continue the conversation
			// This ensures the session appears as "running" when tool replies are sent
			this.session.is_running = true;
			GLib.debug("Agent.execute_tools: Setting is_running=true for session %s (tool replies will continue conversation)", this.session.fid);
			
			return reply_messages;
		}
		
		/**
		 * Rebuilds tools for this agent's Chat instance.
		 * 
		 * Called when tool configuration changes. Clears existing tools from Chat
		 * and re-adds them from Manager, allowing agent to reconfigure/filter.
		 * 
		 * This ensures Chat always has the latest tool configuration.
		 */
		public void rebuild_tools()
		{
			var usage = this.session.model_usage;
			if (usage.model_obj == null || !usage.model_obj.can_call) {
				this.chat_call.tools.clear();
				return;
			}
			this.chat_call.tools = this.session.manager.tools;
			this.factory.configure_tools(this.chat_call);
		}
		
		/**
		 * Set chat_call.model from session; customize if model_obj is set. On customize failure,
		 * add ui-warning message and use default model. Override in subclasses (e.g. Skill Runner).
		 */
		protected virtual async void fill_model()
		{
			if (this.session.model_usage.model_obj == null) {
				this.chat_call.model = this.session.model_usage.model;
				return;
			}
			try {
				var customized_model_name = yield this.session.model_usage.model_obj.customize(
					this.connection,
					this.chat_call.options
				);
				this.chat_call.model = customized_model_name;
			} catch (Error e) {
				this.session.add_message(new Message("ui-warning",
					"You selected this model, however we were unable to use it. Using the default model instead."));
				this.chat_call.model = this.session.model_usage.model;
			}
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
			
			// base donest add systme messages - it's just a generic wrapper
			// system message are added by real agents.
			
			// Add the current "user" message to session.messages (after processing)
			// This ensures the "user" message is in session.messages for API filtering
			this.session.messages.add(message);
			
			// Filter and add messages from this.session.messages (full conversation history)
			// Filter to get API-compatible messages (system, user, assistant, tool)
			// Exclude non-API message types (user-sent, ui, etc.)
			foreach (var msg in this.session.messages) {
				// Filter: only include API-compatible message roles
				if (msg.role == "user" 
					|| msg.role == "assistant" || msg.role == "tool") {
					messages.add(msg);
				}
				// Skip: "user-sent", "ui", "think-stream", "content-stream", "end-stream", "done", etc.
				// (these are for UI/persistence only)
			}
			
			// Set is_running = true when sending (for both initial sends and tool continuation replies)
			// This ensures the session appears as "running" when tool replies continue the conversation
			this.session.is_running = true;
			GLib.debug("is_running=true session %s", this.session.fid);
			
			yield this.fill_model();
			
			// Update cancellable for this request
			this.chat_call.cancellable = cancellable;
			
			// Send full message array using new send() method
			var response = yield this.chat_call.send(messages, cancellable);
			
			// Process response and add assistant messages to session via session.send()
			// This is handled via streaming callbacks/handlers - the response will be processed
			// through Chat's direct method calls to agent.handle_stream_chunk() which relays to
			// session.handle_stream_chunk() for persistence and UI updates
		}
		
		// Implement Agent.Interface
		/**
		 * Get the chat instance for this agent.
		 * 
		 * @return The chat instance
		 */
		public Call.Chat chat()
		{
			return this.chat_call;
		}
		
		/**
		 * Get the permission provider for tool execution.
		 * 
		 * @return The permission provider instance
		 */
		public ChatPermission.Provider get_permission_provider()
		{
			return this.session.manager.permission_provider;
		}
		
		/**
		 * Get the configuration instance for tool execution.
		 * 
		 * @return The config instance from session.manager.config
		 */
		public Settings.Config2 config()
		{
			return this.session.manager.config;
		}
		
		/**
		 * Add a UI message to the conversation.
		 * 
		 * @param message The message to add
		 */
		public void add_message(Message message)
		{
			this.session.add_message(message);
		}
		
		/**
		 * Replace the chat instance with a new one.
		 * 
		 * Used by session code to update the chat when switching agents.
		 * 
		 * @param new_chat The new chat instance to use
		 */
		public void replace_chat(Call.Chat new_chat)
		{
			this.chat_call = new_chat;
		}
		
		/**
		 * Register a tool request for monitoring streaming chunks and message completion.
		 * 
		 * Connects the request's callback methods to agent signals so it can receive
		 * streaming chunks in real-time and be notified when messages complete.
		 * 
		 * @param request_id The unique identifier for this request (auto-generated int)
		 * @param request The request object to register
		 */
		public void register_tool_monitoring(int request_id, OLLMchat.Tool.RequestBase request)
		{
			// Store tool reference to prevent garbage collection
			this.active_tools.set(request_id, request);
			
			// Connect tool to agent signals
			request.agent = this;  // Ensure agent reference is set
			this.stream_chunk.connect(request.on_stream_chunk);  // Use existing stream_chunk signal
			this.message_completed.connect(request.on_message_completed);
			// Note: message_failed not needed - errors propagate as exceptions
			
			GLib.debug("Agent.register_tool_monitoring: Registered request '%d' for monitoring", request_id);
		}
		
		/**
		 * Unregister a tool request from monitoring.
		 * 
		 * Disconnects the request's callback methods from agent signals and removes
		 * it from the registry.
		 * 
		 * @param request_id The unique identifier for this request (auto-generated int)
		 */
		public void unregister_tool(int request_id)
		{
			if (!this.active_tools.has_key(request_id)) {
				return;
			}
			var request = this.active_tools.get(request_id);
			
			// Disconnect signals
			this.stream_chunk.disconnect(request.on_stream_chunk);  // Use existing stream_chunk signal
			this.message_completed.disconnect(request.on_message_completed);
			// Note: message_failed not needed - errors propagate as exceptions
			
			// Remove from registry
			this.active_tools.unset(request_id);
			// Note: Do not clear request.agent - the request may still need it after unregistering
			
			GLib.debug("Agent.unregister_tool: Unregistered request '%d'", request_id);
		}
		
	}
}

