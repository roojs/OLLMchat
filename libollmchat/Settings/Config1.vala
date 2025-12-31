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
	 * Configuration management for OLLMchat client settings (Version 1).
	 *
	 * This is a copy of the original Config class for version 1 format support.
	 * Handles loading and saving client configuration to JSON file.
	 * Supports single client configuration (Phase 1) with structure
	 * designed to support multiple clients in the future.
	 *
	 * @since 1.0
	 */
	public class Config1 : Object, Json.Serializable
	{
		/**
		 * Server URL e.g. http:\/\/localhost:11434\/api
		 */
		public string url { get; set; default = "http://localhost:11434/api"; }
		
		/**
		 * Optional API key for authentication
		 */
		public string api_key { get; set; default = ""; }

		/**
		 * Model name to use for chat requests
		 */
		public string model { get; set; default = ""; }

		/**
		 * Model name for title generation (optional)
		 */
		public string title_model { get; set; default = ""; }

		/**
		 * Whether to return separate thinking output in addition to content
		 */
		public bool think { get; set; default = true; }

		/**
		 * Configuration file path (static, set once at application startup)
		 */
		public static string config_path = ""; 

		/**
		 * Whether the config was successfully loaded from a file.
		 * This property is not serialized.
		 */
		public bool loaded = false;  

		/**
		 * Default constructor.
		 */
		public Config1()
		{
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
			 
			return default_serialize_property(property_name, value, pspec);
		}

		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			return default_deserialize_property(property_name, out value, pspec, property_node);
		}

		/**
		 * Loads Config1 from file.
		 *
		 * Uses the static config_path property which must be set before calling.
		 * The caller should ensure the file exists before calling this method.
		 * If the file cannot be read/parsed, returns a Config1 object with default
		 * values and loaded set to false.
		 *
		 * @return A new Config1 instance loaded from the file
		 */
		public static Config1 load()
		{
			var config = new Config1();
			config.loaded = false;

			try {
				string contents;
				GLib.FileUtils.get_contents(Config1.config_path, out contents);
				
				var loaded_config = Json.gobject_from_data(
					typeof(Config1),
					contents,
					-1
				) as Config1;
				
				if (loaded_config == null) {
					GLib.warning("Failed to deserialize config file");
					return config;
				}

				// Set metadata properties on loaded config
				loaded_config.loaded = true;
				return loaded_config;
			} catch (GLib.Error e) {
				GLib.warning("Failed to load config: %s", e.message);
			}
			
			return config;
		}

	 

		/**
		 * Converts this Config1 instance to a Config2 instance.
		 *
		 * Creates a Config2 with a connection based on this Config1's url and api_key.
		 * The connection is set as the default connection.
		 * Preserves model and title_model as ModelUsage objects in Config2's usage map.
		 *
		 * @return A new Config2 instance with the migrated configuration
		 */
		public Config2 toV2()
		{
			var config2 = new Config2();
			
			// Create a connection from this Config1's data
			var connection = new Connection() {
				name = "Default",
				url = this.url,
				api_key = this.api_key,
				is_default = true
			};
			
			// Add connection to Config2
			config2.connections.set(this.url, connection);
			
			// Initialize empty model_options map (no model-specific options in v1)
			config2.model_options = new Gee.HashMap<string, OLLMchat.Call.Options>();
			
			// Preserve model and title_model as ModelUsage objects in usage map
			// Create ModelUsage for "default_model" key
			var default_model_usage = new ModelUsage() {
				connection = this.url,
				model = this.model,
				options = new OLLMchat.Call.Options()
			};
			config2.usage.set("default_model", default_model_usage);
			
			// Create ModelUsage for "title_model" key
			var title_model_usage = new ModelUsage() {
				connection = this.url,
				model = this.title_model,
				options = new OLLMchat.Call.Options()
			};
			config2.usage.set("title_model", title_model_usage);
			
			// Mark as loaded since this conversion is from a loaded Config1
			config2.loaded = true;
			
			return config2;
		}

	}
}

