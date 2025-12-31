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
		 * @param response The pull progress response object
		 */
		public signal void progress_chunk(Response.Pull response);

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
		 * Processes streaming JSON chunks and emits progress_chunk signals for each update.
		 * The pull operation completes when done.
		 *
		 * @throws Error if the request fails or response is invalid
		 */
		public async void exec_pull() throws Error
		{
			var url = this.build_url();
			var request_body = this.get_request_body();
			var message = this.client.connection.soup_message(this.http_method, url, request_body);

			GLib.debug("Pull request URL: %s", url);
			GLib.debug("Pull request Body: %s", request_body);

			try {
				yield this.handle_streaming_response(message, (chunk) => {
					// Convert Json.Object to Response.Pull
					var chunk_node = new Json.Node(Json.NodeType.OBJECT);
					chunk_node.set_object(chunk);
					
					var response = Json.gobject_deserialize(typeof(Response.Pull), chunk_node) as Response.Pull;
					if (response == null) {
						GLib.warning("Failed to deserialize pull response chunk");
						return;
					}
					
					response.client = this.client;
					this.progress_chunk(response);
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
	}
}

