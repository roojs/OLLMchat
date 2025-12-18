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

namespace OLLMvector.Indexing
{
	/**
	 * Base path for ocvector resources.
	 */
	private const string RESOURCE_BASE_PREFIX = "/ocvector";
	
	/**
	 * Analysis layer for code file processing.
	 * 
	 * Processes code files and sends them to LLM to generate structured JSON data
	 * for vector generation. Uses structured outputs via format_obj for reliable
	 * JSON parsing.
	 */
	public class Analysis : Object
	{
		private OLLMchat.Client client;
		
		/**
		 * Constructor.
		 * 
		 * @param client The OLLMchat client for LLM API calls
		 */
		public Analysis(OLLMchat.Client client)
		{
			this.client = client;
		}
		
		/**
		 * Loads the JSON schema from resources.
		 * 
		 * @return The JSON schema as a Json.Object
		 */
		public Json.Object? load_schema() throws GLib.Error
		{
			var resource_path = GLib.Path.build_filename(
				RESOURCE_BASE_PREFIX,
				"result-schema.json"
			);
			var file = GLib.File.new_for_uri("resource://" + resource_path);
			
			uint8[] data;
			string etag;
			file.load_contents(null, out data, out etag);
			
			var parser = new Json.Parser();
			parser.load_from_data((string)data, -1);
			
			var root = parser.get_root();
			if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
				throw new GLib.IOError.FAILED("Invalid JSON schema: root is not an object");
			}
			
			return root.get_object();
		}
		
		/**
		 * Analyzes a code file using OLLMfiles.File.
		 * 
		 * @param file The OLLMfiles.File to analyze
		 * @return A CodeFile object with analyzed elements
		 */
		public async CodeFile analyze_file(OLLMfiles.File file) throws GLib.Error
		{
			// Generate analysis prompt
			var prompt = yield this.generate_analysis_prompt(file);
			
			// Load JSON schema for structured outputs
			Json.Object? schema = null;
			try {
				schema = this.load_schema();
			} catch (GLib.Error e) {
				GLib.warning("Failed to load JSON schema, falling back to string format: %s", e.message);
			}
			
			// Create chat call with structured outputs
			var chat = new OLLMchat.Call.Chat(this.client);
			
			// Set format_obj if schema is available for structured outputs
			if (schema != null) {
				chat.format_obj = schema;
			} else {
				GLib.warning("Schema not available, attempting analysis without structured outputs");
			}
			
			// Set temperature to 0 for more deterministic structured outputs
			chat.options.temperature = 0.0;
			
			// Set system and user messages
			chat.system_content = "";
			chat.chat_content = prompt;
			
			// Execute the chat call
			OLLMchat.Response.Chat? response = null;
			try {
				response = yield chat.exec_chat();
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED("LLM API call failed: " + e.message);
			}
			
			if (response == null || response.message == null || response.message.content == "") {
				throw new GLib.IOError.FAILED("Empty response from LLM");
			}
			
			// Parse and validate JSON response
			return yield this.parse_and_validate_response(response.message.content, file);
		}
		
		/**
		 * Loads the analysis prompt template from resources.
		 * 
		 * @return The prompt template string
		 */
		private string load_prompt_template() throws GLib.Error
		{
			var resource_path = GLib.Path.build_filename(
				RESOURCE_BASE_PREFIX,
				"ocvector-prompt.txt"
			);
			var file = GLib.File.new_for_uri("resource://" + resource_path);
			
			uint8[] data;
			string etag;
			file.load_contents(null, out data, out etag);
			return (string)data;
		}
		
		/**
		 * Generates the analysis prompt for code analysis.
		 * 
		 * @param file The file object
		 * @return The formatted prompt string
		 */
		private async string generate_analysis_prompt(OLLMfiles.File file) throws GLib.Error
		{
			var template = this.load_prompt_template();
			// Replace placeholders in the template
			var prompt = template.replace("{language}", file.language);
			prompt = prompt.replace("{code}", yield file.read_async());
			return prompt;
		}
		
