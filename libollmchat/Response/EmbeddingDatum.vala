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
	 * One embedding in an OpenAI embeddings response.
	 * embedding (array of doubles), index.
	 */
	public class EmbeddingDatum : Object, Json.Serializable
	{
		public Gee.ArrayList<double?> embedding { get; set;
			default = new Gee.ArrayList<double?>(); }
		public int index { get; set; default = 0; }

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			if (property_name != "embedding") {
				return default_serialize_property(property_name, value, pspec);
			}
			var arr = new Json.Array();
			foreach (var v in this.embedding) {
				arr.add_double_element(v ?? 0.0);
			}
			var node = new Json.Node(Json.NodeType.ARRAY);
			node.init_array(arr);
			return node;
		}

		public override bool deserialize_property(
			string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			if (property_name != "embedding") {
				return default_deserialize_property(property_name, out value, pspec, property_node);
			}
			this.embedding.clear();
			var array = property_node.get_array();
			for (int i = 0; i < array.get_length(); i++) {
				var el = array.get_element(i);
				if (el.get_value_type() == typeof(double)) {
					this.embedding.add(el.get_double());
					continue;
				}
				if (el.get_value_type() == typeof(int)) {
					this.embedding.add((double)el.get_int());
				}
			}
			value = Value(typeof(Gee.ArrayList));
			value.set_object(this.embedding);
			return true;
		}
	}
}
