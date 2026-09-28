# 4.2.3.5.5 — Diff items on the wire

**Status:** **⏳** proposed — fences below cover the open path in [`4.2.3.5.4`](CODER-4.2.3.5.4-source-view-diff-wire-model.md). `parts` runs the diff. The client paints from the returned objects.

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan.**

**Parent:** [`CODER-4.2.3.5-source-view-diff-approval.md`](CODER-4.2.3.5-source-view-diff-approval.md)

**Design:** [`CODER-4.2.3.5.4-source-view-diff-wire-model.md`](CODER-4.2.3.5.4-source-view-diff-wire-model.md)

**Supersedes:** [`done/CODER-4.2.3.5.3-SUPERSEDED-source-view-diff-part-rows.md`](done/CODER-4.2.3.5.3-SUPERSEDED-source-view-diff-part-rows.md) — do not apply its fences.

**Next:** [`4.2.3.5.6`](CODER-4.2.3.5.6-source-view-diff-approval-calls.md) — approval. [`4.2.3.5.7`](CODER-4.2.3.5.7-source-view-diff-resync.md) — resync after save.

**Depends on:**

- [`CODER-4.2.3.5.2-source-view-diff-approval-phase-b.md`](CODER-4.2.3.5.2-source-view-diff-approval-phase-b.md) — **✔️** editor hosts `ReviewBar`. Bulk accept / reject are in-memory stubs.
- [`CODER-4.2.3-URGENT-source-view-diff.md`](CODER-4.2.3-URGENT-source-view-diff.md) — `file_diff_part`, Flow A–F

**Pointer:** `docs/guide-to-writing-plans.md` — Checklist for plans

---

## Purpose

- 🔷 The file server stores one diff item per hunk and sends that array down the wire.
- 🔷 The hunk text is a property on that object. It goes down the wire. It is not a database column.
- 🔷 Close and open again reloads those active items. The client hangs the text on the in-memory item and paints from it.
- 🔷 The client does not write diff items and does not read the backup.

---

## Phase 1

The file server owns the store. Open returns the active items.

```
desktop                                          ollmfilesd
────────────────────────────────────────────────────────────────
File.read
  OLLMfilesd-File.read(project path)  →
                                   ←  File row + project text

show_pending_diff
  OLLMfilesd-FileHistory.parts
    file_history id                 →
                                      stored file_diff_part rows, if any
                                      else Differ, then store
                                  ←  those objects, hunk text on each
  hang the text on the in-memory item
  paint from that array
  backup stays on the daemon           (no wire)
```

- 🔷 The diff item contains the hunk text. That text is a property on the object. It goes down the wire with the item.
- 🔷 The file server writes the items to disk. `hunk` is not in that row. A later open sets the text on the object and returns it.
- 🔷 The client hangs that text on the diff item in memory. The client does not write diff items.
- 🔷 The `parts` request answers the client. The diff itself is `FileHistory.rebuild_parts`. That method is not the request.
- 🔷 `rebuild_parts` reads the cache backup and the project file. No rows yet: `Differ`, insert one row per patch, set `hunk` on the objects, remember those objects, return them.
- 🔷 The diff is the project file now against that history's backup. The history id alone does not make a remembered list current.
- 🔷 A later `parts` returns the remembered objects only when the project file's modification stamp still equals the stamp captured when that list was diffed. `hunk` is already on them.
- 🔷 That stamp is the project file's modification time in microseconds, read from the file at diff time.
- 🔷 A different stamp does not return that list. `parts` calls `rebuild_parts`. That sets `hunk` on the rows already stored for that history. Those rows stay.
- 🔷 Rows in the table but no remembered objects: `rebuild_parts` sets `hunk` on those rows. It does not insert again.
- 🔷 `show_pending_diff` does not call `RPC-File.read` on `backup_path`.
- ℹ️ `file_diff_part` today has no hunk text. `ollmfilesd/FileDiffPart.vala`. The daemon cannot link `libocfiles`, so `Differ` still has to be built into `ollmfilesd` the same way `Copyable.vala` is symlinked.
- 🔷 The table is already `file_diff_part`. `hunk` is a property on `FileDiffPart`, not a column. Not a new table, and not `edited/parts/…patch`.
- 🔷 `accepted` `0` is undecided. `1` accepted. `-1` rejected. Same values as the old `file_history.status`. A row exists before anyone decides.
- ℹ️ Today’s comment says the opposite: no row means pending, and `accepted` `0` means reject. Nothing writes `file_diff_part` yet, and the column default is already `0`, so `0` becomes undecided. Reject is `-1`.
- ℹ️ `HunkDecision` in the bar is a separate enum. Its third value is not the stored reject.
- 🔷 `OLLMfilesd-FileHistory.parts` takes the `file_history` id. `FileWithHistory.approve_id` is that same id on the pending-list row. It is not a separate argument.
- 🔷 `hunk` is the changed lines. A removed line starts with `-`. An added line starts with `+`. No `@@` header and no line numbers in that text.
- 💩 `old_line_start` and `new_line_start` are properties on the object, not part of `hunk` and not columns. A removal has no place in the current file, so the editor still needs those starts.
- 🔷 `show_pending_diff` calls `parts` and paints from that array. It does not read the backup and it does not run `Differ`.

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify surrounding context before applying.