		/**
		 * Parses and validates the JSON response from LLM.
		 * 
		 * @param json_content The JSON string from LLM response
		 * @param file The original file object
		 * @return A validated CodeFile object
		 */
		private async CodeFile parse_and_validate_response(string json_content, OLLMfiles.File file) throws GLib.Error
		{
			// Try to extract JSON from response - might be wrapped
			string json_to_parse = json_content;
			var parser = new Json.Parser();
			
			try {
				parser.load_from_data(json_content, -1);
				var root_node = parser.get_root();
				if (root_node != null && root_node.get_node_type() == Json.NodeType.OBJECT) {
					var response_obj = root_node.get_object();
					// Check if response is wrapped in a "response" field
					if (response_obj.has_member("response")) {
						var response_node = response_obj.get_member("response");
						if (response_node.get_node_type() == Json.NodeType.VALUE) {
							json_to_parse = response_node.get_string();
						}
					}
				}
			} catch (GLib.Error e) {
				// If parsing fails, assume json_content is already the JSON we need
				GLib.debug("JSON extraction failed, using content as-is: %s", e.message);
			}
			
			// Parse the JSON into CodeFile
			CodeFile? code_file = null;
			try {
				code_file = Json.gobject_from_data(typeof(CodeFile), json_to_parse, -1) as CodeFile;
			} catch (GLib.Error e) {
				// Try once more with the original content if first attempt failed
				try {
					code_file = Json.gobject_from_data(typeof(CodeFile), json_content, -1) as CodeFile;
				} catch (GLib.Error e2) {
					throw new GLib.IOError.FAILED(
						"Failed to parse JSON response: " + e.message + ". Original error: " + e2.message);
				}
			}
			
			if (code_file == null) {
				throw new GLib.IOError.FAILED("Failed to deserialize code analysis response");
			}
			
			// Validate required fields
			if (code_file.file_path == "" || code_file.language == "" || code_file.elements == null) {
				throw new GLib.IOError.FAILED("Invalid response: missing required fields (file_path, language, or elements)");
			}
			
			// Set additional fields
			code_file.file_path = file.path;
			code_file.language = file.language;
			
			// Read file contents for code snippets
			var code = yield file.read_async();
			code_file.raw_code = code;
			
			// Split code into lines once
			var lines = code.split("\n");
			
			// Validate and extract code snippets for each element
			var valid_elements = new Gee.ArrayList<CodeElement>();
			foreach (var element in code_file.elements) {
				// Validate element
				if (element.property_type == "" || element.name == "" || element.start_line <= 0 || element.end_line <= 0) {
					GLib.warning("Skipping invalid element: type='" + element.property_type + "', name='" + element.name + "', start_line=" + element.start_line.to_string() + ", end_line=" + element.end_line.to_string());
					continue;
				}
				
				// Extract code snippet
				element.code_snippet = this.extract_code_snippet(lines, element.start_line, element.end_line);
				valid_elements.add(element);
			}
			
			// Update elements list with validated elements
			code_file.elements = valid_elements;
			
			if (code_file.elements.size == 0) {
				GLib.warning("No valid elements found in analysis response for file: %s", file.path);
			}
			
			return code_file;
		}
		
		/**
		 * Extracts a code snippet from the lines array based on line numbers.
		 * 
		 * @param lines The code split into lines
		 * @param start_line The starting line number (1-based)
		 * @param end_line The ending line number (1-based)
		 * @return The extracted code snippet
		 */
		private string extract_code_snippet(string[] lines, int start_line, int end_line)
		{
			var snippet = new GLib.StringBuilder();
			
			// Convert 1-based line numbers to 0-based array indices
			int start_idx = (start_line - 1).clamp(0, lines.length - 1);
			int end_idx = (end_line - 1).clamp(0, lines.length - 1);
			
			for (int i = start_idx; i <= end_idx && i < lines.length; i++) {
				snippet.append(lines[i]);
				if (i < end_idx) {
					snippet.append("\n");
				}
			}
			
			return snippet.str;
		}
	}
}
