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

namespace OLLMchat.Response
{
	/**
	 * Represents model information from the Ollama server.
	 *
	 * Contains model metadata including name, size, capabilities, context length,
	 * and other details. Used in model listing and model information responses.
	 */
	public class Model : Base
	{
		/**
		 * Model name/identifier. This is the primary identifier for the model.
		 *
		 * When setting Client.model, always use this property (model.name), not model.model.
		 * This ensures consistency across all model sources (models(), ps(), show_model()).
		 *
		 * This property comes from the list API (models() endpoint). When updating from show API,
		 * use update_from_list_model() to preserve the name from the list API.
		 */
		/**
		 * Model name/identifier. This is the primary identifier for the model.
		 *
		 * When setting Client.model, always use this property (model.name), not model.model.
		 * This ensures consistency across all model sources (models(), ps(), show_model()).
		 *
		 * This property comes from the list API (models() endpoint). When updating from show API,
		 * use update_from_list_model() to preserve the name from the list API.
		 */
		public string name { get; set; default = ""; }
		
		/**
		 * Last modified timestamp in ISO 8601 format.
		 *
		 * Available from both list API and show API. Show API takes precedence when updating.
		 */
		public string modified_at { get; set; default = ""; }
		
		/**
		 * Model size in bytes.
		 *
		 * Available from the list API (models() endpoint). When updating from show API,
		 * use update_from_list_model() to preserve the size from the list API.
		 */
		public int64 size { get; set; default = 0; }
		
		/**
		 * Model digest/hash identifier.
		 *
		 * Available from the list API (models() endpoint). When updating from show API,
		 * use update_from_list_model() to preserve the digest from the list API.
		 */
		public string digest { get; set; default = ""; }
		
		/**
		 * List of supported features/capabilities.
		 *
		 * Available from the show API (show_model() endpoint). Common values include:
		 * "completion", "vision", "tools", "thinking", etc.
		 */
		public Gee.ArrayList<string> capabilities { get;  set; default = new Gee.ArrayList<string>(); }

		/**
		 * Model size in VRAM (runtime, from ps() API).
		 *
		 * Available from the ps() API when a model is currently loaded/running.
		 * Not available from list API or show API.
		 */
		public int64 size_vram { get; set; default = 0; }
		
		/**
		 * Total duration in nanoseconds (runtime, from ps() API).
		 *
		 * Available from the ps() API when a model is currently loaded/running.
		 * Not available from list API or show API.
		 */
		public int64 total_duration { get; set; default = 0; }
		
		/**
		 * Load duration in nanoseconds (runtime, from ps() API).
		 *
		 * Available from the ps() API when a model is currently loaded/running.
		 * Not available from list API or show API.
		 */
		public int64 load_duration { get; set; default = 0; }
		
		/**
		 * Prompt evaluation count (runtime, from ps() API).
		 *
		 * Available from the ps() API when a model is currently loaded/running.
		 * Not available from list API or show API.
		 */
		public int prompt_eval_count { get; set; default = 0; }
		
		/**
		 * Prompt evaluation duration in nanoseconds (runtime, from ps() API).
		 *
		 * Available from the ps() API when a model is currently loaded/running.
		 * Not available from list API or show API.
		 */
		public int64 prompt_eval_duration { get; set; default = 0; }
		
		/**
		 * Evaluation count (runtime, from ps() API).
		 *
		 * Available from the ps() API when a model is currently loaded/running.
		 * Not available from list API or show API.
		 */
		public int eval_count { get; set; default = 0; }
		
		/**
		 * Evaluation duration in nanoseconds (runtime, from ps() API).
		 *
		 * Available from the ps() API when a model is currently loaded/running.
		 * Not available from list API or show API.
		 */
		public int64 eval_duration { get; set; default = 0; }
		/**
		 * Model identifier from show API response.
		 *
		 * Note: For setting Client.model, always use model.name instead of this property
		 * to ensure consistency. This property may be empty or differ from name in some contexts.
		 *
		 * This property comes from the show API (show_model() endpoint). The name property
		 * comes from the list API (models() endpoint) and is the primary identifier.
		 */
		public string model { get; set; default = ""; }
		
