# Changed-files notification → Approvals icon / open in editor

**Status:** ⏳ OPEN — **`since_id` marker sync applied** ✔️; await user re-test / ✅

**Started:** 2026-08-12 · **Updated:** 2026-08-13

---

## Problem

🔷 Create a Hello World file under the project **`docs/`** directory **via our API** (`File.write` / tools that call it — not a raw disk copy). Expected end-to-end:

1. **Daemon** creates a pending-approval record for that file.
2. **Backend → frontend notification** that the changed-file list should refresh.
3. **Approvals control** (top-right header, next to save) becomes visible / clickable and shows the pending file(s).
4. Selecting a row **opens that file in the editor** (`SourceView`).

🔷 **Actual (user smoke):** Approvals icon / list did not reflect the new file.

🔷 Scope is the **API create → notify → Approvals → open** path.  
🚫 Not about manually copying a file onto disk outside the API (agent misread that earlier as “external drop”).

---

## Reproduction

1. Open app with a project that has a `docs/` tree.
2. Create a small Hello World file under `docs/` **through the API** (`File.write` / write_file tool / equivalent).
3. Watch header Approvals control and daemon→client notifications.
4. **Expected:** pending list updates; icon usable; click opens file in editor.
5. **Actual:** no observed Approvals update for that file.

---

## Related

ℹ️ Approvals UI + `ReviewFiles` refresh on `event.project.invalidate_cache`:

- `liboccoder/Approvals.vala` — `rpc.notification` → `review_files.refresh.begin()` when method is `event.project.invalidate_cache`
- `liboccoder/SourceView.vala` — same notification refreshes file dropdown; `approvals.file_selected` → `open_file`
- Daemon emit: `ollmfilesd/File.vala` (`File.write` / `to_real`) — `event.project.invalidate_cache`

ℹ️ Pending list RPC: `Folder.fetch_pending_approvals` → client `libocfiles/ReviewFiles.vala`

ℹ️ Prior related: [`2026-07-27-write-file-no-project-index-ui.md`](2026-07-27-write-file-no-project-index-ui.md)

ℹ️ Editor open: `Approvals.update_selected_file()` only emits `file_selected` if `file_cache.get(row.path)` is non-null.

---

## Hypotheses

💩 **H1 — Daemon never creates a pending-approval record on API write.**  
✔️ Probe A (clean interactive `File.write`): **does** create the record.  
✔️ Live ~19:28 write tool to `docs/Hello World Test`: **did not** — `is_need_approval=0`, no `file_history`. H1 still open for this path.

💩 **H2 — Record exists, but live app never gets / never acts on the notify** (`event.project.invalidate_cache` → Approvals refresh).  
✔️ Live run: client never saw `invalidate_cache`; Approvals debug never fired. May be because daemon never emitted (tied to H1) — not a separate Approvals bug yet.
💩 **H3 — Notify handled, but Approvals / `ReviewFiles` refresh still wrong** (empty list, wrong project path, etc.).  
⏳ After H2.

💩 **H4 — List OK, open broken:** row visible but `file_cache` miss blocks editor open.  
⏳ After list works.

---

## Evidence

### Probe A — API `File.write` creates approval ✔️

Tool: `build/ollmfilesd/ollmfilesd --interactive --rpc-script=…`

1. `ProjectManager.create_project` + `activate_project`
2. `File.write` → `docs/hello-via-write.txt`
3. `Folder.fetch_pending_approvals`

**Result** (`/tmp/ollm-approval-probe-wIdN`):

- Write: `msg: ok`
- Pending: one `FileWithHistory`, `last-change-type: added`, `approve-id: 1`
- SQLite: `is_need_approval=1`, `file_history` `added` / `status=0`
- Notification: `event.project.invalidate_cache` with project path

→ Step 1 of the expected chain works at the daemon/API layer.

### Live app run 2026-08-13 ~19:28 — write tool → `docs/Hello World Test` ✔️

