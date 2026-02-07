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

	public class List : Node
	{
		public override FormatType node_type { get; set; default = FormatType.LIST; }
		public bool ordered { get; set; }
		public uint indentation { get; set; }

		public override string to_markdown()
		{
			string[] parts = new string[this.children.size];
			int i = 0;
			foreach (var child in this.children) {
				var item = child as ListItem;
				string prefix = this.ordered ? (i + 1).to_string() + ". " : "- ";
				parts[i++] = prefix + (item != null ? item.to_markdown() : "");
			}
			return string.joinv("\n", parts);
		}
	}
}
