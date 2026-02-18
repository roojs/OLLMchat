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

	public class ListItem : Node
	{
		public override FormatType node_type { get; set; default = FormatType.LIST_ITEM; }
		public bool task_checked { get; set; }
		public bool is_task_item { get; set; default = false; }

		/**
		 * Get key from this list item and fill value with the rest (operates on this).
		 * Caller creates value and passes it in. Only checks first child; only BOLD_ASTERISK.
		 * If first child is not BOLD_ASTERISK → return "". Else return first child's text and append tail to value.children.
		 */
		public string key_value(Block value)
		{
			if (this.children.size == 0) {
				return "";
			}
			var first = this.children.get(0);
			if (!(first is Format) || ((Format) first).kind != FormatType.BOLD_ASTERISK) {
				return "";
			}
			var key = ((Format) first).text_content().strip();
			for (var i = 1; i < this.children.size; i++) {
				value.children.add(this.children.get(i));
			}
			return key;
		}

		/** Append a nested ListItem under this list item; creates a List if needed. Returns the new ListItem (uid from document). */
		public ListItem? append_li()
		{
			var doc = this.document() as Document;
			if (doc == null) {
				return null;
			}
			List? list = null;
			if (this.children.size > 0 && this.children.get(this.children.size - 1) is List) {
				list = (List) this.children.get(this.children.size - 1);
			}
			if (list == null) {
				list = new List() { 
					ordered = false, 
					indentation = 0 
				};
				list.uid = doc.uid_count++;
				this.adopt(list);
			}
			var item = new ListItem();
			item.uid = doc.uid_count++;
			list.adopt(item);
			return item;
		}

		/** Append a child node from raw markdown (parsed as inline/one paragraph). */
		public void append_raw(string raw)
		{
			var doc = this.document() as Document;
			if (doc == null) {
				return;
			}
			var temp = new Render();
			temp.parse(raw);
			foreach (var c in temp.document.children) {
				c.uid = doc.uid_count++;
				this.adopt(c);
			}
		}

		public override string to_markdown()
		{
			var result = this.is_task_item ? (this.task_checked ? "[x] " : "[ ] ") : "";
			foreach (var child in this.children) {
				if (child is List) {
					result += "\n" + child.to_markdown();
					continue;
				}
				result += child.to_markdown();
				
			}
			return result;
		}
	}
}
