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
	 * Pending-approval list row ({@code Folder.fetch_pending_approvals}).
	 * Wire / SQL row only — not a {@link FileBase} tree node.
	 */
	public class FileWithHistory : Object, OLLMrpc.Bin.Serializable
	{
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("FileWithHistory", typeof(FileWithHistory));
		}

		public int64 id { get; set; default = 0; }
		public string path { get; set; default = ""; }
		public string last_change_type { get; set; default = ""; }
		public int64 last_modified { get; set; default = 0; }

		/** Newest pending {@code file_history.id}. */
		public int64 approve_id { get; set; default = 0; }

		/** Newest backup {@code file_history.id} for reject. */
		public int64 reject_id { get; set; default = 0; }

		/**
		 * Pending-list delta: `0` = upsert still-pending; `1` / `-1` = leave pending set.
		 */
		public int status { get; set; default = 0; }

		/**
		 * {@code Folder.fetch_pending_approvals} — history rows since marker.
		 * Project scope from {@link Folder.roots} (not {@code project.path} alone).
		 *
		 * @param manager Project manager / DB
		 * @param project Project folder for root scope
		 * @param since_id Client marker ({@code MAX(file_history.id)}); {@code 0} = replay from start
		 */
		public static Gee.ArrayList<GLib.Object> pending(
			ProjectManager manager,
			Folder project,
			int64 since_id = 0
		) throws Error {
			var list = new Gee.ArrayList<GLib.Object>();
			var root_folders = project.roots();
			string[] path_conds = {};
			foreach (var root in root_folders) {
				var escaped_path = root.path.replace("'", "''");
				path_conds += "(instr(file_history.path, '"
					+ escaped_path + "/') = 1 OR file_history.path = '"
					+ escaped_path + "')";
			}
			var root_scope = " AND (" + string.joinv(" OR ", path_conds) + ")";
			var q = """
SELECT
	file_history.filebase_id AS id,
	file_history.path,
	filebase.last_change_type,
	filebase.last_modified,
	file_history.status,
	(
		SELECT
			file_history.id
		FROM
			file_history
		WHERE
				file_history.filebase_id = filebase.id
			AND
				file_history.status = 0
		ORDER BY
			file_history.timestamp DESC
		LIMIT 1
	) AS approve_id,
	(
		SELECT
			file_history.id
		FROM
			file_history
		WHERE
				file_history.filebase_id = filebase.id
			AND
				file_history.backup_path != ''
		ORDER BY
			file_history.timestamp DESC
		LIMIT 1
	) AS reject_id
FROM
	file_history
LEFT JOIN
	filebase
ON
	filebase.id = file_history.filebase_id
WHERE
	(
		file_history.id > """ + since_id.to_string() + """
		OR
		file_history.since_id > """ + since_id.to_string() + """
	)""" + root_scope + """
ORDER BY
	file_history.id ASC,
	file_history.since_id ASC
""";
			var rows = new Gee.ArrayList<FileWithHistory>();
			var query = new SQ.Query<FileWithHistory>(
				manager.db,
				"file_history"
			);
			query.selectQuery(q, rows);
			foreach (var row in rows) {
				list.add(row);
			}
			return list;
		}
	}
}
