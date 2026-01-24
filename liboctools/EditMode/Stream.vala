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
				return false;
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
			
			this.current_line = "";
			this.current_change = new OLLMfiles.FileChange(this.file) {
				start = start_line,
				end = end_line
			};
			return true;
		}
		
		private void add_linebreak()
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
			
			this.current_change.add_linebreak(true);
			
			this.changes.add(this.current_change);
			this.has_changes = true;
			
			this.current_line = "";
			this.current_change = null;
		}
	}
}

