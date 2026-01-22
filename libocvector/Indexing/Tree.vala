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
	 * Tree-sitter AST parsing and VectorMetadata creation.
	 * 
	 * Parses source code files using tree-sitter to extract code elements
	 * and create VectorMetadata objects with line numbers and documentation.
	 */
	public class Tree : OLLMfiles.TreeBase
	{
		/**
		 * Array of VectorMetadata objects extracted from the AST.
		 */
		public Gee.ArrayList<VectorMetadata> elements { get; private set; default = new Gee.ArrayList<VectorMetadata>(); }
		
		/**
		 * Constructor.
		 * 
		 * @param file The OLLMfiles.File to parse
		 */
		public Tree(OLLMfiles.File file)
		{
			base(file);
		}
		
		/**
		 * Main entry point: parse file and populate elements array.
		 * 
		 * @throws Error if parsing fails
		 */
		public async void parse() throws GLib.Error
		{
			// Load file content using base class method
			var code_content = yield this.load_file_content();
			
			// Check if this is a non-code file that we should skip (including empty language)
			// This check must come before the empty language warning
			if (this.is_unsupported_language(this.file.language ?? "")) {
				GLib.debug("SKIP - not a code file: %s (language: %s)", 
					this.file.path, this.file.language ?? "empty");
				return;
			}
			
			// Initialize parser using base class method
			yield this.init_parser();
			if (this.language == null) {
				GLib.warning("Failed to load tree-sitter language for: %s (language: %s)", 
					this.file.path, this.file.language);
				return;
			}
			
			// Parse source code using tree-sitter
			var tree = this.parse_content(code_content);
			if (tree == null) {
				throw new GLib.IOError.FAILED("Failed to parse file: " + this.file.path);
			}
			
			// Traverse AST and extract elements
			var root_node = tree.get_root_node();
			this.traverse_ast(root_node, code_content, null, null, null);
		}
		
		/**
		 * Recursively traverse AST and extract code elements.
		 * 
		 * @param node Current AST node
		 * @param code_content Source code content for text extraction
		 */
		private void traverse_ast(TreeSitter.Node node, string code_content, string? parent_enum_name = null, string? current_namespace = null, string? parent_class_name = null)
		{
			if (TreeSitter.node_is_null(node)) {
				return;
			}
			
			unowned string? node_type = TreeSitter.node_get_type(node);
			var node_type_lower = (node_type ?? "").down();
			
			// Track parent enum name for enum_value nodes
			string? current_parent_enum = parent_enum_name;
			if (node_type_lower == "enum_declaration" || node_type_lower == "enum") {
				// Extract the enum name to use as parent for enum values
				var enum_name = this.element_name(node, code_content);
				if (enum_name != null && enum_name != "") {
					current_parent_enum = enum_name;
				}
			}
			
			// Track namespace for all elements
			string? updated_namespace = current_namespace;
			if (node_type_lower == "namespace_declaration") {
				// Extract the namespace name
				var namespace_name = this.element_name(node, code_content);
				if (namespace_name != null && namespace_name != "") {
					// Build full namespace path (e.g., "OLLMvector.Indexing")
					if (current_namespace != null && current_namespace != "") {
						updated_namespace = "%s.%s".printf(current_namespace, namespace_name);
					} else {
						updated_namespace = namespace_name;
					}
				}
			}
			
			// Track parent class/struct/interface hierarchy for methods, properties, fields, etc.
			// Build hierarchical path for nested classes (e.g., "OuterClass-InnerClass")
			var updated_parent_class = parent_class_name;
			if (node_type_lower == "class_declaration" || node_type_lower == "class" ||
			    node_type_lower == "struct_declaration" || node_type_lower == "struct" ||
			    node_type_lower == "interface_declaration" || node_type_lower == "interface") {
				// Extract the class/struct/interface name to use as parent
				var class_name = this.element_name(node, code_content);
				if (class_name != null && class_name != "") {
					// Build hierarchical path for nested classes
					if (parent_class_name != null && parent_class_name != "") {
						updated_parent_class = "%s-%s".printf(parent_class_name, class_name);
					} else {
						updated_parent_class = class_name;
					}
				}
			}
			
			// Extract element metadata if this node represents a code element
			var metadata = this.extract_element_metadata(node, code_content, current_parent_enum, updated_namespace, updated_parent_class);
			if (metadata != null) {
				this.elements.add(metadata);
			}
			
			// Recursively traverse children, passing down the parent enum name, namespace, and parent class
			uint child_count = TreeSitter.node_get_child_count(node);
			for (uint i = 0; i < child_count; i++) {
				var child = TreeSitter.node_get_child(node, i);
				this.traverse_ast(child, code_content, current_parent_enum, updated_namespace, updated_parent_class);
			}
		}
		
		/**
		 * Extract code element information from AST node and create VectorMetadata.
		 * 
		 * @param node AST node
		 * @param code_content Source code content for text extraction
		 * @return VectorMetadata object, or null if node is not a code element
		 */
		private VectorMetadata? extract_element_metadata(TreeSitter.Node node, string code_content, string? parent_enum_name = null, string? namespace = null, string? parent_class = null)
		{
			// Only process named nodes (skip anonymous nodes)
			if (!TreeSitter.node_is_named(node)) {
				//GLib.debug("Skipping node: not a named node (anonymous)");
				return null;
			}
			
			// Get node type
			unowned string? node_type = TreeSitter.node_get_type(node);
			if (node_type == null) {
				//GLib.debug("Skipping node: node type is null");
				return null;
			}
			
			var start_line = (int)TreeSitter.node_get_start_point(node).row + 1;
			var end_line = (int)TreeSitter.node_get_end_point(node).row + 1;
			
			// Skip namespace_member - we only want namespace_declaration
			// This prevents duplicate namespace extraction
			var node_type_lower = node_type.down();
			if (node_type_lower == "namespace_member") {
			//	GLib.debug("Skipping node: namespace_member (lines %d-%d) - only extracting namespace_declaration", start_line, end_line);
				return null;
			}
			
			// Determine element type from node type (using base class method)
			var element_type = this.get_element_type(node, this.language);
			if (element_type == "") {
				// Not a code element we're interested in
				//GLib.debug("Skipping node: %s (lines %d-%d) - not a recognized code element type", node_type, start_line, end_line);
				return null;
			}
			
			// Skip namespace declarations - we track namespace for context but don't vectorize them separately
			if (element_type == "namespace") {
				//GLib.debug("Skipping node: namespace_declaration (lines %d-%d) - namespace tracked for context only", start_line, end_line);
				return null;
			}
			
			// Create VectorMetadata object early and assign values as we compute them
			var metadata = new VectorMetadata() {
				file_id = this.file.id,
				element_type = element_type
			};
			
			// Get element name - skip elements without proper names
			// Anonymous/internal elements aren't useful for code search
			var element_name = this.element_name(node, code_content);
			
			// For enum_value nodes, prefix with parent enum name if available
			if (node_type_lower == "enum_value" && parent_enum_name != null && parent_enum_name != "") {
				if (element_name != null && element_name != "") {
					element_name = "%s.%s".printf(parent_enum_name, element_name);
				} else {
					// If we can't get the enum value name, try to extract it from the node text
					var start_byte = TreeSitter.node_get_start_byte(node);
					var end_byte = TreeSitter.node_get_end_byte(node);
					if (end_byte > start_byte) {
						var value_text = code_content.substring((int)start_byte, (int)(end_byte - start_byte)).strip();
						// Remove trailing comma if present
						if (value_text.has_suffix(",")) {
							value_text = value_text.substring(0, value_text.length - 1).strip();
						}
						if (value_text != null && value_text != "") {
							element_name = "%s.%s".printf(parent_enum_name, value_text);
						}
					}
				}
			}
			
			// For classes and namespaces only, try fallback if primary extraction failed
			// But only if the node type actually indicates it's a class/namespace declaration
			// (not just a type reference in a property or method signature)
			bool is_class_or_namespace_decl = false;
			if (node_type != null) {
				is_class_or_namespace_decl = (node_type_lower.contains("class") && 
					(node_type_lower.contains("declaration") || node_type_lower == "class")) ||
					(node_type_lower.contains("namespace") && 
					(node_type_lower.contains("declaration") || node_type_lower == "namespace"));
			}
			
			if ((element_name == null || element_name == "") && 
			    (element_type == "class" || element_type == "namespace") &&
			    is_class_or_namespace_decl) {
				element_name = this.extract_first_identifier(node, code_content);
				// Validate fallback name - must be reasonable length and not a keyword
				if (element_name != null && element_name != "") {
					var name_lower = element_name.down();
					// Check it's not obviously wrong (too short, is a keyword, etc.)
					if (element_name.length < 3 || name_lower == "public" || name_lower == "private" || 
					    name_lower == "class" || name_lower == "namespace" || element_name.has_prefix("_")) {
						element_name = null;
					}
				}
			}
			
			if (element_name == null || element_name == "") {
				// Skip elements without names - they're likely internal implementation details
				GLib.debug("Skipping %s (lines %d-%d): element has no name", element_type, start_line, end_line);
				return null;
			}
			
			// Skip if too short or starts with underscore (likely internal)
			if (element_name.length < 2) {
				GLib.debug("Skipping %s: %s (lines %d-%d): name too short (< 2 chars)", element_type, element_name, start_line, end_line);
				return null;
			}
			if (element_name.has_prefix("_")) {
				GLib.debug("Skipping %s: %s (lines %d-%d): name starts with underscore (likely internal)", element_type, element_name, start_line, end_line);
				return null;
			}
			
			metadata.element_name = element_name;
			
			// Set namespace if available
			if (namespace != null && namespace != "") {
				metadata.namespace = namespace;
			}
			
			// Set parent class if available (for methods, properties, fields, etc.)
			// Don't set it for the class/struct/interface itself
			// Reuse node_type_lower that was already declared earlier
			bool is_class_or_struct_or_interface = 
					(node_type_lower == "class_declaration" || node_type_lower == "class" ||
					node_type_lower == "struct_declaration" || node_type_lower == "struct" ||
					node_type_lower == "interface_declaration" || node_type_lower == "interface");
			
			// Detect constructors: methods with the same name as their parent class
			if (element_type == "method" && parent_class != null && parent_class != "" && 
			    element_name == parent_class) {
				element_type = "constructor";
				metadata.element_type = "constructor";
			}
			if (parent_class != null && parent_class != "" && !is_class_or_struct_or_interface) {
				metadata.parent_class = parent_class;
			}
			
			// Get line numbers (tree-sitter uses 0-indexed, we use 1-indexed)
			metadata.start_line = (int)TreeSitter.node_get_start_point(node).row + 1;  // Convert to 1-indexed
			metadata.end_line = (int)TreeSitter.node_get_end_point(node).row + 1;      // Convert to 1-indexed
			
			// Extract signature for all elements (helps with debugging and understanding what was extracted)
			metadata.signature = this.extract_signature(node, code_content);
			
			// Extract documentation block line numbers
			this.extract_documentation_lines(node, metadata);
			
			// Build AST path from node by traversing up the AST using base class method
			metadata.ast_path = this.ast_path(node, code_content);
			GLib.debug("extract_element_metadata: set ast_path='%s' for %s %s (lines %d-%d)", 
				metadata.ast_path, element_type, element_name, metadata.start_line, metadata.end_line);
			
			return metadata;
		}
		
		/**
		 * Extract documentation block line numbers using tree-sitter API.
		 * 
		 * @param node AST node for the code element
		 * @param metadata VectorMetadata object to set codedoc_start and codedoc_end on
		 */
		private void extract_documentation_lines(TreeSitter.Node node, VectorMetadata metadata)
		{
			// Get the element's start position
			var element_start = TreeSitter.node_get_start_point(node);
			var element_start_line = (int)element_start.row + 1;  // 1-indexed
			
			// Look for comment nodes before this element
			// We traverse backwards from the element to find preceding comments
			var parent = TreeSitter.node_get_parent(node);
			if (TreeSitter.node_is_null(parent)) {
				return;
			}
			
			// Find the element's position among siblings
			var child_count = TreeSitter.node_get_child_count(parent);
			var element_index = -1;
			for (uint i = 0; i < child_count; i++) {
				var child = TreeSitter.node_get_child(parent, i);
				if (TreeSitter.node_equals(child, node)) {
					element_index = (int)i;
					break;
				}
			}
			
			if (element_index < 0) {
				return;
			}
			
			// Look backwards through siblings for comment nodes
			for (int i = element_index - 1; i >= 0; i--) {
				var sibling = TreeSitter.node_get_child(parent, (uint)i);
				if (TreeSitter.node_is_null(sibling)) {
					continue;
				}
				
				unowned string? sibling_type = TreeSitter.node_get_type(sibling);
				if (sibling_type == null) {
					continue;
				}
				
				// Check if this is a comment node (varies by language)
				var type_lower = sibling_type.down();
				if (!type_lower.contains("comment") && 
				    type_lower != "line_comment" && 
				    type_lower != "block_comment" &&
				    type_lower != "doc_comment" &&
				    !type_lower.contains("doc")) {
					// Not a comment, stop looking backwards
					return;
				}
				
				var sibling_end_line = (int)TreeSitter.node_get_end_point(sibling).row + 1;
				
				// Check if comment is adjacent to the element (within a few lines)
				if (sibling_end_line >= element_start_line || 
				    (element_start_line - sibling_end_line) > 2) {
					// Comment is too far away, stop looking
					return;
				}
				
				// This comment is likely documentation for the element
				if (metadata.codedoc_end == -1) {
					metadata.codedoc_end = sibling_end_line;
				}
				metadata.codedoc_start = (int)TreeSitter.node_get_start_point(sibling).row + 1;
			}
		}
		
		
		/**
		 * Extract first identifier from node text as fallback name extraction.
		 * 
		 * @param node AST node
		 * @param code_content Source code content
		 * @return First identifier found, or null
		 */
		private string? extract_first_identifier(TreeSitter.Node node, string code_content)
		{
			// Get node text
			var start_byte = TreeSitter.node_get_start_byte(node);
			var end_byte = TreeSitter.node_get_end_byte(node);
			if (end_byte <= start_byte) {
				return null;
			}
			
			var node_text = code_content.substring((int)start_byte, (int)(end_byte - start_byte));
			if (node_text == null || node_text == "") {
				return null;
			}
			
			// Try to find first identifier using regex-like approach
			// Look for word characters after common keywords
			var text_lower = node_text.down();
			string[] keywords = { "class", "method", "function", "property", "namespace", "public", "private" };
			foreach (var keyword in keywords) {
				var keyword_pos = text_lower.index_of(keyword);
				if (keyword_pos >= 0) {
					// Find next identifier after keyword
					var after_keyword = node_text.substring(keyword_pos + keyword.length);
					// Skip whitespace and find identifier
					MatchInfo match_info;
					if (/^[\s]*([a-zA-Z_][a-zA-Z0-9_]*)/.match(after_keyword, 0, out match_info)) {
						var identifier = match_info.fetch(1);
						if (identifier != null && identifier != "" && identifier.length < 100) {
							return identifier;
						}
					}
				}
			}
			
			// Fallback: find first identifier-like pattern
			MatchInfo match_info2;
			if (/([a-zA-Z_][a-zA-Z0-9_]*)/.match(node_text, 0, out match_info2)) {
				var identifier = match_info2.fetch(1);
				if (identifier != null && identifier != "" && identifier.length < 100) {
					return identifier;
				}
			}
			
			return null;
		}
		
		/**
		 * Extract method/function signature from AST node.
		 * 
		 * @param node AST node for method/function
		 * @param code_content Source code content
		 * @return Signature string (e.g., "public async void parse() throws GLib.Error")
		 */
		private string extract_signature(TreeSitter.Node node, string code_content)
		{
			unowned string? node_type = TreeSitter.node_get_type(node);
			var node_type_lower = (node_type ?? "").down();
			
			// Get the start and end of the signature
			var start_byte = TreeSitter.node_get_start_byte(node);
			var end_byte = TreeSitter.node_get_end_byte(node);
			var node_text = code_content.substring((int)start_byte, (int)(end_byte - start_byte));
			
			// For property declarations, include the accessors (get/set/default) inside the braces
			// For other elements (methods, classes), stop at the opening brace
			if (node_type_lower == "property_declaration") {
				// Find the closing brace to include the full property declaration
				var closing_brace_pos = node_text.last_index_of("}");
				if (closing_brace_pos >= 0) {
					// Extract up to and including the closing brace
					var signature_text = node_text.substring(0, closing_brace_pos + 1);
					signature_text = this.clean_signature_whitespace(signature_text);
					// Ensure proper spacing around braces and semicolons
					signature_text = signature_text.replace("{", " { ").replace("}", " } ");
					signature_text = signature_text.replace(";", "; ");
					// Collapse multiple spaces again after adding spacing
					signature_text = this.clean_signature_whitespace(signature_text);
					return signature_text.strip();
				}
			}
			
			// For other elements, find the opening brace to get just the signature line(s)
			var brace_pos = node_text.index_of("{");
			if (brace_pos >= 0) {
				// Extract up to the opening brace
				var signature_text = node_text.substring(0, brace_pos);
				signature_text = this.clean_signature_whitespace(signature_text);
				return signature_text.strip();
			}
			
			// Fallback: if no brace found, return first line
			var first_newline = node_text.index_of("\n");
			if (first_newline >= 0) {
				var signature_text = node_text.substring(0, first_newline);
				signature_text = this.clean_signature_whitespace(signature_text);
				return signature_text.strip();
			}
			
			var signature_text = node_text;
			signature_text = this.clean_signature_whitespace(signature_text);
			return signature_text.strip();
		}
		
		/**
		 * Clean excessive whitespace from signature text.
		 * Removes newlines, tabs, and collapses multiple spaces to single spaces.
		 */
		private string clean_signature_whitespace(string text)
		{
			// Replace all newlines, carriage returns, and tabs with spaces
			var cleaned = text.replace("\n", " ").replace("\r", " ").replace("\t", " ");
			// Collapse multiple spaces to single spaces
			while (cleaned.contains("  ")) {
				cleaned = cleaned.replace("  ", " ");
			}
			return cleaned;
		}
	}
}

