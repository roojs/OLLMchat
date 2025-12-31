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

namespace OLLMtools
{
	/**
	 * Request handler for reading file contents with optional line range support.
	 */
	public class RequestReadFile : OLLMchat.Tool.RequestBase
	{
		// Parameter properties
		public string file_path { get; set; default = ""; }
		public int64 start_line { get; set; default = -1; }
		public int64 end_line { get; set; default = -1; }
		public bool read_entire_file { get; set; default = false; }
		public bool with_lines { get; set; default = false; }
		public string find_words { get; set; default = ""; }
		
		/**
		 * Default constructor.
		 */
		public RequestReadFile()
		{
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
		
		protected override bool build_perm_question()
		{
			// Validate required parameter
			if (this.file_path == "") {
				return false;
			}
			
			// Normalize file path
			var normalized_path = this.normalize_file_path(this.file_path);
			if (normalized_path == null || normalized_path == "") {
				return false;
			}
			
			// Set up permission properties for non-project files first
			this.permission_target_path = normalized_path;
			this.permission_operation = OLLMchat.ChatPermission.Operation.READ;
			
			// Build permission question based on parameters
			string question;
			if (this.read_entire_file) {
				question = "Read entire file '" + normalized_path + "'?";
			} else if (this.start_line > 0 && this.end_line > 0) {
				question = "Read file '" + normalized_path + "' (lines " + this.start_line.to_string() + "-" + this.end_line.to_string() + ")?";
			} else {
				question = "Read file '" + normalized_path + "'?";
			}
			this.permission_question = question;
			
			// Check if file is in active project (skip permission prompt if so)
			if (((ReadFile) this.tool).project_manager?.get_file_from_active_project(normalized_path) != null) {
				// File is in active project - skip permission prompt
				// Clear permission question to indicate auto-approved
				this.permission_question = "";
				// Return false to skip permission check (auto-approved for project files)
				return false;
			}
			
			// File is not in active project - require permission
			return true;
		}
		
		protected override async string execute_request() throws Error
		{
			// Normalize file path
			var file_path = this.normalize_file_path(this.file_path);
			
			// Build standardized file read request message and send to UI (before any validation)
			// Use original file_path if normalized is empty, otherwise use normalized
			var display_path = (file_path != null && file_path != "") ? file_path : this.file_path;
			var request_message = "File: " + display_path + "\n";
			
			// Add lines if specified
			if (!this.read_entire_file && this.start_line > 0 && this.end_line > 0) {
				request_message += "Lines: %lld-%lld\n".printf(this.start_line, this.end_line);
			}
			
			// Add full file status
			request_message += this.read_entire_file ? "Full file: yes\n" : "Full file: no\n";
			
			// Add with_lines option
			if (this.with_lines) {
				request_message += "With line numbers: yes\n";
			}
			
			// Add find_words option
			if (this.find_words != null && this.find_words.strip() != "") {
				request_message += "Find words: " + this.find_words + "\n";
			}
			
			// Send request message to UI in standardized codeblock format
			this.send_ui("txt", "File Read Requested", request_message);
			
			// Validate that file_path was provided
			if (file_path == null || file_path == "") {
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
			if (!GLib.FileUtils.test(file_path, GLib.FileTest.IS_REGULAR)) {
				var error_msg = "File not found or is not a regular file: " + file_path;
				this.send_ui("txt", "Read file Response", "Error: " + error_msg);
				throw new GLib.IOError.FAILED(error_msg);
			}
			
			// Validate line range if not reading entire file and not using find_words
			// (find_words can work without explicit line range)
			if (!this.read_entire_file && (this.find_words == null || this.find_words.strip() == "")) {
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
			
			// Get or create File object from path
			var project_manager = ((ReadFile) this.tool).project_manager;
			if (project_manager == null) {
				throw new GLib.IOError.FAILED("ProjectManager is not available");
			}
			
			
			// First, try to get from active project
			var file = project_manager.get_file_from_active_project(file_path);
			
			
			if (file == null) {
				file = new OLLMfiles.File.new_fake(project_manager, file_path);
			}
			
			
			// Ensure buffer exists (create if needed)
			file.manager.buffer_provider.create_buffer(file);
			
			// Ensure buffer is loaded
			if (!file.buffer.is_loaded) {
				yield file.buffer.read_async();
			}

			// Get full content (default to entire file)
			var  full_content = file.buffer.get_text();
			var content_start_line = 1; // Track starting line number for line number formatting
			
			// Read line range if specified and not reading entire file
			if (!this.read_entire_file && (this.start_line > 0 || this.end_line > 0)) {
				// Read line range using buffer.get_text() (convert 1-based to 0-based)
				// Original: 1-based, inclusive start, exclusive end
				// Buffer: 0-based, inclusive start and end
				// Conversion: start_line_0 = start_line - 1, end_line_0 = end_line - 2
				full_content = file.buffer.get_text(
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
			
			// Handle with_lines option - format with line numbers
			if (this.with_lines) {
				full_content = this.format_with_line_numbers(full_content, content_start_line);
			}
			
			// Send first 10 lines to UI
			var preview_content = this.get_first_lines(full_content, 10);
			var file_basename = GLib.Path.get_basename(file.path);
			
			// Build line range suffix if specified
			string line_range_suffix = "";
			if (!this.read_entire_file && this.start_line > 0 && this.end_line > 0) {
				line_range_suffix = " (lines %lld-%lld)".printf(this.start_line, this.end_line);
			}
			
			this.send_ui("txt", "Reading file: " + file_basename + line_range_suffix, preview_content);
			
			// Return full content to LLM
			return full_content;
		}
	}
}

