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

namespace OLLMchat.Call
{
	/**
	 * Chat API call implementation for sending messages and receiving responses.
	 *
	 * Handles chat conversations with the LLM, including message history, tool calling,
	 * streaming responses, and automatic tool execution. Manages the conversation
	 * flow and tool call recursion. Automatically executes tools when the model
	 * requests them and continues the conversation with tool results.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var call = new Call.Chat(client, "llama3.2");
	 * call.messages.add(new Message("user", "Hello!"));
	 *
	 * // Execute chat (handles tool calls automatically)
	 * var response = yield call.send(call.messages);
	 *
	 * // Access response content
	 * print(response.message.content);
	 * }}}
	 */
	public class Chat : Base, ChatContentInterface
	{
		public string model { get; set; }
		
		// Real properties (Phase 3: fallback logic removed)
		public bool stream { get; set; default = false; }
		
		public string? format { get; set; }
		
		/**
		 * JSON schema object for structured outputs.
		 * When set, this will be serialized as the "format" field instead of the string format property.
		 * Used for Ollama's structured output feature.
		 */
		public Json.Object? format_obj { get; set; default = null; }
		
		public Call.Options options { get; set; }
		
		public bool think { get; set; default = false; }
		
		public string? keep_alive { get; set; }
		
		public Gee.HashMap<string, Tool.BaseTool>? tools { get; set; default = new Gee.HashMap<string, Tool.BaseTool>(); }
		
		/**
		 * Current streaming response object (internal use).
		 *
		 * Used internally to track the streaming state during chat operations.
		 * Also accessed by OLLMchatGtk for UI updates. Set to null when not streaming.
		 */
		public Response.Chat? streaming_response { get; set; default = null; }
		
		/**
		 * Reference to the agent handler that created this chat.
		 *
		 * Allows tools to access the session via chat_call.agent.session.
		 * Set by AgentHandler when creating Chat in send_message_async().
		 *
		 * @since 1.2.2
		 */
		public Agent.Base? agent { get; set; }

		public Gee.ArrayList<Message> messages { get; set; default = new Gee.ArrayList<Message>(); }
		
		/**
		 * Emitted when a streaming chunk is received from the chat API.
		 *
		 * @param new_text The new text chunk received
		 * @param is_thinking Whether this chunk is thinking content (true) or regular content (false)
		 * @param response The Response object containing the streaming state
		 * @since 1.0
		 */
		public signal void stream_chunk(string new_text, bool is_thinking, Response.Chat response);

		/**
		 * Emitted when the streaming response starts (first chunk received).
		 * This signal is emitted when the first chunk of the response is processed,
		 * indicating that the server has started sending data back.
		 *
		 * @since 1.0
		 */
		public signal void stream_start();

		/**
		 * Emitted when a tool sends a status message during execution.
		 *
		 * @param message The Message object from the tool (typically "ui" role)
		 * @since 1.0
		 */
		public signal void tool_message(Message message);
		
		/**
		 * Emitted when a tool call is detected and needs to be executed.
		 * 
		 * For non-agent usage: Connect to this signal to handle tool execution.
		 * 
		 * The handler is responsible for:
		 * 1. Execute the tool: Get the tool from `chat.tools.get(tool_call.function.name)` and call `tool.execute(chat, tool_call)`
		 * 2. Create tool reply message: `new Message.tool_reply(tool_call.id, tool_call.function.name, result)`
		 * 3. Append it to return_messages: `return_messages.add(tool_reply)`
		 * 
		 * Chat will collect all tool reply messages and send them automatically.
		 * 
		 * For agent usage: This signal is not used - agent.execute_tools() is called directly by Chat.toolsReply().
		 * 
		 * @param tool_call The tool call that needs to be executed
		 * @param return_messages Array to append tool reply messages to
		 */
		public signal void tool_call_requested(Response.ToolCall tool_call, Gee.ArrayList<Message> return_messages);
		
