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

namespace OLLMfilesd
{
	/**
	 * One hunk on a {@link FileHistory} write.
	 *
	 * The row is stored when the diff is shown, before anyone decides.
	 * {@code hunk_remove} and {@code hunk_add} are on this object for
	 * the wire. They are not columns. No '+' or '-' prefix.
	 * {@code accepted} 0 is undecided, 1 accepted, -1 rejected.
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
		 * SHA256 of ''hunk_remove'', a NUL, then ''hunk_add''.
		 * A column. {@link compare} uses this instead of the hunk text.
		 */
		public string checksum { get; set; default = ""; }

		/**
		 * Removed lines, joined by newline. No '-' prefix. Not a column.
		 */
		public string hunk_remove { get; set; default = ""; }

		/**
		 * Added lines, joined by newline. No '+' prefix. Not a column.
		 */
		public string hunk_add { get; set; default = ""; }

		/**
		 * First old line, 1-based. Not a column.
		 */
		public int old_line_start { get; set; default = 0; }

		/**
		 * Last old line, 1-based inclusive. Not a column.
		 * Less than {@code old_line_start} means no removal.
		 */
		public int old_line_end { get; set; default = 0; }

		/**
		 * First new line, 1-based. Not a column.
		 */
		public int new_line_start { get; set; default = 0; }

		/**
		 * Last new line, 1-based inclusive. Not a column.
		 * Less than {@code new_line_start} means no addition.
		 */
		public int new_line_end { get; set; default = 0; }

		public int accepted { get; set; default = 0; }
		public int64 decided_at { get; set; default = 0; }

		/**
		 * Set {@code checksum} from {@code hunk_remove} and
		 * {@code hunk_add}. SHA256 of the remove text, a NUL,
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
		 * {@code 0} neither. {@code 1} line numbers only.
		 * {@code 2} checksum only. {@code 3} both.
		 *
		 * @param other the other hunk
		 * @return 0, 1, 2, or 3
		 */
		public int compare(FileDiffPart other)
		{
			var lines = this.old_line_start == other.old_line_start
				&& this.old_line_end == other.old_line_end
				&& this.new_line_start == other.new_line_start
				&& this.new_line_end == other.new_line_end;
			var hunks = this.checksum != "" && this.checksum == other.checksum;
			return lines ? (hunks ? 3 : 1) : (hunks ? 2 : 0);
		}

		/**
		 * Derived hunk patch path (not stored in SQLite).
		 *
		 * @param history parent write chunk
		 * @return cache path under edited/parts
		 */
		public string path(FileHistory history)
		{
			return GLib.Path.build_filename(
				GLib.Environment.get_user_cache_dir(), "ollmchat", "edited", "parts",
				"%lld-%lld-%d-%s.patch".printf(this.file_history_id, this.id, this.part_index,
					GLib.Path.get_basename(history.path)));
		}

		public static SQ.Query<FileDiffPart> query(SQ.Database db)
		{
			return new SQ.Query<FileDiffPart>(db, "file_diff_part");
		}

		/**
		 * Create file_diff_part table.
		 *
		 * @param db Database instance
		 */
		public static void init_db(SQ.Database db)
		{
			string errmsg;
			var query = "CREATE TABLE IF NOT EXISTS file_diff_part (" +
				"id INTEGER PRIMARY KEY, " +
				"file_history_id INT64 NOT NULL DEFAULT 0, " +
				"part_index INTEGER NOT NULL DEFAULT 0, " +
				"accepted INTEGER NOT NULL DEFAULT 0, " +
				"decided_at INT64 NOT NULL DEFAULT 0, " +
				"checksum TEXT NOT NULL DEFAULT '', " +
				"UNIQUE (file_history_id, part_index)" +
				");";
			if (Sqlite.OK != db.db.exec(query, null, out errmsg)) {
				GLib.warning("Failed to create file_diff_part table: %s", db.db.errmsg());
			}
			var migrate_checksum = "ALTER TABLE file_diff_part ADD COLUMN checksum TEXT NOT NULL DEFAULT ''";
			if (Sqlite.OK != db.db.exec(migrate_checksum, null, out errmsg)) {
				if (!errmsg.contains("duplicate column name")) {
					GLib.debug("Migration note (may be expected): %s", errmsg);
				}
			}
		}
	}
}
