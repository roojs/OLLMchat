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
	 * Markdown/documentation parsing and OLLMfiles.SQT.VectorMetadata creation.
	 * 
	 * Parses documentation files (markdown, plain text) to extract sections
	 * and create OLLMfiles.SQT.VectorMetadata objects with hierarchical structure.
	 */
	public class DocumentationTree : OLLMfiles.TreeBase
	{
		/**
		 * Array of OLLMfiles.SQT.VectorMetadata objects extracted from document sections.
		 */
		public Gee.ArrayList<OLLMfiles.SQT.VectorMetadata> elements { get; private set; default = new Gee.ArrayList<OLLMfiles.SQT.VectorMetadata>(); }
		
		/**
		 * Root element (document-level metadata).
		 */
		public OLLMfiles.SQT.VectorMetadata? root_element { get; private set; default = null; }
		
		/**
		 * Document category (plan, documentation, rule, etc.).
		 */
		public string category { get; set; default = ""; }
		
		/**
		 * Constructor.
		 */
		public DocumentationTree(OLLMfiles.File file)
		{
			base(file);
		}
		
		/**
		 * Main entry point: parse file and populate elements array.
		 */
		public async void parse() throws GLib.Error
		{
			// Load file content using base class method
			var content = yield this.load_file_content();
			
			// Category will be determined during analysis (Level A)
			this.category = "";
			
			// Check if file is markdown
			var is_markdown = this.file.path.has_suffix(".md") || 
			                  this.file.path.has_suffix(".markdown");
			
			// Early return: markdown file
			if (is_markdown) {
				yield this.parse_markdown_tree(content);
				return;
			}
			
			// Plain text file - create single element
			this.parse_plain_text();
		}
		
		/**
		 * Parses markdown file using tree-sitter to extract heading hierarchy.
		 */
		private async void parse_markdown_tree(string content) throws GLib.Error
		{
			// Create document-level element (root element)
			var document_element = new OLLMfiles.SQT.VectorMetadata() {
				element_type = "document",
				element_name = GLib.Path.get_basename(this.file.path),
				file_id = this.file.id,
				start_line = 1,
				end_line = this.lines.length,
				category = this.category,
				ast_path = ""
			};
			this.root_element = document_element;
			this.elements.add(document_element);
			
			// Initialize parser using base class method
			yield this.init_parser();
			if (this.language == null) {
				GLib.warning("Failed to load tree-sitter language for markdown: %s", this.file.path);
				return;
			}
			
			// Parse markdown using tree-sitter
			var tree = this.parse_content(content);
			if (tree == null) {
				throw new GLib.IOError.FAILED("Failed to parse markdown file: " + this.file.path);
			}
			
			// Traverse AST to extract heading hierarchy
			var root_node = tree.get_root_node();
			var root_sections = new Gee.ArrayList<OLLMfiles.SQT.VectorMetadata>();
			this.traverse_markdown_ast(root_node, content, root_sections, null, 0);
			
			// Update end lines for all sections based on next heading
			this.update_section_end_lines();
		}
		
		/**
		 * Updates end_line for each section based on the start_line of the next section.
		 */
		private void update_section_end_lines()
		{
			// Sort all sections by start_line
			var sections_list = new Gee.ArrayList<OLLMfiles.SQT.VectorMetadata>();
			foreach (var element in this.elements) {
				// Early continue: skip non-sections
				if (element.element_type != "section") {
					continue;
				}
				sections_list.add(element);
			}
			
			sections_list.sort((a, b) => {
				return a.start_line - b.start_line;
			});
			
			// For each section, set end_line to the line before the next section at same or higher level
			for (int i = 0; i < sections_list.size; i++) {
				var section = sections_list.get(i);
				var section_level = section.ast_path.split("-").length;
				
				// Find next section at same or higher level (or end of document)
				int end_line = this.lines.length;
				for (int j = i + 1; j < sections_list.size; j++) {
					var next_section = sections_list.get(j);
					var next_level = next_section.ast_path.split("-").length;
					// Early continue: next section is deeper (lower level)
					if (next_level > section_level) {
						continue;
					}
					
					// Found next section at same or higher level
					end_line = next_section.start_line - 1;
					break;
				}
				
				section.end_line = end_line;
			}
		}
		
		/**
		 * Recursively traverse markdown AST to extract heading hierarchy.
		 */
		private void traverse_markdown_ast(
			TreeSitter.Node node,
			string content,
			Gee.ArrayList<OLLMfiles.SQT.VectorMetadata> root_sections,
			OLLMfiles.SQT.VectorMetadata? current_parent,
			int current_level)
		{
			// Early return: null node
			if (TreeSitter.node_is_null(node)) {
				return;
			}
			
			unowned string? node_type = TreeSitter.node_get_type(node);
			// Early return: no node type - recurse into children
			if (node_type == null) {
				uint child_count = TreeSitter.node_get_child_count(node);
				for (uint i = 0; i < child_count; i++) {
					var child = TreeSitter.node_get_child(node, i);
					this.traverse_markdown_ast(child, content, root_sections, current_parent, current_level);
				}
				return;
			}
			
			// Check if this is a heading node using base class method
			var element_type = this.get_element_type(node, this.language);
			// Early return: not a heading - recurse into children with same parent
			if (!element_type.has_prefix("heading")) {
				uint child_count = TreeSitter.node_get_child_count(node);
				for (uint i = 0; i < child_count; i++) {
					var child = TreeSitter.node_get_child(node, i);
					this.traverse_markdown_ast(child, content, root_sections, current_parent, current_level);
				}
				return;
			}
			
			// Extract heading level from element_type (e.g., "heading1" -> 1, "heading2" -> 2)
			var heading_level = this.get_heading_level_from_element_type(element_type);
			var heading_name = this.element_name(node, content);
			
			// Early return: heading without name - recurse into children
			if (heading_name == null || heading_name == "") {
				uint child_count = TreeSitter.node_get_child_count(node);
				for (uint i = 0; i < child_count; i++) {
					var child = TreeSitter.node_get_child(node, i);
					this.traverse_markdown_ast(child, content, root_sections, current_parent, current_level);
				}
				return;
			}
			
			// Get start line from heading node (1-based). Section end_line is set by update_section_end_lines()
			// so use start_line here; the heading node's end_point is only the heading line, not the section extent.
			var start_line = (int)TreeSitter.node_get_start_point(node).row + 1;
			
			// Create section metadata (end_line set later by update_section_end_lines())
			var section = new OLLMfiles.SQT.VectorMetadata() {
				element_type = "section",
				element_name = heading_name,
				file_id = this.file.id,
				start_line = start_line,
				end_line = start_line,
				category = this.category,
				ast_path = ""
			};
			
			// Find appropriate parent based on heading level
			OLLMfiles.SQT.VectorMetadata? parent_section = null;
			if (current_parent != null && heading_level > current_level) {
				// Child of current parent
				parent_section = current_parent;
			} else if (current_parent != null) {
				// Sibling or ancestor - walk up to find appropriate parent
				parent_section = this.find_parent_by_level(current_parent, heading_level);
			}
			
			// Build hierarchy
			if (parent_section == null) {
				// Root-level section
				root_sections.add(section);
				section.ast_path = heading_name;
			} else {
				// Child section
				parent_section.children.add(section);
				section.parent = parent_section;
				section.ast_path = parent_section.ast_path + "-" + heading_name;
			}
			
			this.elements.add(section);
			
			// Recurse into children with this section as parent
			uint child_count = TreeSitter.node_get_child_count(node);
			for (uint i = 0; i < child_count; i++) {
				var child = TreeSitter.node_get_child(node, i);
				this.traverse_markdown_ast(child, content, root_sections, section, heading_level);
			}
		}
		
		/**
		 * Gets heading level from element type string (e.g., "heading1" -> 1, "heading2" -> 2).
		 */
		private int get_heading_level_from_element_type(string element_type)
		{
			// Early return: not a heading
			if (!element_type.has_prefix("heading")) {
				return 1;
			}
			
			var level_str = element_type.replace("heading", "");
			// Early return: empty level string
			if (level_str == "") {
				return 1;
			}
			
			var level = int.parse(level_str);
			// Early return: invalid level
			if (level <= 0 || level > 6) {
				return 1;
			}
			
			return level;
		}
		
		/**
		 * Finds parent section by walking up the hierarchy until finding one with level < target_level.
		 */
		private OLLMfiles.SQT.VectorMetadata? find_parent_by_level(OLLMfiles.SQT.VectorMetadata current, int target_level)
		{
			var candidate = current.parent;
			while (candidate != null) {
				// Calculate candidate's level from ast_path depth
				var candidate_level = candidate.ast_path.split("-").length;
				if (candidate_level < target_level) {
					return candidate;
				}
				candidate = candidate.parent;
			}
			return null;
		}
		
		/**
		 * Parses plain text file (creates single element).
		 */
		private void parse_plain_text()
		{
			// Create single element for entire file
			var metadata = new OLLMfiles.SQT.VectorMetadata() {
				element_type = "document",
				element_name = GLib.Path.get_basename(this.file.path),
				file_id = this.file.id,
				start_line = 1,
				end_line = this.lines.length,
				category = this.category,
				ast_path = ""
			};
			
			this.root_element = metadata;
			this.elements.add(metadata);
		}
		
	}
}
