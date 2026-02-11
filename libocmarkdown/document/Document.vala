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

		/** Heading text (stripped) → Block; populated when blocks are adopted (Render) or after deserializing children. Not serialized. */
		public Gee.HashMap<string, Block> headings {
			get; private set; default = new Gee.HashMap<string, Block>(); }

		/** Call when a top-level heading block is adopted; keeps headings in sync. Only stores the first occurrence of each heading name. */
		internal void register_heading(Block b)
		{
			var key = b.text_content().strip();
			if (key == "" || this.headings.has_key(key)) {
				return;
			}
			this.headings.set(key, b);
		}

		/** Create a new node (Block or Format) with uid from this document; caller may adopt it. */
		public Node create(FormatType type, string text = "")
		{
			if (type == FormatType.TEXT) {
				var node = new Format.from_text(text);
				node.uid = this.uid_count++;
				return node;
			}
			if (type.is_block()) {
				var node = new Block(type);
				node.uid = this.uid_count++;
				if (text == "") {
					return node;
				}
				var format = new Format.from_text(text);
				format.uid = this.uid_count++;
				node.adopt(format);
				return node;
			}
			var node = new Format(type);
			node.uid = this.uid_count++;
			if (text != "") {
				node.text = text;
			}
			return node;
		}

		public override string to_markdown()
		{
			if (this.children.size == 0) {
				return "\n";
			}
			var result = "";
			var sep = "";
			var prev_was_blockquote = false;
			var prev_was_table = false;
			for (var i = 0; i < this.children.size; i++) {
				var child = this.children.get(i);
				sep = (i == 0) ? "" : "\n\n";
				if (!(child is Block)) {
					result += sep + child.to_markdown();
					prev_was_blockquote = false;
					prev_was_table = false;
					continue;
				}
				var b = (child as Block).kind;
				// Only use single newline between consecutive blockquotes; otherwise default double newline after blocks
				if (prev_was_blockquote && b == FormatType.BLOCKQUOTE) {
					sep = "\n";
				}
				// Table to_markdown() already ends with \n; avoid extra blank line before next block
				if (prev_was_table) {
					sep = "\n";
				}
				result += sep + child.to_markdown();
				prev_was_blockquote = (b == FormatType.BLOCKQUOTE);
				prev_was_table = (b == FormatType.TABLE);
			}
			return result + "\n";
		}
	}
}
