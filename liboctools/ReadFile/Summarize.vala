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

namespace OLLMtools.ReadFile
{
	/**
	 * Tree-sitter based file structure summarizer.
	 * 
	 * Parses source code files using tree-sitter to extract code elements
	 * and output a markdown summary with indentation following file structure.
	 */
	public class Summarize : OLLMfiles.TreeBase
	{
		/**
		 * Markdown output buffer.
		 */
		private GLib.StringBuilder output = new GLib.StringBuilder();
		
		/**
		 * Current indentation level (number of spaces).
		 */
		private int indent_level = 0;
		
		/**
		 * Indentation step (spaces per level).
		 */
		private const int INDENT_STEP = 3;
		
		/**
		 * Constructor.
		 * 
		 * @param file The OLLMfiles.File to parse
		 */
		public Summarize(OLLMfiles.File file)
		{
			base(file);
		}
		
		/**
		 * Main entry point: parse file and generate markdown summary.
		 * 
		 * @throws Error if parsing fails
		 * @return Markdown summary string
		 */
		public async string summarize() throws GLib.Error
		{
			// Load file content using base class method
			var code_content = yield this.load_file_content();
			
			// Check if this is a non-code file that we should skip
			if (this.is_unsupported_language(this.file.language ?? "")) {
				return "# File Summary\n\n* text file (not a code file)\n";
			}
			
			// Initialize parser using base class method
			// GLib.debug("ReadFileSummarize: Initializing parser for language: %s", this.file.language ?? "null");
			yield this.init_parser();
			if (this.language == null) {
				// GLib.debug("ReadFileSummarize: Language is null after init_parser");
				return "# File Summary\n\n* unsupported language: " + (this.file.language ?? "unknown") + "\n";
			}
			// GLib.debug("ReadFileSummarize: Language loaded successfully");
			
			// Parse source code using tree-sitter
			var tree = this.parse_content(code_content);
			if (tree == null) {
				// GLib.debug("ReadFileSummarize: parse_content returned null");
				throw new GLib.IOError.FAILED("Failed to parse file: " + this.file.path);
			}
			// GLib.debug("ReadFileSummarize: Tree parsed successfully");
			
			// Initialize output
			this.output = new GLib.StringBuilder();
			this.output.append("# File Summary\n\n");
			
			// Traverse AST and extract elements
			var root_node = tree.get_root_node();
			unowned string? root_type = TreeSitter.node_get_type(root_node);
			// GLib.debug("ReadFileSummarize: Root node type: %s", root_type ?? "null");
			// GLib.debug("ReadFileSummarize: Root node child count: %u", TreeSitter.node_get_child_count(root_node));
			// GLib.debug("ReadFileSummarize: Root node named child count: %u", TreeSitter.node_get_named_child_count(root_node));
			this.traverse_ast(root_node, code_content, null, null, null, null);
			
			return this.output.str;
		}
		
		
		/**
		 * Recursively traverse AST and extract code elements, outputting markdown.
		 * 
		 * @param node Current AST node
		 * @param code_content Source code content for text extraction
		 * @param parent_enum_name Parent enum name (for enum values)
		 * @param current_namespace Current namespace
		 * @param parent_class_name Parent class/struct/interface name
		 */
		private void traverse_ast(TreeSitter.Node node, string code_content, string? parent_enum_name = null, string? current_namespace = null, string? parent_class_name = null, TreeSitter.Node? parent_section = null)
		{
			if (TreeSitter.node_is_null(node)) {
				return;
			}
			
			unowned string? node_type = TreeSitter.node_get_type(node);
			var node_type_lower = (node_type ?? "").down();
			var start_line = (int)TreeSitter.node_get_start_point(node).row + 1;
			var end_line = (int)TreeSitter.node_get_end_point(node).row + 1;
			
			// For markdown: track section nodes that contain headings and their content
			TreeSitter.Node? current_section = parent_section;
			if (node_type_lower == "section") {
				current_section = node;
			}
			
			// Special case: Check if this is a list_item that contains a heading
			// Headings inside list items might be parsed as separate nodes
			if (node_type_lower == "list_item") {
				var child_count = TreeSitter.node_get_child_count(node);
				// Look for a sequence of '#' nodes followed by text that looks like a heading
				for (uint i = 0; i < child_count; i++) {
					var child = TreeSitter.node_get_child(node, i);
					if (TreeSitter.node_is_null(child)) {
						continue;
					}
					unowned string? child_type = TreeSitter.node_get_type(child);
					if (child_type == null) {
						continue;
					}
					// Check if this child or its children form a heading pattern
					var child_start_line = (int)TreeSitter.node_get_start_point(child).row + 1;
					if (child_start_line == start_line && (child_type == "#" || child_type.down() == "block_continuation")) {
						// This might be part of a heading - check siblings
						int hash_count = 0;
						uint j = i;
						while (j < child_count && hash_count < 6) {
							var sibling = TreeSitter.node_get_child(node, j);
							unowned string? sibling_type = TreeSitter.node_get_type(sibling);
							if (sibling_type != null && sibling_type == "#") {
								hash_count++;
								j++;
							} else {
								break;
							}
						}
						if (hash_count >= 1 && hash_count <= 6) {
							// GLib.debug("ReadFileSummarize.traverse_ast: Found heading pattern in list_item: %d hashes starting at index %u", hash_count, i);
							// We found a heading pattern - process it specially
							// The heading text should be in subsequent children
						}
					}
				}
			}
			
			// Debug: log all nodes at top level or with interesting types, and nodes around line 1145
			// if (this.indent_level == 0 || node_type_lower.has_prefix("heading") || node_type_lower.has_prefix("atx") || 
			//     (start_line >= 1143 && start_line <= 1147)) {
			// 	var parent_info = "";
			// 	// Try to get parent info if possible (we don't have direct parent access, but we can log context)
			// 	GLib.debug("ReadFileSummarize.traverse_ast: Node type='%s' lines %d-%d named=%s indent=%d", 
			// 		node_type ?? "null", start_line, end_line, 
			// 		TreeSitter.node_is_named(node).to_string(), this.indent_level);
			// }
			
			// Track parent enum name for enum_value nodes
			string? current_parent_enum = parent_enum_name;
			if (node_type_lower == "enum_declaration" || node_type_lower == "enum") {
				var enum_name = this.element_name(node, code_content);
				if (enum_name != null && enum_name != "") {
					current_parent_enum = enum_name;
				}
			}
			
			// Track namespace for all elements
			string? updated_namespace = current_namespace;
			if (node_type_lower == "namespace_declaration") {
				var namespace_name = this.element_name(node, code_content);
				if (namespace_name != null && namespace_name != "") {
					if (current_namespace != null && current_namespace != "") {
						updated_namespace = "%s.%s".printf(current_namespace, namespace_name);
					} else {
						updated_namespace = namespace_name;
					}
				}
			}
			
			// Track parent class/struct/interface for methods, properties, fields, etc.
			string? updated_parent_class = parent_class_name;
			if (node_type_lower == "class_declaration" || node_type_lower == "class" ||
			    node_type_lower == "struct_declaration" || node_type_lower == "struct" ||
			    node_type_lower == "interface_declaration" || node_type_lower == "interface") {
				var class_name = this.element_name(node, code_content);
				if (class_name != null && class_name != "") {
					updated_parent_class = class_name;
				}
			}
			
			// Extract and output element if this node represents a code element
			var element_type = this.get_element_type(node, this.language);
			string? cached_element_name = null;
			bool should_output = false;
			int saved_indent = this.indent_level;
			
			// Special case: For block_continuation nodes, check if they're part of a heading pattern
			// by trying to extract a name first - if we get a heading-like name, it's a heading
			// The element_name function already checks the line content and extracts the name
			// If it successfully extracts a name from a block_continuation, it means it found a heading pattern
			if (node_type_lower == "block_continuation" && element_type == "") {
				cached_element_name = this.element_name(node, code_content);
				// If we extracted a name, check the line to determine heading level
				if (cached_element_name != null && cached_element_name != "") {
					// Get the line content to check for heading level
					var start_byte = TreeSitter.node_get_start_byte(node);
					// Find line start (search backwards for newline)
					int line_start = -1;
					for (int i = (int)start_byte - 1; i >= 0 && i >= (int)start_byte - 500; i--) {
						if (code_content[i] == '\n') {
							line_start = i;
							break;
						}
					}
					// Find line end (search forwards for newline)
					int line_end = (int)code_content.length;
					for (uint32 i = start_byte; i < code_content.length && i < start_byte + 500; i++) {
						if (code_content[i] == '\n') {
							line_end = (int)i;
							break;
						}
					}
					
					if (line_end > line_start + 1) {
						var line_text = code_content.substring(line_start + 1, line_end - line_start - 1);
						// Check if line starts with 1-6 '#' characters
						int hash_count = 0;
						for (int i = 0; i < line_text.length && i < 6; i++) {
							if (line_text[i] == '#') {
								hash_count++;
							} else if (line_text[i] == ' ' || line_text[i] == '\t') {
								continue;
							} else {
								break;
							}
						}
						
							if (hash_count >= 1 && hash_count <= 6) {
								element_type = "heading" + hash_count.to_string();
								// GLib.debug("ReadFileSummarize.traverse_ast: Detected heading%d from block_continuation pattern at line %d", hash_count, start_line);
							}
					}
				}
			}
			
			// Debug: log element type detection (including block_continuation for investigation)
			// if (element_type != "" || node_type_lower.has_prefix("heading") || node_type_lower.has_prefix("atx") || node_type_lower == "block_continuation") {
			// 	GLib.debug("ReadFileSummarize.traverse_ast: element_type='%s' for node_type='%s' lines %d-%d", 
			// 		element_type, node_type ?? "null", start_line, end_line);
			// }
			
			if (element_type != "") {
				// Skip namespace declarations - we track namespace for context but don't output them separately
				if (element_type != "namespace") {
					cached_element_name = this.element_name(node, code_content);
					
					// Debug: log name extraction
					// if (element_type.has_prefix("heading") || node_type_lower.has_prefix("heading") || node_type_lower.has_prefix("atx")) {
					// 	GLib.debug("ReadFileSummarize.traverse_ast: extracted name='%s' for element_type='%s' lines %d-%d", 
					// 		cached_element_name ?? "null", element_type, start_line, end_line);
					// }
					
					// For enum_value nodes, prefix with parent enum name if available
					if (node_type_lower == "enum_value" && current_parent_enum != null && current_parent_enum != "") {
						if (cached_element_name != null && cached_element_name != "") {
							cached_element_name = "%s.%s".printf(current_parent_enum, cached_element_name);
						}
					}
					
					// Only output if we have a name (skip anonymous elements)
					if (cached_element_name != null && cached_element_name != "") {
						should_output = true;
						// start_line and end_line already calculated above
						
						// For markdown headings, use section end line if available (includes all content)
						int output_end_line = end_line;
						if (element_type.has_prefix("heading") && current_section != null && !TreeSitter.node_is_null(current_section)) {
							var section_end_line = (int)TreeSitter.node_get_end_point(current_section).row + 1;
							if (section_end_line > end_line) {
								output_end_line = section_end_line;
							}
						}
						
						// For markdown headings, set indent based on heading level (h1=0, h2=1, etc.)
						if (element_type.has_prefix("heading")) {
							var heading_num_str = element_type.substring(7);  // Remove "heading" prefix
							var heading_num = int.parse(heading_num_str);
							if (heading_num > 0 && heading_num <= 6) {
								this.indent_level = heading_num - 1;
							}
						}
						
						// Output markdown line with indentation
						this.output_indented_line(element_type, cached_element_name, start_line, output_end_line);
						
						// Increase indent for children (for code elements, not markdown headings)
						if (!element_type.has_prefix("heading")) {
							this.indent_level++;
						}
					}
				}
			}
			
			// Special handling: Check if we're in a context where '#' nodes indicate a heading
			// When headings appear after list items, they might be parsed as block_continuation + '#' siblings
			// Look ahead to see if the next siblings are '#' characters
			// if (node_type_lower == "block_continuation" && start_line >= 1143 && start_line <= 1147) {
			// 	GLib.debug("ReadFileSummarize.traverse_ast: Found block_continuation at line %d, checking siblings", start_line);
			// }
			
			// Recursively traverse children
			uint child_count = TreeSitter.node_get_child_count(node);
			for (uint i = 0; i < child_count; i++) {
				var child = TreeSitter.node_get_child(node, i);
				this.traverse_ast(child, code_content, current_parent_enum, updated_namespace, updated_parent_class, current_section);
			}
			
			// After processing children, check if this node and its siblings form a heading pattern
			// This handles cases where headings are parsed as separate nodes (block_continuation + '#' + text)
			// We can't easily check siblings from here, so we'll handle this in get_element_type/element_name
			// by checking the node's position and looking at the raw text content
			
			// Decrease indent after processing children (use cached element_name)
			// For markdown headings, restore saved indent; for code elements, decrease by 1
			if (should_output) {
				if (element_type.has_prefix("heading")) {
					this.indent_level = saved_indent;
				} else {
					this.indent_level--;
				}
			}
		}
		
		/**
		 * Output an indented markdown line for an element.
		 * 
		 * @param type Element type (e.g., "class", "method")
		 * @param name Element name
		 * @param start_line Starting line number (1-indexed)
		 * @param end_line Ending line number (1-indexed)
		 */
		private void output_indented_line(string type, string name, int start_line, int end_line)
		{
			// Generate indentation
			var indent = string.nfill(this.indent_level * INDENT_STEP, ' ');
			
			// Build the entire line in one operation
			string line = indent + "* " + type + " " + name + " lines " + start_line.to_string();
			if (end_line != start_line) {
				line = line + "-" + end_line.to_string();
			}
			line = line + "\n";
			
			this.output.append(line);
		}
	}
}

