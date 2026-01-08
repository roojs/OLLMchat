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

namespace OLLMchat.Tool
{
	/**
	 * Abstract base class for tools that can be used with Ollama function calling.
	 *
	 * This class contains all the implementation logic. Subclasses must implement
	 * the abstract properties (name, description, parameter_description). The Function
	 * class is built from Tool's properties on construction. Parameter descriptions
	 * use a special syntax with @type, @property, and @param directives.
	 *
	 * == Example ==
	 *
	 * {{{
	 * public class MyTool : Tool.BaseTool {
	 *     public override string name { get { return "my_tool"; } }
	 *     public override string description { get { return "Does something useful"; } }
	 *     public override string parameter_description {
	 *         get {
	 *             return """
	 * @param file_path string The path to the file
	 * @param line_number int Optional line number (default: 0)
	 * """;
	 *         }
	 *     }
	 *
	 *     public MyTool(Client? client = null) {
	 *         base(client);
	 *     }
	 *
	 *     public override async string? execute(Json.Object parameters) {
	 *         var file_path = parameters.get_string_member("file_path");
	 *         // ... tool implementation
	 *         return "Result";
	 *     }
	 * }
	 * }}}
	 */
	public abstract class BaseTool : Object, Json.Serializable
	{
		public string tool_type { get; set; default = "function"; }
		
		// Abstract properties that subclasses must implement
		public abstract string name { get; }
		public abstract string description { get; }
		public abstract string title { get; }
		public abstract string  parameter_description { get; default = ""; }
		
		// Abstract method that subclasses must implement
		public abstract Type config_class();
		
		// Function instance built from Tool's properties
		public Function? function { get; set; default = null; }
		
		public Client? client { get; set; default = null; }
		
		public bool active { get; set; default = true; }

		protected BaseTool(Client? client = null)
		{
			this.client = client;
			this.function = new Function(this);
			
			// Parse parameter description in two passes:
			// 1. Collect @type and @property declarations
			// 2. Parse @param declarations, resolving types
			
			var type_definitions = new Gee.HashMap<string, ParamObject>();
			var lines = this.parameter_description.split("\n");
			var current_decl = "";
			
			// First pass: collect @type and @property declarations
			foreach (var line in lines) {
				var stripped = line.strip();
				if (stripped == "") {
					continue;
				}
				
				if (stripped.has_prefix("@")) {
					// Process previous declaration if we have one
					if (current_decl != "") {
						this.parse_type_or_property(current_decl, type_definitions);
					}
					// Start new declaration
					current_decl = stripped;
					continue;
				}
				
				// Continuation of current declaration
				if (current_decl == "") {
					continue;
				}
				current_decl += " " + stripped;
			}
			
			// Process any leftover declaration at the end
			if (current_decl != "" && (current_decl.has_prefix("@type") || current_decl.has_prefix("@property"))) {
				this.parse_type_or_property(current_decl, type_definitions);
			}
			
			// Second pass: parse @param declarations
			current_decl = "";
			foreach (var line in lines) {
				var stripped = line.strip();
				if (stripped == "") {
					continue;
				}
				
				if (stripped.has_prefix("@param")) {
					// Process previous parameter if we have one
					if (current_decl != "") {
						this.parse_parameter_description_string(current_decl, type_definitions);
					}
					// Start new parameter
					current_decl = stripped;
					continue;
				}
				
				// Continuation of current parameter
				if (current_decl == "" || !current_decl.has_prefix("@param")) {
					continue;
				}
				current_decl += " " + stripped;
			}
			
			// Process any leftover parameter at the end
			if (current_decl != "" && current_decl.has_prefix("@param")) {
				this.parse_parameter_description_string(current_decl, type_definitions);
			}
		}
		
		private enum ParseState
		{
			PARAM,
			NAME,
			TYPE,
			REQUIRED,
			DESCRIPTION
		}
		
		/**
		 * Parses @type and @property declarations.
		 *
		 * Format: @type typename {object} Description
		 * Format: @property typename.propertyname {type} Description
		 *
		 * @param desc The declaration string (must start with @type or @property)
		 * @param type_definitions Map to store type definitions
		 */
		private void parse_type_or_property(string in_desc, Gee.HashMap<string, ParamObject> type_definitions)
		{
			var desc = in_desc.strip();
			
			if (desc.has_prefix("@type")) {
				this.parse_type_declaration(desc, type_definitions);
				return;
			}
			
			if (desc.has_prefix("@property")) {
				this.parse_property_declaration(desc, type_definitions);
			}
		}
		