Agent Pi `write` / edit_mode complete_file. Disk file exists (`Hello World`, 12 bytes).

**Client** (`~/.cache/ollmchat/ollmchat.debug.log`):

| Time | Event |
|------|--------|
| 19:28:12 | `id=15 method=File.write` |
| 19:28:19 | `replied id=15` |
| 19:28:19 | `id=16 method=File.register` → replied |
| 19:28:20 | EditMode: `Successfully applied changes to file …/docs/Hello World Test` |
| 19:28:20 | `Folder.fetch_pending_approvals` (tool-driven `review_files.refresh`) |
| 19:28:20 | **`review_files refresh done old=0 new=0`** |

- ✔️ **No** client line `notification method=event.project.invalidate_cache` (entire log count **0**)
- ✔️ **No** Approvals line `invalidate_cache received…` (count **0**) — handler never ran
- ✔️ Refresh that did run was from the **write tool** after apply, not from Approvals notify — and pending list was **empty**

**Daemon:** `File.write` / `File.register` recv+reply only; no useful approval debug on that path.

**SQLite** (`files.sqlite`): path `/home/alan/gitlive/OLLMchat/docs/Hello World Test` has **six** `filebase` rows; all **`is_need_approval=0`**, empty `last_change_type`. **No** `file_history` rows for that path. Global `is_need_approval=1` count = **0**.

→ Unlike isolated Probe A, this production write **did not** leave a pending-approval record, so fetch correctly returned empty. Notify→Approvals never got a chance: **`invalidate_cache` never arrived** on the client.

💩 **H1 reopened for the live write/register path** (Probe A still true for clean interactive `File.write`). Likely `to_real` / modified-approval branch not applying here (duplicate rows / existing id / early return) — needs daemon-side debug next.

ℹ️ **Test-suite gap / reproduction status (2026-08-13 evening):**

Tried to reproduce live empty-pending in `ollmfilesd --rpc-script` (same binary as `build/ollmfilesd/ollmfilesd`):

| Probe | Setup | Pending after write→register? | `invalidate_cache`? |
|-------|--------|-------------------------------|---------------------|
| A | New path under `docs/` | yes (often **2** duplicate rows) | yes |
| B | Rewrite existing `hello.txt` | yes | yes |
| E | `skip_scan` then new path | yes | yes |
| G/H | Pre-seed zero-approval / duplicate rows then write | yes (new/updated rows); stale duplicates can remain at 0 | yes |

→ **Harness cannot yet reproduce** live `new=0` / no history / no client `invalidate_cache`. Live failure needs another precondition (or a non-RPC layer) we have not captured. Suite still lacks an assertion for pending+notify on the app write→register flow; adding that test now would **pass** and would not red-fail like production.

---

### Live DB + FS with **new** binary (2026-08-13 ~19:42) ✔️

Copied `~/.local/share/ollmchat/files.sqlite` → temp `--data-dir`, project path = real `/home/alan/gitlive/OLLMchat`, binary = `build/ollmfilesd/ollmfilesd` (2026-08-13).

`File.write` + `File.register` on `docs/Hello World Test LiveProbe` → pending **n=2**, `invalidate_cache` ×2, `is_need_approval=1`.

→ Live DB/FS are fine with current code. Failure is not “big project / dirty DB”.

### Root cause of live empty-pending ✔️

Live machine still has **`ollmfilesd --debug` pid since 2026-07-21**:

- `exe` = **`/usr/bin/ollmfilesd (deleted)`** (old install removed; process kept running)
- Socket `~/.local/share/ollmchat/ollmfilesd.sock` from that Jul 21 start
- App `ClientBoot` finds the socket already up → **does not spawn** `build/ollmfilesd`
- That ancient daemon accepts `File.write` (disk OK) but **does not** create pending approval / emit `invalidate_cache` the way current code does

