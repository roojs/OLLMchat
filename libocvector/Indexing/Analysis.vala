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
	public class Analysis : VectorBase
	{
		private SQ.Database sql_db;
		private PromptTemplate? cached_template = null;
		
		/**
		 * Constructor.
		 * 
		 * @param config The Config2 instance containing tool configuration
		 * @param sql_db The SQLite database for syncing after file processing
		 */
		public Analysis(OLLMchat.Settings.Config2 config, SQ.Database sql_db)
		{
			base(config);
			this.sql_db = sql_db;
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
				"ocvector",
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
		 * @throws GLib.Error if template cannot be loaded
		 */
		private PromptTemplate get_prompt_template() throws GLib.Error
		{
			if (this.cached_template != null) {
				return this.cached_template;
			}
			
			// Load from resources - fail if it doesn't work
			this.cached_template = this.load_prompt_template();
			return this.cached_template;
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
					// Print element info before analysis starts
					stdout.printf("\n[Analyzing: %s (%s)]\n", element.element_name, element.element_type);
					stdout.flush();
					
					yield this.analyze_element(element, tree);
					
					// Print newline after analysis completes
					stdout.printf("\n");
					stdout.flush();
					
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
			
			// Sync database to file after processing this file
			this.sql_db.backupDB();
			
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
			// Build user message from template with context
			// Get file basename for context
			var file_basename = GLib.Path.get_basename(tree.file.path);
			
			var user_message = this.cached_template.user_template.replace(
				"{code}",
				tree.lines_to_string(element.start_line, element.end_line, 100)
			).replace(			
				"{documentation}",
				tree.lines_to_string(element.codedoc_start, element.codedoc_end)
			).replace(
				"{element_type}",
				element.element_type != "" ? element.element_type : "unknown"
			).replace(
				"{element_name}",
				element.element_name != "" ? element.element_name : "unnamed"
			).replace(
				"{file_basename}",
				file_basename != "" ? file_basename : "unknown"
			);
			
			// Add namespace context if available
			var namespace_context = "";
			if (element.namespace != null && element.namespace != "") {
				namespace_context = "- This code is in the namespace '" + element.namespace + "'\n";
			}
			user_message = user_message.replace("{namespace_context}", namespace_context);
			
			// Add parent class context if available (for methods, properties, fields, etc.)
			var parent_class_context = "";
			if (element.parent_class != null && element.parent_class != "") {
				// Try to find the parent class element to get its documentation
				VectorMetadata? parent_class_element = null;
				foreach (var e in tree.elements) {
					if (e.element_type == "class" && e.element_name == element.parent_class) {
						parent_class_element = e;
						break;
					}
				}
				
				if (parent_class_element != null) {
					// Get parent class documentation if available
					var parent_doc = tree.lines_to_string(parent_class_element.codedoc_start, parent_class_element.codedoc_end);
					if (parent_doc != null && parent_doc.strip() != "") {
						parent_class_context = "- This is a " + element.element_type + " of the class '" + element.parent_class + "', which: " + parent_doc.strip() + "\n";
					} else {
						// Fallback to just the class name
						parent_class_context = "- This is a " + element.element_type + " of the class '" + element.parent_class + "'\n";
					}
				} else {
					// Parent class not found in elements, just mention it
					parent_class_context = "- This is a " + element.element_type + " of the class '" + element.parent_class + "'\n";
				}
			}
			user_message = user_message.replace("{parent_class_context}", parent_class_context);
			
			// Add signature context if available (for methods, functions, properties, etc.)
			var signature_context = "";
			if (element.signature != null && element.signature != "") {
				signature_context = "- Full signature: " + element.signature + "\n";
			}
			user_message = user_message.replace("{signature_context}", signature_context);
			
			// Retry up to 2 times
			const int MAX_RETRIES = 2;
			
			for (int attempt = 0; attempt <= MAX_RETRIES; attempt++) {
				try {
					// Get analysis connection using base class method
					var analysis_conn = yield this.connection("analysis");
					var tool_config = this.config.tools.get("codebase_search") as OLLMvector.Tool.CodebaseSearchToolConfig;
					
					var chat = new OLLMchat.Call.Chat(
							analysis_conn,
							tool_config.analysis.model) {
						stream = true,  // Enable streaming (Phase 2: migrate to real properties)
						options = tool_config.analysis.options
					};
					
					// Build messages array directly from template and user message
					var messages = new Gee.ArrayList<OLLMchat.Message>();
					
					if (this.cached_template.system_message != "") {
						messages.add(new OLLMchat.Message("system", this.cached_template.system_message));
					}
					
					messages.add(new OLLMchat.Message("user", user_message));
					
					// Streaming is enabled on chat (set in constructor) so we can see progress
					// The response will still have complete content when done=true
					// We're requesting plain text format (format=null means text, not JSON)
					
					// Connect to stream_chunk signal to capture and print partial content (including thinking)
					ulong stream_chunk_id = 0;
					stream_chunk_id = chat.stream_chunk.connect((new_text, is_thinking, response) => {
						// Print the partial content as it arrives (both thinking and regular content)
						// Use stdout and flush immediately so output appears on command line in real-time
						stdout.printf("%s", new_text);
						stdout.flush();
					});
					
					// Execute LLM call (streaming enabled, plain text response)
					OLLMchat.Response.Chat? response = null;
					try {
						response = yield chat.send(messages, null);
					} finally {
						// Disconnect signal handler
						if (stream_chunk_id != 0) {
							chat.disconnect(stream_chunk_id);
						}
					}
					
					// Wait for streaming to complete if needed
					// (send() already waits, but response.done indicates completion)
					if (response != null && !response.done) {
						GLib.debug("Waiting for streaming response to complete...");
						// In practice, send() should return with done=true, but just in case
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
