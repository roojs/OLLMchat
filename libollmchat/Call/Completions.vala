/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, see <http://www.gnu.org/licenses/>.
 */

namespace OLLMchat.Call
{
	/**
	 * OpenAI-compatible completions API call (prompt → text).
	 * Uses v1/completions; same URL pattern as Call.Models.
	 * Request: model, prompt (required), optional max_tokens, temperature, top_p, n, stop, presence_penalty, frequency_penalty.
	 * Options: same Call.Options as Generate; used as fallback when top-level param not set (options.num_predict → max_tokens, etc.).
	 * Returns Response.Generate; v1 JSON is parsed via deserialize_property.
	 */
	public class Completions : Base
	{
		public string model { get; set; }
		public string prompt { get; set; default = ""; }
		public bool stream { get; set; default = false; }
		public int max_tokens { get; set; default = -1; }
		public double temperature { get; set; default = -1.0; }
		public double top_p { get; set; default = -1.0; }
		public int n { get; set; default = 1; }
		public string stop { get; set; default = ""; }
		public double presence_penalty { get; set; default = -1.0; }
		public double frequency_penalty { get; set; default = -1.0; }
		public Call.Options options { get; set; default = new Call.Options(); }

		public Completions(Settings.Connection connection, string model)
		{
			base(connection);
			if (model == "") {
				throw new OllmError.INVALID_ARGUMENT("Model is required");
			}
			this.model = model;
			this.is_openai = true;
			this.url_endpoint = "v1/completions";
			this.http_method = "POST";
		}

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "options":
					// Do not serialize "options" as a key; we flatten options into top-level params below.
					return null;
				case "prompt":
					return default_serialize_property(property_name, value, pspec);
				case "max_tokens": {
					var v = this.max_tokens >= 0 ? this.max_tokens : this.options.num_predict;
					if (v < 0) {
						return null;
					}
					var node = new Json.Node(Json.NodeType.VALUE);
					node.set_int(v);
					return node;
				}
				case "temperature": {
					var v = this.temperature >= 0 ? this.temperature : this.options.temperature;
					if (v < 0) {
						return null;
					}
					var node = new Json.Node(Json.NodeType.VALUE);
					node.set_double(v);
					return node;
				}
				case "top_p": {
					var v = this.top_p >= 0 ? this.top_p : this.options.top_p;
					if (v < 0) {
						return null;
					}
					var node = new Json.Node(Json.NodeType.VALUE);
					node.set_double(v);
					return node;
				}
				case "stop": {
					var s = this.stop != "" ? this.stop : this.options.stop;
					if (s == "") {
						return null;
					}
					var node = new Json.Node(Json.NodeType.VALUE);
					node.set_string(s);
					return node;
				}
				case "presence_penalty": {
					var v = this.presence_penalty >= 0 ? this.presence_penalty : this.options.presence_penalty;
					if (v < 0) {
						return null;
					}
					var node = new Json.Node(Json.NodeType.VALUE);
					node.set_double(v);
					return node;
				}
				case "frequency_penalty": {
					var v = this.frequency_penalty >= 0 ? this.frequency_penalty : this.options.frequency_penalty;
					if (v < 0) {
						return null;
					}
					var node = new Json.Node(Json.NodeType.VALUE);
					node.set_double(v);
					return node;
				}
				case "n":
					if (this.n <= 1) {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				default:
					return base.serialize_property(property_name, value, pspec);
			}
		}

		/**
		 * Execute request; uses Json deserialize (gobject_from_data). Response.Generate
		 * deserialize_property handles v1 shape (choices[], usage) and maps into flat properties.
		 * Prompt is required for the API; we throw if empty.
		 */
		public async Response.Generate exec_completions() throws Error
		{
			if (this.prompt == "") {
				throw new OllmError.INVALID_ARGUMENT("Prompt is required for completions");
			}
			var bytes = yield this.send_request(true);
			var root = this.parse_response(bytes);
			if (root.get_node_type() != Json.NodeType.OBJECT) {
				throw new OllmError.FAILED("Invalid JSON response");
			}
			var generator = new Json.Generator();
			generator.set_root(root);
			var json_str = generator.to_data(null);
			var gen = Json.gobject_from_data(
				typeof(Response.Generate), json_str, -1) as Response.Generate;
			if (gen == null) {
				throw new OllmError.FAILED("Failed to deserialize completions response");
			}
			return gen;
		}
	}
}
