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
	 * OpenAI-compatible chat completions API call.
	 * Uses v1/chat/completions; same URL pattern as Call.Models.
	 * Request: model, messages, stream, max_tokens, temperature, top_p,
	 * response_format, tools. Returns Response.ChatCompletion (or accumulated
	 * message when streaming).
	 */
	public class ChatCompletions : Base
	{
		public string model { get; set; }
		public Gee.ArrayList<Message> messages { get; set;
			default = new Gee.ArrayList<Message>(); }
		public bool stream { get; set; default = true; }
		public int max_tokens { get; set; default = -1; }
		public double temperature { get; set; default = -1.0; }
		public double top_p { get; set; default = -1.0; }
		public Json.Object? response_format { get; set; default = null; }
		public Gee.HashMap<string, Tool.BaseTool>? tools { get; set;
			default = new Gee.HashMap<string, Tool.BaseTool>(); }

		public ChatCompletions(Settings.Connection connection, string model)
		{
			base(connection);
			if (model == "") {
				throw new OllmError.INVALID_ARGUMENT("Model is required");
			}
			this.model = model;
			this.is_openai = true;
			this.url_endpoint = "v1/chat/completions";
			this.http_method = "POST";
		}

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "connection":
				case "cancellable":
					return null;
				case "messages":
					var arr = new Json.Array();
					foreach (var m in this.messages) {
						var msg_node = Json.gobject_serialize(m);
						m.serialize_images(msg_node.get_object());
						arr.add_element(msg_node);
					}
					var node = new Json.Node(Json.NodeType.ARRAY);
					node.init_array(arr);
					return node;
				case "max_tokens":
					if (this.max_tokens < 0) {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				case "temperature":
				case "top_p":
					if (value.get_double() < 0) {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				case "response_format":
					if (this.response_format == null) {
						return null;
					}
					var fmt_node = new Json.Node(Json.NodeType.OBJECT);
					fmt_node.set_object(this.response_format);
					return fmt_node;
				case "tools":
					if (this.tools.size == 0) {
						return null;
					}
					var tools_arr = new Json.Array();
					foreach (var entry in this.tools.entries) {
						if (!entry.value.active) {
							continue;
						}
						var tool_node = Json.gobject_serialize(entry.value);
						var tool_obj = tool_node.get_object();
						var func_node = tool_obj.get_member("function");
						if (func_node != null && func_node.get_node_type() == Json.NodeType.OBJECT) {
							func_node.get_object().set_string_member("name", entry.key);
						}
						tool_obj.set_string_member("type", entry.value.tool_type);
						tools_arr.add_element(tool_node);
					}
					var tools_node = new Json.Node(Json.NodeType.ARRAY);
					tools_node.init_array(tools_arr);
					return tools_node;
				default:
					return default_serialize_property(property_name, value, pspec);
			}
		}

		/**
		 * Execute non-streaming request; returns full ChatCompletion.
		 */
		public async Response.ChatCompletion exec() throws Error
		{
			var bytes = yield this.send_request(true);
			var root = this.parse_response(bytes);
			if (root.get_node_type() != Json.NodeType.OBJECT) {
				throw new OllmError.FAILED("Invalid JSON response");
			}
			var generator = new Json.Generator();
			generator.set_root(root);
			var json_str = generator.to_data(null);
			var obj = Json.gobject_from_data(
				typeof(Response.ChatCompletion), json_str, -1) as Response.ChatCompletion;
			if (obj == null) {
				throw new OllmError.FAILED("Failed to deserialize chat completion response");
			}
			return obj;
		}

		/**
		 * Execute streaming request; consumes SSE, accumulates deltas into
		 * a single ChatCompletionMessage and returns it with finish_reason.
		 * Outstanding: wire SSE read loop and delta accumulation (see plan).
		 */
		public async Response.ChatCompletionMessage exec_stream() throws Error
		{
			var message = new Response.ChatCompletionMessage();
			// TODO: wire SSE read loop and delta accumulation (see plan §1.4).
			return message;
		}
	}
}
