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
			if (((EditMode) this.tool).project_manager?.get_file_from_active_project(this.normalized_path) != null) {
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
			
			// Get project manager and file status for UI message
			var project_manager = ((EditMode) this.tool).project_manager;
			var is_in_project = project_manager?.get_file_from_active_project(this.normalized_path) != null;
			var file_exists = GLib.FileUtils.test(this.normalized_path, GLib.FileTest.IS_REGULAR);
			
			// Build UI message - just the request info and permission status
			string ui_message = "Edit mode activated for file: " + this.normalized_path + "\n";
			ui_message += "File status: " + (file_exists ? "exists" : "will be created") + "\n";
			ui_message += "Project file: " + (is_in_project ? "yes (auto-approved)" : "no (permission required)");
			
			// Send to UI using standardized format
			this.send_ui("txt", "Edit Mode Activated", ui_message);
			
			// Build LLM message - tell LLM edit mode is activated and provide instructions
			string llm_message = "Edit mode activated for file: " + this.normalized_path + "\n\n";
			
			string instructions;
			if (this.complete_file) {
				instructions = "Since complete_file=true is enabled, code blocks should only have the language tag (e.g., ```javascript, ```python). Do not include line numbers. The entire file content will be replaced.";
			} else {
				instructions = "Code blocks must include line range in format type:startline:endline (e.g., ```javascript:10:15, ```python:1:5). The range is inclusive of the start line and exclusive of the end line. Line numbers are 1-based.";
			}
			
			llm_message += instructions;
			if (this.overwrite && file_exists) {
				llm_message += "\n\nYou set overwrite=true, so we will overwrite the existing file when you complete your message.";
			}
			
			// Clean up any existing active request for the same file before starting a new one
			// This handles the case where edit mode is called again after a failed attempt
			var existing_requests = new Gee.ArrayList<RequestEditMode>();
			foreach (var req in active_requests) {
				if (req.normalized_path == this.normalized_path && req != this) {
					existing_requests.add(req);
				}
			}
			foreach (var req in existing_requests) {
				GLib.debug("RequestEditMode.execute_request: Cleaning up existing request for file %s", req.normalized_path);
				req.disconnect_signals();
				active_requests.remove(req);
			}
			
			// Keep this request alive so signal handlers can be called
			active_requests.add(this);
			GLib.debug("RequestEditMode.execute_request: Added request to active_requests (total=%zu, file=%s)", 
				active_requests.size, this.normalized_path);
			
			// Connect signals for this request
			this.connect_signals();
			
			return llm_message;
		}
		
		/**
		 * Connects client signals to this request's handlers.
		 * Called when edit mode is activated for this request.
		 */
		public void connect_signals()
		{
			GLib.debug("RequestEditMode.connect_signals: Connecting signals for file %s (tool.active=%s)", 
				this.normalized_path, this.tool.active.to_string());
			
			// Connect to stream_chunk signal to capture code blocks as they stream in
			// Replaces stream_content signal - use is_thinking check to filter out thinking content
			// Tools access Client via tool.client (BaseTool has client property)
			if (this.chat_call.stream && this.tool.client != null) {
				this.stream_content_id = this.tool.client.stream_chunk.connect((new_text, is_thinking, response) => {
					// Only process non-thinking content (replaces stream_content signal)
					if (is_thinking) {
						return;
					}
					// Check if this request is still valid before processing
					if (this.chat_call == null || this.tool.client == null) {
						return;
					}
					// Only process if this response belongs to our chat_call
					if (response.call != this.chat_call) {
						return;
					}
					this.process_streaming_content(new_text);
				});
			}
			
			// TODO: message_created connection removed per Phase 1.2
			// Need to replace with direct calls from message creation code
			// For now, RequestEditMode won't detect when messages are done
			// this.message_created_id = this.chat_call.client.message_created.connect((message, content_interface) => {
			// 	// Check if this request is still valid before processing
			// 	if (this.chat_call == null || this.chat_call.client == null) {
			// 		GLib.debug("RequestEditMode: message_created handler called but chat_call/client is null (file=%s)", 
			// 			this.normalized_path);
			// 		return;
			// 	}
			// 	// Only process if this message belongs to our chat_call
			// 	if (message.message_interface != this.chat_call) {
			// 		GLib.debug("RequestEditMode: message_created handler called for different chat_call, skipping (file=%s, message_interface=%p, our_chat_call=%p)", 
			// 			this.normalized_path, message.message_interface, this.chat_call);
			// 		return;
			// 	}
			// 	this.on_message_created.begin(message, content_interface);
			// });
			// GLib.debug("RequestEditMode.connect_signals: Connected message_created signal (id=%lu)", this.message_created_id);
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
			if (this.chat_call == null || this.tool.client == null) {
				return;
			}
			
			// Disconnect stream_chunk signal (replaces stream_content)
			if (this.stream_content_id != 0 && GLib.SignalHandler.is_connected(this.tool.client, this.stream_content_id)) {
				this.tool.client.disconnect(this.stream_content_id);
			}
			this.stream_content_id = 0;
			
			// Disconnect message_created signal
			if (this.message_created_id != 0 && GLib.SignalHandler.is_connected(this.tool.client, this.message_created_id)) {
				this.tool.client.disconnect(this.message_created_id);
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
			if (this.chat_call == null) {
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
			if (this.chat_call == null) {
				GLib.debug("RequestEditMode.on_message_created: chat_call is null, skipping (file=%s)", 
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
			
			GLib.debug("RequestEditMode.on_message_created: Processing done message (file=%s, changes_count=%zu)", 
				this.normalized_path, this.changes.size);
			
			// If not streaming, process the full content at once
			// If streaming, we should have already captured everything via stream_content
			// Phase 3: stream is on Chat, not Client
			if (!this.chat_call.stream && response.message != null && response.message.content != "") {
				var parts = response.message.content.split("\n");
				for (int i = 0; i < parts.length; i++) {
					this.add_text(parts[i]);
					this.add_linebreak();
				}
			}
			
			// Process any remaining current_line (for both streaming and non-streaming)
			this.add_linebreak();
			
			// Check if we have any changes - if not, just clean up silently
			// This allows the LLM to call edit mode again without getting a confusing error message
			if (this.changes.size == 0) {
				// No changes were captured - clean up silently
				GLib.debug("RequestEditMode.on_message_created: No changes captured (file=%s, in_code_block=%s, current_block_size=%zu), cleaning up silently", 
					this.normalized_path, this.in_code_block.to_string(), this.current_block.length);
				this.disconnect_signals();
				active_requests.remove(this);
				GLib.debug("RequestEditMode.on_message_created: Removed request from active_requests (remaining=%zu, file=%s)", 
					active_requests.size, this.normalized_path);
				// Don't send any reply - just let the LLM try again naturally
				return;
			}
			
			GLib.debug("RequestEditMode.on_message_created: Found %zu changes, applying to file %s", 
				this.changes.size, this.normalized_path);
			
			// Apply changes
			int line_count = 0;
			try {
				yield this.apply_all_changes();
				
				// Calculate line count for success message
				try {
					line_count = this.count_file_lines();
				} catch (Error e) {
					GLib.warning("Error counting lines in %s: %s", this.normalized_path, e.message);
				}
				
				// Build and emit UI message with more detail
				string update_message = "File updated: " + this.normalized_path + "\n";
				if (line_count > 0) {
					update_message += "Total lines: " + line_count.to_string() + "\n";
				}
				update_message += "Changes applied: " + this.changes.size.to_string() + "\n";
				var project_manager = ((EditMode) this.tool).project_manager;
				var is_in_project = project_manager?.get_file_from_active_project(this.normalized_path) != null;
				update_message += "Project file: " + (is_in_project ? "yes" : "no");
				this.send_ui("txt", "File Updated", update_message);
				
				// Send tool reply to LLM
				this.reply_with_errors(
					response,
					(line_count > 0)
						? "File '" + this.normalized_path + 
							"' has been updated. It now has " + 
							line_count.to_string() + " lines."
						: "File '" + this.normalized_path + "' has been updated."
				);
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
		private async void apply_all_changes() throws Error
		{
			if (this.changes.size == 0) {
				return;
			}
		
			// Get or create File object from path
			var project_manager = ((EditMode) this.tool).project_manager;
			if (project_manager == null) {
				throw new GLib.IOError.FAILED("ProjectManager is not available");
			}
			
			// First, try to get from active project
			var file = project_manager.get_file_from_active_project(this.normalized_path);
			var is_in_project = (file != null);
			
			// Only check permission if file is NOT in active project
			// Files in active project are auto-approved and don't need permission checks
			if (!is_in_project) {
				// Check if permission status has changed (e.g., revoked by signal handler)
				// Phase 3: permission_provider is on Chat, not Client
				if (this.chat_call.permission_provider == null || !this.chat_call.permission_provider.check_permission(this)) {
					throw new GLib.IOError.PERMISSION_DENIED("Permission denied or revoked");
				}
			}
			
			// Log and notify that we're starting to write with more detail
			GLib.debug("Starting to apply changes to file %s (in_project=%s, changes=%zu)", 
				this.normalized_path, is_in_project.to_string(), this.changes.size);
			
			string apply_message = "Applying changes to file: " + this.normalized_path + "\n";
			apply_message += "Changes to apply: " + this.changes.size.to_string() + "\n";
			apply_message += "Project file: " + (is_in_project ? "yes" : "no") + "\n";
			if (this.complete_file) {
				apply_message += "Mode: Complete file replacement";
			} else {
				apply_message += "Mode: Line range edits";
			}
			this.send_ui("txt", "Applying Changes", apply_message);
			
			if (file == null) {
				file = new OLLMfiles.File.new_fake(project_manager, this.normalized_path);
			}
			
			// Ensure buffer exists (create if needed)
			file.manager.buffer_provider.create_buffer(file);
			
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
				yield this.create_new_file_with_changes(file);
			} else {
				// Normal mode: file must exist
				if (!file_exists) {
					throw new GLib.IOError.NOT_FOUND("File does not exist: " + this.normalized_path + ". Use complete_file=true to create a new file.");
				}
				// Apply edits to existing file
				yield this.apply_edits(file);
			}
			
			// Log and send status message after successful write with more detail
			GLib.debug("RequestEditMode.apply_all_changes: Successfully applied changes to file %s", this.normalized_path);
			
			string success_message = "Successfully applied changes to file: " + this.normalized_path + "\n";
			success_message += "Changes applied: " + this.changes.size.to_string() + "\n";
			success_message += "Project file: " + (is_in_project ? "yes" : "no") + "\n";
			if (this.complete_file) {
				success_message += "Mode: Complete file replacement";
			} else {
				success_message += "Mode: Line range edits";
			}
			this.send_ui("txt", "Changes Applied", success_message);
			
			// Emit change_done signal for each change
			var edit_tool = (EditMode) this.tool;
			foreach (var change in this.changes) {
				edit_tool.change_done(this.normalized_path, change);
			}
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
		 * Creates a new file with all changes applied.
		 */
		private async void create_new_file_with_changes(OLLMfiles.File file) throws Error
		{
			// Write replacement content using buffer (handles backup and directory creation automatically)
			yield file.buffer.write(this.changes[0].replacement);
		}
		
		/**
		 * Counts the total number of lines in a file using buffer.
		 */
		private int count_file_lines() throws Error
		{
			// Get or create File object from path
			var project_manager = ((EditMode) this.tool).project_manager;
			if (project_manager == null) {
				throw new GLib.IOError.FAILED("ProjectManager is not available");
			}
			
			// First, try to get from active project
			var file = project_manager.get_file_from_active_project(this.normalized_path);
			
			if (file == null) {
				file = new OLLMfiles.File.new_fake(project_manager, this.normalized_path);
			}
			
			// Ensure buffer exists (create if needed)
			file.manager.buffer_provider.create_buffer(file);
			
			// Use buffer-based line counting (will load file synchronously if needed)
			return file.buffer.get_line_count();
		}
	}
}