### 1. `ollmfilesd/FileDiffPart.vala` — hunk on the object, undecided is `0`

**Why:** The row is `file_diff_part`. It exists before a decision. `hunk` is on the object for the wire. The table has no `hunk` column.

**Where:** class docblock and properties. Do not change the `init_db` create string.

**Depends on:** none.

#### Remove

```vala
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
```

#### Replace with

```vala
	/**
	 * One hunk on a {@link FileHistory} write.
	 *
	 * The row is stored when the diff is shown, before anyone decides.
	 * {@code hunk} is on this object for the wire. It is not a column.
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
		 * Changed lines. A removed line starts with ''-''. An added
		 * line starts with ''+''. No line numbers. Not a column.
		 */
		public string hunk { get; set; default = ""; }

		/**
		 * First old line, 1-based. Not a column.
		 */
		public int old_line_start { get; set; default = 0; }

		/**
		 * First new line, 1-based. Not a column.
		 */
		public int new_line_start { get; set; default = 0; }

		public int accepted { get; set; default = 0; }
		public int64 decided_at { get; set; default = 0; }
```

### 2. `ollmfilesd/Application.vala` — register the row

**Why:** `parts` returns `FileDiffPart` rows. The wire alias has to be registered before that reply.

**Where:** `Application` startup, immediately after `FileWithHistory.rpc_register()`.

**Depends on:** §1.

#### Add — after `FileWithHistory.rpc_register()`.

```vala
			FileDiffPart.rpc_register();
```

### 3. `ollmfilesd/Diff/*.vala` — symlink `Differ` into the daemon

**Why:** `parts` runs `Differ` on the daemon. `ollmfilesd/meson.build` bans linking `libocfiles`. `Copyable.vala` is already a symlink of an `OLLMfiles` source into this binary.

**Where:** new symlinks under `ollmfilesd/Diff/`, then `ollmfilesd_src` after `'FileDiffPart.vala',`.

**Depends on:** none.

#### Add — create the symlinks from the repo root

`mkdir` and `ln -s`. Same kind of symlink as `ollmfilesd/Copyable.vala`.

```sh
mkdir -p ollmfilesd/Diff
ln -s ../../libocfiles/Diff/Patch.vala ollmfilesd/Diff/Patch.vala
ln -s ../../libocfiles/Diff/Differ.vala ollmfilesd/Diff/Differ.vala
```

#### Add — `ollmfilesd/meson.build` `ollmfilesd_src`, after `'FileDiffPart.vala',`

```meson
  'Diff/Patch.vala',
  'Diff/Differ.vala',
```

### 4. `ollmfilesd/FileHistory.vala` — `parts` and `rebuild_parts`

**Why:** The client asks for the parts. `parts` returns the remembered list when the file stamp still matches. Otherwise it calls `rebuild_parts`. The diff is that method, not the request.

**Where:** `rpc_register` gains the `OLLMfilesd-FileHistory` class. A `live` map sits after `rpc_manager`. `parts` is a new method after `for_rpc`. `rebuild_parts` follows `parts`. The reviewed-flag comment above `reviewed` is the old “no row means pending” wording.

**Depends on:** §1, §3.

#### Remove

```vala
		 * Accept vs reject lives on {@link FileDiffPart.accepted} when parts exist.
		 * Whole-file approve/reject sets {@code reviewed=1} with no part rows.
```

