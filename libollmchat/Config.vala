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
	 * Configuration management for OLLMchat client settings.
	 * 
	 * Handles loading and saving client configuration to JSON file.
	 * Supports single client configuration (Phase 1) with structure
	 * designed to support multiple clients in the future.
	 * 
	 * @since 1.0
	 */
	public class Config : Object, Json.Serializable
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
		public Config()
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
		 * Loads configuration from file into this Config object.
		 * 
		 * If the file doesn't exist or cannot be read/parsed, this Config object
		 * remains with its default values and loaded is set to false.
		 * 
		 * @param config_path Path to the configuration file
		 */
		public void load(string config_path)
		{
			this.config_path = config_path;
			this.loaded = false;
			
			var file = File.new_for_path(config_path);
			
			if (!file.query_exists()) {
				return;
			}

			try {
				var parser = new Json.Parser();
				parser.load_from_file(config_path);
				
				var root = parser.get_root();
				if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
					GLib.warning("Invalid config file: file is empty or not valid JSON");
					return;
				}

				// Deserialize JSON to temporary Config object
				var generator = new Json.Generator();
				generator.set_root(root);
				var json_str = generator.to_data(null);
				
				var loaded_config = Json.gobject_from_data(typeof(Config), json_str, -1) as Config;
				if (loaded_config == null) {
					GLib.warning("Failed to deserialize config file");
					return;
				}

				// Copy properties from loaded config to this object
				loaded_config.copy_to(this);
				this.loaded = true;
			} catch (GLib.Error e) {
				GLib.warning("Failed to load config: %s", e.message);
			}
		}

		/**
		 * Copies properties from this config to another config object.
		 * 
		 * @param target The target config object to copy to
		 */
		public void copy_to(Config target)
		{
			target.url = this.url;
			target.api_key = this.api_key;
			target.model = this.model;
			target.title_model = this.title_model;
			target.think = this.think;
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

			// Serialize Config object to JSON
			var json_node = Json.gobject_serialize(this);
			var generator = new Json.Generator();
			generator.pretty = true;
			generator.indent = 4;
			generator.set_root(json_node);
			
			generator.to_file(this.config_path);
		}

	}
}
