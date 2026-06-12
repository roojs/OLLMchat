# FIXED: Background semantic scan makes UI sluggish on project open

**Status: FIXED** (2026-05-16)

**Resolution:** Countdown-coalesced `backupDB()` in `libocsqlite/Database.vala` — max-age **20 s**, short-circuit while timer armed, **500 ms** × **5** deferred write, `backup_real` for disk I/O. Debug lines `disk backup requested` / `coalesced` / `writing` / `done` for verification (`--debug`, grep `~/.cache/ollmchat/ollmchat.debug.log`). Strace confirmed pre-fix backup storm (~60–70 renames/s). Follow-ups **2–6** (scanning map, LLM builtins, etc.) remain optional if UI still heavy.

## Problem

When opening a project, background semantic indexing runs (`BackgroundScan`) but the foreground UI becomes sluggish.

**Reproduce:** Open a large project (e.g. `web.MediaOutreach`) with codebase search enabled. Run with **`--debug`**.

## Verdict (definitive vs still open)

### Definitive (code + syscall evidence)

These are facts, not guesses:

1. **`backupDB()` serializes the whole app against the DB.** In `libocsqlite/Database.vala`, `backupDB()` locks `db_mutex`, runs `Sqlite.Backup` to completion (`step(-1)`), then unlocks. Every `SQ.Query` path locks the same `db_mutex` around statements. So for the entire duration of a backup, **no other code can use that database connection**; conversely, any in-flight query blocks a backup. There is no “read in parallel while backup finishes” on this wrapper.

2. **A backup is a full copy of the in-memory DB to disk** (temp `*.sqlite.new`, then rename into place). It is not an incremental flush.

3. **During project filesystem scan, the app calls `backupDB()` far too often.** `libocfiles/Folder.vala` calls it after many scan steps (including when each `process_folders` batch completes, and after individual `read_dir_update` saves). Debug logs counted hundreds per open; **strace independently shows on the order of ~60–70 completed disk commits per second** to `~/.local/share/ollmchat/files.sqlite` during busy stretches (count `rename` of `files.sqlite.new` → `files.sqlite`).

4. **Those calls run on the GLib main context** (idle/async continuations from the folder walk), so **each `backupDB()` runs synchronously on the thread that drives GTK**: the main loop cannot dispatch input, redraw, or other idle work until the call returns. That is a **definitive** recipe for UI stalls whenever a backup takes non-trivial time.

Together: we **definitively** have a **pathological persistence pattern** (full DB snapshot, global lock, main-thread call sites, extremely high call rate). Treating that as acceptable would be wrong; fixing it is justified on architecture alone.

### Not definitive (needs one more step)

- **How much** of the user-visible “sluggish” in a given session is **CPU/IO time inside `backupDB()`** vs main-thread **directory walk**, **tree reloads**, **LLM latency**, etc. Strace proves **frequency** of commits, not milliseconds per backup (the heavy `read`/`pwrite64` work is outside the narrow syscall filter we used).

**Further investigation (to rank contributors):** one **Sysprof** (or `perf record`) capture during the same repro, then inspect where wall time goes (e.g. `sqlite3_backup_step`, GTK paint, `read_dir`). Until that exists, do **not** claim “backup is 90% of jank”—claim instead what is already certain above.

### H1 status

H1 is **confirmed** as a real, severe design/usage problem (mutex + full backup + main context + extreme rate). It is **not** the same as “proven sole cause of all perceived lag” without profiling.

## Debug rules (must follow)

Per **`docs/bug-fix-process.md`** and **`docs/coding-standards.md`** (Debug and Warning Statements):

- `GLib.debug()` / `GLib.warning()`: **no** class names, method names, or `[tags]` in the message (file:line is in the log).
- **No** `GLib.get_monotonic_time()` or duration fields in messages.
- **No** `if (...)` whose only purpose is to skip debug — log unconditionally at real phase boundaries; filter with grep.

## Useful grep patterns (`~/.cache/ollmchat/ollmchat.debug.log`)