#### Replace with

```vala
		 * {@link FileDiffPart.accepted} is 0 undecided, 1 accepted, -1 rejected.
		 * Whole-file approve/reject sets {@code reviewed=1}.
```

#### Add — second `add_class` at the end of `rpc_register`, after the `RPC-FileHistory` registration.

```vala
			OLLMrpc.Request.add_class(
				"OLLMfilesd-FileHistory", typeof(FileHistory),
				"parts", "x"
			);
```

#### Add — `live` after `private ProjectManager rpc_manager;`

Remembered objects for this process. `hunk` stays on them. The table does not store it. `live_stamp` is the project file's modification time in microseconds when that list was diffed.

```vala
		private Gee.HashMap<int64, Gee.ArrayList<FileDiffPart>> live { get; set; default = new Gee.HashMap<int64, Gee.ArrayList<FileDiffPart>>(); }
		private Gee.HashMap<int64, int64> live_stamp { get; set; default = new Gee.HashMap<int64, int64>(); }
```

#### Add — new method `parts` after `for_rpc`.

This request returns the remembered list when `live_stamp` for that history id still equals the project file's modification time. Otherwise it calls `rebuild_parts` and replies with that array.

```vala
		/**
		 * Diff items for one file_history row.
		 *
		 * Returns the remembered list when the project file's
		 * modification stamp still matches the stamp from
		 * {@link rebuild_parts}. Otherwise calls {@link rebuild_parts}
		 * and replies with that array.
		 *
		 * @param request inbound RPC
		 * @param id file_history.id
		 */
		public void parts(OLLMrpc.Request request, int64 id)
		{
			var histories = new Gee.ArrayList<FileHistory>();
			FileHistory.query(this.rpc_manager.db).select(
				"WHERE id = %lld".printf(id),
				histories
			);
			if (histories.size == 0) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						"history row not found"
					)
				});
				return;
			}
			var stamp = (int64) 0;
			try {
				var info = GLib.File.new_for_path(histories.get(0).path).query_info(
					GLib.FileAttribute.TIME_MODIFIED_USEC,
					GLib.FileQueryInfoFlags.NONE,
					null);
				stamp = (int64) info.get_attribute_uint64(
					GLib.FileAttribute.TIME_MODIFIED_USEC);
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
			if (this.live.has_key(id) && this.live_stamp.has_key(id) && this.live_stamp.get(id) == stamp) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					retval = OLLMrpc.val("o", this.live.get(id))
				});
				return;
			}
			try {
				var rows = this.rebuild_parts(histories.get(0));
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					retval = OLLMrpc.val("o", rows)
				});
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						e.message
					)
				});
			}
		}
```

#### Add — new method `rebuild_parts` after `parts`.

The diff. Reads the backup and the project file, runs `Differ`, and sets `hunk` on the rows already stored. Inserts rows only when that history has none. Does not delete rows. Does not write `hunk`. Remembers the list with the project file's modification time from this read.

