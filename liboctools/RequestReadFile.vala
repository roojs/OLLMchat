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
		
		/**
		 * Default constructor.
		 */
		public RequestReadFile()
		{
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
			// Normalize and validate file path
			var file_path = this.normalize_file_path(this.file_path);
			
			// Validate that file_path was provided
			if (file_path == null || file_path == "") {
				if (this.file_path == null || this.file_path == "") {
					throw new GLib.IOError.INVALID_ARGUMENT("File path parameter is required but was not provided or is empty");
				} else {
					throw new GLib.IOError.INVALID_ARGUMENT("File path parameter is empty after normalization");
				}
			}
			
			// Emit execution message with human-friendly tool name and file path
			var message = "Executing %s on file: %s".printf(
					this.tool.description.strip().split("\n")[0],
					file_path
				);
			if (this.read_entire_file) {
				message = "Executing %s on file: %s".printf(
					this.tool.description.strip().split("\n")[0],
					file_path
				);
			} else if (this.start_line > 0 && this.end_line > 0) {
				message = "Executing %s on file: %s (lines %lld-%lld)".printf(
					this.tool.description.strip().split("\n")[0],
					file_path,
					this.start_line,
					this.end_line
				);
			} 
			this.chat_call.client.message_created(
				new OLLMchat.Message(this.chat_call, "ui", message),
				this.chat_call
			);
			
			if (!GLib.FileUtils.test(file_path, GLib.FileTest.IS_REGULAR)) {
				throw new GLib.IOError.FAILED("File not found or is not a regular file: " + file_path);
			}
			
			// Validate line range if provided
			if (this.start_line > 0 && this.end_line > 0 && this.start_line > this.end_line) {
				throw new GLib.IOError.INVALID_ARGUMENT(
					"Invalid line range: start_line (" + this.start_line.to_string() + 
					") must be <= end_line (" + this.end_line.to_string() + ")"
				);
			}
			
			if (this.start_line > 0 && this.end_line > 0 && this.start_line < 1) {
				throw new GLib.IOError.INVALID_ARGUMENT("Invalid line range: start_line must be >= 1");
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
			var ret = "";
			if (!file.buffer.is_loaded) {
				ret = yield file.buffer.read_async();
			}

			// Read entire file if requested or no line range specified
			if (this.read_entire_file || (this.start_line <= 0 && this.end_line <= 0)) {
				// Use buffer.read_async() for entire file
				return ret;
			}
			
			
			// Read line range using buffer.get_text() (convert 1-based to 0-based)
			// Original: 1-based, inclusive start, exclusive end
			// Buffer: 0-based, inclusive start and end
			// Conversion: start_line_0 = start_line - 1, end_line_0 = end_line - 2
			return file.buffer.get_text(
				(int)(this.start_line - 1),
				(int)(this.end_line - 2)
			);
		}
	}
}