Harness probes used the **new** binary → always green. Live app used the **Jul 21** process → empty pending.

### Client receive path (code review 2026-08-13)

Chain when a notify arrives on the app’s `OLLMrpc.Client`:

1. **`libocrpc/Client.vala` `dispatch_message`** — debug: `notification method=%s object_type=%s`, then signal.
2. **`Approvals`** — on `event.project.invalidate_cache` → `review_files.refresh.begin()` (+ our temp debug).
3. **`ReviewFiles.refresh()`** — `fetch_pending` → list → `refreshed` → button visibility (+ our temp debug).


---

## Call flow (Approvals list today)

```text
Write / register / EditMode
        │
        ├─ daemon: File.write / File.register
        │     → may set is_need_approval + file_history
        │     → event.project.invalidate_cache
        │
        └─ client tool: review_files.refresh() (also)

OLLMrpc.Client.notification
        → Approvals: invalidate_cache → review_files.refresh()

ReviewFiles.refresh()
        → Folder.fetch_pending_approvals  (full snapshot)
        → clear list + refill + items_changed
        → refreshed → update_button_visibility

Approve / Reject UI
        → FileHistory.approve / FileHistory.revert RPC
        → daemon clears need-approval / updates history
        → client review_files.refresh() again (full snapshot)
```

ℹ️ Pending list is always a **full pull** of rows with `is_need_approval=1` + pending `file_history`. There is **no** “changed since T” / delta wire today.

---

## Root cause

✔️ **Stale daemon (earlier):** Jul 21 `ollmfilesd` → empty pending. Restart → current binary.

✔️ **GTK abort (~19:47):** overlapping `refresh()` cleared the ListModel across `yield` and emitted mismatched `items_changed` (`old=1 new=2` then `old=0 new=4` → `gtk_list_item_manager_ensure_items`).

✔️ **Partial code fix applied:** fetch **before** mutating the list; single-flight so overlapping callers set `refresh_queued` instead of interleaving clears.

---

## Applied code (crash path — current tree)

ℹ️ `libocfiles/ReviewFiles.vala`: `refresh_running` / `refresh_queued`; today fetch-until-quiet then **one** clear/refill. Marker design keeps the loop but **applies each iteration** (see Proposed fix §10).

🚫 Do not “fix” GTK abort by catching it or hiding Approvals.
🚫 Do not treat time-debounce of full `fetch_pending` as the product design (Option A — rejected).

---

## Target design: marker + deltas (only path)

User: **no** settle-then-full-fetch; **no** “just remove locally on approve”. Client holds a **marker**; asks daemon for **rows that changed the pending set since that marker**; patches local `ReviewFiles` from that reply.

### How pending is stored (daemon today)

| Store | Role |
|-------|------|
| `filebase.is_need_approval` | File is in the pending set (`1`) or not (`0`). Cleared on approve/reject. |
| `filebase.last_change_type` | UI label (`added` / `modified` / …). |
| `file_history` | One row per change: `id` (SQLite autoincrement), `filebase_id`, `path`, `timestamp`, `change_type`, `status` (`0` pending / `1` approved / `-1` rejected), `backup_path`. |

`FileWithHistory.pending()` (today’s full list): `filebase` with `is_need_approval=1`, `delete_id=0`, `base_type='f'`, and at least one `file_history` with `status=0` under project roots. Row fields: `id` (=filebase.id), `path`, `last_change_type`, `approve_id` / `reject_id` (newest matching history ids).

**Write / register:** inserts `file_history` (`status=0`, new `id`), sets `is_need_approval=1`, may bump `last_change_type`.

**Approve** (`FileHistory.approve`): **updates in place** pending history rows → `status=1`; sets `is_need_approval=0`. **Does not insert a new `file_history` row** → **`id` does not advance** on approve alone.

**Reject / revert:** sets rejected status / may insert further history; clears `is_need_approval`.

### Why `max(file_history.id)` alone is not enough

