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
	 * the abstract properties. The Function class is built from Tool's properties
	 * on construction.
	 */
	public abstract class Interface : Object, Json.Serializable
	{
		public string tool_type { get; set; default = "function"; }
		
		// Abstract properties that subclasses must implement
		public abstract string name { get; }
		public abstract string description { get; }
		public abstract string  parameter_description { get; default = ""; }
		
		// Function instance built from Tool's properties
		public Function? function { get; set; default = null; }
		
		public Client client { get; set;  }
		
		public string permission_question { get; protected set; default = ""; }
		public string permission_target_path { get; protected set; default = ""; }
		public OLLMchat.ChatPermission.Operation permission_operation { get; protected set; default = OLLMchat.ChatPermission.Operation.READ; }
		
		public bool active { get; set; default = true; }

		protected Interface(Client client)
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
				case "permission-question":
				case "permission-target_path":
				case "permission-operation":
				case "active":
					// Exclude these properties from serialization
					return null;
					// exculd nem etc..
				default:
					return null;
			}
		}
		
		/**
		 * Generic method to read parameters from JSON and assign them to object properties.
		 * 
		 * Loops through the function's parameter properties and assigns values from the JSON
		 * parameters object to matching properties on this object.
		 * 
		 * @param parameters The JSON parameters object from the Ollama function call
		 */
		protected virtual void readParams(Json.Object parameters)
		{
			unowned var ocl = (GLib.ObjectClass) this.get_class();
			
			foreach (var param in this.function.parameters.properties) {
				if (!(param is ParamSimple)) {
					continue;
				}
				
				var simple_param = (ParamSimple) param;
				var param_name = simple_param.name;
				
				if (!parameters.has_member(param_name)) {
					continue;
				}
				
				var ps = ocl.find_property(param_name);
				if (ps == null) {
					continue;
				}
				
				var value = Value(ps.value_type);
				
				switch (simple_param.x_type) {
					case "string":
						value.set_string(parameters.get_string_member(param_name));
						break;
					case "integer":
						value.set_int64(parameters.get_int_member(param_name));
						break;
					case "boolean":
						value.set_boolean(parameters.get_boolean_member(param_name));
						break;
					default:
						continue;
				}
				
				this.set_property(ps, value);
			}
		}
		
		/**
		 * Normalizes a file path using the permission provider's normalization logic.
		 * 
		 * @param path The path to normalize
		 * @return The normalized path
		 */
		protected string normalize_file_path(string in_path)
		{
			
			var path = in_path;
			// Use permission provider's normalize_path if accessible, otherwise do basic normalization
			if (!GLib.Path.is_absolute(path) && this.client.permission_provider.relative_path != "") {
				path = GLib.Path.build_filename(this.client.permission_provider.relative_path, path);
			}
			// if it's still absolute - return it we might have to fail at this point..
			// llm should send valid paths, we should not try and solve it.
			 
			return path;
		}
		
		/**
		 * Reads parameters from JSON into object properties.
		 * 
		 * Tools can override this to read their specific parameters.
		 * 
		 * @param parameters The parameters from the Ollama function call
		 */
		protected virtual void prepare(Json.Object parameters)
		{
			this.readParams(parameters);
		}
		
		/**
		 * Abstract method for tools to build permission information.
		 * 
		 * Tools implement this method to build permission information
		 * from their specific parameters. Sets permission_question, permission_target_path,
		 * and permission_operation properties.
		 * 
		 * @return true if permission needs to be asked, false if permission check can be skipped
		 */
		protected abstract bool build_perm_question();
		
		/**
		 * Public method that handles permission checking before execution.
		 * 
		 * Calls prepare() to read parameters, then build_perm_question() to populate permission properties,
		 * checks permission if needed, and finally calls execute_tool() to perform the actual operation.
		 * 
		 * @param chat_call The chat call context for this tool execution
		 * @param parameters The parameters from the Ollama function call
		 * @return String result or error message (prefixed with "ERROR: " for errors)
		 */
		public virtual async string execute(Call.Chat chat_call, Json.Object parameters)
		{
			// Read parameters
			this.prepare(parameters);
			
			// Check permission if needed
			if (this.build_perm_question()) {
				GLib.debug("Tool.execute: Tool '%s' requires permission: '%s'", this.name, this.permission_question);
				GLib.debug("Tool.execute: Tool '%s' client=%p, permission_provider=%p (%s)", 
					this.name, this.client, this.client.permission_provider, 
					this.client.permission_provider.get_type().name());
				if (!(yield this.client.permission_provider.request(this))) {
					GLib.debug("Tool.execute: Permission denied for tool '%s'", this.name);
					return "ERROR: Permission denied: " + this.permission_question;
				}
				GLib.debug("Tool.execute: Permission granted for tool '%s'", this.name);
			} else {
				GLib.debug("Tool.execute: Tool '%s' does not require permission", this.name);
			}
			
			// Execute the tool
			try {
				var result = this.execute_tool(chat_call, parameters);
				GLib.debug("Tool.execute: Tool '%s' executed successfully, result length: %zu", this.name, result.length);
				return result;
			} catch (Error e) {
				GLib.debug("Tool.execute: Tool '%s' threw error: %s", this.name, e.message);
				return "ERROR: " + e.message;
			}
		}
		
		/**
		 * Abstract method for tools to implement their actual execution logic.
		 * 
		 * This method contains the tool-specific implementation that performs
		 * the actual operation after permission has been granted.
		 * 
		 * @param chat_call The chat call context for this tool execution
		 * @param parameters The parameters from the Ollama function call
		 * @return String content result (will be wrapped in JSON by execute())
		 */
		protected abstract string execute_tool(Call.Chat chat_call, Json.Object parameters) throws Error;
	}
}
