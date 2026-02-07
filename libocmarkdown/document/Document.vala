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
			string[] parts = {};
			foreach (var child in this.children) {
				parts += child.to_markdown();
			}
			return string.joinv("\n\n", parts);
		}
	}
}
