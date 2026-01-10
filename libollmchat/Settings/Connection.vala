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

namespace OLLMchat.Settings
{
	/**
	 * Represents a single server connection configuration.
	 *
	 * Stores connection details for Ollama or OpenAI-compatible API servers.
	 * Used by Client to establish API connections.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var connection = new Settings.Connection() {
	 *     name = "Local Ollama",
	 *     url = "http://127.0.0.1:11434/api",
	 *     is_default = true
	 * };
	 *
	 * var client = new Client(connection);
	 * }}}
	 *
	 * @since 1.0
	 */
	public class Connection : Object, Json.Serializable
	{
		/**
		 * Connection alias/name (e.g., "Local Ollama", "OpenAI", "Remote Server")
		 */
		public string name { get; set; default = ""; }
		
		/**
		 * Server URL (e.g., http:\/\/127.0.0.1:11434\/api)
		 */
		public string url { get; set; default = ""; }
		
		/**
		 * Optional API key for authentication
		 */
		public string api_key { get; set; default = ""; }
		
		/**
		 * Whether this is the default connection
		 */
		public bool is_default { get; set; default = false; }
		
		/**
		 * Whether this connection is currently working (version check passed).
		 * Not saved to config - checked on dialog close.
		 */
		public bool is_working = true;
		
		/**
		 * List of model names to hide from the UI
		 */
		public Gee.ArrayList<string> hidden_models { get; set; default = new Gee.ArrayList<string>(); }

		/**
		 * HTTP session for making requests.
		 * 
		 * Shared across all Clients using this Connection (connection pooling).
		 * Initialized via init() method (called in constructor and after deserialization).
		 * Non-serialized field (runtime state, not saved to config).
		 * 
		 * @since 1.2.3
		 */
		public Soup.Session soup;

		/**
		 * HTTP request timeout in seconds.
		 * 
		 * Default is 300 seconds (5 minutes) to accommodate long-running LLM requests.
		 * Set to 0 for no timeout (not recommended).
		 * Aliases soup.timeout - reading/writing this property reads/writes soup.timeout.
		 * Non-serialized property (runtime state, not saved to config).
		 * 
		 * @since 1.2.3
		 */
		public uint timeout {
			get { return this.soup.timeout; }
			set { this.soup.timeout = value; }
		}

		/**
		 * Models loaded from the server, keyed by model name.
		 *
		 * This map is populated by calling load_models().
		 * Non-serialized property (runtime cache, not saved to config).
		 *
		 * @since 1.2.7.11
		 */
		public Gee.HashMap<string, OLLMchat.Response.Model> models { get; private set; 
			default = new Gee.HashMap<string, OLLMchat.Response.Model>(); }

		/**
		 * Initializes runtime state (soup session).
		 * 
		 * Must be called after deserialization from JSON to ensure soup is initialized.
		 * Called automatically in constructor.
		 * 
		 * @since 1.2.3
		 */
		public void init()
		{
			this.soup = new Soup.Session();
			this.timeout = 300; // Default timeout
		
		}

		/**
		 * Default constructor.
		 */
		public Connection()
		{
			this.init();
		}

		/**
		 * Creates a clone of this Connection object with all properties copied.
		 *
		 * @return A new Connection instance with all properties copied from this object
		 */
		public Connection clone()
		{
			var new_obj = new Connection();
			
			foreach (unowned ParamSpec pspec in this.get_class().list_properties()) {
				var value = this.get_property(pspec);
				new_obj.set_property(pspec, value);
			}
			
			return new_obj;
		}

		public unowned ParamSpec? find_property(string name)
		{
			return this.get_class().find_property(name);
		}

		public new void Json.Serializable.set_property(ParamSpec pspec, Value value)
		{
			base.set_property(pspec.get_name(), value);
		}

