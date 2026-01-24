/*
 * Streaming content processor for EditMode.
 *
 * Phase 1: Introduce Stream class and FileChange extensions.
 * Request integration and migration of streaming logic will be done
 * in later phases as described in the 2.1.6 plan.
 */

namespace OLLMtools.EditMode
{
	/**
	 * Handles streaming content parsing for EditMode.
	 * 
	 * Request will construct this class and delegate streaming-related
	 * responsibilities in a later phase. For Phase 1, this class
	 * provides the full interface and internal state, ready to be wired.
	 */
	public class Stream : GLib.Object
	{
		// Parent Request reference (for UI messages)
		private OLLMtools.EditMode.Request request;
		
		// File for AST path resolution
		private OLLMfiles.File file;
		
		
		// Streaming state
		private string current_line = "";
		private OLLMfiles.FileChange? current_change = null;
		
		// Captured changes and non-change errors
		public Gee.ArrayList<OLLMfiles.FileChange> changes { 
			get; private set; default = new Gee.ArrayList<OLLMfiles.FileChange>(); }
		public Gee.ArrayList<string> error_messages { 
			get; private set; default = new Gee.ArrayList<string>(); }
		
		// Indicates whether any changes have been captured
		public bool has_changes { get; private set; default = false; }
		
		// Queue state for async change application
		private Gee.Queue<OLLMfiles.FileChange> pending_changes = new Gee.LinkedList<OLLMfiles.FileChange>();
		private bool processing_change = false;
		private bool history_created = false;
		
		
		public Stream(
			OLLMtools.EditMode.Request request,
			OLLMfiles.File file
		)
		{
			this.request = request;
			this.file = file;
		}

		
		/**
		 * Process a streaming chunk of content.
		 * 
		 * This mirrors Request.on_stream_chunk(), but without any direct
		 * dependency on Response.Chat. Integration will be handled
		 * by Request in a later phase.
		 */
		public void process_chunk(string new_text, bool is_thinking)
		{
			if (is_thinking || new_text.length == 0) {
				return;
			}
			
			if (!this.request.tool.active) {
				return;
			}
			
			if (!new_text.contains("\n")) {
				this.add_text(new_text);
				return;
			}
			
			var parts = new_text.split("\n");
			for (int i = 0; i < parts.length; i++) {
				this.add_text(parts[i]);
				if (i < parts.length - 1) {
					this.add_linebreak();
				}
			}
		}
		
		/**
		 * Process non-streaming content (fallback mode).
		 */
		public void process_complete_content(string content)
		{
			if (content == "") {
				return;
			}
			
			var parts = content.split("\n");
			for (int i = 0; i < parts.length; i++) {
				this.add_text(parts[i]);
				this.add_linebreak();
			}
		}
		
		//
		// Internal helpers (migrated from Request in later phase)
		//
		
		private void add_text(string text)
		{
			this.current_line += text;
			
			if (this.current_change != null) {
				this.current_change.replacement += text;
			}
		}

		private string describe_mode(string mode)
		{
			switch (mode) {
				case "line_numbers":
					return "line number";
				case "complete_file":
					return "complete file";
				default:
					return "AST path";
			}
		}

		private bool ensure_mode_allows(string detected_mode)
		{
			if (this.request.edit_mode == detected_mode) {
				return true;
			}
			
			var required_format = (this.request.edit_mode == "line_numbers")
					? "type:startline:endline"
				: (this.request.edit_mode == "complete_file"
						? "bare language tag"
						: "type:Namespace-Class-Method");
			var detected_text = (detected_mode == "line_numbers")
				? "Line number format specified but AST path mode is active."
				: (detected_mode == "ast_path"
					? "AST path format specified but line number mode is active."
					: "Format specified but complete file mode is active.");
			
			var message = detected_text + " Use format: `" + required_format + "` instead.";
			if (this.request.edit_mode == "complete_file") {
				message = "Complete file mode is active. Use a bare language tag (e.g., ```vala) without line numbers or AST path.";
			}
			
			this.current_line = "";
			this.current_change = new OLLMfiles.FileChange.with_error(this.file, message);
			
			return false;
		}
		
