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

namespace OLLMchat
{
	/**
	 * Simple message class for chat conversations.
	 * Implements Json.Serializable for use in chat calls.
	 */
	public class Message : Object, Json.Serializable
	{
		public string role {
			get;
			set {
				// Reset all flags
				is_thinking = false;
				is_content = false;
				is_stream = false;
				is_user = false;
				is_hidden = false;
				is_tool = false;
				is_agent = false;
				is_stream_end = false;
				
				// Set flags based on role
				switch (value) {
					case "think-stream":
						is_thinking = true;
						is_stream = true;
						is_hidden = true;
						break;
					case "content-stream":
						is_content = true;
						is_stream = true;
						is_hidden = true;
						break;
					case "user":
					case "user-sent":
						is_user = true;
						if (value == "user-sent") {
							is_hidden = true;
						}
						break;
					case "assistant":
						is_agent = true;
						break;
					case "tool":
						is_tool = true;
						break;
					case "end-stream":
						is_stream_end = true;
						is_hidden = true;
						break;
					case "ui":
						is_hidden = true;
						break;
					case "system":
						// System messages are not hidden (they get sent to API)
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
		public bool is_agent = false;
		public bool is_stream_end = false;
		
		public string content { get; set; default = ""; }
		public string thinking { get; set; default = ""; }
		public Gee.ArrayList<Response.ToolCall> tool_calls { get; set; default = new Gee.ArrayList<Response.ToolCall>(); }
		public string tool_call_id { get; set; default = ""; }
		public string name { get; set; default = ""; }
		public MessageInterface message_interface;
		
		// History info (only included when include_history_info is true)
		public bool include_history_info { get; set; default = false; }
		public string timestamp { get; set; default = ""; }  // Format: Y-m-d H:i:s
		public bool hidden { get; set; default = false; }

		public Message(MessageInterface message_interface, string role, string content, string thinking = "")
		{
			this.message_interface = message_interface;
			this.role = role;
			this.content = content;
			this.thinking = thinking;
		}
		
		/**
		 * Constructor for tool response messages.
		 * Used to send tool execution results back to OLLMchat.
		 * 
		 * @param message_interface The message interface
		 * @param tool_call_id The ID of the tool call this response corresponds to
		 * @param name The name of the tool function that was executed
		 * @param content The result content from the tool execution
		 */
		public Message.tool_reply(MessageInterface message_interface, string tool_call_id, string name, string content)
		{
			this.message_interface = message_interface;
			this.role = "tool";
			this.tool_call_id = tool_call_id;
			this.name = name;
			this.content = content;
			
		}
		
		/**
		 * Constructor for tool call failure messages.
		 * Used when tool execution fails with an error.
		 * 
		 * @param message_interface The message interface
		 * @param tool_call The tool call that failed
		 * @param e The error that occurred during execution
		c */
		public Message.tool_call_fail(MessageInterface message_interface, Response.ToolCall tool_call, Error e)
		{
			this.message_interface = message_interface;
			this.role = "tool";
			this.tool_call_id = tool_call.id;
			this.name = tool_call.function.name;
			this.content = "ERROR: " + e.message;
		}
		
		/**
		 * Constructor for invalid tool call messages.
		 * Used when a tool is not found or not available.
		 * 
		 * @param message_interface The message interface
		 * @param tool_call The tool call that is invalid
		 */
		public Message.tool_call_invalid(MessageInterface message_interface, Response.ToolCall tool_call)
		{
			this.message_interface = message_interface;
			this.role = "tool";
			this.tool_call_id = tool_call.id;
			this.name = tool_call.function.name;
			this.content = "ERROR: Tool '" + tool_call.function.name + "' is not available";
			
			// Emit tool message (message_interface is always a Chat for tool-related messages)
			((Call.Chat) message_interface).client.tool_message("Error: Tool '" + tool_call.function.name + "' not found");
		}
		
		/**
		 * Constructor for assistant messages with tool calls.
		 * Used when Ollama requests tool execution (tool call request from Ollama).
		 * 
		 * @param message_interface The message interface
		 * @param tool_calls The list of tool calls requested by the assistant
		 */
		public Message.with_tools(MessageInterface message_interface, Gee.ArrayList<Response.ToolCall> tool_calls)
		{
			this.message_interface = message_interface;
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
					if (this.tool_calls.size == 0) {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				
				case "name":
					// Only serialize name if not empty (for tool role messages)
					if (this.name == "") {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				
				default:
					return default_serialize_property(property_name, value, pspec);
			}
		}
		
		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			// Handle tool-calls (kebab-case from JSON) - Vala converts tool_calls to tool-calls in JSON
			if (property_name != "tool-calls") {
				return default_deserialize_property(property_name, out value, pspec, property_node);
			}
			
			// Convert Json.Array to Gee.ArrayList<ToolCall>
			this.tool_calls.clear();
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
		}
	}
}

