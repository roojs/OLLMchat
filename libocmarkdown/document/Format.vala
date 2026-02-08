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

	public class Format : Node
	{
		public override FormatType node_type { get; set; default = FormatType.FORMAT; }
		public string text { get; set; default = ""; }
		public string href { get; set; default = ""; }
		public string title { get; set; default = ""; }
		public bool is_reference { get; set; }
		public string src { get; set; default = ""; }
		public string tag { get; set; default = ""; }
		public string tag_attributes { get; set; default = ""; }
		public string tag_name { get; set; default = ""; }

		public Format(FormatType k)
		{
			this.kind = k;
		}

		/** Secondary constructor: text run (FormatType.TEXT). */
		public Format.from_text(string s)
		{
			this.kind = FormatType.TEXT;
			this.text = s;
		}

		public override string to_markdown()
		{
			string inner = "";
			foreach (var child in this.children) {
				inner += child.to_markdown();
			}
			switch (this.kind) {
				case FormatType.TEXT:
					return this.text;
				case FormatType.ITALIC:
				case FormatType.ITALIC_ASTERISK:
					return "*" + inner + "*";
				case FormatType.ITALIC_UNDERSCORE:
					return "_" + inner + "_";
				case FormatType.BOLD:
				case FormatType.BOLD_ASTERISK:
					return "**" + inner + "**";
				case FormatType.BOLD_UNDERSCORE:
					return "__" + inner + "__";
				case FormatType.BOLD_ITALIC_ASTERISK:
					return "***" + inner + "***";
				case FormatType.BOLD_ITALIC_UNDERSCORE:
					return "___" + inner + "___";
				case FormatType.CODE:
					return "`" + (this.text != "" ? this.text : inner) + "`";
				case FormatType.STRIKETHROUGH:
					return "~~" + inner + "~~";
				case FormatType.U:
					return "<u>" + inner + "</u>";
				case FormatType.LINK:
					if (this.is_reference) {
						// Implicit ref [text][]: ref key equals link text → emit []; else [ref]
						bool implicit_ref = (this.href != "" && this.href == inner);
						return "[" + inner + "]" + (implicit_ref ? "[]" : "[" + this.href + "]");
					}
					return "[" + inner + "](" + this.href
						+ (this.title != "" ? " \"" + this.title + "\"" : "") + ")";
				case FormatType.TASK_LIST:
					return "[ ]";
				case FormatType.TASK_LIST_DONE:
					return "[x]";
				case FormatType.IMAGE:
					return "![" + (this.title != "" ? this.title : "image") + "](" + this.src
						+ (this.title != "" ? " \"" + this.title + "\"" : "") + ")";
				case FormatType.BR:
					return "\n";
				case FormatType.HTML:
					return "<" + this.tag
						+ (this.tag_attributes != "" ? " " + this.tag_attributes : "") + ">"
						+ inner + "</" + this.tag + ">";
				case FormatType.OTHER:
					return "<" + this.tag_name + ">" + inner + "</" + this.tag_name + ">";
				default:
					return inner;
			}
		}
	}
}
