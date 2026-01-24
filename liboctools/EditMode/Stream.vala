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
		
		// Mode: complete file replacement vs line-based edits
		private bool write_complete_file = false;
		
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
		
		
		public Stream(
			OLLMtools.EditMode.Request request,
			OLLMfiles.File file,
			bool write_complete_file
		)
		{
			this.request = request;
			this.file = file;
			this.write_complete_file = write_complete_file;
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
		
		private bool try_parse_code_block_opener(string stripped_line)
		{
			var tag = stripped_line.substring(3).strip();
			
			if (this.write_complete_file && !tag.contains(":")) {
				this.current_line = "";
				this.current_change = new OLLMfiles.FileChange(this.file);
				return true;
			}
			
			if (!tag.contains(":")) {
				this.current_line = "";
				this.current_change = new OLLMfiles.FileChange(this.file);
				return true;
			}
			
			var parts = tag.split(":");
			if (parts.length < 2) {
				// Invalid format - create FileChange with error state
				this.current_line = "";
				var error_msg = "Invalid code block format: expected format with ':' separator";
				this.current_change = new OLLMfiles.FileChange.with_error(this.file, error_msg);
				this.request.send_ui("txt", "Edit Mode Error", error_msg);
				return true;
			}
			
			// Look for "ast-path" marker
			int ast_path_index = -1;
			for (int i = 0; i < parts.length; i++) {
				if (parts[i] == "ast-path") {
					ast_path_index = i;
					break;
				}
			}
			
			// AST path format
			if (ast_path_index >= 0 && ast_path_index < parts.length - 1) {
				var ast_path_parts = parts[ast_path_index + 1:parts.length];
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
			
			// Line number format: type:startline:endline
			if (parts.length < 3) {
				// Invalid format - create FileChange with error state
				this.current_line = "";
				var error_msg = "Invalid code block format: line number format requires at least 3 parts (type:start:end)";
				this.current_change = new OLLMfiles.FileChange.with_error(this.file, error_msg);
				this.request.send_ui("txt", "Edit Mode Error", error_msg);
				return true;
			}
			
			int start_line = -1;
			int end_line = -1;
			
			if (!int.try_parse(parts[parts.length - 2], out start_line)) {
				// Invalid format - create FileChange with error state
				this.current_line = "";
				var error_msg = "Invalid code block format: start line must be a valid integer";
				this.current_change = new OLLMfiles.FileChange.with_error(this.file, error_msg);
				this.request.send_ui("txt", "Edit Mode Error", error_msg);
				return true;
			}
			
			if (!int.try_parse(parts[parts.length - 1], out end_line)) {
				// Invalid format - create FileChange with error state
				this.current_line = "";
				var error_msg = "Invalid code block format: end line must be a valid integer";
				this.current_change = new OLLMfiles.FileChange.with_error(this.file, error_msg);
				this.request.send_ui("txt", "Edit Mode Error", error_msg);
				return true;
			}
			
			if (start_line < 1 || end_line < start_line) {
				// Invalid format - create FileChange with error state
				this.current_line = "";
				var error_msg = "Invalid code block format: start line must be >= 1 and end line must be >= start line";
				this.current_change = new OLLMfiles.FileChange.with_error(this.file, error_msg);
				this.request.send_ui("txt", "Edit Mode Error", error_msg);
				return true;
			}
			
			this.current_line = "";
			this.current_change = new OLLMfiles.FileChange(this.file) {
				start = start_line,
				end = end_line
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
			if (this.current_change.start == -2 || this.current_change.end == -2) {
				// Format error already set in try_parse_code_block_opener
				// Just add to changes and reset
				this.changes.add(this.current_change);
				this.has_changes = true;
				this.current_line = "";
				this.current_change = null;
				return;
			}
			
			this.current_change.add_linebreak(true);
			
			// If AST path resolution was started, it will complete asynchronously
			// For line number format, FileChange.add_linebreak() marks it as completed immediately
			
			this.changes.add(this.current_change);
			this.has_changes = true;
			
			this.current_line = "";
			this.current_change = null;
		}
		
		/**
		 * Finalizes stream processing and waits for AST path resolutions to complete.
		 * 
		 * This should be called when message is completed. It finalizes any remaining
		 * content, waits for AST resolutions, and builds error summaries.
		 * 
		 * @param response The chat response object
		 */
		public async void finalize_and_wait_for_resolutions(OLLMchat.Response.Chat response)
		{
			// Finalize stream processing
			this.add_linebreak();
			
			// Check if we have any changes
			if (this.changes.size == 0) {
				// No changes were captured - Request will handle cleanup
				return;
			}
			
			GLib.debug("Stream.finalize_and_wait_for_resolutions: Found %zu changes, waiting for AST resolutions", 
				this.changes.size);
			
			// Wait for all AST path resolutions to complete
			// Try up to 5 times (5 * 200ms = 1 second total wait time)
			int attempts = 0;
			while (attempts < 5) {
				bool all_completed = true;
				foreach (var change in this.changes) {
					if (!change.completed) {
						all_completed = false;
						break;
					}
				}
				
				if (all_completed) {
					break; // All resolutions complete
				}
				
				// Wait 200ms before checking again (200 milliseconds = 0.2 seconds)
				GLib.Timeout.add(200, () => {
					finalize_and_wait_for_resolutions.callback();
					return false;
				});
				yield;
				attempts++;
			}
			
			// After 5 attempts, cancel all changes that are not finished
			foreach (var change in this.changes) {
				if (!change.completed) {
					change.mark_completed("AST path resolution timeout");
				}
			}
			
			// Build summary message from individual change results
			int applied_count = 0;
			int failed_count = 0;
			var summary_lines = new Gee.ArrayList<string>();
			
			foreach (var change in this.changes) {
				// Check result (format errors and AST resolution errors are already stored in change.result)
				if (change.result != "applied") {
					failed_count++;
					string error_msg = change.get_description() + " was not applied: " + (change.result != "" ? change.result : "unknown error");
					summary_lines.add("  • " + error_msg);
					this.error_messages.add(error_msg); // Collect for reply_with_errors()
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
			
			// Store summary in error_messages if there were failures
			if (failed_count > 0) {
				this.error_messages.insert(0, summary);
			}
		}
		
		/**
		 * Applies all captured changes to a file.
		 * 
		 * Filters out failed changes and applies only successful ones.
		 * Handles file creation, history, validation, and emits signals.
		 */
		public async void apply_all_changes() throws Error
		{
			if (this.changes.size == 0) {
				return;
			}
		
			var project_manager = ((Tool) this.request.tool).project_manager;
			if (project_manager == null) {
				throw new GLib.IOError.FAILED("ProjectManager is not available");
			}
			
			var normalized_path = this.request.normalized_path;
			var file = project_manager.get_file_from_active_project(normalized_path);
			var is_in_project = (file != null);
			
			if (!is_in_project && project_manager.active_project != null) {
				var dir_path = GLib.Path.get_dirname(normalized_path);
				if (project_manager.active_project.project_files.folder_map.has_key(dir_path)) {
					is_in_project = true;
				}
			}
			
			if (!is_in_project && !this.request.agent.get_permission_provider().check_permission(this.request)) {
				throw new GLib.IOError.PERMISSION_DENIED("Permission denied or revoked");
			}
			
			this.send_apply_ui_message(is_in_project);
			
			if (file == null) {
				file = new OLLMfiles.File.new_fake(project_manager, normalized_path);
			}
			file.manager.buffer_provider.create_buffer(file);
			
			var file_exists = GLib.FileUtils.test(normalized_path, GLib.FileTest.IS_REGULAR);
			var change_type = file_exists ? "modified" : "added";
			
			if (change_type == "modified") {
				yield this.create_file_history(project_manager, file, change_type);
			}
			
			this.validate_changes(file_exists);
			
			// Filter out failed changes (those with start == -2 || end == -2)
			var valid_changes = new Gee.ArrayList<OLLMfiles.FileChange>();
			foreach (var change in this.changes) {
				if (change.start != -2 && change.end != -2 && change.result == "applied") {
					valid_changes.add(change);
				}
			}
			
			if (this.write_complete_file) {
				if (valid_changes.size > 0) {
					// Write replacement content using buffer (handles backup and directory creation automatically)
					yield file.buffer.write(valid_changes[0].replacement);
				}
			} else {
				if (valid_changes.size > 0) {
					yield this.apply_edits(file, valid_changes);
				}
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
			
			if (project_manager.db != null) {
				project_manager.db.backupDB();
			}
		}
		
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
				GLib.warning("Cannot create FileHistory for edit (%s): %s", this.request.normalized_path, e.message);
			}
		}
		
		private void validate_changes(bool file_exists) throws Error
		{
			if (!this.write_complete_file) {
				if (!file_exists) {
					throw new GLib.IOError.NOT_FOUND(
						"File does not exist: " + this.request.normalized_path + ". Use complete_file=true to create a new file.");
				}
				return;
			}
			
			if (this.changes.size > 1) {
				throw new GLib.IOError.INVALID_ARGUMENT(
					"Cannot create/overwrite file: multiple changes detected. Complete file mode only allows a single code block.");
			}
			
			if (this.changes.size > 0 && 
				(this.changes[0].start != -1 || this.changes[0].end != -1)) {
				throw new GLib.IOError.INVALID_ARGUMENT(
					"Cannot use line numbers in complete_file mode. When complete_file=true, code blocks should only have the language tag (e.g., ```vala, not ```vala:1:1).");
			}
			
			if (file_exists && !this.request.overwrite) {
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
		
		private void send_apply_ui_message(bool is_in_project)
		{
			GLib.debug("Starting to apply changes to file %s (in_project=%s, changes=%zu)", 
				this.request.normalized_path, is_in_project.to_string(), this.changes.size);
			
			var mode_text = this.write_complete_file ? "Complete file replacement" : "Line range edits";
			var apply_message = "Applying changes to file: " + this.request.normalized_path + "\n" +
				"Changes to apply: " + this.changes.size.to_string() + "\n" +
				"Project file: " + (is_in_project ? "yes" : "no") + "\n" +
				"Mode: " + mode_text;
			this.request.send_ui("txt", "Applying Changes", apply_message);
		}
		
		private void send_success_ui_message(bool is_in_project)
		{
			GLib.debug("Successfully applied changes to file %s", this.request.normalized_path);
			
			var mode_text = this.write_complete_file ? "Complete file replacement" : "Line range edits";
			var success_message = "Successfully applied changes to file: " + this.request.normalized_path + "\n" +
				"Changes applied: " + this.changes.size.to_string() + "\n" +
				"Project file: " + (is_in_project ? "yes" : "no") + "\n" +
				"Mode: " + mode_text;
			this.request.send_ui("txt", "Changes Applied", success_message);
		}
		
		private async void apply_edits(OLLMfiles.File file, Gee.ArrayList<OLLMfiles.FileChange> changes) throws Error
		{
			// Ensure buffer is loaded
			if (!file.buffer.is_loaded) {
				yield file.buffer.read_async();
			}
			
			// Sort changes by start line (descending) so we can apply them in reverse order
			changes.sort((a, b) => {
				if (a.start < b.start) return 1;
				if (a.start > b.start) return -1;
				return 0;
			});
			
			// Apply edits using buffer's efficient apply_edits method
			// This will use GTK buffer operations for GtkSourceFileBuffer
			// or in-memory lines array for DummyFileBuffer
			yield file.buffer.apply_edits(changes);
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
		
		private const string ERROR_APPLYING_CHANGES = "There was a problem applying the changes: ";
		
		/**
		 * Handles the response after applying changes.
		 * 
		 * Counts file lines, sends UI messages, and replies to the LLM.
		 * 
		 * @param res The async result from apply_all_changes()
		 * @param response The chat response object
		 */
		public void handle_apply_changes_response(GLib.AsyncResult res, OLLMchat.Response.Chat response)
		{
			int line_count = 0;
			
			try {
				this.apply_all_changes.end(res);
				
				// Calculate line count for success message
				try {
					line_count = this.count_file_lines();
				} catch (Error e) {
					GLib.warning("Error counting lines in %s: %s", this.request.normalized_path, e.message);
				}
				
				// Build and emit UI message with more detail
				string update_message = "File updated: " + this.request.normalized_path + "\n";
				if (line_count > 0) {
					update_message += "Total lines: " + line_count.to_string() + "\n";
				}
				update_message += "Changes applied: " + this.changes.size.to_string() + "\n";
				var project_manager = ((Tool) this.request.tool).project_manager;
				var is_in_project = project_manager?.get_file_from_active_project(this.request.normalized_path) != null;
				update_message += "Project file: " + (is_in_project ? "yes" : "no");
				this.request.send_ui("txt", "File Updated", update_message);
				
				// Send tool reply to LLM
				this.request.reply_with_errors(
					response,
					(line_count > 0)
						? "File '" + this.request.normalized_path + 
							"' has been updated. It now has " + 
							line_count.to_string() + " lines."
						: "File '" + this.request.normalized_path + "' has been updated."
				);
			} catch (Error e) {
				GLib.warning("Error applying changes to %s: %s", this.request.normalized_path, e.message);
				// Store error message instead of sending immediately
				this.error_messages.add(ERROR_APPLYING_CHANGES + e.message);
				this.request.reply_with_errors(response);
			}
		}
	}
}

