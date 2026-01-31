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

namespace OLLMtools.Child
{
	/**
	 * Parser class for parsing agent file frontmatter.
	 *
	 * Parses YAML frontmatter from agent files in resources/agents/.
	 * Uses instance properties similar to ParamParser.
	 */
	public class Parser : Object
	{
		/**
		 * Agent name from frontmatter (required).
		 */
		public string name { get; private set; default = ""; }
		
		/**
		 * Agent description from frontmatter (required).
		 */
		public string description { get; private set; default = ""; }
		
		/**
		 * List of tool names the agent can use (from tools: field, comma-separated).
		 */
		public Gee.ArrayList<string> tools { 
			get; private set; default = new Gee.ArrayList<string>(); 
		}
		
		/**
		 * Model preference from frontmatter (optional).
		 */
		public string model { get; private set; default = ""; }
		
		/**
		 * Agent instructions (everything after frontmatter).
		 */
		public string instructions { get; private set; default = ""; }
		
		/**
		 * Placeholders found in instructions (format: {placeholder_name}).
		 */
		public Gee.ArrayList<string> placeholders { 
			get; private set; default = new Gee.ArrayList<string>(); 
		}
		
		/**
		 * Parses an agent file from resource path and populates properties.
		 *
		 * @param resource_path The resource path (e.g., "/agents/codebase-locator.md")
		 * @return true if parsing succeeded, false otherwise
		 */
		public bool parse_file(string resource_path)
		{
			// Read file content using resource:// URI
			string contents;
			try {
				var resource_uri = "resource://" + resource_path;
				var file = GLib.File.new_for_uri(resource_uri);
				if (!file.query_exists()) {
					GLib.warning("Agent resource does not exist: %s", resource_path);
					return false;
				}
				
				uint8[] data;
				string etag;
				file.load_contents(null, out data, out etag);
				contents = (string)data;
			} catch (GLib.Error e) {
				GLib.warning("Failed to read agent resource %s: %s", resource_path, e.message);
				return false;
			}
			
			// Find frontmatter block (between --- markers) and parse in single loop
			var lines = contents.split("\n");
			this.instructions = "";
			bool in_frontmatter = false;
			bool found_first_delimiter = false;
			
			foreach (var line in lines) {
				var stripped = line.strip();
				
				// Check for frontmatter delimiter
				if (stripped == "---") {
					if (!found_first_delimiter) {
						// First delimiter - start frontmatter
						found_first_delimiter = true;
						in_frontmatter = true;
						continue;
					} else {
						// Second delimiter - end frontmatter
						in_frontmatter = false;
						continue;
					}
				}
				
				if (!in_frontmatter && !found_first_delimiter) {
					continue; // Skip lines before frontmatter
				}
				
				// After frontmatter - this is instructions
				if (found_first_delimiter && !in_frontmatter) {
					if (this.instructions != "") {
						this.instructions += "\n";
					}
					this.instructions += line;
					continue;
				}
				
				// Parse frontmatter key: value pairs
				if (stripped == "" || stripped.has_prefix("#")) {
					continue; // Skip empty lines and comments
				}
				
				// Parse key: value format
				var colon_index = stripped.index_of(":");
				if (colon_index < 0) {
					continue; // Skip lines without colon
				}
				
				var key = stripped.substring(0, colon_index).strip();
				var value = stripped.substring(colon_index + 1).strip();
				
				switch (key) {
					case "name":
						this.name = value;
						break;
					case "description":
						this.description = value;
						break;
					case "tools":
						// Parse comma-separated list
						this.tools.clear();
						if (value != "") {
							var tool_names = value.split(",");
							foreach (var tool_name in tool_names) {
								var trimmed = tool_name.strip();
								if (trimmed != "") {
									this.tools.add(trimmed);
								}
							}
						}
						break;
					case "model":
						this.model = value;
						break;
				}
			}
			
			// Strip leading/trailing whitespace from instructions
			this.instructions = this.instructions.strip();
			
			// Extract placeholders from instructions
			this.extract_placeholders(contents);
			
			return true;
		}
		
		/**
		 * Extracts placeholders from text (format: {placeholder_name}, case-insensitive).
		 *
		 * @param text The text to search for placeholders
		 */
		private void extract_placeholders(string text)
		{
			try {
				// Case-insensitive regex to find {placeholder} patterns
				var regex = new GLib.Regex("\\{([a-zA-Z_]+)\\}", GLib.RegexCompileFlags.CASELESS);
				GLib.MatchInfo match_info;
				
				if (!regex.match_all(text, 0, out match_info)) {
					return;
				}
				
				do {
					var placeholder = match_info.fetch(1);
					if (placeholder != null && !this.placeholders.contains(placeholder)) {
						this.placeholders.add(placeholder);
					}
				} while (match_info.next());
			} catch (GLib.RegexError e) {
				// Regex error - continue without extracting placeholders
				GLib.warning("Failed to extract placeholders: %s", e.message);
			}
		}
		
