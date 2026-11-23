# Windows: SQLite backup leaves orphaned `*.new`; next open loads empty DB

**Status:** ✔️ ships in **1.4.17**

**Downstream:** Argus RM — [`argusrm/docs/bugs/2026-11-23-ISSUE-windows-reconnect-after-upgrade.md`](../../../argusrm/docs/bugs/2026-11-23-ISSUE-windows-reconnect-after-upgrade.md)

**Pointer:** `docs/bug-fix-process.md`, [`libocsqlite/Database.vala`](../../libocsqlite/Database.vala) (`load_from_file`, `backup_real`). Reference implementation: Snappr2 `src/SQ/Database.vala` (same author; orphan recovery + Windows promote).

### User reported

- 🔷 Argus Windows agent (**0.1.42** in-place upgrade): machine stays **Disconnected**; reconnect loop never succeeds despite valid PEMs on disk.

### Success scenario

- `backup_real()` always promotes `filename.new` → `filename` on every OS (including replace-in-place on Windows).
- If shutdown or service stop interrupts promote, the **next** `new SQ.Database(path)` recovers when only `path.new` exists.
- Callers (e.g. Argus `ensure_client_db`) need no duplicate promote logic.

### Current behavior

- `backup_real()` writes `filename.new`, then `GLib.FileUtils.rename(new_filename, this.filename)` with no remove-existing and no copy fallback.
- On Windows, rename may fail when `filename` already exists → only `.new` remains.
- `load_from_file()` tests only `filename`; missing file → empty in-memory DB (schema init, **no rows**).
- Argus symptom: `Connection` — `no saved server` every retry; `server.sqlite` absent, `server.sqlite.new` present (~12 KiB).

### Codebase observed behavior

- [`libocsqlite/Database.vala`](../../libocsqlite/Database.vala) line ~251: bare `rename` after backup.
- [`libocsqlite/Database.vala`](../../libocsqlite/Database.vala) line ~119: `if (!exists) return false` with no orphan handling.
- Related (fixed elsewhere): zero-byte discard in `load_from_file()` — [`2026-11-21-FIXED-zero-byte-sqlite-backup-connect.md`](done/2026-11-21-FIXED-zero-byte-sqlite-backup-connect.md).

### Debugging

#### Current debug output

- **Source:** Argus `snappr-win`, Windows service `agent.log`, 2026-11-23 (after NSIS **0.1.42** upgrade)

```text
14:33:55.918441: G_LOG_LEVEL_DEBUG : Database.vala:176: disk backup requested
14:33:56.851648: G_LOG_LEVEL_WARNING : Connection.vala:199: no saved server
(repeats every ~5s)
```

- **On disk:** `…\AppData\Local\argus\client.pem` present; `server.sqlite` **missing**; `server.sqlite.new` present.

#### Debug code added (remove when complete)

None.

### Proposed fix

- ✔️ **`backup_real()`** only — after Sqlite backup to `.new`, `File.copy` `OVERWRITE` to `filename` and delete `.new` (no `rename`). `load_from_file()` unchanged.

### Verification

- Throwaway: create `foo.sqlite.new`, omit `foo.sqlite`, `new SQ.Database("foo.sqlite")` — row data visible after promote block.
- Windows: backup over existing file twice; no leftover `.new`; stop process mid-backup (optional) then reopen — orphan promoted.

### LLM

- ℹ️ Argus must not fork backup semantics in `Application.vala`; bump **libocsqlite** release after fix.
- ℹ️ Ops workaround: manual `server.sqlite.new` → `server.sqlite` on affected agents until release ships.