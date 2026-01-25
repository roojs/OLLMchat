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

namespace OLLMtools.ReadFile
{
	/**
	 * Tool for reading file contents with optional line range support.
	 * 
	 * This tool reads file contents and returns them as a string. The caller
	 * is responsible for creating the JSON reply.
	 */
	public class Tool : OLLMchat.Tool.BaseTool
	{
		
	public override string name { get { return "read_file"; } }
	
	public override Type config_class() { return typeof(OLLMchat.Settings.BaseToolConfig); }
			
		public override string description { get {
			return """
Read the contents of a file (and the outline).

If you want to understand what is in a file, you are recommended to call summarize on it first. This will give you an overview of the file's structure and contents before reading specific sections. The summary shows the hierarchical structure of code elements (classes, methods, functions, etc.) with AST paths by default, making it easy to identify and reference specific elements.

You can read specific code elements using AST paths (e.g., "Namespace-Class-Method") instead of line numbers. This is more reliable than line numbers, especially when code changes. AST paths work for files in the active project and automatically resolve to the correct line range, including any preceding documentation comments when available.

When using this tool to gather information, it's your responsibility to ensure you have the COMPLETE context. Each time you call this command you should:
1) Assess if contents viewed are sufficient to proceed with the task.
2) Take note of lines not shown.
3) If file contents viewed are insufficient, and you suspect they may be in lines not shown, proactively call the tool again to view those lines.
4) When in doubt, call this tool again to gather more information. Partial file views may miss critical dependencies, imports, or functionality.

If reading a range of lines is not enough, you may choose to read the entire file.
Reading entire files is often wasteful and slow, especially for large files (i.e. more than a few hundred lines). So you should use this option sparingly.
Reading the entire file is not allowed in most cases. You are only allowed to read the entire file if it has been edited or manually attached to the conversation by the user.""";
		} }
		
		public override string parameter_description { get {
			return """
@param file_path {string} [required] The path to the file to read.
@param ast_path {string} [optional] AST path to locate code elements (e.g., "Namespace-Class-Method"). Alternative to start_line/end_line. Resolves to line range automatically and includes preceding documentation comments when available. Only works for files in the active project.
@param start_line {integer} [optional] The starting line number to read from. Ignored if ast_path is provided.
@param end_line {integer} [optional] The ending line number to read to. Ignored if ast_path is provided.
@param read_entire_file {boolean} [optional] Whether to read the entire file. Only allowed if the file has been edited or manually attached to the conversation by the user.
@param show_lines {boolean} [optional] If true, output content with line numbers prefixed to each line (e.g., "1: content", "2: content"). We recommend you do this if you are going to edit code, as it will make it easier to work out which lines to edit.
@param find_words {string} [optional] Search for lines containing this string and return only matching lines with line numbers. Case-insensitive search.
@param summarize {boolean} [optional] If true, generate a tree-sitter based summary of the file structure instead of reading the file contents. The summary shows the hierarchical structure (classes, methods, functions, etc.) with AST paths by default. If you want line numbers instead, use show_lines parameter.""";
		} }
		
		/**
		 * ProjectManager instance for accessing project context.
		 * Optional - set to null if not available.
		 */
		public OLLMfiles.ProjectManager? project_manager { get; set; default = null; }
		
	public Tool(OLLMfiles.ProjectManager? project_manager = null)
	{
		base();
		this.project_manager = project_manager;
		this.title = "Read File Tool";
	}
		
		public OLLMchat.Tool.BaseTool? clone()
		{
			return new Tool(this.project_manager);
		}
		
		protected override OLLMchat.Tool.RequestBase? deserialize(Json.Node parameters_node)
		{
			return Json.gobject_deserialize(typeof(Request), parameters_node) as OLLMchat.Tool.RequestBase;
		}
	}
}

