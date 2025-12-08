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
	 * Represents the response from the embeddings API.
	 * 
	 * Contains the model name, embeddings (array of arrays of floats),
	 * and timing information.
	 */
	public class Embed : Base
	{
		public string model { get; set; default = ""; }
		public Gee.ArrayList<Gee.ArrayList<double?>> embeddings { 
				get; set; 
				default = new Gee.ArrayList<Gee.ArrayList<double?>>(); 
		}
		public int64 total_duration { get; set; default = 0; }
		public int64 load_duration { get; set; default = 0; }
		public int prompt_eval_count { get; set; default = 0; }

		public Embed(Client? client = null)
		{
			base(client);
		}

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "client":
					return null;
				case "embeddings":
					// Serialize embeddings as array of arrays
					var embeddings_list = value.get_object() as Gee.ArrayList<Gee.ArrayList<double?>>;
					 
					var array_node = new Json.Node(Json.NodeType.ARRAY);
					var json_array = new Json.Array();
					foreach (var embedding in embeddings_list) {
						var inner_array = new Json.Array();
						foreach (var val in embedding) {
							 
							inner_array.add_double_element(val);
							 
						}
						json_array.add_array_element(inner_array);
					}
					array_node.init_array(json_array);
					return array_node;
				default:
					return base.serialize_property(property_name, value, pspec);
			}
		}

		public override bool deserialize_property(
			string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			switch (property_name) {
				case "embeddings":
					// Handle embeddings as array of arrays
					var embeddings_list = new Gee.ArrayList<Gee.ArrayList<double?>>();
					var array = property_node.get_array();
					for (int i = 0; i < array.get_length(); i++) {
						var inner_array = array.get_array_element(i);
						var embedding = new Gee.ArrayList<double?>();
						for (int j = 0; j < inner_array.get_length(); j++) {
							var val_node = inner_array.get_element(j);
							if (val_node.get_value_type() == typeof(double)) {
								embedding.add(val_node.get_double());
								continue;
							}
							if (val_node.get_value_type() == typeof(int)) {	
								embedding.add((double)val_node.get_int());
								continue;
							}
						}
						embeddings_list.add(embedding);
					}
					value = Value(typeof(Gee.ArrayList));
					value.set_object(embeddings_list);
					return true;
				default:
					return base.deserialize_property(property_name, out value, pspec, property_node);
			}
		}
	}
}

