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

namespace OLLMchat.Call
{
	/**
	 * API call to generate embeddings for input text.
	 *
	 * Creates vector embeddings representing the input text using the specified model.
	 * Supports single string or array of strings as input.
	 */
	public class Embed : Base
	{
		// Real properties (Phase 3: fallback logic removed)
		public string model { get; set; }
		
		public string input { get; set; default = ""; }
		public Gee.ArrayList<string> input_array { get; set; default = new Gee.ArrayList<string>(); }
		public bool truncate { get; set; default = false; }
		public int dimensions { get; set; default = -1; }
		
		public string? keep_alive { get; set; }
		
		public Call.Options options { get; set; default = new Call.Options(); }

		public Embed(Settings.Connection connection, string model, Call.Options? options = null)
		{
			base(connection);
			if (model == "") {
				throw new OllamaError.INVALID_ARGUMENT("Model is required");
			}
			this.url_endpoint = "embed";
			this.http_method = "POST";
			this.model = model;
			
			// Load model options from config if options not provided
			if (options != null) {
				this.options = options;
			} else {
				// Note: When using connection directly, config is not available
				// Caller should provide options if needed
				this.options = new Call.Options();
			}
		}

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "client":
					return null;
				case "input":
					// If input_array has items, serialize it as "input" (array)
					// Otherwise serialize the string input
					if (this.input_array.size > 0) {
						var input_array_node = new Json.Node(Json.NodeType.ARRAY);
						var json_array = new Json.Array();
						foreach (var item in this.input_array) {
							json_array.add_string_element(item);
						}
						input_array_node.init_array(json_array);
						return input_array_node;
					}
					// Serialize string input normally (only if not empty)
					if (this.input == "") {
						return null;
					}
					return base.serialize_property(property_name, value, pspec);
				case "input-array":
					// Don't serialize input_array directly - it's handled in "input"
					return null;
				case "dimensions":
					// Only serialize if set (not -1)
					if (this.dimensions == -1) {
						return null;
					}
					return base.serialize_property(property_name, value, pspec);
				case "options":
					// Only serialize options if they have valid values
					if (!this.options.has_values()) {
						return null;
					}
					// Serialize options and convert hyphen keys to underscores for Ollama API
					var options_node = Json.gobject_serialize(this.options);
					var obj = options_node.get_object();
					// Create a new object with renamed keys (hyphens to underscores)
					var new_obj = new Json.Object();
					obj.foreach_member((o, key, node) => {
						var new_key = key.contains("-") ? key.replace("-", "_") : key;
						new_obj.set_member(new_key, node);
					});
					var new_node = new Json.Node(Json.NodeType.OBJECT);
					new_node.set_object(new_obj);
					return new_node;
				default:
					return base.serialize_property(property_name, value, pspec);
			}
		}

		/**
		 * Normalizes a single embedding vector to unit length (L2 normalization).
		 *
		 * @param embedding The embedding vector to normalize
		 */
		private void normalize_embedding(Gee.ArrayList<double?> embedding)
		{
			if (embedding.size == 0) {
				return;
			}
			
			// Calculate L2 norm
			double norm_squared = 0.0;
			foreach (var val in embedding) {
				if (val != null) {
					norm_squared += val * val;
				}
			}
			
			double norm = Math.sqrt(norm_squared);
			
			// Skip normalization if norm is zero or very small (avoid division by zero)
			if (norm < 1e-10) {
				return;
			}
			
			// Normalize each component
			for (int i = 0; i < embedding.size; i++) {
				var val = embedding.get(i);
				if (val != null) {
					embedding.set(i, val / norm);
				}
			}
		}

		public async Response.Embed exec_embed() throws Error
		{
			var bytes = yield this.send_request(true);
			var root = this.parse_response(bytes);

			if (root.get_node_type() != Json.NodeType.OBJECT) {
				throw new OllamaError.FAILED("Invalid JSON response");
			}

			var generator = new Json.Generator();
			generator.set_root(root);
			var json_str = generator.to_data(null);
			var embed_obj = Json.gobject_from_data(
				typeof(Response.Embed),
				json_str,
				-1
			) as Response.Embed;
			if (embed_obj == null) {
				throw new OllamaError.FAILED("Failed to deserialize embed response");
			}
			// Note: client no longer set on response objects
			
			// Normalize all embeddings before returning
			foreach (var embedding in embed_obj.embeddings) {
				this.normalize_embedding(embedding);
			}
			
			return embed_obj;
		}
	}
}

