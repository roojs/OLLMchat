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

namespace OLLMfiles
{
	/**
	 * One diff item on the wire (''FileHistory.parts'').
	 *
	 * {@link hunk_remove} and {@link hunk_add} are the changed lines.
	 * No '+' or '-' prefix. No line numbers in those strings.
	 * {@link accepted} is 0 undecided, 1 accepted, -1 rejected.
	 * ''compare'' is on the file-server part. It takes another
	 * part.
	 */
	public class FileDiffPart : Object, OLLMrpc.Bin.Serializable
	{
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("FileDiffPart", typeof(FileDiffPart));
		}

		public int64 id { get; set; default = 0; }
		public int64 file_history_id { get; set; default = 0; }
		public int part_index { get; set; default = 0; }

		/**
		 * SHA256 of the hunk text. A column on the file server.
		 */
		public string checksum { get; set; default = ""; }

		/**
		 * Removed lines from ''parts''. No '-' prefix.
		 */
		public string hunk_remove { get; set; default = ""; }

		/**
		 * Added lines from ''parts''. No '+' prefix.
		 */
		public string hunk_add { get; set; default = ""; }

		/**
		 * First old line, 1-based. Not a database column.
		 */
		public int old_line_start { get; set; default = 0; }

		/**
		 * Last old line, 1-based inclusive. Not a database column.
		 */
		public int old_line_end { get; set; default = 0; }

		/**
		 * First new line, 1-based. Not a database column.
		 */
		public int new_line_start { get; set; default = 0; }

		/**
		 * Last new line, 1-based inclusive. Not a database column.
		 */
		public int new_line_end { get; set; default = 0; }

		public int accepted { get; set; default = 0; }
		public int64 decided_at { get; set; default = 0; }
	}
}
