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
	 * Tree-sitter AST parsing and VectorMetadata creation.
	 * 
	 * Parses source code files using tree-sitter to extract code elements
	 * and create VectorMetadata objects with line numbers and documentation.
	 */
	public class Tree : Object
	{
		/**
		 * The file being parsed.
		 */
		public OLLMfiles.File file { get; private set; }
		
		/**
		 * Array of VectorMetadata objects extracted from the AST.
		 */
		public Gee.ArrayList<VectorMetadata> elements { get; private set; default = new Gee.ArrayList<VectorMetadata>(); }
		
		/**
		 * File content split into lines (0-indexed array).
		 */
		public string[] lines { get; private set; }
		
		private TreeSitter.Parser parser = new TreeSitter.Parser();
		private TreeSitter.Language? language;
		private unowned GLib.Module? loaded_module;  // Keep module loaded to prevent language object from becoming invalid
		
		[CCode (has_target = false)]
		private delegate unowned TreeSitter.Language TreeSitterLanguageFunc();
		
		/**
		 * Constructor.
		 * 
		 * @param file The OLLMfiles.File to parse
		 */
		public Tree(OLLMfiles.File file)
		{
			this.file = file;
		}
		
		/**
		 * Check if language is supported by tree-sitter (or should be skipped).
		 * 
		 * @param lang_name Language name (normalized to lowercase)
		 * @return true if language should be skipped (not a code file), false if we should try to load it
		 */
		private bool is_unsupported_language(string lang_name)
		{
			// Handle empty/null language as unsupported
			if (lang_name == null || lang_name == "") {
				return true;
			}
			
			var lang_lower = lang_name.down();
			switch (lang_lower) {
				case "markdown":
				case "html":
				case "htm":
				case "xhtml":
				case "css":
				case "txt":
				case "text":
				case "plaintext":
					return true;
				default:
					return false;
			}
		}
		
		/**
		 * Main entry point: parse file and populate elements array.
		 * 
		 * @throws Error if parsing fails
		 */
		public async void parse() throws GLib.Error
		{
			// Load file content lazily (only when needed for parsing)
			// Use read_async() to read from disk since buffer may not be loaded
			var code_content = yield this.file.read_async();
			if (code_content == null || code_content == "") {
				throw new GLib.IOError.NOT_FOUND("File is empty or cannot be read: " + this.file.path);
			}
			
			// Split into lines
			this.lines = code_content.split("\n");
			
			// Check if this is a non-code file that we should skip (including empty language)
			// This check must come before the empty language warning
			if (this.is_unsupported_language(this.file.language ?? "")) {
				GLib.debug("SKIP - not a code file: %s (language: %s)", 
					this.file.path, this.file.language ?? "empty");
				return;
			}
			
			// Load tree-sitter language dynamically using GModule
			this.language = this.load_tree_sitter_language();
			if (this.language == null) {
				GLib.warning("Failed to load tree-sitter language for: %s (language: %s)", 
					this.file.path, this.file.language);
				return;
			}
			
			// Set language on parser
			if (!this.parser.set_language(this.language)) {
				throw new GLib.IOError.FAILED("Failed to set tree-sitter language for file: " + this.file.path);
			}
			
			// Parse source code using tree-sitter
			var tree = this.parser.parse_string(null, code_content, (uint32)code_content.length);
			if (tree == null) {
				throw new GLib.IOError.FAILED("Failed to parse file: " + this.file.path);
			}
			
			// Traverse AST and extract elements
			var root_node = tree.get_root_node();
			this.traverse_ast(root_node, code_content, null, null, null);
		}
		
		/**
		 * Load tree-sitter language dynamically from shared library using GModule.
		 * 
		 * @return TreeSitter.Language object, or null if loading fails
		 */
		private TreeSitter.Language? load_tree_sitter_language()
		{
			// Get language from file
			var file_lang = this.file.language;
			if (file_lang == null || file_lang == "") {
				return null;
			}
			
			// Normalize language name
			var lang_name = file_lang.down();
			
			// Map language names to tree-sitter library/function names using switch/case
			// Most languages use the name as-is (default case)
			// Note: GtkSource.LanguageManager returns "js" but tree-sitter uses "javascript"
			// We map these differences here
			switch (lang_name) {
				case "c++":
				case "cxx":
					lang_name = "cpp";
					break;
				case "csharp":
					lang_name = "c_sharp";
					break;
				case "sh":
					lang_name = "bash";  // tree-sitter uses "bash" not "sh"
					break;
				case "js":
					lang_name = "javascript";  // GtkSource returns "js" but tree-sitter uses "javascript"
					break;
				default:
					break;
			}
			
			// Normalize for function/library names (replace hyphens with underscores)
			var normalized_lang = lang_name.replace("-", "_");
			
			// Build library names: try parser_{lang}.so (Debian/Ubuntu) and libtree-sitter-{lang}.so (standard)
			var lib_name = "parser_" + lang_name + ".so";
			var alt_lib_name = "libtree-sitter-" + lang_name + ".so";
			
			// Build function name: tree_sitter_{lang}
			var func_name = "tree_sitter_" + normalized_lang;
			
			// Try both library naming conventions
			// GLib.Module.open() will search system library paths automatically
			string[] lib_names = { lib_name, alt_lib_name };
			
			foreach (var current_lib_name in lib_names) {
				// Load the parser library using GModule (searches system library paths)
				var module = GLib.Module.open(current_lib_name, GLib.ModuleFlags.LAZY | GLib.ModuleFlags.LOCAL);
				if (module == null) {
					GLib.debug("Failed to open module %s: %s", current_lib_name, GLib.Module.error());
					continue;
				}
				GLib.debug("Opened library: %s", current_lib_name);
				
				// Get the function symbol
				void* func_ptr;
				if (!module.symbol(func_name, out func_ptr)) {
					GLib.debug("Function '%s' not found in %s: %s", func_name, current_lib_name, GLib.Module.error());
					module.close();
					continue;
				}
				GLib.debug("Found function '%s' in %s", func_name, current_lib_name);
				
				// Cast function pointer to Language* ()(void) - tree-sitter language functions take no args
				// The function signature is: const TSLanguage* tree_sitter_{lang}(void)
				TreeSitterLanguageFunc lang_func = (TreeSitterLanguageFunc)func_ptr;
				unowned TreeSitter.Language? language = lang_func();
				
				if (language != null) {
					// Keep the module loaded - make it resident so it won't be unloaded
					// The language object depends on symbols from the module
					module.make_resident();
					this.loaded_module = module;
					return language;
				}
				
				module.close();
			}
			
			GLib.debug("Tree-sitter language library not found for: %s (searched for %s)", 
				this.file.language, lib_name);
			return null;
		}
		
		/**
		 * Extract string from lines array using Vala string range syntax.
		 * 
		 * @param start_line Starting line number (1-indexed, or -1 for invalid/no content)
		 * @param end_line Ending line number (1-indexed, exclusive, or -1 for invalid/no content)
		 * @param max_lines Maximum number of lines to return (0 or negative = no truncation)
		 * @return Code snippet or documentation text (empty string if invalid range, truncated if max_lines > 0)
		 */
		public string lines_to_string(int start_line, int end_line, int max_lines = 0)
		{
			// Handle invalid/negative line numbers (e.g., -1 indicates no documentation)
			if (start_line <= 0 || end_line <= 0 || start_line > end_line) {
				return "";
			}
			
			// Convert 1-indexed line numbers to 0-based array indices
			var start_idx = (start_line - 1).clamp(0, this.lines.length - 1);
			var end_idx = end_line.clamp(0, this.lines.length);
			
			if (start_idx >= end_idx) {
				return "";
			}
			
			// Use Vala array slicing: lines[start_idx:end_idx]
			var slice = this.lines[start_idx:end_idx];
			var result = string.joinv("\n", slice);
			
			// Apply truncation if max_lines is specified and positive
			if (max_lines > 0 && slice.length > max_lines) {
				var truncated_slice = this.lines[start_idx:start_idx + max_lines];
				var truncated = string.joinv("\n", truncated_slice);
				var total_lines = end_line - start_line + 1;
				return truncated + "\n\n// ... (code truncated: showing first " + max_lines.to_string() + " of " + total_lines.to_string() + " lines) ...";
			}
			
			return result;
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
				var enum_name = this.get_element_name(node, code_content);
				if (enum_name != null && enum_name != "") {
					current_parent_enum = enum_name;
				}
			}
			
			// Track namespace for all elements
			string? updated_namespace = current_namespace;
			if (node_type_lower == "namespace_declaration") {
				// Extract the namespace name
				var namespace_name = this.get_element_name(node, code_content);
				if (namespace_name != null && namespace_name != "") {
					// Build full namespace path (e.g., "OLLMvector.Indexing")
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
				// Extract the class/struct/interface name to use as parent
				var class_name = this.get_element_name(node, code_content);
				if (class_name != null && class_name != "") {
					updated_parent_class = class_name;
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
				GLib.debug("Skipping node: not a named node (anonymous)");
				return null;
			}
			
			// Get node type
			unowned string? node_type = TreeSitter.node_get_type(node);
			if (node_type == null) {
				GLib.debug("Skipping node: node type is null");
				return null;
			}
			
			var start_line = (int)TreeSitter.node_get_start_point(node).row + 1;
			var end_line = (int)TreeSitter.node_get_end_point(node).row + 1;
			
			// Skip namespace_member - we only want namespace_declaration
			// This prevents duplicate namespace extraction
			var node_type_lower = node_type.down();
			if (node_type_lower == "namespace_member") {
				GLib.debug("Skipping node: namespace_member (lines %d-%d) - only extracting namespace_declaration", start_line, end_line);
				return null;
			}
			
			// Determine element type from node type
			var element_type = this.get_element_type(node, this.language);
			if (element_type == "") {
				// Not a code element we're interested in
				GLib.debug("Skipping node: %s (lines %d-%d) - not a recognized code element type", node_type, start_line, end_line);
				return null;
			}
			
			// Create VectorMetadata object early and assign values as we compute them
			var metadata = new VectorMetadata() {
				file_id = this.file.id,
				element_type = element_type
			};
			
			// Get element name - skip elements without proper names
			// Anonymous/internal elements aren't useful for code search
			var element_name = this.get_element_name(node, code_content);
			
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
			
			// VERY RISKY: Filtering elements by name characteristics may lose important information
			// Different languages have different naming conventions (e.g., single-letter names, underscore prefixes)
			// This filtering could incorrectly exclude valid elements in some languages
			// TODO: Consider making this configurable or language-aware, or remove entirely
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
		 * Static map of node type patterns to element types.
		 * Maps tree-sitter node type patterns to our element type strings.
		 */
		private static Gee.HashMap<string, string> element_type_map;
		
		static construct
		{
			element_type_map = new Gee.HashMap<string, string>();
			element_type_map.set("class", "class");
			element_type_map.set("class_declaration", "class");
			element_type_map.set("struct", "struct");
			element_type_map.set("struct_declaration", "struct");
			element_type_map.set("interface", "interface");
			element_type_map.set("interface_declaration", "interface");
			element_type_map.set("enum", "enum_type");
			element_type_map.set("enum_declaration", "enum_type");
			element_type_map.set("enum_value", "enum");
			// Only map namespace_declaration, not namespace (which might be a member)
			element_type_map.set("namespace_declaration", "namespace");
			element_type_map.set("function", "function");
			element_type_map.set("method", "method");
			element_type_map.set("method_declaration", "method");
			element_type_map.set("method_definition", "method");
			element_type_map.set("constructor", "constructor");
			element_type_map.set("property", "property");
			element_type_map.set("property_declaration", "property");
			element_type_map.set("field", "field");
			element_type_map.set("field_declaration", "field");
			element_type_map.set("delegate", "delegate");
			element_type_map.set("signal", "signal");
			element_type_map.set("constant", "constant");
			element_type_map.set("constant_declaration", "constant");
		}
		
		/**
		 * Determine element type from tree-sitter node type.
		 * 
		 * @param node AST node
		 * @param lang Tree-sitter language
		 * @return Element type string (e.g., "class", "method", "function"), or empty string if not a code element
		 */
		private string get_element_type(TreeSitter.Node node, TreeSitter.Language lang)
		{
			unowned string? node_type = TreeSitter.node_get_type(node);
			if (node_type == null) {
				return "";
			}
			
			var type_lower = node_type.down();
			
			// Check exact matches first
			if (element_type_map.has_key(type_lower)) {
				return element_type_map.get(type_lower);
			}
			
			// Check contains patterns using foreach loop
			foreach (var entry in element_type_map.entries) {
				if (type_lower.contains(entry.key)) {
					// Special case: function should not match if it contains "method"
					if (entry.key == "function" && type_lower.contains("method")) {
						continue;
					}
					return entry.value;
				}
			}
			
			// Not a recognized code element type
			return "";
		}
		
		/**
		 * Get element name from AST node.
		 * 
		 * @param node AST node
		 * @param code_content Source code content for text extraction
		 * @return Element name, or null if not found
		 */
		private string? get_element_name(TreeSitter.Node node, string code_content)
		{
			unowned string? node_type = TreeSitter.node_get_type(node);
			var start_line = (int)TreeSitter.node_get_start_point(node).row + 1;
			
			// Strategy 1: Try to get name from field (most reliable)
			// Try common field names that tree-sitter grammars use
			string[] field_names = { "name", "identifier", "type", "property_name", "method_name" };
			foreach (var field_name in field_names) {
				var name_node = TreeSitter.node_get_child_by_field_name(node, field_name, (uint32)field_name.length);
				if (TreeSitter.node_is_null(name_node)) {
					continue;
				}
				
				var start_byte = TreeSitter.node_get_start_byte(name_node);
				var end_byte = TreeSitter.node_get_end_byte(name_node);
				if (end_byte <= start_byte) {
					continue;
				}
				
				var name = code_content.substring((int)start_byte, (int)(end_byte - start_byte));
				if (name != null && name != "") {
					return name;
				}
			}
			
			// Strategy 2: Look for identifier/name nodes in direct children
			var child_count = TreeSitter.node_get_child_count(node);
			
			// Debug: Log what fields and children we have (only if name extraction failed)
			var debug_named_child_count = TreeSitter.node_get_named_child_count(node);
			GLib.debug("get_element_name failed for %s (line %d): child_count=%u, named_child_count=%u", 
			           node_type ?? "unknown", start_line, child_count, debug_named_child_count);
			
			// Log first few child types for debugging
			for (uint i = 0; i < child_count && i < 5; i++) {
				var child = TreeSitter.node_get_child(node, i);
				unowned string? child_type = TreeSitter.node_get_type(child);
				var is_named = TreeSitter.node_is_named(child);
				GLib.debug("  child[%u]: type=%s, named=%s", i, child_type ?? "null", is_named ? "yes" : "no");
			}
			for (uint i = 0; i < child_count; i++) {
				var child = TreeSitter.node_get_child(node, i);
				if (!TreeSitter.node_is_named(child)) {
					continue;
				}
				
				unowned string? child_type = TreeSitter.node_get_type(child);
				if (child_type == null) {
					continue;
				}
				
				var type_lower = child_type.down();
				
				// Check for identifier nodes (common across languages)
				// Also check for Vala-specific types: symbol, unqualified_type
				if (type_lower == "identifier" || 
				    type_lower == "type_identifier" ||
				    type_lower == "property_identifier" ||
				    type_lower == "method_identifier" ||
				    type_lower == "symbol" ||  // Vala uses "symbol" for names
				    type_lower == "unqualified_type" ||  // Vala uses this for type names
				    type_lower.contains("name") ||
				    type_lower.contains("identifier")) {
					var start_byte = TreeSitter.node_get_start_byte(child);
					var end_byte = TreeSitter.node_get_end_byte(child);
					if (end_byte > start_byte) {
						var name = code_content.substring((int)start_byte, (int)(end_byte - start_byte));
						if (name != null && name != "") {
							return name;
						}
					}
				}
			}
			
			// Strategy 3: Look in named children only (deeper search)
			var named_child_count = TreeSitter.node_get_named_child_count(node);
			for (uint i = 0; i < named_child_count; i++) {
				var child = TreeSitter.node_get_named_child(node, i);
				unowned string? child_type = TreeSitter.node_get_type(child);
				if (child_type == null) {
					continue;
				}
				
				var type_lower = child_type.down();
				// Check for identifier nodes and Vala-specific types
				if (type_lower == "identifier" || 
				    type_lower == "type_identifier" ||
				    type_lower == "symbol" ||  // Vala uses "symbol" for names
				    type_lower == "unqualified_type" ||  // Vala uses this for type names
				    type_lower.contains("name")) {
					var start_byte = TreeSitter.node_get_start_byte(child);
					var end_byte = TreeSitter.node_get_end_byte(child);
					if (end_byte > start_byte) {
						var name = code_content.substring((int)start_byte, (int)(end_byte - start_byte));
						if (name != null && name != "") {
							return name;
						}
					}
				}
			}
			
			return null;
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

