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

namespace OLLMfiles
{
	/**
	 * Tree-sitter AST path lookup class.
	 * 
	 * Provides fast lookup of AST paths to line numbers by parsing the file
	 * and building hash maps of path -> line number mappings.
	 */
	public class Tree : TreeBase
	{
		/**
		 * Hash map of AST path to start line number.
		 */
		private Gee.HashMap<string, int> ast_start = new Gee.HashMap<string, int>();
		
		/**
		 * Hash map of AST path to end line number.
		 */
		private Gee.HashMap<string, int> ast_end = new Gee.HashMap<string, int>();
		
		/**
		 * Timestamp of when the file was last parsed (Unix timestamp).
		 * Used to determine if re-parsing is needed.
		 */
		public int64 last_parsed { get; private set; default = 0; }
		
		/**
		 * Flag indicating that the tree needs to be reparsed even if mtime hasn't changed.
		 * This is set when AST path-based edits are applied, so subsequent AST path lookups
		 * use updated line numbers.
		 */
		public bool needs_reparse { get; set; default = false; }
		
		/**
		 * Constructor.
		 * 
		 * @param file The OLLMfiles.File to parse
		 */
		public Tree(File file)
		{
			base(file);
		}
		
		/**
		 * Parse file and build AST path maps.
		 * 
		 * Compares file modification time with last_parsed. If they match, this is a NOOP.
		 * Otherwise, clears the hashmaps and rebuilds them by traversing the AST.
		 * 
		 * @throws Error if parsing fails
		 */
		public async void parse() throws GLib.Error
		{
			// Get current file modification time
			var file_mtime = this.file.mtime_on_disk();
			
			// If file hasn't changed since last parse and no reparse flag is set, skip parsing
			if (file_mtime > 0 && file_mtime == this.last_parsed && !this.needs_reparse) {
				GLib.debug("Tree.parse: File unchanged (mtime=%lld), skipping parse", file_mtime);
				return;
			}
			
			// Clear reparse flag if it was set
			if (this.needs_reparse) {
				this.needs_reparse = false;
			}
			
			// Clear existing maps
			this.ast_start.clear();
			this.ast_end.clear();
			
			// Check if this is a non-code file that we should skip
			if (this.is_unsupported_language(this.file.language ?? "")) {
				GLib.debug("Tree.parse: Skipping non-code file: %s (language: %s)", 
					this.file.path, this.file.language ?? "empty");
				this.last_parsed = file_mtime;
				return;
			}
			
			// Load file content using base class method
			var code_content = yield this.load_file_content();
			
			// Initialize parser using base class method
			yield this.init_parser();
			if (this.language == null) {
				GLib.warning("Tree.parse: Failed to load tree-sitter language for: %s (language: %s)", 
					this.file.path, this.file.language);
				this.last_parsed = file_mtime;
				return;
			}
			
			// Parse source code using tree-sitter
			var tree = this.parse_content(code_content);
			if (tree == null) {
				throw new GLib.IOError.FAILED("Failed to parse file: " + this.file.path);
			}
			
			// Traverse AST and build path maps
			var root_node = tree.get_root_node();
			this.traverse_ast_build_maps(root_node, code_content, null, null, null);
			
			// Update last_parsed timestamp
			this.last_parsed = file_mtime;
			
			GLib.debug("Tree.parse: Built %d AST path mappings for %s", 
				this.ast_start.size, this.file.path);
		}
		
		/**
		 * Recursively traverse AST and build path -> line number maps.
		 * 
		 * Similar to OLLMvector.Indexing.Tree.traverse_ast() but only builds
		 * the path maps without creating VectorMetadata objects.
		 * 
		 * @param node Current AST node
		 * @param code_content Source code content for text extraction
		 * @param parent_enum_name Parent enum name (for enum_value nodes)
		 * @param current_namespace Current namespace string
		 * @param parent_class_name Parent class/struct/interface name
		 */
		private void traverse_ast_build_maps(
			TreeSitter.Node node, 
			string code_content,
			string? parent_enum_name = null, 
			string? current_namespace = null, 
			string? parent_class_name = null)
		{
			if (TreeSitter.node_is_null(node)) {
				return;
			}
			
			unowned string? node_type = TreeSitter.node_get_type(node);
			var node_type_lower = (node_type ?? "").down();
			
			// Track parent enum name for enum_value nodes
			var current_parent_enum = this.update_parent_enum_from_node(node_type_lower, node, code_content, parent_enum_name);
			
			// Track namespace for all elements
			var updated_namespace = this.update_namespace_from_node(node_type_lower, node, code_content, current_namespace);
			
			// Track parent class/struct/interface hierarchy for methods, properties, fields, etc.
			var updated_parent_class = this.update_parent_class_from_node(node_type_lower, node, code_content, parent_class_name);
			
			// Only process named nodes (skip anonymous nodes)
			if (TreeSitter.node_is_named(node) && this.language != null) {
				// Get element type to determine if this is a code element we care about
				var element_type = this.get_element_type(node, this.language);
				
				// Process if it's a recognized element type and not a namespace
				if (element_type != "" && element_type != "namespace") {
					// Build AST path for this element
					var ast_path = this.ast_path(node, code_content);
					if (ast_path != null && ast_path != "") {
						// Get line numbers
						var start_line = (int)TreeSitter.node_get_start_point(node).row + 1;
						var end_line = (int)TreeSitter.node_get_end_point(node).row + 1;
						
						// Store in maps (overwrite if duplicate path exists)
						this.ast_start.set(ast_path, start_line);
						this.ast_end.set(ast_path, end_line);
					}
				}
			}
			
			// Recursively traverse children, passing down the parent enum name, namespace, and parent class
			uint child_count = TreeSitter.node_get_child_count(node);
			for (uint i = 0; i < child_count; i++) {
				var child = TreeSitter.node_get_child(node, i);
				this.traverse_ast_build_maps(child, code_content, current_parent_enum, updated_namespace, updated_parent_class);
			}
		}
		
		/**
		 * Lookup AST path and return line range.
		 * 
		 * First tries exact match. If not found, iterates through all paths
		 * and returns the first match using suffix string matching.
		 * 
		 * @param ast_path AST path to lookup (e.g., "Namespace-Class-Method")
		 * @param start_line Output parameter for starting line number (1-indexed, -1 if not found)
		 * @param end_line Output parameter for ending line number (1-indexed, -1 if not found)
		 * @return true if found, false if not found
		 */
		public bool lookup_path(string ast_path, out int start_line, out int end_line)
		{
			// Try exact match first
			if (this.ast_start.has_key(ast_path)) {
				start_line = this.ast_start.get(ast_path);
				end_line = this.ast_end.get(ast_path);
				return true;
			}
			
			// Try suffix matching - find first path that ends with the search path
			foreach (var path in this.ast_start.keys) {
				if (path.has_suffix(ast_path)) {
					start_line = this.ast_start.get(path);
					end_line = this.ast_end.get(path);
					return true;
				}
			}
			
			// Not found - set to -1 to indicate failure
			start_line = -1;
			end_line = -1;
			return false;
		}
	}
}