		private bool try_parse_code_block_opener(string stripped_line)
		{
			var tag = stripped_line.substring(3).strip();
			
			if (this.request.edit_mode == "complete_file" && this.changes.size > 0) {
				this.current_line = "";
				this.current_change = new OLLMfiles.FileChange.with_error(
					this.file,
					"Complete file mode allows only one code block. This block was ignored."
				);
				return true;
			}



			if (tag == "") {
				if (this.request.edit_mode != "complete_file") {
					this.current_line = "";
					this.current_change = new OLLMfiles.FileChange.with_error(
						this.file,
						"Unlabeled code block not allowed in " + this.describe_mode(this.request.edit_mode) + " mode. " +
						"Use `type:Namespace-Class-Method` or `type:startline:endline`."
					);
					return true;
				}
				this.current_line = "";
				this.current_change = new OLLMfiles.FileChange(this.file);
				return true;
			}
				
			if (this.request.edit_mode == "complete_file" && !tag.contains(":")) {
				// Allow bare language tag for complete file replacement.
				this.current_line = "";
				this.current_change = new OLLMfiles.FileChange(this.file);
				return true;
			}
			
			if (!tag.contains(":")) {
				this.current_line = "";
				this.current_change = new OLLMfiles.FileChange.with_error(
					this.file,
					"Bare language tags are only allowed in complete_file mode. " +
					"Use `type:Namespace-Class-Method` or `type:startline:endline`."
				);
				return true;
			}
			
			var parts = tag.split(":");
			if (parts.length < 2) {
				this.current_line = "";
				this.current_change = new OLLMfiles.FileChange.with_error(
					this.file,
					"Invalid code block format: expected format with ':' separator"
				);
				return true;
			}

			int start_line = -1;
			int end_line = -1;
			var is_line_range = false;
			try {
				var line_range_regex = new GLib.Regex(".*:(\\d+):(\\d+)$");
				GLib.MatchInfo match_info;
				if (line_range_regex.match(tag, 0, out match_info)) {
					is_line_range = true;
					int.try_parse(match_info.fetch(1), out start_line);
					int.try_parse(match_info.fetch(2), out end_line);
				}
			} catch (GLib.RegexError e) {
				is_line_range = false;
			}

			if (is_line_range) {
				if (!this.ensure_mode_allows("line_numbers")) {
					return true;
				}
				
				if (start_line < 1 || end_line < start_line) {
					this.current_line = "";
					this.current_change = new OLLMfiles.FileChange.with_error(
						this.file,
						"Invalid code block format: start line must be >= 1 and end line must be >= start line"
					);
					return true;
				}
				
				this.current_line = "";
				this.current_change = new OLLMfiles.FileChange(this.file) {
					start = start_line,
					end = end_line
				};
				return true;
			}
			
			if (!this.ensure_mode_allows("ast_path")) {
				return true;
			}
			
			var ast_path_parts = parts[1:parts.length];
			if (ast_path_parts.length == 0 || ast_path_parts[0] == "") {
				this.current_line = "";
				this.current_change = new OLLMfiles.FileChange.with_error(
					this.file,
					"Invalid code block format: AST path is missing"
				);
				return true;
			}
			var operation_type = OLLMfiles.OperationType.REPLACE;
			
			switch (ast_path_parts.length > 0 ? ast_path_parts[ast_path_parts.length - 1] : "") {
				case "before":
					operation_type = OLLMfiles.OperationType.BEFORE;
					ast_path_parts = ast_path_parts[0:ast_path_parts.length - 1];
					break;
				case "after":
					operation_type = OLLMfiles.OperationType.AFTER;
					ast_path_parts = ast_path_parts[0:ast_path_parts.length - 1];
					break;
				case "remove":
					operation_type = OLLMfiles.OperationType.DELETE;
					ast_path_parts = ast_path_parts[0:ast_path_parts.length - 1];
					break;
				default:
					break;
			}
			
			
			// For Phase 1, we enter a code block without resolved line numbers.
			// Resolution is done by FileChange.resolve_ast_path() which is
			// a placeholder for now and will be fully implemented in Phase 2.
			this.current_line = "";
			this.current_change = new OLLMfiles.FileChange(this.file) {
				operation_type = operation_type,
				ast_path = string.joinv("-", ast_path_parts)
			};
			return true;
		}
		
