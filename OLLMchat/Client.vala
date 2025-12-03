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
	 */
	public class Client : Object
	{
		/**
		 * Base URL for the Ollama API endpoint.
		 * 
		 * Defaults to localhost:11434/api for local Ollama instances.
		 * Can be set to point to remote Ollama servers or OpenAI-compatible APIs.
		 * 
		 * @since 1.0
		 */
		public string url { get; set; default = "http://localhost:11434/api"; }
		
		/**
		 * API key for authentication (optional).
		 * 
		 * Used for authenticated API requests. Set to null if no authentication is required.
		 * 
		 * @since 1.0
		 */
		public string? api_key { get; set; }
		
		/**
		 * Model name to use for chat requests.
		 * 
		 * Required for chat operations. Must be a valid model name available on the Ollama server.
		 * See the Ollama API documentation for details.
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
		public Gee.HashMap<string, Tool.Interface> tools { get; set; default = new Gee.HashMap<string, Tool.Interface>(); }
		
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
		public OLLMchat.Prompt.BaseAgent prompt_assistant { get; set; default = new OLLMchat.Prompt.BaseAgent(); }
		
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
		 * These properties control various aspects of text generation behavior.
		 * Default values (-1 for numbers, empty string for strings) indicate no value set,
		 * and the option will not be included in API requests.
		 * See the Ollama API documentation for details on the options parameter.
		 */
		
		/**
		 * Random seed for reproducible outputs.
		 * 
		 * Set to -1 (default) to use random seed. Set to a positive integer for deterministic outputs.
		 * 
		 * @since 1.0
		 */
		public int seed { get; set; default = -1; }
		
		/**
		 * Temperature for sampling (0.0 to 1.0).
		 * 
		 * Controls randomness in output. Lower values make output more deterministic.
		 * Set to -1.0 (default) to use model default.
		 * 
		 * @since 1.0
		 */
		public double temperature { get; set; default = -1.0; }
		
		/**
		 * Top-p (nucleus) sampling parameter (0.0 to 1.0).
		 * 
		 * Controls diversity via nucleus sampling. Set to -1.0 (default) to use model default.
		 * 
		 * @since 1.0
		 */
		public double top_p { get; set; default = -1.0; }
		
		/**
		 * Top-k sampling parameter.
		 * 
		 * Limits sampling to the top k most likely tokens. Set to -1 (default) to use model default.
		 * 
		 * @since 1.0
		 */
		public int top_k { get; set; default = -1; }
		
		/**
		 * Maximum number of tokens to predict.
		 * 
		 * Limits the length of generated responses. Set to -1 (default) for no limit.
		 * 
		 * @since 1.0
		 */
		public int num_predict { get; set; default = -1; }
		
		/**
		 * Repeat penalty for reducing repetition.
		 * 
		 * Penalty applied to repeated tokens. Values > 1.0 reduce repetition.
		 * Set to -1.0 (default) to use model default.
		 * 
		 * @since 1.0
		 */
		public double repeat_penalty { get; set; default = -1.0; }
		
		/**
		 * Context window size.
		 * 
		 * Maximum number of tokens in the context window. Set to -1 (default) to use model default.
		 * 
		 * @since 1.0
		 */
		public int num_ctx { get; set; default = -1; }
		
		/**
		 * Stop sequences.
		 * 
		 * Comma-separated list of strings that will stop generation when encountered.
		 * Set to empty string (default) to use model default.
		 * 
		 * @since 1.0
		 */
		public string stop { get; set; default = ""; }
		
		/**
		 * HTTP request timeout in seconds.
		 * Default is 300 seconds (5 minutes) to accommodate long-running LLM requests.
		 * Set to 0 for no timeout (not recommended).
		 * 
		 * @since 1.0
		 */
		public uint timeout { get; set; default = 300; }

		public Client()
		{
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
		 * @param message The status message from the tool
		 * @param widget Optional widget parameter (default null). Expected to be a Gtk.Widget,
		 *               but typed as Object? since the Ollama base library should work without Gtk.
		 *               A cast will be needed when using this parameter in Gtk-based applications.
		 * @since 1.0
		 */
		public signal void tool_message(string message, Object? widget = null);

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
		public void addTool(Tool.Interface tool)
		{
			// Ensure tools HashMap is initialized
			tool.client = this;
			this.tools.set(tool.name,  tool);
		}

		public async Response.Chat chat(string text, GLib.Cancellable? cancellable = null) throws Error
		{
			// Create chat call
			var call = new Call.Chat(this) {
				cancellable = cancellable
			};
			
			// Fill chat call with prompts from prompt_assistant
			this.prompt_assistant.fill(call, text);
			
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
		 * Sets the model from the first running model on the server (ps()).
		 * 
		 * Only sets the model if it's not already configured (empty string).
		 * If running models are found and model is empty, sets this.model to the first model's name.
		 * If no running models are found or an error occurs, leaves model unchanged.
		 * 
		 * Note: Always uses model.name (not model.model) to ensure consistency.
		 * 
		 * @since 1.0
		 */
		public void set_model_from_ps()
		{
			// Don't override model if it's already set (e.g., from config)
			if (this.model != "") {
				return;
			}
			
			var main_loop = new MainLoop();
			Gee.ArrayList<Response.Model>? running_models = null;
			
			this.ps.begin((obj, res) => {
				try {
					running_models = this.ps.end(res);
					if (running_models.size > 0) {
						// Always use model.name for consistency (not model.model)
						this.model = running_models[0].name;
					}
				} catch (Error e) {
					GLib.warning("Failed to set model from ps(): %s", e.message);
				}
				main_loop.quit();
			});
			
			main_loop.run();
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
			GLib.debug("show_model: %s", model_name);
			
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
				GLib.debug("Loaded model '%s' from cache", model_name);
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
			var call = new Call.Embed(this) {
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
			var call = new Call.Embed(this) {
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

