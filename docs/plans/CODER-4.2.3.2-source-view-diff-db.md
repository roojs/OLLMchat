# 4.2.3.2 — SourceView diff Phase 1: DB + migrate

**Status:** **✔️** agent-done (awaiting user ✅)

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan.**

**Parent:** [`CODER-4.2.3-URGENT-source-view-diff.md`](CODER-4.2.3-URGENT-source-view-diff.md)

**Pointer:** `docs/guide-to-writing-plans.md` — Checklist for plans; proposed Vala follows **`docs/coding-standards.md`**

**Sibling:** walkthrough [`CODER-4.2.3.1`](CODER-4.2.3.1-source-view-diff-walkthrough-hello.md) · Phase 2 [`CODER-4.2.3.3`](CODER-4.2.3.3-source-view-diff-render.md)

---

## Purpose

- 🔷 ✔️ Rename **`file_history.status`** → **`reviewed`** (`0` open / `1` decided). Map old `status != 0` → `reviewed=1` (covers approve `1` and reject `-1`).
- 🔷 ✔️ Create **`file_diff_part`** child table (+ UNIQUE on `(file_history_id, part_index)`).
- 🔷 ✔️ Daemon row type **`FileDiffPart`** with query by parent id; named method **`path`** for the derived hunk-file path.
- 🔷 ✔️ Update whole-file approve / revert paths to set **`reviewed`** (no per-hunk RPC yet).
- 🔷 ✔️ Rename wire **`FileWithHistory.status`** → **`reviewed`** (daemon + client + `ReviewFiles`); SQL selects **`file_history.reviewed`** with no alias.

---

## Tasks

- 🔷 ✔️ `FileHistory` property + `init_db` CREATE + migrate ADD/UPDATE/DROP.
- 🔷 ✔️ `FileDiffPart` new file + `init_db` + meson + `ProjectManager` call.
- 🔷 ✔️ `FileHistory.approve` / `revert` + `File.approve` / `revert` use `reviewed`.
- 🔷 ✔️ `FileWithHistory.pending` SQL / wire property use `reviewed` (no `status` alias).

---

## Named methods (approved)

- 🔷 **`FileDiffPart.path(FileHistory history)`** — derived hunk file under `~/.cache/ollmchat/edited/parts/` (uses `history.path` for basename).
- 🔷 **`FileDiffPart.init_db(SQ.Database db)`** — CREATE `file_diff_part`.
- 🔷 **`FileDiffPart.query(SQ.Database db)`** — same pattern as `FileHistory.query`.

---

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `ollmfilesd/FileHistory.vala` — property `status` → `reviewed`

**Why:** Parent model — chunk open/closed only; accept/reject lives on parts.

**Where:** property block currently named `status` (~lines 108–116).

#### Remove

```vala
		/**
		 * User approval state (0 = pending, 1 = approved, -1 = rejected).
		 * - 0 = pending (not yet reviewed)
		 * - 1 = approved (user approved the change)
		 * - -1 = rejected (user rejected the change)
		 * 
		 * Note: Don't track "applied" or "restored" - status is just approval state.
		 */
		public int status { get; set; default = 0; }
```

#### Replace with

```vala
		/**
		 * Chunk review closed flag (0 = open, 1 = every hunk decided or whole-file done).
		 *
		 * Accept vs reject lives on {@link FileDiffPart.accepted} when parts exist.
		 * Whole-file approve/reject sets {@code reviewed=1} with no part rows.
		 */
		public int reviewed { get; set; default = 0; }
```

---

### 2. `ollmfilesd/FileHistory.vala` — `approve` pending filter + assign

**Where:** `approve` method.

#### Remove

```vala
			FileHistory.query(db).select(
				"WHERE path = '" + this.path.replace("'", "''") + "' AND status = 0",
				pending
			);
```

#### Replace with

```vala
			FileHistory.query(db).select(
				"WHERE path = '" + this.path.replace("'", "''") + "' AND reviewed = 0", pending);
```

#### Remove

```vala
			foreach (var row in pending) {
				row.status = 1;
				row.since_id = poke;
				FileHistory.query(db).updateById(row);
			}
```

#### Replace with

```vala
			foreach (var row in pending) {
				row.reviewed = 1;
				row.since_id = poke;
				FileHistory.query(db).updateById(row);
			}
```

---

### 3. `ollmfilesd/FileHistory.vala` — `revert` assigns

**Where:** `revert` — new revert row + closing this row.

#### Remove

```vala
			revert_history.status = 1;
```

#### Replace with

```vala
			revert_history.reviewed = 1;
```

#### Remove

```vala
			this.status = -1;
```

#### Replace with

```vala
			this.reviewed = 1;
```

---

### 4. `ollmfilesd/FileHistory.vala` — `init_db` CREATE + migrate

