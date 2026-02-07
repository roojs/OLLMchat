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

	public class Document : Node
	{
		public override FormatType node_type { get; set; default = FormatType.DOCUMENT; }

		/** Next uid to assign; increment when creating a new node so each node has a unique uid. */
		public int uid_count { get; set; default = 1; }

		public override string to_markdown()
		{
			if (this.children.size == 0) {
				return "\n";
			}
			var result = "";
			var sep = "";
			var prev_was_blockquote = false;
			for (var i = 0; i < this.children.size; i++) {
				var child = this.children.get(i);
				sep = (i == 0) ? "" : "\n\n";
				if (!(child is Block)) {
					result += sep + child.to_markdown();
					prev_was_blockquote = false;
					continue;
				}
				var b = (child as Block).kind;
				// Only use single newline between consecutive blockquotes; otherwise default double newline after blocks
				if (prev_was_blockquote && b == FormatType.BLOCKQUOTE) {
					sep = "\n";
				}
				result += sep + child.to_markdown();
				prev_was_blockquote = (b == FormatType.BLOCKQUOTE);
			}
			return result + "\n";
		}
	}
}
