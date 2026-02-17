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
	 * Tool for editing files by activating "edit mode" for a file.
	 * 
	 * This tool activates edit mode for a file. While edit mode is active, code blocks
	 * with type:startline:endline format are automatically captured. When chat is done,
	 * all captured changes are applied to the file.
	 */
	public class Tool : OLLMchat.Tool.BaseTool
	{
		
		public override string name { get { return "edit_mode"; } }
		
		public override Type config_class() { return typeof(OLLMchat.Settings.BaseToolConfig); }
		public override string title { get { return "Edit Mode Tool"; } }
		public override string example_call {
			get { return "{\"name\": \"edit_mode\", \"arguments\": {\"file_path\": \"src/main.vala\", \"edit_mode\": \"ast_path\"}}"; }
		}
		public override string description { get {
			return """
Turn on edit mode for a file.

While edit mode is active, code blocks will be automatically captured and applied to the file when the chat is done.

To apply changes, just end the chat (send chat done signal). All captured code blocks will be applied to the file automatically.

Supported formats:
- ast_path (default, preferred): use type:Namespace-Class-Method
- complete_file: replace or create a full file with a bare language tag
- line_numbers (not recommended): edit an existing file with type:startline:endline
An editing session cannot mix output formats.

Code block format depends on the mode:
- ast_path: Code blocks must include AST path in format type:Namespace-Class-Method.
- ast_path suffixes: `:before-comment`, `:after`, `:remove`, `:with-comment` (comments apply to replace/remove/before-comment).
- line_numbers: Code blocks must include line range in format type:startline:endline (e.g., vala:10:15, vala:1:5). The range is inclusive of the start line and exclusive of the end line. Line numbers are 1-based.
- complete_file: Code blocks should only have the language tag (e.g., ```vala). The entire file content will be replaced. If the file doesn't exist, it will be created. If it exists and overwrite=true, it will be overwritten. If overwrite=false and the file exists, an error will be returned.

When edit_mode=complete_file, do not include line numbers or ast-path in the code block.

CRITICAL: You MUST include both opening and closing markdown code block tags. For example:
```
content to write
```
Don't forget to close the code block with the closing ``` tag. If you don't close it, the changes will not be captured and applied.""";
		} }
		
		public override string parameter_description { get {
			return """
@param file_path {string} [required] The path to the file to edit.
@param edit_mode {string} [optional] One of: ast_path, line_numbers, complete_file. Default is ast_path.
@param overwrite {boolean} [optional] If true and edit_mode=complete_file, overwrite existing file. If false and file exists, return error. Default is false.""";
		} }
		
		/**
		 * Signal emitted when a change is actually applied to a file.
		 * This signal is emitted for each change as it is applied, allowing UI
		 * components to track and preview changes non-blockingly.
		 */
		public signal void change_done(string file_path, OLLMfiles.FileChange change);
		
		/**
		 * ProjectManager instance for accessing project context.
		 * Optional - set to null if not available.
		 */
		public OLLMfiles.ProjectManager? project_manager { get; set; default = null; }
		
		/**
		 * List to keep active requests alive so signal handlers can be called.
		 * Hidden from serialization (public field, not a property).
		 * Uses request_id for equality comparison so remove() works correctly.
		 */
		public Gee.ArrayList<Request> active_requests = new Gee.ArrayList<Request>((a, b) => {
			return a.request_id == b.request_id;
		});
		
		public Tool(OLLMfiles.ProjectManager? project_manager = null)
		{
			base();
			this.project_manager = project_manager;
		}
		
		public OLLMchat.Tool.BaseTool? clone()
		{
			return new Tool(this.project_manager);
		}
		
		/**
		 * Activates a request, adding it to the active requests list.
		 * 
		 * Note: Multiple requests for the same file are allowed (e.g., when a single
		 * agent restarts the tool). Handling conflicts between multiple agents editing
		 * the same file is deferred to plan 5.4 (multi-window chat issues).
		 * 
		 * @param request The request to activate
		 */
		public void activate_request(Request request)
		{
			// Clean up any existing active request for the same file before starting a new one
			// in theory this should not be needed - 
			// and it may cause issues if to processes are editing the same file.
			// 
			var existing_requests = new Gee.ArrayList<Request>();
			foreach (var req in this.active_requests) {
				if (req.normalized_path == request.normalized_path && req.request_id != request.request_id) {
					existing_requests.add(req);
				}
			}
			foreach (var req in existing_requests) {
				GLib.debug("Tool.activate_request: Cleaning up existing request for file %s (request_id=%d)", 
					req.normalized_path, req.request_id);
				// Unregister from agent if registered
				req.agent.unregister_tool(req.request_id);
				this.active_requests.remove(req);
			}
			
			// Keep this request alive so signal handlers can be called
			this.active_requests.add(request);
			GLib.debug("Tool.activate_request: Added request to active_requests (total=%zu, file=%s, request_id=%d)", 
				this.active_requests.size, request.normalized_path, request.request_id);
			
			// TODO (Plan 5.4): Handle conflicts when multiple agents edit the same file
			// Currently we allow multiple requests for the same file, which works for
			// single agent restarting the tool, but could cause issues with multiple agents.
		}
		
		protected override OLLMchat.Tool.RequestBase? deserialize(Json.Node parameters_node)
		{
			return Json.gobject_deserialize(typeof(Request), parameters_node) as OLLMchat.Tool.RequestBase;
		}
	}
}

