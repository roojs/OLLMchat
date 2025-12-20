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
	 * Processes Tree objects from the Tree layer and generates one-line descriptions
	 * for code elements using LLM. Skips LLM analysis for simple elements (enum types
	 * without documentation, simple properties, enum values, fields without docs).
	 */
	public class Analysis : Object
	{
		private OLLMchat.Client client;
		private PromptTemplate? cached_template = null;
		
		/**
		 * Constructor.
		 * 
		 * @param client The OLLMchat client for LLM API calls
		 */
		public Analysis(OLLMchat.Client client)
		{
			this.client = client;
			// Enable streaming so we can see progress during analysis
			this.client.stream = true;
		}
		
		/**
		 * Prompt template structure.
		 */
		private struct PromptTemplate
		{
			public string system_message;
			public string user_template;
		}
		
		/**
		 * Loads a prompt template from resources.
		 * Template should use `---` separator between system and user messages.
		 * 
		 * @return PromptTemplate with system_message and user_template
		 */
		private PromptTemplate load_prompt_template() throws GLib.Error
		{
			var resource_path = GLib.Path.build_filename(
				RESOURCE_BASE_PREFIX,
				"analysis-prompt.txt"
			);
			var file = GLib.File.new_for_uri("resource://" + resource_path);
			
			uint8[] data;
			string etag;
			file.load_contents(null, out data, out etag);
			var template = (string)data;
			
			// Split on `---` separator
			var parts = template.split("---", 2);
			if (parts.length != 2) {
				throw new GLib.IOError.FAILED("Prompt template must contain '---' separator between system and user messages");
			}
			
			return PromptTemplate() {
				system_message = parts[0].strip(),
				user_template = parts[1].strip()
			};
		}
		
		/**
		 * Determines if an element should skip LLM analysis.
		 * 
		 * @param element The VectorMetadata element to check
		 * @return true if LLM analysis should be skipped
		 */
		private bool should_skip_llm(VectorMetadata element)
		{
			// Always skip enum values (they're just identifiers)
			if (element.element_type == "enum") {
				return true;
			}
			
			// Skip enum types without documentation
			if (element.element_type == "enum_type" && element.codedoc_start == -1) {
				return true;
			}
			
			// Skip fields without documentation
			if (element.element_type == "field" && element.codedoc_start == -1) {
				return true;
			}
			
			// Skip simple properties (properties without documentation and simple signatures)
			if (element.element_type == "property") {
				// Skip if no documentation
				if (element.codedoc_start == -1) {
					// Check if it's a simple property (just get/set, no complex default value)
					// Simple properties have signatures like: "public Type name { get; set; }"
					// Complex properties have: "public Type name { get; set; default = expression; }"
					if (element.signature == null || element.signature == "") {
						return true;
					}
					// If signature contains "default =", it's complex
					if (!element.signature.contains("default =")) {
						return true;
					}
				}
			}
			
			// Skip delegates without documentation
			if (element.element_type == "delegate" && element.codedoc_start == -1) {
				return true;
			}
			
			// All other elements should use LLM
			return false;
		}
		
		/**
		 * Gets the prompt template, loading and caching it if needed.
		 * 
		 * @return PromptTemplate (cached after first load)
		 */
		private PromptTemplate get_prompt_template()
		{
			if (this.cached_template != null) {
				return this.cached_template;
			}
			
			// Try to load from resources
			try {
				this.cached_template = this.load_prompt_template();
				return this.cached_template;
			} catch (GLib.Error e) {
				GLib.warning("Failed to load prompt template: %s. Using fallback template.", e.message);
				// Fallback to simple template if resource loading fails
				this.cached_template = PromptTemplate() {
					system_message = "You are a code analysis assistant. Generate a concise one-line description of what the code element does.",
					user_template = "Describe this code element:\n\n<code>\n{code}\n</code>\n\n{documentation}"
				};
				return this.cached_template;
			}
		}
		
		/**
		 * Analyzes a Tree object and generates descriptions for elements.
		 * 
		 * Iterates over Tree.elements and:
		 * - Skips LLM for simple elements (enum types without docs, simple properties, etc.)
		 * - Calls LLM for complex elements (classes, methods, properties with docs, etc.)
		 * - Stores descriptions in VectorMetadata.description property
		 * 
		 * @param tree The Tree object from Tree layer
		 * @return The same Tree object with descriptions populated
		 */
		public async Tree analyze_tree(Tree tree) throws GLib.Error
		{
			// Ensure prompt template is loaded (cached after first load)
			this.get_prompt_template();
			
			// Process elements in batches for efficiency
			var elements_to_process = new Gee.ArrayList<VectorMetadata>();
			
			// Collect elements that need LLM analysis
			foreach (var element in tree.elements) {
				if (this.should_skip_llm(element)) {
					element.description = "";
					continue;
				}
				elements_to_process.add(element);
			}
			
			GLib.debug("Processing file %s - %d elements need LLM, %d elements skipped", 
			           tree.file.path, elements_to_process.size, tree.elements.size - elements_to_process.size);
			
			// Process elements sequentially (can be optimized to batch later)
			int success_count = 0;
			int failure_count = 0;
			
			foreach (var element in elements_to_process) {
				try {
					yield this.analyze_element(element, tree);
					if (element.description != null && element.description != "") {
						success_count++;
						continue;
					}
					failure_count++;
				} catch (GLib.Error e) {
					GLib.warning("Failed to analyze element %s (%s) in file %s: %s", 
					             element.element_name, element.element_type, tree.file.path, e.message);
					element.description = "";
					failure_count++;
				}
			}
			
			GLib.debug("Complete for file %s: %d succeeded, %d failed", 
			           tree.file.path, success_count, failure_count);
			
			return tree;
		}
		
		/**
		 * Analyzes a single element and updates its description.
		 * 
		 * Sets element.description directly. Retries up to 2 times if LLM call fails.
		 * Leaves description empty if all attempts fail.
		 * 
		 * @param element The VectorMetadata element to analyze (description will be updated)
		 * @param tree The Tree object (for accessing lines)
		 */
		private async void analyze_element(VectorMetadata element, Tree tree) throws GLib.Error
		{
			// Build user message from template
			var user_message = this.cached_template.user_template.replace(
				"{code}",
				tree.lines_to_string(element.start_line, element.end_line)
			).replace(			
				"{documentation}",
				tree.lines_to_string(element.codedoc_start, element.codedoc_end)
			);
			
			// Retry up to 2 times
			const int MAX_RETRIES = 2;
			
			for (int attempt = 0; attempt <= MAX_RETRIES; attempt++) {
				try {
					// Create chat call
					var chat = new OLLMchat.Call.Chat(this.client);
					chat.system_content = this.cached_template.system_message;
					chat.chat_content = user_message;
					chat.options.temperature = 0.0;
					
					// Streaming is enabled on client (set in constructor) so we can see progress
					// The response will still have complete content when done=true
					// We're requesting plain text format (format=null means text, not JSON)
					
					// Connect to stream_chunk signal to capture and print partial content (including thinking)
					ulong stream_chunk_id = 0;
					stream_chunk_id = this.client.stream_chunk.connect((new_text, is_thinking, response) => {
						// Print the partial content as it arrives (both thinking and regular content)
						stderr.printf(new_text);
					});
					
					// Execute LLM call (streaming enabled, plain text response)
					OLLMchat.Response.Chat? response = null;
					try {
						response = yield chat.exec_chat();
					} finally {
						// Disconnect signal handler
						if (stream_chunk_id != 0) {
							this.client.disconnect(stream_chunk_id);
						}
					}
					
					// Wait for streaming to complete if needed
					// (exec_chat() already waits, but response.done indicates completion)
					if (response != null && !response.done) {
						GLib.debug("Waiting for streaming response to complete...");
						// In practice, exec_chat() should return with done=true, but just in case
					}
					
					if (response == null || response.message == null || response.message.content == null) {
						if (attempt < MAX_RETRIES) {
							continue;
						}
						element.description = "";
						return;
					}
					
					// Process response (strip whitespace and remove markdown formatting)
					var description = response.message.content.strip();
					
					// Remove markdown code blocks if present
					if (description.has_prefix("```")) {
						var lines = description.split("\n");
						if (lines.length > 2) {
							description = string.joinv("\n", lines[1:lines.length-1]).strip();
						}
					}
					
					// Update element description (leave empty if still empty after processing)
					if (description != null && description != "") {
						element.description = description;
						return;
					}
					
					// Empty description - retry if we have attempts left
					if (attempt < MAX_RETRIES) {
						continue;
					}
					
					// All retries exhausted, leave empty
					element.description = "";
					return;
					
				} catch (GLib.Error e) {
					// Retry if we have attempts left
					if (attempt < MAX_RETRIES) {
						continue;
					}
					// All retries exhausted, re-throw the error
					throw e;
				}
			}
			
			// Should never reach here, but just in case
			element.description = "";
		}
	}
}
