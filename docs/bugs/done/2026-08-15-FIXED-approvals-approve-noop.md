# Approve / Reject click does not clear pending buttons

**Status:** ✅ FIXED — user verified 2026-08-15 (approval stuff working)

**Started:** 2026-08-15

**Related:** [`2026-08-15-FIXED-approvals-click-no-approve-reject.md`](2026-08-15-FIXED-approvals-click-no-approve-reject.md) (buttons now show)

---

## Problem

🔷 Approve / Reject now appear. Clicking them **does not appear to do anything**.

🔷 After a successful approve, the file should leave the changed list and the buttons should hide.

---

## Evidence

✔️ Live click 08:51:41 (`~/.cache/ollmchat/ollmchat.debug.log` / `ollmfilesd.debug.log`):

- Client `FileHistory.approve` **id=9** → daemon `call_approve` → reply **ok** in ~1ms
- Client immediately `Folder.fetch_pending_approvals` **id=10** → reply
- No RPC error

✔️ SQLite **after** that click — **nothing changed**:

- `file_history` 370 / 371 still `status=0`, `since_id=0`
- `filebase` 110749 / 110750 still `is_need_approval=1` (same path `docs/Hello World Test`)
- `MAX(since_id)` still `0` (approve never poked)

✔️ Same path has older `filebase` **110732** with `is_text=1`, `is_need_approval=0` (the row `child_map` can hold). Pending rows are **110749 / 110750** with `is_text=0`.

ℹ️ Daemon `FileHistory.approve` RPC (`ollmfilesd/FileHistory.vala`): `get_file_from_active_project(path)` → `project_files.child_map` (text files only) → `rows.get(0).approve(db, file)` uses **`file.id`** for `WHERE filebase_id = …`.

ℹ️ Client `on_approve_clicked` ignores the RPC result body; `review_files.refresh` then `on_active_file_changed` re-selects the path if it is still in `file_map` → buttons stay.

ℹ️ Reject on this file (`change_type=added`): daemon `revert` replies **Cannot revert added files**. Client `FileHistory.revert` returns on `response.error` then still refreshes. Separate from the approve no-op.

---

## Root cause

✔️ Approve RPC looks up the **index** `File` by path (`child_map`), then flips history for **`file.id`**. That id is the old text row (110732), which has **no** pending history. The client sent `approve_id` 370 / 371 (`filebase_id` 110749 / 110750). Those rows are never updated. Handler still replies `ok`.

✔️ Refresh therefore still sees the path as pending. `on_active_file_changed` selects it again. Buttons stay.

🚫 Not a UI visibility bug in Approvals (that was the previous log). Hiding buttons locally without flipping history would leave the file on the next startup list.

---

## Proposed fix

🔷 Approve the **file** (path): every pending `file_history` row for that path (`status=0` → `1`, poke `since_id`), and every `filebase` row for that path (`is_need_approval=0`). Duplicate filebase ids for Hello World are included.

🔷 Keep `file.is_need_approval = false` + `file.saveToDB` so the in-memory `child_map` object stays in sync.

💩 Reject for **added** files: daemon already refuses. Not this patch.

### 1. `ollmfilesd/FileHistory.vala` — `approve`: all pending history + filebase rows for `this.path`

**Why:** User approves the file, not one `filebase_id`. `file.id` from `child_map` can be a different duplicate and left real pending rows untouched.

**Where:** `approve(SQ.Database db, File file)` body.

**Depends on:** none.

#### Remove
```vala
		public void approve(SQ.Database db, File file)
		{
			var pending = new Gee.ArrayList<FileHistory>();
			FileHistory.query(db).select((
					"WHERE filebase_id = %lld AND status = 0  AND timestamp <= %lld"
				).printf(
					file.id,
					this.timestamp
				),
				pending
			);
			var max_stmt = FileHistory.query(db).selectPrepare(
				"SELECT MAX(id) FROM file_history"
			);
			var max_ids = FileHistory.query(db).fetchAllInt64(max_stmt);
			var poke = (max_ids.size > 0 ? max_ids.get(0) : (int64) 0) + 1;
			foreach (var row in pending) {
				row.status = 1;
				row.since_id = poke;
				FileHistory.query(db).updateById(row);
			}
			file.is_need_approval = false;
			file.last_change_type = "";
			file.saveToDB(db, null, false);
		}
```

#### Replace with
```vala
		public void approve(SQ.Database db, File file)
		{
			var pending = new Gee.ArrayList<FileHistory>();
			FileHistory.query(db).select(
				"WHERE path = '" + this.path.replace("'", "''") + "' AND status = 0",
				pending
			);
			var max_stmt = FileHistory.query(db).selectPrepare(
				"SELECT MAX(id) FROM file_history"
			);
			var max_ids = FileHistory.query(db).fetchAllInt64(max_stmt);
			var poke = (max_ids.size > 0 ? max_ids.get(0) : (int64) 0) + 1;
			foreach (var row in pending) {
				row.status = 1;
				row.since_id = poke;
				FileHistory.query(db).updateById(row);
			}
			var targets = new Gee.ArrayList<FileBase>();
			FileBase.query(db, file.manager).select(
				"WHERE path = '" + this.path.replace("'", "''") + "'",
				targets
			);
			foreach (var target in targets) {
				target.is_need_approval = false;
				target.last_change_type = "";
				target.saveToDB(db, null, false);
			}
			file.is_need_approval = false;
			file.last_change_type = "";
			file.saveToDB(db, null, false);
		}
```

---

## Attempts / changelog

- ✔️ 2026-08-15 — User: buttons show; Approve/Reject click does nothing.
- ✔️ 2026-08-15 — Live approve RPC ok; SQLite status/since_id/need-approval unchanged.
- ✔️ 2026-08-15 — `file.id` from `child_map` (110732) ≠ history `filebase_id` (110749/110750).
- ✔️ 2026-08-15 — User: approve all historical changes for the file. Applied path-wide history + filebase update.

## Next

✅ Closed 2026-08-15 — user verified approve/reject clears pending UI.