| Grep pattern | What it shows |
|--------------|----------------|
| `restoring session project` | session restore → `activate_project` |
| `opening project` | `activate_project` entries / duplicate opens |
| `opening project skipped already active` | redundant activation avoided |
| `filesystem scan already active` | scan still in progress for path |
| `filesystem scan queued` | scan scheduled for project path |
| `filesystem scan returned` | `read_dir` returned to caller (may be before subtree idle completes) |
| `semantic index waiting filesystem` | background scan blocked on `pm.scanning` |
| `queued [0-9]+ files` | background queue size |
| `parsed path=.*elements=` | tree-sitter element count per file |
| `element analysis starting` | LLM pass beginning |
| `element analysis done` | LLM pass finished (`llm_ok` / `llm_fail`) |
| `persisting db after element analysis` | worker `backupDB` after each file's LLM pass |
| `persisting db on main after indexed` | main `backupDB` after successful index |
| `indexed file finished` | full pipeline completed for one file |
| `Analyzing:` | per-element LLM call (noisy; count these) |

**Note:** Diagnostic `GLib.debug` lines in `Folder.vala` for filesystem scan / project tree load were **removed** after strace confirmed backup frequency; older captures may still contain those strings.

## Established from log (~16:25 run)

- **Duplicate project open:** two `opening project` / `filesystem scan queued` pairs within ~40ms; `filesystem scan returned` at +2ms then again at +2.7s while UI sluggish.
- **Overlapping tree loads:** two `project tree load starting` on main before filesystem scan.
- **`filesystem scan finished` absent** in capture — project walk still running on idle when user stopped.
- **130 files queued;** per-file reload mostly `project tree load skipped`.
- **`Ap.php`:** 82 elements; many `Analyzing:` calls for PHP builtins (`empty`, `explode`, …) — ~20+ LLM round-trips before user stopped.
- **No** `element analysis done` / `persisting db after element analysis` in capture — no file completed LLM pass.

## Hypotheses (not fixed until confirmed)

| ID | Hypothesis | Grep / evidence |
|----|------------|-----------------|
| H1 | **`backupDB()` contends on shared `db_mutex` — CONFIRMED** (see Verdict) | Code: `libocsqlite/Database.vala` + `libocsqlite/Query.vala`; logs; strace rename rate on `files.sqlite` |
| H2 | Per-file full `load_files_from_db` | many `project tree load starting` vs `skipped` during `semantic index file=` |
| H3 | `scan_update` on main every file | `scan banner update` |
| H4 | Too many LLM calls per file (builtin “functions”) | count `Analyzing:` vs `element analysis done` `llm_ok` |
| H5 | Duplicate `activate_project` / overlapping filesystem scan | `opening project`, paired `filesystem scan queued` / `returned` |

## Strace verification (disk backup frequency, 2026-05-16)

Independent of `GLib.debug` text: each successful `backupDB()` ends with `rename("…/files.sqlite.new", "…/files.sqlite")` (after unlink of `files.sqlite.new-journal`). Counting those renames measures how often the global files DB is fully written and swapped into place.

**Command (one line):**

```bash
strace -f -tt -T -y -o /tmp/ollmchat-backup.strace -e trace=rename,renameat,renameat2,unlink,unlinkat ollmchat --debug 2>&1 | tee /tmp/ollmchat-backup.console
```

**Runs (same machine, same command, path `~/.local/share/ollmchat/files.sqlite`):**

| Run | Renames (`files.sqlite.new` → `files.sqlite`) | Approx. window | ~rate |
|-----|-----------------------------------------------|------------------|-------|
| A | **4133** | first rename ~09:40:35 → SIGINT ~09:41:32 (~57 s) | ~72/s |
| B | **1482** | ~09:54:31.50 → ~09:54:55.80 (~24 s) | ~61/s |

Same pattern: one main pid holds the rename storm; spacing between renames on the order of **~12–16 ms** in dense stretches.

