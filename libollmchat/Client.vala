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

namespace OLLMchat
{
	/**
	 * Main client class for interacting with Ollama API and OpenAI-compatible REST interfaces.
	 *
	 * Provides methods for chat, model management, and tool integration. Handles
	 * HTTP requests, streaming responses, and function calling. Manages tool
	 * registration and execution with permission checking.
	 *
	* == Basic Usage ==
	*
	* {{{
	* var connection = new Settings.Connection() {
	*     url = "http://127.0.0.1:11434/api"
	* };
	* var client = new Client(connection);
	* var chat = new Call.Chat(client, "llama3.2") {
	*     stream = true
	* };
	* chat.messages.add(new Message(chat, "user", "Hello!"));
	* var response = yield chat.send(chat.messages);
	* }}}
	 *
 * == Tool Integration ==
 *
 * {{{
 * // Add tools to Chat before chatting
 * var read_file = new Tools.ReadFile(client);
 * var chat = new Call.Chat(client, "llama3.2");
 * chat.add_tool(read_file);
 *
 * // Tools are automatically called when the model requests them
 * chat.messages.add(new Message(chat, "user", "Read README.md"));
 * var response = yield chat.send(chat.messages);
 * }}}
 *
 * == Streaming ==
 *
 * {{{
 * var chat = new Call.Chat(client, "llama3.2") {
 *     stream = true
 * };
 * chat.message_created.connect((msg, content) => {
 *     if (msg.is_content && msg.is_stream) {
 *         // Process incremental content
 *         print(content.chat_content);
 *     }
 * });
 * }}}
	 */
	public class Client : Object
	{
		/**
		 * Connection configuration for this client.
		 *
		 * Contains URL, API key, and connection settings.
		 *
		 * @since 1.0
		 */
		public Settings.Connection connection { get; set; }
		
		

		public Client(Settings.Connection connection)
		{
			this.connection = connection;
		}
		/**
		 * Executes a pre-prepared Chat object.
		 * 
		 * The Chat object should already have its messages array prepared
		 * by the agent/handler. This method simply executes the chat request.
		 * 
		 * @param call The pre-prepared Chat object to execute
		 * @return The Response from executing the chat call
		 */
		public async Response.Chat chat_execute(Call.Chat call) throws Error
		{
			// Client does NOT modify messages array - use what agent prepared
			return yield call.send(call.messages, call.cancellable);
		}

		/**
		 * Legacy chat method for backward compatibility.
		 * 
		 * Creates a basic Chat object with the user text and executes it.
		 * No prompt generation is performed - the text is used as-is.
		 * For agent-based conversations, use AgentHandler instead.
		 * 
		 * Note: This method does NOT handle system messages - that's the agent's job.
		 * This is a minimal implementation for backward compatibility only.
		 * 
		 * @param model The model name to use for the chat
		 * @param text The user's input text
		 * @param options Optional Call.Options for the chat request
		 * @param cancellable Optional cancellable for cancelling the request
		 * @return The Response from executing the chat call
		 */
		public async Response.Chat chat(
			string model,
			string text,
			Call.Options? options = null,
			GLib.Cancellable? cancellable = null
		) throws Error
		{
			if (model == "") {
				throw new OllamaError.INVALID_ARGUMENT("Client.chat() requires a model parameter.");
			}
			// Create chat call with defaults (Phase 3: no Client properties)
			var call = new Call.Chat(this.connection, model) {
				cancellable = cancellable,
				stream = true,  // Default to non-streaming for legacy method
				think = true
			};
			call.options =  options == null ? new Call.Options() : options; 
			// Create dummy user-sent Message with original text
			var user_sent_msg = new Message(call, "user-sent", text);
			// message_created signal emission removed - callers handle state directly when creating messages
			
			// Set chat_content to user text (no prompt generation)
			call.chat_content = text;
			
			// Prepare messages array for API request
			// Agent/handler should prepare system messages - this is just for backward compatibility
			// Add the user message with chat_content (for API request)
			call.messages.add(new Message(call, "user", call.chat_content));
			
			var result = yield call.send(call.messages, cancellable);

			return result;
		}

		public async Gee.ArrayList<Response.Model> models() throws Error
		{
			var call = new Call.Models(this.connection);
			var result = yield call.exec_models();
			return result;
		}

		public async Gee.ArrayList<Response.Model> ps() throws Error
		{
			var call = new Call.Ps(this.connection);
			var result = yield call.exec_models();
			return result;
		}

