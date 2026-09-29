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
- 🔷 A hunk stores the removed lines and the added lines separately. `hunk_remove` and `hunk_add`. Neither string has a `+` or `-` on each line.
- 🔷 The line range is on the object. Counts come from that range. Nothing scans the lines to find out how many there are.
- 🔷 `FileDiffPart.compare` takes another file part and returns an int. `0` neither. `1` line numbers only. `2` checksum only. `3` both.
- 🔷 `checksum` is a column on `file_diff_part`. `compare` uses it instead of `hunk_remove` and `hunk_add`.
- 🔷 `FileDiffPart.update_sum` sets `checksum` from that part's `hunk_remove` and `hunk_add`.
- 💩 The checksum is SHA256 of `hunk_remove`, a NUL byte, then `hunk_add`.
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
                                  ←  those objects, remove and add text on each
  hang the text on the in-memory item
  paint from that array
  backup stays on the daemon           (no wire)
```

- 🔷 The diff item contains `hunk_remove` and `hunk_add`. Those strings are properties on the object. They go down the wire with the item.
- 🔷 The file server writes the items to disk. `hunk_remove` and `hunk_add` are not in that row. A later open sets the text on the object and returns it.
- 🔷 The client hangs that text on the diff item in memory. The client does not write diff items.
- 🔷 The `parts` request answers the client. The diff itself is `FileHistory.rebuild_parts`. That method is not the request.
- 🔷 `rebuild_parts` reads the cache backup and the project file. No rows yet: `Differ`, insert one row per patch, set `hunk_remove`, `hunk_add`, and the line range on the objects, remember those objects, return them.
- 🔷 The diff is the project file now against that history's backup. The history id alone does not make a remembered list current.
- 🔷 A later `parts` returns the remembered objects only when the project file's modification stamp still equals the stamp captured when that list was diffed. `hunk_remove` and `hunk_add` are already on them.
- 🔷 That stamp is the project file's modification time in microseconds, read from the file at diff time.
- 🔷 A different stamp does not return that list. `parts` calls `rebuild_parts`.
- 🔷 Keep or remove is the bullet list above `rebuild_parts`.
- 🔷 `show_pending_diff` does not call `RPC-File.read` on `backup_path`.
- ℹ️ `file_diff_part` today has no hunk text. `ollmfilesd/FileDiffPart.vala`. The daemon cannot link `libocfiles`.
- 🔷 The review diff runs on the file server. If that is the only user, `Differ` / `Patch` / `PatchApplier` move out of `libocfiles` into `ollmfilesd`.
- ℹ️ Still compiled against `libocfiles/Diff` today: `liboccoder/SourceView.vala` `show_diff`, `liboccoder/Diff/ReviewBar.vala` (`HunkBand`, `update_diff(Differ)`), `examples/oc-diff.vala`, `examples/oc-test-source-diff.vala`. `PatchApplier` has no caller.
- 🔷 Those callers are the old path. They are deprecated.
- 💩 This phase still symlinks `libocfiles/Diff` into `ollmfilesd`, same as `Copyable.vala`. Moving the files now would fork the algorithm or break `show_diff` and the examples. The move waits until those callers are gone.
- 🔷 The table is already `file_diff_part`. `hunk_remove` and `hunk_add` are properties on `FileDiffPart`, not columns. Not a new table, and not `edited/parts/…patch`.
- 🔷 `accepted` `0` is undecided. `1` accepted. `-1` rejected. Same values as the old `file_history.status`. A row exists before anyone decides.
- ℹ️ Today’s comment says the opposite: no row means pending, and `accepted` `0` means reject. Nothing writes `file_diff_part` yet, and the column default is already `0`, so `0` becomes undecided. Reject is `-1`.
- ℹ️ `HunkDecision` in the bar is a separate enum. Its third value is not the stored reject.
- 🔷 `OLLMfilesd-FileHistory.parts` takes the `file_history` id. `FileWithHistory.approve_id` is that same id on the pending-list row. It is not a separate argument.
- 🔷 `hunk_remove` is the removed lines. `hunk_add` is the added lines. No `+` or `-` prefix. No `@@` header. Line numbers are not inside those strings.
- 🔷 The range is `old_line_start`, `old_line_end`, `new_line_start`, `new_line_end`. A count is `end - start + 1` when `end >= start`, otherwise `0`.
- 💩 Those four ints are properties on the object, not columns. A removal has no place in the current file, so the editor still needs the old range.
- 🔷 `show_pending_diff` calls `parts` and paints from that array. It does not read the backup and it does not run `Differ`.

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify surrounding context before applying.

### 1. `ollmfilesd/FileDiffPart.vala` — remove and add on the object, undecided is `0`

**Why:** The row is `file_diff_part`. It exists before a decision. `hunk_remove` and `hunk_add` are on the object for the wire. They are not columns. `checksum` is a column. `compare` uses it instead of the hunk strings. `compare` returns `0`, `1`, `2`, or `3`. No result class.

**Where:** class docblock and properties, then `compare` after `decided_at` and before `path`. `init_db` gains the `checksum` column.

**Depends on:** none. `compare` takes another `FileDiffPart`.

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
```

