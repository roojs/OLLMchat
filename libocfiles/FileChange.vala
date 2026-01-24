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
	 * Operation type for file changes.
	 */
	public enum OperationType {
		REPLACE,  // Replace the range
		BEFORE,   // Insert before the range
		AFTER,    // Insert after the range
		DELETE    // Delete the range
	}
	
	/**
	 * Represents a single edit operation with range and replacement.
	 * 
	 * Line numbers are 1-based (inclusive start, exclusive end).
	 */
	public class FileChange : Object
	{
		/**
		 * The file this change applies to.
		 * 
		 * FIXME: Make file non-nullable later in the process.
		 * We leave it nullable for now so it builds at present.
		 */
		public File? file { get; construct; }
		
		/**
		 * Starting line number (1-based, inclusive).
		 */
		public int start { get; set; default = -1; }
		
		/**
		 * Ending line number (1-based, exclusive).
		 */
		public int end { get; set; default = -1; }
		
		/**
		 * Replacement text to insert at the specified range.
		 */
		public string replacement { get; set; default = ""; }
		
		/**
		 * AST path for this change (empty string when using line numbers).
		 */
		public string ast_path { get; set; default = ""; }
		
		/**
		 * Whether to include preceding comments when resolving AST path.
		 */
		public bool include_comments { get; set; default = false; }
		
		/**
		 * Indicates whether AST path resolution and application result
		 * have been determined for this change.
		 */
		public bool completed { get; private set; default = false; }

		/**
		 * Indicates whether this change represents a parse/format error.
		 */
		public bool has_error { get; private set; default = false; }
		
		/**
		 * Operation type for this change.
		 */
		public OperationType operation_type { get; set; default = OperationType.REPLACE; }
		
		/**
		 * Result message for this change.
		 * 
		 * ""          = not yet determined
		 * "applied"   = applied successfully
		 * other text  = error message (format errors, AST errors, etc.)
		 */
		public string result { get; set; default = ""; }
		
		/**
		 * Constructor.
		 * 
		 * @param file The file this change applies to (nullable)
		 */
		public FileChange(File? file = null)
		{
			Object(file: file);
		}
		
		/**
		 * Secondary constructor for creating a FileChange with an error state.
		 * 
		 * @param file The file this change applies to (nullable)
		 * @param error_message The error message to store in result
		 */
		public FileChange.with_error(File? file, string error_message)
		{
			Object(file: file);
			this.result = error_message;
			this.completed = true;
			this.has_error = true;
		}
		
		/**
		 * Normalize indentation of replacement text based on base indentation.
		 * 
		 * Removes minimum leading whitespace from all lines, then prepends base_indent.
		 * 
		 * @param base_indent The base indentation string to prepend to each line
		 */
		public void normalize_indentation(string base_indent)
		{
			if (this.replacement.length == 0) {
				return;
			}
			
			var lines = this.replacement.split("\n");
			
			// Find minimum leading whitespace
			int min_indent = int.MAX;
			foreach (var line in lines) {
				if (line.strip().length == 0) {
					continue;
				}
				// Use chug to find prefix length
				var prefix_length = line.length - line.chug().length;
				if (prefix_length < min_indent) {
					min_indent = prefix_length;
				}
			}
			
			string[] ret = {};
			
			foreach (var line in lines) {
				ret += base_indent + (
					(min_indent == int.MAX || line.strip().length == 0) ? "" :
						line.substring(min_indent));
			}
			
			this.replacement = string.joinv("\n", ret);
		}
		
		/**
		 * Returns a human-readable description of this change.
		 * 
		 * Uses AST path when available, otherwise falls back to line range.
		 */
		public string get_description()
		{
			if (this.ast_path != "") {
				return "ast-path:" + this.ast_path;
			}
		
			if (this.has_error) {
				return "code block";
			}
				
			return "lines " + this.start.to_string() + "-" + this.end.to_string();
		}
		
		/**
		 * Resolve AST path to line range.
		 * 
		 * Only resolves AST paths for files in the active project.
		 * Uses this.file.manager to get ProjectManager and resolve the AST path.
		 * 
		 * On success: Sets this.start and this.end, adjusts based on operation_type,
		 * sets this.result = "applied", and marks this.completed = true.
		 * 
		 * On failure: Sets this.result to an error message, sets has_error = true,
		 * and marks this.completed = true.
		 */
		public async void resolve_ast_path()
		{
			if (this.ast_path == "") {
				return;
			}
			
			if (this.file == null) {
				this.result = "No file available for AST path resolution";
				this.completed = true;
				this.has_error = true;
				return;
			}
			
			var project_manager = this.file.manager;
			
			if (this.file.id <= 0) {
				this.result = "AST path resolution requires file to be in active project";
				this.completed = true;
				this.has_error = true;
				return;
			}
			
			var tree = project_manager.tree_factory(this.file);
			
			int start, end, comment_start;
			try {
				yield tree.parse();
				if (!tree.lookup_path(this.ast_path, out start, out end, out comment_start)) {
					this.result = "AST path not found: " + this.ast_path;
					this.completed = true;
					this.has_error = true;
					return;
				}
			} catch (GLib.Error e) {
				GLib.warning("Error resolving AST path '%s': %s", this.ast_path, e.message);
				this.result = "Error resolving AST path: " + e.message;
				this.completed = true;
				this.has_error = true;
				return;
			}
			
			this.start = this.include_comments ? comment_start : start;
			this.end = end;
			
			switch (this.operation_type) {
				case OperationType.BEFORE:
					this.end = this.start;
					break;
				case OperationType.AFTER:
					this.start = this.end;
					break;
				case OperationType.DELETE:
					if (this.replacement.strip() != "") {
						this.replacement = "";
					}
					break;
				case OperationType.REPLACE:
					break;
			}
			this.completed = true;
		}
		
		/**
		 * Apply this change to the file buffer.
		 * 
		 * This method handles buffer creation, loading, and applying the edit.
		 * Does NOT throw errors - sets result and completed on success or failure.
		 * 
		 * @param write_complete_file Whether to write the complete file (replacement content)
		 */
		public async void apply_change(bool write_complete_file)
		{
			// File is already set as a property of FileChange
			// Project manager is available via file.manager
			this.file.manager.buffer_provider.create_buffer(this.file);
			
			// Ensure buffer is loaded
			if (!this.file.buffer.is_loaded) {
				try {
					yield this.file.buffer.read_async();
				} catch (GLib.Error e) {
					this.result = "Error loading buffer: " + e.message;
					this.completed = true;
					return;
				}
			}
			// TODO: When modes are added to the tool, in AST mode we should not reload the file
			// - The file is already in memory since we had to run the tree on it to start with
			// - AST path resolution requires the file to be parsed, so buffer should already be loaded
			// - This check can be optimized for AST mode to skip the reload
			
			// Handle complete file write
			if (write_complete_file) {
				try {
					yield this.file.buffer.write(this.replacement);
				} catch (GLib.Error e) {
					this.result = "Error writing file: " + e.message;
					this.completed = true;
					return;
				}
				this.result = "applied";
				this.completed = true;
				return;
			}
			
			// Apply single edit using apply_edit (singular)
			// apply_edit() throws errors - catch and set result/completed
			try {
				yield this.file.buffer.apply_edit(this);
			} catch (GLib.Error e) {
				this.result = "Error applying edit: " + e.message;
				this.completed = true;
				return;
			}
			this.result = "applied";
			this.completed = true;
		}
		
		/**
		 * Add a linebreak to the replacement text.
		 * 
		 * @param is_closing Whether this is a closing linebreak (when closing code block)
		 */
		public void add_linebreak(bool is_closing)
		{
			if (!is_closing) {
				this.replacement += "\n";
				return;
			}
			
			// Remove trailing ``` markers from replacement
			var offset = this.replacement.has_suffix("```\n") ? 4 : (
				this.replacement.has_suffix("```") ? 3 : 0);
			if (offset > 0) {
				this.replacement = this.replacement.substring(
					0,
					this.replacement.length - offset
				);
			}
			
			// Empty replacement means delete
			if (this.replacement.strip() == "") {
				this.operation_type = OperationType.DELETE;
			}
			// Adjust line range for insert/delete based on operation_type.
			if (this.ast_path != "") {
				// AST path: let FileChange.resolve_ast_path() handle ranges
				if (this.file != null) {
					this.resolve_ast_path.begin();
				}
				return;
			}
		}
	}
}

