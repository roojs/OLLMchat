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

namespace OLLMchat.Ollama
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
		public string url { get; set; default = "http://localhost:11434/api"; }
		public string? api_key { get; set; }
		public string model { get; set; default = ""; }
		public bool stream { get; set; default = false; }
		public string? format { get; set; }
		public Json.Object? options { get; set; }
		public bool think { get; set; default = false; }
		public string? keep_alive { get; set; }
		public Gee.HashMap<string, Tool> tools { get; set; default = new Gee.HashMap<string, Tool>(); }
		public ChatResponse? streaming_response { get; set; default = null; }
		public Prompt.BaseAgentPrompt prompt_assistant { get; set; default = new Prompt.BaseAgentPrompt(); }
		public ChatPermission.Provider permission_provider { get; set; default = new ChatPermission.Dummy(); }
		
		/**
		 * HTTP request timeout in seconds.
		 * Default is 300 seconds (5 minutes) to accommodate long-running LLM requests.
		 * Set to 0 for no timeout (not recommended).
		 * 
		 * @since 1.0
		 */
		public uint timeout { get; set; default = 300; }

		/**
		 * Emitted when a streaming chunk is received from the chat API.
		 * 
		 * @param new_text The new text chunk received
		 * @param is_thinking Whether this chunk is thinking content (true) or regular content (false)
		 * @param response The ChatResponse object containing the streaming state
		 * @since 1.0
		 */
		public signal void stream_chunk(string new_text, bool is_thinking, ChatResponse response);

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
		 * Emitted when a request is about to be sent to the server.
		 * This signal is emitted at the start of any API request, including
		 * initial chat requests and automatic continuations after tool execution.
		 * 
		 * @since 1.0
		 */
		public signal void send_starting();

		public Soup.Session? session = null;

		/**
		* Available models loaded from the server, keyed by model name.
		* 
		* This map is populated by calling fetch_all_model_details().
		* 
		* @since 1.0
		*/
		public Gee.HashMap<string, Model> available_models { get; private set; 
			default = new Gee.HashMap<string, Model>(); }

		/**
		* Adds a tool to the client's tools map.
		* 
		* Adds the tool to the tools hashmap keyed by tool name. The tool's client is set via constructor.
		* 
		* @param tool The tool to add
		*/
		public void addTool(Tool tool)
		{
			// Ensure tools HashMap is initialized
			tool.client = this;
			this.tools.set(tool.name,  tool);
		}

		public async ChatResponse chat(string text, GLib.Cancellable? cancellable = null) throws Error
		{
			// Create chat call
			var call = new ChatCall(this) {
				cancellable = cancellable
			};
			
			// Fill chat call with prompts from prompt_assistant
			this.prompt_assistant.fill(call, text);
			
			var result = yield call.exec_chat();

			return result;
		}

		public async Gee.ArrayList<Model> models() throws Error
		{
			var call = new ModelsCall(this);
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

		public async Gee.ArrayList<Model> ps() throws Error
		{
			var call = new PsCall(this);
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
			Gee.ArrayList<Model>? running_models = null;
			
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
		public async Model show_model(string model_name) throws Error
		{
			GLib.debug("show_model: %s", model_name);
			
			// Check if model already exists in available_models
			Model model;
			if (this.available_models.has_key(model_name)) {
				model = this.available_models.get(model_name);
			} else {
				// Create new model instance
				model = new Model(this);
				model.name = model_name;
				this.available_models.set(model_name, model);
			}
			
			// Try to load from cache first
			if (model.load_from_cache()) {
				GLib.debug("Loaded model '%s' from cache", model_name);
				return model;
			}
			
			// Not in cache, fetch from API
			var result = yield new ShowModelCall(this, model_name).exec_show();
			
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
		 * Returns a single EmbedResponse object containing the embeddings and metadata.
		 * 
		 * @param input The text to generate embeddings for
		 * @param cancellable Optional cancellable for cancelling the request
		 * @return EmbedResponse object with embeddings and timing information
		 * @since 1.0
		 */
		public async EmbedResponse embed(string input, GLib.Cancellable? cancellable = null) throws Error
		{
			var call = new EmbedCall(this, input) {
				cancellable = cancellable
			};
			
			var result = yield call.exec_embed();
			
			return result;
		}
	}
}

