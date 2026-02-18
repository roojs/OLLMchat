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

		/** Heading line plus section body as markdown. Used by Runner for template placeholders (e.g. project-description, current-file). */
		public string to_markdown_with_content()
		{
			var out = this.to_markdown();
			foreach (var node in this.contents(false)) {
				out += "\n\n" + node.to_markdown();
			}
			return out;
		}

		/** Content nodes from after this heading until the next heading. Default (with_sub_headings = false): stop at any heading; do not include sub-headings. with_sub_headings = true: stop at next heading with level <= this.level (include sub-headings). */
		public Gee.ArrayList<Node> contents(bool with_sub_headings = false)
		{
			var ret = new Gee.ArrayList<Node>();
			var doc = this.document();
			if (doc == null) {
				return ret;
			}
			int i = doc.children.index_of(this);
			for (var j = i + 1; j < doc.children.size; j++) {
				var n = doc.children.get(j);
				if (!(n is Block)) {
					ret.add(n);
					continue;
				}
				var b = (Block) n;
				if (b.kind < FormatType.HEADING_1 || b.kind > FormatType.HEADING_6) {
					ret.add(n);
					continue;
				}
				if (!with_sub_headings || b.level <= this.level) {
					break;
				}
				ret.add(n);
			}
			return ret;
		}

		/** Link nodes (Format with kind LINK) among this block's direct children. Each has .href and .title. */
		public Gee.ArrayList<Format> links()
		{
			var ret = new Gee.ArrayList<Format>();
			for (var i = 0; i < this.children.size; i++) {
				var n = this.children.get(i);
				if (n is Format && ((Format) n).kind == FormatType.LINK) {
					ret.add((Format) n);
				}
			}
			return ret;
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
					// inner here will never contain multiple lines (one blockquote block = one line); do not replace newlines
					return (string.nfill((int)(this.level == 0 ? 1 : this.level), '>').replace(">", "> ")
						+ inner).strip();
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
				case FormatType.TABLE: {
					if (this.children.size == 0) {
						return "";
					}
					var first_row = (Block) this.children.get(0);
					var align_row = "| ";
					for (int i = 0; i < first_row.children.size; i++) {
						align_row += (i > 0) ? " | " : "";
						switch (((Block) first_row.children.get(i)).align) {
							case 0:
								align_row += ":---:";
								break;
							case 1:
								align_row += "---:";
								break;
							default:
								align_row += ":---";
								break;
						}
					}
					align_row += " |\n";
					var body_rows = "";
					for (int r = 1; r < this.children.size; r++) {
						body_rows += this.children.get(r).to_markdown();
					}
					return first_row.to_markdown() + align_row + body_rows;
				}
				case FormatType.TABLE_ROW: {
					string result = "| ";
					bool first = true;
					foreach (var c in this.children) {
						result += ((!first) ? " | " : "") + c.to_markdown();
						first = false;
					}
					result += " |\n";
					return result;
				}
				case FormatType.TABLE_HCELL:
				case FormatType.TABLE_CELL:
					return inner;
				default:
					return inner;
			}
		}
	}
}
