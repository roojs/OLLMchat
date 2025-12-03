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
	 * API call to generate a response for a prompt.
	 * 
	 * Generates a response for the provided prompt using the /api/generate endpoint.
	 * This is a simpler endpoint than chat that doesn't maintain conversation history.
	 */
	public class Generate : Base
	{
		// Read-only getters that read from client (with fake setters for serialization)
		public string model { 
			get { return this.client.model; }
			set { } // Fake setter for serialization
		}
		
		public string prompt { get; set; default = ""; }
		public string system { get; set; default = ""; }
		public string suffix { get; set; default = ""; }
		public Gee.ArrayList<string> images { get; set; default = new Gee.ArrayList<string>(); }
		internal string? format { 
			get { return this.client.format; }
			set { } // Fake setter for serialization
		}
		internal bool stream { 
			get { return this.client.stream; }
			set { } // Fake setter for serialization
		}
		internal bool think { 
			get { return this.client.think; }
			set { } // Fake setter for serialization
		}
		public bool raw { get; set; default = false; }
		internal string? keep_alive { 
			get { return this.client.keep_alive; }
			set { } // Fake setter for serialization
		}
		
		internal Call.Options options { 
			owned get { return new Call.Options(this.client); }
			set { } // Fake setter for serialization
		}

		public Generate(Client client)
		{
			base(client);
			this.url_endpoint = "generate";
			this.http_method = "POST";
		}

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "client":
					return null;
				
				// String properties - default empty string
				case "prompt":
				case "system":
				case "suffix":
					if (value.get_string() == "") {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				
				// Boolean properties - default false
				case "stream":
				case "think":
				case "raw":
					if (!value.get_boolean()) {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				
				// Nullable string properties
				case "format":
				case "keep-alive":
					if (value.get_string() == "") {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				
				// Array properties
				case "images":
					if (this.images.size == 0) {
						return null;
					}
					var images_array_node = new Json.Node(Json.NodeType.ARRAY);
					var json_array = new Json.Array();
					foreach (var item in this.images) {
						json_array.add_string_element(item);
					}
					images_array_node.init_array(json_array);
					return images_array_node;
				
				// Options
				case "options":
					if (!this.options.has_values()) {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				
				default:
					return base.serialize_property(property_name, value, pspec);
			}
		}

		public async Response.Generate exec_generate() throws Error
		{
			var bytes = yield this.send_request(true);
			var root = this.parse_response(bytes);

			if (root.get_node_type() != Json.NodeType.OBJECT) {
				throw new OllamaError.FAILED("Invalid JSON response");
			}

			var generator = new Json.Generator();
			generator.set_root(root);
			var json_str = generator.to_data(null);
			var generate_obj = Json.gobject_from_data(typeof(Response.Generate), json_str, -1) as Response.Generate;
			if (generate_obj == null) {
				throw new OllamaError.FAILED("Failed to deserialize generate response");
			}
			generate_obj.client = this.client;
			return generate_obj;
		}
	}
}

