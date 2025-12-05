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
		 */
		public string name { get; set; default = ""; }
		public string modified_at { get; set; default = ""; }
		public int64 size { get; set; default = 0; }
		public string digest { get; set; default = ""; }
		public Gee.ArrayList<string> capabilities { get;  set; default = new Gee.ArrayList<string>(); }

		public int64 size_vram { get; set; default = 0; }
		public int64 total_duration { get; set; default = 0; }
		public int64 load_duration { get; set; default = 0; }
		public int prompt_eval_count { get; set; default = 0; }
		public int64 prompt_eval_duration { get; set; default = 0; }
		public int eval_count { get; set; default = 0; }
		public int64 eval_duration { get; set; default = 0; }
		/**
		 * Model identifier from ps() API response. 
		 * 
		 * Note: For setting Client.model, always use model.name instead of this property
		 * to ensure consistency. This property may be null or differ from name in some contexts.
		 */
		public string? model { get; set; } 
		public string? expires_at { get; set; }
		public int context_length { get; set; default = 0; }

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

		public Model(Client? client = null)
		{
			base(client);
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
		 * Updates this model's properties from a show API response.
		 * Only updates fields that come from the show API endpoint:
		 * - modified_at
		 * - capabilities
		 * - context_length (if present in show response)
		 * 
		 * Does NOT update fields from models() API (name, size, digest) or
		 * runtime fields from ps() API (size_vram, durations, counts).
		 * 
		 * @param source The model from show API response to copy properties from
		 */
		public void updateFrom(Model source)
		{
			this.freeze_notify();
			// Only update fields that come from show API
			this.modified_at = source.modified_at;
			
			// Freeze notifications to batch property changes
 			
			// Update capabilities by clearing and adding, rather than replacing
			this.capabilities.clear();
			foreach (var cap in source.capabilities) {
				this.capabilities.add(cap);
			}
			// Notify computed properties that depend on capabilities
			//this.notify_property("capabilities");

			this.notify_property("is-thinking");
			this.notify_property("can-call");
			
			// Update context_length if present in show response
			if (source.context_length > 0) {
				this.context_length = source.context_length;
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
		* Loads model details from cache if available and updates this model using updateFrom().
		* 
		* @return true if cache was loaded successfully, false otherwise
		*/
		public bool load_from_cache()
		{
			if (this.name == "") {
				return false;
			}
			
			var cache_path = this.get_cache_path();
			var cache_file = File.new_for_path(cache_path);
			
			if (!cache_file.query_exists()) {
				return false;
			}
			
			try {
				var parser = new Json.Parser();
				parser.load_from_file(cache_path);
				var root = parser.get_root();
				if (root == null) {
					return false;
				}
				
				var generator = new Json.Generator();
				generator.set_root(root);
				var json_str = generator.to_data(null);
				var cached_model = Json.gobject_from_data(typeof(Model), json_str, -1) as Model;
				if (cached_model == null) {
					return false;
				}
				
				// Update this model with cached data
				this.updateFrom(cached_model);
				return true;
			} catch (Error e) {
				GLib.debug("Failed to load model from cache: %s", e.message);
				return false;
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