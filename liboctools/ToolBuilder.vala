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

namespace OLLMtools
{
	/**
	 * Builder class for creating wrapped tools from .tool definition files.
	 *
	 * Scans the resources/wrapped-tools/ directory for .tool files, parses
	 * their definitions, and registers wrapped tool instances with the
	 * tool hashmap.
	 */
	public class ToolBuilder : Object
	{
		private Gee.HashMap<string, OLLMchat.Tool.BaseTool> tools;
		
		/**
		 * Creates a new ToolBuilder instance.
		 *
		 * @param tools The hashmap of registered tools (will be modified to add wrapped tools)
		 */
		public ToolBuilder(Gee.HashMap<string, OLLMchat.Tool.BaseTool> tools)
		{
			this.tools = tools;
		}
		
		/**
		 * Scans the wrapped-tools directory and builds all wrapped tools.
		 * FIXME - later look at .config/ollmchat/wrapped-tools/
		 *
		 * Scans {{{resource:///wrapped-tools/}}} for *.tool files, parses each file,
		 * and registers the wrapped tools with the tools hashmap.
		 */
		public void scan_and_build()
		{
			// Enumerate children in the resource directory using Resource API
			// Use GLib.resources_enumerate_children() for globally registered resources
			string[] children;
			try {
				children = GLib.resources_enumerate_children("/wrapped-tools", GLib.ResourceLookupFlags.NONE);
			} catch (GLib.Error e) {
				GLib.warning("Cannot enumerate resource directory /wrapped-tools: %s", e.message);
				return;
			}
			
			foreach (var child_name in children) {
				if (!child_name.has_suffix(".tool")) {
					continue;
				}
				
				var parser = this.parse_tool_file("/wrapped-tools/" + child_name);
				
				if (parser.name == "") {
					GLib.warning("Failed to parse /wrapped-tools/%s, skipping", child_name);
					continue;
				}
				
				this.register_wrapped_tool(parser);
			}
		}
		
		/**
		 * Parses a .tool definition file.
		 *
		 * @param resource_path The resource path to the .tool file (e.g., /wrapped-tools/grep.tool)
		 * @return ParamParser instance with parsed data. Check parser.name == "" to determine if parsing failed.
		 */
		private OLLMchat.Tool.ParamParser parse_tool_file(string resource_path)
		{
			var parser = new OLLMchat.Tool.ParamParser();
			
			string contents;
			try {
				var resource_uri = "resource://" + resource_path;
				var file = GLib.File.new_for_uri(resource_uri);
				if (!file.query_exists()) {
					GLib.warning("Tool resource does not exist: %s", resource_path);
					return parser;
				}
				
				uint8[] data;
				string etag;
				file.load_contents(null, out data, out etag);
				contents = (string)data;
			} catch (GLib.Error e) {
				GLib.warning("Failed to read tool resource %s: %s", resource_path, e.message);
				return parser;
			}
			
			// Use ParamParser to parse the file contents
			parser.parse(contents);
			
			// Validate required fields
			if (parser.name == "" || parser.wrapped == "") {
				GLib.warning("Missing required fields (@name or @wrapped) in %s (name='%s', wrapped='%s')", 
					resource_path, parser.name, parser.wrapped);
				// Return empty parser to indicate failure
				parser = new OLLMchat.Tool.ParamParser();
			}
			
			return parser;
		}
		
		/**
		 * Registers a wrapped tool with the tools hashmap.
		 *
		 * @param parser The ParamParser instance with parsed tool definition
		 */
		private void register_wrapped_tool(OLLMchat.Tool.ParamParser parser)
		{
			if (!this.tools.has_key(parser.wrapped)) {
				GLib.warning("Wrapped tool '%s' not found for tool '%s'", parser.wrapped, parser.name);
				return;
			}
			
			var wrapped_tool = this.tools.get(parser.wrapped);
			
			// Check if this is a simple alias (only @name and @wrapped, no @param)
			// Aliases don't define parameters - they use the wrapped tool's existing parameters
			// Wrapped tools always define their own parameters with @param
			bool is_alias = (parser.parameter_description == "");
				
			if (is_alias) {
				if (this.tools.has_key(parser.name)) {
					GLib.critical("Tool name '%s' already exists, skipping alias", parser.name);
					return;
				}
				
				this.tools.set(parser.name, wrapped_tool);
				return;
			}
			
			// For full wrapped tools, require WrapInterface
			if (!(wrapped_tool is OLLMchat.Tool.WrapInterface)) {
				GLib.critical("Tool '%s' does not implement WrapInterface, cannot wrap", parser.wrapped);
				return;
			}
			
			// Full wrapped tool: create new instance using clone()
			// wrapped_tool already implements WrapInterface (checked above), which includes clone()
			var wrapped_interface = wrapped_tool as OLLMchat.Tool.WrapInterface;
			var new_tool = wrapped_interface.clone();
			
		// Set wrapped tool properties
			new_tool.is_wrapped = true;
			new_tool.command_template = parser.command_template;
			new_tool.title = parser.title + " (Wrapped)";
			
			if (new_tool.title == "") {
				GLib.critical("Empty title on tool %s", parser.name);
				return;
			}
			
		// Create function with parameters and custom name/description from parsed .tool file
			// Skip init() since we're setting parameters directly from parser
			var function = new OLLMchat.Tool.Function() {
				name = parser.name,
				description = parser.description,
				parameter_description = parser.parameter_description,
				parameters = parser.parameters
			};
			new_tool.function = function;
			
			if (this.tools.has_key(parser.name)) {
				GLib.warning("Tool name '%s' already exists, skipping wrapped tool", parser.name);
				return;
			}
			
			this.tools.set(parser.name, new_tool);
		}
	}
}
