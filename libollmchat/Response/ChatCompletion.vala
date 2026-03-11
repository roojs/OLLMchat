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
	 * Top-level OpenAI chat completion response.
	 * id, object, created, model, choices, optional usage.
	 */
	public class ChatCompletion : Object, Json.Serializable
	{
		public string id { get; set; default = ""; }
		public string object { get; set; default = ""; }
		public int64 created { get; set; default = 0; }
		public string model { get; set; default = ""; }
		public Gee.ArrayList<Response.ChatCompletionChoice> choices { get; set;
			default = new Gee.ArrayList<Response.ChatCompletionChoice>(); }
		public Response.Usage? usage { get; set; default = null; }

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "choices":
					var arr = new Json.Array();
					foreach (var c in this.choices) {
						arr.add_element(Json.gobject_serialize(c));
					}
					var node = new Json.Node(Json.NodeType.ARRAY);
					node.init_array(arr);
					return node;
				case "usage":
					if (this.usage == null) {
						return null;
					}
					return Json.gobject_serialize(this.usage);
				default:
					return default_serialize_property(property_name, value, pspec);
			}
		}

		public override bool deserialize_property(
			string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			switch (property_name) {
				case "choices":
					this.choices.clear();
					var array = property_node.get_array();
					for (int i = 0; i < array.get_length(); i++) {
						var el = Json.gobject_deserialize(
							typeof(Response.ChatCompletionChoice),
							array.get_element(i)) as Response.ChatCompletionChoice;
						if (el != null) {
							this.choices.add(el);
						}
					}
					value = Value(typeof(Gee.ArrayList));
					value.set_object(this.choices);
					return true;
				case "usage":
					this.usage = Json.gobject_deserialize(
						typeof(Response.Usage), property_node) as Response.Usage;
					value = Value(typeof(Response.Usage));
					value.set_object(this.usage);
					return true;
				default:
					return default_deserialize_property(property_name, out value, pspec, property_node);
			}
		}
	}
}
