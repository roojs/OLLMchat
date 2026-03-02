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

namespace OLLMvector.Indexing
{
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
		private static PromptTemplate? cached_template = null;
		private static PromptTemplate? cached_file_template = null;
		
		/**
		 * Static constructor - loads templates at class initialization.
		 */
		static construct
		{
			cached_template = new PromptTemplate("analysis-prompt.txt");
			cached_template.load();
			cached_file_template = new PromptTemplate("analysis-prompt-file.txt");
			cached_file_template.load();
		}
		
		/**
		 * Emitted when an element is finished being analyzed.
		 * 
		 * @param element_name Name of the element that was analyzed
		 * @param element_number Current element number (1-based)
		 * @param total_elements Total number of elements in the current file
		 */
		public signal void element_analyzed(string element_name, int element_number, int total_elements);
		
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
		 * Determines if an element should skip LLM analysis.
		 * 
		 * @param element The OLLMfiles.SQT.VectorMetadata element to check
		 * @return true if LLM analysis should be skipped
		 */
		private bool should_skip_llm(OLLMfiles.SQT.VectorMetadata element)
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
		 * Analyzes a Tree object and generates descriptions for elements.
		 * 
		 * Iterates over Tree.elements and:
		 * - Skips LLM for simple elements (enum types without docs, simple properties, etc.)
		 * - Calls LLM for complex elements (classes, methods, properties with docs, etc.)
		 * - Stores descriptions in OLLMfiles.SQT.VectorMetadata.description property
		 * 
		 * @param tree The Tree object from Tree layer
		 * @return The same Tree object with descriptions populated
		 */
		public async Tree analyze_tree(Tree tree) throws GLib.Error
		{
			
			// Process elements sequentially
			int success_count = 0;
			int failure_count = 0;
			int skipped_count = 0;
			int total_elements = tree.elements.size;
			int element_number = 0;
			
			foreach (var element in tree.elements) {
				element_number++;
				
				// Skip if element already has description (pre-populated from cache)
				if (element.description != "" && element.description != null) {
					skipped_count++;
					// Emit signal for skipped elements too
					this.element_analyzed(element.element_name, element_number, total_elements);
					continue;
				}
				
				if (this.should_skip_llm(element)) {
					element.description = "";
					// Emit signal for skipped elements too
					this.element_analyzed(element.element_name, element_number, total_elements);
					continue;
				}
				
				try {
					GLib.debug("Analyzing: %s (%s)", element.element_name, element.element_type);
					yield this.analyze_element(element, tree);
					
					// Emit signal after element is analyzed
					this.element_analyzed(element.element_name, element_number, total_elements);
					
					if (element.description != null && element.description != "") {
						success_count++;
						continue;
					}
					failure_count++;
				} catch (GLib.Error e) {
					GLib.warning("Failed to analyze element %s (%s) in file %s: %s", 
					             element.element_name, element.element_type, tree.file.path, e.message);
					element.description = "";
					// Emit signal even if analysis failed
					this.element_analyzed(element.element_name, element_number, total_elements);
					failure_count++;
				}
			}
			
			GLib.debug("Processing file %s - %d elements processed, %d skipped (cached), %d succeeded, %d failed", 
			           tree.file.path, total_elements, skipped_count, success_count, failure_count);
			
			GLib.debug("Complete for file %s: %d succeeded, %d failed", 
			           tree.file.path, success_count, failure_count);
			
			// Sync database to file after processing this file
			this.sql_db.backupDB();
			
			return tree;
		}
		
