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
	 * {@link compare} takes another part. 0 neither. 1 lines
	 * only. 2 checksum only. 3 both. The file server matches.
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
		 * True for an unchanged run built in the editor.
		 * Not a database column. {@link hunk_remove} stays
		 * empty. {@link hunk_add} holds the file lines.
		 */
		public bool unchanged { get; set; default = false; }

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

		/**
		 * Set {@link checksum} from {@link hunk_remove} and
		 * {@link hunk_add}. SHA256 of the remove text, a NUL,
		 * then the add text.
		 */
		public void update_sum()
		{
			var sum = new GLib.Checksum(GLib.ChecksumType.SHA256);
			sum.update((uint8[]) (this.hunk_remove + "\0" + this.hunk_add).to_utf8(), -1);
			this.checksum = sum.get_string();
		}

		/**
		 * Compare this part to another file part.
		 *
		 * 0 neither. 1 line numbers only. 2 checksum only. 3 both.
		 *
		 * @param other the other hunk
		 * @return 0, 1, 2, or 3
		 */
		public int compare(FileDiffPart other)
		{
			var lines = this.old_line_start == other.old_line_start &&
				this.old_line_end == other.old_line_end &&
				this.new_line_start == other.new_line_start &&
				this.new_line_end == other.new_line_end;
			var hunks = this.checksum != "" && this.checksum == other.checksum;
			if (lines && hunks) {
				return 3;
			}
			if (lines) {
				return 1;
			}
			if (hunks) {
				return 2;
			}
			return 0;
		}
	}
}