**What this does / does not prove:** Confirms **extremely high backup frequency** (matches the “hundreds of `backupDB` during scan” story from debug logs). The `-T` column on **`rename`** stays sub-millisecond (expected: rename is cheap); **per-backup wall time** mostly lives in SQLite copying pages into `.new` (`read`/`pwrite64`/etc.), which this syscall filter omits. Use a wider `-e` filtered with `grep files.sqlite`, or Sysprof / `perf`, to quantify cost per backup.

## Conclusions from full run (~6.5 min, log ends 16:38:10)

**Run stats:** 8247 log lines; **3 of 130** files fully indexed; 4th file (`Widget.php`) still doing LLM when log ends.

### Contributing factors (evidence) — not all are “% of jank” ranked

| # | Factor | Evidence |
|---|--------|----------|
| **1** | **Definitive bug:** main-context **`backupDB()` storm** during filesystem walk (full DB copy + `db_mutex` + huge rate) | **396×** `persisting db after filesystem scan` in long log run (debug since removed). **Strace:** **4133** / ~57 s and **1482** / ~24 s — ~**60–70/s** commits. **Mitigation:** **✅** countdown-coalesced `backupDB` in `Database.vala`. |
| **2** | **Main thread: long recursive filesystem scan via `Idle`** | **449×** `filesystem scan subdir`; project walk **16:31:46 → 16:35:04** (~3m18s) overlapping semantic indexing; scan includes paths **outside** project e.g. `Pman.BAdmin` under `gitlive` with `root=web.MediaOutreach` |
| **3** | **`pm.scanning` map grows large and blocks background queue** | `semantic index waiting filesystem scan active=` rises **1 → 47**; each `read_dir` does `scanning.set(path)` but many paths not cleared until subtree idle completes |
| **4** | **~80–190 Ollama calls per PHP file** | `element analysis done`: Ap.php **llm_ok=78**/82, Feed.php **113**/123, RSS.php **187**/191; **460×** `Analyzing:` total; ~1–2.5 min/file |
| **5** | **Worker + main `backupDB` after indexing** | 3× `persisting db after element analysis` + 3× `persisting db on main after indexed` (only 3 files completed) |
| **6** | **Duplicate session restore** | 2× `restoring session project` + 2× `opening project` within 0.4s at startup |

### Timeline

| Time | Event |
|------|--------|
| 16:31:45 | Open project (twice via restore) |
| 16:31:47 | Background queues **130 files**, starts `Ap.php` LLM |
| 16:31:50 | Filesystem scan defers **24 subdirs** on main idle; `activate_project` returns |
| 16:31:50–16:35:04 | Main idle walks **449 subdirs**, **396 backupDB** |
| 16:32:47 | `Ap.php` LLM done (78 calls) |
| 16:33:00 | First file fully indexed |
| 16:35:04 | `filesystem scan finished` (main walk ends) |
| 16:34:49 / 16:37:17 | Files 2–3 indexed |
| 16:37:18+ | File 4 (`Widget.php`) LLM in progress; `scanning active=47` still |

### Proposed fixes (need approval before coding)

1. **✅ Countdown-coalesced `backupDB`** — **done** in `libocsqlite/Database.vala` (see plan below): max-age **20 s** first, short-circuit, **500 ms** × **5** countdown, **`backup_real`** only.
2. **`scanning` map:** set only on project root (or refcount), not every `read_dir` entry.
3. **Indexing path:** reduce redundant `backupDB` *semantics* after debounce lands (optional further reduction); `should_skip_llm` for PHP builtins (see table row 4).
4. **`should_skip_llm`:** skip PHP builtin/call expressions (`empty`, `explode`, `isset`, etc.) — would have removed most of 78–187 calls on sample files.
5. **BackgroundScan:** avoid `set_active_project_and_load` per queued file when project unchanged.
6. **Investigate** why filesystem scan visits `gitlive/Pman.BAdmin` with project root `web.MediaOutreach`.

At ~2 min/file × 130 files, background indexing alone is **hours** even after main-thread fixes.

## Plan: Countdown-coalesced backupDB (`SQ.Database`)

**Status:** done (implemented in `libocsqlite/Database.vala`)

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans** (below); **`docs/guide-to-writing-plans.md`** — plan shape and code-proposal fences.

