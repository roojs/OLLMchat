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
	}
}
