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

namespace OLLMtools.EditMode
{
	/**
	 * Request handler for editing files by activating "edit mode" for a file.
	 */
	public class Request : OLLMchat.Tool.RequestBase
	{
		// Message constants
		private const string INSTRUCTIONS_COMPLETE_FILE = """
Since complete_file=true is enabled, code blocks should only have the language tag e.g.,

```javascript
the output goes here
```

 Do not include line numbers. The entire file content will be replaced.
""";

		private const string INSTRUCTIONS_LINE_RANGE = """
Code blocks must include line range in format type:startline:endline e.g.,

```javascript:10:15
the output goes here
```

The range is inclusive of the start line and exclusive of the end line. Line numbers are 1-based.
""";

		private const string OVERWRITE_MESSAGE = """
You set overwrite=true, so we will overwrite the existing file when you complete your message.
""";

		private const string CODE_BLOCK_REQUIREMENT = """
Now provide markdown code block with content. You MUST include a starting markdown tag and an ending one. For example:

```
content to write
```

Don't forget to close it.
""";

		private const string ERROR_APPLYING_CHANGES = "There was a problem applying the changes: ";


		// Static list to keep active requests alive so signal handlers can be called
		private static Gee.ArrayList<Request> active_requests = new Gee.ArrayList<Request>();
		
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
		 * files with relative paths. This override ensures relative paths are
		 * normalized using the active project path, which will then get auto-approved.
		 */
		protected override string normalize_file_path(string in_path)
		{
			// Check if we have an active project first
			var project_manager = ((Tool) this.tool).project_manager;
			if (project_manager != null && project_manager.active_project != null) {
				// If path is relative, normalize it using the project path directly
				// This ensures project files get auto-approved
				if (!GLib.Path.is_absolute(in_path)) {
					return GLib.Path.build_filename(project_manager.active_project.path, in_path);
				}
			}
			
			// For absolute paths or when no project is available, use base normalization
			return base.normalize_file_path(in_path);
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
			
			var project_manager = ((Tool) this.tool).project_manager;
			
			// Check if file is in active project (skip permission prompt if so)
			if (project_manager.get_file_from_active_project(this.normalized_path) != null) {
				// File is in active project - skip permission prompt
				// Clear permission question to indicate auto-approved
				this.permission_question = "";
				// Return false to skip permission check (auto-approved for project files)
				return false;
			}
			
		// Check if file path is within project folder (even if file doesn't exist yet)
		// This allows new files inside the project folder to be created without permission checks
		if (project_manager.active_project != null) {
			var dir_path = GLib.Path.get_dirname(this.normalized_path);
			// Check if the directory containing the file is in the project's folder_map
			if (project_manager.active_project.project_files.folder_map.has_key(dir_path) == true) {
				// File is within project folder - skip permission prompt
				this.permission_question = "";
				return false;
			}
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
			var project_manager = ((Tool) this.tool).project_manager;
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
			
			string instructions = this.complete_file ? INSTRUCTIONS_COMPLETE_FILE : INSTRUCTIONS_LINE_RANGE;
			llm_message += instructions;
			
			if (this.overwrite && file_exists) {
				llm_message += "\n" + OVERWRITE_MESSAGE;
			}
			
			llm_message += "\n" + CODE_BLOCK_REQUIREMENT;
			
			// Clean up any existing active request for the same file before starting a new one
			// This handles the case where edit mode is called again after a failed attempt
			var existing_requests = new Gee.ArrayList<Request>();
			foreach (var req in active_requests) {
				if (req.normalized_path == this.normalized_path && req != this) {
					existing_requests.add(req);
				}
			}
			foreach (var req in existing_requests) {
				GLib.debug("Request.execute_request: Cleaning up existing request for file %s", req.normalized_path);
				// Unregister from agent if registered
				
				req.agent.unregister_tool(req.request_id);
				
				active_requests.remove(req);
			}
			
			// Keep this request alive so signal handlers can be called
			active_requests.add(this);
			GLib.debug("Request.execute_request: Added request to active_requests (total=%zu, file=%s)", 
				active_requests.size, this.normalized_path);
			
			// Signal connections are now handled automatically via agent.register_tool_monitoring()
			// which is called in Tool.execute() when the request is created.
			
			return llm_message;
		}
		
		/**
		 * Override on_stream_chunk callback to process streaming content.
		 * Called by agent when streaming chunks arrive.
		 */
		public override void on_stream_chunk(string new_text, bool is_thinking, OLLMchat.Response.Chat response)
		{
			// Only process non-thinking content (actual code blocks)
			if (is_thinking || new_text.length == 0) {
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
		 * Override on_message_completed callback to process completed messages.
		 * Called by agent when message is done.
		 */
		public override void on_message_completed(OLLMchat.Response.Chat response)
		{
			GLib.debug("Request.on_message_completed: Received response (file=%s, response.done=%s, message.role=%s, tool_active=%s)", 
				this.normalized_path, response.done.to_string(), 
				response.message != null ? response.message.role : "null", this.tool.active.to_string());
			
			// Check if response is actually done
			if (!response.done) {
				GLib.debug("Request.on_message_completed: Response is not done, skipping (response.done=%s)", response.done.to_string());
				return;
			}
		
		// Get Response.Chat from agent.chat().streaming_response
		if (this.agent == null) {
			GLib.debug("Request.on_message_completed: agent is null (file=%s)", this.normalized_path);
			return;
		}
		this.agent.unregister_tool(this.request_id);

		
		GLib.debug("Request.on_message_completed: Processing done message (file=%s, changes_count=%zu)", 
		this.normalized_path, this.changes.size);
	
		// If not streaming, process the full content at once
		// If streaming, we should have already captured everything via stream_content
		// Phase 3: stream is on Chat, not Client
		if (!this.agent.chat().stream && response.message.content != "") {
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
				GLib.debug("Request.on_message_completed: No changes captured (file=%s, in_code_block=%s, current_block_size=%zu), cleaning up silently", 
					this.normalized_path, this.in_code_block.to_string(), this.current_block.length);
				// Already unregistered at the top of this method
				active_requests.remove(this);
				GLib.debug("Request.on_message_completed: Removed request from active_requests (remaining=%zu, file=%s)", 
					active_requests.size, this.normalized_path);
				// Don't send any reply - just let the LLM try again naturally
				return;
			}
			
			GLib.debug("Request.on_message_completed: Found %zu changes, applying to file %s", 
				this.changes.size, this.normalized_path);
			
			// Apply changes
			this.apply_all_changes.begin((obj, res) => {
				this.handle_apply_changes_response(res, response);
			});
		}
		
		private void handle_apply_changes_response(GLib.AsyncResult res, OLLMchat.Response.Chat response)
		{
			int line_count = 0;
			
			try {
				this.apply_all_changes.end(res);
				
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
				var project_manager = ((Tool) this.tool).project_manager;
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
				this.error_messages.add(ERROR_APPLYING_CHANGES + e.message);
				this.reply_with_errors(response);
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
			var tag = stripped_line.substring(3).strip();
			GLib.debug("Parsing code block opener (file=%s, tag='%s', complete_file=%s)", 
				this.normalized_path, tag, this.complete_file.to_string());
			
			if (this.complete_file && !tag.contains(":")) {
				GLib.debug("Complete file mode - accepting language-only tag '%s'", tag);
				this.enter_code_block(-1, -1);
				return true;
			}
			
			if (!tag.contains(":")) {
				this.enter_code_block(-1, -1);
				return true;
			}
			
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
			
			this.enter_code_block(start_line, end_line);
			return true;
		}
		
		/**
		 * Enters code block state with given line numbers.
		 */
		private void enter_code_block(int start_line, int end_line)
		{
			this.current_start_line = start_line;
			this.current_end_line = end_line;
			this.in_code_block = true;
			this.current_line = "";
			this.current_block = "";
		}
		
		/**
		 * Processes line break: checks current_line for code block markers,
		 * updates state, and clears current_line.
		 */
		private void add_linebreak()
		{
			if (!this.in_code_block && this.current_line.has_prefix("```")) {
				if (this.try_parse_code_block_opener(this.current_line)) {
					return;
				}
			}
			
			if (this.current_line == "```") {
				if (!this.in_code_block) {
					this.enter_code_block(-1, -1);
					return;
				}
				
				if (this.current_block.has_suffix("```\n")) {
					this.current_block = this.current_block.substring(0, this.current_block.length - 4);
				} else if (this.current_block.has_suffix("```")) {
					this.current_block = this.current_block.substring(0, this.current_block.length - 3);
				}
				
				GLib.debug("Captured code block (file=%s, start=%d, end=%d, size=%zu bytes)", 
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
			
			if (this.in_code_block) {
				this.current_block += "\n";
			}
			
			this.current_line = "";
		}
		
		/**
		 * Sends a message to continue the conversation and disconnects signals.
		 * This method should be called on both success and error paths to ensure signals are always disconnected.
		 * Uses agent.chat().send_append() to continue the conversation with the LLM's response.
		 */
		private void reply_with_errors(OLLMchat.Response.Chat response, string message = "")
		{
			// Check if agent is available before proceeding
			if (this.agent == null) {
				GLib.debug("Request.reply_with_errors: agent is null (file=%s)", this.normalized_path);
				return;
			}
			
			// Unregister from agent - we're done processing new content
			this.agent.unregister_tool(this.request_id);
			
			// Get chat reference after unregistering (agent reference remains valid)
			var chat = this.agent.chat();
			
			// Build reply: errors first (if any), then message
			string reply_text = (this.error_messages.size > 0 
				? string.joinv("\n", this.error_messages.to_array()) + (message != "" ? "\n" : "") 
				: "") + message;
			
			// Schedule send_append() to run on idle to avoid race condition:
			// The previous response's final chunk (done=true) may still be processing in the event loop,
			// which sets is_streaming_active=false. If we call send_append() immediately, it sets is_streaming_active=true,
			// but then the final chunk processing overwrites it back to false. By deferring to idle, we ensure
			// the final chunk processing completes first, then send_append() sets is_streaming_active=true before
			// the continuation response starts streaming.
			GLib.Idle.add(() => {
				// Build messages array: previous assistant response + new user message
				var messages_to_send = new Gee.ArrayList<OLLMchat.Message>();
				
				// Add the assistant's response from the previous call
				messages_to_send.add(response.message);
				
				// Add the new user message
				messages_to_send.add(new OLLMchat.Message("user", reply_text));
				
				// Append messages and send (using captured chat reference)
				chat.send_append.begin(
					messages_to_send,
					null,
					(obj, res) => {
						// Remove from active requests after send completes
						active_requests.remove(this);
						GLib.debug("Request.reply_with_errors: Removed request from active_requests (remaining=%zu, file=%s)", 
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
		
			var project_manager = ((Tool) this.tool).project_manager;
			if (project_manager == null) {
				throw new GLib.IOError.FAILED("ProjectManager is not available");
			}
			
			var file = project_manager.get_file_from_active_project(this.normalized_path);
			var is_in_project = (file != null);
			
			if (!is_in_project && project_manager.active_project != null) {
				var dir_path = GLib.Path.get_dirname(this.normalized_path);
				if (project_manager.active_project.project_files.folder_map.has_key(dir_path)) {
					is_in_project = true;
				}
			}
			
			if (!is_in_project && !this.agent.get_permission_provider().check_permission(this)) {
				throw new GLib.IOError.PERMISSION_DENIED("Permission denied or revoked");
			}
			
			this.send_apply_ui_message(is_in_project);
			
			if (file == null) {
				file = new OLLMfiles.File.new_fake(project_manager, this.normalized_path);
			}
			file.manager.buffer_provider.create_buffer(file);
			
			var file_exists = GLib.FileUtils.test(this.normalized_path, GLib.FileTest.IS_REGULAR);
			var change_type = file_exists ? "modified" : "added";
			
			if (change_type == "modified") {
				yield this.create_file_history(project_manager, file, change_type);
			}
			
			this.validate_changes(file_exists);
			if (this.complete_file) {
				yield this.create_new_file_with_changes(file);
			} else {
				yield this.apply_edits(file);
			}
			
			this.send_success_ui_message(is_in_project);
			
			if (change_type == "added" && file.id <= 0 && is_in_project) {
				file = yield this.convert_new_file_to_real(project_manager, file);
				if (file != null) {
					is_in_project = true;
					project_manager.active_project.project_files.update_from(project_manager.active_project);
					yield this.create_file_history(project_manager, file, change_type);
				}
			}
			
			file.is_need_approval = true;
			file.last_change_type = change_type;
			file.last_modified = new GLib.DateTime.now_local().to_unix();
			
			if (is_in_project || file.id > 0) {
				file.saveToDB(project_manager.db, null, false);
			}
			
			if (is_in_project) {
				project_manager.active_project.project_files.review_files.refresh();
			}
			this.emit_change_signals();
			
			if (project_manager.db != null) {
				project_manager.db.backupDB();
			}
		}
		
		/**
		 * Creates FileHistory entry for the change.
		 */
		private async void create_file_history(
			OLLMfiles.ProjectManager project_manager,
			OLLMfiles.File file,
			string change_type) throws Error
		{
			if (project_manager.db == null) {
				return;
			}
			
			try {
				var file_history = new OLLMfiles.FileHistory(
					project_manager.db,
					file,
					change_type,
					new GLib.DateTime.now_local()
				);
				yield file_history.commit();
			} catch (GLib.Error e) {
				GLib.warning("Cannot create FileHistory for edit (%s): %s", this.normalized_path, e.message);
			}
		}
		
		/**
		 * Validates changes based on mode and file existence.
		 */
		private void validate_changes(bool file_exists) throws Error
		{
			if (!this.complete_file) {
				if (!file_exists) {
					throw new GLib.IOError.NOT_FOUND(
						"File does not exist: " + this.normalized_path + ". Use complete_file=true to create a new file.");
				}
				return;
			}
			
			if (this.changes.size > 1) {
				throw new GLib.IOError.INVALID_ARGUMENT(
					"Cannot create/overwrite file: multiple changes detected. Complete file mode only allows a single code block.");
			}
			
			if (this.changes[0].start != -1 || this.changes[0].end != -1) {
				throw new GLib.IOError.INVALID_ARGUMENT(
					"Cannot use line numbers in complete_file mode. When complete_file=true, code blocks should only have the language tag (e.g., ```python, not ```python:1:1).");
			}
			
			if (file_exists && !this.overwrite) {
				throw new GLib.IOError.EXISTS(
					"File already exists: " + this.normalized_path + ". Use overwrite=true to overwrite it.");
			}
		}
		
		/**
		 * Converts a fake file to a real file.
		 */
		private async OLLMfiles.File? convert_new_file_to_real(
			OLLMfiles.ProjectManager project_manager,
			OLLMfiles.File file) throws Error
		{
			try {
				yield project_manager.convert_fake_file_to_real(file, this.normalized_path);
				return project_manager.get_file_from_active_project(this.normalized_path);
			} catch (GLib.Error e) {
				GLib.warning("Cannot convert fake file to real (%s): %s", this.normalized_path, e.message);
				return null;
			}
		}
		
		/**
		 * Sends UI message about applying changes.
		 */
		private void send_apply_ui_message(bool is_in_project)
		{
			GLib.debug("Starting to apply changes to file %s (in_project=%s, changes=%zu)", 
				this.normalized_path, is_in_project.to_string(), this.changes.size);
			
			var mode_text = this.complete_file ? "Complete file replacement" : "Line range edits";
			var apply_message = "Applying changes to file: " + this.normalized_path + "\n" +
				"Changes to apply: " + this.changes.size.to_string() + "\n" +
				"Project file: " + (is_in_project ? "yes" : "no") + "\n" +
				"Mode: " + mode_text;
			this.send_ui("txt", "Applying Changes", apply_message);
		}
		
		/**
		 * Sends UI message about successful changes.
		 */
		private void send_success_ui_message(bool is_in_project)
		{
			GLib.debug("Successfully applied changes to file %s", this.normalized_path);
			
			var mode_text = this.complete_file ? "Complete file replacement" : "Line range edits";
			var success_message = "Successfully applied changes to file: " + this.normalized_path + "\n" +
				"Changes applied: " + this.changes.size.to_string() + "\n" +
				"Project file: " + (is_in_project ? "yes" : "no") + "\n" +
				"Mode: " + mode_text;
			this.send_ui("txt", "Changes Applied", success_message);
		}
		
		/**
		 * Emits change_done signals for each change.
		 */
		private void emit_change_signals()
		{
			var edit_tool = (Tool) this.tool;
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
			var project_manager = ((Tool) this.tool).project_manager;
			if (project_manager == null) {
				throw new GLib.IOError.FAILED("ProjectManager is not available");
			}
			
			var file = project_manager.get_file_from_active_project(this.normalized_path);
			if (file == null) {
				file = new OLLMfiles.File.new_fake(project_manager, this.normalized_path);
			}
			
			file.manager.buffer_provider.create_buffer(file);
			return file.buffer.get_line_count();
		}
	}
}
