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
	 * Abstract base class for all Ollama API calls.
	 *
	 * Provides common functionality for making HTTP requests to the Ollama API,
	 * including URL building, request execution, and response handling. Handles
	 * streaming responses and error management. Subclasses must set url_endpoint
	 * and implement request-specific logic.
	 */
	public abstract class Base : OllamaBase
	{
		protected string url_endpoint;
		protected string http_method = "POST";
		public GLib.Cancellable? cancellable { get; set; default = null; }
		public Response.Base? streaming_response { get; set; default = null; }

	protected Base(Settings.Connection? connection = null)
	{
		base(connection);
	}

	protected string build_url()
	{
		if (this.connection == null) {
			return "";
		}
		var base_url = this.connection.url;
		if (!base_url.has_suffix("/")) {
			base_url += "/";
		}
		return base_url + this.url_endpoint;
	}

	protected async Bytes send_request(bool needs_body) throws Error
	{
		if (this.connection == null) {
			throw new OllamaError.INVALID_ARGUMENT("Connection is null");
		}

		var url = this.build_url();
		
		// Soup is initialized when Connection is created, never null
		// Timeout is already set on soup (via connection.timeout property)
		
		var message = this.connection.soup_message(this.http_method, url);

		if (needs_body && this.http_method == "POST") {
			this.set_request_body(message);
		}

		GLib.debug("Request URL: %s", url);

		var bytes = yield this.connection.soup.send_and_read_async(message, GLib.Priority.DEFAULT, null);

		if (message.status_code != 200) {
			switch (message.status_code) {
				case 400:
					// Try to parse error message from response body
					if (bytes != null && bytes.get_size() > 0) {
						this.parse_error_from_json((string)bytes.get_data(), "Bad request: ");
					}
					// Fall through to default error message if parsing failed or no error field found
					throw new OllamaError.FAILED("fetch returned 400: Bad request. Please check your request parameters.");
				case 401:
					throw new OllamaError.FAILED("fetch returned 401: Unauthorized. Please check your API key.");
				case 404:
					throw new OllamaError.FAILED("fetch returned 404: Endpoint not found. Please check the server URL.");
			default:
				if (message.status_code >= 500) {
					throw new OllamaError.FAILED("fetch returned " + message.status_code.to_string() + ": Server error. The server may be experiencing issues.");
				}
				throw new OllamaError.FAILED("fetch returned " + message.status_code.to_string());
			}
		}

		return bytes;
	}

		protected string get_request_body()
		{
			var json_node = Json.gobject_serialize(this);
			var generator = new Json.Generator();
			generator.set_root(json_node);
			return generator.to_data(null);
		}

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "chat-content":
				case "connection":
				case "cancellable":
				case "streaming-response":
					// Exclude these properties from serialization
					return null;
				default:
					return base.serialize_property(property_name, value, pspec);
			}
		}

		private void set_request_body(Soup.Message message)
		{
			var request_body = this.get_request_body();
			message.set_request_body_from_bytes("application/json", new Bytes(request_body.data));
			GLib.debug("Request Body: %s", request_body);
		}

		protected delegate void StreamingChunkCallback(Json.Object chunk);

		private void parse_error_from_json(string json_data, string prefix) throws OllamaError
		{
			var parser = new Json.Parser();
			try {
				parser.load_from_data(json_data, -1);
			} catch (Error e) {
				// If JSON parsing fails, throw an error about it
				throw new OllamaError.FAILED(@"Failed to parse error response: $(e.message)");
			}
				
			var root = parser.get_root();
			if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
				throw new OllamaError.FAILED("Failed to parse error response: invalid JSON structure");
			}
			
			var root_obj = root.get_object();
			if (!root_obj.has_member("error")) {
				throw new OllamaError.FAILED("Failed to parse error response: no error field found");
			}
			
			var error_message = root_obj.get_string_member("error");
			if (error_message == "") {
				throw new OllamaError.FAILED("Failed to parse error response: empty error message");
			}
			throw new OllamaError.FAILED(prefix + error_message);
		}

		private void parse_streaming_error(InputStream? input_stream, string prefix) throws OllamaError
		{
			if (input_stream == null) {
				return;
			}
			
			// Read error response from stream (synchronous - should be fast for a single line)
			var data_stream = new DataInputStream(input_stream);
			string? line = null;
			size_t length = 0;
			try {
				line = data_stream.read_line(out length, this.cancellable);
			} catch (Error e) {
				// If reading fails, just return (fall through to default error)
				GLib.debug("Failed to read error response from stream: %s", e.message);
				return;
			}
			
			if (line == null || line.strip() == "") {
				return;
			}
			
			this.parse_error_from_json(line.strip(), prefix);
		}

		protected async void handle_streaming_response(Soup.Message message, StreamingChunkCallback on_chunk) throws Error
		{
			// Use send_async() to get InputStream for true streaming
			// In Vala's libsoup-3.0 bindings, send_async() is already async and returns InputStream directly
			// Soup is initialized when Connection is created, never null
			// Timeout is already set on soup (via connection.timeout property)
			
			InputStream? input_stream = null;
			try {
				input_stream = yield this.connection.soup.send_async(
						message, GLib.Priority.DEFAULT, this.cancellable);
			} catch (GLib.IOError e) {
				if (e.code == GLib.IOError.CANCELLED) {
					// User cancelled - this is expected, don't throw
					return;
				}
				throw e;
			}
			
			if (message.status_code != 200) {
				switch (message.status_code) {
					case 400:
						// Try to parse error message from input stream (for streaming responses)
						this.parse_streaming_error(input_stream, "Bad request: ");
						// Fall through to default error message if parsing failed or no error field found
						throw new OllamaError.FAILED("fetch returned 400: Bad request. Please check your request parameters.");
					case 401:
						throw new OllamaError.FAILED("fetch returned 401: Unauthorized. Please check your API key.");
					case 404:
						throw new OllamaError.FAILED("fetch returned 404: Endpoint not found. Please check the server URL.");
				default:
					if (message.status_code >= 500) {
						throw new OllamaError.FAILED("fetch returned " + message.status_code.to_string() + ": Server error. The server may be experiencing issues.");
					}
					throw new OllamaError.FAILED("fetch returned " + message.status_code.to_string());
				}
			}
			
			if (input_stream == null) {
				throw new OllamaError.FAILED("Failed to get response input stream");
			}
			
			// Process the stream line by line as data arrives
			try {
				yield this.process_json_streaming(input_stream, on_chunk);
			} catch (GLib.IOError e) {
				if (e.code == GLib.IOError.CANCELLED) {
					// User cancelled during streaming - this is expected, don't throw
					return;
				}
				throw e;
			}
		}

		private async void process_json_streaming(InputStream input_stream, StreamingChunkCallback on_chunk) throws Error
		{
			var line_buffer = new StringBuilder();
			var data_input = new DataInputStream(input_stream);

			while (true) {
				string? line = null;
				try {
					line = yield data_input.read_line_async(GLib.Priority.DEFAULT, this.cancellable);
				} catch (GLib.IOError e) {
					if (e.code == GLib.IOError.CANCELLED) {
						// User cancelled - break gracefully
						break;
					}
					// Re-throw other IO errors
					throw e;
				}

				if (line == null) {
					break;
				}

				var trimmed = line.strip();
				if (trimmed != "") {
					this.process_json_chunk(trimmed, on_chunk);
				}
			}

			if (line_buffer.len > 0) {
				var final_line = line_buffer.str.strip();
				if (final_line != "") {
					this.process_json_chunk(final_line, on_chunk);
				}
			}
		}

		private async void process_streaming(InputStream input_stream, StreamingChunkCallback on_chunk) throws Error
		{
			while (true) {
				var chunk_str = yield this.read_chunk(input_stream);
				if (chunk_str == null) {
					break;
				}

				this.process_json_chunk(chunk_str, on_chunk);
			}
		}

		private async string? read_chunk(InputStream input_stream) throws Error
		{
			uint8[] chunk = new uint8[4096];
			ssize_t bytes_read = yield input_stream.read_async(chunk, GLib.Priority.DEFAULT, null);

			if (bytes_read <= 0) {
				return null;
			}

			return (string)chunk[0:bytes_read];
		}

		private void process_json_chunk(string chunk_str, StreamingChunkCallback on_chunk)
		{
			var trimmed = chunk_str.strip();
			//GLib.debug("GOT: %s", trimmed);
			if (trimmed == "" || !trimmed.has_suffix("}")) {
				return;
			}
			var parser = new Json.Parser();
			try {
				parser.load_from_data(trimmed, -1);
				var chunk_node = parser.get_root();
				if (chunk_node == null || chunk_node.get_node_type() != Json.NodeType.OBJECT) {
					GLib.debug("Skipping non-object JSON chunk: %s", trimmed.substring(0, trimmed.length > 100 ? 100 : trimmed.length));
					return;
				}
				// Only log first chunk if streaming_response exists and message is null
				// (streaming_response is null for Pull, but set for Chat)
				if (this.streaming_response != null && this.streaming_response.message == null) {
					GLib.debug("First streaming response: %s", trimmed);
				}
				var chunk_obj = chunk_node.get_object();
				if (chunk_obj.has_member("done") && chunk_obj.get_boolean_member("done") == true) {
					GLib.debug("Last streaming response: %s", trimmed);
				}				
				on_chunk(chunk_obj);
			} catch (Error e) {
				// Log JSON parsing errors
				GLib.debug("Failed to parse JSON chunk: %s. Error: %s", trimmed.substring(0, trimmed.length > 100 ? 100 : trimmed.length), e.message);
				// Skip invalid JSON chunks - they might be partial or malformed
			}
		}

		protected Json.Node parse_response(Bytes bytes) throws Error
		{
			var parser = new Json.Parser();
			parser.load_from_data((string)bytes.get_data(), -1);

			var root = parser.get_root();
			if (root == null) {
				throw new OllamaError.FAILED("Invalid JSON response");
			}

			return root;
		}

		protected Gee.ArrayList<Response.Model> parse_models_array(Json.Array array)
		{
			var items = new Gee.ArrayList<Response.Model>((a, b) => {
				return a.name == b.name;
			});

			for (int i = 0; i < array.get_length(); i++) {
				var element_node = array.get_element(i);
				var generator = new Json.Generator();
				generator.set_root(element_node);
				var json_str = generator.to_data(null);
				var item_obj = Json.gobject_from_data(typeof(Response.Model), json_str, -1) as Response.Model;
				if (item_obj == null) {
					continue;
				}
				
				// For ps() API responses: set name from model property
				// This ensures name is always set for consistency
				// Only do this for Ps, as Models already has name set correctly
				if (this is Ps) {
					GLib.debug("PsCall: setting name='%s' from model='%s'", item_obj.model, item_obj.name);
					item_obj.name = item_obj.model;
				}
				
				items.add(item_obj);
			}

			return items;
		}

		protected async Gee.ArrayList<Response.Model> get_models(string field_name) throws Error
		{
			var bytes = yield this.send_request(false);
			var root = this.parse_response(bytes);

			if (root.get_node_type() != Json.NodeType.OBJECT) {
				throw new OllamaError.FAILED("Invalid JSON response");
			}

			var root_obj = root.get_object();
			if (!root_obj.has_member(field_name)) {
				throw new OllamaError.FAILED(@"Response missing '$(field_name)' field");
			}

			return this.parse_models_array(root_obj.get_array_member(field_name));
		}
	}
}
