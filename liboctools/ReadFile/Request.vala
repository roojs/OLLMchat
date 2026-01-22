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
	 * Request handler for reading file contents with optional line range support.
	 */
	public class Request : OLLMchat.Tool.RequestBase
	{
		// Parameter properties
		public string file_path { get; set; default = ""; }
		public int64 start_line { get; set; default = -1; }
		public int64 end_line { get; set; default = -1; }
		public string ast_path { get; set; default = ""; }
		public bool read_entire_file { get; set; default = false; }
		public bool show_lines { get; set; default = false; }
		public string find_words { get; set; default = ""; }
		public bool summarize { get; set; default = false; }
		
		// Internal: normalized file path (set once at start of interaction)
		private string normalized_path = "";
		
		// Internal: File object (set once at start of execute_request)
		private OLLMfiles.File? file = null;
		
		/**
		 * Default constructor.
		 */
		public Request()
		{
		}
		
		/**
		 * Override normalize_file_path to prepend project path for relative paths.
		 * 
		 * When the agent sends the workspace path to the LLM, the LLM may request
		 * files with relative paths. This override prepends the active project path
		 * from the tool's project_manager if the path is still relative after
		 * permission provider normalization.
		 */
		protected override string normalize_file_path(string in_path)
		{
			var path = base.normalize_file_path(in_path);
			
			// If path is already absolute, return it as-is
			if (GLib.Path.is_absolute(path)) {
				return path;
			}
			
			// If path is still relative, try to prepend project path
			var project_manager = ((Tool) this.tool).project_manager;
			if (project_manager != null && project_manager.active_project != null) {
				path = GLib.Path.build_filename(project_manager.active_project.path, path);
			}
			
			return path;
		}
		
		/**
		 * Get first N lines from content string.
		 * 
		 * @param content The full content string
		 * @param max_lines Maximum number of lines to return
		 * @return First N lines of content
		 */
		private string get_first_lines(string content, int max_lines)
		{
			if (content == null || content == "") {
				return "";
			}
			
			var lines = content.split("\n");
			if (lines.length <= max_lines) {
				return content;
			}
			
			return string.joinv("\n", lines[0:max_lines]);
		}
		
		/**
		 * Format content with line numbers.
		 * 
		 * @param content The content string
		 * @param start_line_number The starting line number (1-based)
		 * @return Content with line numbers prefixed
		 */
		private string format_with_line_numbers(string content, int start_line_number)
		{
			if (content == null || content == "") {
				return "";
			}
			
			var lines = content.split("\n");
			var result = new string[lines.length];
			
			for (int i = 0; i < lines.length; i++) {
				var line_num = start_line_number + i;
				result[i] = "%d: %s".printf(line_num, lines[i]);
			}
			
			return string.joinv("\n", result);
		}
		
		/**
		 * Resolve AST path to line range.
		 * 
		 * Only resolves AST paths for files in the active project.
		 * Uses this.file (must be set before calling).
		 * 
		 * @return true if AST path was resolved successfully, false otherwise
		 */
		private async bool resolve_ast_path() throws GLib.Error
		{
			if (this.ast_path == "" || this.file == null) {
				return false;
			}
			
			var project_manager = ((Tool) this.tool).project_manager;
			
			// Get Tree instance and parse
			var tree = project_manager.tree_factory(this.file);
			yield tree.parse();
			
			// Lookup AST path
			int start, end;
			if (tree.lookup_path(this.ast_path, out start, out end)) {
				this.start_line = start;
				this.end_line = end;
				return true;
			}
			
			return false;
		}
		
		/**
		 * Find lines containing search words and return with line numbers.
		 * 
		 * @param content The full content string
		 * @param search_words The words to search for
		 * @param start_line_number The starting line number (1-based) for the content
		 * @return Matching lines with line numbers, or empty string if no matches
		 */
		private string find_matching_lines(string content, string search_words, int start_line_number)
		{
			if (content == null || content == "" || search_words == null || search_words.strip() == "") {
				return "";
			}
			
			var lines = content.split("\n");
			var matching_lines = new Gee.ArrayList<string>();
			var search_lower = search_words.strip().down();
			
			for (int i = 0; i < lines.length; i++) {
				var line_lower = lines[i].down();
				if (line_lower.contains(search_lower)) {
					var line_num = start_line_number + i;
					matching_lines.add("%d: %s".printf(line_num, lines[i]));
				}
			}
			
			if (matching_lines.size == 0) {
				return "";
			}
			
			return string.joinv("\n", matching_lines.to_array());
		}
		
		/**
		 * Build permission question for file read operation.
		 * 
		 * @return true if permission is required (file is outside project or project_manager is null),
		 *         false if permission is not required (file is in project or invalid parameters)
		 */
		protected override bool build_perm_question()
		{
			// Validate required parameter
			if (this.file_path == "") {
				return false; // Invalid - no permission needed
			}
			
			// If project_manager is null, return false - no permission needed, execute_request() will fail with error
			var project_manager = ((Tool) this.tool).project_manager;
			if (project_manager == null) {
				this.permission_question = "";
				return false; // No permission needed - execute_request() will fail with proper error
			}
			
			// Normalize file path once at the start
			this.normalized_path = this.normalize_file_path(this.file_path);
			
			// Debug: Log input path
			GLib.debug("ReadFile.build_perm_question: Input file_path='%s'", this.file_path);
			
			// Debug: Log normalized path
			GLib.debug("ReadFile.build_perm_question: Normalized patnh='%s' (was '%s')",
				this.normalized_path,
				this.file_path);
			
			if (this.normalized_path == null || this.normalized_path == "") {
				return false; // Invalid - no permission needed
			}
			
			// If path is under the project, don't ask for permission
			if (project_manager.active_project != null) {
				var project_path = project_manager.active_project.path;
				if ((this.normalized_path == project_path) || this.normalized_path.has_prefix(project_path + "/")) {
					this.permission_question = "";
					return false; // File in project - no permission needed
				}
			}
			
			// Set up permission properties for non-project files
			this.permission_target_path = this.normalized_path;
			this.permission_operation = OLLMchat.ChatPermission.Operation.READ;
			// Return true - permission required for files outside project
			
			// Build permission question based on parameters
			string question;
			if (this.summarize) {
				question = "Summarize file '" + this.normalized_path + "'?";
			} else if (this.read_entire_file) {
				question = "Read entire file '" + this.normalized_path + "'?";
			} else if (this.ast_path != "") {
				// Show AST path in permission question (line numbers resolved later in execute_request)
				question = "Read file '" + this.normalized_path + "' (ast-path: " + this.ast_path + ")?";
			} else if (this.start_line > 0 && this.end_line > 0) {
				question = "Read file '" + this.normalized_path + "' (lines " + this.start_line.to_string() + "-" + this.end_line.to_string() + ")?";
			} else {
				question = "Read file '" + this.normalized_path + "'?";
			}
			this.permission_question = question;
			
			// File is not under project - require permission
			return true;
		}
		
		protected override async string execute_request() throws Error
		{
			// Use normalized_path from build_perm_question() (called first)
			
			// Get ProjectManager
			var project_manager = ((Tool) this.tool).project_manager;
			if (project_manager == null) {
				throw new GLib.IOError.FAILED("ProjectManager is not available");
			}
			
			// Try to get File from active project (needed for AST path resolution)
			this.file = project_manager.get_file_from_active_project(this.normalized_path);
			
			// Resolve AST path if provided (only works for project files)
			if (this.ast_path != "") {
				if (this.file == null) {
					var error_msg = "AST path resolution requires file to be in active project: " + this.ast_path;
					this.send_ui("txt", "Read file Response", "Error: " + error_msg);
					throw new GLib.IOError.NOT_FOUND(error_msg);
				}
				if (!yield this.resolve_ast_path()) {
					var error_msg = "AST path not found: " + this.ast_path;
					this.send_ui("txt", "Read file Response", "Error: " + error_msg);
					throw new GLib.IOError.NOT_FOUND(error_msg);
				}
			}
			
			// Create fake file if needed (only after AST path check, since AST doesn't work on fake files)
			if (this.file == null) {
				this.file = new OLLMfiles.File.new_fake(project_manager, this.normalized_path);
			}
			
			// Build standardized file read request message and send to UI (before any validation)
			// Use original file_path if normalized is empty, otherwise use normalized
			var display_path = (this.normalized_path != null && this.normalized_path != "") ? this.normalized_path : this.file_path;
			var request_message = "File: " + display_path + "\n";
			
			// Add AST path if specified
			if (this.ast_path != "") {
				request_message += "AST path: " + this.ast_path + "\n";
			}
			
			// Add lines if specified
			if (!this.read_entire_file && this.start_line > 0 && this.end_line > 0) {
				request_message += "Lines: %lld-%lld\n".printf(this.start_line, this.end_line);
			}
			
			// Add full file status
			request_message += this.read_entire_file ? "Full file: yes\n" : "Full file: no\n";
			
			// Add show_lines option
			if (this.show_lines) {
				request_message += "With line numbers: yes\n";
			}
			
			// Add find_words option
			if (this.find_words != null && this.find_words.strip() != "") {
				request_message += "Find words: " + this.find_words + "\n";
			}
			
			// Add summarize option
			if (this.summarize) {
				request_message += "Summarize: yes\n";
			}
			
			// Send request message to UI in standardized codeblock format
			this.send_ui("txt", "File Read Requested", request_message);
			
			// Validate that file_path was provided
			if (this.normalized_path == null || this.normalized_path == "") {
				string error_msg;
				if (this.file_path == null || this.file_path == "") {
					error_msg = "File path parameter is required but was not provided or is empty";
				} else {
					error_msg = "File path parameter is empty after normalization";
				}
				this.send_ui("txt", "Read file Response", "Error: " + error_msg);
				throw new GLib.IOError.INVALID_ARGUMENT(error_msg);
			}
			
			// Validate that file exists
			if (!GLib.FileUtils.test(this.normalized_path, GLib.FileTest.IS_REGULAR)) {
				var error_msg = "File not found or is not a regular file: " + this.normalized_path;
				this.send_ui("txt", "Read file Response", "Error: " + error_msg);
				throw new GLib.IOError.FAILED(error_msg);
			}
			
			// Validate line range if not reading entire file and not using find_words or summarize
			// (find_words and summarize can work without explicit line range)
			if (!this.read_entire_file && !this.summarize && (this.find_words == null || this.find_words.strip() == "")) {
				if (this.start_line < 1) {
					var error_msg = "Invalid line range: start_line must be >= 1";
					this.send_ui("txt", "Read file Response", "Error: " + error_msg);
					throw new GLib.IOError.INVALID_ARGUMENT(error_msg);
				}
				
				// Validate line range if provided
				if (this.start_line > 0 && this.end_line > 0 && this.start_line > this.end_line) {
					var error_msg = "Invalid line range: start_line (" + this.start_line.to_string() + 
						") must be <= end_line (" + this.end_line.to_string() + ")";
					this.send_ui("txt", "Read file Response", "Error: " + error_msg);
					throw new GLib.IOError.INVALID_ARGUMENT(error_msg);
				}
			}
			
			
			// Handle summarize option
			if (this.summarize) {
				// Create Summarize instance (pass show_lines to control output format)
				var summarizer = new Summarize(this.file, this.show_lines);
				
				// Generate summary
				var summary = yield summarizer.summarize();
				
				// Send summary to UI
				var preview_summary = this.get_first_lines(summary, 20);
				this.send_ui("txt", "File Summary", preview_summary);
				
				// Return full summary to LLM
				return summary;
			}
			
			// Ensure buffer exists (create if needed)
			this.file.manager.buffer_provider.create_buffer(this.file);
			
			// Ensure buffer is loaded
			if (!this.file.buffer.is_loaded) {
				yield this.file.buffer.read_async();
			}

			// Get full content (default to entire file)
			var  full_content = this.file.buffer.get_text();
			var content_start_line = 1; // Track starting line number for line number formatting
			
			// Read line range if specified and not reading entire file
			if (!this.read_entire_file && (this.start_line > 0 || this.end_line > 0)) {
				// Read line range using buffer.get_text() (convert 1-based to 0-based)
				// Original: 1-based, inclusive start, exclusive end
				// Buffer: 0-based, inclusive start and end
				// Conversion: start_line_0 = start_line - 1, end_line_0 = end_line - 2
				full_content = this.file.buffer.get_text(
					(int)(this.start_line - 1),
					(int)(this.end_line - 2)
				);
				content_start_line = (int)this.start_line;
			}  
			
			// Handle find_words option - search for matching lines
			if (this.find_words != null && this.find_words.strip() != "") {
				var matching_lines = this.find_matching_lines(full_content, this.find_words, content_start_line);
				
				if (matching_lines == "") {
					this.send_ui("txt", "Read file Reply", "Result: No lines found");
					return "No lines found containing: " + this.find_words;
				}
				
				// Send matching lines to UI
				var preview_matching = this.get_first_lines(matching_lines, 20);
				this.send_ui("txt", "Read file Reply", preview_matching);
				
				return matching_lines;
			}
			
			// Handle show_lines option - format with line numbers
			if (this.show_lines) {
				full_content = this.format_with_line_numbers(full_content, content_start_line);
			}
			
			// Send first 10 lines to UI
			var preview_content = this.get_first_lines(full_content, 10);
			var file_basename = GLib.Path.get_basename(this.file.path);
			
			// Build line range suffix if specified
			string line_range_suffix = "";
			if (this.ast_path != "") {
				line_range_suffix = " (ast-path: " + this.ast_path;
				if (this.start_line > 0 && this.end_line > 0) {
					line_range_suffix += ", lines %lld-%lld".printf(this.start_line, this.end_line);
				}
				line_range_suffix += ")";
			} else if (!this.read_entire_file && this.start_line > 0 && this.end_line > 0) {
				line_range_suffix = " (lines %lld-%lld)".printf(this.start_line, this.end_line);
			}
			
			this.send_ui("txt", "Reading file: " + file_basename + line_range_suffix, preview_content);
			
			// Return full content to LLM
			return full_content;
		}
	}
}

