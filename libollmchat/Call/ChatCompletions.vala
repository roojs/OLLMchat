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
	 *
	 * Uses {{{v1/chat/completions}}}. Request uses flat top-level params with
	 * {{{Call.Options}}} as fallback (same pattern as {@link Completions}).
	 * {{{format}}} / {{{format_obj}}} map to JSON key {{{response_format}}}.
	 * Non-streaming and streaming both return {@link Response.Chat}.
	 */
	public class ChatCompletions : Base, ChatInterface
	{
		public string model { get; set; }
		public Gee.ArrayList<Message> messages { get; set;
			default = new Gee.ArrayList<Message>(); }
		public bool stream { get; set; default = true; }
		public int max_tokens { get; set; default = -1; }
		public double temperature { get; set; default = -1.0; }
		public double top_p { get; set; default = -1.0; }
		/**
		 * Simple format hint: e.g. {{{"json"}}} maps to
		 * {{{response_format: { type: json_object }}}}.
		 */
		public string format { get; set; default = ""; }
		/**
		 * Full OpenAI response_format object when set (schema / json_object).
		 */
		public Json.Object? format_obj { get; set; default = null; }
		public Call.Options options { get; set; default = new Call.Options(); }
		public int seed { get; set; default = -1; }
		public string stop { get; set; default = ""; }
		public double presence_penalty { get; set; default = -1.0; }
		public double frequency_penalty { get; set; default = -1.0; }
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

		/**
		 * Injects {{{response_format}}} from {@link format_obj} or {@link format}.
		 * Not a GObject property so {@link Json.gobject_serialize} does not emit it
		 * by default.
		 */
		private void merge_response_format_into_object(Json.Object obj)
		{
			if (this.format_obj != null) {
				var n = new Json.Node(Json.NodeType.OBJECT);
				n.set_object(this.format_obj);
				obj.set_member("response_format", n);
				return;
			}
			if (this.format == "json") {
				var o = new Json.Object();
				o.set_string_member("type", "json_object");
				var n = new Json.Node(Json.NodeType.OBJECT);
				n.set_object(o);
				obj.set_member("response_format", n);
			}
		}

		protected override string get_request_body()
		{
			var json_node = Json.gobject_serialize(this);
			var obj = json_node.get_object();
			this.merge_response_format_into_object(obj);
			var generator = new Json.Generator();
			generator.set_root(json_node);
			return generator.to_data(null);
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
				case "options":
					return null;
				case "format":
				case "format-obj":
					return null;
				case "max_tokens": {
					var v = this.max_tokens >= 0 ? this.max_tokens : this.options.num_predict;
					if (v < 0) {
						return null;
					}
					var int_node = new Json.Node(Json.NodeType.VALUE);
					int_node.set_int(v);
					return int_node;
				}
				case "temperature": {
					var v = this.temperature >= 0 ? this.temperature : this.options.temperature;
					if (v < 0) {
						return null;
					}
					var d_node = new Json.Node(Json.NodeType.VALUE);
					d_node.set_double(v);
					return d_node;
				}
				case "top_p": {
					var v = this.top_p >= 0 ? this.top_p : this.options.top_p;
					if (v < 0) {
						return null;
					}
					var d_node = new Json.Node(Json.NodeType.VALUE);
					d_node.set_double(v);
					return d_node;
				}
				case "seed": {
					var v = this.seed >= 0 ? this.seed : this.options.seed;
					if (v < 0) {
						return null;
					}
					var int_node = new Json.Node(Json.NodeType.VALUE);
					int_node.set_int(v);
					return int_node;
				}
				case "stop": {
					var s = this.stop != "" ? this.stop : this.options.stop;
					if (s == "") {
						return null;
					}
					var s_node = new Json.Node(Json.NodeType.VALUE);
					s_node.set_string(s);
					return s_node;
				}
				case "presence_penalty": {
					var v = this.presence_penalty >= 0
						? this.presence_penalty
						: this.options.presence_penalty;
					if (v < 0) {
						return null;
					}
					var d_node = new Json.Node(Json.NodeType.VALUE);
					d_node.set_double(v);
					return d_node;
				}
				case "frequency_penalty": {
					var v = this.frequency_penalty >= 0
						? this.frequency_penalty
						: this.options.frequency_penalty;
					if (v < 0) {
						return null;
					}
					var d_node = new Json.Node(Json.NodeType.VALUE);
					d_node.set_double(v);
					return d_node;
				}
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
					return base.serialize_property(property_name, value, pspec);
			}
		}

		/**
		 * Non-streaming request; response parsed into {@link Response.Chat}.
		 *
		 * @return v1 completion mapped into {@link Response.Chat}
		 */
		public async Response.Chat exec() throws Error
		{
			if (this.messages.size == 0) {
				throw new OllmError.INVALID_ARGUMENT("Messages are required for chat completions");
			}
			var stream_orig = this.stream;
			this.stream = false;
			try {
				var bytes = yield this.send_request(true);
				var root = this.parse_response(bytes);
				if (root.get_node_type() != Json.NodeType.OBJECT) {
					throw new OllmError.FAILED("Invalid JSON response");
				}
				var chat = Json.gobject_deserialize(typeof(Response.Chat), root) as Response.Chat;
				if (chat == null) {
					throw new OllmError.FAILED("Failed to deserialize chat completion response");
				}
				chat.connection = this.connection;
				chat.call = this;
				chat.done = true;
				return chat;
			} finally {
				this.stream = stream_orig;
			}
		}

		/**
		 * Streaming request; SSE lines deserialized to {@link Response.Chunk},
		 * accumulated via {@link Response.Chat.addChunk}.
		 *
		 * @return accumulated {@link Response.Chat}
		 */
		public async Response.Chat exec_stream() throws Error
		{
			if (this.messages.size == 0) {
				throw new OllmError.INVALID_ARGUMENT("Messages are required for chat completions");
			}
			if (this.connection == null) {
				throw new OllmError.INVALID_ARGUMENT("Connection is null");
			}

			var resp = new Response.Chat(this.connection, this);

			var url = this.build_url();
			var stream_orig = this.stream;
			this.stream = true;
			var request_body = this.get_request_body();
			this.stream = stream_orig;
			var soup_msg = this.connection.soup_message(this.http_method, url, request_body);

			GLib.InputStream? input_stream = null;
			try {
				input_stream = yield this.connection.soup.send_async(
					soup_msg, GLib.Priority.DEFAULT, this.cancellable);
			} catch (GLib.IOError e) {
				if (this.cancellable == null || !this.cancellable.is_cancelled()) {
					throw e;
				}
				resp.done = true;
				return resp;
			}

			if (soup_msg.status_code != 200) {
				if (input_stream != null && soup_msg.status_code == 400) {
					var data_stream = new GLib.DataInputStream(input_stream);
					var err_line = "";
					try {
						var read = yield data_stream.read_line_async(
							GLib.Priority.DEFAULT, this.cancellable);
						if (read != null) {
							err_line = read;
						}
					} catch (GLib.IOError ignored) {
					}
					if (err_line.strip() != "") {
						this.parse_error_from_json(err_line.strip(), "Stream error: ");
					}
				}
				this.handle_message_error(soup_msg);
			}

			if (input_stream == null) {
				throw new OllmError.FAILED("Failed to get response input stream");
			}

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

				var parser = new Json.Parser();
				try {
					parser.load_from_data(payload, -1);
				} catch (Error e) {
					continue;
				}
				var root = parser.get_root();
				if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
					continue;
				}
				Response.Chunk? chunk = null;
				try {
					chunk = Json.gobject_deserialize(typeof(Response.Chunk), root) as Response.Chunk;
				} catch (Error e) {
					continue;
				}
				if (chunk == null) {
					continue;
				}
				var token = resp.addChunk(chunk);
				if (token == "") {
					continue;
				}
				resp.back_tokens.insert(0, token);
				if (resp.back_tokens.size > 100) {
					resp.back_tokens.remove_at(resp.back_tokens.size - 1);
				}
				if (!resp.check_back_token()) {
					throw new OllmError.FAILED(
						"Streaming stopped: output repeated; possible infinite generation loop.");
				}
			}

			if (!resp.done) {
				resp.done = true;
			}
			return resp;
		}

		/**
		 * Append messages and run one non-streaming completions request.
		 *
		 * Returns {@link Response.Chat} with v1 fields mapped in deserialize.
		 * Streaming is forced off for this round so the body is a single JSON object.
		 */
		public async Response.Chat send_append(
			Gee.ArrayList<Message> new_messages,
			GLib.Cancellable? cancellable = null) throws Error
		{
			foreach (var msg in new_messages) {
				this.messages.add(msg);
			}
			if (this.messages.size == 0) {
				throw new OllmError.INVALID_ARGUMENT("Messages are required for chat completions");
			}
			this.cancellable = cancellable;
			bool was_stream = this.stream;
			this.stream = false;
			try {
				var bytes = yield this.send_request(true);
				var root = this.parse_response(bytes);
				if (root.get_node_type() != Json.NodeType.OBJECT) {
					throw new OllmError.FAILED("Invalid JSON response");
				}
				var response_obj = Json.gobject_deserialize(typeof(Response.Chat), root) as Response.Chat;
				if (response_obj == null) {
					throw new OllmError.FAILED("Failed to parse response");
				}
				response_obj.connection = this.connection;
				response_obj.call = this;
				response_obj.done = true;
				return response_obj;
			} finally {
				this.stream = was_stream;
			}
		}
	}
}
