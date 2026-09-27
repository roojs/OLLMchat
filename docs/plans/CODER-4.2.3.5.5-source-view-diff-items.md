# 4.2.3.5.5 — Diff items on the wire

**Status:** **⏳** proposed — row and list-call fences below. Differ-when-empty is not fenced yet.

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

- 🔷 The file server stores one diff item per hunk, hunk text included, and sends that array down the wire.
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
                                  ←  those rows, hunk text on each
  hang the text on the in-memory item
  paint from that array
  backup stays on the daemon           (no wire)
```

- 🔷 The diff item contains the hunk text. That text goes down the wire with the item.
- 🔷 The file server writes the items to disk. A later open returns the active items, hunk text included.
- 🔷 The client hangs that text on the diff item in memory. The client does not write diff items.
- 🔷 `Differ` runs on `ollmfilesd`, and only when this history has no stored items yet. Inputs are the cache backup and the project file.
- 🔷 `show_pending_diff` does not call `RPC-File.read` on `backup_path`.
- ℹ️ `file_diff_part` today has no hunk text. `ollmfilesd/FileDiffPart.vala`. The daemon cannot link `libocfiles`, so `Differ` still has to be built into `ollmfilesd` the same way `Copyable.vala` is symlinked.
- 🔷 The table is already `file_diff_part`. The hunk text is a `hunk` column on that row. Not a new table, and not `edited/parts/…patch`.
- 🔷 `accepted` `0` is undecided. `1` accepted. `-1` rejected. Same values as the old `file_history.status`. A row exists before anyone decides.
- ℹ️ Today’s comment says the opposite: no row means pending, and `accepted` `0` means reject. Nothing writes `file_diff_part` yet, and the column default is already `0`, so `0` becomes undecided. Reject is `-1`.
- ℹ️ `HunkDecision` in the bar is a separate enum. Its third value is not the stored reject.
- 🔷 `OLLMfilesd-FileHistory.parts` takes the `file_history` id. `FileHistory` loads `file_diff_part` for that id. `FileWithHistory.approve_id` is that same id on the pending-list row. It is not a separate argument.
- 💩 When that list is empty, `parts` still runs `Differ` and stores the rows. That body is not fenced yet.

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify surrounding context before applying.

### 1. `ollmfilesd/FileDiffPart.vala` — hunk text, undecided is `0`

**Why:** The row is `file_diff_part`. It exists before a decision, and it carries the hunk text.

**Where:** class docblock and properties. `init_db` create string, then an `ALTER` after the create `exec`, same pattern as `file_history.reviewed`.

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
	 * One hunk on a {@link FileHistory} write, including its hunk text.
	 *
	 * The row is stored when the diff is shown, before anyone decides.
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
		public string hunk { get; set; default = ""; }
		public int accepted { get; set; default = 0; }
		public int64 decided_at { get; set; default = 0; }
```

#### Remove

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
				"hunk TEXT NOT NULL DEFAULT '', " +
				"accepted INTEGER NOT NULL DEFAULT 0, " +
				"decided_at INT64 NOT NULL DEFAULT 0, " +
				"UNIQUE (file_history_id, part_index)" +
				");";
			if (Sqlite.OK != db.db.exec(query, null, out errmsg)) {
				GLib.warning("Failed to create file_diff_part table: %s", db.db.errmsg());
			}
			var migrate_hunk = "ALTER TABLE file_diff_part ADD COLUMN hunk TEXT NOT NULL DEFAULT ''";
			if (Sqlite.OK != db.db.exec(migrate_hunk, null, out errmsg)) {
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

### 3. `ollmfilesd/FileHistory.vala` — `parts` loads `file_diff_part`

**Why:** The list call’s argument is the `file_history` id. `FileHistory` reads `file_diff_part` for that id.

**Where:** `rpc_register` gains the `OLLMfilesd-FileHistory` class. `parts` is a new method after `for_rpc`. The reviewed-flag comment above `reviewed` is the old “no row means pending” wording.

**Depends on:** §1.

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

#### Add — new method `parts` after `for_rpc`.

Returns the stored `file_diff_part` rows for that history id. Does not run `Differ`.

```vala
		/**
		 * Stored diff hunks for one {@code file_history} row.
		 *
		 * @param request inbound RPC
		 * @param id {@code file_history.id}
		 */
		public void parts(OLLMrpc.Request request, int64 id)
		{
			var rows = new Gee.ArrayList<FileDiffPart>();
			FileDiffPart.query(this.rpc_manager.db).select(
				"WHERE file_history_id = %lld ORDER BY part_index".printf(id),
				rows
			);
			var list = new Gee.ArrayList<GLib.Object>();
			foreach (var row in rows) {
				list.add(row);
			}
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				retval = OLLMrpc.val("o", list)
			});
		}
```

### 4. `ollmfilesd/Application.vala` — dispatch `OLLMfilesd-FileHistory`

**Why:** `add_class` names the method. `Request.register` binds the live `FileHistory` that handles it. One instance serves both names.

**Where:** the existing `Request.register("RPC-FileHistory", …)` call.

**Depends on:** §3.

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

---

## LLM notes

- 🚫 Apply any fence from [`4.2.3.5.3`](done/CODER-4.2.3.5.3-SUPERSEDED-source-view-diff-part-rows.md).
- 🚫 A hunk file that stores the full project text.
- 🚫 No row until Accept or Reject. The items exist when the diff is shown.
- 🚫 Client `Differ` on the backup body.
- 🚫 `RPC-File` rename in this plan. New calls use `OLLMfilesd-`. The hyphen joins the namespace and the class. The dot is only the method. `RPC-` stays for internal calls such as `RPC-Daemon.hello`.
- ℹ️ Touch points: `liboccoder/SourceView.vala` `show_pending_diff`, `ollmfilesd/FileDiffPart.vala`, `ollmfilesd/FileHistory.vala`, `libocfiles/Diff/Differ.vala`.
