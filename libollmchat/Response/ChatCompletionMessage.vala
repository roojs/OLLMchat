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

namespace OLLMchat.Response
{
	/**
	 * Message in an OpenAI chat completion choice.
	 * role, content, and optional tool_calls (array of ToolCall).
	 */
	public class ChatCompletionMessage : Object, Json.Serializable
	{
		public string role { get; set; default = ""; }
		public string content { get; set; default = ""; }
		public Gee.ArrayList<Response.ToolCall> tool_calls { get; set;
			default = new Gee.ArrayList<Response.ToolCall>(); }

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "tool_calls":
					if (this.tool_calls.size == 0) {
						return null;
					}
					var arr = new Json.Array();
					foreach (var tc in this.tool_calls) {
						arr.add_element(Json.gobject_serialize(tc));
					}
					var node = new Json.Node(Json.NodeType.ARRAY);
					node.init_array(arr);
					return node;
				default:
					return default_serialize_property(property_name, value, pspec);
			}
		}

		public override bool deserialize_property(
			string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			if (property_name != "tool_calls") {
				return default_deserialize_property(property_name, out value, pspec, property_node);
			}
			this.tool_calls.clear();
			var array = property_node.get_array();
			for (int i = 0; i < array.get_length(); i++) {
				var el = Json.gobject_deserialize(
					typeof(Response.ToolCall), array.get_element(i)) as Response.ToolCall;
				if (el != null) {
					this.tool_calls.add(el);
				}
			}
			value = Value(typeof(Gee.ArrayList));
			value.set_object(this.tool_calls);
			return true;
		}
	}
}
