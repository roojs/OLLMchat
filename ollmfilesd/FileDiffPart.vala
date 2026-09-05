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
	 * One acted-on hunk within a {@link FileHistory} write chunk.
	 *
	 * No row means the hunk is still pending. {@code accepted=1} approve
	 * (disk unchanged); {@code accepted=0} reject (hunk undone on disk).
	 */
	public class FileDiffPart : Object
	{
		public int64 id { get; set; default = 0; }
		public int64 file_history_id { get; set; default = 0; }
		public int part_index { get; set; default = 0; }
		public int accepted { get; set; default = 0; }
		public int64 decided_at { get; set; default = 0; }

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
				"UNIQUE (file_history_id, part_index)" +
				");";
			if (Sqlite.OK != db.db.exec(query, null, out errmsg)) {
				GLib.warning("Failed to create file_diff_part table: %s", db.db.errmsg());
			}
		}
	}
}
