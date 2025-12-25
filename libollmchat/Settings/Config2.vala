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
		 * Map of usage key → model usage objects (handled by registered GTypes)
		 * 
		 * Contains model usage configurations such as "default_model", "title_model",
		 * and external library configurations like "ocvector".
		 */
		public Gee.Map<string, Object> usage { get; set; default = new Gee.HashMap<string, Object>(); }
		
		/**
		 * Map of usage key → Json.Node for unregistered types.
		 * 
		 * Stores unregistered usage configurations as JSON nodes so they can be
		 * serialized back later when the type is registered.
		 */
		public Gee.Map<string, Json.Node> usage_unregistered { get; set; default = new Gee.HashMap<string, Json.Node>(); }
		
		/**
		 * Static registry of key → GType for deserialization.
		 * Shared across all Config2 instances.
		 */
		private static Gee.HashMap<string, Type>? usage_types = null;
		
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
		 * Initializes the usage_types map and registers default types.
		 * This is called lazily when first needed.
		 */
		private static void init()
		{
			// Return early if already initialized
			if (usage_types != null) {
				return;
			}
			
			// Initialize usage_types map
			usage_types = new Gee.HashMap<string, Type>();
			
			// Register default ModelUsage types
			usage_types.set("default_model", typeof(ModelUsage));
			usage_types.set("title_model", typeof(ModelUsage));
		}

		/**
		 * Default constructor.
		 */
		public Config2()
		{
		}

		/**
		 * Registers a GType for a property/section key (static method).
		 * 
		 * When deserializing JSON, Config2 will use the registered GType to deserialize
		 * the property using standard Json.Serializable.
		 * 
		 * @param key The property/section key name
		 * @param gtype The GType to use for deserialization
		 */
		public static void register_type(string key, Type gtype)
		{
			// Always call init (it will return early if already initialized)
			init();
			
			usage_types.set(key, gtype);
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
				case "connections":
					// Serialize connections map as a JSON object (key-value pairs)
					var obj = new Json.Object();
					foreach (var entry in this.connections.entries) {
						var key = entry.key;
						var connection = entry.value;
						var node = Json.gobject_serialize(connection);
						obj.set_member(key, node);
					}
					var result = new Json.Node(Json.NodeType.OBJECT);
					result.set_object(obj);
					return result;
					
				case "model-options":
					// Serialize model_options map as a JSON object (key-value pairs)
					var obj = new Json.Object();
					foreach (var entry in this.model_options.entries) {
						var key = entry.key;
						var options = entry.value;
						var node = Json.gobject_serialize(options);
						obj.set_member(key, node);
					}
					var result = new Json.Node(Json.NodeType.OBJECT);
					result.set_object(obj);
					return result;
					
				case "usage":
					// Serialize both registered and unregistered usage types
					var obj = new Json.Object();
					
					// Serialize registered types from usage map
					foreach (var entry in this.usage.entries) {
						var key = entry.key;
						var usage_obj = entry.value;
						var node = Json.gobject_serialize(usage_obj);
						obj.set_member(key, node);
					}
					
					// Serialize unregistered types from usage_unregistered map
					foreach (var entry in this.usage_unregistered.entries) {
						var key = entry.key;
						var node = entry.value;
						obj.set_member(key, node);
					}
					
					var result = new Json.Node(Json.NodeType.OBJECT);
					result.set_object(obj);
					return result;
					
				case "usage-unregistered":
					// Exclude usage_unregistered from serialization - it's already included in "usage"
					return null;
					
				case "loaded":
					// Exclude loaded flag from serialization (it's metadata, not config data)
					return null;
					
				default:
					// Return null for any unhandled properties to avoid Gee collection warnings
					return null;
			}
		}

		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			switch (property_name) {
				case "connections":
					// Deserialize connections from JSON object (key-value pairs)
					if (property_node.get_node_type() != Json.NodeType.OBJECT) {
						break;
					}
					
					var obj = property_node.get_object();
					obj.foreach_member((object, key, node) => {
						// Deserialize each Connection object
						var connection = Json.gobject_deserialize(typeof(Connection), node) as Connection;
						if (connection != null) {
							this.connections.set(key, connection);
						}
					});
					
					// Return the connections map as the value
					value = Value(typeof(Gee.Map));
					value.set_object(this.connections);
					return true;
					
				case "model-options":
					// Deserialize model_options from JSON object (key-value pairs)
					if (property_node.get_node_type() != Json.NodeType.OBJECT) {
						break;
					}
					
					var obj = property_node.get_object();
					obj.foreach_member((object, key, node) => {
						// Deserialize each Call.Options object
						var options = Json.gobject_deserialize(typeof(OLLMchat.Call.Options), node) as OLLMchat.Call.Options;
						if (options != null) {
							this.model_options.set(key, options);
						}
					});
					
					// Return the model_options map as the value
					value = Value(typeof(Gee.Map));
					value.set_object(this.model_options);
					return true;
					
				case "usage":
					// Ensure usage_types is initialized
					init();
					
					// usage will be an object - iterate through the object(node)
					if (property_node.get_node_type() != Json.NodeType.OBJECT) {
						break;
					}
					
					var obj = property_node.get_object();
					obj.foreach_member((object, key, node) => {
						if (!usage_types.has_key(key)) {
							// Unregistered type - save JSON node for later serialization
							this.usage_unregistered.set(key, node);
							return;
						}
						
						// Registered type - deserialize and set in usage map
						var deserialized_obj = Json.gobject_deserialize(usage_types.get(key), node);
						if (deserialized_obj == null) {
							return;
						}
						this.usage.set(key, deserialized_obj);
					});
					
					// Return the usage map as the value
					value = Value(typeof(Gee.Map));
					value.set_object(this.usage);
					return true;
			}
			
			// Use default deserialization for known properties
			return default_deserialize_property(property_name, out value, pspec, property_node);
		}

		/**
		 * Loads Config2 from file.
		 * 
		 * Uses the static config_path property which must be set before calling.
		 * The caller should ensure the file exists before calling this method.
		 * If the file cannot be read/parsed, returns a Config2 object with default
		 * values and loaded set to false.
		 * 
		 * @return A new Config2 instance loaded from the file
		 */
		public static Config2 load()
		{
			var config = new Config2();
			config.loaded = false;

			try {
				string contents;
				GLib.FileUtils.get_contents(Config2.config_path, out contents);
				
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
				loaded_config.loaded = true;
				return loaded_config;
			} catch (GLib.Error e) {
				GLib.warning("Failed to load config: %s", e.message);
			}
			
			return config;
		}

		/**
		 * Gets the default connection from the connections map.
		 * 
		 * @return The default connection, or null if no default connection is found
		 */
		public Connection? get_default_connection()
		{
			foreach (var entry in this.connections.entries) {
				if (entry.value.is_default) {
					return entry.value;
				}
			}
			return null;
		}

		/**
		 * Gets the default model name from the usage map.
		 * 
		 * @return The default model name, or empty string if not configured
		 */
		public string get_default_model()
		{
			var default_model_usage_obj = this.usage.get("default_model") as ModelUsage;
			if (default_model_usage_obj != null) {
				return default_model_usage_obj.model;
			}
			return "";
		}

		/**
		 * Creates a Client instance configured from a usage entry.
		 * 
		 * Gets the ModelUsage for the given name, finds the connection specified
		 * in ModelUsage.connection URL, and creates a Client with the connection,
		 * model, and config. Returns null if the usage entry doesn't exist or
		 * the specified connection is not found.
		 * 
		 * @param name The usage key name (e.g., "default_model", "title_model")
		 * @return A new Client instance configured from the usage entry, or null if not found or connection invalid
		 */
		public OLLMchat.Client? create_client(string name)
		{
			var model_usage_obj = this.usage.get(name) as ModelUsage;
			if (model_usage_obj == null) {
				return null;
			}

			// Get connection from ModelUsage
			if (model_usage_obj.connection == "" || 
					!this.connections.has_key(model_usage_obj.connection)) {
				return null;
			}
			

			// Create client with connection, model, and config
			return new OLLMchat.Client( this.connections.get(model_usage_obj.connection)) {
				config = this,
				model = model_usage_obj.model
			};
		}

		/**
		 * Saves configuration to file.
		 * 
		 * Creates the directory structure if it doesn't exist.
		 * Uses the static config_path property.
		 * 
		 * @throws Error if file cannot be written
		 */
		public void save() throws Error
		{
			// Ensure directory exists
			var dir = GLib.File.new_for_path(GLib.Path.get_dirname(Config2.config_path));
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
			
			generator.to_file(Config2.config_path);
		}
	}
}