		/**
		 * Gets the version of the Ollama server.
		 *
		 * Calls the /api/version endpoint to retrieve the server version.
		 * Useful for verifying connectivity during bootstrap.
		 * Uses a short timeout (10 seconds) since version checks should be quick.
		 *
		 * @param cancellable Optional cancellable for cancelling the request
		 * @return Version string from the server (e.g., "0.12.6")
		 * @throws Error if the request fails or response is invalid
		 * @since 1.0
		 */
		public async string version(GLib.Cancellable? cancellable = null) throws Error
		{
			// Save original timeout and set short timeout for version check
			var original_timeout = this.connection.timeout;
			this.connection.timeout = 10;  // 10 seconds - version check should be quick
			
			try {
				var call = new OLLMchat.Call.Version(this.connection) {
					cancellable = cancellable
				};
				var result = yield call.exec_version();
				return result;
			} finally {
				// Restore original timeout
				this.connection.timeout = original_timeout;
			}
		}



		/**
		* Gets detailed information about a specific model including capabilities.
		*
		* @param model_name The name of the model to get details for
		* @return Model object with full details including capabilities
		* @since 1.0
		*/
		public async Response.Model show_model(string model_name) throws Error
		{
			return yield new Call.ShowModel(this.connection, model_name).exec_show();
		}


		/**
		 * Generates embeddings for the input text.
		 *
		 * Creates vector embeddings representing the input text using the specified model.
		 * Returns a single Response.Embed object containing the embeddings and metadata.
		 *
		 * @param model The model name to use for generating embeddings
		 * @param input The text to generate embeddings for
		 * @param dimensions Optional number of dimensions to generate embeddings for (default: -1, not set)
		 * @param truncate Optional whether to truncate inputs that exceed context window (default: false)
		 * @param options Optional Call.Options for the embed request
		 * @param cancellable Optional cancellable for cancelling the request
		 * @return Response.Embed object with embeddings and timing information
		 * @since 1.0
		 */
		public async Response.Embed embed(
			string model,
			string input,
			int dimensions = -1,
			bool truncate = false,
			Call.Options? options = null,
			GLib.Cancellable? cancellable = null
		) throws Error
		{
			if (model == "") {
				throw new OllamaError.INVALID_ARGUMENT("Client.embed() requires a model parameter.");
			}
			var call = new Call.Embed(this.connection, model) {
				cancellable = cancellable,
				input = input,
				dimensions = dimensions,
				truncate = truncate
			};
			call.options = options == null ? new Call.Options() : options;
			
			var result = yield call.exec_embed();
			
			return result;
		}

		/**
		 * Generates embeddings for an array of input texts.
		 *
		 * Creates vector embeddings representing the input texts using the specified model.
		 * Returns a single Response.Embed object containing the embeddings and metadata.
		 *
		 * @param model The model name to use for generating embeddings
		 * @param input_array The array of texts to generate embeddings for
		 * @param dimensions Optional number of dimensions to generate embeddings for (default: -1, not set)
		 * @param truncate Optional whether to truncate inputs that exceed context window (default: false)
		 * @param options Optional Call.Options for the embed request
		 * @param cancellable Optional cancellable for cancelling the request
		 * @return Response.Embed object with embeddings and timing information
		 * @since 1.0
		 */
		public async Response.Embed embed_array(
			string model,
			Gee.ArrayList<string> input_array,
			int dimensions = -1,
			bool truncate = false,
			Call.Options? options = null,
			GLib.Cancellable? cancellable = null
		) throws Error
		{
			if (model == "") {
				throw new OllamaError.INVALID_ARGUMENT("Client.embed_array() requires a model parameter.");
			}
			var call = new Call.Embed(this.connection, model) {
				cancellable = cancellable,
				input_array = input_array,
				dimensions = dimensions,
				truncate = truncate
			};
			call.options = options == null ? new Call.Options() : options;
			
		var result = yield call.exec_embed();
			
			return result;
		}

		/**
		 * Generates a response for the provided prompt.
		 *
		 * Uses the /api/generate endpoint to generate a response without maintaining
		 * conversation history. This is useful for simple prompt-response scenarios.
		 *
		 * @param model The model name to use for generation
		 * @param prompt The text prompt to generate a response for
		 * @param system Optional system prompt
		 * @param options Optional Call.Options for the generate request
		 * @param cancellable Optional cancellable for cancelling the request
		 * @return Response.Generate object with the generated response and metadata
		 * @since 1.0
		 */
		public async Response.Generate generate(
			string model,
			string prompt,
			string system = "",
			Call.Options? options = null,
			GLib.Cancellable? cancellable = null
		) throws Error
		{
			if (model == "") {
				throw new OllamaError.INVALID_ARGUMENT("Client.generate() requires a model parameter.");
			}
			var call = new Call.Generate(this.connection) {
				cancellable = cancellable,
				prompt = prompt,
				system = system,
				model = model,
				stream = false,
				think = false
			};
			call.options = options == null ? new Call.Options() : options;
			
			var result = yield call.exec_generate();
			
			return result;
		}
	}
}

