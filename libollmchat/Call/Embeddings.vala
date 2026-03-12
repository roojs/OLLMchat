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

namespace OLLMchat.Call
{
	/**
	 * OpenAI-compatible embeddings API call.
	 * Uses v1/embeddings; same URL pattern as Call.Models.
	 * Request: model, input (string array). Returns Response.Embed (v1 response parsed into Embed).
	 */
	public class Embeddings : Base
	{
		public string model { get; set; }
		public string[] input { get; set; default = new string[0]; }
		public int dimensions { get; set; default = -1; }
		public string encoding_format { get; set; default = ""; }

		public Embeddings(Settings.Connection connection, string model)
		{
			base(connection);
			if (model == "") {
				throw new OllmError.INVALID_ARGUMENT("Model is required");
			}
			this.model = model;
			this.is_openai = true;
			this.url_endpoint = "v1/embeddings";
			this.http_method = "POST";
		}

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "input":
					if (this.input.length == 0) {
						return null;
					}
					var arr = new Json.Array();
					foreach (var s in this.input) {
						arr.add_string_element(s);
					}
					var node = new Json.Node(Json.NodeType.ARRAY);
					node.init_array(arr);
					return node;
				case "dimensions":
					if (this.dimensions < 0) {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				case "encoding_format":
				case "encoding-format":
					if (this.encoding_format == "") {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				default:
					// Delegate to Base so connection, chat-content, cancellable, streaming-response are excluded
					return base.serialize_property(property_name, value, pspec);
			}
		}

		public async Response.Embed exec_embedding() throws Error
		{
			var bytes = yield this.send_request(true);
			var root = this.parse_response(bytes);
			if (root.get_node_type() != Json.NodeType.OBJECT) {
				throw new OllmError.FAILED("Invalid JSON response");
			}
			var generator = new Json.Generator();
			generator.set_root(root);
			var json_str = generator.to_data(null);
			var embed = Json.gobject_from_data(
				typeof(Response.Embed), json_str, -1) as Response.Embed;
			if (embed == null) {
				throw new OllmError.FAILED("Failed to deserialize embeddings response");
			}
			var obj = root.get_object();
			embed.read_data(obj);
			embed.read_usage(obj);
			return embed;
		}
	}
}