		/**
		 * Creates a new Chat instance for sending messages to the chat API.
		 * 
		 * The constructor initializes basic properties. Most properties should be
		 * set after construction, including options, stream, think, tools, and agent.
		 * 
		 * == Example ==
		 * 
		 * {{{
		 * // Create connection
		 * var connection = new Settings.Connection() {
		 *     name = "Local Ollama",
		 *     url = "http://127.0.0.1:11434/api"
		 * };
		 * 
		 * // Create chat with properties set via object initializer
		 * var chat = new Call.Chat(connection, "llama3.2") {
		 *     stream = true,
		 *     think = true,
		 *     agent = agent_handler
		 * };
		 * 
		 * // Create and assign Options object
		 * chat.options = new Call.Options() {
		 *     temperature = 0.7,
		 *     top_p = 0.9
		 * };
		 * 
		 * // Or assign existing Options object
		 * chat.options = existing_options;
		 * 
		 * // Add tools
		 * foreach (var tool in manager.tools.values) {
		 *     chat.add_tool(tool);
		 * }
		 * 
		 * // Send messages
		 * var response = yield chat.send(messages);
		 * }}}
		 * 
		 * @param connection The connection settings for the API endpoint
		 * @param model The model name to use for chat
		 * @throws OllmError.INVALID_ARGUMENT if model is empty
		 */
		public Chat(Settings.Connection connection, string model)
		{
			base(connection);
			if (model == "") {
				throw new OllmError.INVALID_ARGUMENT("Model is required");
			}
			this.url_endpoint = "chat";
			this.http_method = "POST";
			this.model = model;
			// FID is owned by Session, not Chat (Chat is created per request by AgentHandler)
			
			// Always initialize with empty options - callers should set options after construction
			this.options = new Call.Options();
		}
	
		
		/**
		 * Adds a tool to this chat's tools map.
		 *
		 * Adds the tool to the tools hashmap keyed by tool name. The tool's client is set via constructor.
		 * This method allows callers to add tools directly to Chat (not Client).
		 *
		 * @param tool The tool to add
		 */
		public void add_tool(Tool.BaseTool tool)
		{
			// Initialize tools HashMap if not already set
			if (this.tools == null) {
				this.tools = new Gee.HashMap<string, Tool.BaseTool>();
			}
			// Ensure tools HashMap is initialized
			// Note: tool.client is no longer set (tools use connection directly)
			this.tools.set(tool.name, tool);
		}
		// this is only called by response - not by the user
		  
		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "chat-content":
				case "message":
				case "streaming-response":
					// Exclude these properties from serialization
					return null;
				
