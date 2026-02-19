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
	 * Analysis layer for documentation file processing.
	 *
	 * Uses analysis-prompt-doc-file (whole-document category and summary) and
	 * analysis-prompt-doc-section (section descriptions). Used for shell, meson,
	 * and other non-coding-language text files (docs, configs, etc.).
	 *
	 * Processes DocumentationTree objects and generates descriptions using LLM
	 * with three-level processing: document summary, section summaries, and leaf extraction.
	 */
	public class DocumentationAnalysis : VectorBase
	{
		private SQ.Database sql_db;
		private static PromptTemplate? cached_template = null;
		private static PromptTemplate? cached_document_template = null;
		
		/**
		 * Static constructor - loads templates at class initialization.
		 */
		static construct
		{
			cached_template = new PromptTemplate("analysis-prompt-doc-section.txt");
			cached_template.load();
			cached_document_template = new PromptTemplate("analysis-prompt-doc-file.txt");
			cached_document_template.load();
		}
		
		/**
		 * Emitted when an element is finished being analyzed.
		 */
		public signal void element_analyzed(string element_name, int element_number, int total_elements);
		
		public DocumentationAnalysis(OLLMchat.Settings.Config2 config, SQ.Database sql_db)
		{
			base(config);
			this.sql_db = sql_db;
		}
		
		/**
		 * Analyzes a DocumentationTree and generates descriptions.
		 * 
		 * Three-level processing:
		 * 1. Level A: Document summary (root element)
		 * 2. Level B: Section summaries (with child context)
		 * 3. Level C: Leaf section extraction
		 */
		public async DocumentationTree analyze_tree(DocumentationTree tree) throws GLib.Error
		{
			// Level A: Analyze document (root element)
			if (tree.root_element != null) {
				yield this.analyze_document(tree.root_element, tree);
			}
			
			// Level B: Analyze sections (top-down traversal)
			yield this.analyze_sections(tree);
			
			// Level C: Extract leaf sections (already done during parsing)
			// Leaf sections are ready for vectorization
			
			// Sync database after processing
			this.sql_db.backupDB();
			
			return tree;
		}
		
		/**
		 * Level A: Analyzes entire document and generates summary and category.
		 */
		private async void analyze_document(
			OLLMfiles.SQT.VectorMetadata root_element, 
			DocumentationTree tree) throws GLib.Error
		{
			// Skip if already has description
			if (root_element.description != "") {
				return;
			}
			
			// Get full document content
			var document_content = tree.lines_to_string(1, tree.lines.length);
			var filename = GLib.Path.get_basename(tree.file.path);
			var filepath = tree.file.path;
			
			// Build user message (includes path and filename for LLM categorization)
			var user_message = cached_document_template.fill(
				"document_content", document_content,
				"filename", filename,
				"filepath", filepath
			);

			var messages = new Gee.ArrayList<OLLMchat.Message>();
			if (cached_document_template.system_message != "") {
				messages.add(new OLLMchat.Message("system", cached_document_template.system_message));
			}
			messages.add(new OLLMchat.Message("user", user_message));

			string result = "";
			try {
				var tool_config = this.config.tools.get("codebase_search") as OLLMvector.Tool.CodebaseSearchToolConfig;
				result = yield this.request_analysis(messages, tool_config.analysis);
			} catch (GLib.Error e) {
				root_element.category = "other";
				root_element.description = "";
				tree.category = root_element.category;
				return;
			}
			if (result == "") {
				root_element.category = "other";
				root_element.description = "";
				tree.category = root_element.category;
				return;
			}
			// Parse result: format is "CATEGORY: description" or just "description"
			var parts = result.split(":", 2);
			if (parts.length == 2) {
				var category_candidate = parts[0].strip().down();
				switch (category_candidate) {
					case "plan":
					case "documentation":
					case "rule":
					case "configuration":
					case "data":
					case "license":
					case "changelog":
					case "build":
					case "other":
						root_element.category = category_candidate;
						root_element.description = parts[1].strip();
						break;
					default:
						root_element.category = "other";
						root_element.description = result.strip();
						break;
				}
			} else {
				root_element.category = "other";
				root_element.description = result.strip();
			}
			tree.category = root_element.category;
		}
		
		/**
		 * Level B: Analyzes sections with child context.
		 */
		private async void analyze_sections(DocumentationTree tree) throws GLib.Error
		{
			// Top-down traversal: process parent sections before children
			var sections_to_process = new Gee.ArrayList<OLLMfiles.SQT.VectorMetadata>();
			
			// Collect all sections (excluding root)
			foreach (var element in tree.elements) {
				if (element.element_type == "section") {
					sections_to_process.add(element);
				}
			}
			
			// Sort by level (shallow to deep)
			sections_to_process.sort((a, b) => {
				var a_level = a.ast_path.split("-").length;
				var b_level = b.ast_path.split("-").length;
				return a_level - b_level;
			});
			
			// Process each section
			int element_number = 0;
			foreach (var section in sections_to_process) {
				element_number++;
				
				// Skip if already has description
				if (section.description != "") {
					this.element_analyzed(section.element_name, element_number, sections_to_process.size);
					continue;
				}
				
				// Skip small sections (< 10 words)
				var content = tree.lines_to_string(section.start_line, section.end_line);
				if (content.split(" ").length < 10) {
					section.description = "";
					this.element_analyzed(section.element_name, element_number, sections_to_process.size);
					continue;
				}
				
				// Get full section content including all subsections
				// Note: content should include all text from this section through all its child sections
				var full_content = tree.lines_to_string(section.start_line, section.end_line);
				
				// Collect parent context using get_section_context() method
				var parent_context_text = section.get_section_context();
				if (parent_context_text == "") {
					parent_context_text = "(top-level section)";
				}
				
				var user_message = cached_template.fill(
					"section_content", full_content,
					"section_title", section.element_name,
					"parent_sections", parent_context_text
				);

				var messages = new Gee.ArrayList<OLLMchat.Message>();
				if (cached_template.system_message != "") {
					messages.add(new OLLMchat.Message("system", cached_template.system_message));
				}
				messages.add(new OLLMchat.Message("user", user_message));

				try {
					var tool_config = this.config.tools.get("codebase_search") as OLLMvector.Tool.CodebaseSearchToolConfig;
					section.description = yield this.request_analysis(messages, tool_config.analysis);
				} catch (GLib.Error e) {
					section.description = "";
				}

				this.element_analyzed(section.element_name, element_number, sections_to_process.size);
			}
		}
	}
}