**Where:** entire `init_db` body after `string errmsg;`.

#### Remove

```vala
			var query = "CREATE TABLE IF NOT EXISTS file_history (" +
				"id INTEGER PRIMARY KEY, " +
				"path TEXT NOT NULL DEFAULT '', " +
				"filebase_id INT64 NOT NULL DEFAULT 0, " +
				"timestamp INT64 NOT NULL DEFAULT 0, " +
				"change_type TEXT NOT NULL DEFAULT '', " +
				"base_type TEXT NOT NULL DEFAULT '', " +
				"backup_path TEXT NOT NULL DEFAULT '', " +
				"status INTEGER NOT NULL DEFAULT 0, " +
				"since_id INT64 NOT NULL DEFAULT 0, " +
				"alias_target TEXT NOT NULL DEFAULT '', " +
				"moved_to TEXT NOT NULL DEFAULT '', " +
				"moved_from TEXT NOT NULL DEFAULT '', " +
				"agent_id INTEGER NOT NULL DEFAULT 0" +
				");";
			if (Sqlite.OK != db.db.exec(query, null, out errmsg)) {
				GLib.warning("Failed to create file_history table: %s", db.db.errmsg());
			}
			var migrate_since = "ALTER TABLE file_history ADD COLUMN since_id INT64 NOT NULL DEFAULT 0";
			if (Sqlite.OK != db.db.exec(migrate_since, null, out errmsg)) {
				if (!errmsg.contains("duplicate column name")) {
					GLib.debug("Migration note (may be expected): %s", errmsg);
				}
			}
```

#### Replace with

```vala
			var query = "CREATE TABLE IF NOT EXISTS file_history (" +
				"id INTEGER PRIMARY KEY, " +
				"path TEXT NOT NULL DEFAULT '', " +
				"filebase_id INT64 NOT NULL DEFAULT 0, " +
				"timestamp INT64 NOT NULL DEFAULT 0, " +
				"change_type TEXT NOT NULL DEFAULT '', " +
				"base_type TEXT NOT NULL DEFAULT '', " +
				"backup_path TEXT NOT NULL DEFAULT '', " +
				"reviewed INTEGER NOT NULL DEFAULT 0, " +
				"since_id INT64 NOT NULL DEFAULT 0, " +
				"alias_target TEXT NOT NULL DEFAULT '', " +
				"moved_to TEXT NOT NULL DEFAULT '', " +
				"moved_from TEXT NOT NULL DEFAULT '', " +
				"agent_id INTEGER NOT NULL DEFAULT 0" +
				");";
			if (Sqlite.OK != db.db.exec(query, null, out errmsg)) {
				GLib.warning("Failed to create file_history table: %s", db.db.errmsg());
			}
			var migrate_since = "ALTER TABLE file_history ADD COLUMN since_id INT64 NOT NULL DEFAULT 0";
			if (Sqlite.OK != db.db.exec(migrate_since, null, out errmsg)) {
				if (!errmsg.contains("duplicate column name")) {
					GLib.debug("Migration note (may be expected): %s", errmsg);
				}
			}
			var migrate_reviewed = "ALTER TABLE file_history ADD COLUMN reviewed INTEGER NOT NULL DEFAULT 0";
			if (Sqlite.OK != db.db.exec(migrate_reviewed, null, out errmsg)) {
				if (!errmsg.contains("duplicate column name")) {
					GLib.debug("Migration note (may be expected): %s", errmsg);
				}
			}
			if (Sqlite.OK != db.db.exec("UPDATE file_history SET reviewed = 1 WHERE status != 0",
				null, out errmsg)) {
				if (!errmsg.contains("no such column")) {
					GLib.debug("Migration note (may be expected): %s", errmsg);
				}
			}
			if (Sqlite.OK != db.db.exec("ALTER TABLE file_history DROP COLUMN status",
				null, out errmsg)) {
				if (!errmsg.contains("no such column")) {
					GLib.debug("Migration note (may be expected): %s", errmsg);
				}
			}
```

---

### 5. `ollmfilesd/File.vala` — `approve` / `revert` use `reviewed`

**Where:** `approve` foreach; `revert` revert_history + history close.

#### Remove

```vala
			// Update each FileHistory record to approved status
			foreach (var history in history_records) {
				history.status = 1;
				try {
					FileHistory.query(db).updateById(history);
				} catch (GLib.Error e) {
					GLib.warning("Failed to update FileHistory status: %s", e.message);
				}
			}
```

#### Replace with

```vala
			foreach (var history in history_records) {
				history.reviewed = 1;
				try {
					FileHistory.query(db).updateById(history);
				} catch (GLib.Error e) {
					GLib.warning("Failed to update FileHistory reviewed: %s", e.message);
				}
			}
```

