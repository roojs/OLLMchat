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
	 * API call to pull a model from the Ollama server.
	 * 
	 * Pulls a model by name, with optional streaming progress updates.
	 * The pull operation downloads the model files from the server.
	 */
	public class Pull : Base
	{
		public string name { get; set; default = ""; }
		public bool stream { get; set; default = true; }

		/**
		 * Signal emitted when a progress chunk is received during pull.
		 * 
		 * @param chunk The JSON object containing progress information
		 */
		public signal void progress_chunk(Json.Object chunk);

		public Pull(Client client, string model_name)
		{
			base(client);
			if (model_name == "") {
				throw new OllamaError.INVALID_ARGUMENT("Model name cannot be empty");
			}
			this.name = model_name;
			this.url_endpoint = "pull";
			this.http_method = "POST";
		}

		/**
		 * Executes the pull API call.
		 * 
		 * If streaming is enabled (default), processes streaming JSON chunks and emits
		 * progress_chunk signals for each update. The pull operation completes when done.
		 * 
		 * @throws Error if the request fails or response is invalid
		 */
		public async void exec_pull() throws Error
		{
			if (this.stream) {
				yield this.execute_streaming();
			} else {
				yield this.execute_non_streaming();
			}
		}

		private async void execute_streaming() throws Error
		{
			var url = this.build_url();
			var request_body = this.get_request_body();
			var message = this.create_streaming_message(url, request_body);

			GLib.debug("Pull request URL: %s", url);
			GLib.debug("Pull request Body: %s", request_body);

			try {
				yield this.handle_streaming_response(message, (chunk) => {
					this.progress_chunk(chunk);
				});
			} catch (GLib.IOError e) {
				if (e.code == GLib.IOError.CANCELLED) {
					// User cancelled - this is expected, don't throw
					return;
				}
				// Re-throw other IO errors
				throw e;
			}
		}

		private async void execute_non_streaming() throws Error
		{
			var bytes = yield this.send_request(true);
			var root = this.parse_response(bytes);

			if (root.get_node_type() != Json.NodeType.OBJECT) {
				throw new OllamaError.FAILED("Invalid JSON response");
			}

			// For non-streaming, emit the final chunk as progress
			var root_obj = root.get_object();
			this.progress_chunk(root_obj);
		}

		private Soup.Message create_streaming_message(string url, string request_body)
		{
			var message = new Soup.Message(this.http_method, url);

			if (this.client.connection.api_key != "") {
				message.request_headers.append("Authorization",
					"Bearer " + this.client.connection.api_key 
				);
			}

			message.set_request_body_from_bytes("application/json", new Bytes(request_body.data));
			return message;
		}
	}
}