		private void parse_type_declaration(string desc, Gee.HashMap<string, ParamObject> type_definitions)
		{
			var tokens = desc.split(" ");
			if (tokens.length < 3) {
				return;
			}
			
			var type_name = tokens[1];
			var type_token = tokens[2];
			
			if (!type_token.has_prefix("{") || !type_token.has_suffix("}")) {
				return;
			}
			
			var type_value = type_token.substring(1, type_token.length - 2);
			if (type_value != "object") {
				return;
			}
			
			// Extract description (everything after the type)
			string description = "";
			for (int i = 3; i < tokens.length; i++) {
				if (description != "") {
					description += " ";
				}
				description += tokens[i];
			}
			
			// Create or get the type definition
			if (!type_definitions.has_key(type_name)) {
				type_definitions[type_name] = new ParamObject.with_name(type_name, description, false);
			}
		}
		
		private void parse_property_declaration(string desc, Gee.HashMap<string, ParamObject> type_definitions)
		{
			var tokens = desc.split(" ");
			if (tokens.length < 3) {
				return;
			}
			
			var property_path = tokens[1];
			if (!property_path.contains(".")) {
				return;
			}
			
			var parts = property_path.split(".");
			if (parts.length != 2) {
				return;
			}
			
			var type_name = parts[0];
			var property_name = parts[1];
			var type_token = tokens[2];
			
			if (!type_token.has_prefix("{") || !type_token.has_suffix("}")) {
				return;
			}
			
			var property_type = type_token.substring(1, type_token.length - 2);
			
			// Extract description (everything after the type)
			string description = "";
			for (int i = 3; i < tokens.length; i++) {
				if (description != "") {
					description += " ";
				}
				description += tokens[i];
			}
			
			// Get or create the type definition
			if (!type_definitions.has_key(type_name)) {
				type_definitions[type_name] = new ParamObject.with_name(type_name, "", false);
			}
			
			var type_obj = type_definitions[type_name];
			
			// Parse property type and add directly to type_obj
			if (property_type.has_prefix("array<") && property_type.has_suffix(">")) {
				var item_type = property_type.substring(6, property_type.length - 7);
				
				if (item_type == "integer") {
					type_obj.properties.add(new ParamArray.with_name(
						property_name,
						new ParamSimple.with_values("item", "integer", "", false),
						description,
						true
					));
					return;
				}
				
				if (type_definitions.has_key(item_type)) {
					type_obj.properties.add(new ParamArray.with_name(
						property_name,
						type_definitions[item_type],
						description,
						true
					));
					return;
				}
				
				// Array of simple type
				type_obj.properties.add(new ParamArray.with_name(
					property_name,
					new ParamSimple.with_values("item", item_type, "", false),
					description,
					true
				));
				return;
			}
			
			// Simple type
			type_obj.properties.add(new ParamSimple.with_values(
				property_name,
				property_type,
				description,
				true
			));
		}
		
