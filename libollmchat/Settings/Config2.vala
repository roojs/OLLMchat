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
	 * Main serializable configuration holder for version 2 format (multiple clients, extended structure).
	 * 
	 * This is the top-level container class that holds all configuration data.
	 * Supports GType registration for external configuration sections.
	 * 
	 * @since 1.0
	 */
	public class Config2 : Object, Json.Serializable
	{
		/**
		 * Map of connection URL → Connection objects
		 */
		public Gee.Map<string, Connection> connections { get; set; default = new Gee.HashMap<string, Connection>(); }
		
		/**
		 * Map of model name → Call.Options (per-model option overrides)
		 */
		public Gee.Map<string, OLLMchat.Call.Options> model_options { get; set; default = new Gee.HashMap<string, OLLMchat.Call.Options>(); }
		
		/**
		 * Map of section name → external config objects (handled by registered GTypes)
		 */
		public Gee.Map<string, Object> external_configs { get; set; default = new Gee.HashMap<string, Object>(); }
		
		/**
		 * Map of registered key → GType for deserialization
		 */
		private Gee.HashMap<string, Type> registered_types = new Gee.HashMap<string, Type>();
		
		/**
		 * Configuration file path
		 */
		public string config_path = "";
		
		/**
		 * Whether the config was successfully loaded from a file.
		 * This property is not serialized.
		 */
		public bool loaded = false;

		/**
		 * Default constructor.
		 */
		public Config2()
		{
		}

		/**
		 * Registers a GType for a property/section key.
		 * 
		 * When deserializing JSON, Config2 will use the registered GType to deserialize
		 * the property using standard Json.Serializable.
		 * 
		 * @param key The property/section key name
		 * @param gtype The GType to use for deserialization
		 */
		public void register_type(string key, Type gtype)
		{
			this.registered_types.set(key, gtype);
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
			// Check if this is a registered external config type
			if (this.registered_types.has_key(property_name)) {
				var gtype = this.registered_types.get(property_name);
				
				// Deserialize using the registered GType directly from Json.Node
				var obj = Json.gobject_deserialize(gtype, property_node);
				if (obj != null) {
					value = Value(gtype);
					value.set_object(obj);
					return true;
				}
			}
			
			// Use default deserialization for known properties
			return default_deserialize_property(property_name, out value, pspec, property_node);
		}

		/**
		 * Creates a new Config2 object loaded from a file.
		 * 
		 * The caller should ensure the file exists before calling this method.
		 * If the file cannot be read/parsed, returns a Config2 object with default
		 * values and loaded set to false.
		 * 
		 * @param config_path Path to the configuration file
		 * @return A new Config2 instance loaded from the file
		 */
		public static Config2 from_file(string config_path)
		{
			var config = new Config2();
			config.config_path = config_path;
			config.loaded = false;

			try {
				string contents;
				GLib.FileUtils.get_contents(config_path, out contents);
				
				var loaded_config = Json.gobject_from_data(
					typeof(Config2),
					contents,
					-1
				) as Config2;
				
				if (loaded_config == null) {
					GLib.warning("Failed to deserialize config file");
					return config;
				}

				// Set metadata properties on loaded config
				loaded_config.config_path = config_path;
				loaded_config.loaded = true;
				return loaded_config;
			} catch (GLib.Error e) {
				GLib.warning("Failed to load config: %s", e.message);
			}
			
			return config;
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
			// Ensure directory exists
			var dir = File.new_for_path(Path.get_dirname(this.config_path));
			if (!dir.query_exists()) {
				try {
					dir.make_directory_with_parents(null);
				} catch (GLib.Error e) {
					throw new GLib.FileError.FAILED("Failed to create config directory: %s", e.message);
				}
			}

			// Serialize Config2 object to JSON
			var generator = new Json.Generator();
			generator.pretty = true;
			generator.indent = 4;
			generator.set_root(Json.gobject_serialize(this));
			
			generator.to_file(this.config_path);
		}
	}
}

