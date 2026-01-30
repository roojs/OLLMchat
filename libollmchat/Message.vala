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

namespace OLLMchat
{
	/**
	 * Message class for chat conversations with role-based behavior.
	 *
	 * Messages have different roles that control their behavior and visibility:
	 * * "user" / "user-sent": User messages (user-sent is visible in UI)
	 * * "assistant": LLM response (not directly visible, use content-stream instead)
	 * * "content-stream" / "content-non-stream": Visible assistant content
	 * * "think-stream": Thinking output (for models that support it)
	 * * "tool": Tool execution results
	 * * "ui": UI messages displayed via tool_message
	 * * "system": System prompts
	 * * "end-stream": Stream end marker (not displayed)
	 * * "done": Completion marker (not displayed)
	 *
	 * Role changes automatically set flags (is_user, is_llm, is_content, etc.)
	 * for easy filtering and UI display decisions.
	 *
	 * == Example ==
	 *
	 * {{{
	 * // Create a user message
	 * var msg = new Message("user-sent", "Hello!");
	 *
	 * // Check message type
	 * if (msg.is_user && msg.is_ui_visible) {
	 *     // Display in UI
	 * }
	 *
	 * // Create streaming content message
	 * var content_msg = new Message("content-stream", "");
	 * content_msg.chat_content = "Partial response...";
	 * }}}
	 */
	public class Message : Object, Json.Serializable
	{
		private string _role;
		public string role {
			get { return _role; }
			set {
				_role = value;
				// Reset all flags
			
				
				// Set flags based on role
				switch (value) {
					case "think-stream":
						is_thinking = true;
						is_stream = true;
						is_hidden = true;
						is_ui_visible = true;  // Display as assistant message
						break;
					case "content-stream":
						is_content = true;
						is_stream = true;
						is_hidden = true;
						is_ui_visible = true;  // Display as assistant message
						break;
					case "content-non-stream":
						is_content = true;
						is_hidden = true;
						is_ui_visible = true;  // Display as assistant message
						break;
					case "user":
					case "user-sent":
						is_user = true;
						if (value == "user-sent") {
							is_hidden = true;
							is_ui_visible = true;  // Display user-sent messages
						}
						// "user" role is not UI visible (use "user-sent" instead)
						break;
					case "assistant":
						is_llm = true;
						is_ui_visible = false;  // Not displayed in UI (use content-stream or content-non-stream instead)
						break;
					case "tool":
						is_tool = true;
						// Tool messages are handled separately, not displayed directly
						break;
					case "end-stream":
						is_stream_end = true;
						is_hidden = true;
						// Not displayed in UI
						break;
					case "ui":
						is_hidden = true;
						is_ui_visible = true;  // Display via tool_message
						break;
					case "done":
						is_done = true;
						is_hidden = true;
						is_ui_visible = false;  // Not displayed in UI
						break;
					case "system":
						// System messages are not hidden (they get sent to API)
						// But not displayed in UI
						break;
				}
			}
		}
		
		// Public properties (without get/set)
		public bool is_thinking = false;
		public bool is_content = false;
		public bool is_stream = false;
		public bool is_user = false;
		public bool is_hidden = false;  // For types that don't get sent to the API
		public bool is_tool = false;
		public bool is_llm = false;  // For messages from the LLM (assistant role)
		public bool is_stream_end = false;
		public bool is_done = false;  // For "done" role messages indicating completion
		public bool is_ui_visible = false;  // For types that should be displayed in the UI
		
		public string content { get; set; default = ""; }
		public string thinking { get; set; default = ""; }
		public Gee.ArrayList<string> images { get; set; default = new Gee.ArrayList<string>(); }
		public Gee.ArrayList<Response.ToolCall> tool_calls { get; set; default = new Gee.ArrayList<Response.ToolCall>(); }
		public string tool_call_id { get; set; default = ""; }
		public string name { get; set; default = ""; }
		
		// History info (only included when include_history_info is true)
		public bool include_history_info { get; set; default = false; }
		public string timestamp { get; set; default = ""; }  // Format: Y-m-d H:i:s
		public bool hidden { get; set; default = false; }

		public Message(string role, string content, string thinking = "")
		{
			this.role = role;
			this.content = content;
			this.thinking = thinking;
		}
		
		/**
		 * Constructor for tool response messages.
		 * Used to send tool execution results back to OLLMchat.
		 *
		 * @param tool_call_id The ID of the tool call this response corresponds to
		 * @param name The name of the tool function that was executed
		 * @param content The result content from the tool execution
		 */
		public Message.tool_reply(string tool_call_id, string name, string content)
		{
			this.role = "tool";
			this.tool_call_id = tool_call_id;
			this.name = name;
			this.content = content;
			
		}
		
		/**
		 * Constructor for tool call failure messages.
		 * Used when tool execution fails with an error.
		 *
		 * @param tool_call The tool call that failed
		 * @param e The error that occurred during execution
		c */
		public Message.tool_call_fail(Response.ToolCall tool_call, Error e)
		{
			this.role = "tool";
			this.tool_call_id = tool_call.id;
			this.name = tool_call.function.name;
			this.content = "ERROR: " + e.message;
		}
		
		/**
		 * Constructor for invalid tool call messages.
		 * Used when a tool is not found or not available.
		 *
		 * @param tool_call The tool call that is invalid
		 * @param err_message The error message to send to the LLM
		 */
		public Message.tool_call_invalid(Response.ToolCall tool_call, string err_message)
		{
			this.role = "tool";
			this.tool_call_id = tool_call.id;
			this.name = tool_call.function.name;
			this.content = err_message;
			
			// Emit message_created signal
			// Note: UI message is already emitted in toolsReply(), so this is just for the tool message itself
		}
		