```vala
		/**
		 * Build the diff items for one history row.
		 *
		 * Reads the backup and the project file, then runs
		 * {@link OLLMfiles.Diff.Differ}. Sets ''hunk'' on the rows
		 * already stored. Inserts rows only when that history has
		 * none. Does not delete rows. Does not write ''hunk''.
		 * Remembers the list with the project file's modification
		 * stamp from this read.
		 *
		 * @param history the file_history row to diff
		 * @return the diff items, with hunk text on each
		 * @throws GLib.Error the backup or project file could not be read
		 */
		public Gee.ArrayList<FileDiffPart> rebuild_parts(FileHistory history) throws GLib.Error
		{
			var rows = new Gee.ArrayList<FileDiffPart>();
			FileDiffPart.query(this.rpc_manager.db).select(
				"WHERE file_history_id = %lld ORDER BY part_index".printf(history.id),
				rows
			);
			var backup = "";
			uint8[] data;
			string etag;
			if (history.backup_path != "") {
				GLib.File.new_for_path(history.backup_path).load_contents(
					null, out data, out etag);
				backup = (string) data;
			}
			GLib.File.new_for_path(history.path).load_contents(
				null, out data, out etag);
			var project = (string) data;
			var info = GLib.File.new_for_path(history.path).query_info(
				GLib.FileAttribute.TIME_MODIFIED_USEC, GLib.FileQueryInfoFlags.NONE, null);
			var stamp = (int64) info.get_attribute_uint64(GLib.FileAttribute.TIME_MODIFIED_USEC);
			var differ = new OLLMfiles.Diff.Differ(backup, project);
			var patches = differ.diff();
			var hunks = new string[patches.size];
			var old_starts = new int[patches.size];
			var new_starts = new int[patches.size];
			var index = 0;
			foreach (var patch in patches) {
				var old_body = patch.old_lines();
				var new_body = patch.new_lines();
				var marked = new string[old_body.length + new_body.length];
				for (var line_i = 0; line_i < old_body.length; line_i++) {
					marked[line_i] = "-" + old_body[line_i];
				}
				for (var line_i = 0; line_i < new_body.length; line_i++) {
					marked[old_body.length + line_i] = "+" + new_body[line_i];
				}
				hunks[index] = string.joinv("\n", marked);
				old_starts[index] = patch.old_line_start;
				new_starts[index] = patch.new_line_start;
				index++;
			}
			if (rows.size == 0) {
				for (var n = 0; n < hunks.length; n++) {
					var part = new FileDiffPart();
					part.file_history_id = history.id;
					part.part_index = n;
					part.hunk = hunks[n];
					part.old_line_start = old_starts[n];
					part.new_line_start = new_starts[n];
					FileDiffPart.query(this.rpc_manager.db).insert(part);
					rows.add(part);
				}
			}
			if (rows.size > 0 && rows.get(0).hunk == "") {
				foreach (var part in rows) {
					if (part.part_index < 0 || part.part_index >= hunks.length) {
						continue;
					}
					part.hunk = hunks[part.part_index];
					part.old_line_start = old_starts[part.part_index];
					part.new_line_start = new_starts[part.part_index];
				}
			}
			if (rows.size > 0) {
				this.live.set(history.id, rows);
				this.live_stamp.set(history.id, stamp);
			}
			return rows;
		}
```

### 5. `ollmfilesd/Application.vala` — dispatch `OLLMfilesd-FileHistory`

**Why:** `add_class` names the method. `Request.register` binds the live `FileHistory` that handles it. One instance serves both names.

**Where:** the existing `Request.register("RPC-FileHistory", …)` call.

**Depends on:** §4.

#### Remove

```vala
			OLLMrpc.Request.register("RPC-FileHistory", 
				new FileHistory.for_rpc(this.project_manager));
```

#### Replace with

```vala
			var history_rpc = new FileHistory.for_rpc(this.project_manager);
			OLLMrpc.Request.register("RPC-FileHistory", history_rpc);
			OLLMrpc.Request.register("OLLMfilesd-FileHistory", history_rpc);
```

### 6. `libocfiles/FileDiffPart.vala` — client wire object

**Why:** The desktop decodes the `parts` reply. The daemon class is not in this process. Same wire name `FileDiffPart`.

**Where:** new file. `libocfiles/meson.build` `ocfiles_gir_src` after `'FileWithHistory.vala',`. `OLLMfiles.rpc_register()` after `FileWithHistory.rpc_register()`.

**Depends on:** §1.

#### Add — new file `libocfiles/FileDiffPart.vala`

```vala
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
	 * One diff item on the wire ({@code OLLMfilesd-FileHistory.parts}).
	 *
	 * {@code hunk} is the changed lines. A removed line starts with
	 * ''-''. An added line starts with ''+''. No line numbers.
	 * {@code accepted} is 0 undecided, 1 accepted, -1 rejected.
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
		 * Changed lines from {@code parts}. A removed line starts with
		 * ''-''. An added line starts with ''+''. No line numbers.
		 */
		public string hunk { get; set; default = ""; }

		/**
		 * First old line, 1-based. Not a database column.
		 */
		public int old_line_start { get; set; default = 0; }

		/**
		 * First new line, 1-based. Not a database column.
		 */
		public int new_line_start { get; set; default = 0; }

		public int accepted { get; set; default = 0; }
		public int64 decided_at { get; set; default = 0; }
	}
}
```

#### Add — `libocfiles/meson.build` `ocfiles_gir_src`, after `'FileWithHistory.vala',`