		public void add_linebreak()
		{
			if (this.current_change == null && this.current_line.has_prefix("```")) {
				if (this.try_parse_code_block_opener(this.current_line)) {
					return;
				}
			}
				
			if (this.current_line != "```") {
				if (this.current_change != null) {
					this.current_change.add_linebreak(false);
				}
				
				this.current_line = "";
				return;
			}
				
			if (this.current_change == null) {
				this.current_line = "";
				this.current_change = new OLLMfiles.FileChange(this.file);
				return;
			}
			
			// Check if there are format errors before closing
			if (this.current_change.has_error) {
				// Format error already set in try_parse_code_block_opener
				// Just add to changes and reset
				this.changes.add(this.current_change);
				this.has_changes = true;
				this.current_line = "";
				this.current_change = null;
				return;
			}
			
			this.current_change.add_linebreak(true);
			
			// Add change to changes array (for tracking)
			this.changes.add(this.current_change);
			this.has_changes = true;
			
			// Handle AST path changes vs line number changes differently
			if (this.current_change.ast_path != "") {
				// AST path change: add to queue for async processing
				this.pending_changes.offer(this.current_change);
				
				// Start processing queue if not already processing
				if (!this.processing_change) {
					this.process_next_change.begin();
				}
			}
			// Line number changes: do NOT add to queue
			// They will be processed serially after message completion
			
			this.current_line = "";
			this.current_change = null;
		}
		
		/**
		 * Process the next change in the queue.
		 * 
		 * This method processes AST-based changes asynchronously (but not concurrently).
		 * When a change completes, it processes the next queue item, or if the end message
		 * has been received and queue is empty, syncs metadata and sends the response.
		 */
		private async void process_next_change()
		{
			if (this.processing_change) {
				return; // Already processing
			}
			
			if (this.pending_changes.size == 0) {
				// Queue is empty - sync buffer to file and update metadata for AST changes
				// then send response if message is completed
				if (this.request.message_completed) {
					yield this.sync_and_update_metadata();
					this.send_response();
				}
				return;
			}
			
			this.processing_change = true;
			var change = this.pending_changes.poll();
			
			// Ensure file history is created on first edit (before changes for modified files)
			yield this.create_file_history(
				this.file.manager,
				this.file,
				this.request.creating_file ? "added" : "modified"
			);
			
			// Wait for AST resolution if needed
			// Since resolve_ast_path() is async, we can yield on it directly
			// Changes in queue are not completed yet (they're added when code block closes)
			if (change.ast_path != "") {
				// Yield for resolution - no timeout loops needed
				yield change.resolve_ast_path();
			}
			
			// Apply change after resolution (change is already in changes array, don't add again)
			// apply_change() sets result and completed - does not throw errors
			yield change.apply_change(this.request.edit_mode == "complete_file");
			// result and completed are already set by apply_change()
			// Note: apply_edit() only applies to buffer - does not sync to file
			// Buffer sync and metadata updates happen when queue is empty (before sending response)
			
			this.processing_change = false;
			
			// Process next item in queue, or send response if queue is empty and message completed
			// This is the key: when a change completes, either process next queue item
			// or if end message received and queue empty, sync metadata and send response
			this.process_next_change.begin();
		}
		
