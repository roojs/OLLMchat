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

namespace OLLMfiles
{
	/**
	 * Base class for tree-sitter AST parsing.
	 * 
	 * Provides common functionality for parsing source code files using tree-sitter,
	 * including language loading, element name/type extraction, and file content management.
	 */
	public abstract class TreeBase : Object
	{
		/**
		 * The file being parsed.
		 */
		public File file { get; protected set; }
		
		/**
		 * File content split into lines (0-indexed array).
		 */
		public string[] lines { get; protected set; }
		
		protected TreeSitter.Parser parser = new TreeSitter.Parser();
		protected TreeSitter.Language? language;
		protected unowned GLib.Module? loaded_module;  // Keep module loaded to prevent language object from becoming invalid
		
		[CCode (has_target = false)]
		private delegate unowned TreeSitter.Language TreeSitterLanguageFunc();
		
		/**
		 * Constructor.
		 * 
		 * @param file The OLLMfiles.File to parse
		 */
		protected TreeBase(File file)
		{
			this.file = file;
		}
		
		/**
		 * Check if language is supported by tree-sitter (or should be skipped).
		 * 
		 * @param lang_name Language name (normalized to lowercase)
		 * @return true if language should be skipped (not a code file), false if we should try to load it
		 */
		protected bool is_unsupported_language(string lang_name)
		{
			// Handle empty/null language as unsupported
			if (lang_name == null || lang_name == "") {
				return true;
			}
			
			var lang_lower = lang_name.down();
			switch (lang_lower) {
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
		 * Load file content and split into lines.
		 * 
		 * @throws Error if file cannot be read
		 * @return File content as string
		 */
		protected async string load_file_content() throws GLib.Error
		{
			// Load file content lazily (only when needed for parsing)
			// Use buffer.read_async() to read from disk since buffer may not be loaded
			this.file.manager.buffer_provider.create_buffer(this.file);
			var code_content = yield this.file.buffer.read_async();
			if (code_content == null || code_content == "") {
				throw new GLib.IOError.NOT_FOUND("File is empty or cannot be read: " + this.file.path);
			}
			
			// Split into lines
			this.lines = code_content.split("\n");
			
			return code_content;
		}
		
		/**
		 * Initialize tree-sitter parser with language for the file.
		 * 
		 * @throws Error if language cannot be loaded or set
		 */
		protected async void init_parser() throws GLib.Error
		{
			// Check if this is a non-code file that we should skip
			if (this.is_unsupported_language(this.file.language ?? "")) {
				return;
			}
			
			// Load tree-sitter language dynamically using GModule
			this.language = this.load_tree_sitter_language();
			if (this.language == null) {
				return;
			}
			
			// Set language on parser
			if (!this.parser.set_language(this.language)) {
				throw new GLib.IOError.FAILED("Failed to set tree-sitter language for file: " + this.file.path);
			}
		}
		
		/**
		 * Parse file content using tree-sitter.
		 * 
		 * @param code_content Source code content to parse
		 * @return Tree-sitter Tree object, or null if parsing fails
		 */
		protected TreeSitter.Tree? parse_content(string code_content)
		{
			if (this.language == null) {
				return null;
			}
			
			// Parse source code using tree-sitter
			return this.parser.parse_string(null, code_content, (uint32)code_content.length);
		}
		
		/**
		 * Load tree-sitter language dynamically from shared library using GModule.
		 * 
		 * @return TreeSitter.Language object, or null if loading fails
		 */
		protected TreeSitter.Language? load_tree_sitter_language()
		{
			// Get language from file
			var file_lang = this.file.language;
			if (file_lang == null || file_lang == "") {
				// GLib.debug("TreeBase.load_tree_sitter_language: No language detected for file: %s", this.file.path);
				return null;
			}
			
			// GLib.debug("TreeBase.load_tree_sitter_language: Detected language '%s' for file: %s", file_lang, this.file.path);
			
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
			
			// Build library names: try multiple naming conventions
			// 1. tree_sitter_parser_{lang}.so (standardized naming - preferred)
			// 2. parser_{lang}.so (legacy naming)
			// 3. parser_tree-sitter-{lang}.so (legacy Debian tree-sitter packages)
			// 4. libtree-sitter-{lang}.so (standard upstream naming)
			var lib_name = "tree_sitter_parser_" + lang_name + ".so";
			var legacy_lib_name = "parser_" + lang_name + ".so";
			var debian_lib_name = "parser_tree-sitter-" + lang_name + ".so";
			var alt_lib_name = "libtree-sitter-" + lang_name + ".so";
			
			// Build function name: tree_sitter_{lang}
			var func_name = "tree_sitter_" + normalized_lang;
			
			// Try all library naming conventions (preferred first)
			// GLib.Module.open() will search system library paths automatically
			string[] lib_names = { lib_name, legacy_lib_name, debian_lib_name, alt_lib_name };
			
			foreach (var current_lib_name in lib_names) {
				// Load the parser library using GModule (searches system library paths)
				var module = GLib.Module.open(current_lib_name, GLib.ModuleFlags.LAZY | GLib.ModuleFlags.LOCAL);
				if (module == null) {
					// GLib.debug("TreeBase.load_tree_sitter_language: Failed to open module %s: %s", current_lib_name, GLib.Module.error());
					continue;
				}
				// GLib.debug("TreeBase.load_tree_sitter_language: Opened library: %s", current_lib_name);
				
				// Get the function symbol
				void* func_ptr;
				if (!module.symbol(func_name, out func_ptr)) {
					// GLib.debug("Function '%s' not found in %s: %s", func_name, current_lib_name, GLib.Module.error());
					module.close();
					continue;
				}
				// GLib.debug("Found function '%s' in %s", func_name, current_lib_name);
				
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
			
			// GLib.debug("Tree-sitter language library not found for: %s (searched for %s)", 
			// 	this.file.language, lib_name);
			return null;
		}
		
		/**
		 * Build AST path from a TreeSitter node by traversing up the AST tree.
		 * 
		 * Creates a hierarchical path representing the element's location in the AST by
		 * walking up the parent chain to find namespace and class declarations.
		 * Format: namespace-class-method or namespace-outerclass-innerclass-method etc. (using '-' separator).
		 * 
		 * @param node TreeSitter node for the element
		 * @param code_content Source code content for text extraction
		 * @return AST path string (e.g., "OLLMvector.Indexing-OuterClass-InnerClass-methodName")
		 */
		public string ast_path(TreeSitter.Node node, string code_content)
		{
			if (TreeSitter.node_is_null(node)) {
				return "";
			}
			
			// Get element name from the node itself
			var elem_name = this.element_name(node, code_content);
			if (elem_name == null || elem_name == "") {
				return "";
			}
			
			// Traverse up the AST to collect namespace and class hierarchy
			// We traverse from inner to outer, so we'll reverse the arrays at the end
			string[] namespace_parts = {};
			string[] class_parts = {};
			
			var current = TreeSitter.node_get_parent(node);
			while (!TreeSitter.node_is_null(current)) {
				unowned string? node_type = TreeSitter.node_get_type(current);
				if (node_type == null) {
					current = TreeSitter.node_get_parent(current);
					continue;
				}
				
				var node_type_lower = node_type.down();
				
				// Check for namespace declarations
				if (node_type_lower == "namespace_declaration" || node_type_lower == "namespace") {
					var namespace_name = this.element_name(current, code_content);
					if (namespace_name != null && namespace_name != "") {
						// Prepend to build full namespace path (outer namespaces first)
						string[] new_parts = { namespace_name };
						new_parts += string.joinv(".", namespace_parts);
						namespace_parts = string.joinv(".", new_parts).split(".");
					}
				}
				
				// Check for class/struct/interface declarations
				if (node_type_lower == "class_declaration" || node_type_lower == "class" ||
				    node_type_lower == "struct_declaration" || node_type_lower == "struct" ||
				    node_type_lower == "interface_declaration" || node_type_lower == "interface") {
					var class_name = this.element_name(current, code_content);
					if (class_name != null && class_name != "") {
						// Prepend to build nested class hierarchy (outer classes first)
						string[] new_parts = { class_name };
						new_parts += string.joinv("-", class_parts);
						class_parts = string.joinv("-", new_parts).split("-");
					}
				}
				
				current = TreeSitter.node_get_parent(current);
			}
			
			// Build the final path
			string[] ast_path_parts = {};
			
			// Add namespace (join with '.' for namespace parts)
			if (namespace_parts.length > 0) {
				ast_path_parts += string.joinv(".", namespace_parts);
			}
			
			// Add class hierarchy (join with '-' for class parts)
			if (class_parts.length > 0) {
				ast_path_parts += string.joinv("-", class_parts);
			}
			
			// Add element name
			ast_path_parts += elem_name;
			
			return string.joinv("-", ast_path_parts);
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
		 * Get element name from AST node.
		 * 
		 * Handles various edge cases including markdown headings, block continuations,
		 * and different field names used by tree-sitter grammars.
		 * 
		 * @param node AST node
		 * @param code_content Source code content for text extraction
		 * @return Element name, or null if not found
		 */
		protected string? element_name(TreeSitter.Node node, string code_content)
		{
			unowned string? node_type = TreeSitter.node_get_type(node);
			var node_type_lower = (node_type ?? "").down();
			
			// Special handling for block_continuation that might be part of a heading
			// When headings appear after list items, they're parsed as: block_continuation + '#' + '#' + '#' + text
			// The '#' nodes are siblings, not children, so we need to check the raw line content
			if (node_type_lower == "block_continuation") {
				var start_line = (int)TreeSitter.node_get_start_point(node).row + 1;
				var start_byte = (int)TreeSitter.node_get_start_byte(node);
				
				// Get the full line content by finding newlines around this position
				// Find the start of the line (search backwards for newline)
				var search_start = (start_byte - 500).clamp(0, start_byte);
				var search_range = code_content.substring(search_start, start_byte - search_start);
				var before_pos = search_range.last_index_of("\n");
				var line_start_idx = (before_pos >= 0) ? search_start + before_pos + 1 : search_start;
				
				// Find the end of the line (search forwards for newline)
				var search_end = (start_byte + 500).clamp(start_byte, (int)code_content.length);
				var after_pos = code_content.index_of("\n", start_byte);
				var line_end_idx = (after_pos >= 0 && after_pos <= search_end) ? after_pos : search_end;
				
				if (line_end_idx > line_start_idx) {
					var line_text = code_content.substring(line_start_idx, line_end_idx - line_start_idx);
					// GLib.debug("TreeBase.element_name: block_continuation at line %d, checking line text: '%s'", start_line, line_text);
					
					// Check if line starts with 1-6 '#' characters followed by optional whitespace
					MatchInfo match_info;
					if (/^#{1,6}\s*(.+)$/.match(line_text, 0, out match_info)) {
						var name = match_info.fetch(1).strip();
						if (name != null && name != "") {
							// GLib.debug("TreeBase.element_name: Extracted heading name '%s' from block_continuation at line %d", name, start_line);
							return name;
						}
					}
				}
			}
			
			// Special handling for markdown headings: extract heading text directly
			if (node_type_lower.has_prefix("heading") || node_type_lower.has_prefix("atx_heading")) {
				// For markdown headings, the text is typically in a "heading_content" field or as direct children
				var heading_content_node = TreeSitter.node_get_child_by_field_name(node, "heading_content", 14);
				if (!TreeSitter.node_is_null(heading_content_node)) {
					var start_byte = TreeSitter.node_get_start_byte(heading_content_node);
					var end_byte = TreeSitter.node_get_end_byte(heading_content_node);
					if (end_byte > start_byte) {
						var name = code_content.substring((int)start_byte, (int)(end_byte - start_byte)).strip();
						if (name != null && name != "") {
							return name;
						}
					}
				}
				// Fallback: extract text from the node itself (excluding the # markers)
				var start_byte = TreeSitter.node_get_start_byte(node);
				var end_byte = TreeSitter.node_get_end_byte(node);
				if (end_byte > start_byte) {
					var raw_text = code_content.substring((int)start_byte, (int)(end_byte - start_byte));
					// Remove leading # and whitespace
					var name = raw_text.replace("#", "").strip();
					if (name != null && name != "") {
						return name;
					}
				}
			}
			
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
		 * Determine element type from tree-sitter node type.
		 * 
		 * @param node AST node
		 * @param lang Tree-sitter language
		 * @return Element type string (e.g., "class", "method", "function"), or empty string if not a code element
		 */
		protected string get_element_type(TreeSitter.Node node, TreeSitter.Language lang)
		{
			unowned string? node_type = TreeSitter.node_get_type(node);
			if (node_type == null) {
				return "";
			}
			
			var type_lower = node_type.down();
			
			// Debug: log heading-related nodes
			// if (type_lower.has_prefix("heading") || type_lower.has_prefix("atx")) {
			// 	GLib.debug("TreeBase.get_element_type: Checking node_type='%s' (lower='%s')", node_type, type_lower);
			// }
			
			// Special handling for block_continuation that might contain a heading
			// Sometimes headings inside lists are parsed as block_continuation nodes
			// The '#' characters might be siblings, not children, so check the node's text content
			if (type_lower == "block_continuation") {
				var start_line = (int)TreeSitter.node_get_start_point(node).row + 1;
				var start_byte = TreeSitter.node_get_start_byte(node);
				var end_byte = TreeSitter.node_get_end_byte(node);
				
				// Check if the node's text content starts with '#' characters
				if (end_byte > start_byte) {
					// We need code_content to check, but we don't have it here
					// Instead, check if parent has children that are '#' nodes
					// For now, check child count - if 0, the content might be in the node itself
					var child_count = TreeSitter.node_get_child_count(node);
					// GLib.debug("TreeBase.get_element_type: Checking block_continuation at line %d with %u children, bytes %u-%u", 
					// 	start_line, child_count, start_byte, end_byte);
					
					// If no children, the heading text might be in sibling nodes
					// We'll handle this in element_name by checking the raw text
					// For now, if it's at a line that looks like it could be a heading, return a generic heading
					// The actual level will be determined when we extract the name
					if (child_count == 0) {
						// This might be a heading - we'll verify in element_name
						// Return a placeholder that element_name can use
						// GLib.debug("TreeBase.get_element_type: block_continuation at line %d has no children, might be heading", start_line);
						// Don't return here - let it fall through and check in element_name
					}
				}
			}
			
			// Special handling for generic atx_heading: determine level from children
			if (type_lower == "atx_heading") {
				// Look for atx_h1_marker, atx_h2_marker, etc. in children
				var child_count = TreeSitter.node_get_child_count(node);
				for (uint i = 0; i < child_count; i++) {
					var child = TreeSitter.node_get_child(node, i);
					unowned string? child_type = TreeSitter.node_get_type(child);
					if (child_type == null) {
						continue;
					}
					var child_type_lower = child_type.down();
					if (child_type_lower.has_prefix("atx_h") && child_type_lower.has_suffix("_marker")) {
						// Extract number: atx_h1_marker -> 1, atx_h2_marker -> 2, etc.
						var heading_num = int.parse(child_type_lower.replace("atx_h", "").replace("_marker", ""));
						if (heading_num > 0 && heading_num <= 6) {
							// GLib.debug("TreeBase.get_element_type: Detected %s from %s", "heading" + heading_num.to_string(), child_type);
							return "heading" + heading_num.to_string();
						}
					}
				}
				// Fallback: if we can't determine level, return generic heading
				// GLib.debug("TreeBase.get_element_type: Could not determine heading level for atx_heading");
				return "heading";
			}
			
			// Check exact matches first
			if (element_type_map.has_key(type_lower)) {
				// if (element_type_map.get(type_lower).has_prefix("heading")) {
				// 	GLib.debug("TreeBase.get_element_type: Found exact match: '%s' -> '%s'", type_lower, element_type_map.get(type_lower));
				// }
				return element_type_map.get(type_lower);
			}
			
			// Check contains patterns using foreach loop
			foreach (var entry in element_type_map.entries) {
				if (type_lower.contains(entry.key)) {
					// Special case: function should not match if it contains "method"
					if (entry.key == "function" && type_lower.contains("method")) {
						continue;
					}
					// if (entry.value.has_prefix("heading")) {
					// 	GLib.debug("TreeBase.get_element_type: Found contains match: '%s' contains '%s' -> '%s'", 
					// 		type_lower, entry.key, entry.value);
					// }
					return entry.value;
				}
			}
			
			// Not a recognized code element type
			// if (type_lower.has_prefix("heading") || type_lower.has_prefix("atx")) {
			// 	GLib.debug("TreeBase.get_element_type: No match found for '%s'", type_lower);
			// }
			return "";
		}
		
		/**
		 * Static map of node type patterns to element types.
		 * Maps tree-sitter node type patterns to our element type strings.
		 */
		protected static Gee.HashMap<string, string> element_type_map;
		
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
			// For markdown files
			element_type_map.set("heading1", "heading1");
			element_type_map.set("heading2", "heading2");
			element_type_map.set("heading3", "heading3");
			element_type_map.set("heading4", "heading4");
			element_type_map.set("heading5", "heading5");
			element_type_map.set("heading6", "heading6");
			element_type_map.set("atx_heading1", "heading1");
			element_type_map.set("atx_heading2", "heading2");
			element_type_map.set("atx_heading3", "heading3");
			element_type_map.set("atx_heading4", "heading4");
			element_type_map.set("atx_heading5", "heading5");
			element_type_map.set("atx_heading6", "heading6");
		}
	}
}