```meson
  'FileDiffPart.vala',
```

#### Add — `libocfiles/namespace.vala` `rpc_register()`, after `FileWithHistory.rpc_register();`

```vala
		FileDiffPart.rpc_register();
```

### 7. `liboccoder/SourceView.vala` — `show_pending_diff` paints from `parts`

**Why:** Open asks for the parts and paints that array. The backup stays on the daemon.

**Where:** replace `show_pending_diff`.

**Depends on:** §4, §6.

#### Remove

```vala
		/**
		 * If ''file'' is pending approval, load V_backup via daemon and show inline diff.
		 *
		 * @param file open project file (buffer already holds V_disk)
		 */
		public async void show_pending_diff(OLLMfiles.File file)
		{
			if (!this.manager.review_files.file_map.has_key(file.path)) {
				return;
			}
			var row = this.manager.review_files.file_map.get(file.path);
			var gtk_buffer = file.buffer as GtkSource.Buffer;
			if (row.backup_path == "") {
				var differ = new OLLMfiles.Diff.Differ("", gtk_buffer.text);
				this.show_diff(differ);
				this.review_bar.update_diff(differ, this.review_bar.file_index);
				return;
			}
			var v_backup = "";
			try {
				var response = yield this.manager.rpc.call(new OLLMrpc.Request() {
					method = "RPC-File.read",
					args = OLLMrpc.args("s", row.backup_path)
				});
				if (this.current_file != file) {
					return;
				}
				v_backup = response.msg;
				if (response.msg_encode == 1) {
					v_backup = (string) GLib.Base64.decode(response.msg);
				}
			} catch (GLib.Error e) {
				GLib.warning("Failed to read backup %s: %s", row.backup_path, e.message);
			}
			if (this.current_file != file) {
				return;
			}
			var differ = new OLLMfiles.Diff.Differ(v_backup, gtk_buffer.text);
			this.show_diff(differ);
			this.review_bar.update_diff(differ, this.review_bar.file_index);
		}
```

#### Replace with

```vala
		/**
		 * If ''file'' is pending approval, load diff items and paint them.
		 *
		 * Calls {@code OLLMfilesd-FileHistory.parts}. Does not read the backup.
		 *
		 * @param file open project file (buffer already holds V_disk)
		 */
		public async void show_pending_diff(OLLMfiles.File file)
		{
			if (!this.manager.review_files.file_map.has_key(file.path)) {
				return;
			}
			var row = this.manager.review_files.file_map.get(file.path);
			var parts = new Gee.ArrayList<OLLMfiles.FileDiffPart>();
			try {
				var response = yield this.manager.rpc.call(new OLLMrpc.Request() {
					method = "OLLMfilesd-FileHistory.parts",
					args = OLLMrpc.args("x", row.approve_id)
				});
				if (this.current_file != file) {
					return;
				}
				if (response.error != null) {
					GLib.warning("Failed to load diff parts for %s: %s", file.path, response.error.message);
					return;
				}
				if (response.retval.type() == GLib.Type.INVALID) {
					if (this.diff_active) {
						this.clear_diff();
					}
					return;
				}
				parts = (Gee.ArrayList<OLLMfiles.FileDiffPart>) response.retval.get_object();
			} catch (GLib.Error e) {
				GLib.warning("Failed to load diff parts for %s: %s", file.path, e.message);
				return;
			}
			if (this.current_file != file) {
				return;
			}
			if (this.diff_active) {
				this.clear_diff();
			}
			var editor_lines = (file.buffer as GtkSource.Buffer).text.split("\n");
			var display = new Gee.ArrayList<string>();
			var kinds = new Gee.ArrayList<int>();
			this.diff_baseline.clear();
			this.diff_remove_at.clear();
			this.diff_remove_n.clear();
			var new_i = 1;
			foreach (var part in parts) {
				var removed = new Gee.ArrayList<string>();
				var new_count = 0;
				if (part.hunk != "") {
					foreach (var line in part.hunk.split("\n")) {
						if (line.has_prefix("-")) {
							removed.add(line.substring(1));
							continue;
						}
						if (line.has_prefix("+")) {
							new_count++;
						}
					}
				}
				var new_start = part.new_line_start;
				while (new_i < new_start && new_i <= editor_lines.length) {
					display.add(editor_lines[new_i - 1]);
					this.diff_baseline.add(new_i);
					kinds.add(0);
					new_i++;
				}
				if (removed.size > 0) {
					this.diff_remove_at.add(new_start);
					this.diff_remove_n.add(removed.size);
					foreach (var line in removed) {
						display.add(line);
						this.diff_baseline.add(0);
						kinds.add(2);
					}
				}
				if (new_count == 0) {
					if (new_start > new_i) {
						new_i = new_start;
					}
					continue;
				}
				for (var ln = new_start; ln < new_start + new_count && ln <= editor_lines.length; ln++) {
					display.add(editor_lines[ln - 1]);
					this.diff_baseline.add(ln);
					kinds.add(1);
				}
				new_i = new_start + new_count;
			}
			while (new_i <= editor_lines.length) {
				display.add(editor_lines[new_i - 1]);
				this.diff_baseline.add(new_i);
				kinds.add(0);
				new_i++;
			}
			this.diff_buffer = new GtkSource.Buffer(this.diff_tag_table);
			this.diff_buffer.set_text(string.joinv("\n", display.to_array()), -1);
			var add_tag = this.diff_tag_table.lookup("diff-add");
			var remove_tag = this.diff_tag_table.lookup("diff-remove");
			for (var i = 0; i < kinds.size; i++) {
				if (kinds.get(i) == 0) {
					continue;
				}
				Gtk.TextIter iter;
				this.diff_buffer.get_iter_at_line(out iter, i);
				var line_end = iter;
				if (!line_end.ends_line()) {
					line_end.forward_to_line_end();
				}
				if (!line_end.is_end()) {
					line_end.forward_char();
				}
				this.diff_buffer.apply_tag(kinds.get(i) == 1 ? add_tag : remove_tag, iter, line_end);
			}
			this.pre_diff_buffer = this.source_view.buffer as GtkSource.Buffer;
			this.source_view.set_buffer(this.diff_buffer);
			this.source_view.show_line_numbers = false;
			this.diff_active = true;
			this.scrolled_window.visible = true;
			this.review_bar.update_diff(parts, this.review_bar.file_index);
		}
```

