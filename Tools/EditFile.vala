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
	 * Tool for editing files by applying code from the last markdown code block in the conversation.
	 * 
	 * This tool extracts code from the assistant's last markdown code block and applies it to a file.
	 * Supports two-step permission flow: first READ permission to generate diff, then WRITE permission with diff display.
	 */
	public class EditFile : Ollama.Tool
	{
		// Parameter properties
		public string file_path { get; set; default = ""; }
		public int start_line { get; set; default = -1; }
		public int end_line { get; set; default = -1; }
		
		// Internal: single edit properties
		private string? replacement { get; set; default = null; }
		private string normalized_path = "";
		
		// Streaming state tracking
		private string current_line = "";
		private bool in_code_block = false;
		private string current_block = "";
		private bool got_block = false;
		
		public override string name { get { return "edit_file"; } }
		
		public override string description { get {
			return """
Apply code from the last markdown code block you output to a file.

IMPORTANT: Before calling this tool, you MUST first output a markdown code block 
with the code you want to apply. The code block should use triple backticks with 
a language tag, for example:

```python
def hello():
    print("Hello, world!")
```

Then call this tool with the file path and line range. The tool will extract the 
code from your last code block and apply it to the file.

The range is specified as [start, end] where:
- The range is inclusive of the start line and exclusive of the end line
- Line numbers are 1-based
- If the range is [n, n], the edit is an insertion before line n
- If the range is [n, n+1], the edit is a replacement of line n
- If the range is [n, m] where m > n+1, the edit is a replacement of lines n through m-1

When creating a new file, use range [1, 1].

You should always read the file before editing it to ensure you have the latest version.""";
		} }
		
		public override string parameter_description { get {
			return """
@param file_path {string} [required] The path to the file to edit.
@param range {array<integer>} [required] Range of lines to edit, specified as [start, end]. The range is inclusive of the start line and exclusive of the end line. Line numbers are 1-based.""";
		} }
		
		/**
		 * Signal emitted before applying edits to a file.
		 * Notification-only signal - use permission system to block operations.
		 */
		public signal void before_change(string file_path, int start_line, int end_line);
		
		/**
		 * Signal emitted after successfully applying edits to a file.
		 */
		public signal void after_change(string file_path, int start_line, int end_line);
		
		public EditFile(Ollama.Client client)
		{
			base(client);
			
			// Only connect to stream_content if streaming is enabled
			// This tool requires streaming to capture code blocks as they arrive
			if (!this.client.stream) {
				GLib.warning("EditFile tool requires streaming to be enabled (client.stream = true)");
				this.active = false;
				return;
			}
			
			// Connect to stream_start signal to reset state when streaming starts
			this.client.stream_start.connect(() => {
				// Only reset if tool is active
				this.current_line = "";
				this.in_code_block = false;
				this.current_block = "";
				this.got_block = false;
			
			});
			
			// Connect to stream_content signal to capture streaming messages
			this.client.stream_content.connect((new_text, response) => {
				this.process_streaming_content(new_text);
			});
		}
		
		/**
		 * Processes streaming content to track code blocks.
		 * Splits on newlines and processes each part.
		 */
		private void process_streaming_content(string new_text)
		{
			// Only process stream if tool is active
			if (!this.active) {
				return;
			}
			if (!new_text.contains("\n")) {
				// No newline, just add the text
				this.add_text(new_text);
				return;
			}
			
			// Split on newlines
			var parts = new_text.split("\n");
			
			// Process all parts
			for (int i = 0; i < parts.length; i++) {
				this.add_text(parts[i]);
				// Only call add_linebreak if not the last part
				if (i < parts.length - 1) {
					this.add_linebreak();
				}
			}
		}
		
		/**
		 * Adds text to current_line and to current_block if in code block.
		 */
		private void add_text(string text)
		{
			this.current_line += text;
			
			if (this.in_code_block) {
				this.current_block += text;
			}
		}
		
		/**
		 * Processes line break: checks current_line for code block markers,
		 * updates state, and clears current_line.
		 */
		private void add_linebreak()
		{
			// Check if current_line is a code block marker (```)
			if (this.current_line.strip() == "```") {
				// Toggle code block state
				if (!this.in_code_block) {
					this.in_code_block = true;
					this.current_line = "";
					this.current_block = "";
					this.got_block = true;
					//this.current_block = "```\n"; // is this needed?
					return;
				}
					// Exiting code block: remove the marker text we just added to current_block
					// current_block should end with "```\n", remove that
				if (this.current_block.has_suffix("```\n")) {
					this.current_block = this.current_block.substring(0, this.current_block.length - 4);
				} else if (this.current_block.has_suffix("```")) {
					this.current_block = this.current_block.substring(0, this.current_block.length - 3);
				}
				 
				this.in_code_block = false;
				this.current_line = "";
				return;
			}
			
			// Not a code block marker
			if (this.in_code_block) {
				// In code block: add newline to current_block (text already added by add_text)
				this.current_block += "\n";
			}
			// If not in code block, we just discard the line (as per requirements)
			
			// Clear current_line after processing
			this.current_line = "";
		}
		
		
		
		protected override void readParams(Json.Object parameters)
		{
			// Read simple parameters first
			base.readParams(parameters); 
			
			// Read range array
			if (parameters.has_member("range")) {
				var range_node = parameters.get_member("range");
				var range_array = range_node.get_array();
				if (range_array.get_length() >= 2) {
					this.start_line = (int)range_array.get_int_element(0);
					this.end_line = (int)range_array.get_int_element(1);
				}
			}
		}
		
		protected override bool build_perm_question()
		{
			// Validate parameters first
			if (this.file_path == "" || this.start_line < 1 || this.end_line < this.start_line) {
				return false;
			}
			
			// Note: chat_call is not available in build_perm_question, 
			// so we can't extract code block here. This will be done in execute().
			// For now, just validate that we have the basic parameters.
			
			// Store the edit properties
			
			// Normalize file path
			this.normalized_path = this.normalize_file_path(this.file_path);
			
			// Set permission properties for WRITE operation
			this.permission_target_path = this.normalized_path;
			this.permission_operation = ChatPermission.Operation.WRITE;
			this.permission_question = "Write to file '" + this.normalized_path + "'?";
			
			return true;
		}
		
		/**
		 * Override execute() to handle permission flow:
		 * Request WRITE permission (which automatically includes READ) to generate diff and write file.
		 */
		public override async string execute(Ollama.ChatCall chat_call, Json.Object parameters)
		{
			// Check if streaming is enabled (required for this tool)
			if (!this.client.stream) {
				return "ERROR: EditFile tool requires streaming to be enabled (client.stream = true)";
			}
			
			// Read parameters
			this.prepare(parameters);
			
			// Validate parameters with descriptive errors
			if (this.file_path == "") {
				return "ERROR: file_path parameter is required";
			}
			if (this.start_line < 1) {
				return "ERROR: start_line must be >= 1 (got " + this.start_line.to_string() + ")";
			}
			if (this.end_line < this.start_line) {
				return "ERROR: end_line must be >= start_line (got start=" + this.start_line.to_string() + ", end=" + this.end_line.to_string() + ")";
			}
			
			// Process any remaining current_line (as if there was a final linebreak)
			if (this.current_line.length > 0) {
				this.add_linebreak();
			}
			
			// Extract code from last code block (use streaming data)
			this.replacement = this.current_block != "" ? this.current_block : null;
			if (this.replacement == null) {
				return "ERROR: No code block found in recent assistant messages. Please output a code block before calling this tool.";
			}
			
			// Build permission question and request permission
			if (!this.build_perm_question()) {
				return "ERROR: Invalid parameters";
			}
			
			var normalized_path = this.normalize_file_path(this.file_path);
			
			// Request WRITE permission (which includes READ automatically)
			// This allows us to read the file for diff generation and write the changes
			if (!(yield this.client.permission_provider.request(this))) {
				return "ERROR: Permission denied: " + this.permission_question;
			}
			
			// Execute the tool
			try {
				var result = this.execute_tool(chat_call, parameters);
				// Emit after_change signal
				this.after_change(this.normalized_path, this.start_line, this.end_line);
				return result;
			} catch (Error e) {
				return "ERROR: " + e.message;
			}
		}
		
		protected override string execute_tool(Ollama.ChatCall chat_call, Json.Object parameters) throws Error
		{
			// Re-parse parameters
			this.prepare(parameters);
			
			// Normalize path if not already done
			if (this.normalized_path == "") {
				this.normalized_path = this.normalize_file_path(this.file_path);
			}
			
			var file_exists = GLib.FileUtils.test(this.normalized_path, GLib.FileTest.IS_REGULAR);
			
			// If file doesn't exist, validate that edit can create a new file
			if (!file_exists) {
				// For new files, edit should be an insertion (start == end) or start at line 1
				if (this.start_line != this.end_line && this.start_line != 1) {
					throw new GLib.IOError.INVALID_ARGUMENT("Cannot create new file: edit starts at line " + this.start_line.to_string() + " but file doesn't exist");
				}
			} else {
				// File exists - validate edit
				if (this.start_line < 1) {
					throw new GLib.IOError.INVALID_ARGUMENT("Start line number must be >= 1 (got " + this.start_line.to_string() + ")");
				}
				if (this.end_line < this.start_line) {
					throw new GLib.IOError.INVALID_ARGUMENT("End line number must be >= start (got start=" + this.start_line.to_string() + ", end=" + this.end_line.to_string() + ")");
				}
			}
			
			// Emit before_change signal (notification only - blocking handled by permission system)
			this.before_change(this.normalized_path, this.start_line, this.end_line);
			
			// Check if permission status has changed (e.g., revoked by signal handler)
			if (!this.client.permission_provider.check_permission(this)) {
				throw new GLib.IOError.PERMISSION_DENIED("Permission denied or revoked");
			}
			
			// Log and notify that we're starting to write
			GLib.debug("Starting to write file %s", this.normalized_path);
			this.client.tool_message("Writing to file " + this.normalized_path + "...");
			
			// Apply edit using streaming approach
			this.apply_edit();
			
			// Log and send status message after successful write
			GLib.debug("Successfully wrote file %s", this.normalized_path);
			this.client.tool_message("Wrote file " + this.normalized_path);
			
			return "Successfully edited file: " + this.normalized_path;
		}
		
		
		/**
		 * Applies edit to a file using a streaming approach.
		 * Handles both existing files and new file creation.
		 */
		private void apply_edit() throws Error
		{
			var file_exists = GLib.FileUtils.test(this.normalized_path, GLib.FileTest.IS_REGULAR);
			
			if (!file_exists) {
				this.create_new_file();
				return;
			}
			
			// Create temporary file for output in system temp directory
			var file_basename = GLib.Path.get_basename(this.normalized_path);
			var timestamp = GLib.get_real_time().to_string();
			var temp_file = GLib.File.new_for_path(GLib.Path.build_filename(
				GLib.Environment.get_tmp_dir(),
				"ollmchat-edit-" + file_basename + "-" + timestamp + ".tmp"
			));
			var temp_output = new GLib.DataOutputStream(
				temp_file.create(GLib.FileCreateFlags.NONE, null)
			);
			
			// Open input file
			var input_file = GLib.File.new_for_path(file_path);
			var input_data = new GLib.DataInputStream(input_file.read(null));
			
			this.process_edit(input_data, temp_output);
			
			input_data.close(null);
			temp_output.close(null);
			
			// Replace original file with temporary file
			var original_file = GLib.File.new_for_path(this.normalized_path);
			try {
				original_file.delete(null);
			} catch (GLib.Error e) {
				// Ignore if file doesn't exist
			}
			temp_file.move(original_file, GLib.FileCopyFlags.OVERWRITE, null, null);
		}
		
		/**
		 * Creates a new file with the replacement content.
		 */
		private void create_new_file() throws Error
		{
			// Ensure parent directory exists
			var parent_dir = GLib.Path.get_dirname(this.normalized_path);
			var dir = GLib.File.new_for_path(parent_dir);
			if (!dir.query_exists()) {
				try {
					dir.make_directory_with_parents(null);
				} catch (GLib.Error e) {
					throw new GLib.IOError.FAILED("Failed to create parent directory: " + e.message);
				}
			}
			
			// Create new file and write replacement content
			var output_file = GLib.File.new_for_path(this.normalized_path);
			var output_stream = new GLib.DataOutputStream(
				output_file.create(GLib.FileCreateFlags.NONE, null)
			);
			
			try {
				foreach (var new_line in this.replacement.split("\n")) {
					output_stream.put_string(new_line);
					output_stream.put_byte('\n');
				}
			} finally {
				try {
					output_stream.close(null);
				} catch (GLib.Error e) {
					// Ignore close errors
				}
			}
		}
		
		/**
		 * Processes the file line by line, applying the edit.
		 */
		private void process_edit(
			GLib.DataInputStream input_data,
			GLib.DataOutputStream temp_output) throws Error
		{
			int current_line = 0;
			string? line;
			size_t length;
			
			while ((line = input_data.read_line(out length, null)) != null) {
				current_line++;
				
				// If we're at the start of the edit, write replacement and skip old lines
				if (current_line == this.start_line) {
					// Write replacement lines
					foreach (var new_line in this.replacement.split("\n")) {
						temp_output.put_string(new_line);
						temp_output.put_byte('\n');
					}
					
					// Skip old lines in input stream until end of edit range (exclusive)
					while (current_line < this.end_line - 1) {
						line = input_data.read_line(out length, null);
						if (line == null) {
							break;
						}
						current_line++;
					}
					continue;
				}
				
				// If we're in the edit range (being replaced), skip it
				if (current_line >= this.start_line && current_line < this.end_line) {
					continue;
				}
				
				// Write line as-is (not part of the edit)
				temp_output.put_string(line);
				temp_output.put_byte('\n');
			}
			
			// Handle insertions at end of file (range [n, n] where n > file length)
			if (this.start_line == this.end_line && this.start_line > current_line) {
				foreach (var new_line in this.replacement.split("\n")) {
					temp_output.put_string(new_line);
					temp_output.put_byte('\n');
				}
			}
		}
	}
}


