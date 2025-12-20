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
		 * Loads a prompt template from resources.
		 * 
		 * @param template_name The template name (e.g., "types", "properties", "methods")
		 * @return The prompt template string
		 */
		private string load_prompt_template(string template_name) throws GLib.Error
		{
			var resource_path = GLib.Path.build_filename(
				RESOURCE_BASE_PREFIX,
				"ocvector",
				"prompt-" + template_name + ".txt"
			);
			var file = GLib.File.new_for_uri("resource://" + resource_path);
			
			uint8[] data;
			string etag;
			file.load_contents(null, out data, out etag);
			return (string)data;
		}
		
		/**
		 * Loads a JSON schema from resources.
		 * 
		 * @param schema_name The schema name (e.g., "types", "properties", "methods")
		 * @return The JSON schema as a Json.Object
		 */
		private Json.Object? load_schema(string schema_name) throws GLib.Error
		{
			var resource_path = GLib.Path.build_filename(
				RESOURCE_BASE_PREFIX,
				"ocvector",
				"schema-" + schema_name + ".json"
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
		 * Generic extraction method that loads a prompt template and schema, makes LLM call, and returns elements.
		 * 
		 * @param file The OLLMfiles.File to analyze
		 * @param template_name The template name (e.g., "types", "properties", "methods")
		 * @param type_ranges Optional string with type line ranges for properties extraction
		 * @return A list of CodeElement objects
		 */
		private async Gee.ArrayList<CodeElement> extract(OLLMfiles.File file, string template_name, string? type_ranges = null) throws GLib.Error
		{
			// Load prompt template (this will be used as system message)
			var template = this.load_prompt_template(template_name);
			
			// Generate system message from template
			var system_message = template.replace("{language}", file.language);
			
			// For properties extraction, replace type_ranges placeholder in system message
			if (type_ranges != null) {
				system_message = system_message.replace("{type_ranges}", type_ranges);
			}
			
			// Read file content
			var code = yield file.read_async();
			
			// Load JSON schema for structured outputs
			Json.Object? schema = null;
			try {
				schema = this.load_schema(template_name);
			} catch (GLib.Error e) {
				GLib.warning("Failed to load JSON schema for %s, falling back to string format: %s", template_name, e.message);
			}
			
			// Enable streaming on the client
			var original_stream_setting = this.client.stream;
			this.client.stream = true;
			
			// Create chat call with structured outputs
			var chat = new OLLMchat.Call.Chat(this.client);
			
			// Set format_obj if schema is available for structured outputs
			if (schema != null) {
				chat.format_obj = schema;
			} else {
				GLib.warning("Schema not available for %s, attempting analysis without structured outputs", template_name);
			}
			
			// Set temperature to 0 for more deterministic structured outputs
			chat.options.temperature = 0.0;
			// Add restrictive sampling parameters to reduce hallucination
			chat.options.top_p = 0.9;  // Reduce sampling diversity
			chat.options.top_k = 40;    // Limit token choices
			chat.options.repeat_penalty = 1.1;  // Penalize repetition
			
			// Set system message from template (instructions)
			chat.system_content = system_message;
			
			// Set user message with code wrapped in <code></code> tags
			chat.chat_content = "Extract the requested information from this code:\n\n<code>\n" + code + "\n</code>";
			
			// Accumulate streaming content (both thinking and regular content)
			var accumulated_content = new GLib.StringBuilder();
			ulong stream_chunk_id = 0;
			
			// Connect to stream_chunk signal to capture and print partial content (including thinking)
			stream_chunk_id = this.client.stream_chunk.connect((new_text, is_thinking, response) => {
				// Print the partial content as it arrives (both thinking and regular content)
				stderr.printf(new_text);
				// Accumulate only regular content (not thinking) for JSON parsing
				if (!is_thinking) {
					accumulated_content.append(new_text);
				}
			});
			
			// Execute the chat call (streaming)
			OLLMchat.Response.Chat? response = null;
			try {
				response = yield chat.exec_chat();
			} catch (GLib.Error e) {
				// Disconnect signal handler
				if (stream_chunk_id != 0) {
					this.client.disconnect(stream_chunk_id);
				}
				// Restore original stream setting
				this.client.stream = original_stream_setting;
				throw new GLib.IOError.FAILED("LLM API call failed for " + template_name + ": " + e.message);
			}
			
			// Disconnect signal handler
			if (stream_chunk_id != 0) {
				this.client.disconnect(stream_chunk_id);
			}
			
			// Restore original stream setting
			this.client.stream = original_stream_setting;
			
			// Get the final content from response (should be complete after streaming)
			string final_content = "";
			if (response != null && response.message != null && response.message.content != "") {
				final_content = response.message.content;
			} else if (accumulated_content.str != "") {
				// Fallback to accumulated content if response doesn't have it
				final_content = accumulated_content.str;
			} else {
				throw new GLib.IOError.FAILED("Empty response from LLM for " + template_name);
			}
			
			// Parse and validate JSON response
			return yield this.parse_elements_response(final_content);
		}
		
		/**
		 * Parses a JSON response containing elements array.
		 * 
		 * @param json_content The JSON string from LLM response
		 * @return A list of CodeElement objects
		 */
		private async Gee.ArrayList<CodeElement> parse_elements_response(string json_content) throws GLib.Error
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
			
			// Parse the JSON to get elements array
			Json.Node? root_node = null;
			try {
				var parser2 = new Json.Parser();
				parser2.load_from_data(json_to_parse, -1);
				root_node = parser2.get_root();
			} catch (GLib.Error e) {
				// Try once more with the original content if first attempt failed
				try {
					var parser2 = new Json.Parser();
					parser2.load_from_data(json_content, -1);
					root_node = parser2.get_root();
				} catch (GLib.Error e2) {
					throw new GLib.IOError.FAILED(
						"Failed to parse JSON response: " + e.message + ". Original error: " + e2.message);
				}
			}
			
			if (root_node == null || root_node.get_node_type() != Json.NodeType.OBJECT) {
				throw new GLib.IOError.FAILED("Invalid JSON response: root is not an object");
			}
			
			var response_obj = root_node.get_object();
			if (!response_obj.has_member("elements")) {
				throw new GLib.IOError.FAILED("Invalid response: missing 'elements' field");
			}
			
			var elements_node = response_obj.get_member("elements");
			if (elements_node.get_node_type() != Json.NodeType.ARRAY) {
				throw new GLib.IOError.FAILED("Invalid response: 'elements' is not an array");
			}
			
			var elements_array = elements_node.get_array();
			var elements = new Gee.ArrayList<CodeElement>();
			
			for (uint i = 0; i < elements_array.get_length(); i++) {
				var element_node = elements_array.get_element(i);
				var element = Json.gobject_deserialize(typeof(CodeElement), element_node) as CodeElement;
				if (element != null) {
					elements.add(element);
				}
			}
			
			return elements;
		}
		
		/**
		 * Analyzes a code file using OLLMfiles.File.
		 * 
		 * @param file The OLLMfiles.File to analyze
		 * @return A CodeFile object with analyzed elements
		 */
		public async CodeFile analyze_file(OLLMfiles.File file) throws GLib.Error
		{
			// Step 1: Extract types (classes, structs, enums)
			Gee.ArrayList<CodeElement> types = new Gee.ArrayList<CodeElement>();
			try {
				types = yield this.extract(file, "types");
				GLib.debug("Extracted %d types from file: %s", types.size, file.path);
			} catch (GLib.Error e) {
				GLib.warning("Failed to extract types from file %s: %s", file.path, e.message);
			}
			
			// Step 2: Extract properties from identified types
			Gee.ArrayList<CodeElement> properties = new Gee.ArrayList<CodeElement>();
			try {
				// Build type ranges string for properties prompt
				var type_ranges = new GLib.StringBuilder();
				foreach (var type in types) {
					type_ranges.append_printf("- %s '%s' between lines %d-%d\n", 
						type.property_type, type.name, type.start_line, type.end_line);
				}
				
				if (types.size > 0) {
					properties = yield this.extract(file, "properties", type_ranges.str);
					GLib.debug("Extracted %d properties from file: %s", properties.size, file.path);
				}
			} catch (GLib.Error e) {
				GLib.warning("Failed to extract properties from file %s: %s", file.path, e.message);
			}
			
			// Step 3: Extract methods
			Gee.ArrayList<CodeElement> methods = new Gee.ArrayList<CodeElement>();
			try {
				methods = yield this.extract(file, "methods");
				GLib.debug("Extracted %d methods from file: %s", methods.size, file.path);
			} catch (GLib.Error e) {
				GLib.warning("Failed to extract methods from file %s: %s", file.path, e.message);
			}
			
			// Combine all results into CodeFile
			var code_file = new CodeFile();
			code_file.language = file.language;
			code_file.file = file;
			
			// Read file contents and split into lines
			var code = yield file.read_async();
			code_file.lines = code.split("\n");
			
			// Combine all elements
			var all_elements = new Gee.ArrayList<CodeElement>();
			all_elements.add_all(types);
			all_elements.add_all(properties);
			all_elements.add_all(methods);
			
			// Validate and extract code snippets for each element
			var valid_elements = new Gee.ArrayList<CodeElement>();
			foreach (var element in all_elements) {
				// Validate element
				if (element.property_type == "" || element.name == "" || element.start_line <= 0 || element.end_line <= 0) {
					GLib.warning("Skipping invalid element: type='" + element.property_type + "', name='" + element.name + "', start_line=" + element.start_line.to_string() + ", end_line=" + element.end_line.to_string());
					continue;
				}
				
				// Extract code snippet by slicing from CodeFile.lines
				// Convert 1-based line numbers to 0-based array indices
				int start_idx = (element.start_line - 1).clamp(0, code_file.lines.length - 1);
				int end_idx = element.end_line.clamp(0, code_file.lines.length);
				element.code_snippet_lines = code_file.lines[start_idx:end_idx];
				valid_elements.add(element);
			}
			
			// Set elements
			code_file.elements = valid_elements;
			
			if (code_file.elements.size == 0) {
				GLib.warning("No valid elements found in analysis response for file: %s", file.path);
			}
			
			return code_file;
		}
	}
}
