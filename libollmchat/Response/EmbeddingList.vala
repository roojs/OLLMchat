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
	 * Top-level OpenAI embeddings response.
	 * object, data (array of EmbeddingDatum), model, optional usage.
	 */
	public class EmbeddingList : Object, Json.Serializable
	{
		public string object { get; set; default = ""; }
		public Gee.ArrayList<Response.EmbeddingDatum> data { get; set;
			default = new Gee.ArrayList<Response.EmbeddingDatum>(); }
		public string model { get; set; default = ""; }
		public Response.Usage? usage { get; set; default = null; }

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "data":
					var arr = new Json.Array();
					foreach (var d in this.data) {
						arr.add_element(Json.gobject_serialize(d));
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
				case "data":
					this.data.clear();
					var array = property_node.get_array();
					for (int i = 0; i < array.get_length(); i++) {
						var el = Json.gobject_deserialize(
							typeof(Response.EmbeddingDatum),
							array.get_element(i)) as Response.EmbeddingDatum;
						if (el != null) {
							this.data.add(el);
						}
					}
					value = Value(typeof(Gee.ArrayList));
					value.set_object(this.data);
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
