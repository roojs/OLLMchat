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
		private Gee.ArrayList<OLLMfiles.FileChange> changes = new Gee.ArrayList<OLLMfiles.FileChange>();
		
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
			
			// Set up permission properties for non-project files first
			this.permission_target_path = this.normalized_path;
			this.permission_operation = OLLMchat.ChatPermission.Operation.WRITE;
			this.permission_question = "Write to file '" + this.normalized_path + "'?";
			
			// Check if file is in active project (skip permission prompt if so)
			// Files in active project are auto-approved and don't need permission checks
			var project_manager = ((EditMode) this.tool).project_manager;
			if (project_manager.get_file_from_active_project(this.normalized_path) != null) {
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
			
			// Send to UI using standardized format
			this.send_ui("txt", "CodeEdit Tool: Edit Mode Activated", message);
			
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
				this.on_message_created.begin(message, content_interface);
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
				
				// Exiting code block: create FileChange
				// Remove the marker text from current_block if it was accidentally added
				if (this.current_block.has_suffix("```\n")) {
					this.current_block = this.current_block.substring(0, this.current_block.length - 4);
				} else if (this.current_block.has_suffix("```")) {
					this.current_block = this.current_block.substring(0, this.current_block.length - 3);
				}
				
				// Create FileChange
				GLib.debug("RequestEditMode.add_linebreak: Captured code block (file=%s, start=%d, end=%d, size=%zu bytes)", 
					this.normalized_path, this.current_start_line, this.current_end_line, this.current_block.length);
				this.changes.add(new OLLMfiles.FileChange() {
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
		private async void on_message_created(OLLMchat.Message message, OLLMchat.ChatContentInterface? content_interface)
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
			int line_count = 0;
			OLLMfiles.File? modified_file = null;
			try {
				modified_file = yield this.apply_all_changes();
			} catch (Error e) {
				GLib.warning("Error applying changes to %s: %s", this.normalized_path, e.message);
				// Store error message instead of sending immediately
				this.error_messages.add("There was a problem applying the changes: " + e.message);
				this.reply_with_errors(response);
				return;
			}
			
			// Calculate line count for success message using buffer
			// After write() or apply_edits(), buffer should be loaded
			line_count = yield this.get_line_count_from_buffer(modified_file);
			
			// Build and emit UI message
			string update_message = (line_count > 0)
				? "File '" + this.normalized_path + 
					"' has been updated. It now has " + 
					line_count.to_string() + " lines."
				: "File '" + this.normalized_path + "' has been updated.";
			this.send_ui("txt", "CodeEdit Tool: File Updated", update_message);
			
			// Send tool reply to LLM
			this.reply_with_errors(
				response,
				(line_count > 0)
					? "File '" + this.normalized_path + 
						"' has been updated. It now has " + 
						line_count.to_string() + " lines."
					: "File '" + this.normalized_path + "' has been updated."
			);
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
		 * 
		 * @return The file object that was modified, for use in line counting
		 */
		private async OLLMfiles.File? apply_all_changes() throws Error
		{
			if (this.changes.size == 0) {
				this.send_ui("txt", "CodeEdit Tool: No Changes", "No changes to apply to file " + this.normalized_path);
				return null;
			}
		
			// Get or create File object from path
			var project_manager = ((EditMode) this.tool).project_manager;
			
			// First, try to get from active project
			var file = project_manager.get_file_from_active_project(this.normalized_path);
			
			// Only check permission if file is NOT in active project
			// Files in active project are auto-approved and don't need permission checks
			if (file == null && !this.chat_call.client.permission_provider.check_permission(this)) {
				throw new GLib.IOError.PERMISSION_DENIED("Permission denied or revoked");
			}
			
			// Log that we're starting to write
			GLib.debug("Starting to apply changes to file %s (in_project=%s, changes=%zu)", 
				this.normalized_path, (file != null).to_string(), this.changes.size);
			
			if (file == null) {
				file = new OLLMfiles.File.new_fake(project_manager, this.normalized_path);
			}
			
			// Ensure buffer exists (create if needed)
			file.manager.buffer_provider.create_buffer(file);
			
			var file_exists = GLib.FileUtils.test(this.normalized_path, GLib.FileTest.IS_REGULAR);
			
			// Handle complete_file mode first (early return)
			if (this.complete_file) {
				// Complete file mode: only allow a single change
				if (this.changes.size > 1) {
					this.send_ui("txt", "CodeEdit Tool: Validation Error", "Cannot create/overwrite file: multiple changes detected. Complete file mode only allows a single code block.");
					throw new GLib.IOError.INVALID_ARGUMENT("Cannot create/overwrite file: multiple changes detected. Complete file mode only allows a single code block.");
				}
				// Check if code block had line numbers (invalid in complete_file mode)
				// In complete_file mode, start and end should both be -1 (not set) when no line numbers provided
				// If they sent line numbers, start would be >= 1
				if (this.changes[0].start != -1 || this.changes[0].end != -1) {
					this.send_ui("txt", "CodeEdit Tool: Validation Error", "Cannot use line numbers in complete_file mode. When complete_file=true, code blocks should only have the language tag (e.g., ```python, not ```python:1:1).");
					throw new GLib.IOError.INVALID_ARGUMENT("Cannot use line numbers in complete_file mode. When complete_file=true, code blocks should only have the language tag (e.g., ```python, not ```python:1:1).");
				}
				// Check if file exists and overwrite is not allowed
				if (file_exists && !this.overwrite) {
					this.send_ui("txt", "CodeEdit Tool: Validation Error", "File already exists: " + this.normalized_path + ". Use overwrite=true to overwrite it.");
					throw new GLib.IOError.EXISTS("File already exists: " + this.normalized_path + ". Use overwrite=true to overwrite it.");
				}
				// Create new file or overwrite existing file
				this.send_ui("txt", "CodeEdit Tool: Applying Changes", "Applying changes to file " + this.normalized_path + "...");
				yield this.create_new_file_with_changes(file);
				this.send_ui("txt", "CodeEdit Tool: Changes Applied", "Applied changes to file " + this.normalized_path);
				// Return file object for line counting
				return file;
			}
			
			// Normal mode: file must exist
			if (!file_exists) {
				this.send_ui("txt", "CodeEdit Tool: Validation Error", "File does not exist: " + this.normalized_path + ". Use complete_file=true to create a new file.");
				throw new GLib.IOError.NOT_FOUND("File does not exist: " + this.normalized_path + ". Use complete_file=true to create a new file.");
			}
			// Apply edits to existing file
			this.send_ui("txt", "CodeEdit Tool: Applying Changes", "Applying changes to file " + this.normalized_path + "...");
			yield this.apply_edits(file);
			this.send_ui("txt", "CodeEdit Tool: Changes Applied", "Applied changes to file " + this.normalized_path);
			
			// Log successful write
			GLib.debug("RequestEditMode.apply_all_changes: Successfully applied changes to file %s", this.normalized_path);
			
			// Return file object for line counting
			return file;
		}
		
		/**
		 * Applies multiple edits to a file using buffer-based approach.
		 * Handles both existing files and new file creation.
		 */
		private async void apply_edits(OLLMfiles.File file) throws Error
		{
			// Ensure buffer is loaded
			if (!file.buffer.is_loaded) {
				yield file.buffer.read_async();
			}
			
			// Sort changes by start line (descending) so we can apply them in reverse order
			this.changes.sort((a, b) => {
				if (a.start < b.start) return 1;
				if (a.start > b.start) return -1;
				return 0;
			});
			
			// Apply edits using buffer's efficient apply_edits method
			// This will use GTK buffer operations for GtkSourceFileBuffer
			// or in-memory lines array for DummyFileBuffer
			yield file.buffer.apply_edits(this.changes);
		}
		
		/**
		 * Gets line count from buffer, handling errors gracefully.
		 * Returns 0 if counting fails (non-fatal error).
		 * 
		 * @param file The file to count lines for, or null
		 * @return Line count, or 0 if unavailable
		 */
		private async int get_line_count_from_buffer(OLLMfiles.File? file)
		{
			if (file == null) {
				return 0;
			}
			
			try {
				// Ensure buffer is loaded (should already be after write/apply_edits)
				if (!file.buffer.is_loaded) {
					yield file.buffer.read_async();
				}
				// Use buffer's built-in get_line_count() method
				return file.buffer.get_line_count();
			} catch (Error e) {
				GLib.warning("Error counting lines in %s: %s", this.normalized_path, e.message);
				return 0;
			}
		}
		
		/**
		 * Creates a new file with all changes applied.
		 * Uses buffer-based writing for automatic backups and proper file handling.
		 */
		private async void create_new_file_with_changes(OLLMfiles.File file) throws Error
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
			
			// Get replacement content (should be the full file content for complete_file mode)
			var replacement_content = this.changes[0].replacement;
			
			// Write to buffer - this handles:
			// - Creating the file if it doesn't exist
			// - Overwriting if it exists (buffer.write() always overwrites)
			// - Creating backups for project files (automatic)
			// - Updating file metadata
			yield file.buffer.write(replacement_content);
			
			// If this is a fake file (id = -1), convert it to a real file if within project
			if (file.id == -1) {
				yield this.deal_with_new_file(file);
			}
		}
		
		/**
		 * Converts a fake file (id = -1) to a real File object if it's within the active project.
		 * 
		 * This method:
		 * - Checks if the file is within the active project
		 * - Finds or creates parent folder objects in the project tree
		 * - Queries file info from disk
		 * - Converts the fake file to a real File object
		 * - Saves the file to the database
		 * - Updates the ProjectFiles list
		 * - Emits the new_file_added signal
		 * 
		 * @param file The fake file to convert (must have id = -1)
		 */
		private async void deal_with_new_file(OLLMfiles.File file) throws Error
		{
			var project_manager = ((EditMode) this.tool).project_manager;
			var active_project = project_manager.active_project;
			
			// Early return if file is outside active project
			if (active_project == null || !this.normalized_path.has_prefix(active_project.path)) {
				// File is outside project - keep as fake file (id = -1)
				return;
			}
			
			// File is within project and has id = -1 (fake file)
			// Get parent directory path
			var parent_dir_path = GLib.Path.get_dirname(this.normalized_path);
			
			// Find or create parent folder objects in project tree
			var parent_folder = yield this.find_or_create_parent_folder(active_project, parent_dir_path);
			if (parent_folder == null) {
				GLib.warning("RequestEditMode.deal_with_new_file: Could not find or create parent folder for %s", this.normalized_path);
				return;
			}
			
			// Query file info from disk
			var gfile = GLib.File.new_for_path(this.normalized_path);
			if (!gfile.query_exists()) {
				GLib.warning("RequestEditMode.deal_with_new_file: File does not exist on disk: %s", this.normalized_path);
				return;
			}
			
			GLib.FileInfo file_info;
			try {
				file_info = gfile.query_info(
					GLib.FileAttribute.STANDARD_CONTENT_TYPE + "," + GLib.FileAttribute.TIME_MODIFIED,
					GLib.FileQueryInfoFlags.NONE,
					null
				);
			} catch (GLib.Error e) {
				GLib.warning("RequestEditMode.deal_with_new_file: Could not query file info for %s: %s", this.normalized_path, e.message);
				return;
			}
			
			// Convert fake file to real File object
			// Create new File (not new_fake)
			var real_file = new OLLMfiles.File(project_manager);
			real_file.path = this.normalized_path;
			real_file.parent = parent_folder;
			real_file.parent_id = parent_folder.id;
			real_file.id = 0; // New file, will be inserted on save
			
			// Set properties from FileInfo
			var content_type = file_info.get_content_type();
			real_file.is_text = content_type != null && content_type != "" && content_type.has_prefix("text/");
			
			var mod_time = file_info.get_modification_date_time();
			if (mod_time != null) {
				real_file.last_modified = mod_time.to_unix();
			}
			
			// Detect language from filename using buffer provider
			var detected_language = project_manager.buffer_provider.detect_language(real_file);
			if (detected_language != null && detected_language != "") {
				real_file.language = detected_language;
			}
			
			// Add file to parent folder's children
			parent_folder.children.append(real_file);
			
			// Add file to project_manager.file_cache
			project_manager.file_cache.set(real_file.path, real_file);
			
			// Replace buffer's file reference by recreating buffer with new file object
			// The old buffer was associated with the fake file, so we need to create a new one
			project_manager.buffer_provider.create_buffer(real_file);
			
			// Copy buffer content from old file to new file if old buffer was loaded
			if (file.buffer != null && file.buffer.is_loaded) {
				var content = file.buffer.get_text();
				if (content != null && content != "") {
					yield real_file.buffer.write(content);
				}
			}
			
			// Save file to DB (gets id > 0)
			if (project_manager.db != null) {
				real_file.saveToDB(project_manager.db, null, false);
			}
			
			// Update ProjectFiles list
			active_project.project_files.update_from(active_project);
			
			// Manually emit new_file_added signal
			active_project.project_files.new_file_added(real_file);
		}
		
		/**
		 * Finds or creates a folder by walking down the path from the project root.
		 * 
		 * @param project_root The project root folder
		 * @param folder_path The full path to the folder to find or create
		 * @return The Folder object, or null if path is outside project
		 */
		private async OLLMfiles.Folder? find_or_create_parent_folder(OLLMfiles.Folder project_root, string folder_path) throws Error
		{
			// If folder_path is the project root, return it
			if (folder_path == project_root.path) {
				return project_root;
			}
			
			// Check if folder_path is within project
			if (!folder_path.has_prefix(project_root.path)) {
				return null;
			}
			
			// Get relative path from project root
			var relative_path = folder_path.substring(project_root.path.length);
			if (relative_path.has_prefix("/")) {
				relative_path = relative_path.substring(1);
			}
			if (relative_path == "") {
				return project_root;
			}
			
			// Split path into components
			var components = relative_path.split("/");
			
			// Walk down the path, finding or creating folders
			var current_folder = project_root;
			var current_path = project_root.path;
			
			foreach (var component in components) {
				if (component == "") {
					continue;
				}
				
				current_path = GLib.Path.build_filename(current_path, component);
				
				// Check if folder exists in children
				OLLMfiles.Folder? child_folder = null;
				if (current_folder.children.child_map.has_key(component)) {
					var child = current_folder.children.child_map.get(component);
					if (child is OLLMfiles.Folder) {
						child_folder = child as OLLMfiles.Folder;
					}
				}
				
				// If folder doesn't exist, create it
				if (child_folder == null) {
					// Query folder info from disk
					var gfile = GLib.File.new_for_path(current_path);
					if (!gfile.query_exists()) {
						GLib.warning("RequestEditMode.find_or_create_parent_folder: Folder does not exist on disk: %s", current_path);
						return null;
					}
					
					GLib.FileInfo folder_info;
					try {
						folder_info = gfile.query_info(
							GLib.FileAttribute.TIME_MODIFIED,
							GLib.FileQueryInfoFlags.NONE,
							null
						);
					} catch (GLib.Error e) {
						GLib.warning("RequestEditMode.find_or_create_parent_folder: Could not query folder info for %s: %s", current_path, e.message);
						return null;
					}
					
					// Create new folder
					child_folder = new OLLMfiles.Folder.new_from_info(
						project_root.manager,
						current_folder,
						folder_info,
						current_path
					);
					
					// Add to parent's children
					current_folder.children.append(child_folder);
					
					// Add to file_cache
					project_root.manager.file_cache.set(child_folder.path, child_folder);
					
					// Save to DB
					if (project_root.manager.db != null) {
						child_folder.saveToDB(project_root.manager.db, null, false);
					}
				}
				
				current_folder = child_folder;
			}
			
			return current_folder;
		}
	}
}
