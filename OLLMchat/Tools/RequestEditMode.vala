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
	 * Request handler for editing files by activating "edit mode" for a file.
	 */
	public class RequestEditMode : OLLMchat.Tool.RequestBase
	{
		// Static list to keep active requests alive so signal handlers can be called
		private static Gee.ArrayList<RequestEditMode> active_requests = new Gee.ArrayList<RequestEditMode>();
		
		// Parameter properties
		public string file_path { get; set; default = ""; }
		public bool complete_file { get; set; default = false; }
		public bool overwrite { get; set; default = false; }
		
		// Normalized path (set during permission building)
		private string normalized_path = "";
		
		// Streaming state tracking
		private string current_line = "";
		private bool in_code_block = false;
		private string current_block = "";
		private int current_start_line = -1;
		private int current_end_line = -1;
		
		// Captured changes
		private Gee.ArrayList<EditModeChange> changes = new Gee.ArrayList<EditModeChange>();
		
		// Stored error messages to send when message is done
		private Gee.ArrayList<string> error_messages = new Gee.ArrayList<string>();
		
		// Signal handler IDs for disconnection
		private ulong stream_content_id = 0;
		private ulong message_created_id = 0;
		
		/**
		 * Default constructor.
		 */
		public RequestEditMode()
		{
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
			this.permission_operation = OLLMchat.ChatPermission.Operation.WRITE;
			this.permission_question = "Write to file '" + this.normalized_path + "'?";
			
			return true;
		}
		
		protected override string execute_request() throws Error
		{
			// Validate parameters with descriptive errors
			if (this.file_path == "") {
				throw new GLib.IOError.INVALID_ARGUMENT("file_path parameter is required");
			}
			
			// Build instructions based on mode
			string instructions;
			if (this.complete_file) {
				instructions = "Since complete_file=true is enabled, code blocks should only have the language tag (e.g., ```javascript, ```python). Do not include line numbers. The entire file content will be replaced.";
			} else {
				instructions = "Code blocks must include line range in format type:startline:endline (e.g., ```javascript:10:15, ```python:1:5). The range is inclusive of the start line and exclusive of the end line. Line numbers are 1-based.";
			}
			
			// Build the message string
			string message = "Edit mode activated for file: " + this.normalized_path + "\n\n";
			if (this.complete_file) {
				message += "You should now output the content of the file you want to write in a code block.\n\n";
			}
			message += instructions + "\n\n";
			if (this.overwrite && GLib.FileUtils.test(this.normalized_path, GLib.FileTest.IS_REGULAR)) {
				message += "You set overwrite=true, so we will overwrite the existing file when you complete your message.";
			}
			
			// Emit to UI
			this.chat_call.client.tool_message(
				new OLLMchat.Message(this.chat_call, "ui", message)
			);
			
			// Keep this request alive so signal handlers can be called
			active_requests.add(this);
			GLib.debug("RequestEditMode.execute_request: Added request to active_requests (total=%zu, file=%s)", 
				active_requests.size, this.normalized_path);
			
			// Connect signals for this request
			this.connect_signals();
			
			return message;
		}
		
		/**
		 * Connects client signals to this request's handlers.
		 * Called when edit mode is activated for this request.
		 */
		public void connect_signals()
		{
			GLib.debug("RequestEditMode.connect_signals: Connecting signals for file %s (tool.active=%s)", 
				this.normalized_path, this.tool.active.to_string());
			
			// Connect to stream_content signal to capture code blocks as they stream in
			if (this.chat_call.client.stream) {
				this.stream_content_id = this.chat_call.client.stream_content.connect((new_text, response) => {
					// Check if this request is still valid before processing
					if (this.chat_call == null || this.chat_call.client == null) {
						return;
					}
					// Only process if this response belongs to our chat_call
					if (response.call != this.chat_call) {
						return;
					}
					this.process_streaming_content(new_text);
				});
			}
			
			// Connect to message_created signal to detect when message is done and apply changes
			this.message_created_id = this.chat_call.client.message_created.connect((message, content_interface) => {
				// Check if this request is still valid before processing
				if (this.chat_call == null || this.chat_call.client == null) {
					GLib.debug("RequestEditMode: message_created handler called but chat_call/client is null (file=%s)", 
						this.normalized_path);
					return;
				}
				// Only process if this message belongs to our chat_call
				if (message.message_interface != this.chat_call) {
					GLib.debug("RequestEditMode: message_created handler called for different chat_call, skipping (file=%s, message_interface=%p, our_chat_call=%p)", 
						this.normalized_path, message.message_interface, this.chat_call);
					return;
				}
				this.on_message_created(message, content_interface);
			});
			GLib.debug("RequestEditMode.connect_signals: Connected message_created signal (id=%lu)", this.message_created_id);
		}
		
		/**
		 * Disconnects client signals from this request's handlers.
		 * Called when edit mode is deactivated for this request.
		 */
		/**
		 * Disconnects signal handlers but keeps the object alive.
		 * Call this before sending the final reply to stop processing new content.
		 */
		public void disconnect_signals()
		{
			if (this.chat_call == null || this.chat_call.client == null) {
				return;
			}
			
			// Disconnect stream_content signal
			if (this.stream_content_id != 0 && GLib.SignalHandler.is_connected(this.chat_call.client, this.stream_content_id)) {
				this.chat_call.client.disconnect(this.stream_content_id);
			}
			this.stream_content_id = 0;
			
			// Disconnect message_created signal
			if (this.message_created_id != 0 && GLib.SignalHandler.is_connected(this.chat_call.client, this.message_created_id)) {
				this.chat_call.client.disconnect(this.message_created_id);
			}
			this.message_created_id = 0;
			
			GLib.debug("RequestEditMode.disconnect_signals: Disconnected signals (file=%s, still in active_requests=%s)", 
				this.normalized_path, active_requests.contains(this).to_string());
		}
		
		/**
		 * Processes streaming content to track code blocks.
		 * Splits on newlines and processes each part.
		 */
		public void process_streaming_content(string new_text)
		{
			// Check if request is still valid
			if (this.chat_call == null || this.chat_call.client == null) {
				return;
			}
			
			// Only process if tool is active
			if (!this.tool.active) {
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
		 * Language tag format: ```type:startline:endline (e.g., ```python:10:15) when complete_file=false
		 * Language tag format: ```type (e.g., ```python) when complete_file=true
		 * 
		 * @param line The line that starts with ```
		 * @return true if successfully parsed and entered code block, false otherwise
		 */
		private bool try_parse_code_block_opener(string stripped_line)
		{
			var tag = stripped_line.substring(3).strip(); // Remove ```
			GLib.debug("RequestEditMode.try_parse_code_block_opener: Parsing code block opener (file=%s, tag='%s', complete_file=%s)", 
				this.normalized_path, tag, this.complete_file.to_string());
			
			// For complete_file mode, accept language-only tags (no colons)
			if (this.complete_file && !tag.contains(":")) {
				GLib.debug("RequestEditMode.try_parse_code_block_opener: Complete file mode - accepting language-only tag '%s'", tag);
				this.current_start_line = -1;
				this.current_end_line = -1;
				this.in_code_block = true;
				this.current_line = "";
				this.current_block = "";
				return true;
			}
			
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
			// Accept it (we'll validate later if complete_file mode requires line numbers)
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
				
				// Exiting code block: create EditModeChange
				// Remove the marker text from current_block if it was accidentally added
				if (this.current_block.has_suffix("```\n")) {
					this.current_block = this.current_block.substring(0, this.current_block.length - 4);
				} else if (this.current_block.has_suffix("```")) {
					this.current_block = this.current_block.substring(0, this.current_block.length - 3);
				}
				
				// Create EditModeChange
				GLib.debug("RequestEditMode.add_linebreak: Captured code block (file=%s, start=%d, end=%d, size=%zu bytes)", 
					this.normalized_path, this.current_start_line, this.current_end_line, this.current_block.length);
				this.changes.add(new EditModeChange() {
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
		
		/**
		 * Called when a message is created. Processes final content and applies changes when "done" message is received.
		 */
		private void on_message_created(OLLMchat.Message message, OLLMchat.ChatContentInterface? content_interface)
		{
			// Check if request is still valid
			if (this.chat_call == null || this.chat_call.client == null) {
				GLib.debug("RequestEditMode.on_message_created: chat_call/client is null, skipping (file=%s)", 
					this.normalized_path);
				return;
			}
			
			GLib.debug("RequestEditMode.on_message_created: Received message (file=%s, role=%s, is_done=%s, tool_active=%s)", 
				this.normalized_path, message.role, message.is_done.to_string(), this.tool.active.to_string());
			
			// Only process "done" messages - this indicates the assistant message is complete
			if (!message.is_done) {
				GLib.debug("RequestEditMode.on_message_created: Message is not 'done', skipping (role=%s)", message.role);
				return;
			}
			
			// content_interface should be Response.Chat for assistant messages
			if (content_interface == null || !(content_interface is OLLMchat.Response.Chat)) {
				GLib.debug("RequestEditMode.on_message_created: Invalid content_interface (null=%s, is_Response.Chat=%s)", 
					(content_interface == null).to_string(), 
					(content_interface != null && content_interface is OLLMchat.Response.Chat).to_string());
				return;
			}
			
			var response = content_interface as OLLMchat.Response.Chat;
			
			// Double-check chat_call is still valid before accessing client
			if (this.chat_call == null || this.chat_call.client == null) {
				return;
			}
			
			GLib.debug("RequestEditMode.on_message_created: Processing done message (file=%s, changes_count=%zu)", 
				this.normalized_path, this.changes.size);
			
			// If not streaming, process the full content at once
			// If streaming, we should have already captured everything via stream_content
			if (!this.chat_call.client.stream && response.message != null && response.message.content != "") {
				var parts = response.message.content.split("\n");
				for (int i = 0; i < parts.length; i++) {
					this.add_text(parts[i]);
					this.add_linebreak();
				}
			}
			
			// Process any remaining current_line (for both streaming and non-streaming)
			this.add_linebreak();
			
			// Check if we have any changes - store error if not
			if (this.changes.size == 0) {
				// No changes were captured
				GLib.debug("RequestEditMode.on_message_created: No changes captured (file=%s, in_code_block=%s, current_block_size=%zu)", 
					this.normalized_path, this.in_code_block.to_string(), this.current_block.length);
				this.error_messages.add("There was a problem: we could not read the content you sent.\n\nYou should call edit mode again, and follow the instructions that you receive.");
				this.reply_with_errors(response);
				return;
			}
			
			GLib.debug("RequestEditMode.on_message_created: Found %zu changes, applying to file %s", 
				this.changes.size, this.normalized_path);
			
			// Apply changes
			try {
				this.apply_all_changes();
				
				// Calculate success message with line count and send
				string success_message;
				try {
					int line_count = this.count_file_lines();
					success_message = @"File '`$(this.normalized_path)`' has been updated. It now has `$(line_count)` lines.";
				} catch (Error e) {
					GLib.warning("Error counting lines in %s: %s", this.normalized_path, e.message);
					// Send success message without line count
					success_message = @"File '`$(this.normalized_path)`' has been updated.";
				}
				
				// Emit UI message
				this.chat_call.client.tool_message(
					new OLLMchat.Message(this.chat_call, "ui", success_message)
				);
				
				// Send tool reply to LLM
				this.reply_with_errors(response, success_message);
			} catch (Error e) {
				GLib.warning("Error applying changes to %s: %s", this.normalized_path, e.message);
				// Store error message instead of sending immediately
				this.error_messages.add("There was a problem applying the changes: " + e.message);
				this.reply_with_errors(response);
				return;
			}
		}
		
		/**
		 * Sends a message to continue the conversation and disconnects signals.
		 * This method should be called on both success and error paths to ensure signals are always disconnected.
		 * Uses chat_call.reply() to continue the conversation with the LLM's response.
		 */
		private void reply_with_errors(OLLMchat.Response.Chat response, string message = "")
		{
			if (this.chat_call == null) {
				this.disconnect_signals();
				active_requests.remove(this);
				GLib.debug("RequestEditMode.reply_with_errors: Removed request from active_requests (remaining=%zu, file=%s)", 
					active_requests.size, this.normalized_path);
				return;
			}
			
			// Disconnect signals first - we're done processing new content
			this.disconnect_signals();
			
			// Build reply: errors first (if any), then message
			string reply_text = (this.error_messages.size > 0 
				? string.joinv("\n", this.error_messages.to_array()) + (message != "" ? "\n" : "") 
				: "") + message;
			
			// Schedule reply() to run on idle to avoid race condition:
			// The previous response's final chunk (done=true) may still be processing in the event loop,
			// which sets is_streaming_active=false. If we call reply() immediately, it sets is_streaming_active=true,
			// but then the final chunk processing overwrites it back to false. By deferring to idle, we ensure
			// the final chunk processing completes first, then reply() sets is_streaming_active=true before
			// the continuation response starts streaming.
			GLib.Idle.add(() => {
				this.chat_call.reply.begin(
					reply_text,
					response,
					(obj, res) => {
						// Remove from active requests after reply completes
						active_requests.remove(this);
						GLib.debug("RequestEditMode.reply_with_errors: Removed request from active_requests (remaining=%zu, file=%s)", 
							active_requests.size, this.normalized_path);
					}
				);
				return false; // Don't repeat
			});
		}
		
		/**
		 * Applies all captured changes to a file.
		 */
		private void apply_all_changes() throws Error
		{
			if (this.changes.size == 0) {
				return;
			}
			
			// Check if permission status has changed (e.g., revoked by signal handler)
			if (!this.chat_call.client.permission_provider.check_permission(this)) {
				throw new GLib.IOError.PERMISSION_DENIED("Permission denied or revoked");
			}
			
			// Log and notify that we're starting to write
			GLib.debug("Starting to apply changes to file %s", this.normalized_path);
			this.chat_call.client.tool_message(
				new OLLMchat.Message(this.chat_call, "ui",
				"Applying changes to file " + this.normalized_path + "...")
			);
		
			
			var file_exists = GLib.FileUtils.test(this.normalized_path, GLib.FileTest.IS_REGULAR);
			
			// Validate and apply changes
			if (this.complete_file) {
				// Complete file mode: only allow a single change
				if (this.changes.size > 1) {
					throw new GLib.IOError.INVALID_ARGUMENT("Cannot create/overwrite file: multiple changes detected. Complete file mode only allows a single code block.");
				}
				// Check if code block had line numbers (invalid in complete_file mode)
				// In complete_file mode, start and end should both be -1 (not set) when no line numbers provided
				// If they sent line numbers, start would be >= 1
				if (this.changes[0].start != -1 || this.changes[0].end != -1) {
					throw new GLib.IOError.INVALID_ARGUMENT("Cannot use line numbers in complete_file mode. When complete_file=true, code blocks should only have the language tag (e.g., ```python, not ```python:1:1).");
				}
				// Check if file exists and overwrite is not allowed
				if (file_exists && !this.overwrite) {
					throw new GLib.IOError.EXISTS("File already exists: " + this.normalized_path + ". Use overwrite=true to overwrite it.");
				}
				// Create new file or overwrite existing file
				this.create_new_file_with_changes();
			} else {
				// Normal mode: file must exist
				if (!file_exists) {
					throw new GLib.IOError.NOT_FOUND("File does not exist: " + this.normalized_path + ". Use complete_file=true to create a new file.");
				}
				// Apply edits to existing file
				this.apply_edits();
			}
			
			// Log and send status message after successful write
			GLib.debug("RequestEditMode.apply_all_changes: Successfully applied changes to file %s", this.normalized_path);
			var message = new OLLMchat.Message(this.chat_call, "ui",
				"Applied changes to file " + this.normalized_path);
			GLib.debug("RequestEditMode.apply_all_changes: Created message (role=%s, content='%s', chat_call=%p, client=%p, in_active_requests=%s)", 
				message.role, message.content, this.chat_call, this.chat_call.client, active_requests.contains(this).to_string());
			this.chat_call.client.tool_message(message);
			GLib.debug("RequestEditMode.apply_all_changes: Emitted tool_message signal");
			
			// Emit change_done signal for each change
			var edit_tool = (EditMode) this.tool;
			foreach (var change in this.changes) {
				edit_tool.change_done(this.normalized_path, change);
			}
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
			
			 
			
			// Create new file and write all changes (overwrite if exists)
			// If overwrite is true and file exists, delete it first
			var output_file = GLib.File.new_for_path(this.normalized_path);
			if (this.overwrite && output_file.query_exists()) {
				try {
					output_file.delete(null);
				} catch (GLib.Error e) {
					throw new GLib.IOError.FAILED("Failed to delete existing file: " + e.message);
				}
			}
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
				var edit_tool = (EditMode) this.tool;
				edit_tool.change_done(this.normalized_path, this.changes[0]);
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
			var edit_tool = (EditMode) this.tool;
			
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
						edit_tool.change_done(this.normalized_path, change);
						
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
					edit_tool.change_done(this.normalized_path, change);
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