### Coding standards checklist (this plan)

| Item | Answer |
|------|--------|
| Nullable / `uint?` for countdown id | **No** — `countdown_id` is `uint`, **0** = none |
| New methods | **One** only: **`backup_real`** (user-approved); tick = lambda in **`backupDB`** |
| `this.` / `GLib.*` | **Yes** in new/changed code |
| Property defaults | **`get; private set; default =`** for `countdown`, `countdown_id`, `last_backup` |
| Trivial temporaries | **No** `now` / `tick_now` — inline `GLib.DateTime.now_local().to_unix()` in conditions |
| Debug | **None** added |
| Docblocks | Multiline on new properties, **`backupDB`**, **`backup_real`** |
| Single canonical proposal | One **Replace with** fence below |

### Purpose

Collapse bursty `backupDB()` invocations so the main thread does not run a full disk backup on every call. **`countdown`** is reset while a timer is already armed; a **500 ms** repeating tick decrements it; at **0**, **`backup_real()`** runs (~**2.5 s** quiet after the last request when **`countdown = 5`**). **`last_backup`** caps how long we can defer if requests never stop.

### Scope

| In scope | Out of scope (follow-ups) |
|----------|---------------------------|
| `libocsqlite/Database.vala`: debounce **public** `backupDB()` | Changing every `backupDB()` call site in `Folder.vala` / vector / tools (optional later) |
| One global debounce per `Database` instance | Env vars or runtime toggles for interval |
| **500 ms** tick × **`countdown = 5`** ⇒ ~**2.5 s** quiet before a normal deferred backup | Separate per-feature tuning tables |
| **`last_backup`** (`int64`, **0** = never); force **`backup_real()`** if older than **20 s** | Env vars or runtime toggles for interval |
| Keep existing mutex + `Sqlite.Backup` + rename behaviour inside the **executed** path | WAL / on-disk primary DB redesign |

### Acceptance criteria

- After a burst of **N** `backupDB()` calls with **no** further calls for ~**2.5 s**, **one** full backup runs (strace: one `rename(…files.sqlite.new…)` per burst).
- While `backupDB()` is called continuously, a backup still runs at least every **~20 s** (`last_backup` force path).
- **🔷** Tick interval **500 ms**; default **`countdown = 5`** on arm/reset ⇒ ~**2.5 s** quiet window.
- **🔷** `backupDB()` order: **max-age first** (`now - last_backup > 20` → `backup_real`); then short-circuit; then arm timer. Lambda **only** decrements `countdown`.
- **`backup_real()`** sets **`last_backup`** when a disk backup completes successfully.
- Existing **autosave** (`is_dirty` → `backupDB()`) still coalesces via the same mechanism.
- **⏳** Orderly shutdown under **2.5 s** since last `backupDB()` may skip a deferred backup — follow-up `flush` on quit if needed.

### Discussion

- **🔷** **Order in `backupDB()`:** (1) if **`now - last_backup > 20`**, disarm timer if any, **`backup_real()`**, **`return`**. (2) if **`countdown_id != 0`**, **`countdown = 5`**, **`return`**. (3) arm **500 ms** lambda (decrement only; **no** date check in the tick).
- **🔷** **`countdown = -1`**: used on the max-age path before **`backup_real()`**.
- **🔷** **`countdown_id`**: **`0`** = no armed source — **no** `uint?` / `null`.
- **ℹ️** Inline **lambda** only; **`backup_real`** is the **only** added named method.
- **🚫** No `backup_db_execute`, `on_backup_countdown_tick`, or other helpers.

### Concrete code proposals

#### 1. `libocsqlite/Database.vala` — `backupDB` + single added `backup_real`

**🔷** Exactly **two** named units: existing **`backupDB`** (rewritten) and **one** new **`backup_real`** (today’s mutex + `Sqlite.Backup` body). Countdown tick = **lambda** inside `backupDB`, not a third method.

##### Keep (anchor — class already has `db_mutex`, `filename`, `is_dirty`, `setup_autosave`)

