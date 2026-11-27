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
Write or edit a file using <write>…</write> tags in the assistant message.

Call write with file_path and edit_mode, then in the SAME assistant message output:

<write file="PATH" edit_mode="complete_file|line_numbers|ast_path" overwrite="true|false">
...content...
</write>

Do not put file body in the tool call. Do not call write again for this path in this message. STOP after </write>.

edit_mode=complete_file — full file text inside the tag (plain text).
edit_mode=line_numbers — partial edits via lang:start:end fences inside the tag.
edit_mode=ast_path — AST path fences inside the tag (type:Namespace-Class-Method).""";
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
