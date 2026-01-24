/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
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

		// Parameter properties
		public string file_path { get; set; default = ""; }
		public bool complete_file { get; set; default = false; }
		public bool overwrite { get; set; default = false; }
		
		// Normalized path (set during permission building)
		// Internal so Stream can access it
		internal string normalized_path = "";
		
		// Internal: File object (set once at start of execute_request)
		private OLLMfiles.File? file = null;
		
		// Stream handler for processing streaming content
		private Stream? stream_handler = null;
		
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
			
			// Get ProjectManager
			var project_manager = ((Tool) this.tool).project_manager;
			if (project_manager == null) {
				throw new GLib.IOError.FAILED("ProjectManager is not available");
			}
			
			// Try to get File from active project (needed for AST path resolution)
			this.file = project_manager.get_file_from_active_project(this.normalized_path);
			
			// Create fake file if needed (only after AST path check, since AST doesn't work on fake files)
			// Note: AST path resolution will be done later when code blocks are processed
			if (this.file == null) {
				this.file = new OLLMfiles.File.new_fake(project_manager, this.normalized_path);
			}
			
			// Create Stream instance for processing streaming content
			this.stream_handler = new Stream(
				this,                    // Request reference (Stream calls send_ui() on this)
				this.file,              // File object (Stream can get path from file.path, project_manager from file.manager)
				this.complete_file      // Complete file mode (passed as write_complete_file)
			);
			
			// Get file status for UI message
			var is_in_project = (this.file.id > 0);
			var file_exists = GLib.FileUtils.test(this.normalized_path, GLib.FileTest.IS_REGULAR);
			
			// Build UI message - just the request info and permission status
			var ui_message = "Edit mode activated for file: " + this.normalized_path + "\n"
				+ "File status: " + (file_exists ? "exists" : "will be created") + "\n"
				+ "Project file: " + (is_in_project ? "yes (auto-approved)" : "no (permission required)");
			
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
			
			// Activate this request (cleans up existing requests for same file)
			var edit_tool = (Tool) this.tool;
			edit_tool.activate_request(this);
			
			// Signal connections are now handled automatically via agent.register_tool_monitoring()
			// which is called in Tool.execute() when the request is created.
			
			return llm_message;
		}
		
		/**
		 * Override on_stream_chunk callback to process streaming content.
		 * 
		 * This method is connected as a signal handler to Agent.Base.stream_chunk signal
		 * in Agent.Base.register_tool_monitoring() when the tool is activated. It's
		 * disconnected in Agent.Base.unregister_tool() when the tool completes.
		 * 
		 * The signal is emitted by Agent.Base.handle_stream_chunk() which is called
		 * by Chat when streaming chunks arrive from the Ollama API.
		 * 
		 * @param new_text The new text chunk
		 * @param is_thinking Whether this is a thinking chunk
		 * @param response The response object
		 */
		public override void on_stream_chunk(string new_text, bool is_thinking, OLLMchat.Response.Chat response)
		{
			// stream_handler is created in execute_request() and stream chunks only arrive when tool is active
			this.stream_handler.process_chunk(new_text, is_thinking);
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

			GLib.debug("Request.on_message_completed: Processing done message (file=%s)", this.normalized_path);
	
			// Process non-streaming content if needed
			// stream_handler is created in execute_request() and on_message_completed() only happens when tool is active
			if (!this.agent.chat().stream && response.message.content != "") {
				this.stream_handler.process_complete_content(response.message.content);
			}
			
			// Finalize stream processing and wait for AST resolutions
			// Stream handles all the waiting and summary building
			this.stream_handler.finalize_and_wait_for_resolutions.begin(response, (obj, res) => {
				this.stream_handler.finalize_and_wait_for_resolutions.end(res);
				
				// Check if we have any changes (Stream may have found none)
				if (this.stream_handler.changes.size == 0) {
					// No changes were captured - clean up silently
					GLib.debug("Request.on_message_completed: No changes captured (file=%s), cleaning up silently", 
						this.normalized_path);
					// Already unregistered at the top of this method
					var edit_tool = (Tool) this.tool;
					edit_tool.active_requests.remove(this);
					GLib.debug("Request.on_message_completed: Removed request from active_requests (remaining=%zu, file=%s)", 
						edit_tool.active_requests.size, this.normalized_path);
					// Don't send any reply - just let the LLM try again naturally
					return;
				}
				//FIXME - need to solve this - it's ab background operation 
				// and can send to the LLM at some point?
				// and needs to block the user from doing anything in the meantime.
				// Stream has completed finalization and built summaries
				// Now apply changes (only those that succeeded)
				this.stream_handler.apply_all_changes.begin((obj, res2) => {
					this.stream_handler.handle_apply_changes_response(res2, response);
				});
			});
		}
		
		/**
		 * Sends a message to continue the conversation and disconnects signals.
		 * This method should be called on both success and error paths to ensure signals are always disconnected.
		 * Uses agent.chat().send_append() to continue the conversation with the LLM's response.
		 * 
		 * Internal so Stream can call it.
		 */
		internal void reply_with_errors(OLLMchat.Response.Chat response, string message = "")
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
			string reply_text = (this.stream_handler.error_messages.size > 0 
				? string.joinv("\n", this.stream_handler.error_messages.to_array()) + (message != "" ? "\n" : "") 
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
						var edit_tool = (Tool) this.tool;
						edit_tool.active_requests.remove(this);
						GLib.debug("Request.reply_with_errors: Removed request from active_requests (remaining=%zu, file=%s)", 
							edit_tool.active_requests.size, this.normalized_path);
					}
				);
				return false; // Don't repeat
			});
		}
		
	}
}
