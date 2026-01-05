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
	 * Tool for reading file contents with optional line range support.
	 * 
	 * This tool reads file contents and returns them as a string. The caller
	 * is responsible for creating the JSON reply.
	 */
	public class ReadFile : OLLMchat.Tool.BaseTool
	{
		/**
		 * Sets up the read_file tool configuration with default values.
		 */
		public static void setup_tool_config(OLLMchat.Settings.Config2 config)
		{
			var tool_config = new OLLMchat.Settings.BaseToolConfig();
			tool_config.title = new ReadFile(
				new OLLMchat.Client(
					new OLLMchat.Settings.Connection() { url = "http://localhost" }
				)
			).description.strip().split("\n")[0];
			config.tools.set("read_file", tool_config);
		}
		
		public override string name { get { return "read_file"; } }
		
		public override string description { get {
			return """
Read the contents of a file (and the outline).

If you want to understand what is in a file, you are recommended to call summarize on it first. This will give you an overview of the file's structure and contents before reading specific sections.

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
@param start_line {integer} [optional] The starting line number to read from.
@param end_line {integer} [optional] The ending line number to read to.
@param read_entire_file {boolean} [optional] Whether to read the entire file. Only allowed if the file has been edited or manually attached to the conversation by the user.
@param with_lines {boolean} [optional] If true, output content with line numbers prefixed to each line (e.g., "1: content", "2: content").
@param find_words {string} [optional] Search for lines containing this string and return only matching lines with line numbers. Case-insensitive search.
@param summarize {boolean} [optional] If true, generate a tree-sitter based summary of the file structure instead of reading the file contents.""";
		} }
		
		/**
		 * ProjectManager instance for accessing project context.
		 * Optional - set to null if not available.
		 */
		public OLLMfiles.ProjectManager? project_manager { get; set; default = null; }
		
		public ReadFile(OLLMchat.Client? client = null, OLLMfiles.ProjectManager? project_manager = null)
		{
			base(client);
			this.project_manager = project_manager;
		}
		
		protected override OLLMchat.Tool.RequestBase? deserialize(Json.Node parameters_node)
		{
			return Json.gobject_deserialize(typeof(RequestReadFile), parameters_node) as OLLMchat.Tool.RequestBase;
		}
	}
}

