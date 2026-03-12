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
					// Delegate to Base so connection, chat-content, cancellable, streaming-response are excluded
					return base.serialize_property(property_name, value, pspec);
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
		 * a single ChatCompletionMessage and returns it.
		 * The stream's finish_reason is set on the returned message.
		 *
		 * @return accumulated message (role, content, tool_calls, finish_reason)
		 */
		public async Response.ChatCompletionMessage exec_stream() throws Error
		{
			var message = new Response.ChatCompletionMessage();
			message.role = "assistant";

			if (this.connection == null) {
				throw new OllmError.INVALID_ARGUMENT("Connection is null");
			}

			var url = this.build_url();
			var stream_orig = this.stream;
			this.stream = true;
			var request_body = this.get_request_body();
			this.stream = stream_orig;
			var soup_msg = this.connection.soup_message( this.http_method, url, request_body);

			GLib.InputStream? input_stream = null;
			try {
				input_stream = yield this.connection.soup.send_async(
					soup_msg, GLib.Priority.DEFAULT, this.cancellable);
			} catch (GLib.IOError e) {
				if (this.cancellable == null || !this.cancellable.is_cancelled()) {
					throw e;
				}
				return message;
			}

			if (soup_msg.status_code != 200) {
				if (input_stream != null && soup_msg.status_code == 400) {
					var data_stream = new GLib.DataInputStream(input_stream);
					string? line = null;
					try {
						line = yield data_stream.read_line_async(GLib.Priority.DEFAULT, this.cancellable);
					} catch (GLib.IOError ignored) {
					}
					if (line != null && line.strip() != "") {
						this.parse_error_from_json(line.strip(), "Stream error: ");
					}
				}
				this.handle_message_error(soup_msg);
			}

			if (input_stream == null) {
				throw new OllmError.FAILED("Failed to get response input stream");
			}

			var args_buffer = new Gee.ArrayList<string>();
			var data_input = new GLib.DataInputStream(input_stream);

			while (true) {
				string? line = null;
				try {
					line = yield data_input.read_line_async(
						GLib.Priority.DEFAULT, this.cancellable);
				} catch (GLib.IOError e) {
					if (e.code == GLib.IOError.CANCELLED) {
						break;
					}
					throw e;
				}

				if (line == null) {
					break;
				}

				var trimmed = line.strip();
				if (trimmed.length == 0) {
					continue;
				}
				if (!trimmed.has_prefix("data: ")) {
					continue;
				}
				var payload = trimmed.substring(6).strip();
				if (payload == "[DONE]") {
					break;
				}
				if (!payload.has_suffix("}")) {
					continue;
				}

				Response.ChatCompletionChunk? chunk = null;
				try {
					chunk = Json.gobject_from_data(typeof(Response.ChatCompletionChunk), payload, -1) as Response.ChatCompletionChunk;
				} catch (Error e) {
					continue;
				}
				if (chunk == null || chunk.choices.size == 0) {
					continue;
				}
				var choice = chunk.choices.get(0);

				if (choice.finish_reason != "") {
					message.finish_reason = choice.finish_reason;
					break;
				}

				var delta = choice.delta;
				if (delta.content != "") {
					message.content += delta.content;
				}
				if (delta.role != "") {
					message.role = delta.role;
				}
				if (delta.tool_calls.size == 0) {
					continue;
				}
				foreach (var tc in delta.tool_calls) {
					int index = tc.index;
					while (message.tool_calls.size <= index) {
						message.tool_calls.add(new Response.ToolCall());
						args_buffer.add("");
					}
					var tool_call = message.tool_calls.get(index);
					if (tc.id != "") {
						tool_call.id = tc.id;
					}
					if (tc.function.name != "") {
						tool_call.function.name = tc.function.name;
					}
					if (tc.function.arguments != "") {
						args_buffer.set(index, args_buffer.get(index) + tc.function.arguments);
					}
				}
			}

			for (int i = 0; i < args_buffer.size; i++) {
				var arg_str = args_buffer.get(i).strip();
				if (arg_str == "") {
					continue;
				}
				try {
					var parser = new Json.Parser();
					parser.load_from_data(arg_str, -1);
					var node = parser.get_root();
					if (node != null && node.get_node_type() == Json.NodeType.OBJECT) {
						message.tool_calls.get(i).function.arguments = node.get_object();
					}
				} catch (Error e) {
					// leave arguments as empty Json.Object
				}
			}

			return message;
		}
	}
}