		public new Value Json.Serializable.get_property(ParamSpec pspec)
		{
			Value val = Value(pspec.value_type);
			base.get_property(pspec.get_name(), ref val);
			return val;
		}

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "hidden-models":
					// Serialize hidden_models list as a JSON array
					var array_node = new Json.Node(Json.NodeType.ARRAY);
					array_node.init_array(new Json.Array());
					var json_array = array_node.get_array();
					foreach (var model in this.hidden_models) {
						json_array.add_string_element(model);
					}
					return array_node;
				case "soup":
				case "timeout":
				case "models":
					// Exclude runtime properties from serialization
					return null;
			}
			return default_serialize_property(property_name, value, pspec);
		}

		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			switch (property_name) {
				case "hidden-models":
					// Deserialize hidden_models from JSON array
					if (property_node.get_node_type() != Json.NodeType.ARRAY) {
						break;
					}
					
					var json_array = property_node.get_array();
					json_array.foreach_element((array, index, node) => {
						if (node.get_value_type() == typeof(string)) {
							this.hidden_models.add(node.get_string());
						}
					});
					
					// Return the hidden_models list as the value
					value = Value(typeof(Gee.ArrayList));
					value.set_object(this.hidden_models);
					return true;
			}
			return default_deserialize_property(property_name, out value, pspec, property_node);
		}

		/**
		 * Creates a Soup.Message with authorization headers set.
		 *
		 * Creates a new HTTP message with the specified method and URL, and automatically
		 * adds the Authorization header if an API key is configured.
		 *
		 * @param method HTTP method (e.g., "GET", "POST")
		 * @param url Full URL for the request
		 * @param body Optional request body string (will be set as JSON content type)
		 * @return A new Soup.Message with authorization headers configured
		 */
		public Soup.Message soup_message(string method, string url, string? body = null)
		{
			var message = new Soup.Message(method, url);

			if (this.api_key != "") {
				message.request_headers.append("Authorization",
					"Bearer " + this.api_key 
				);
			}

			if (body != null) {
				GLib.debug("SEND: %s", body);
				message.set_request_body_from_bytes("application/json", new Bytes(body.data));
			}
			
			return message;
		}

		/**
		 * Loads all available models from the server and stores them in models.
		 *
		 * Fetches the list of models, then gets detailed information for each model
		 * including capabilities. Results are stored in models HashMap.
		 *
		 * Replicates the original Client.fetch_all_model_details() behavior:
		 * calls models() API, then show_model() for each model.
		 *
		 * Note: This method does not refresh model details for models that are already
		 * cached (in-memory or file cache). It only fetches details for new models that
		 * are not yet cached. This functionality may be needed in the future to refresh
		 * cached models with updated server data, but is not currently implemented.
		 *
		 * @since 1.2.7.11
		 */
		public async void load_models() throws Error
		{
			// Create a temporary client to use its methods (which don't store state anymore)
			var client = new OLLMchat.Client(this);
			
			// Get list of models from API (replicates original: yield this.models())
			var models_list = yield client.models();
			
			// Track which models are still available
			var current_model_names = new Gee.HashSet<string>();
			
			// For each model, get detailed information including capabilities
			// Replicates original: yield this.show_model(model.name) for each
			foreach (var model in models_list) {
				current_model_names.add(model.name);
				
				// Skip if model already exists in cache
				if (this.models.has_key(model.name)) {
					continue;
				}
				
				// Try to load from file cache
				var cached_model = model.load_from_cache();
				if (cached_model != null) {
					this.models.set(model.name, cached_model);
					continue;
				}
				
				// Fetch from API (only this part needs error handling)
				try {
					var show_call = new OLLMchat.Call.ShowModel(this, model.name);
					var detailed_model = yield show_call.exec_show();
					
					// Update detailed model with relevant data from list model (size, digest, etc.)
					detailed_model.update_from_list_model(model);
					
					// Save to file cache
					detailed_model.save_to_cache();
					
					// Store in connection.models cache (replaces client.available_models)
					this.models.set(model.name, detailed_model);
				} catch (Error e) {
					GLib.warning("Failed to get details for model %s: %s", model.name, e.message);
					// Skip this model on error
				}
			}
			
			// Remove old models from cache that are no longer in the list
			var models_to_remove = new Gee.ArrayList<string>();
			foreach (var model_name in this.models.keys) {
				if (!current_model_names.contains(model_name)) {
					models_to_remove.add(model_name);
				}
			}
			foreach (var model_name in models_to_remove) {
				this.models.unset(model_name);
			}
		}
	}
}

