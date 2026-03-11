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
	 * One SSE data: line for streaming chat completions.
	 * id, object, model, created, choices (array of chunk choice).
	 */
	public class ChatCompletionChunk : Object, Json.Serializable
	{
		public string id { get; set; default = ""; }
		public string object { get; set; default = ""; }
		public string model { get; set; default = ""; }
		public int64 created { get; set; default = 0; }
		public Gee.ArrayList<Response.ChatCompletionChunkChoice> choices {
			get; set;
			default = new Gee.ArrayList<Response.ChatCompletionChunkChoice>(); }

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			if (property_name != "choices") {
				return default_serialize_property(property_name, value, pspec);
			}
			if (this.choices.size == 0) {
				return null;
			}
			var arr = new Json.Array();
			foreach (var c in this.choices) {
				arr.add_element(Json.gobject_serialize(c));
			}
			var node = new Json.Node(Json.NodeType.ARRAY);
			node.init_array(arr);
			return node;
		}

		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			if (property_name != "choices") {
				return default_deserialize_property(property_name, out value, pspec, property_node);
			}
			this.choices.clear();
			var array = property_node.get_array();
			for (int i = 0; i < array.get_length(); i++) {
				var el = Json.gobject_deserialize(typeof(Response.ChatCompletionChunkChoice), array.get_element(i)) as Response.ChatCompletionChunkChoice;
				if (el != null) {
					this.choices.add(el);
				}
			}
			value = Value(typeof(Gee.ArrayList));
			value.set_object(this.choices);
			return true;
		}
	}
}
