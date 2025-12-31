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
	 * Represents a function call with name and arguments.
	 * Used within ToolCall to represent the function being called.
	 *
	 * JSON example handled by this class:
	 *
	 *   "function": {
	 *     "name": "read_file",
	 *     "arguments": {
	 *       "file_path": "src/Example.vala",
	 *       "encoding": "utf-8",
	 *       "options": {
	 *         "timeout": 30
	 *       },
	 *       "tags": ["important", "documentation"]
	 *     }
	 *   }
	 *
	 * This is the "function" object within a tool call.
	 */
	public class CallFunction : Object, Json.Serializable
	{
		public string name { get; set; default = ""; }
		public Json.Object arguments { get; set; default = new Json.Object(); }
		
		public CallFunction()
		{
		}
		
		public CallFunction.with_values(string name, Json.Object arguments)
		{
			this.name = name;
			this.arguments = arguments;
		}
		
		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "name":
					return default_serialize_property(property_name, value, pspec);
				
				case "arguments":
					var node = new Json.Node(Json.NodeType.OBJECT);
					node.set_object(this.arguments);
					return node;
				
				default:
					return null;
			}
		}
		
		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			switch (property_name) {
				case "name":
					return default_deserialize_property(property_name, out value, pspec, property_node);
				
			case "arguments":
				if (property_node.get_node_type() == Json.NodeType.OBJECT) {
					this.arguments = property_node.get_object();
				} else {
					this.arguments = new Json.Object();
				}
				value = Value(typeof(Json.Object));
				value.set_boxed(this.arguments);
				return true;
				
				default:
					return default_deserialize_property(property_name, out value, pspec, property_node);
			}
		}
	}
}

