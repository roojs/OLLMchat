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

namespace OLLMchat.Response
{
	/**
	 * Represents a tool call from the assistant.
	 * Used in assistant messages with tool_calls array.
	 *
	 * JSON example handled by this class:
	 *
	 *   {
	 *     "id": "call_123",
	 *     "function": {
	 *       "name": "read_file",
	 *       "arguments": {
	 *         "file_path": "src/Example.vala",
	 *         "encoding": "utf-8"
	 *       }
	 *     }
	 *   }
	 *
	 * This appears as an element in the "tool_calls" array within an assistant message.
	 */
	public class ToolCall : Object, Json.Serializable
	{
		public string id { get; set; default = ""; }
		public Response.CallFunction function { get; set; default = new Response.CallFunction(); }
		
		// used by desrialization
		public ToolCall()
		{
		}
		
		public ToolCall.with_values(string id, Response.CallFunction function)
		{
			this.id = id;
			this.function = function;
		}
		
		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "id":
					return default_serialize_property(property_name, value, pspec);
				
				case "function":
					return Json.gobject_serialize(this.function);
				
				default:
					return null;
			}
		}
		
		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			switch (property_name) {
				case "id":
					return default_deserialize_property(property_name, out value, pspec, property_node);
				
				case "function":
					this.function = Json.gobject_deserialize(typeof(Response.CallFunction), property_node) as Response.CallFunction;
				
					value = Value(typeof(Response.CallFunction));
					value.set_object(this.function);
					return true;
				
				default:
					return default_deserialize_property(property_name, out value, pspec, property_node);
			}
		}
	}
}