				case "think":
					// Only serialize think if true, otherwise exclude
					if (!this.think) {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				
				case "tools":
					// Only serialize tools if tools exist
					if (this.tools.size == 0) {
						return null;
					}
					
					// Check if model supports tools
					// First try via agent.session.manager.connection_models (if agent is set)
					// Otherwise check directly from connection.models
					if (this.agent != null) {
						var model_usage = this.agent.session.manager.connection_models.find_model(
							this.connection.url, 
							this.model
						);
						
						if (model_usage != null && !model_usage.model_obj.can_call) {
							return null;
						}
					} 
					if (this.connection.models.has_key(this.model)) {
						// Check directly from connection.models if agent is not set
						var model_obj = this.connection.models.get(this.model);
						if (model_obj != null && !model_obj.can_call) {
							return null;
						}
					}
					
					var tools_node = new Json.Node(Json.NodeType.ARRAY);
					tools_node.init_array(new Json.Array());
					var tools_array = tools_node.get_array();
					foreach (var tool in this.tools.values) {
						// Only include active tools
						if (!tool.active) {
							continue;
						}
						var tool_node = Json.gobject_serialize(tool);
						var tool_obj = tool_node.get_object();
						// Add "type" field for Ollama API compatibility (tool-type is excluded from serialization)
						tool_obj.set_string_member("type", tool.tool_type);
						tools_array.add_element(tool_node);
					}
					return tools_node;
				
				case "format":
					// If format_obj is set, serialize it instead of the string format
					if (this.format_obj != null) {
						var format_node = new Json.Node(Json.NodeType.OBJECT);
						format_node.init_object(this.format_obj);
						return format_node;
					}
					// Otherwise, serialize the string format if it's set
					if (this.format == null || this.format == "") {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				
				case "options":
					// Only serialize options if they have valid values
					if (!this.options.has_values()) {
						return null;
					}
					// Serialize options and convert hyphen keys to underscores for Ollama API
					var options_node = Json.gobject_serialize(this.options);
					var obj = options_node.get_object();
					// Create a new object with renamed keys (hyphens to underscores)
					var new_obj = new Json.Object();
					obj.foreach_member((o, key, node) => {
						var new_key = key.contains("-") ? key.replace("-", "_") : key;
						new_obj.set_member(new_key, node);
					});
					var new_node = new Json.Node(Json.NodeType.OBJECT);
					new_node.set_object(new_obj);
					return new_node;
				
				case "messages":
					// Serialize the message array built in send()
					var node = new Json.Node(Json.NodeType.ARRAY);
					node.init_array(new Json.Array());
					var array = node.get_array();
					foreach (var m in this.messages) {
						var msg_node = Json.gobject_serialize(m);
						array.add_element(msg_node);
					}
					return node;
				
				default:
					return default_serialize_property(property_name, value, pspec);
			}
		}

		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			if (property_name != "messages") {
				return default_deserialize_property(property_name, out value, pspec, property_node);
			}
			
			var messages = new Gee.ArrayList<Message>();
			
			var array = property_node.get_array();
			for (int i = 0; i < array.get_length(); i++) {
				var element_node = array.get_element(i);
				var msg_obj = Json.gobject_deserialize(typeof(Message), element_node) as Message;
				
				messages.add(msg_obj);
			}
			
			value = Value(typeof(Gee.ArrayList));
			value.set_object(messages);
			return true;
		}
 
