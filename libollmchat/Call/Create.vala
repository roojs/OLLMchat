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
	 * API call to create a model using the Ollama create API endpoint.
	 *
	 * Creates a new model using the Ollama create API. This is a "dumb"
	 * implementation that simply performs the API call with the provided parameters.
	 * No logic about when to create or how to name - the caller provides all parameters.
	 *
	 * Supports all create API fields except messages. This call always streams
	 * status updates. See [[https://docs.ollama.com/api/create]] for the API specification.
	 *
	 * Used internally by Model.customize() to create temporary model variants
	 * when custom num_ctx settings are needed.
	 */
	public class Create : Base
	{
		/**
		 * Name for the model to create (required).
		 *
		 * This is the identifier that will be used to reference the created model.
		 */
		public string model { get; set; default = ""; }
		
		/**
		 * Existing model to create from.
		 *
		 * The base model to use as the foundation for the new model.
		 * Equivalent to "FROM" in a Modelfile.
		 */
		public string from { get; set; default = ""; }
		
		/**
		 * Prompt template to use for the model.
		 *
		 * The template that defines how prompts are formatted for this model.
		 * Equivalent to "TEMPLATE" in a Modelfile.
		 */
		public string template { get; set; default = ""; }
		
		/**
		 * License string or array of licenses for the model.
		 *
		 * Can be a single license string or an array of license strings.
		 * Equivalent to "LICENSE" in a Modelfile.
		 */
		public string license { get; set; default = ""; }
		
		/**
		 * System prompt to embed in the model.
		 *
		 * The system message that will be automatically included in conversations.
		 * Equivalent to "SYSTEM" in a Modelfile.
		 */
		public string system { get; set; default = ""; }
		
		/**
		 * Key-value parameters for the model.
		 *
		 * Parameters like num_ctx, temperature, etc. as an Options object.
		 * Serializes automatically with proper key conversion for Ollama API.
		 * Equivalent to "PARAMETER" directives in a Modelfile.
		 */
		public Options parameters { get; set; default = new Options(); }
		
		/**
		 * Quantization level to apply.
		 *
		 * Examples: "q4_K_M", "q8_0", etc.
		 * Equivalent to "QUANTIZE" in a Modelfile.
		 */
		public string quantize { get; set; default = ""; }
		
		/**
		 * Whether to stream status updates.
		 *
		 * Defaults to true.
		 */
		public bool stream { get; set; default = true; }

		/**
		 * Signal emitted when a progress chunk is received during create.
		 *
		 * @param response The create progress response object
		 */
		public signal void progress_chunk(Response.Create response);

		/**
		 * Creates a new Create API call instance.
		 *
		 * @param connection The connection settings for the API endpoint
		 * @param model_name The name for the model to create (required)
		 * @throws OllmError.INVALID_ARGUMENT if model_name is empty
		 */
		public Create(Settings.Connection connection, string model_name)
		{
			base(connection);
			if (model_name == "") {
				throw new OllmError.INVALID_ARGUMENT("Model name cannot be empty");
			}
			this.model = model_name;
			this.url_endpoint = "create";
			this.http_method = "POST";
		}

		/**
		 * Executes the create API call.
		 *
		 * Processes streaming JSON chunks and emits progress_chunk signals for each update.
		 * The create operation completes when done.
		 *
		 * @throws Error if the request fails or response is invalid
		 */
		public async void exec_create() throws Error
		{
			var url = this.build_url();
			var request_body = this.get_request_body();
			var message = this.connection.soup_message(this.http_method, url, request_body);

			GLib.debug("Create request URL: %s", url);
			GLib.debug("Create request Body: %s", request_body);

			try {
				yield this.handle_streaming_response(message, (chunk) => {
					// Convert Json.Object to Response.Create
					var chunk_node = new Json.Node(Json.NodeType.OBJECT);
					chunk_node.set_object(chunk);
					
					var response = Json.gobject_deserialize(typeof(Response.Create), chunk_node) as Response.Create;
					if (response == null) {
						GLib.warning("Failed to deserialize create response chunk");
						return;
					}
					
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

		/**
		 * Custom serialization - whitelist approach.
		 */
		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "model":
					// Always serialize model (required)
					return default_serialize_property(property_name, value, pspec);
				case "from":
				case "template":
				case "license":
				case "system":
				case "quantize":
					// String properties - exclude if empty
					if (value.get_string() == "") {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				case "parameters":
					// Only serialize parameters if they have valid values
					if (!this.parameters.has_values()) {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				case "stream":
					// Always serialize stream (bool)
					return default_serialize_property(property_name, value, pspec);
				default:
					// Exclude all other properties
					return null;
			}
		}
	}
}