		/**
		 * Parses a single parameter description and adds it to the function's parameters property.
		 *
		 * Format: @param parameter_name {type} [required|optional] Parameter description here
		 * Format: @param parameter_name {array<type>} [required|optional] Parameter description here
		 *
		 * @param desc The parameter description string for a single parameter (must start with @param)
		 * @param type_definitions Map of type definitions for resolving array<type> references
		 */
		protected void parse_parameter_description_string(string in_desc, Gee.HashMap<string, ParamObject> type_definitions)
		{
			var desc = in_desc.strip();
			if (!desc.has_prefix("@param")) {
				return;
			}
			
			var tokens = desc.split(" ");
			var state = ParseState.PARAM;
			var param_name = "";
			var param_type = "";
			var required = false;
			var description = "";
			
			foreach (string token in tokens) {
				if (token == "") {
					continue; // Skip empty tokens (handles double spaces)
				}
				
				switch (state) {
					case ParseState.PARAM:
						if (token == "@param") {
							state = ParseState.NAME;
							break;
						}
						GLib.error("Invalid parameter description: %s", desc);
						 
					case ParseState.NAME:
						param_name = token;
						state = ParseState.TYPE;
						break;

					case ParseState.TYPE:
						if (token.has_prefix("{") && token.has_suffix("}")) {
							param_type = token.substring(1, token.length - 2);
							state = ParseState.REQUIRED;
							break;
						} 
						if (token.has_prefix("[") && token.has_suffix("]")) {
							// Type is optional, this is [required] or [optional]
							string req_str = token.substring(1, token.length - 2);
							required = (req_str == "required");
							state = ParseState.DESCRIPTION;
							break;
						}
						// Type is optional, this is the start of description
						description = token;
						state = ParseState.DESCRIPTION;
						break;

					case ParseState.REQUIRED:
						if (token.has_prefix("[") && token.has_suffix("]")) {
							string req_str = token.substring(1, token.length - 2);
							required = (req_str == "required");
							state = ParseState.DESCRIPTION;
							break;
						} 
						description = token;
						state = ParseState.DESCRIPTION;
					
						break;
					case ParseState.DESCRIPTION:
						if (description != "") {
							description += " ";
						}
						description += token;
						break;
				}
			}
			if (state != ParseState.DESCRIPTION && state != ParseState.REQUIRED) {
				GLib.error("Invalid parameter description: %s", desc);
			}
			
			// Handle array types: array<type>
			if (param_type.has_prefix("array<") && param_type.has_suffix(">")) {
				var item_type = param_type.substring(6, param_type.length - 7);
				
				if (type_definitions.has_key(item_type)) {
					this.function.parameters.properties.add(new ParamArray.with_name(
						param_name,
						type_definitions[item_type],
						description,
						required
					));
					return;
				}
			 
				this.function.parameters.properties.add(new ParamArray.with_name(
					param_name,
					new ParamSimple.with_values("item", item_type, "", false),
					description,
					required
				));
				return;
			}
			
			// Simple type
			this.function.parameters.properties.add(new ParamSimple.with_values(
				param_name,
				param_type,
				description,
				required
			));
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

		public Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "tool-type":
					// Exclude tool-type from serialization - it will be added manually as "type" in Chat
					return null;
				
				case "function":
					return Json.gobject_serialize(this.function);
					
				case "client":
				case "active":
					// Exclude these properties from serialization
					return null;
					// exculd nem etc..
				default:
					return null;
			}
		}
		
		/**
		 * Abstract method for tools to deserialize parameters into a Request object.
		 *
		 * Each tool implementation creates its specific Request type from the parameters JSON node.
		 *
		 * @param parameters_node The parameters as a Json.Node (converted from Json.Object by execute())
		 * @return A RequestBase instance or null if deserialization fails
		 */
		protected abstract RequestBase? deserialize(Json.Node parameters_node);
		
		/**
		 * Public method that creates a Request and delegates execution to it.
		 *
		 * Converts parameters to Json.Node, calls deserialize() to create a Request object,
		 * then sets tool and agent properties, and calls its execute() method.
		 *
		 * @param chat_call The chat call context for this tool execution
		 * @param parameters The parameters from the Ollama function call
		 * @return String result or error message (prefixed with "ERROR: " for errors)
		 */
		public virtual async string execute(Call.Chat chat_call, Json.Object parameters)
		{
			// Convert parameters Json.Object to Json.Node for deserialization
			var parameters_node = new Json.Node(Json.NodeType.OBJECT);
			parameters_node.set_object(parameters);
			
			// Deserialize parameters JSON into Request object
			var request = this.deserialize(parameters_node);
			if (request == null) {
				return "ERROR: Failed to create request object";
			}
			
			// Set tool and agent (not in JSON, set after deserialization)
			request.tool = this;
			// Set agent property (from chat_call, set after deserialization)
			request.agent = chat_call.agent;
			
			return yield request.execute();
		}
		
		/**
		 * Sets up tool configuration with default values.
		 *
		 * Default implementation for simple tools using BaseToolConfig.
		 * Creates a BaseToolConfig instance if it doesn't exist in the config.
		 * 
		 * Simple tools using BaseToolConfig don't need to override this - it's handled automatically.
		 * Complex tools that need custom config setup should override this method.
		 *
		 * @param config The Config2 instance
		 */
		public virtual void setup_tool_config(Settings.Config2 config)
		{
			// If config already exists, nothing to do
			if (config.tools.has_key(this.name)) {
				return;
			}
			
			// Create config instance using config_class() - works for all tool config types
			config.tools.set(this.name, Object.new(this.config_class()) as Settings.BaseToolConfig);
		}
		
