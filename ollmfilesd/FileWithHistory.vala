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
	public class FileWithHistory : Object, Json.Serializable, OLLMrpc.Bin.Serializable
	{
		public static void rpc_register()
		{
			OLLMrpc.Bin.Stream.register(
				"FileWithHistory",
				typeof(FileWithHistory)
			);
		}

		public int64 id { get; set; default = 0; }
		public string path { get; set; default = ""; }
		public string last_change_type { get; set; default = ""; }
		public int64 last_modified { get; set; default = 0; }

		/** Newest pending {@code file_history.id}. */
		public int64 approve_id { get; set; default = 0; }

		/** Newest backup {@code file_history.id} for reject. */
		public int64 reject_id { get; set; default = 0; }

		public unowned ParamSpec? find_property(string name)
		{
			return this.get_class().find_property(name);
		}

		public new void Json.Serializable.set_property(ParamSpec pspec, Value value)
		{
			base.set_property(pspec.get_name(), value);
		}

		public new Value Json.Serializable.get_property(ParamSpec pspec)
		{
			Value val = Value(pspec.value_type);
			base.get_property(pspec.get_name(), ref val);
			return val;
		}

		/**
		 * {@code Folder.fetch_pending_approvals} — one {@code selectQuery}.
		 * Project scope from {@link Folder.roots} (not {@code project.path} alone).
		 */
		public static Gee.ArrayList<GLib.Object> pending(
			ProjectManager manager,
			Folder project
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
	filebase.id,
	filebase.path,
	filebase.last_change_type,
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
	filebase
WHERE
		filebase.is_need_approval = 1
	AND
		filebase.delete_id = 0
	AND
		filebase.base_type = 'f'
	AND
		filebase.id IN (
			SELECT
				file_history.filebase_id
			FROM
				file_history
			WHERE
				file_history.status = 0""" + root_scope + """
		)
""";
			var rows = new Gee.ArrayList<FileWithHistory>();
			var query = new SQ.Query<FileWithHistory>(
				manager.db,
				"filebase"
			);
			query.selectQuery(q, rows);
			foreach (var row in rows) {
				list.add(row);
			}
			return list;
		}
	}
}