		/**
		 * Executes tool calls from a response and continues the conversation automatically.
		 *
		 * This method:
		 * 1. Adds the assistant message with tool_calls to the conversation
		 * 2. Executes all tool calls from the response
		 * 3. Adds tool result messages to the conversation
		 * 4. Continues the conversation automatically until a final response is received
		 *
		 * @param response The Response containing tool calls
		 * @return The final Response after tool execution and auto-reply
		 */
		public async Response.Chat toolsReply(Response.Chat response) throws Error
		{
			GLib.debug("Chat.toolsReply: Processing %d tool call(s)", response.message.tool_calls.size);
			
			// Only process tool calls if response is done and has tool_calls
			// Tool calls can be present even when content is also present
			if (!response.done || response.message.tool_calls.size == 0) {
				GLib.debug("Chat.toolsReply: Reply end - done=%s, tool_calls.size=%d, content.length=%zu", 
					response.done.to_string(), 
					response.message.tool_calls.size, 
					response.message.content.length);
				return response;
			}
			
			GLib.debug("Chat.toolsReply: Sending tool responses to LLM: %s", response.message.content);
			
			if (this.agent != null) {
				// Agent usage (normal flow): delegate to agent handler (agent executes tools and returns messages)
				var tool_reply_messages = yield this.agent.execute_tools(response.message.tool_calls);
				
				// Build messages array: assistant message with tool_calls + tool reply messages
				var messages_to_send = new Gee.ArrayList<Message>();
				messages_to_send.add(response.message); // Assistant message with tool_calls
				foreach (var reply_msg in tool_reply_messages) {
					messages_to_send.add(reply_msg); // Tool reply messages
				}
				
				// Append all messages and send
				var next_response = yield this.send_append(messages_to_send);
				
				// Recursively handle tool calls if the next response also has them and is done
				if (next_response.done && 
					next_response.message.tool_calls.size > 0) {
					return yield this.toolsReply(next_response);
				}
				
				return next_response;
			}
			
			// Non-agent usage (external code using Chat directly): emit signal for each tool call
			// Signal handler is responsible for executing tools and appending tool reply messages
			// Our code always has agent set, so this path is only for external users
			
			// Build messages array: assistant message + tool replies (handler will append tool replies)
			var messages_to_send = new Gee.ArrayList<Message>();
			messages_to_send.add(response.message); // Assistant message with tool_calls
			
			// Emit signal for each tool call - handler executes tools and appends tool reply messages to messages_to_send
			// Signal handlers run synchronously, so they can modify messages_to_send
			foreach (var tool_call in response.message.tool_calls) {
				this.tool_call_requested(tool_call, messages_to_send);
			}
			
			// Append all messages and send (same logic as agent path)
			var next_response = yield this.send_append(messages_to_send);
			
			// Recursively handle tool calls if the next response also has them and is done
			if (next_response.done && 
				next_response.message.tool_calls.size > 0) {
				return yield this.toolsReply(next_response);
			}
			
			return next_response;
		}

		
		/**
		 * Appends new messages to existing messages and sends them.
		 * 
		 * Convenience method for continuing conversations after tool execution.
		 * Appends the provided messages to this.messages and then calls send().
		 * 
		 * @param new_messages Messages to append to existing messages
		 * @param cancellable Optional cancellation token
		 * @return The Response from executing the chat call
		 * @throws Error if send fails
		 */
		public async Response.Chat send_append(Gee.ArrayList<Message> new_messages, GLib.Cancellable? cancellable = null) throws Error
		{
			// Append new messages to existing messages
			foreach (var msg in new_messages) {
				this.messages.add(msg);
			}
			
			// Send using existing send() method; preserve this.cancellable when caller omits it
			// so that Stop continues to work across tool rounds (toolsReply, etc.)
			return yield this.send(this.messages, 
				cancellable != null ? cancellable : this.cancellable);
		}
		
		/**
		 * Sends messages to the chat API.
		 * 
		 * Takes messages array as argument and resets all state when called.
		 * This method replaces the old exec_chat() method and has its own complete implementation.
		 * 
		 * @param messages The messages array to send
		 * @param cancellable Optional cancellation token
		 * @return The Response from executing the chat call
		 */
		public async Response.Chat send(Gee.ArrayList<Message> messages, GLib.Cancellable? cancellable = null) throws Error
		{
			if (messages.size == 0) {
				throw new OllmError.INVALID_ARGUMENT("Chat messages array is empty. Provide messages to send.");
			}
			
			// Reset state
			this.streaming_response = null;
			this.cancellable = cancellable;
			
			// Store provided messages in this.messages (for serialization/access)
			this.messages = messages;
			
			// Debug: output messages being sent
			GLib.debug("Chat.send: Sending %d message(s):", this.messages.size);
			for (int i = 0; i < this.messages.size; i++) {
				var msg = this.messages[i];
				GLib.debug("  Message %d: role='%s', content='%s'%s", 
					i + 1, 
					msg.role, 
					msg.content,
					msg.thinking != "" ? @", thinking='$(msg.thinking)'" : "");
			}
			
			// Execute with streaming or non-streaming
			if (this.stream) {
				return yield this.execute_streaming();
			}
			
			return yield this.execute_non_streaming();
		}