Approve **only flips** `status` (and clears `filebase.is_need_approval` / `last_change_type`) — **no new history row**, so `id` does not advance and “`WHERE id > M`” **misses leaves**.

Revert: may **insert** a `revert` history row (new `id`) **and** set the rejected row’s `status = -1` in place — the in-place flip still needs a watermark bump on that row.

### Locked watermark: `file_history.since_id` (user 2026-08-13)

Add column **`since_id`** on `file_history`.

**Assign `since_id` (simple — user refinement):**

| Event | Action |
|-------|--------|
| **INSERT** history | Leave `since_id` at default `0` — **irrelevant**. New rows are already caught by `id > M`. |
| **Status flip** (approve / reject in place) | `since_id = MAX(id) + 1` for the whole table (not `MAX(since_id)+1`). |

No separate rev table. `since_id` is only a “poke” so status flips show up in `since_id > M` when `id` did not change.

**Client marker `M` = last known `MAX(file_history.id)`** (not `MAX(since_id)`).

Delta: rows with **`id > M OR since_id > M`** (project-scoped as today). Reply returns current `MAX(id)` as the next marker.

**Sticky `MAX(id)+1` and repeated batches (accepted):**

While no new history rows are inserted, `MAX(id)` stays e.g. `2`, so every approve sets `since_id = 3`. Clients still at `M = 2` keep receiving the same `since_id = 3` batch on each refresh.

Client is **idempotent** — that is fine:

| Incoming row | Local list | Action |
|--------------|------------|--------|
| `status = 0` | missing | upsert |
| `status = 0` | present | update in place (or no-op if same) |
| `status = 1` / `-1` | present | remove |
| `status = 1` / `-1` | absent | **ignore** |

When a **new** history line is inserted, real `id` advances (`3`, `4`, …), client marker advances with `MAX(id)`, and later status flips use a higher `MAX(id)+1`. The sticky repeat storm ends until the next approve-only streak.

### Sync shape

1. **Same RPC** `Folder.fetch_pending_approvals` — pass client marker as **`FolderParams.since_id`** (`M`; `0` = bootstrap / replay from start).
2. **One SQL for all `M`:** `file_history` rows with `id > M OR since_id > M` (project-scoped), as `FileWithHistory` + wire **`status`**. With `M = 0` that is the whole in-scope history stream — same shape as any later delta.
3. **`Response.msg`** = decimal `MAX(file_history.id)` (next marker).
4. Client always applies rows **idempotently** (upsert / remove / ignore). If local marker was `0`, **clear** the list first, then apply (replay onto empty).
5. **Invalidate_cache:** hint to call with current marker.
6. **Fallback:** reset marker to `0` → clear + replay.

**`refresh()` loop (user 2026-08-13):** keep `refresh_running` / `refresh_queued`. While queued, loop — but **each iteration** must `fetch_pending` **and apply that batch** (marker advances inside `fetch_pending`). Next iteration uses the **new** marker → small delta, not a bigger re-pull of the same window. 🚫 Fetch-until-quiet then apply once. 🚫 Drop the loop entirely. 🚫 “One follow-up only” without apply-per-iteration.

ℹ️ Bootstrap (`M = 0`) may return more rows than today’s pending-only snapshot; after idempotent apply the list matches. One SQL shape for all `M`.

### Rejected alternatives (this bug)

🚫 Option A — time-debounce then full `fetch_pending`.
🚫 “Incremental” = only local remove on approve without a server since-marker protocol.
🚫 Separate pending-rev table / append-only event log (superseded by `since_id` on `file_history`).
🚫 Marker = bare `file_history.id` **without** `since_id` poke on status flip.
🚫 Require strictly monotonic unique `since_id` via `MAX(id, since_id)+1` (unnecessary if client ignores repeats).
🚫 Fetch-while-queued **without** applying each batch (growing same-marker windows / apply-once-at-end).
🚫 Drop the queued loop entirely, or replace it with a single follow-up and no per-iteration apply.

