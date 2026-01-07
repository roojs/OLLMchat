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
	 * var client = new Client(connection) {
	 *     model = "llama3.2",
	 *     stream = true
	 * };
	 *
	 * var response = yield client.chat("Hello!");
	 * }}}
	 *
	 * == Tool Integration ==
	 *
	 * {{{
	 * // Add tools before chatting
	 * var read_file = new Tools.ReadFile(client);
	 * client.addTool(read_file);
	 *
	 * // Tools are automatically called when the model requests them
	 * var response = yield client.chat("Read README.md");
	 * }}}
	 *
	 * == Streaming ==
	 *
	 * {{{
	 * client.stream = true;
	 * client.message_created.connect((msg, content) => {
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
		
		/**
		 * Configuration settings (Config2 instance).
		 *
		 * Contains all configuration including connections, model_options, and usage map.
		 *
		 * @since 1.0
		 */
		public Settings.Config2? config { get; set; }
		
		/**
		 * Model name to use for chat requests.
		 *
		 * Set by caller after constructor from Config2's usage map if needed.
		 *
		 * @since 1.0
		 */
		public string model { get; set; default = ""; }

		
		/**
		 * Whether to stream responses from the API.
		 *
		 * When true, responses are streamed incrementally as they are generated.
		 * When false, the complete response is returned after generation finishes.
		 * Defaults to false. See the Ollama API documentation for details.
		 *
		 * @since 1.0
		 */
		public bool stream { get; set; default = false; }
		
		/**
		 * Format to return a response in.
		 *
		 * Can be "json" to force JSON output, or a JSON schema object for structured output.
		 * Set to null to use the model's default format.
		 * See the Ollama API documentation for details.
		 *
		 * @since 1.0
		 */
		public string? format { get; set; }
		
		/**
		 * Whether to return separate thinking output in addition to content.
		 *
		 * When true, returns thinking content separately from regular content.
		 * Can be a boolean (true/false) or a string ("high", "medium", "low") for supported models.
		 * Defaults to false. See the Ollama API documentation for details.
		 *
		 * @since 1.0
		 */
		public bool think { get; set; default = false; }
		
		/**
		 * Model keep-alive duration.
		 *
		 * Controls how long the model stays loaded in memory after use.
		 * Can be a duration string (e.g., "5m", "10s") or a number in seconds.
		 * Set to "0" to unload immediately after use.
		 * See the Ollama API documentation for details.
		 *
		 * @since 1.0
		 */
		public string? keep_alive { get; set; }
		
		/**
		 * Map of available tools (functions) that the model can call during chat.
		 *
		 * Tools are indexed by their name. The model can request to call these tools
		 * during conversation, and they will be executed with permission checking.
		 * See the Ollama API documentation for details on tools parameter.
		 *
		 * @since 1.0
		 */
		public Gee.HashMap<string, Tool.BaseTool> tools { get; set; default = new Gee.HashMap<string, Tool.BaseTool>(); }
		
		/**
		 * Current streaming response object (internal use).
		 *
		 * Used internally to track the streaming state during chat operations.
		 * Also accessed by OLLMchatGtk for UI updates. Set to null when not streaming.
		 *
		 * @since 1.0
		 */
		public Response.Chat? streaming_response { get; set; default = null; }
		
		/**
		 * Prompt generator for agent-based conversations.
		 *
		 * Used to generate system and user prompts for chat requests.
		 * Defaults to a basic BaseAgent instance.
		 *
		 * @since 1.0
		 */
		public Prompt.BaseAgent prompt_assistant { get; set; default = new Prompt.BaseAgent(); }
		
		/**
		 * Permission provider for tool execution.
		 *
		 * Handles permission requests when tools need to access files or execute commands.
		 * Defaults to a Dummy provider that logs requests.
		 *
		 * @since 1.0
		 */
		public OLLMchat.ChatPermission.Provider permission_provider { get; set; default = new OLLMchat.ChatPermission.Dummy(); }
	
		/**
		 * Runtime options for text generation.
		 *
		 * Contains all runtime parameters that can be passed to Ollama API.
		 * Default values (-1 for numbers, empty string for strings) indicate no value set,
		 * and the option will not be included in API requests.
		 * See the Ollama API documentation for details on the options parameter.
		 *
		 * @since 1.0
		 */
		public Call.Options options { get; set; default = new Call.Options(); }
		
		/**
		 * HTTP request timeout in seconds.
		 * Default is 300 seconds (5 minutes) to accommodate long-running LLM requests.
		 * Set to 0 for no timeout (not recommended).
		 *
		 * @since 1.0
		 */
		public uint timeout { get; set; default = 300; }

		/**
		 * Optional ConnectionModels instance for looking up model information.
		 * Set by Manager when creating clients. Temporary solution until Client is removed.
		 */
		public Settings.ConnectionModels? connection_models { get; set; default = null; }

		public Client(Settings.Connection connection)
		{
			this.connection = connection;
		}



		/**
		 * Emitted when a streaming chunk is received from the chat API.
		 *
		 * @param new_text The new text chunk received
		 * @param is_thinking Whether this chunk is thinking content (true) or regular content (false)
		 * @param response The Response object containing the streaming state
		 * @since 1.0
		 */
		public signal void stream_chunk(string new_text, bool is_thinking, Response.Chat response);

		/**
		 * Emitted when streaming content (not thinking) is received from the chat API.
		 *
		 * This signal is emitted only for regular content chunks, not thinking content.
		 * Tools can connect to this signal to capture streaming messages and build strings,
		 * including extracting code blocks as they arrive.
		 *
		 * @param new_text The new content text chunk received (not thinking)
		 * @param response The Response.Chat object containing the streaming state
		 * @since 1.0
		 */
		public signal void stream_content(string new_text, Response.Chat response);

		/**
		 * Emitted when a tool sends a status message during execution.
		 *
		 * @param message The Message object from the tool (typically "ui" role)
		 * @since 1.0
		 */
		public signal void tool_message(Message message);

		/**
		 * Emitted when a chat request is sent to the server.
		 * This signal is emitted when the request is about to be sent, including
		 * initial chat requests and automatic continuations after tool execution.
		 *
		 * @param chat The Call.Chat object that is being sent
		 * @since 1.0
		 */
		public signal void chat_send(Call.Chat chat);

		/**
		 * Emitted when the streaming response starts (first chunk received).
		 * This signal is emitted when the first chunk of the response is processed,
		 * indicating that the server has started sending data back.
		 *
		 * @since 1.0
		 */
		public signal void stream_start();

		/**
		 * Emitted when a message is created in the conversation.
		 * This signal is the primary driver for message creation events, used for
		 * both persistence (Manager) and UI display. Messages are created before
		 * prompt engine modification to preserve original user text.
		 *
		 * @param m The Message object that was created
		 * @param content_interface The ChatContentInterface associated with this message (e.g., Response.Chat for assistant messages)
		 * @since 1.0
		 */
		public signal void message_created(Message m, ChatContentInterface? content_interface);

		public Soup.Session? session = null;

		/**
		* Available models loaded from the server, keyed by model name.
		*
		* This map is populated by calling fetch_all_model_details().
		*
		* @since 1.0
		*/
		public Gee.HashMap<string, Response.Model> available_models { get; private set; 
			default = new Gee.HashMap<string, Response.Model>(); }

		/**
		* Adds a tool to the client's tools map.
		*
		* Adds the tool to the tools hashmap keyed by tool name. The tool's client is set via constructor.
		*
		* @param tool The tool to add
		*/
		public void addTool(Tool.BaseTool tool)
		{
			tool.client = this;
			this.tools.set(tool.name,  tool);
		}

		public async Response.Chat chat(string text, GLib.Cancellable? cancellable = null) throws Error
		{
			// Create chat call
			var call = new Call.Chat(this, this.model) {
				cancellable = cancellable
			};
			
			// Create dummy user-sent Message with original text BEFORE prompt engine modification
			var user_sent_msg = new Message(call, "user-sent", text);
			this.message_created(user_sent_msg, call);
			
			// Fill chat call with prompts from prompt_assistant (modifies chat_content)
			this.prompt_assistant.fill(call, text);
			
			// If system_content is set, create system Message and emit message_created
			if (call.system_content != "") {
				var system_msg = new Message(call, "system", call.system_content);
				this.message_created(system_msg, call);
			}
			
			var result = yield call.exec_chat();

			return result;
		}

		public async Gee.ArrayList<Response.Model> models() throws Error
		{
			var call = new Call.Models(this);
			var result = yield call.exec_models();
			// in theory we should make a list of models that we have and delete if they are
			// not there anymore..
			// Populate available_models with the models from the list
			foreach (var model in result) {
				if (this.available_models.has_key(model.name)) {
					continue;
				}
				this.available_models.set(model.name, model);
			}
			
			return result;
		}

		public async Gee.ArrayList<Response.Model> ps() throws Error
		{
			var call = new Call.Ps(this);
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
			var original_timeout = this.timeout;
			this.timeout = 10;  // 10 seconds - version check should be quick
			
			try {
				var call = new OLLMchat.Call.Version(this) {
					cancellable = cancellable
				};
				var result = yield call.exec_version();
				return result;
			} finally {
				// Restore original timeout
				this.timeout = original_timeout;
			}
		}



		/**
		* Gets detailed information about a specific model including capabilities and stores it in available_models.
		*
		* If the model already exists in available_models, it will be updated with the new data using updateFrom().
		* Otherwise, the new model will be added to available_models.
		*
		* Checks cache first, and saves to cache after fetching from API.
		*
		* @param model_name The name of the model to get details for
		* @return Model object with full details including capabilities
		* @since 1.0
		*/
		public async Response.Model show_model(string model_name) throws Error
		{
			//GLib.debug("show_model: %s", model_name);
			
			// Check if model already exists in available_models
			Response.Model model;
			if (this.available_models.has_key(model_name)) {
				model = this.available_models.get(model_name);
			} else {
				// Create new model instance
				model = new Response.Model(this);
				model.name = model_name;
				this.available_models.set(model_name, model);
			}
			
			// Try to load from cache first
			if (model.load_from_cache()) {
				//GLib.debug("show_model: Loaded model '%s' from cache, parameters: '%s'", model_name, model.parameters ?? "(null)");
				return model;
			}
			
			// Not in cache, fetch from API
			var result = yield new Call.ShowModel(this, model_name).exec_show();
			
			// Update model with API result
			model.updateFrom(result);
			
			// Save to cache
			model.save_to_cache();
			
			return model;
		}

		/**
		* Fetches detailed information for all available models and populates available_models.
		*
		* This method calls models() to get the list of models, then calls show_model()
		* for each model to get full details including capabilities. The results are
		* stored in available_models HashMap keyed by model name.
		*
		* @since 1.0
		*/
		public async void fetch_all_model_details() throws Error
		{
			
			var models_list = yield this.models();
			//this.available_models.clear(); // why clear this.models sets it?
			
			foreach (var model in models_list) {
				try {
					var detailed_model = yield this.show_model(model.name);
					// Preserve size from the initial models() call if show_model didn't return it
					if (detailed_model.size == 0 && model.size != 0) {
						detailed_model.size = model.size;
					}
				} catch (Error e) {
					GLib.warning("Failed to get details for model %s: %s", model.name, e.message);
					// Skip this model on error
				}
			}
		}

		/**
		 * Generates embeddings for the input text.
		 *
		 * Creates vector embeddings representing the input text using the configured model.
		 * Returns a single Response.Embed object containing the embeddings and metadata.
		 *
		 * @param input The text to generate embeddings for
		 * @param dimensions Optional number of dimensions to generate embeddings for (default: -1, not set)
		 * @param truncate Optional whether to truncate inputs that exceed context window (default: false)
		 * @param cancellable Optional cancellable for cancelling the request
		 * @return Response.Embed object with embeddings and timing information
		 * @since 1.0
		 */
		public async Response.Embed embed(
		string input,
			int dimensions = -1,
			bool truncate = false,
			GLib.Cancellable? cancellable = null
		) throws Error
		{
			var call = new Call.Embed(this, this.model, new Call.Options()) {
				cancellable = cancellable,
				input = input,
				dimensions = dimensions,
				truncate = truncate
			};
			
			var result = yield call.exec_embed();
			
			return result;
		}

		/**
		 * Generates embeddings for an array of input texts.
		 *
		 * Creates vector embeddings representing the input texts using the configured model.
		 * Returns a single Response.Embed object containing the embeddings and metadata.
		 *
		 * @param input_array The array of texts to generate embeddings for
		 * @param dimensions Optional number of dimensions to generate embeddings for (default: -1, not set)
		 * @param truncate Optional whether to truncate inputs that exceed context window (default: false)
		 * @param cancellable Optional cancellable for cancelling the request
		 * @return Response.Embed object with embeddings and timing information
		 * @since 1.0
		 */
		public async Response.Embed embed_array(
			Gee.ArrayList<string> input_array,
			int dimensions = -1,
			bool truncate = false,
			GLib.Cancellable? cancellable = null
		) throws Error
		{
			var call = new Call.Embed(this, this.model, new Call.Options()) {
				cancellable = cancellable,
				input_array = input_array,
				dimensions = dimensions,
				truncate = truncate
			};
			
			var result = yield call.exec_embed();
			
			return result;
		}

		/**
		 * Generates a response for the provided prompt.
		 *
		 * Uses the /api/generate endpoint to generate a response without maintaining
		 * conversation history. This is useful for simple prompt-response scenarios.
		 *
		 * @param prompt The text prompt to generate a response for
		 * @param system Optional system prompt
		 * @param cancellable Optional cancellable for cancelling the request
		 * @return Response.Generate object with the generated response and metadata
		 * @since 1.0
		 */
		public async Response.Generate generate(
			string prompt,
			string system = "",
			GLib.Cancellable? cancellable = null
		) throws Error
		{
			var call = new Call.Generate(this) {
				cancellable = cancellable,
				prompt = prompt,
				system = system
			};
			
			var result = yield call.exec_generate();
			
			return result;
		}
	}
}

