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
		 * Configuration file path
		 */
		public string config_path   = ""; 

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
		 * Creates a new Config1 object loaded from a file.
		 * 
		 * If the file doesn't exist or cannot be read/parsed, returns a Config1
		 * object with default values and loaded set to false.
		 * 
		 * @param config_path Path to the configuration file
		 * @return A new Config1 instance loaded from the file
		 */
		public static Config1 from_file(string config_path)
		{
			var config = new Config1();
			config.config_path = config_path;
			config.loaded = false;
			
			var file = File.new_for_path(config_path);
			
			if (!file.query_exists()) {
				return config;
			}

			try {
				var parser = new Json.Parser();
				parser.load_from_file(config_path);
				
				var root = parser.get_root();
				if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
					GLib.warning("Invalid config file: file is empty or not valid JSON");
					return config;
				}

				// Deserialize JSON to Config1 object
				var generator = new Json.Generator();
				generator.set_root(root);
				var json_str = generator.to_data(null);
				
				var loaded_config = Json.gobject_from_data(typeof(Config1), json_str, -1) as Config1;
				if (loaded_config == null) {
					GLib.warning("Failed to deserialize config file");
					return config;
				}

				// Clone the loaded config and set metadata properties
				config = loaded_config.clone();
				config.config_path = config_path;
				config.loaded = true;
			} catch (GLib.Error e) {
				GLib.warning("Failed to load config: %s", e.message);
			}
			
			return config;
		}

		/**
		 * Creates a clone of this Config1 object with all properties copied.
		 * 
		 * Uses GObject introspection to iterate through all properties and copy them.
		 * 
		 * @return A new Config1 instance with all properties copied from this object
		 */
		public Config1 clone()
		{
			var new_obj = new Config1();
			
			foreach (unowned ParamSpec pspec in this.get_class().list_properties()) {
				var value = this.get_property(pspec);
				new_obj.set_property(pspec, value);
			}
			
			return new_obj;
		}

		/**
		 * Saves configuration to file.
		 * 
		 * Creates the directory structure if it doesn't exist.
		 * Uses the config_path property set during construction or loading.
		 * 
		 * @throws Error if file cannot be written
		 */
		public void save() throws Error
		{
			if (this.config_path == null || this.config_path == "") {
				throw new GLib.FileError.INVAL("Config path is not set");
			}
			
			// Ensure directory exists
			var dir_path = Path.get_dirname(this.config_path);
			var dir = File.new_for_path(dir_path);
			if (!dir.query_exists()) {
				try {
					dir.make_directory_with_parents(null);
				} catch (GLib.Error e) {
					throw new GLib.FileError.FAILED("Failed to create config directory: %s", e.message);
				}
			}

			// Serialize Config1 object to JSON
			var json_node = Json.gobject_serialize(this);
			var generator = new Json.Generator();
			generator.pretty = true;
			generator.indent = 4;
			generator.set_root(json_node);
			
			generator.to_file(this.config_path);
		}

	}
}

