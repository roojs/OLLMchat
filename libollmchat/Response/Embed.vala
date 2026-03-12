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
	 * Represents the response from the embeddings API.
	 *
	 * Contains the model name, embeddings (array of arrays of floats),
	 * and timing information.
	 */
	public class Embed : Base
	{
		public string model { get; set; default = ""; }
		public FloatArray embeddings { get; set; default = new FloatArray(0); }
		public int64 total_duration { get; set; default = 0; }
		public int64 load_duration { get; set; default = 0; }
		public int prompt_eval_count { get; set; default = 0; }
		public int prompt_tokens { get; set; default = 0; }
		public int total_tokens { get; set; default = 0; }

		public Embed(Settings.Connection? connection = null)
		{
			base(connection);
		}

		/**
		 * Fill embeddings from OpenAI v1 "data" array if present (array of { "embedding": number[], "index" }).
		 * No-op if obj has no "data" or it is not an array.
		 */
		public void read_data(Json.Object obj)
		{
			if (!obj.has_member("data")) {
				return;
			}
			var data_array = obj.get_member("data").get_array();
			if (data_array.get_length() == 0) {
				return;
			}
			var first = data_array.get_object_element(0);
			if (!first.has_member("embedding")) {
				return;
			}
			var first_inner = first.get_member("embedding").get_array();
			int width = (int)first_inner.get_length();
			var fa = new FloatArray(width);
			for (int i = 0; i < (int)data_array.get_length(); i++) {
				var item = data_array.get_object_element(i);
				if (!item.has_member("embedding")) {
					continue;
				}
				var inner = item.get_member("embedding").get_array();
				float[] vec = {};
				for (int j = 0; j < (int)inner.get_length(); j++) {
					var val_node = inner.get_element(j);
					float v = 0.0f;
					if (val_node.get_value_type() == typeof(double)) {
						v = (float)val_node.get_double();
					} else if (val_node.get_value_type() == typeof(int)) {
						v = (float)val_node.get_int();
					}
					vec += v;
				}
				fa.add(vec);
			}
			this.embeddings = fa;
		}

		/**
		 * Set prompt_tokens and total_tokens from OpenAI v1 "usage" object if present.
		 */
		public void read_usage(Json.Object obj)
		{
			if (!obj.has_member("usage")) {
				return;
			}
			var usage_obj = obj.get_object_member("usage");
			this.prompt_tokens = (int)usage_obj.get_int_member("prompt_tokens");
			this.total_tokens = (int)usage_obj.get_int_member("total_tokens");
		}

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "client":
					return null;
				case "embeddings":
					var fa = value.get_object() as FloatArray;
					if (fa == null || fa.rows == 0) {
						return null;
					}
					var json_array = new Json.Array();
					for (int i = 0; i < fa.rows; i++) {
						var inner = new Json.Array();
						int offset = i * fa.width;
						for (int j = 0; j < fa.width; j++) {
							inner.add_double_element((double)fa.data[offset + j]);
						}
						json_array.add_array_element(inner);
					}
					var array_node = new Json.Node(Json.NodeType.ARRAY);
					array_node.init_array(json_array);
					return array_node;
				default:
					return default_serialize_property(property_name, value, pspec);
			}
		}

		public override bool deserialize_property(
			string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			switch (property_name) {
				case "embeddings":
					// Ollama format: array of arrays of numbers
					var array = property_node.get_array();
					if (array.get_length() == 0) {
						value = Value(typeof(FloatArray));
						value.set_object(this.embeddings);
						return true;
					}
					var first_inner = array.get_array_element(0);
					int width = (int)first_inner.get_length();
					var fa = new FloatArray(width);
					for (int i = 0; i < (int)array.get_length(); i++) {
						var inner_array = array.get_array_element(i);
						float[] vec = {};
						for (int j = 0; j < (int)inner_array.get_length(); j++) {
							var val_node = inner_array.get_element(j);
							float v = 0.0f;
							if (val_node.get_value_type() == typeof(double)) {
								v = (float)val_node.get_double();
							} else if (val_node.get_value_type() == typeof(int)) {
								v = (float)val_node.get_int();
							}
							vec += v;
						}
						fa.add(vec);
					}
					value = Value(typeof(FloatArray));
					value.set_object(fa);
					return true;
				default:
					return default_deserialize_property(property_name, out value, pspec, property_node);
			}
		}
	}
}