		/**
		 * Finalizes stream processing and handles response sending.
		 * 
		 * This should be called when message is completed. It finalizes any remaining
		 * content, sets message_completed flag, and handles response sending based on
		 * queue status. Line-based changes are applied serially after message completion.
		 * AST-based changes are handled by the queue.
		 * 
		 * @param response The chat response object
		 */
		public async void finalize_and_handle_response(OLLMchat.Response.Chat response)
		{
			// Response state is stored on Request so it owns lifecycle and cleanup.
			// Caller is responsible for setting request.chat_response and request.message_completed.
			
			// Check if we have any changes
			if (this.changes.size == 0 && this.pending_changes.size == 0) {
				// No changes were captured - send message to LLM
				this.send_no_changes_response(response);
				return;
			}
			
			// Check for line-based changes (changes without ast_path)
			// These need to be applied serially after message completion
			var has_line_based_changes = false;
			foreach (var change in this.changes) {
				if (change.ast_path == "") {
					has_line_based_changes = true;
					break;
				}
			}
			
			if (has_line_based_changes) {
				// Apply line-based changes serially
				try {
					yield this.apply_line_based_changes();
				} catch (GLib.Error e) {
					GLib.warning("Error applying line-based changes to %s: %s", this.request.normalized_path, e.message);
					this.error_messages.add("There was a problem applying the changes: " + e.message);
				}
			}
			
			// Check queue status (not changes array - both line-based and AST changes go in changes array)
			// If queue is processing or has items, queue processing will handle response when done
			if (this.processing_change || this.pending_changes.size > 0) {
				return;
			}
			
			// Check if AST queue is empty - if so, send response immediately
			// Otherwise, queue processing will send response when done
			if (this.pending_changes.size == 0 && !this.processing_change) {
				this.send_response();
			}
		}
		
		/**
		 * Apply line-based changes serially from start to end.
		 * 
		 * Line-based changes must be applied serially from start to end
		 * to ensure line numbers remain valid. File and project_manager
		 * are already set up (file is stored in Stream, project_manager via file.manager).
		 */
		private async void apply_line_based_changes() throws Error
		{
			// Line-based changes must be applied serially from start to end
			// to ensure line numbers remain valid
			// File and project_manager are already set up (file is stored in Stream, project_manager via file.manager)
			
			var project_manager = this.file.manager;
			var normalized_path = this.request.normalized_path;
			var is_in_project = (this.file.id > 0);
			
			if (!is_in_project && project_manager.active_project != null) {
				var dir_path = GLib.Path.get_dirname(normalized_path);
				if (project_manager.active_project.project_files.folder_map.has_key(dir_path)) {
					is_in_project = true;
				}
			}
			
			this.file.manager.buffer_provider.create_buffer(this.file);
			
			// Ensure file history is created on first edit (before changes for modified files)
			var change_type = this.request.creating_file ? "added" : "modified";
			yield this.create_file_history(project_manager, this.file, change_type);
			
			this.validate_complete_file_changes();
			
			// Filter out completed changes and AST changes - only process line-based changes that are not yet completed
			var valid_changes = new Gee.ArrayList<OLLMfiles.FileChange>();
			foreach (var change in this.changes) {
				if (!change.completed && change.ast_path == "") {
					valid_changes.add(change);
				}
			}
			
			if (valid_changes.size == 0) {
				return;
			}
			// Apply line-based changes serially (from end to start)
			// The LLM line numbers are based on the original file snapshot.
			// Applying from end to start keeps earlier line numbers valid.
			// Sort by start line (descending) to preserve those positions.
			valid_changes.sort((a, b) => {
				if (a.start < b.start) {
					return 1;
				}
				if (a.start > b.start) {
					return -1;
				}
				return 0;
			});
			
			
			if (this.request.edit_mode == "complete_file") {
				yield valid_changes.get(0).apply_change(true);
			} else {
				// Apply in reverse order for line-based changes
				// apply_change() updates result and completed
				foreach (var change in valid_changes) {
					yield change.apply_change(false);
				}
			}
			
			// Sync buffer to file and update metadata
			yield this.sync_and_update_metadata();
		}
		
		/**
		 * Send no changes response to LLM.
		 * 
		 * Called when edit mode was enabled but no changes were provided.
		 */
		private void send_no_changes_response(OLLMchat.Response.Chat response)
		{
			// Send message to LLM that edit mode was enabled but no changes were provided
			this.request.reply_with_errors(
				response,
				"You enabled edit mode for '" + this.request.normalized_path +
					"' but did not provide any code blocks with changes. " +
					"Please provide code blocks with the changes you want to make."
			);
		}
		