		/**
		 * Expiration timestamp (runtime, from ps() API).
		 *
		 * Available from the ps() API when a model is currently loaded/running.
		 * Indicates when the model will expire/be unloaded if keep_alive is set.
		 * Not available from list API or show API.
		 */
		public string expires_at { get; set; default = ""; }
		
		/**
		 * Context length (maximum tokens the model can process).
		 *
		 * Available from the show API (show_model() endpoint). This is typically found
		 * in the model_info object as "{model_name}.context_length" in the API response.
		 */
		public int context_length { get; set; default = 0; }
		/**
		 * Model parameter settings serialized as text.
		 *
		 * Available from the show API (show_model() endpoint). Contains default parameter
		 * values in format like "temperature 0.7\nnum_ctx 2048". When set, automatically
		 * fills this.options with parsed values.
		 */
		private string _parameters = "";
		public string parameters {
			get { return this._parameters; }
			set {
				this._parameters = value;
//				GLib.debug("Model.parameters set for '%s': '%s'", this.name, value);
				// Automatically fill options from parameters when set
				if (value != "") {
					this.options.fill_from_model(this);
				}
			}
		}
		
		/**
		 * Default options parsed from model parameters.
		 *
		 * Automatically populated when parameters property is set.
		 */
		public OLLMchat.Call.Options options { get; set; default = new OLLMchat.Call.Options(); }

		/**
		 * Returns whether the model supports thinking output
		 */
		public bool is_thinking {
			get {
				//GLib.debug("is_thinking: %s %s", this.name, 
				//	this.capabilities.contains("thinking") ? "1" : "0");
				return this.capabilities.contains("thinking");
			}
			private set { }
		}

		/**
		 * Returns whether the model supports tool/function calling
		 */
		public bool can_call {
			get {
				//GLib.debug("can_call: %s %s", this.name, 
				//	this.capabilities.contains("tools") ? "1" : "0");
				return this.capabilities.contains("tools");
			}
			private set { }
		}

		/**
		 * Returns model name with size in parentheses (e.g., "llama3.1:70b (4.1 GB)")
		 */
		public string name_with_size {
			owned get {
				if (this.size == 0) {
					return this.name;
				}
				double size_gb_val = (double)this.size / (1024.0 * 1024.0 * 1024.0);
				string size_str;
				if (size_gb_val >= 1.0) {
					size_str = "%.1f GB".printf(size_gb_val);
				} else {
					size_str = "<1GB";
				}
				return "%s (%s)".printf(this.name, size_str);
			}
		}