#### Remove — `init_db` create string

The table already exists on databases created before `checksum`. `CREATE TABLE IF NOT EXISTS` does not add a column. The `ALTER` matches `file_history`.

```vala
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
```

#### Replace with

```vala
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

**Why:** `parts` runs `Differ` on the daemon. `ollmfilesd/meson.build` bans linking `libocfiles`. `Copyable.vala` is already a symlink of an `OLLMfiles` source into this binary. The long-term home is `ollmfilesd` once the deprecated callers listed above are gone. This phase does not move the files.

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

Remembered objects for this process. `hunk_remove` and `hunk_add` stay on them. The table does not store them. `live_stamp` is the project file's modification time in microseconds when that list was diffed.

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

Looking at one file. The backup and the project file are the two texts. `Differ` makes the new parts. The stored rows are the old parts. `compare` is how a new part is checked against an old one.

- 🔷 No stored rows. Insert one row per new part. Set `hunk_remove`, `hunk_add`, and the line range. Do not write those strings into the table. Remember the list with the file stamp. Return it.
- 🔷 Stored rows are indexed by start line.
- 💩 That key is `old_line_start`. A pure add still has that anchor on the backup.
- 🔷 The pass walks the file by the line range. Removed lines are `hunk_remove`. Added lines are the new-file range.
- 🔷 At each new part, `compare` it to the old part at that start line.
- 🔷 Return `3`. Keep that stored row. The decision stays. Drop that old part out of the leftover set.
- 🔷 Every old part returns `3`. The leftover set is empty. Nothing is added or removed.
- 💩 Return `1`. Same lines, different checksum. Write the new `hunk_remove` and `hunk_add`, then `update_sum`. Clear `accepted` and `decided_at`.
- 💩 Return `2`. Same checksum, different lines. Keep the row and the decision. Write the new line range on the object.
- 💩 Return `0`. Neither matches. Delete that stored row. Insert the new part. `accepted` stays `0`.
- 💩 A new part with no old part at that start. Insert a row. `accepted` stays `0`.
- 💩 An old part whose start line is not among the new parts. Delete that row.
- ℹ️ `hunk_remove` and `hunk_add` are not columns. A part from the table does not have them. The old parts are the remembered list, which still has the text.

```vala
		/**
		 * Build the diff items for one history row.
		 *
		 * Reads the backup and the project file, then runs
		 * {@link OLLMfiles.Diff.Differ}. No stored rows: insert
		 * one part per patch. Stored rows are indexed by
		 * ''old_line_start'' and checked with
		 * {@link FileDiffPart.compare}. ''3'' keeps the row.
		 * ''1'' replaces the hunk text and clears the decision.
		 * ''2'' keeps the decision and writes the new line range.
		 * ''0'' deletes that row and inserts the new part.
		 * A stored part with no new part at its start line is
		 * deleted. Old parts come from the remembered list.
		 * A load from the table does not have the hunk text.
		 * Does not write the hunk strings into the table.
		 *
		 * @param history the file_history row to diff
		 * @return the parts to paint, in file order
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
			var fresh = new Gee.ArrayList<FileDiffPart>();
			var index = 0;
			foreach (var patch in patches) {
				var part = new FileDiffPart() {
					file_history_id = history.id,
					part_index = index,
					hunk_remove = string.joinv("\n", patch.old_lines()),
					hunk_add = string.joinv("\n", patch.new_lines()),
					old_line_start = patch.old_line_start,
					old_line_end = patch.old_line_end,
					new_line_start = patch.new_line_start,
					new_line_end = patch.new_line_end
				};
				part.update_sum();
				fresh.add(part);
				index++;
			}
			if (rows.size == 0) {
				foreach (var part in fresh) {
					FileDiffPart.query(this.rpc_manager.db).insert(part);
				}
				this.live.set(history.id, fresh);
				this.live_stamp.set(history.id, stamp);
				return fresh;
			}
			if (this.live.has_key(history.id) && this.live.get(history.id).size > 0) {
				rows = this.live.get(history.id);
			}
			var next_index = rows.get(rows.size - 1).part_index + 1;
			var older = new Gee.HashMap<int, FileDiffPart>();
			foreach (var part in rows) {
				older.set(part.old_line_start, part);
			}
			var kept = new Gee.ArrayList<FileDiffPart>();
			foreach (var part in fresh) {
				if (!older.has_key(part.old_line_start)) {
					part.part_index = next_index;
					next_index++;
					FileDiffPart.query(this.rpc_manager.db).insert(part);
					kept.add(part);
					continue;
				}
				var old = older.get(part.old_line_start);
				older.unset(part.old_line_start);
				switch (old.compare(part)) {
					case 3:
						kept.add(old);
						break;

					case 1:
						old.hunk_remove = part.hunk_remove;
						old.hunk_add = part.hunk_add;
						old.update_sum();
						old.accepted = 0;
						old.decided_at = 0;
						FileDiffPart.query(this.rpc_manager.db).updateById(old);
						kept.add(old);
						break;

					case 2:
						old.old_line_end = part.old_line_end;
						old.new_line_start = part.new_line_start;
						old.new_line_end = part.new_line_end;
						kept.add(old);
						break;

					default:
						FileDiffPart.query(this.rpc_manager.db).deleteId(old.id);
						part.part_index = next_index;
						next_index++;
						FileDiffPart.query(this.rpc_manager.db).insert(part);
						kept.add(part);
						break;
				}
			}
			foreach (var old in older.values) {
				FileDiffPart.query(this.rpc_manager.db).deleteId(old.id);
			}
			this.live.set(history.id, kept);
			this.live_stamp.set(history.id, stamp);
			return kept;
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
	 * {@code hunk_remove} and {@code hunk_add} are the changed lines.
	 * No '+' or '-' prefix. No line numbers in those strings.
	 * {@code accepted} is 0 undecided, 1 accepted, -1 rejected.
	 * {@code compare} is on the file-server part. It takes another
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
		 * Removed lines from {@code parts}. No '-' prefix.
		 */
		public string hunk_remove { get; set; default = ""; }

		/**
		 * Added lines from {@code parts}. No '+' prefix.
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
				var add_count = part.new_line_end < part.new_line_start ? 0 : part.new_line_end - part.new_line_start + 1;
				var remove_count = part.old_line_end < part.old_line_start ? 0 : part.old_line_end - part.old_line_start + 1;
				while (new_i < part.new_line_start && new_i <= editor_lines.length) {
					display.add(editor_lines[new_i - 1]);
					this.diff_baseline.add(new_i);
					kinds.add(0);
					new_i++;
				}
				if (remove_count > 0 && part.hunk_remove != "") {
					this.diff_remove_at.add(part.new_line_start);
					this.diff_remove_n.add(remove_count);
					var removed = part.hunk_remove.split("\n");
					for (var r = 0; r < remove_count && r < removed.length; r++) {
						display.add(removed[r]);
						this.diff_baseline.add(0);
						kinds.add(2);
					}
				}
				if (add_count == 0) {
					if (part.new_line_start > new_i) {
						new_i = part.new_line_start;
					}
					continue;
				}
				for (var ln = part.new_line_start; ln < part.new_line_start + add_count && ln <= editor_lines.length; ln++) {
					display.add(editor_lines[ln - 1]);
					this.diff_baseline.add(ln);
					kinds.add(1);
				}
				new_i = part.new_line_start + add_count;
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

Bands from the line range. `accepted` 0 is pending, 1 accepted, -1 rejected. The count is `end - start + 1`. No scan of `hunk_remove` or `hunk_add`.

```vala
		/**
		 * Paint hunk bands from {@code OLLMfilesd-FileHistory.parts}.
		 *
		 * Keeps {@code parts} so the hunk text stays on the client.
		 *
		 * @param parts diff items, remove and add text on each
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
				var old_count = part.old_line_end < part.old_line_start ? 0 : part.old_line_end - part.old_line_start + 1;
				var new_count = part.new_line_end < part.new_line_start ? 0 : part.new_line_end - part.new_line_start + 1;
				var op = OLLMfiles.Diff.PatchOperation.REPLACE;
				if (old_count == 0) {
					op = OLLMfiles.Diff.PatchOperation.ADD;
				}
				if (old_count > 0 && new_count == 0) {
					op = OLLMfiles.Diff.PatchOperation.REMOVE;
				}
				var patch = new OLLMfiles.Diff.Patch(
					op, part.old_line_start, part.old_line_end,
					part.new_line_start, part.new_line_end,
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
- 🚫 A `hunk`, `hunk_remove`, or `hunk_add` column on `file_diff_part`. No `ALTER TABLE` for them.
- 🚫 Copy `rows` into a `Gee.ArrayList<GLib.Object>` before `val("o", …)`. `rows` is already that array.
- 🚫 `Differ` inside `parts`. A cache miss calls `rebuild_parts`.
- 🚫 No row until Accept or Reject. The items exist when the diff is shown.
- 🚫 Client `Differ`, and `RPC-File.read` of `backup_path`, inside `show_pending_diff`.
- 🚫 `RPC-File` rename in this plan. New calls use `OLLMfilesd-`. The hyphen joins the namespace and the class. The dot is only the method. `RPC-` stays for internal calls such as `RPC-Daemon.hello`.
- 🚫 Return `live` because the history id is present. The project file's modification stamp from that diff has to match `live_stamp`.
- 🚫 Delete every `file_diff_part` row for a history and insert a new set. `rebuild_parts` deletes a row only when `compare` says so. A return of `3` keeps that row.
- 🚫 Delete a row because `hunk_remove` and `hunk_add` are empty. Those strings are not columns. A load from the table always looks empty.
- ℹ️ [`4.2.3.5.7`](CODER-4.2.3.5.7-source-view-diff-resync.md) calls the same `rebuild_parts` after save. That writes `live` and `live_stamp` for the kept parts.
- 🚫 A `+` or `-` prefix on hunk lines, and a `@@` line-number header inside `hunk_remove` or `hunk_add`.
- 🚫 Move `libocfiles/Diff` into `ollmfilesd` in this phase. Symlink until `show_diff`, `ReviewBar`'s `Differ` / `Patch` API, and the two examples are gone.
- 💩 `ReviewBar.update_diff` still builds an `OLLMfiles.Diff.Patch` so `HunkBand` can take one. That is the deprecated client use. The counts come from the range.
- ℹ️ Touch points: `liboccoder/SourceView.vala` `show_pending_diff`, `liboccoder/Diff/ReviewBar.vala`, `ollmfilesd/FileDiffPart.vala`, `ollmfilesd/FileHistory.vala`, `libocfiles/Diff/Differ.vala`.