		/**
		 * Send response to LLM after all changes are applied.
		 * 
		 * Builds summary of applied changes and sends response to LLM.
		 * This will trigger the "messages completed" signal to UI after response is sent.
		 */
		private void send_response()
		{
			if (!this.request.message_completed) {
				return; // Message not completed yet
			}
			
			if (this.processing_change || this.pending_changes.size > 0) {
				return; // Still processing changes
			}
			
			if (this.request.chat_response == null) {
				return; // No response to send
			}
			
			// Build summary and send response
			int applied_count = 0;
			int failed_count = 0;
			var summary_lines = new Gee.ArrayList<string>();
			
			foreach (var change in this.changes) {
				if (change.result != "applied") {
					failed_count++;
					summary_lines.add("  • " + change.get_description() + " was not applied: " +
						(change.result != "" ? change.result : "unknown error"));
					this.error_messages.add(change.get_description() + " was not applied: " +
						(change.result != "" ? change.result : "unknown error"));
					continue;
				}
				
				applied_count++;
				summary_lines.add("  • " + change.get_description() + " applied");
			}
			
			// Build summary message
			var summary = "All changes were applied.\n\n";
			if (failed_count > 0 && applied_count > 0) {
				summary = "Some changes were applied.\n\n";
			} else if (failed_count > 0) {
				summary = "No changes were applied.\n\n";
			}
			
			foreach (var line in summary_lines) {
				summary += line + "\n";
			}
			
			if (failed_count > 0) {
				this.error_messages.insert(0, summary);
			}
			
			// Calculate line count for success message
			int line_count = 0;
			try {
				line_count = this.count_file_lines();
			} catch (GLib.Error e) {
				GLib.warning("Error counting lines in %s: %s", this.request.normalized_path, e.message);
			}
			
			// Send tool reply to LLM
			// This will trigger the "messages completed" signal to UI after response is sent
			this.request.reply_with_errors(
				this.request.chat_response,
				(line_count > 0)
					? "File '" + this.request.normalized_path +
						"' has been updated. It now has " +
						line_count.to_string() + " lines."
					: "File '" + this.request.normalized_path + "' has been updated."
			);
		}
		
		private async void create_file_history(
			OLLMfiles.ProjectManager project_manager,
			OLLMfiles.File file,
			string change_type) throws Error
		{
			// Check if history already created
			if (this.history_created) {
				return; // Already created
			}
			
		// For modified files, require the file to exist so it has an ID to reference.
		// For added files, history can be created even if the file doesn't exist yet.
			if (change_type != "added" && this.request.creating_file) {
				return; // File doesn't exist yet, will be called again later
			}
		
		
			try {
				var file_history = new OLLMfiles.FileHistory(
					project_manager.db,
					file,
					change_type,
					new GLib.DateTime.now_local()
				);
				yield file_history.commit();
				this.history_created = true;
			} catch (GLib.Error e) {
				GLib.warning("Cannot create FileHistory for edit (%s): %s", this.request.normalized_path, e.message);
			}
		}
		