### 8. `liboccoder/Diff/ReviewBar.vala` — bands from the parts

**Why:** The bar paints from the same objects. It keeps that list so a later decision still has the hunk text.

**Where:** `parts` property after `hunks`. New `update_diff` overload after the existing `update_diff(Differ, …)`.

**Depends on:** §6.

#### Add — after `private HunkList hunks`

```vala
		public Gee.ArrayList<OLLMfiles.FileDiffPart> parts { get; set; default = new Gee.ArrayList<OLLMfiles.FileDiffPart>(); }
```

#### Add — after the existing `update_diff(OLLMfiles.Diff.Differ, …)` method

Bands from the changed lines and the start properties. `accepted` 0 is pending, 1 accepted, -1 rejected.

```vala
		/**
		 * Paint hunk bands from {@code OLLMfilesd-FileHistory.parts}.
		 *
		 * Keeps {@code parts} so the hunk text stays on the client.
		 *
		 * @param parts diff items, hunk text on each
		 * @param file_index file position in the pending list
		 */
		public void update_diff(
			Gee.ArrayList<OLLMfiles.FileDiffPart> parts,
			int file_index = -1)
		{
			this.parts = parts;
			this.file_index = file_index >= 0 ? file_index : this.file_index;
			this.hunks.clear();
			this.hunk_line_sum = 0;
			var bi = 0;
			var bulk_decision = HunkDecision.PENDING;
			if (this.file_index < this.file_bulk.length) {
				bulk_decision = this.file_bulk[this.file_index];
			}
			foreach (var part in this.parts) {
				var old_count = 0;
				var new_count = 0;
				if (part.hunk != "") {
					foreach (var line in part.hunk.split("\n")) {
						if (line.has_prefix("-")) {
							old_count++;
							continue;
						}
						if (line.has_prefix("+")) {
							new_count++;
						}
					}
				}
				var old_start = part.old_line_start;
				var new_start = part.new_line_start;
				var old_end = old_count == 0 ? old_start - 1 : old_start + old_count - 1;
				var new_end = new_count == 0 ? new_start - 1 : new_start + new_count - 1;
				var op = OLLMfiles.Diff.PatchOperation.REPLACE;
				if (old_count == 0) {
					op = OLLMfiles.Diff.PatchOperation.ADD;
				}
				if (old_count > 0 && new_count == 0) {
					op = OLLMfiles.Diff.PatchOperation.REMOVE;
				}
				var patch = new OLLMfiles.Diff.Patch(
					op, old_start, old_end, new_start, new_end,
					new string[0], new string[0]);
				var band = new HunkBand(patch) {
					band_index = bi,
				};
				switch (part.accepted) {
					case 1:
						band.decision = HunkDecision.ACCEPTED;
						break;
					case -1:
						band.decision = HunkDecision.REJECTED;
						break;
					default:
						break;
				}
				if (bulk_decision != HunkDecision.PENDING) {
					band.decision = bulk_decision;
				}
				this.hunks.add(band);
				this.hunk_line_sum += band.line_count;
				bi++;
			}
			this.file_nav.visible = this.live_queue ? this.file_count > 0 : this.file_count > 1;
			this.file_prev.visible = this.file_count > 1;
			this.file_next.visible = this.file_count > 1;
			if (this.file_nav.visible) {
				this.file_nav_btn.label = "File %d of %d".printf(
					this.file_index + 1, this.file_count);
			}
			if (this.mock_inactive) {
				this.pending_label.visible = true;
				this.map_area.visible = false;
				this.map_scroll_left.visible = false;
				this.map_scroll_right.visible = false;
				this.pending_label.label = "%d changes pending review".printf(
					this.file_count);
				this.accept_btn.visible = false;
				this.reject_btn.visible = false;
				this.feedback_btn.visible = false;
				this.unapprove_btn.visible = false;
				return;
			}
			this.pending_label.visible = false;
			this.map_area.visible = true;
			this.active = this.hunks.pending_after(-1);
			this.active = this.active < 0 && this.hunks.size > 0 ? 0 : this.active;
			if (this.active >= 0) {
				this.source_view.navigate_to_line(this.hunks.get(this.active).scroll_line);
			}
			var pending = this.active >= 0
				&& this.hunks.get(this.active).decision == HunkDecision.PENDING;
			this.accept_btn.visible = pending;
			this.reject_btn.visible = pending;
			this.feedback_btn.visible = this.review_responses.size > 0;
			this.unapprove_btn.visible = false;
			this.map_width = 0;
			GLib.Idle.add_once(() => {
				this.on_width();
			});
		}
```

