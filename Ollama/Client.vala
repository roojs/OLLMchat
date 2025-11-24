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
			
			// Populate available_models with the models from the list
			foreach (var model in result) {
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
		* Gets detailed information about a specific model including capabilities and stores it in available_models.
		* 
		* If the model already exists in available_models, it will be updated with the new data using updateFrom().
		* Otherwise, the new model will be added to available_models.
		* 
		* @param model_name The name of the model to get details for
		* @return Model object with full details including capabilities
		* @since 1.0
		*/
		public async Model show_model(string model_name) throws Error
		{
			var result = yield new ShowModelCall(this, model_name).exec_show();
			
			// Check if model already exists in available_models
			if (this.available_models.has_key(result.name)) {
				// Update existing model with new data
				this.available_models.get(result.name).updateFrom(result);
				return this.available_models.get(result.name);
			}
				// Add new model to available_models
			this.available_models.set(result.name, result);
			return result;
			
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
			this.available_models.clear();
			
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
	}
}

