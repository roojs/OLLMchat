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

namespace OLLMfilesd.Vector
{
	/**
	 * One FAISS hit with metadata for tool markdown formatting.
	 */
	public class SearchResult : GLib.Object
	{
		public int64 vector_id { get; set; default = 0; }
		public float distance { get; set; default = 0.0f; }
		public OLLMvector2.SQT.VectorMetadata metadata { get; set; }

		private Folder folder;

		public SearchResult(
			Folder folder,
			int64 vector_id,
			float distance,
			OLLMvector2.SQT.VectorMetadata metadata
		)
		{
			Object(
				vector_id: vector_id,
				distance: distance,
				metadata: metadata
			);
			this.folder = folder;
		}

		/**
		 * File row for this hit's metadata file_id.
		 */
		public File? file()
		{
			return this.folder.project_files.get_by_id(this.metadata.file_id);
		}

		/**
		 * Code snippet from the indexed line range (buffer must be loaded).
		 *
		 * @param max_lines Maximum lines to return (-1 = no limit)
		 */
		public string code_snippet(int max_lines = -1)
		{
			var file = this.file();
			if (file == null) {
				return "";
			}

			var start_line = (this.metadata.start_line - 1).clamp(0, int.MAX);
			var end_line = (this.metadata.end_line - 1).clamp(0, int.MAX);

			if (start_line > end_line) {
				return "";
			}

			end_line = (max_lines != -1 && (end_line - start_line + 1) > max_lines) ?
				start_line + max_lines - 1 : end_line;

			file.manager.buffer_provider.create_buffer(file);

			return file.buffer.get_text(start_line, end_line);
		}

		/**
		 * Markdown block for one search hit (matches shipping tool output).
		 *
		 * @param max_snippet_lines Max snippet lines (-1 = no limit)
		 */
		public string to_markdown(int max_snippet_lines = -1)
		{
			var file = this.file();
			if (file == null) {
				return "";
			}

			var snippet = this.code_snippet(max_snippet_lines);

			var parts = snippet.split("\n");
			if (max_snippet_lines > 0 && parts.length > 1
					&& snippet.length > 80 * max_snippet_lines) {
				snippet = snippet.substring(0, 80 * max_snippet_lines);
				parts = snippet.split("\n");
				snippet = parts.length < 2 ? snippet :
					string.joinv("\n", parts[0:parts.length - 1]);
			}
			var line_count = this.metadata.end_line - this.metadata.start_line + 1;
			var more_lines = (line_count > parts.length)
				? "... (" + (line_count - parts.length).to_string() + " more lines)\n"
				: "";
			var ast_line = this.metadata.ast_path != "" ?
				"- **ast-path** " + this.metadata.ast_path + "\n" : "";
			var ref_path = file.path + (this.metadata.ast_path != "" ?
				"#" + this.metadata.ast_path : "");
			return 
@"#### Result (distance: $(("%.4f").printf(this.distance)))

- **File** $(file.path)
- **Element** $(this.metadata.element_name) ($(this.metadata.element_type))
- **Lines** $(this.metadata.start_line)-$(this.metadata.end_line)
- **Description** $(this.metadata.description)
$(ast_line)- **Reference Link** [$(this.metadata.element_name)]($(ref_path))

```$(file.language)
$(snippet)
```
$(more_lines)
";
		}
	}
}