---

## Proposed fix (await approval)

🔷 User direction: `file_history.since_id` only on status flip (`MAX(id)+1`); insert leaves `since_id` alone (caught by `id > M`); fetch `id > M OR since_id > M`; client marker = `MAX(id)`; idempotent apply.

💩 Concrete fences below. **Do not apply until user approves.**

**Wire (no new RPC name):** reuse `Folder.fetch_pending_approvals`.
- Request: `FolderParams.since_id` = client marker `M` (`0` = replay from start).
- Result: **one** query shape for all `M` — `FileWithHistory[]` with wire `status` (`0` upsert, `1`/`-1` remove).
- `Response.msg` = decimal string of current `MAX(file_history.id)` (next marker).

**Named API change (plan-approved):** extend existing `FileWithHistory.pending` with a third arg `int64 since_id` — **not** a new helper method. **No** `if (since_id == 0)` SQL branch.

**🚫** New `fetch_pending_approvals_since` method name.
**🚫** Separate pending-rev / event table.
**🚫** Time debounce of full fetch.

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `ollmfilesd/FileHistory.vala` — property `since_id`

**Why:** Persist poke watermark on each history row.

**Where:** class fields — after `status` property.

**Depends on:** none.

#### Add — after `public int status { get; set; default = 0; }`

Poke watermark for status flips only (default `0` on insert).

```vala
		/**
		 * Sync poke for pending-list delta fetch.
		 * Default {@code 0} on insert (new rows use {@link id} &gt; marker).
		 * Set to {@code MAX(id)+1} on in-place status flip.
		 */
		public int64 since_id { get; set; default = 0; }
```

### 2. `ollmfilesd/FileHistory.vala` — `init_db`: column + migrate

**Why:** Schema for existing and new DBs. No backfill — insert `since_id` stays `0`.

**Where:** end of `init_db`, after CREATE TABLE exec block.

**Depends on:** §1.

##### Part 1 — CREATE TABLE include `since_id`

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
				"alias_target TEXT NOT NULL DEFAULT '', " +
				"moved_to TEXT NOT NULL DEFAULT '', " +
				"moved_from TEXT NOT NULL DEFAULT '', " +
				"agent_id INTEGER NOT NULL DEFAULT 0" +
				");";
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
				"status INTEGER NOT NULL DEFAULT 0, " +
				"since_id INT64 NOT NULL DEFAULT 0, " +
				"alias_target TEXT NOT NULL DEFAULT '', " +
				"moved_to TEXT NOT NULL DEFAULT '', " +
				"moved_from TEXT NOT NULL DEFAULT '', " +
				"agent_id INTEGER NOT NULL DEFAULT 0" +
				");";
```

##### Part 2 — ALTER after CREATE exec

#### Add — immediately after the `if (Sqlite.OK != db.db.exec(query, …)) { … }` block that creates `file_history`, before `init_db` closing `}`

Same migrate pattern as `FileBase.init_db` (`duplicate column name` ok). **No** backfill / **no** `save_to_db` change — insert leaves `since_id = 0`.

```vala
			var migrate_since = "ALTER TABLE file_history ADD COLUMN since_id INT64 NOT NULL DEFAULT 0";
			if (Sqlite.OK != db.db.exec(migrate_since, null, out errmsg)) {
				if (!errmsg.contains("duplicate column name")) {
					GLib.debug("Migration note (may be expected): %s", errmsg);
				}
			}
```

### 3. ~~`save_to_db` set `since_id = id`~~ — cancelled

🚫 Insert `since_id` is irrelevant; new rows are selected by `id > M` only. Leave `save_to_db` unchanged.

### 4. `ollmfilesd/FileHistory.vala` — `approve`: poke `since_id = MAX(id)+1`

**Why:** In-place status flip must appear in `since_id > M`.

**Where:** `approve` foreach pending rows.

**Depends on:** §1–§2.

#### Remove

```vala
			foreach (var row in pending) {
				row.status = 1;
				FileHistory.query(db).updateById(row);
			}