		/**
		 * Sync buffer to file and update metadata after all changes have been applied.
		 * 
		 * This method syncs the buffer to file and updates metadata after all changes
		 * have been applied. It also ensures file history is created if it wasn't
		 * created earlier (for added files). It's called by both line-based and
		 * AST-based change processing when all changes are done, before sending the response.
		 */
		private async void sync_and_update_metadata() throws Error
		{
			var is_in_project = (this.file.id > 0);
			
			if (!is_in_project && this.file.manager.active_project != null) {
				if (this.file.manager.active_project.project_files.folder_map.has_key(
					GLib.Path.get_dirname(this.request.normalized_path)
				)) {
					is_in_project = true;
				}
			}
			
			var change_type = this.request.creating_file ? "added" : "modified";
			
			// Sync buffer to file (all changes have been applied to buffer)
			// For GTK buffers: use sync_to_file()
			// For DummyFileBuffer: write buffer contents (sync_to_file() throws NOT_SUPPORTED)
			try {
				yield this.file.buffer.sync_to_file();
			} catch (GLib.IOError e) {
				if (e is GLib.IOError.NOT_SUPPORTED) {
					// DummyFileBuffer: get buffer contents and write
					var contents = this.file.buffer.get_text();
					yield this.file.buffer.write(contents);
				} else {
					throw e;
				}
			}
			
			// Update file metadata
			this.send_success_ui_message(is_in_project);
			
			// For added files: convert fake file to real
			if (change_type == "added" && this.file.id <= 0 && is_in_project) {
				var file = yield this.convert_new_file_to_real(this.file.manager, this.file);
				if (file != null) {
					is_in_project = true;
					this.file.manager.active_project.project_files.update_from(this.file.manager.active_project);
				}
			}
			
			// Create history if not already created (handles both modified and added)
			// For modified: should have been created before changes
			// For added: create here after file is created and converted to real
			// create_file_history() checks history_created flag and file existence internally
			yield this.create_file_history(this.file.manager, this.file, change_type);
			
			this.file.is_need_approval = true;
			this.file.last_change_type = change_type;
			this.file.last_modified = new GLib.DateTime.now_local().to_unix();
			
			if (is_in_project || this.file.id > 0) {
				this.file.saveToDB(this.file.manager.db, null, false);
			}
			
			if (is_in_project) {
				this.file.manager.active_project.project_files.review_files.refresh();
			}
			
			if (this.file.manager.db != null) {
				this.file.manager.db.backupDB();
			}
			
			if (this.request.creating_file) {
				this.request.creating_file = false;
			}
		}
		
		private void validate_complete_file_changes() throws Error
		{
			if (this.request.edit_mode != "complete_file") {
				if (this.request.creating_file) {
					throw new GLib.IOError.NOT_FOUND(
						"File does not exist: " + this.request.normalized_path + ". Use complete_file=true to create a new file.");
				}
				return;
			}
			
			var valid_changes = new Gee.ArrayList<OLLMfiles.FileChange>();
			foreach (var change in this.changes) {
				if (!change.completed || change.result == "") {
					valid_changes.add(change);
				}
			}
			
			if (valid_changes.size == 0) {
				return;
			}
			
			if (!this.request.creating_file && !this.request.overwrite) {
				throw new GLib.IOError.EXISTS(
					"File already exists: " + this.request.normalized_path + ". Use overwrite=true to overwrite it.");
			}
		}
		
		private async OLLMfiles.File? convert_new_file_to_real(
			OLLMfiles.ProjectManager project_manager,
			OLLMfiles.File file) throws Error
		{
			yield project_manager.convert_fake_file_to_real(file, this.request.normalized_path);
			return project_manager.get_file_from_active_project(this.request.normalized_path);
		}
		
		private void send_success_ui_message(bool is_in_project)
		{
			GLib.debug("Successfully applied changes to file %s", this.request.normalized_path);
			
			var mode_text = (this.request.edit_mode == "complete_file")
				? "Complete file replacement"
				: (this.request.edit_mode == "ast_path" ? "AST path edits" : "Line range edits");
			var success_message = "Successfully applied changes to file: " + this.request.normalized_path + "\n" +
				"Changes applied: " + this.changes.size.to_string() + "\n" +
				"Project file: " + (is_in_project ? "yes" : "no") + "\n" +
				"Mode: " + mode_text;
			this.request.send_ui("txt", "Changes Applied", success_message);
		}
		
		/**
		 * Counts the total number of lines in a file using buffer.
		 */
		public int count_file_lines() throws Error
		{
			var project_manager = ((Tool) this.request.tool).project_manager;
			if (project_manager == null) {
				throw new GLib.IOError.FAILED("ProjectManager is not available");
			}
			
			var file = project_manager.get_file_from_active_project(this.request.normalized_path);
			if (file == null) {
				file = new OLLMfiles.File.new_fake(project_manager, this.request.normalized_path);
			}
			
			file.manager.buffer_provider.create_buffer(file);
			return file.buffer.get_line_count();
		}
		
	}
}