		private async Response.Chat execute_non_streaming() throws Error
		{
			// chat_send signal emission removed - callers handle state directly after calling send()
			
			var bytes = yield this.send_request(true);
			var root = this.parse_response(bytes);

			if (root.get_node_type() != Json.NodeType.OBJECT) {
				throw new OllmError.FAILED("Invalid JSON response");
			}

			// Note: stream_start signal removed - handled by caller if needed

			var generator = new Json.Generator();
			generator.set_root(root);
			var json_str = generator.to_data(null);
			var response_obj = Json.gobject_from_data(typeof(Response.Chat), json_str, -1) as Response.Chat;
			if (response_obj == null) {
				throw new OllmError.FAILED("Failed to parse response");
			}

			// Note: client no longer set on response objects
			response_obj.call = this;
			response_obj.done = true; // Non-streaming responses are always done
			
			// Check for tool calls and handle them recursively
			if (response_obj.message.tool_calls.size > 0) {
				return yield this.toolsReply(response_obj);
			}
			
			return response_obj;
		}

		private async Response.Chat execute_streaming() throws Error
		{
			// chat_send signal emission removed - callers handle state directly after calling send()
			
			// Initialize streaming_response before starting stream to ensure it's never null
			if (this.streaming_response == null) {
				this.streaming_response = new Response.Chat(this.connection, this);
			}
			var response = (Response.Chat?)this.streaming_response;
			if (response == null) {
				throw new OllmError.FAILED("Streaming response is null after initialization");
			}
 
			var url = this.build_url();
			var request_body = this.get_request_body();
			var message = this.connection.soup_message(this.http_method, url, request_body);

			GLib.debug("Request URL: %s", url);
			GLib.debug("Request Body: %s", request_body);

			try {
				yield this.handle_streaming_response(message, (chunk) => {
					this.process_streaming_chunk(chunk);
				});
			} catch (GLib.IOError e) {
				if (e.code == GLib.IOError.CANCELLED) {
					// User cancelled - ensure response is marked as done
					response.done = true;
					// Return the response even if cancelled (may be partial)
					return response;
				}
				// Re-throw other IO errors
				throw e;
			} catch (Error e) {
				// Mark as done and re-throw
				response.done = true;
				throw e;
			}

		// Check for tool calls and handle them recursively
			GLib.debug("Chat.execute_streaming: done=%s, tool_calls.size=%d, content='%s'", 
				response.done.to_string(),
				response.message.tool_calls.size,
				response.message.content);
			
			if (response.done && 
				response.message.tool_calls.size > 0) {
				GLib.debug("Chat.execute_streaming: Calling toolsReply");
				return yield this.toolsReply(response);
			}
			
			GLib.debug("Chat.execute_streaming: Not calling toolsReply - done=%s, tool_calls.size=%d",
				response.done.to_string(),
				response.message.tool_calls.size);
			
			return response;
		}


		private void process_streaming_chunk(Json.Object chunk)
		{
			// Ensure streaming_response exists (should be initialized in execute_streaming, but double-check)
			if (this.streaming_response == null) {
				this.streaming_response = new Response.Chat(this.connection, this);
			}
			var response = (Response.Chat?)this.streaming_response;

			// Check if this is the first chunk (message is null before first chunk is processed)
			bool is_first_chunk = (response.message == null);

			// Process chunk
			response.addChunk(chunk);

			// Emit stream_start signal on first chunk
			if (is_first_chunk) {
				// Always emit signal (for non-agent usage and any other listeners)
				this.stream_start();
				
				// If Chat has agent reference, also call agent method directly
				if (this.agent != null) {
					this.agent.handle_stream_started();
				}
			}

		// Emit signal if there's new content (either regular content or thinking)
		// Also emit when done=true even if no new content, so we can finalize
		// Signal will only be delivered if handlers are connected
			if (response.new_thinking.length == 0 && 
				response.new_content.length == 0 && 
				!response.done) {
				return;
			}
			
			// Determine if this chunk is thinking content
			bool is_thinking = response.new_thinking.length > 0;
			string new_text = is_thinking ? response.new_thinking : response.new_content;
			
			// Always emit signal (for non-agent usage and any other listeners)
			this.stream_chunk(new_text, is_thinking, response);
			
			// If Chat has agent reference, also call agent method directly
			if (this.agent != null) {
				this.agent.handle_stream_chunk(new_text, is_thinking, response);
			}
		}
	}
}
