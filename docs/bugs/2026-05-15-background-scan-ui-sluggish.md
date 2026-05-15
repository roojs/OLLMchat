# Background semantic scan makes UI sluggish on project open

**Status:** OPEN — root causes identified from log (~16:31–16:38 run); fixes need approval

## Problem

When opening a project, background semantic indexing runs (`BackgroundScan`) but the foreground UI becomes sluggish.

**Reproduce:** Open a large project (e.g. `web.MediaOutreach`) with codebase search enabled. Run with **`--debug`**.

## Debug rules (must follow)

Per **`docs/bug-fix-process.md`** and **`.cursor/rules/CODING_STANDARDS.md`** (Debug and Warning Statements):

- `GLib.debug()` / `GLib.warning()`: **no** class names, method names, or `[tags]` in the message (file:line is in the log).
- **No** `GLib.get_monotonic_time()` or duration fields in messages.
- **No** `if (...)` whose only purpose is to skip debug — log unconditionally at real phase boundaries; filter with grep.

## Useful grep patterns (`~/.cache/ollmchat/ollmchat.debug.log`)

| Grep pattern | What it shows |
|--------------|----------------|
| `restoring session project` | session restore → `activate_project` |
| `opening project` | `activate_project` entries / duplicate opens |
| `filesystem scan idle subdirs` | main thread deferred recursive walk starting |
| `filesystem scan subdir` | main idle still walking dirs (remaining=N) |
| `opening project skipped already active` | redundant activation avoided |
| `project tree load starting` | full DB tree reload (main or worker) |
| `project tree load skipped` | reload skipped (cheap path) |
| `filesystem scan starting` | `read_dir` recurse began (any folder) |
| `filesystem scan finished` | project root filesystem scan done |
| `filesystem scan returned` | `read_dir` returned to `activate_project` (may be before scan actually finished) |
| `persisting db after filesystem scan` | main-thread `backupDB` after filesystem walk |
| `semantic index waiting filesystem` | background scan blocked on `pm.scanning` |
| `queued [0-9]+ files` | background queue size |
| `parsed path=.*elements=` | tree-sitter element count per file |
| `element analysis starting` | LLM pass beginning |
| `element analysis done` | LLM pass finished (`llm_ok` / `llm_fail`) |
| `persisting db after element analysis` | worker `backupDB` after each file's LLM pass |
| `persisting db on main after indexed` | main `backupDB` after successful index |
| `indexed file finished` | full pipeline completed for one file |
| `Analyzing:` | per-element LLM call (noisy; count these) |

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
| H1 | `backupDB()` contends on shared `db_mutex` | `persisting db after filesystem scan`, `persisting db after element analysis`, `persisting db on main` |
| H2 | Per-file full `load_files_from_db` | many `project tree load starting` vs `skipped` during `semantic index file=` |
| H3 | `scan_update` on main every file | `scan banner update` |
| H4 | Too many LLM calls per file (builtin “functions”) | count `Analyzing:` vs `element analysis done` `llm_ok` |
| H5 | Duplicate `activate_project` / overlapping filesystem scan | `opening project`, paired `filesystem scan queued` / `returned` |

## Conclusions from full run (~6.5 min, log ends 16:38:10)

**Run stats:** 8247 log lines; **3 of 130** files fully indexed; 4th file (`Widget.php`) still doing LLM when log ends.

### Confirmed root causes (evidence)

| # | Cause | Evidence |
|---|--------|----------|
| **1** | **Main thread: `backupDB()` during filesystem walk** | **396×** `persisting db after filesystem scan` — called when *each* subfolder’s `process_folders` queue empties, not only at project end (`Folder.vala` `process_folders`) |
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

1. **`backupDB` only once** when project-root filesystem scan completes — remove per-subfolder `backupDB` in `process_folders` (or only when `is_project`).
2. **`scanning` map:** set only on project root (or refcount), not every `read_dir` entry.
3. **Analysis:** stop calling `backupDB()` after every file; set `is_dirty` and rely on autosave / end-of-file main backup.
4. **`should_skip_llm`:** skip PHP builtin/call expressions (`empty`, `explode`, `isset`, etc.) — would have removed most of 78–187 calls on sample files.
5. **BackgroundScan:** avoid `set_active_project_and_load` per queued file when project unchanged.
6. **Investigate** why filesystem scan visits `gitlive/Pman.BAdmin` with project root `web.MediaOutreach`.

At ~2 min/file × 130 files, background indexing alone is **hours** even after main-thread fixes.

## Changelog

- 2026-05-15: Initial investigation debug; fixed rule violations (no method/class names in messages, no debug-only `if` gating).
- 2026-05-15: Full log analysis (~16:31–16:38); root causes and ranked fix list added.
