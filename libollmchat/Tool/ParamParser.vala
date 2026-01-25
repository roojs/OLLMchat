/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
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
	 * Parser for tool definition text containing descriptions and annotations.
	 *
	 * Parses text that may contain:
	 * - Description text (before annotations)
	 * - Annotations: @title, @name, @wrapped, @command
	 * - Type definitions: @type, @property
	 * - Parameter definitions: @param
	 *
	 * After parsing, access the parsed values via properties.
	 */
	public class ParamParser : Object
	{
		/**
		 * Description text (content before annotations).
		 */
		public string description { get; private set; default = ""; }
		
		/**
		* Tool title from @title annotation.
		*/
		public string title { get; private set; default = ""; }
		
		/**
		 * Tool name from @name annotation.
		 */
		public string name { get; private set; default = ""; }
		
		/**
		 * Wrapped tool name from @wrapped annotation.
		 */
		public string wrapped { get; private set; default = ""; }
		
		/**
		 * Command template from @command annotation.
		 */
		public string command_template { get; private set; default = ""; }
		
		/**
		 * Raw parameter description string (all @param declarations).
		 */
		public string parameter_description { get; private set; default = ""; }
		
		/**
		 * Parsed parameters object (from @param declarations).
		 */
		public ParamObject parameters { get; private set; default = new ParamObject(); }
		
		/**
		 * Type definitions map (from @type and @property declarations).
		 */
		public Gee.HashMap<string, ParamObject> type_definitions { get; private set; default = new Gee.HashMap<string, ParamObject>(); }
		
		private enum ParseState
		{
			PARAM,
			NAME,
			TYPE,
			REQUIRED,
			DESCRIPTION
		}
		
		/**
		 * Parses the input text and populates all properties.
		 *
		 * @param text The text to parse (may contain description and annotations)
		 */
		public void parse(string text)
		{
			var lines = text.split("\n");
			var description_lines = new Gee.ArrayList<string>();
			var in_description = true;
			var current_decl = "";
			var annotations = new Gee.ArrayList<string>();
			
			// First pass: separate description from annotations
			foreach (var line in lines) {
				var stripped = line.strip();
				
				if (in_description) {
					if (stripped == "") {
						// Blank line might separate description from annotations
						continue;
					}
					
					if (stripped.has_prefix("@")) {
						// Found first annotation, description is done
						in_description = false;
						current_decl = stripped;
						continue;
					}
					
					// Still in description
					description_lines.add(line);
					continue;
				}
				
				// Processing annotations
				if (stripped == "") {
					// Blank line might continue current annotation or separate annotations
					if (current_decl != "") {
						annotations.add(current_decl);
						current_decl = "";
					}
					continue;
				}
				
				if (stripped.has_prefix("@")) {
					// New annotation starts
					if (current_decl != "") {
						annotations.add(current_decl);
					}
					current_decl = stripped;
					continue;
				}
				
				// Continuation of current annotation
				if (current_decl != "") {
					current_decl += " " + stripped;
				}
			}
			
			// Process any leftover annotation
			if (current_decl != "") {
				annotations.add(current_decl);
			}
			
			// Join description lines
			this.description = string.joinv("\n", description_lines.to_array());
			this.description = this.description.strip();
			
			// Process annotations
			foreach (var annotation in annotations) {
				this.process_annotation(annotation);
			}
			
			// Parse @param declarations into parameters
			if (this.parameter_description != "") {
				this.parse_parameters();
			}
		}
		
		/**
		 * Processes a single annotation line.
		 */
		private void process_annotation(string annotation_line)
		{
			var tokens = annotation_line.split(" ");
			if (tokens.length == 0) {
				return;
			}
			
			var annotation = tokens[0];
			
			switch (annotation) {
				case "@title":
					if (tokens.length > 1) {
						this.title = string.joinv(" ", tokens[1:tokens.length]);
					}
					break;
					
				case "@name":
					if (tokens.length > 1) {
						this.name = tokens[1];
					}
					break;
					
				case "@wrapped":
					if (tokens.length > 1) {
						this.wrapped = tokens[1];
					}
					break;
					
				case "@command":
					if (tokens.length > 1) {
						this.command_template = string.joinv(" ", tokens[1:tokens.length]);
					}
					break;
					
				case "@type":
				case "@property":
					this.parse_type_or_property(annotation_line);
					break;
					
				case "@param":
					// @param declarations are collected into parameter_description
					if (this.parameter_description != "") {
						this.parameter_description += "\n";
					}
					this.parameter_description += annotation_line;
					break;
			}
		}
		
		/**
		 * Parses @type and @property declarations.
		 */
		private void parse_type_or_property(string desc)
		{
			var stripped = desc.strip();
			
			if (stripped.has_prefix("@type")) {
				this.parse_type_declaration(stripped);
				return;
			}
			
			if (stripped.has_prefix("@property")) {
				this.parse_property_declaration(stripped);
			}
		}
		
		/**
		 * Parses a @type declaration.
		 */
		private void parse_type_declaration(string desc)
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
			if (!this.type_definitions.has_key(type_name)) {
				this.type_definitions.set(type_name, new ParamObject.with_name(type_name, description, false));
			}
		}
		
		/**
		 * Parses a @property declaration.
		 */
		private void parse_property_declaration(string desc)
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
			if (!this.type_definitions.has_key(type_name)) {
				this.type_definitions.set(type_name, new ParamObject.with_name(type_name, "", false));
			}
			
			var type_obj = this.type_definitions.get(type_name);
			
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
				
				if (this.type_definitions.has_key(item_type)) {
					type_obj.properties.add(new ParamArray.with_name(
						property_name,
						this.type_definitions.get(item_type),
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
		 * Parses @param declarations into the parameters object.
		 */
		private void parse_parameters()
		{
			var lines = this.parameter_description.split("\n");
			var current_decl = "";
			
			foreach (var line in lines) {
				var stripped = line.strip();
				if (stripped == "") {
					continue;
				}
				
				if (stripped.has_prefix("@param")) {
					// Process previous parameter if we have one
					if (current_decl != "") {
						this.parse_parameter_description_string(current_decl);
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
				this.parse_parameter_description_string(current_decl);
			}
		}
		
		/**
		 * Parses a single parameter description string.
		 */
		private void parse_parameter_description_string(string in_desc)
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
				
				if (this.type_definitions.has_key(item_type)) {
					this.parameters.properties.add(new ParamArray.with_name(
						param_name,
						this.type_definitions.get(item_type),
						description,
						required
					));
					return;
				}
			 
				this.parameters.properties.add(new ParamArray.with_name(
					param_name,
					new ParamSimple.with_values("item", item_type, "", false),
					description,
					required
				));
				return;
			}
			
			// Simple type
			this.parameters.properties.add(new ParamSimple.with_values(
				param_name,
				param_type,
				description,
				required
			));
		}
	}
}