		/**
		 * Constructor for assistant messages with tool calls.
		 * Used when Ollama requests tool execution (tool call request from Ollama).
		 *
		 * @param tool_calls The list of tool calls requested by the assistant
		 */
		public Message.with_tools(Gee.ArrayList<Response.ToolCall> tool_calls)
		{
			this.role = "assistant";
			this.tool_calls = tool_calls;
		}
		
		/**
		 * Extracts code content from markdown code block syntax in this message's content.
		 * Handles both ```language and ``` formats.
		 * Returns the last code block if multiple exist.
		 */
		public string? extract_last_code()
		{
			var lines = this.content.split("\n");
			
			// Go backwards to find the last code block
			bool in_code_block = false;
			string code = "";
			
			for (int i = lines.length - 1; i >= 0; i--) {
				var line = lines[i];
				
				if (line.has_prefix("```")) {
					if (in_code_block) {
						// Found opening ``` - return the code we've collected
						return code; // yeap if we delete stuff.. then we will put an empty block..
						
					} 
						// Found closing ``` - start collecting
					in_code_block = true;
					continue;
				}
				if (!in_code_block) {
					continue;
				}
				// Prepend line to code (since we're going backwards)
			
				code = (code == "") ? line : line + "\n" + code;
				
				
			}
			
			// Handle case where code block isn't closed (opening ``` at start)
			// if it's no closed.. then its an error..
			
			return null;
		}

		/**
		 * Writes base64-encoded images onto the serialized message object at send time.
		 * Uses this.images (paths only). Updates message_obj in place; does not mutate the Message.
		 * Validates: file exists, MIME type is image. Skips invalid paths.
		 */
		public void serialize_images(Json.Object message_obj)
		{
			if (!message_obj.has_member("images")) {
				return;
			}
			message_obj.remove_member("images");
			var arr = new Json.Array();
			foreach (var path in this.images) {
				var file = GLib.File.new_for_path(path);
				if (!file.query_exists()) {
					continue;
				}
				string? content_type = null;
				try {
					var info = file.query_info(
						GLib.FileAttribute.STANDARD_CONTENT_TYPE,
						GLib.FileQueryInfoFlags.NONE,
						null
					);
					content_type = info.get_content_type();
				} catch (GLib.Error e) {
					continue;
				}
				if (content_type == null || !content_type.has_prefix("image/")) {
					continue;
				}
				uint8[] data;
				try {
					GLib.FileUtils.get_data(path, out data);
				} catch (GLib.Error e) {
					continue;
				}
				arr.add_string_element(GLib.Base64.encode(data));
			}
			if (arr.get_length() == 0) {
				return;
			}
			var n = new Json.Node(Json.NodeType.ARRAY);
			n.init_array(arr);
			message_obj.set_member("images", n);
		}

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "include-history-info":
					// Exclude the flag itself from serialization
					return null;
				
				case "timestamp":
				case "hidden":
					// Only serialize history info if include_history_info is true
					if (!this.include_history_info) {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				
				case "thinking":
					// Exclude thinking if empty
					if (this.thinking == "") {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				
				case "tool-calls":
					// Only serialize tool_calls if not empty (for assistant messages with tool calls)
					if (this.tool_calls.size == 0) {
						return null;
					}
					// Convert Gee.ArrayList<ToolCall> to Json.Array using standard serialization
					var array_node = new Json.Node(Json.NodeType.ARRAY);
					array_node.init_array(new Json.Array());
					var json_array = array_node.get_array();
					foreach (var tool_call in this.tool_calls) {
						json_array.add_element( Json.gobject_serialize(tool_call));
					}
					return array_node;
				
				case "tool-call-id":
					// Only serialize tool_call_id if not empty (for tool role messages)
					if (this.tool_call_id == "") {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				
				case "name":
					// Only serialize name if not empty (for tool role messages)
					if (this.name == "") {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				
				case "images":
					if (this.images.size == 0) {
						return null;
					}
					var arr = new Json.Array();
					for (int i = 0; i < this.images.size; i++) {
						arr.add_string_element(this.images.get(i));
					}
					var n = new Json.Node(Json.NodeType.ARRAY);
					n.init_array(arr);
					return n;
				
				default:
					return default_serialize_property(property_name, value, pspec);
			}
		}
		
		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			switch (property_name) {
				case "images":
					//this.images.clear();
					var images_array = property_node.get_array();
					for (uint i = 0; i < images_array.get_length(); i++) {
						this.images.add(images_array.get_string_element(i));
					}
					value = Value(typeof(Gee.ArrayList));
					value.set_object(this.images);
					return true;
				case "tool-calls":
					// Vala converts tool_calls to tool-calls in JSON
					//this.tool_calls.clear();
					var json_array = property_node.get_array();
					GLib.debug("Message.deserialize_property: Found tool_calls array with %u elements", json_array.get_length());
					for (uint i = 0; i < json_array.get_length(); i++) {
						var element_node = json_array.get_element(i);
						this.tool_calls.add(
							Json.gobject_deserialize(typeof(Response.ToolCall), element_node) as Response.ToolCall
						);
					}
					value = Value(typeof(Gee.ArrayList));
					value.set_object(this.tool_calls);
					return true;
				default:
					return default_deserialize_property(property_name, out value, pspec, property_node);
			}
		}
	}
}

