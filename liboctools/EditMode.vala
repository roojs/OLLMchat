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
	 * Tool for editing files by activating "edit mode" for a file.
	 * 
	 * This tool activates edit mode for a file. While edit mode is active, code blocks
	 * with type:startline:endline format are automatically captured. When chat is done,
	 * all captured changes are applied to the file.
	 */
	public class EditMode : OLLMchat.Tool.BaseTool
	{
		
		public override string name { get { return "edit_mode"; } }
		
		public override string title { get { return "Edit Mode Tool"; } }
		
		public override Type config_class() { return typeof(OLLMchat.Settings.BaseToolConfig); }
			
		public override string description { get {
			return """
Turn on edit mode for a file.

While edit mode is active, code blocks will be automatically captured and applied to the file when the chat is done.

To apply changes, just end the chat (send chat done signal). All captured code blocks will be applied to the file automatically.

Code block format depends on the complete_file parameter:
- If complete_file=false (default): Code blocks must include line range in format type:startline:endline (e.g., python:10:15, vala:1:5). The range is inclusive of the start line and exclusive of the end line. Line numbers are 1-based.
- If complete_file=true: Code blocks should only have the language tag (e.g., ```python, ```vala). The entire file content will be replaced. If the file doesn't exist, it will be created. If it exists and overwrite=true, it will be overwritten. If overwrite=false and the file exists, an error will be returned.

When complete_file=true, do not include line numbers in the code block. When complete_file=false, line numbers are required.""";
		} }
		
		public override string parameter_description { get {
			return """
@param file_path {string} [required] The path to the file to edit.
@param complete_file {boolean} [optional] If true, create or overwrite the entire file. Code blocks should only have language tag (no line numbers). Default is false.
@param overwrite {boolean} [optional] If true and complete_file=true, overwrite existing file. If false and file exists, return error. Default is false.""";
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
		
		public EditMode(OLLMchat.Client? client = null, OLLMfiles.ProjectManager? project_manager = null)
		{
			base(client);
			this.project_manager = project_manager;
		}
		
		protected override OLLMchat.Tool.RequestBase? deserialize(Json.Node parameters_node)
		{
			return Json.gobject_deserialize(typeof(RequestEditMode), parameters_node) as OLLMchat.Tool.RequestBase;
		}
	}
}