#### Remove

```vala
			revert_history.status = 1;
```

#### Replace with

```vala
			revert_history.reviewed = 1;
```

#### Remove

```vala
			// Update FileHistory status to rejected (-1) using query wrapper
			history.status = -1;
			try {
				FileHistory.query(db).updateById(history);
			} catch (GLib.Error e) {
				GLib.warning("Failed to update FileHistory status: %s", e.message);
			}
```

#### Replace with

```vala
			history.reviewed = 1;
			try {
				FileHistory.query(db).updateById(history);
			} catch (GLib.Error e) {
				GLib.warning("Failed to update FileHistory reviewed: %s", e.message);
			}
```

ℹ️ Docblock text on `File.approve` / `File.revert` that still says `status` may be tightened in the same edit if touched; not required for compile.

---

### 6. `ollmfilesd/FileWithHistory.vala` — `pending` SQL + wire property

**Why:** Column rename; wire delta field is also **`reviewed`** (not aliased to `status`).

**Where:** property + SQL string in `pending`.

#### Remove — wire property

```vala
		public int status { get; set; default = 0; }
```

#### Replace with

```vala
		public int reviewed { get; set; default = 0; }
```

#### Remove

```vala
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
```

#### Replace with

```vala
	file_history.reviewed,
	(
		SELECT
			file_history.id
		FROM
			file_history
		WHERE
				file_history.filebase_id = filebase.id
			AND
				file_history.reviewed = 0
		ORDER BY
			file_history.timestamp DESC
		LIMIT 1
	) AS approve_id,
```

#### Remove

```vala
	(
		file_history.status != 0
		OR
		(
			file_history.status = 0
			AND
			filebase.is_need_approval = 1
		)
	)
```

#### Replace with

```vala
	(
		file_history.reviewed != 0
		OR
		(
			file_history.reviewed = 0
			AND
			filebase.is_need_approval = 1
		)
	)
```

---

### 6b. `libocfiles/FileWithHistory.vala` + `ReviewFiles.vala` — wire rename

**Why:** Client must match daemon wire property name.

#### Remove — client property

```vala
		public int status { get; set; default = 0; }
```

#### Replace with

```vala
		public int reviewed { get; set; default = 0; }
```

#### Remove — `ReviewFiles.refresh`

```vala
					if (file.status != 0) {
						if (!this.file_map.has_key(file.path)) {
							continue;
						}
						this.remove(this.file_map.get(file.path));
						continue;
					}
					if (this.file_map.has_key(file.path)) {
						var existing = this.file_map.get(file.path);
						existing.last_change_type = file.last_change_type;
						existing.last_modified = file.last_modified;
						existing.approve_id = file.approve_id;
						existing.reject_id = file.reject_id;
						existing.status = 0;
						continue;
					}
```

#### Replace with

```vala
					if (file.reviewed != 0) {
						if (!this.file_map.has_key(file.path)) {
							continue;
						}
						this.remove(this.file_map.get(file.path));
						continue;
					}
					if (this.file_map.has_key(file.path)) {
						var existing = this.file_map.get(file.path);
						existing.last_change_type = file.last_change_type;
						existing.last_modified = file.last_modified;
						existing.approve_id = file.approve_id;
						existing.reject_id = file.reject_id;
						existing.reviewed = 0;
						continue;
					}
```

---

### 7. `ollmfilesd/FileDiffPart.vala` — **Add** (new file)

**Why:** Child rows for per-hunk decisions (Phase 4 writes; Phase 1 schema + read path).

#### Add — new file `ollmfilesd/FileDiffPart.vala` (create entire file)

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
```

---

### 8. `ollmfilesd/meson.build` — list `FileDiffPart.vala`

**Where:** `ollmfilesd_src = files(` after `FileHistory.vala`.

#### Add — after `'FileHistory.vala',`

```vala
  'FileDiffPart.vala',
```

ℹ️ Meson `files()` entries are strings — use the same quoting style as neighbours (`'FileDiffPart.vala',`).

---

### 9. `ollmfilesd/ProjectManager.vala` — call `FileDiffPart.init_db`

**Where:** next to `FileHistory.init_db(this.db);`.

#### Add — immediately after `FileHistory.init_db(this.db);`

```vala
				FileDiffPart.init_db(this.db);
```

---

## LLM notes

- 🚫 Per-hunk approve/reject RPC or SourceView changes (Phases 2–4).
- 🚫 Keep wire **`FileWithHistory.status`** / `AS status` alias — rename to **`reviewed`** end-to-end.
- 🚫 `file_approval_batch`, `seq`, line-range columns, or `filebase_id` on the child table.
- 🚫 New methods beyond **`path`**, **`init_db`**, **`query`** named above.