		/**
		 * Selects a model for an agent tool using the model selection logic.
		 * 
		 * Steps:
		 * 1. Check if config exists and has model_usage.model set
		 * 2. Try to use model listed in agent frontmatter (if not embedding model)
		 * 3. Fallback to system default (but not embedding models)
		 * 
		 * @param manager The history manager containing config and connection_models
		 * @return Selected ModelUsage, or null if no valid model found
		 */
		private OLLMchat.Settings.ModelUsage? select_model_for_agent(
			OLLMchat.History.Manager manager
		) {
			// Step 1: Check if config exists and has model_usage.model set
			if (manager.config.tools.has_key(this.name)) {
				var existing_config = manager.config.tools.get(this.name) as Config;
				if (existing_config != null && existing_config.model_usage.model != "") {
					return existing_config.model_usage;
				}
			}
			
			// Step 2: Try to use model listed in agent frontmatter
			var model_usage = this.model == "" ? null : manager.connection_models.find_model_by_name(this.model);
			if (model_usage != null && model_usage.model_obj != null && model_usage.model_obj.is_embedding) {
				// Skip embedding models
				model_usage = null;
			}
			if (model_usage != null && model_usage.model_obj != null) {
				// Create/update config with model_usage
				var tool_config = new Config();
				tool_config.model_usage = new OLLMchat.Settings.ModelUsage() {
					connection = model_usage.connection,
					model = model_usage.model,
					model_obj = model_usage.model_obj
				};
				manager.config.tools.set(this.name, tool_config);
				return tool_config.model_usage;
			}
			
			// Step 3: Fallback to system default (but not embedding models)
			var default_connection = manager.config.default_connection();
			// Use connection_map for O(1) lookup instead of iterating all items
			var connection_models_map = default_connection == null ? null : manager.connection_models.connection_map.get(default_connection.url);
			// Get first model from default connection (if any) - if it's embedding, give up
			if (connection_models_map != null && connection_models_map.size > 0) {
				// Get first model from the map (iterate once to get first value)
				foreach (var default_model_usage in connection_models_map.values) {
					if (default_model_usage.model_obj != null
							 && !default_model_usage.model_obj.is_embedding) {
						return default_model_usage;
					}
					// If first model is embedding, give up (don't check others)
					return null;
				}
			}
			
			// No valid model found
			return null;
		}
		
		/**
		 * Scans the /agents/ resource directory and registers all agent tools.
		 * 
		 * Enumerates all .md files in /agents/, parses their frontmatter, and
		 * registers each as a separate tool. Performs model selection and config
		 * setup for each agent tool.
		 * 
		 * @param manager The history manager containing tools, config, and connection_models
		 * @param project_manager Optional ProjectManager instance for tools
		 */
		public void scan_and_register(
			OLLMchat.History.Manager manager,
			OLLMfiles.ProjectManager? project_manager
		) {
			// Enumerate children in /agents/ resource directory
			// Only support resource:// initially (filesystem support can be added later)
			string[] children;
			try {
				children = GLib.resources_enumerate_children("/agents", GLib.ResourceLookupFlags.NONE);
			} catch (GLib.Error e) {
				GLib.warning("Cannot enumerate resource directory /agents: %s", e.message);
				return;
			}
			
			foreach (var child_name in children) {
				if (!child_name.has_suffix(".md")) {
					continue;
				}
				
				// Parse agent file (create new parser for each file - don't reuse)
				var parser = new Parser();
				if (!parser.parse_file("/agents/" + child_name)) {
					GLib.warning("Failed to parse /agents/%s, skipping", child_name);
					continue;
				}
				
				// Validate required fields
				if (parser.name == "" || parser.description == "") {
					GLib.warning("Missing required fields (name or description) in /agents/%s, skipping", child_name);
					continue;
				}
				
				// Check for duplicate tool names
				if (manager.tools.has_key(parser.name)) {
					GLib.critical("Tool name '%s' already exists, skipping agent tool from /agents/%s", parser.name, child_name);
					continue;
				}
				
				// Model selection and config setup
				// This must happen before creating the Tool instance
				var selected_model_usage = parser.select_model_for_agent(manager);
				
				// If no valid model found, disable the tool
				if (selected_model_usage == null) {
					GLib.warning("No valid model found for agent tool '%s' (from /agents/%s), disabling tool", parser.name, child_name);
					continue; // Skip registration
				}
				
				// Save config if we created/updated it during model selection
				if (manager.config.tools.has_key(parser.name)) {
					try {
						manager.config.save();
					} catch (GLib.Error e) {
						GLib.warning("Failed to save config for agent tool '%s': %s", parser.name, e.message);
					}
				}
				
				// Create and register agent tool
				// Each agent is registered as a separate tool, so they appear as individual tools to the LLM
				var agent_tool = new Tool(project_manager) {
					agent_name = parser.name,
					agent_description = parser.description,
					agent_tools = parser.tools,
					agent_model = parser.model,
					agent_instructions = parser.instructions
				};
				manager.tools.set(parser.name, agent_tool);
			}
		}
	}
}
