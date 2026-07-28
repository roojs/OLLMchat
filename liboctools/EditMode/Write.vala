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
	 * Pi-facing ''write'' tool — same Request/exec as {@link Tool}.
	 */
	public class Write : Tool
	{
		public override string name { get { return "write"; } }
		public override string title { get { return "Write"; } }
		public override string example_call {
			get {
				return "{\"name\": \"write\", \"arguments\": {\"file_path\": \"src/main.vala\", \"edit_mode\": \"ast_path\"}}";
			}
		}
		public override string description { get {
			return """
Write or edit a file using stream-captured code fences.

Call this tool with the target path, then emit fenced code blocks. When the turn
completes, captured blocks are applied to the file.

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
@param file_path {string} [required] The path to the file to write or edit.
@param edit_mode {string} [optional] One of: ast_path, line_numbers, complete_file. Default is ast_path.
@param overwrite {boolean} [optional] If true and edit_mode=complete_file, overwrite existing file. If false and file exists, return error. Default is false.""";
		} }

		public Write(OLLMfiles.ProjectManager? project_manager = null)
		{
			base(project_manager);
		}

		public OLLMchat.Tool.BaseTool? clone()
		{
			return new Write(this.project_manager);
		}
	}
}
