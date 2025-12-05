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
	 * flow and tool call recursion.
	 */
	public class Chat : Base, ChatContentInterface
	{
		// Read-only getters that read from client (with fake setters for serialization)
		public string model { 
			get { return this.client.model; }
			set { } // Fake setter for serialization
		}
		
		public bool stream { 
			get { return this.client.stream; }
			set { } // Fake setter for serialization
		}
		
		public string? format { 
			get { return this.client.format; }
			set { } // Fake setter for serialization
		}
		
		public Call.Options options { 
			owned get { return new Call.Options(this.client); }
			set { } // Fake setter for serialization
		}
		
		public bool think { 
			get { return this.client.think; }
			set { } // Fake setter for serialization
		}
		
		public string? keep_alive { 
			get { return this.client.keep_alive; }
			set { } // Fake setter for serialization
		}
		
		public Gee.HashMap<string, Tool.Interface>? tools { 
			get { return this.client.tools; }
			set { } // Fake setter for serialization
		}
		public Response.Chat? streaming_response { get; set; default = null; }
		public string system_content { get; set; default = ""; }

		public Gee.ArrayList<Message> messages { get; set; default = new Gee.ArrayList<Message>(); }
		
		// Session ID field to track which history session this chat belongs to
		// Generated in constructor - will always be set
		public string fid = "";
		
		public Chat(Client client)
		{
			base(client);
			this.url_endpoint = "chat";
			this.http_method = "POST";
			// Generate fid from current timestamp (format: YYYY-MM-DD-HH-MM-SS)
			var now = new DateTime.now_local();
			this.fid = now.format("%Y-%m-%d-%H-%M-%S");
		}
		// this is only called by response - not by the user
		  
		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "chat-content":
				case "message":
				case "streaming-response":
				case "system-content":
					// Exclude these properties from serialization
					return null;
				
				case "think":
					// Only serialize think if true, otherwise exclude
					if (!this.think) {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				
				case "tools":
					// Only serialize tools if model is set and tools exist
					if (this.client.model == "" || this.tools.size == 0) {
						return null;
					}
					if (!this.client.available_models.has_key(this.client.model) 
						|| !this.client.available_models.get(this.client.model).can_call) {
						return null;
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
				
				case "options":
					// Only serialize options if they have valid values
					if (!this.options.has_values()) {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				
				case "messages":
					// Serialize the message array built in exec_chat()
					var node = new Json.Node(Json.NodeType.ARRAY);
					node.init_array(new Json.Array());
					var array = node.get_array();
					foreach (var m in this.messages) {
						var msg_node = Json.gobject_serialize(m);
						array.add_element(msg_node);
					}
					return node;
				
				default:
					return base.serialize_property(property_name, value, pspec);
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
				
				// Set message_interface to this Chat
				msg_obj.message_interface = this;
				messages.add(msg_obj);
			}
			
			value = Value(typeof(Gee.ArrayList));
			value.set_object(messages);
			return true;
		}
 
		/**
		 * Sets up this Chat as a reply to a previous conversation and executes it.
		 * Appends the previous assistant response and new user message to the messages array, then calls exec_chat().
		 * 
		 * @param new_text The new user message text
		 * @param previous_response The previous Response from the assistant
		 * @return The Response from executing the chat call
		 */
		public async Response.Chat reply(string new_text, Response.Chat previous_response) throws Error
		{
			// Create dummy user-sent Message with original text BEFORE prompt engine modification
			var user_sent_msg = new Message(this, "user-sent", new_text);
			this.client.message_created(user_sent_msg, this);
			
			// Fill chat call with prompts from prompt_assistant (modifies chat_content)
			this.client.prompt_assistant.fill(this, new_text);
			
			// If system_content is set, create system Message and emit message_created
			if (this.system_content != "") {
				var system_msg = new Message(this, "system", this.system_content);
				this.client.message_created(system_msg, this);
			}
			
			// Append the assistant's response from the previous call
			// If it had tool_calls, preserve them in the conversation history
			if (previous_response.message.tool_calls.size > 0) {
				this.messages.add(previous_response.message);
			} else {
				this.messages.add(
					new Message(this, "assistant", previous_response.message.content,
					 previous_response.message.thinking));
			}

			// Append the new user message with modified chat_content (for API request)
			// Note: "user-sent" message was already created via signal with original text
			var user_message = new Message(this, "user", this.chat_content);
			this.messages.add(user_message);

			GLib.debug("Chat.reply: Sending %d message(s):", this.messages.size);
			for (int i = 0; i < this.messages.size; i++) {
				var msg = this.messages[i];
				GLib.debug("  Message %d: role='%s', content='%s'%s", 
					i + 1, 
					msg.role, 
					msg.content.length > 100 ? msg.content.substring(0, 100) + "..." : msg.content,
					msg.thinking != "" ? @", thinking='$(msg.thinking.length > 50 ? msg.thinking.substring(0, 50) + "..." : msg.thinking)'" : "");
			}
			
			if (this.stream) {
				//this.streaming_response = new Response(this.client);
				return yield this.execute_streaming();
			}

			return yield this.execute_non_streaming();
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
			
		// Add the assistant message with tool_calls to the conversation
		this.messages.add(response.message);
		
		// Execute each tool call and add tool reply messages directly
		foreach (var tool_call in response.message.tool_calls) {
				GLib.debug("Chat.toolsReply: Executing tool '%s' (id='%s')",
					tool_call.function.name, tool_call.id);
				
				if (!this.client.tools.has_key(tool_call.function.name)) {
					GLib.debug("Chat.toolsReply: Tool '%s' not found in client tools (available tools: %s)", 
						tool_call.function.name, 
						string.joinv(", ", this.client.tools.keys.to_array()));
					var error_msg = new Message(this, "ui", "Error: Tool '" + tool_call.function.name + "' not found");
					this.client.message_created(error_msg, this);
					this.messages.add(new Message.tool_call_invalid(this, tool_call));
					continue;
				}
				
				// Show message that tool is being executed
				var exec_msg = new Message(this, "ui", "Executing tool: `" + tool_call.function.name + "`");
				this.client.message_created(exec_msg, this);
				
				// Execute the tool with chat as first parameter
				try {
					var result = yield this.client.tools
						.get(tool_call.function.name)
						.execute(this, tool_call.function.arguments);
					
					// Log result summary (truncate if too long)
					var result_summary = result.length > 100 ? result.substring(0, 100) + "..." : result;
					
					// Check if result is an error and display it in UI
					if (result.has_prefix("ERROR:")) {
						GLib.debug("Chat.toolsReply: Tool '%s' returned error result: %s",
							tool_call.function.name, result);
						var error_msg = new Message(this, "ui", result);
						this.client.message_created(error_msg, this);
					} else {
						GLib.debug("Chat.toolsReply: Tool '%s' executed successfully, result length: %zu, preview: %s",
							tool_call.function.name, result.length, result_summary);
					}
					
					this.messages.add(
						new Message.tool_reply(
							this, tool_call.id, 
							tool_call.function.name,
							result
						));
				} catch (Error e) {
					GLib.debug("Chat.toolsReply: Error executing tool '%s' (id='%s'): %s", 
						tool_call.function.name, tool_call.id, e.message);
					var error_msg = new Message(this, "ui", "Error executing tool '" + tool_call.function.name + "': " + e.message);
					this.client.message_created(error_msg, this);
					this.messages.add(new Message.tool_call_fail(this, tool_call, e));
				}
			}
			
			// Automatically continue the conversation by sending tool results back to the server
			GLib.debug("Chat.toolsReply: Tools executed, automatically continuing conversation");
			
			// Reset streaming_response for the continuation so we get a fresh response
			this.streaming_response = null;
			
			// Execute the chat call with tool results in the conversation history
			Response.Chat next_response;
			if (this.stream) {
				next_response = yield this.execute_streaming();
			} else {
				next_response = yield this.execute_non_streaming();
			}
			
			// Recursively handle tool calls if the next response also has them and is done
			if (next_response.done && 
				next_response.message.tool_calls.size > 0) {
				return yield this.toolsReply(next_response);
			}
			
			return next_response;
		}

		
		public async Response.Chat exec_chat() throws Error
		{
			if (this.model == "") {
				throw new OllamaError.INVALID_ARGUMENT("Model is required");
			}
			 
			// System and user messages are now created earlier via message_created signal
			// But we still need to add API-compatible messages to messages array for the request
			// Add system message if system_content is set (for API request)
			if (this.system_content != "") {
				this.messages.add(new Message(this, "system", this.system_content));
			}
			
			// Add the user message with modified chat_content (for API request)
			// Note: "user-sent" message was already created via signal with original text
			var user_message = new Message(this, "user", this.chat_content);
			this.messages.add(user_message);
			
			// Debug: output messages being sent
			GLib.debug("Chat.exec_chat: Sending %d message(s):", this.messages.size);
			for (int i = 0; i < this.messages.size; i++) {
				var msg = this.messages[i];
				GLib.debug("  Message %d: role='%s', content='%s'%s", 
					i + 1, 
					msg.role, 
					msg.content.length > 100 ? msg.content.substring(0, 100) + "..." : msg.content,
					msg.thinking != "" ? @", thinking='$(msg.thinking.length > 50 ? msg.thinking.substring(0, 50) + "..." : msg.thinking)'" : "");
			}
			
			if (this.stream) {
				//this.streaming_response = new Response(this.client);
				return yield this.execute_streaming();
			}

			return yield this.execute_non_streaming();
		}

		private async Response.Chat execute_non_streaming() throws Error
		{
			// Emit signal that we're sending the request
			this.client.chat_send(this);
			
			var bytes = yield this.send_request(true);
			var root = this.parse_response(bytes);

			if (root.get_node_type() != Json.NodeType.OBJECT) {
				throw new OllamaError.FAILED("Invalid JSON response");
			}

			// Emit stream_start signal when response is received (non-streaming)
			this.client.stream_start();

			var generator = new Json.Generator();
			generator.set_root(root);
			var json_str = generator.to_data(null);
			var response_obj = Json.gobject_from_data(typeof(Response.Chat), json_str, -1) as Response.Chat;
			if (response_obj == null) {
				throw new OllamaError.FAILED("Failed to parse response");
			}

			response_obj.client = this.client;
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
			// Emit signal that we're sending the request
			this.client.chat_send(this);
			
			// Initialize streaming_response before starting stream to ensure it's never null
			if (this.streaming_response == null) {
				this.streaming_response = new Response.Chat(this.client, this);
			}

			var url = this.build_url();
			var request_body = this.get_request_body();
			var message = this.create_streaming_message(url, request_body);

			GLib.debug("Request URL: %s", url);
			GLib.debug("Request Body: %s", request_body);

			try {
				yield this.handle_streaming_response(message, (chunk) => {
					this.process_streaming_chunk(chunk);
				});
			} catch (GLib.IOError e) {
				if (e.code == GLib.IOError.CANCELLED) {
					// User cancelled - ensure response is marked as done
					this.streaming_response.done = true;
					// Return the response even if cancelled (may be partial)
					return this.streaming_response;
				}
				// Re-throw other IO errors
				throw e;
			} catch (Error e) {
				// Mark as done and re-throw
				this.streaming_response.done = true;
				throw e;
			}

		// Check for tool calls and handle them recursively
			GLib.debug("Chat.execute_streaming: done=%s, tool_calls.size=%d, content='%s'", 
				this.streaming_response.done.to_string(),
				this.streaming_response.message.tool_calls.size,
				this.streaming_response.message.content);
			
			if (this.streaming_response.done && 
				this.streaming_response.message.tool_calls.size > 0) {
				GLib.debug("Chat.execute_streaming: Calling toolsReply");
				return yield this.toolsReply(this.streaming_response);
			}
			
			GLib.debug("Chat.execute_streaming: Not calling toolsReply - done=%s, tool_calls.size=%d",
				this.streaming_response.done.to_string(),
				this.streaming_response.message.tool_calls.size);
			
			return this.streaming_response;
		}
		
		

		private Soup.Message create_streaming_message(string url, string request_body)
		{
			var message = new Soup.Message(this.http_method, url);

			if (this.client.api_key != null && this.client.api_key != "") {
				message.request_headers.append("Authorization", @"Bearer $(this.client.api_key)");
			}

			message.set_request_body_from_bytes("application/json", new Bytes(request_body.data));
			return message;
		}


		private void process_streaming_chunk(Json.Object chunk)
		{
			// Ensure streaming_response exists (should be initialized in execute_streaming, but double-check)
			if (this.streaming_response == null) {
				this.streaming_response = new Response.Chat(this.client, this);
			}

			// Emit stream_start signal on first chunk (when message is null, this is the first chunk)
			if (this.streaming_response.message == null) {
				this.client.stream_start();
			}

			// Process chunk
			this.streaming_response.addChunk(chunk);

			// Emit stream_content signal for content only (not thinking)
			if (this.streaming_response.new_content.length > 0) {
				this.client.stream_content(
					this.streaming_response.new_content, this.streaming_response
				);
			}

			// Emit signal if there's new content (either regular content or thinking)
			// Also emit when done=true even if no new content, so we can finalize
			// Signal will only be delivered if handlers are connected
			if (this.streaming_response == null 
				|| this.client == null 
				|| (
					this.streaming_response.new_thinking.length == 0 && 
					this.streaming_response.new_content.length == 0 && 
					!this.streaming_response.done
				)) {
				return;
			}
			this.client.stream_chunk(
					this.streaming_response.new_thinking.length > 0 ? this.streaming_response.new_thinking : 
						(this.streaming_response.new_content.length > 0 ? this.streaming_response.new_content : ""), 
					this.streaming_response.new_thinking.length > 0 ? true : 
						(this.streaming_response.new_content.length > 0 ? false : this.streaming_response.is_thinking),
					this.streaming_response);
		}
	}
}