```vala
	public class Database {
	
		public Sqlite.Database db;
		public GLib.Mutex db_mutex = GLib.Mutex();
```

##### Add — properties after `save_timeout_id`

Placement: after `private uint? save_timeout_id`. **What:** `countdown`, `countdown_id`, `last_backup` with multiline docblocks (see implemented `libocsqlite/Database.vala`).

##### Replace with — `backupDB` (max-age first, then short-circuit, lambda **500 ms**) and `backup_real`

**What:** Max-age at **entry** so non-stop storms still back up every **20 s**; lambda has **no** date logic.

```vala
		public void backupDB()
		{
			if (new GLib.DateTime.now_local().to_unix() - this.last_backup > 20) {
				if (this.countdown_id != 0) {
					GLib.Source.remove(this.countdown_id);
					this.countdown_id = 0;
				}
				this.countdown = -1;
				this.backup_real();
				return;
			}
			if (this.countdown_id != 0) {
				this.countdown = 5;
				return;
			}
			this.countdown_id = GLib.Timeout.add(500, () => {
				this.countdown--;
				if (this.countdown > 0) {
					return true;
				}
				this.countdown_id = 0;
				this.backup_real();
				return false;
			});
			this.countdown = 5;
		}

		private void backup_real()
		{
			if (this.db == null) {
				return;
			}
			this.db_mutex.lock();
			try {
				var new_filename = this.filename + ".new";
				Sqlite.Database filedb;
				Sqlite.Database.open(new_filename, out filedb);
				var b = new Sqlite.Backup(filedb, "main", this.db, "main");
				b.step(-1);
				var new_file = GLib.File.new_for_path(new_filename);
				GLib.FileInfo info;
				try {
					info = new_file.query_info(
						GLib.FileAttribute.STANDARD_SIZE,
						GLib.FileQueryInfoFlags.NONE);
					if (info.get_size() == 0) {
						GLib.warning(
							"Backup file %s was not created properly (size: 0)",
							new_filename);
						GLib.FileUtils.remove(new_filename);
						return;
					}
				} catch (GLib.Error e) {
					GLib.warning(
						"Backup file %s was not created properly: %s",
						new_filename,
						e.message);
					GLib.FileUtils.remove(new_filename);
					return;
				}
				GLib.FileUtils.rename(new_filename, this.filename);
				this.is_dirty = false;
				this.last_backup = new GLib.DateTime.now_local().to_unix();
			} catch (GLib.Error e) {
				GLib.warning("Error during database backup: %s", e.message);
			} finally {
				this.db_mutex.unlock();
			}
		}
```

##### Remove

The **old** `public void backupDB() { … }` body (single method, no `backup_real` / no countdown) — verbatim match to current `Database.vala` (starts at `public void backupDB()` through closing `}` before `public void exec`).

**Implementer note:** early `return` paths inside `try` that `return` before `finally` still run `finally` in Vala — keep that behaviour identical to today.

## Changelog

- 2026-05-15: Initial investigation debug; fixed rule violations (no method/class names in messages, no debug-only `if` gating).
- 2026-05-15: Full log analysis (~16:31–16:38); root causes and ranked fix list added.
- 2026-05-16: Strace section added (`rename`/`unlink` on `files.sqlite.new`); 4133 commits ~57s; note limits of syscall filter for per-backup duration.
- 2026-05-16: Second strace run recorded (1482 renames / ~24 s); table + strace section updated.
- 2026-05-16: **Verdict** section — definitive (mutex + full backup + main context + strace rate) vs non-definitive (share of felt jank); H1 marked confirmed; table wording softened on “root cause” without profiler.
- 2026-05-16: **Countdown-coalesced `backupDB`** implemented in `libocsqlite/Database.vala` (max-age first, short-circuit, 500 ms tick, `backup_real`, `last_backup`); plan marked done; fix #1 ✅.
- 2026-05-16: Disk-backup debug lines added (`disk backup requested`, etc.).
- 2026-05-16: **FIXED** — moved to `docs/bugs/done/`.