```

#### Replace with

```vala
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
```

### 5. `ollmfilesd/FileHistory.vala` — `revert`: poke rejected row `since_id`

**Why:** In-place `status = -1` must appear in delta (new revert insert already advances `id`).

**Where:** `revert` after `this.status = -1` / before `updateById(this)`.

**Depends on:** §1–§2.

#### Remove

```vala
			this.status = -1;
			FileHistory.query(manager.db).updateById(this);
```

#### Replace with

```vala
			this.status = -1;
			var max_stmt = FileHistory.query(manager.db).selectPrepare(
				"SELECT MAX(id) FROM file_history"
			);
			var max_ids = FileHistory.query(manager.db).fetchAllInt64(max_stmt);
			this.since_id = (max_ids.size > 0 ? max_ids.get(0) : (int64) 0) + 1;
			FileHistory.query(manager.db).updateById(this);
```

### 6. `ollmfilesd/CallParam.vala` — `FolderParams.since_id`

**Why:** Client passes marker on `Folder.fetch_pending_approvals`.

**Where:** `FolderParams` properties — after `metadata_only`.

**Depends on:** none.

#### Add — after `public bool metadata_only { get; set; default = false; }`

```vala
		/** {@link Folder.fetch_pending_approvals} — client marker (`MAX(file_history.id)`); `0` = replay from start. */
		public int64 since_id { get; set; default = 0; }
```

### 7. `ollmfilesd/FileWithHistory.vala` — wire `status` + `pending(…, since_id)`

**Why:** One history-stream query for every marker; wire `status` for upsert vs remove. Extend existing `pending` (plan-named signature change).

**Where:** class properties + `pending` method.

**Depends on:** §2, §6.

##### Part 1 — property

#### Add — after `public int64 reject_id { get; set; default = 0; }`

```vala
		/**
		 * Pending-list delta: `0` = upsert still-pending; `1` / `-1` = leave pending set.
		 */
		public int status { get; set; default = 0; }
```

##### Part 2 — signature + body (single query — no zero branch)

#### Remove

```vala
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
```

#### Replace with

Single query for every marker (including `0`). Client clears+applies when bootstrapping.

```vala
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
```


### 8. `ollmfilesd/Folder.vala` — `call_fetch_pending_approvals`: pass marker + `msg` = `MAX(id)`

**Why:** Wire marker in/out on existing RPC.

**Where:** `call_fetch_pending_approvals` handler in construct.

**Depends on:** §6–§7.

#### Remove

```vala
			this.call_fetch_pending_approvals.connect((request) => {
				var path = ((FolderParams) request.param).path;
				var project = this.manager.project_root(path);
				if (project == null) {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						msg = "project not found"
					});
					return;
				}
				Gee.ArrayList<GLib.Object> result;
				try {
					result = FileWithHistory.pending(
						this.manager,
						project
					);
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
					result = result
				});
			});
```

#### Replace with

```vala
			this.call_fetch_pending_approvals.connect((request) => {
				var p = (FolderParams) request.param;
				var project = this.manager.project_root(p.path);
				if (project == null) {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						msg = "project not found"
					});
					return;
				}
				Gee.ArrayList<GLib.Object> result;
				try {
					result = FileWithHistory.pending(
						this.manager,
						project,
						p.since_id
					);
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
				var max_stmt = FileHistory.query(this.manager.db).selectPrepare(
					"SELECT MAX(id) FROM file_history"
				);
				var max_ids = FileHistory.query(this.manager.db).fetchAllInt64(max_stmt);
				var marker = max_ids.size > 0 ? max_ids.get(0) : (int64) 0;
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					result = result,
					msg = marker.to_string()
				});
			});