		/**
		 * Sets up all tool configurations by discovering tools and calling setup_tool_config() on each.
		 *
		 * This discovers all tool classes, creates dummy instances, and calls setup_tool_config()
		 * on each. Simple tools will use the default implementation, complex tools will use their overrides.
		 *
		 * @param config The Config2 instance
		 */
		public static void setup_all_tool_configs(Settings.Config2 config)
		{
			foreach (var tool_type in discover_classes()) {
				// Create tool instance without parameters - works because constructors are nullable
				// Call setup_tool_config() on the instance
				// Simple tools will use the default implementation, complex tools will use their overrides
				(Object.new(tool_type) as Tool.BaseTool).setup_tool_config(config);
			}
		}
		
		/**
		 * Discovers all tool classes that extend Tool.BaseTool via GType registry.
		 *
		 * Queries the GType registry to find all registered types that extend
		 * Tool.BaseTool (abstract base class) and returns them as a list.
		 * All tools extend BaseTool directly, so we only need to check direct children.
		 *
		 * @return List of tool class GTypes
		 */
		public static Gee.ArrayList<Type> discover_classes()
		{
			var tool_types = new Gee.ArrayList<Type>();
			
			// Get direct children of Tool.BaseTool (all tools extend it directly)
			Type[] children = typeof(Tool.BaseTool).children();
			
			foreach (var child_type in children) {
				// Check if it's a class and not abstract
				if (!child_type.is_classed() || child_type.is_abstract()) {
					continue;
				}
				
				tool_types.add(child_type);
			}
			
			GLib.debug("discover_classes: found %d tool classes", tool_types.size);
			return tool_types;
		}
		
		/**
		 * Registers all tool config types with Config2 (Phase 1: before loading config).
		 *
		 * This method discovers all tool classes, creates tool instances (without
		 * dependencies), calls config_class() on each to get the config GType, and
		 * registers it with Config2. Must be called before config.load_config().
		 *
		 * Constructors must handle null values gracefully since this is called
		 * before dependencies (client, project_manager) are available.
		 */
		public static void register_config()
		{
			var tool_classes = discover_classes();
			
			foreach (var tool_type in tool_classes) {
				// Create tool instance without parameters - works because constructors are nullable
				// Constructors handle null values gracefully (for Phase 1, we only need config_class())
				var tool = Object.new(tool_type) as Tool.BaseTool;
				
				// Register config type with Config2
				Settings.Config2.register_tool_type(tool.name, tool.config_class());
			}
		}
		
		/**
		 * Creates all tool instances (Phase 3: tools moved from Client to Chat).
		 *
		 * This method discovers all tool classes and creates tool instances.
		 * Tools are metadata/descriptors - they don't need project_manager.
		 * Tool handlers (created when tools execute) need project_manager, which
		 * should be provided when creating handlers, not when creating tools.
		 * 
		 * The caller is responsible for storing the tools (e.g., on Manager) and
		 * adding them to Chat objects via Chat.add_tool() when Chat is created.
		 * 
		 * Per the plan: "Caller manages tools" - the caller (AgentHandler, Session, etc.)
		 * adds tools directly to Chat.
		 *
		 * @param client The LLM client instance
		 * @return Map of tool name to tool instance
		 */
		public static Gee.HashMap<string, BaseTool> register_all_tools(Client client)
		{
			var tool_classes = discover_classes();
			var tools_map = new Gee.HashMap<string, BaseTool>();
			
			foreach (var tool_type in tool_classes) {
				// Use Object.new() to create tool instance with constructor parameters
				// Standard signature: (Client? client = null)
				// Tools are metadata - they don't need project_manager
				// Tool handlers need project_manager, provided when handlers are created
				var tool = Object.new(
					tool_type,
					"client", client
				) as Tool.BaseTool;
				
				GLib.debug("register_all_tools: creating tool '%s'", tool.name);
				tools_map.set(tool.name, tool);
			}
			
			GLib.debug("register_all_tools: created %d tools", tool_classes.size);
			return tools_map;
		}
	}
}
