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
