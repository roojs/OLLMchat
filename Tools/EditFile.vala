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
	 * Tool for editing files by activating "edit mode" for a file.
	 * 
	 * This tool activates edit mode for a file. While edit mode is active, code blocks
	 * with type:startline:endline format are automatically captured. When chat is done,
	 * all captured changes are applied to the file.
	 */
	public class EditFile : Ollama.Tool
	{
		// Parameter properties
		public string file_path { get; set; default = ""; }
		public bool create { get; set; default = false; }
		
		// Edit mode tracking
		private bool monitoring = false;
		private Gee.ArrayList<EditFileChange> changes = new Gee.ArrayList<EditFileChange>();
		private string normalized_path = "";
		
		// Streaming state tracking
		private string current_line = "";
		private bool in_code_block = false;
		private string current_block = "";
		private int current_start_line = -1;
		private int current_end_line = -1;
		
		public override string name { get { return "edit_mode"; } }
		
		public override string description { get {
			return """
Turn on edit mode for a file.

While edit mode is active, code blocks will be automatically captured and applied to the file when the chat is done.

To apply changes, just end the chat (send chat done signal). All captured code blocks will be applied to the file automatically.

Code block format depends on the create parameter:
- If create=false (default): Code blocks must include line range in format type:startline:endline (e.g., python:10:15, vala:1:5). The range is inclusive of the start line and exclusive of the end line. Line numbers are 1-based.
- If create=true: Code blocks should only have the language tag (e.g., ```python, ```vala). The entire file content will be replaced. If the file doesn't exist, it will be created. If it exists, it will be overwritten.

When create=true, do not include line numbers in the code block. When create=false, line numbers are required.""";
		} }
		
		public override string parameter_description { get {
			return """
@param file_path {string} [required] The path to the file to edit.
@param create {boolean} [optional] If true, create or overwrite the entire file. Code blocks should only have language tag (no line numbers). Default is false.""";
		} }
		
		/**
		 * Signal emitted when a change is actually applied to a file.
		 * This signal is emitted for each change as it is applied, allowing UI
		 * components to track and preview changes non-blockingly.
		 */
		public signal void change_done(string file_path, EditFileChange change);
		
		public EditFile(Ollama.Client client)
		{
			base(client);
			
			// Connect to stream_start signal to reset state when streaming starts
			this.client.stream_start.connect(() => {
				// Reset state
				this.current_line = "";
				this.in_code_block = false;
				this.current_block = "";
				this.current_start_line = -1;
				this.current_end_line = -1;
			});
			
			// Connect to stream_content signal to capture streaming messages
			this.client.stream_content.connect((new_text, response) => {
				this.process_streaming_content(new_text);
			});
			
			// Connect to stream_chunk signal to handle stream chunks
			this.client.stream_chunk.connect((new_text, is_thinking, response) => {
				this.on_stream_chunk(response);
			});
		}
		
		/**
		 * Processes streaming content to track code blocks.
		 * Splits on newlines and processes each part.
		 */
		private void process_streaming_content(string new_text)
		{
			// Only process stream if tool is active and monitoring
			if (!this.active || !this.monitoring) {
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
		 * Tries to parse a code block opener.
		 * Language tag format: ```type:startline:endline (e.g., ```python:10:15) when create=false
		 * Language tag format: ```type (e.g., ```python) when create=true
		 * 
		 * @param line The line that starts with ```
		 * @return true if successfully parsed and entered code block, false otherwise
		 */
		private bool try_parse_code_block_opener(string stripped_line)
		{
			var tag = stripped_line.substring(3).strip(); // Remove ```
			if (!tag.contains(":")) {
				return false;
			}
			
			// Check if tag contains line numbers
			if (tag.contains(":")) {
				// Parse line numbers from tag (format: type:startline:endline)
				var parts = tag.split(":");
				if (parts.length < 3) {
					return false;
				}
				
				int start_line = -1;
				int end_line = -1;
				
				if (!int.try_parse(parts[parts.length - 2], out start_line)) {
					return false;
				}
				if (!int.try_parse(parts[parts.length - 1], out end_line)) {
					return false;
				}
				if (start_line < 1 || end_line < start_line) {
					return false;
				}
				
				// Valid line numbers - store them and enter code block
				this.current_start_line = start_line;
				this.current_end_line = end_line;
				this.in_code_block = true;
				this.current_line = "";
				this.current_block = "";
				return true;
			}
			
			// No line numbers - language-only tag
			// Accept it (we'll validate later if create mode requires line numbers)
			this.current_start_line = -1;
			this.current_end_line = -1;
			this.in_code_block = true;
			this.current_line = "";
			this.current_block = "";
			return true;
		}
		
		/**
		 * Processes line break: checks current_line for code block markers,
		 * updates state, and clears current_line.
		 */
		private void add_linebreak()
		{
			// Check if this line contains a language tag with opening marker
			// The line must start with ``` (no leading whitespace)
			if (!this.in_code_block && this.current_line.has_prefix("```")) {
				if (this.try_parse_code_block_opener(this.current_line)) {
					return;
				}
			}
			
			// Check if current_line is a code block marker (```)
			if (this.current_line == "```") {
				// Toggle code block state
				if (!this.in_code_block) {
					// Entering code block without language tag (shouldn't happen in our format, but handle it)
					this.in_code_block = true;
					this.current_line = "";
					this.current_block = "";
					return;
				}
				
				// Exiting code block: create EditFileChange
				// Remove the marker text from current_block if it was accidentally added
				if (this.current_block.has_suffix("```\n")) {
					this.current_block = this.current_block.substring(0, this.current_block.length - 4);
				} else if (this.current_block.has_suffix("```")) {
					this.current_block = this.current_block.substring(0, this.current_block.length - 3);
				}
				
				// Create EditFileChange
				this.changes.add(new EditFileChange() {
					start = this.current_start_line,
					end = this.current_end_line,
					replacement = this.current_block
				});
				
				this.in_code_block = false;
				this.current_line = "";
				this.current_block = "";
				this.current_start_line = -1;
				this.current_end_line = -1;
				return;
			}
			
			// Not a code block marker
			if (this.in_code_block) {
				// In code block: add newline to current_block (text already added by add_text)
				this.current_block += "\n";
			}
			
			// Clear current_line after processing
			this.current_line = "";
		}
		
		protected override bool build_perm_question()
		{
			// Validate parameters first
			if (this.file_path == "") {
				return false;
			}
			
			// Normalize file path
			this.normalized_path = this.normalize_file_path(this.file_path);
			
			// Set permission properties for WRITE operation
			this.permission_target_path = this.normalized_path;
			this.permission_operation = ChatPermission.Operation.WRITE;
			this.permission_question = "Write to file '" + this.normalized_path + "'?";
			
			return true;
		}
		
		/**
		 * Override execute() to only request permission and activate edit mode.
		 */
		public override async string execute(Ollama.ChatCall chat_call, Json.Object parameters)
		{
			// Read parameters
			this.prepare(parameters);
			
			// Validate parameters with descriptive errors
			if (this.file_path == "") {
				return "ERROR: file_path parameter is required";
			}
			
			// Build permission question and request permission
			if (!this.build_perm_question()) {
				return "ERROR: Invalid parameters";
			}
			
			// Request WRITE permission (which includes READ automatically)
			if (!(yield this.client.permission_provider.request(this))) {
				return "ERROR: Permission denied: " + this.permission_question;
			}
			
			// Activate edit mode
			this.monitoring = true;
			
			// Initialize state
			this.current_line = "";
			this.in_code_block = false;
			this.current_block = "";
			this.current_start_line = -1;
			this.current_end_line = -1;
			this.changes.clear();
			
			return "Edit mode activated for file: " + this.normalized_path;
		}
		
		protected override string execute_tool(Ollama.ChatCall chat_call, Json.Object parameters) throws Error
		{
			// This method is not used in edit mode - execute() handles everything
			// But it's abstract in base class, so we must implement it
			return "Edit mode activated";
		}
		
		/**
		 * Called on every stream chunk. Applies changes when response is done.
		 */
		private void on_stream_chunk(Ollama.ChatResponse response)
		{
			// Only process if monitoring
			if (!this.monitoring) {
				return;
			}
			
			// Only apply changes when response is done
			if (!response.done) {
				return;
			}
			
			// If not streaming, process the full content at once
			if (!this.client.stream && response.message != null && response.message.content != "") {
				var parts = response.message.content.split("\n");
				for (int i = 0; i < parts.length; i++) {
					this.add_text(parts[i]);
					this.add_linebreak();
				}
			}
			
			// Process any remaining current_line
			this.add_linebreak();
			
			// Check if we have any changes - return early if not
			if (this.changes.size == 0) {
				// No changes were captured
				if (response.call != null) {
					response.call.reply.begin("There was a problem applying the changes.", response);
				}
				// Clear monitoring flag and state
				this.reset_state();
				return;
			}
			
			// Apply changes
			try {
				this.apply_all_changes(response);
			} catch (Error e) {
				GLib.warning("Error applying changes to %s: %s", this.normalized_path, e.message);
				// Try to send error message via ChatCall if available
				if (response.call != null) {
					response.call.reply.begin("There was a problem applying the changes: " + e.message, response);
				}
				// Clear monitoring flag and state
				this.reset_state();
				return;
			}
			
			// Clear monitoring flag and state
			this.reset_state();
		}
		
		/**
		 * Resets the internal state of the EditFile tool.
		 */
		private void reset_state()
		{
			this.monitoring = false;
			this.current_line = "";
			this.in_code_block = false;
			this.current_block = "";
			this.current_start_line = -1;
			this.current_end_line = -1;
			this.changes.clear();
		}
		
		/**
		 * Applies all captured changes to a file.
		 */
		private void apply_all_changes(Ollama.ChatResponse response) throws Error
		{
			if (this.changes.size == 0) {
				return;
			}
			
			// Check if permission status has changed (e.g., revoked by signal handler)
			if (!this.client.permission_provider.check_permission(this)) {
				throw new GLib.IOError.PERMISSION_DENIED("Permission denied or revoked");
			}
			
			// Log and notify that we're starting to write
			GLib.debug("Starting to apply changes to file %s", this.normalized_path);
			this.client.tool_message("Applying changes to file " + this.normalized_path + "...");
			
			var file_exists = GLib.FileUtils.test(this.normalized_path, GLib.FileTest.IS_REGULAR);
			
			// Validate and apply changes
			if (this.create) {
				// Create mode: only allow a single change
				if (this.changes.size > 1) {
					throw new GLib.IOError.INVALID_ARGUMENT("Cannot create/overwrite file: multiple changes detected. Create mode only allows a single code block.");
				}
				// Check if code block had line numbers (invalid in create mode)
				// In create mode, start and end should both be -1 (not set) when no line numbers provided
				// If they sent line numbers, start would be >= 1
				if (this.changes[0].start != -1 || this.changes[0].end != -1) {
					throw new GLib.IOError.INVALID_ARGUMENT("Cannot use line numbers in create mode. When create=true, code blocks should only have the language tag (e.g., ```python, not ```python:1:1).");
				}
				// Create new file or overwrite existing file
				this.create_new_file_with_changes();
			} else {
				// Normal mode: file must exist
				if (!file_exists) {
					throw new GLib.IOError.NOT_FOUND("File does not exist: " + this.normalized_path + ". Use create=true to create a new file.");
				}
				// Apply edits to existing file
				this.apply_edits();
			}
			
			// Count total lines in file after changes
			int line_count = this.count_file_lines();
			
			// Send message with file details via ChatCall.reply()
			if (response.call != null) {
				var message = @"File '$(this.normalized_path)' has been updated. It now has $(line_count) lines.";
				response.call.reply.begin(message, response);
			}
			
			// Log and send status message after successful write
			GLib.debug("Successfully applied changes to file %s", this.normalized_path);
			this.client.tool_message("Applied changes to file " + this.normalized_path);
		}
		
		/**
		 * Applies multiple edits to a file using a streaming approach.
		 * Handles both existing files and new file creation.
		 */
		private void apply_edits() throws Error
		{
			// Sort changes by start line (descending) so we can apply them in reverse order
			this.changes.sort((a, b) => {
				if (a.start < b.start) return 1;
				if (a.start > b.start) return -1;
				return 0;
			});
			
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
			var input_file = GLib.File.new_for_path(this.normalized_path);
			var input_data = new GLib.DataInputStream(input_file.read(null));
			
			this.process_edits(input_data, temp_output);
			
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
		 * Creates a new file with all changes applied.
		 */
		private void create_new_file_with_changes() throws Error
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
			
			 
			
			// Create new file and write all changes
			var output_file = GLib.File.new_for_path(this.normalized_path);
			var output_stream = new GLib.DataOutputStream(
				output_file.create(GLib.FileCreateFlags.NONE, null)
			);
			
			try {
				// Write replacement lines
				foreach (var new_line in this.changes[0].replacement.split("\n")) {
					output_stream.put_string(new_line);
					output_stream.put_byte('\n');
				}
				
				// Emit change_done signal
				this.change_done(this.normalized_path, this.changes[0]);
			} finally {
				try {
					output_stream.close(null);
				} catch (GLib.Error e) {
					// Ignore close errors
				}
			}
		}
		
		/**
		 * Processes the file line by line, applying all edits.
		 */
		private void process_edits(
			GLib.DataInputStream input_data,
			GLib.DataOutputStream temp_output) throws Error
		{
			int current_line = 0;
			string? line;
			size_t length;
			int change_index = 0;
			
			while ((line = input_data.read_line(out length, null)) != null) {
				current_line++;
				
				// Check if we need to apply a change at this line
				if (change_index < this.changes.size) {
					var change = this.changes[change_index];
					
					// If we're at the start of the edit, write replacement and skip old lines
					if (current_line == change.start) {
						// Skip old lines in input stream until end of edit range (exclusive)
						current_line = change.apply_changes(temp_output, input_data, current_line);
						
						// Emit change_done signal
						this.change_done(this.normalized_path, change);
						
						change_index++;
						continue;
					}
					
					// If we're in the edit range (being replaced), skip it
					if (current_line >= change.start && current_line < change.end) {
						continue;
					}
				}
				
				// Write line as-is (not part of any edit)
				temp_output.put_string(line);
				temp_output.put_byte('\n');
			}
			
			// Handle insertions at end of file for remaining changes
			while (change_index < this.changes.size) {
				var change = this.changes[change_index];
				change.write_changes(temp_output, current_line);
				if (change.start == change.end && change.start > current_line) {
					// Emit change_done signal
					this.change_done(this.normalized_path, change);
				}
				change_index++;
			}
		}
		
		/**
		 * Counts the total number of lines in a file.
		 */
		private int count_file_lines() throws Error
		{
			var file = GLib.File.new_for_path(this.normalized_path);
			var file_stream = file.read(null);
			var data_stream = new GLib.DataInputStream(file_stream);
			
			int line_count = 0;
			string? line;
			size_t length;
			
			try {
				while ((line = data_stream.read_line(out length, null)) != null) {
					line_count++;
				}
			} finally {
				try {
					data_stream.close(null);
				} catch (GLib.Error e) {
					// Ignore close errors
				}
			}
			
			return line_count;
		}
	}
}


