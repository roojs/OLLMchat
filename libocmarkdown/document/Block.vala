/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace Markdown.Document
{

	public class Block : Node
	{
		public override FormatType node_type { get; set; default = FormatType.BLOCK; }
		public uint level { get; set; }
		public string lang { get; set; default = ""; }
		public int align { get; set; }
		public bool task_checked { get; set; }
		public string code_text { get; set; default = ""; }
		/** Leading indent for fenced code blocks (e.g. "   " when inside list item). Preserved for round-trip. */
		public string fence_indent { get; set; default = ""; }

		public Block(FormatType k)
		{
			this.kind = k;
		}

		public override string to_markdown()
		{
			string inner = "";
			foreach (var child in this.children) {
				inner += child.to_markdown();
			}
			switch (this.kind) {
				case FormatType.PARAGRAPH:
					return inner;
				case FormatType.HEADING_1:
				case FormatType.HEADING_2:
				case FormatType.HEADING_3:
				case FormatType.HEADING_4:
				case FormatType.HEADING_5:
				case FormatType.HEADING_6:
					var sharp = string.nfill((int)this.level, '#');
					return sharp + " " + inner;
				case FormatType.BLOCKQUOTE:
					return "> " + inner.replace("\n", "\n> ");
				case FormatType.FENCED_CODE_QUOTE:
				case FormatType.FENCED_CODE_TILD:
					var fence = this.kind == FormatType.FENCED_CODE_QUOTE ? "```" : "~~~";
					var code = this.code_text;
					if (code.has_suffix("\n")) {
						code = code.substring(0, code.length - 1);
					}
					var indent = this.fence_indent;
					if (indent != "") {
						var ret = indent + fence + (this.lang != "" ? this.lang : "") + "\n";
						foreach (var line in code.split("\n")) {
							ret += indent + line + "\n";
						}
						ret += indent + fence;
						return ret;
					}
					return fence + (this.lang != "" ? this.lang : "") +
						"\n" + code + "\n" + fence;
				case FormatType.HORIZONTAL_RULE:
					return "---";
				default:
					return inner;
			}
		}
	}
}
