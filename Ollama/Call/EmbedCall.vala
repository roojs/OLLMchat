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

namespace OLLMchat.Ollama
{
	/**
	 * API call to generate embeddings for input text.
	 * 
	 * Creates vector embeddings representing the input text using the specified model.
	 * Supports single string or array of strings as input.
	 */
	public class EmbedCall : BaseCall
	{
		public string model { get; set; default = ""; }
		public string? input { get; set; }
		public Gee.ArrayList<string>? input_array { get; set; }
		public bool truncate { get; set; default = true; }
		public int? dimensions { get; set; }
		public string? keep_alive { get; set; }
		public Json.Object? options { get; set; }

		public EmbedCall(Client client, string input) throws OllamaError
		{
			base(client);
			if (input == "") {
				throw new OllamaError.FAILED("Input cannot be empty");
			}
			this.input = input;
			if (client.model != "") {
				this.model = client.model;
			}
			this.url_endpoint = "embed";
			this.http_method = "POST";
		}

		public EmbedCall.with_array(Client client, Gee.ArrayList<string> input_array) throws OllamaError
		{
			base(client);
			if (input_array == null || input_array.size == 0) {
				throw new OllamaError.FAILED("Input array cannot be empty");
			}
			this.input_array = input_array;
			if (client.model != "") {
				this.model = client.model;
			}
			this.url_endpoint = "embed";
			this.http_method = "POST";
		}

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "client":
				case "input-array":
					return null;
				case "input":
					// Only serialize input if input_array is not set
					if (this.input_array != null) {
						return null;
					}
					return base.serialize_property(property_name, value, pspec);
				case "dimensions":
					// Only serialize if set (not null)
					if (this.dimensions == null) {
						return null;
					}
					return base.serialize_property(property_name, value, pspec);
				case "options":
					// Serialize Json.Object if present
					if (this.options == null) {
						return null;
					}
					var node = new Json.Node(Json.NodeType.OBJECT);
					node.init_object(this.options);
					return node;
				default:
					return base.serialize_property(property_name, value, pspec);
			}
		}

		protected override string get_request_body()
		{
			var root = new Json.Node(Json.NodeType.OBJECT);
			var root_obj = new Json.Object();
			root.init_object(root_obj);

			// Add model
			if (this.model != "") {
				root_obj.set_string_member("model", this.model);
			}

			// Add input - either string or array
			if (this.input_array != null && this.input_array.size > 0) {
				var input_array_node = new Json.Node(Json.NodeType.ARRAY);
				var json_array = new Json.Array();
				foreach (var item in this.input_array) {
					json_array.add_string_element(item);
				}
				input_array_node.init_array(json_array);
				root_obj.set_member("input", input_array_node);
			} else if (this.input != null) {
				root_obj.set_string_member("input", this.input);
			}

			// Add optional fields
			if (!this.truncate) {
				root_obj.set_boolean_member("truncate", false);
			}
			if (this.dimensions != null) {
				root_obj.set_int_member("dimensions", this.dimensions);
			}
			if (this.keep_alive != null) {
				root_obj.set_string_member("keep_alive", this.keep_alive);
			}
			if (this.options != null) {
				root_obj.set_object_member("options", this.options);
			}

			var generator = new Json.Generator();
			generator.set_root(root);
			return generator.to_data(null);
		}

		public async EmbedResponse exec_embed() throws Error
		{
			var bytes = yield this.send_request(true);
			var root = this.parse_response(bytes);

			if (root.get_node_type() != Json.NodeType.OBJECT) {
				throw new OllamaError.FAILED("Invalid JSON response");
			}

			var generator = new Json.Generator();
			generator.set_root(root);
			var json_str = generator.to_data(null);
			var embed_obj = Json.gobject_from_data(typeof(EmbedResponse), json_str, -1) as EmbedResponse;
			if (embed_obj == null) {
				throw new OllamaError.FAILED("Failed to deserialize embed response");
			}
			embed_obj.client = this.client;
			return embed_obj;
		}
	}
}