---

## LLM notes

- 🚫 Apply any fence from [`4.2.3.5.3`](done/CODER-4.2.3.5.3-SUPERSEDED-source-view-diff-part-rows.md).
- 🚫 A hunk file that stores the full project text.
- 🚫 A `hunk` column on `file_diff_part`. No `ALTER TABLE` for it.
- 🚫 Copy `rows` into a `Gee.ArrayList<GLib.Object>` before `val("o", …)`. `rows` is already that array.
- 🚫 `Differ` inside `parts`. A cache miss calls `rebuild_parts`.
- 🚫 No row until Accept or Reject. The items exist when the diff is shown.
- 🚫 Client `Differ`, and `RPC-File.read` of `backup_path`, inside `show_pending_diff`.
- 🚫 `RPC-File` rename in this plan. New calls use `OLLMfilesd-`. The hyphen joins the namespace and the class. The dot is only the method. `RPC-` stays for internal calls such as `RPC-Daemon.hello`.
- 🚫 Return `live` because the history id is present. The project file's modification stamp from that diff has to match `live_stamp`.
- 🚫 Delete the `file_diff_part` rows for a history and insert a new set inside `parts`. A stamp mismatch only refuses the remembered list. The rows stay. `Differ` sets `hunk` on them.
- ℹ️ [`4.2.3.5.7`](CODER-4.2.3.5.7-source-view-diff-resync.md) drops `FileHistory.live` and `FileHistory.live_stamp` for that history id when it replaces the rows.
- 🚫 A `@@` line-number header inside `hunk`. That text is the changed lines only.
- ℹ️ Touch points: `liboccoder/SourceView.vala` `show_pending_diff`, `liboccoder/Diff/ReviewBar.vala`, `ollmfilesd/FileDiffPart.vala`, `ollmfilesd/FileHistory.vala`, `libocfiles/Diff/Differ.vala`.