		/**
		 * Analyzes a file and generates a file-level summary.
		 * 
		 * Creates a OLLMfiles.SQT.VectorMetadata object for the file with element_type='file',
		 * adds it to tree.elements so it gets processed like other elements.
		 * 
		 * @param tree The Tree object with analyzed elements
		 * @return The same Tree object with file element added
		 */
		public async Tree analyze_file(Tree tree) throws GLib.Error
		{
			
			// Build elements summary (excluding enum members)
			string[] elements_summary_parts = {};
			foreach (var element in tree.elements) {
				// Skip enum members (element_type == "enum")
				if (element.element_type == "enum") {
					continue;
				}
				
				// Format: element_type: element_name - description
				var element_line = "%s: %s".printf(element.element_type, element.element_name);
				if (element.description != null && element.description != "" && element.description.strip() != "") {
					element_line += " - %s".printf(element.description.strip());
				}
				elements_summary_parts += element_line;
			}
			
			var elements_summary = string.joinv("\n", elements_summary_parts);
			
			// Get file basename and path
			var file_basename = GLib.Path.get_basename(tree.file.path);
			var file_path = tree.file.path;
			
			// Build user message from template
			var user_message = cached_file_template.fill(
				"file_basename", file_basename != "" ? file_basename : "unknown",
				"file_path", file_path != "" ? file_path : "unknown",
				"elements_summary", elements_summary != "" ? elements_summary : "(no elements found)"
			);
			
			var messages = new Gee.ArrayList<OLLMchat.Message>();
			if (cached_file_template.system_message != "") {
				messages.add(new OLLMchat.Message("system", cached_file_template.system_message));
			}
			messages.add(new OLLMchat.Message("user", user_message));

			GLib.debug("Analyzing file: %s", file_basename);
			string file_description;
			try {
				var tool_config = this.config.tools.get("codebase_search") as OLLMvector.Tool.CodebaseSearchToolConfig;
				file_description = yield this.request_analysis(messages, tool_config.analysis);
			} catch (GLib.Error e) {
				GLib.warning("Failed to analyze file %s: %s", tree.file.path, e.message);
				file_description = "";
			}
			if (file_description != "" && file_description.has_prefix("```")) {
				var lines = file_description.split("\n");
				if (lines.length > 2) {
					file_description = string.joinv("\n", lines[1:lines.length - 1]).strip();
				}
			}
			if (file_description != "") {
				GLib.debug("File analysis result: %s", file_description);
			}

			// Get file line count for end_line
			var file_line_count = tree.file.get_line_count();
			if (file_line_count <= 0) {
				// Fallback: count lines from tree.lines if available
				if (tree.lines != null && tree.lines.length > 0) {
					file_line_count = tree.lines.length;
				} else {
					// Default to 1 if we can't determine
					file_line_count = 1;
				}
			}
			
			// Create OLLMfiles.SQT.VectorMetadata object for the file
			var file_metadata = new OLLMfiles.SQT.VectorMetadata() {
				element_type = "file",
				element_name = file_basename,
				start_line = 1,
				end_line = file_line_count,
				description = file_description,
				file_id = tree.file.id,
				ast_path = ""  // Empty for file elements
			};
			
			// Add file element to tree.elements so it gets processed like other elements
			tree.elements.add(file_metadata);
			
			GLib.debug("File analysis complete for %s: description length %d", 
			           tree.file.path, file_description.length);
			
			return tree;
		}
		
		/**
		 * Analyzes a single element and updates its description.
		 * 
		 * Sets element.description directly. Retries up to 2 times if LLM call fails.
		 * Leaves description empty if all attempts fail.
		 * 
		 * @param element The OLLMfiles.SQT.VectorMetadata element to analyze (description will be updated)
		 * @param tree The Tree object (for accessing lines)
		 */
		private async void analyze_element(OLLMfiles.SQT.VectorMetadata element, Tree tree) throws GLib.Error
		{
			// Build user message from template with context
			// Get file basename for context
			var file_basename = GLib.Path.get_basename(tree.file.path);
			
			// Add namespace context if available
			var namespace_context = "";
			if (element.namespace != null && element.namespace != "") {
				namespace_context = "- This code is in the namespace '" + element.namespace + "'\n";
			}
			
			// Add parent class context if available (for methods, properties, fields, etc.)
			var parent_class_context = "";
			if (element.parent_class != null && element.parent_class != "") {
				// Try to find the parent class element to get its documentation
				OLLMfiles.SQT.VectorMetadata? parent_class_element = null;
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
			
			// Add signature context if available (for methods, functions, properties, etc.)
			var signature_context = "";
			if (element.signature != null && element.signature != "") {
				signature_context = "- Full signature: " + element.signature + "\n";
			}
			
			var user_message = cached_template.fill(
				"code", tree.lines_to_string(element.start_line, element.end_line, 100),
				"documentation", tree.lines_to_string(element.codedoc_start, element.codedoc_end),
				"element_type", element.element_type != "" ? element.element_type : "unknown",
				"element_name", element.element_name != "" ? element.element_name : "unnamed",
				"file_basename", file_basename != "" ? file_basename : "unknown",
				"namespace_context", namespace_context,
				"parent_class_context", parent_class_context,
				"signature_context", signature_context
			);

			var messages = new Gee.ArrayList<OLLMchat.Message>();
			if (cached_template.system_message != "") {
				messages.add(new OLLMchat.Message("system", cached_template.system_message));
			}
			messages.add(new OLLMchat.Message("user", user_message));

			var tool_config = this.config.tools.get("codebase_search") as OLLMvector.Tool.CodebaseSearchToolConfig;
			var description = yield this.request_analysis(messages, tool_config.analysis);
			if (description != "" && description.has_prefix("```")) {
				var lines = description.split("\n");
				if (lines.length > 2) {
					description = string.joinv("\n", lines[1:lines.length - 1]).strip();
				}
			}
			element.description = description;
			if (description != "") {
				GLib.debug("Element analysis result: %s", description);
			}
		}
	}
}