```

### 9. `libocfiles/FileWithHistory.vala` — client wire `status`

**Why:** Deserialize delta status from daemon.

**Where:** class properties — after `reject_id`.

**Depends on:** §7.

#### Add — after `public int64 reject_id { get; set; default = 0; }`

```vala
		/**
		 * Delta: `0` upsert pending; `1` / `-1` remove from Approvals list.
		 */
		public int status { get; set; default = 0; }
```

### 10. `libocfiles/ReviewFiles.vala` — marker + delta apply in `fetch_pending` / `refresh`

**Why:** Stop full clear/refill on every notify; patch from since-marker.

**Where:** fields + `fetch_pending` + `refresh`.

**Depends on:** §6–§9.

##### Part 1 — marker field

#### Add — after `private bool refresh_queued;`

```vala
		/** Last `MAX(file_history.id)` from daemon (`Response.msg`); `0` = clear + replay from start. */
		private int64 since_marker;
```

##### Part 2 — `fetch_pending` pass marker + return response for msg

`fetch_pending` today returns only the list. Extend it to also surface the marker by parsing `response.msg` into `this.since_marker` when the call succeeds (inline in `fetch_pending` / `refresh` — no new method).

#### Remove

```vala
		public async Gee.ArrayList<FileWithHistory> fetch_pending()
		{
			var project = this.manager.active_project;
			if (project == null) {
				return new Gee.ArrayList<FileWithHistory>();
			}
			var response = yield this.manager.rpc.call(new OLLMrpc.Request() {
				method = "Folder.fetch_pending_approvals",
				param = new OLLMfilesd.FolderParams() { path = project.path }
			});
			if (response.error != null) {
				return new Gee.ArrayList<FileWithHistory>();
			}
			return (Gee.ArrayList<FileWithHistory>) response.result;
		}
```

#### Replace with

```vala
		public async Gee.ArrayList<FileWithHistory> fetch_pending()
		{
			var project = this.manager.active_project;
			if (project == null) {
				return new Gee.ArrayList<FileWithHistory>();
			}
			var response = yield this.manager.rpc.call(new OLLMrpc.Request() {
				method = "Folder.fetch_pending_approvals",
				param = new OLLMfilesd.FolderParams() {
					path = project.path,
					since_id = this.since_marker
				}
			});
			if (response.error != null) {
				return new Gee.ArrayList<FileWithHistory>();
			}
			if (response.msg != "" && response.msg != "project not found") {
				this.since_marker = int64.parse(response.msg);
			}
			return (Gee.ArrayList<FileWithHistory>) response.result;
		}
```

##### Part 3 — `refresh`: queued loop, **apply each iteration**

**Why:** Overlapping notifies set `refresh_queued`. Loop until quiet, but each pass fetches with the **current** marker, **applies that batch**, marker advances → next pass is a small new delta. Do **not** fetch repeatedly then apply once.

#### Remove

```vala
		public async void refresh()
		{
			if (this.refresh_running) {
				this.refresh_queued = true;
				return;
			}
			this.refresh_running = true;
			var files = new Gee.ArrayList<FileWithHistory>();
			do {
				this.refresh_queued = false;
				files = yield this.fetch_pending();
			} while (this.refresh_queued);
			var old_n_items = this.items.size;
			this.items.clear();
			this.file_map.clear();
			foreach (var file in files) {
				this.items.add(file);
				this.file_map.set(file.path, file);
			}
			var new_n_items = this.items.size;
			GLib.debug("review_files refresh done old=%d new=%d", old_n_items, new_n_items);
			if (old_n_items > 0 || new_n_items > 0) {
				this.items_changed(0, old_n_items, new_n_items);
			}
			this.refreshed();
			this.refresh_running = false;
		}
