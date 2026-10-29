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
			OLLMrpc.Request.add_class(
				"FileDiffPart", typeof(FileDiffPart),
				"apply", "xi"
			);
		}

		private ProjectManager rpc_manager;
		private FileHistory history;

		/**
		 * Wire handler for {@code FileDiffPart.apply}.
		 *
		 * @param manager daemon projects and the database
		 * @param history the registered {@code FileHistory} handler
		 */
		public FileDiffPart.for_rpc(ProjectManager manager, FileHistory history)
		{
			Object();
			this.rpc_manager = manager;
			this.history = history;
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
		 * True for an unchanged run built in the editor.
		 * Not a database column. {@link hunk_remove} stays
		 * empty. {@link hunk_add} holds the file lines.
		 */
		public bool unchanged { get; set; default = false; }

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
		 * ''FileDiffPart.apply'' — accept, reject, or reset one hunk.
		 *
		 * @param request inbound RPC
		 * @param id file_diff_part.id
		 * @param action 1 accept, -1 reject, 0 reset
		 */
		public void apply(OLLMrpc.Request request, int64 id, int action)
		{
			if (!this.history.part.has_key((int) id)) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						"diff item is not loaded"
					)
				});
				return;
			}
			var item = this.history.part.get((int) id);
			item.commit.begin(this.history, this.rpc_manager.db, action, (obj, res) => {
				try {
					item.commit.end(res);
				} catch (GLib.Error e) {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						error = new OLLMrpc.Error(
							OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
							e.message
						)
					});
					return;
				}
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					retval = OLLMrpc.val("o", item)
				});
			});
		}

		/**
		 * Store one decision and write the project file when the
		 * hunk text on disk has to change.
		 *
		 * A decision that leaves the file alone stores and returns.
		 * Reject of a pending or accepted hunk writes ''hunk_remove''.
		 * Accept or reset of a rejected hunk writes ''hunk_add''
		 * through the project file's buffer. Later hunks on the
		 * remembered list shift by the line delta. Updates
		 * ''live_stamp'' from {@link File.mtime_on_disk} after the
		 * write. The store after a write repeats the no-write store.
		 *
		 * @param history the registered {@code FileHistory} handler
		 * @param db daemon database
		 * @param action 1 accept, -1 reject, 0 reset
		 * @throws GLib.Error the project file could not be read or written
		 */
		public async void commit(FileHistory history, SQ.Database db, int action) throws GLib.Error
		{
			var histories = new Gee.ArrayList<FileHistory>();
			FileHistory.query(db).select(
				"WHERE id = %lld".printf(this.file_history_id),
				histories
			);
			if (histories.size == 0) {
				throw new GLib.IOError.FAILED("history row not found");
			}
			var list = history.live.get((int) this.file_history_id);
			if ((action != -1 && this.accepted != -1) || (action == -1 && this.accepted == -1)) {
				this.accepted = action == 0 ? 0 : action;
				this.decided_at = action == 0 ? (int64) 0 : GLib.get_real_time();
				FileDiffPart.query(db).updateById(this);
				var open = false;
				foreach (var item in list) {
					if (item.accepted == 0) {
						open = true;
					}
				}
				histories.get(0).reviewed = open ? 0 : 1;
				FileHistory.query(db).updateById(histories.get(0));
				return;
			}
			var insert = this.hunk_add;
			if (action == -1) {
				insert = this.hunk_remove;
			}
			var file = history.rpc_manager.get_file_from_active_project(
				histories.get(0).path);
			if (file == null) {
				throw new GLib.IOError.FAILED("file not found");
			}
			if (file.buffer == null) {
				file.manager.buffer_provider.create_buffer(file);
			}
			var add_count = this.new_line_end < this.new_line_start
				? 0 : this.new_line_end - this.new_line_start + 1;
			var remove_count = this.old_line_end < this.old_line_start
				? 0 : this.old_line_end - this.old_line_start + 1;
			var span = this.accepted == -1 ? remove_count : add_count;
			var at = this.new_line_start;
			var inserted = insert == "" ? 0 : insert.split("\n").length;
			var changes = new Gee.ArrayList<FileChange>();
			changes.add(new FileChange(file) {
				start = at,
				end = at + span,
				replacement = insert
			});
			yield file.buffer.apply_edits(changes);
			var delta = inserted - span;
			this.new_line_end = inserted == 0
				? this.new_line_start - 1
				: this.new_line_start + inserted - 1;
			foreach (var other in list) {
				if (other.id == this.id || other.new_line_start < at + span) {
					continue;
				}
				other.new_line_start += delta;
				other.new_line_end += delta;
			}
			history.live_stamp.set((int) this.file_history_id, (int) file.mtime_on_disk());
			this.accepted = action == 0 ? 0 : action;
			this.decided_at = action == 0 ? (int64) 0 : GLib.get_real_time();
			FileDiffPart.query(db).updateById(this);
			var open = false;
			foreach (var item in list) {
				if (item.accepted == 0) {
					open = true;
				}
			}
			histories.get(0).reviewed = open ? 0 : 1;
			FileHistory.query(db).updateById(histories.get(0));
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