		public Model(Settings.Connection? connection = null)
		{
			base(connection);
		}

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			// Exclude computed properties and client from serialization
			switch (property_name) {
				case "size-gb":
				case "is-thinking":
				case "can-call":
				case "name-with-size":
				case "client":
					// These are computed properties or internal references, skip serialization
					return null;
				case "capabilities":
					// Serialize capabilities as JSON array
					var capabilities = value.get_object() as Gee.ArrayList<string>;
					if (capabilities == null) {
						return null;
					}
					var array_node = new Json.Node(Json.NodeType.ARRAY);
					array_node.init_array(new Json.Array());
					var json_array = array_node.get_array();
					foreach (var cap in capabilities) {
						json_array.add_string_element(cap);
					}
					return array_node;
				default:
					// Let default handler process other properties
					return base.serialize_property(property_name, value, pspec);
			}
		}

		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			// Exclude computed properties from deserialization
			switch (property_name) {
				case "size-gb":
				case "is-thinking":
				case "can-call":
				case "name-with-size":
					// These are computed properties, skip deserialization
					value = Value(pspec.value_type);
					return true;
				case "capabilities":
					// Handle capabilities as string array
					var capabilities = new Gee.ArrayList<string>();
					var array = property_node.get_array();
					for (int i = 0; i < array.get_length(); i++) {
						var element = array.get_element(i);
						capabilities.add(element.get_string());
					}
					value = Value(typeof(Gee.ArrayList));
					value.set_object(capabilities);
					return true;
				default:
					// Let default handler process other properties
					return default_deserialize_property(property_name, out value, pspec, property_node);
			}
		}
		
		/**
		 * Updates this model's properties from another model.
		 * 
		 * Updates fields based on what's available in the source:
		 * - From show API: modified_at, capabilities, context_length, parameters, model
		 * - From list API: size, digest, modified_at (if not already set from show API), name
		 *
		 * This method handles both show API responses (with capabilities/parameters/model) and
		 * list API responses (with size/digest/name). It intelligently merges data, preserving
		 * show API data when present and falling back to list API data when needed.
		 *
		 * @param source The model to copy properties from (can be from show API or list API)
		 */
		public void update_from_list_model(Model source)
		{
			this.freeze_notify();
			
			// Update name (from list API, preserve if already set)
			// Note: name comes from list API, model property comes from show API
			this.name = source.name;
			
			
			// Update modified_at (show API takes precedence, but use list API if not set)
			if (source.modified_at != "") {
				this.modified_at = source.modified_at;
			}
			
			// Update capabilities (only from show API - list API doesn't have this)
			if (source.capabilities.size > 0) {
				this.capabilities.clear();
				foreach (var cap in source.capabilities) {
					this.capabilities.add(cap);
				}
			}
			
			// Update context_length (only from show API)
			if (source.context_length > 0) {
				this.context_length = source.context_length;
			}
			
			// Update parameters (only from show API)
			if (source.parameters != "") {
				this.parameters = source.parameters;
			}
			
			// Note: model property comes from show API, so we don't copy it from list API
			// The detailed model (this) already has model property from show API response
			
			// Update size (from list API, preserve if already set)
			if (this.size == 0 && source.size != 0) {
				this.size = source.size;
			}
			
			// Update digest (from list API, preserve if already set)
			if (this.digest == "" && source.digest != "") {
				this.digest = source.digest;
			}
			
			this.thaw_notify();
			// Thaw notifications - all property change signals will be emitted now
 		}
		
		
		/**
		* Gets the cache file path for this model.
		*
		* @return Path to the cache file in ~/.local/share/ollmchat/models/
		*/
		public string get_cache_path()
		{
			// Sanitize model name for filesystem (replace / and : with _)
			var safe_name = this.name.replace("/", "_").replace(":", "_");
			var cache_dir = Path.build_filename(
				GLib.Environment.get_user_data_dir(),
				"ollmchat",
				"models"
			);
			// Ensure cache directory exists
			var dir = File.new_for_path(cache_dir);
			if (!dir.query_exists()) {
				try {
					dir.make_directory_with_parents();
				} catch (Error e) {
					GLib.warning("Failed to create cache directory: %s", e.message);
				}
			}
			return Path.build_filename(cache_dir, safe_name + ".json");
		}

		/**
		* Loads model details from cache if available.
		*
		* @return Model object if cache was loaded successfully, null otherwise
		*/
		public Model? load_from_cache()
		{
			if (this.name == "") {
				return null;
			}
			
			var cache_path = this.get_cache_path();
			var cache_file = File.new_for_path(cache_path);
			
			if (!cache_file.query_exists()) {
				return null;
			}
			
			try {
				string contents;
				if (!GLib.FileUtils.get_contents(cache_path, out contents)) {
					return null;
				}
				
				var cached_model = Json.gobject_from_data(typeof(Model), contents, -1) as Model;
				if (cached_model == null) {
					return null;
				}
				
				// Set connection on cached model
				cached_model.connection = this.connection;
				
				return cached_model;
			} catch (Error e) {
				GLib.debug("Failed to load model from cache: %s", e.message);
				return null;
			}
		}

		/**
		* Saves model details to cache.
		*/
		public void save_to_cache()
		{
			var cache_path = this.get_cache_path();
			
			try {
				var json_node = Json.gobject_serialize(this);
				var generator = new Json.Generator();
				generator.pretty = true;
				generator.indent = 2;
				generator.set_root(json_node);
				var json_str = generator.to_data(null);
				
				var file = File.new_for_path(cache_path);
				file.replace_contents(
					json_str.data,
					null,
					false,
					FileCreateFlags.NONE,
					null
				);
			} catch (Error e) {
				GLib.warning("Failed to save model to cache: %s", e.message);
			}
		}
		
	}

}