```

#### Replace with

```vala
		public async void refresh()
		{
			if (this.refresh_running) {
				this.refresh_queued = true;
				return;
			}
			this.refresh_running = true;
			do {
				this.refresh_queued = false;
				var replay = this.since_marker == 0;
				var files = yield this.fetch_pending();
				if (replay) {
					var old_n_items = this.items.size;
					this.items.clear();
					this.file_map.clear();
					if (old_n_items > 0) {
						this.items_changed(0, old_n_items, 0);
					}
				}
				foreach (var file in files) {
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
					this.append(file);
				}
				GLib.debug("review_files refresh delta n=%d marker=%lld list=%d replay=%d",
					files.size, this.since_marker, this.items.size, replay ? 1 : 0);
			} while (this.refresh_queued);
			this.refreshed();
			this.refresh_running = false;
		}
```

### 11. Project switch / clear — reset marker

**Why:** Marker is per daemon DB stream; clearing list must force replay from `0` next time.

**Where:** `ReviewFiles.clear`.

**Depends on:** §10.

#### Remove

```vala
		public void clear()
		{
			var old_n_items = this.items.size;
			this.items.clear();
			this.file_map.clear();

			if (old_n_items > 0) {
				this.items_changed(0, (uint)old_n_items, 0);
			}
		}
```

#### Replace with

```vala
		public void clear()
		{
			var old_n_items = this.items.size;
			this.items.clear();
			this.file_map.clear();
			this.since_marker = 0;

			if (old_n_items > 0) {
				this.items_changed(0, (uint)old_n_items, 0);
			}
		}
```

---

## Attempts / changelog

- ✔️ 2026-08-12 — Bug log created.
- ✔️ 2026-08-13 — CLI Probe A: pending + `invalidate_cache` on new binary.
- ✔️ 2026-08-13 — Live write empty pending under Jul 21 stale daemon.
- ✔️ 2026-08-13 — Live DB copy + new binary: pending works; identified stale daemon.
- ✔️ 2026-08-13 ~19:47 — After daemon restart: invalidate + Approvals refresh; **GTK list abort**.
- ✔️ 2026-08-13 — Applied fetch-first + single-flight coalesce.
- ✔️ 2026-08-13 — Coalesce: refetch while queued, one `items_changed` after last fetch.
- ✔️ 2026-08-13 — User: coalesce ≠ debounce; want settle-then-fetch and/or incremental; recorded as Options A/B.
- ✔️ 2026-08-13 — User: **A out**; prior B wrong. Target = **marker + changes since**; documented daemon storage + approve-in-place gap + watermark options A/B/C.
- ✔️ 2026-08-13 — User: add **`file_history.since_id`**; bump with `MAX(id, since_id)+1` on insert and on status flip (approve/reject). Locked as watermark.
- ✔️ 2026-08-13 — User: simplify — insert `since_id = id`; status flip `since_id = MAX(id)+1`; marker = `MAX(id)`; repeated sticky batches OK (idempotent ignore).
- ✔️ 2026-08-13 — Proposed fix fences §1–§11 in this log (`since_id` column, poke on approve/revert, same RPC + `FolderParams.since_id`, client delta apply).
- ✔️ 2026-08-13 — User: insert `since_id` irrelevant (stay `0`); only poke on status flip. Cancelled §3 / backfill.
- ✔️ 2026-08-13 — User: no zero/nonzero SQL branch — one `id > M OR since_id > M` query; bootstrap = `M=0` + clear + idempotent apply.
- ✔️ 2026-08-13 — User: keep `refresh_queued` loop; **apply each iteration** (marker advances → small next batch). Not fetch-until-quiet+apply-once; not drop-the-loop.
- ✔️ 2026-08-13 — User: fix `GLib.debug` wrap (message on call line); otherwise good to go — **applied** §1–§11 (minus cancelled §3).

---

## Next

⏳ 🔷 Re-test write under `docs/` (Approvals visible; delta refresh under burst; no GTK abort).

⏳ After ✅ on marker sync: remove temporary Approvals / ReviewFiles debug lines.
