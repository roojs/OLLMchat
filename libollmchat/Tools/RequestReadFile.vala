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

namespace OLLMchat.Tools
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
			
			// Build permission question based on parameters
			string question;
			if (this.read_entire_file) {
				question = "Read entire file '" + this.file_path + "'?";
			} else if (this.start_line > 0 && this.end_line > 0) {
				question = "Read file '" + this.file_path + "' (lines " + this.start_line.to_string() + "-" + this.end_line.to_string() + ")?";
			} else {
				question = "Read file '" + this.file_path + "'?";
			}
			
			// Set permission properties
			this.permission_target_path = this.file_path;
			this.permission_operation = OLLMchat.ChatPermission.Operation.READ;
			this.permission_question = question;
			
			return true;
		}
		
		protected override string execute_request() throws Error
		{
			// Normalize and validate file path
			var file_path = this.normalize_file_path(this.file_path);
			
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
			this.chat_call.client.tool_message(
				new OLLMchat.Message(this.chat_call, "ui", message)
			);
			
			if (!GLib.FileUtils.test(file_path, GLib.FileTest.IS_REGULAR)) {
				throw new GLib.IOError.FAILED(@"File not found or is not a regular file: $file_path");
			}
			
			// Validate line range if provided
			if (this.start_line > 0 && this.end_line > 0) {
				if (this.start_line > this.end_line) {
					throw new GLib.IOError.INVALID_ARGUMENT(@"Invalid line range: start_line ($(this.start_line)) must be <= end_line ($(this.end_line))");
				}
				
				if (this.start_line < 1) {
					throw new GLib.IOError.INVALID_ARGUMENT(@"Invalid line range: start_line must be >= 1");
				}
			}
			
			// Read entire file if requested or no line range specified
			if (this.read_entire_file || (this.start_line <= 0 && this.end_line <= 0)) {
				string content;
				GLib.FileUtils.get_contents(file_path, out content);
				return content;
			}
			
			// Read line range (1-based, inclusive start, exclusive end)
			string content = "";
			var file = GLib.File.new_for_path(file_path);
			var file_stream = file.read(null);
			var data_stream = new GLib.DataInputStream(file_stream);
			
			try {
				int current_line = 0;
				string? line;
				size_t length;
				
				while ((line = data_stream.read_line(out length, null)) != null) {
					current_line++;
					
					// Skip lines before start_line
					if (current_line < this.start_line) {
						continue;
					}
					
					// Stop at end_line (exclusive)
					if (current_line >= this.end_line) {
						break;
					}
					
					// Add line to content
					if (content != "") {
						content += "\n";
					}
					content += line;
				}
			} finally {
				try {
					data_stream.close(null);
				} catch (GLib.Error e) {
					// Ignore close errors
				}
			}
			
			return content;
		}
	}
}
