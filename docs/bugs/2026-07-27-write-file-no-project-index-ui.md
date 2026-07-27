# write_file / edit_mode: new file not in pull-down / changed-files list

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✔️ E1/E2 + F1/F2 + A′ + G applied 2026-07-27 — await user verify (file pull-down + changed-files after create)

**Started:** 2026-07-25 · **Reopened:** 2026-07-27

**Prior archive name:** `docs/bugs/done/2026-07-25-FIXED-write-file-no-project-index-ui.md`
(moved back to active; filename date = reopen day)

---

## Scoreboard (where we are)

| Item | Fence complete? | User approved apply? | Applied in tree? | Notes |
|------|-----------------|----------------------|------------------|-------|
| **A** WriteFile / EditMode prefix gate | ✔️ | 🔷 yes | ✔️ | Register **does** run now (confirmed 2026-07-27) |
| **B** `wait_scan_idle` + client `loading` | ✔️ | 🔷 yes | ✔️ | Still race evidence on open (see B′) |
| **C** `invalidate_cache` + SourceView / Approvals | ✔️ | 🔷 yes | ✔️ | **No** `invalidate_cache` seen in client log this run |
| **E1/E2** `copy_from` skips `"manager"` on read/register | ✔️ | 🔷 yes | ✔️ | Applied 2026-07-27 |
| **F1/F2** Daemon history + approval on `to_real` / write | ✔️ | 🔷 yes | ✔️ | Applied 2026-07-27 |
| **A′** Drop dead Stream `contains_folder` | ✔️ | 🔷 yes | ✔️ | Applied 2026-07-27 |
| **G** EditMode `to_summary` under-project | ✔️ | 🔷 yes | ✔️ | Applied 2026-07-27 |
| **D** SourceView last-line | separate | separate | separate | [`2026-07-25-FIXED-sourceview-open-shows-only-last-line.md`](done/2026-07-25-FIXED-sourceview-open-shows-only-last-line.md) |

---

## Related

- ℹ️ Plan under test: [`docs/plans/2.22-write-file-tool.md`](../plans/2.22-write-file-tool.md)
- ℹ️ Changed-files / approvals UX (known incomplete): [`docs/plans/2.6.2-bwrap-ux-fixes.md`](../plans/2.6.2-bwrap-ux-fixes.md) — summary flags “list of changed files does not work well”
- ℹ️ Null-`manager` after RPC `copy_from` (diagnosed, **not applied**):
  [`docs/bugs/done/2026-07-05-CLOSED-file-read-null-manager-changed-banner.md`](done/2026-07-05-CLOSED-file-read-null-manager-changed-banner.md)
- ℹ️ Debug logs: `~/.cache/ollmchat/ollmchat.debug.log`,
  `~/.cache/ollmchat/ollmfilesd.debug.log`
- ℹ️ DB: `~/.local/share/ollmchat/files.sqlite`
- ℹ️ Session (reopen): `~/.local/share/ollmchat/history/2026/07/27/08-25-18.json`
  (agent `code-assistant`, project `/home/alan/gitlive/roo-gtksettings`)
- ℹ️ Session (original): `…/history/2026/07/25/15-01-30.json`
  (project `/home/alan/gitlive/app.RooTerm`)

---

## Problem

🔷 After a successful create (`write_file` or `edit_mode` + `complete_file`) under
the active project, the new file should:

- appear in the **file pull-down**, and
- appear in the **Changed files** / approvals list (pending approval).

🔷 Actual (2026-07-27, `roo-gtksettings`): disk write + DB index succeed;
file pull-down still empty (`filtered=0`); changed-files list empty;
activation UI still prints misleading `Project file: no (permission required)`
even though permission was correctly skipped.

---

## Evidence — 2026-07-27 reopen

### Session

- ✔️ Session `08-25-18`: `edit_mode` `complete_file` →
  `docs/plans/0.1-base-plan.md` (not `write_file`).
- ✔️ UI activate frame:

  ```text
  Edit Mode Activated
  Edit mode activated for file: …/docs/plans/0.1-base-plan.md
  File status: will be created or is outside index
  Project file: no (permission required)
  ```

  ℹ️ `EditMode/Request.to_summary` uses **only**
  `file_cache.has_key` — not the path-under-project gate used by
  `build_perm_question`. Misleading label; permission path was fine.

- ✔️ Disk: file present at `08:26:38` (907 bytes).
- ✔️ SQLite `filebase` id `110648` for the plan file (+ parent dirs).

### Client log (`ollmchat.debug.log`)

```text
08:26:09  Tool 'edit_mode' does not require permission
08:26:38  Folder.contains_folder  (id=16)     ← leftover gate in line-apply path
08:26:38  File.write              (id=17) replied
08:26:38  File.register           (id=18) replied
08:26:38  CRITICAL oll_mfiles_project_manager_get_file_cache: assertion 'self != NULL' failed
08:26:38  CRITICAL gee_abstract_map_set: assertion 'self != NULL' failed
08:26:38  Successfully applied changes to file …/0.1-base-plan.md
08:26:38  CRITICAL oll_mfiles_project_manager_get_review_files: assertion 'self != NULL' failed
08:26:38  CRITICAL oll_mfiles_review_files_refresh: assertion 'self != NULL' failed
08:26:41  SearchableDropdown popup show filtered=0
```

- ✔️ **A worked:** register ran (prefix gate).
- ✔️ **E confirmed:** after `File.register`, `copy_from` overwrites
  `this.manager` with null from the RPC-hydrated row →
  `file_cache.set` and `review_files.refresh` both abort.
- ✔️ No `event.project.invalidate_cache` notification in client log for this run
  (filesystem / vector notifications do log).
- ✔️ Open-project race still visible earlier same session:

  ```text
  08:25:10  ProjectFiles refresh done total=0 loaded=0
  08:25:10  event.filesystem.scan_start
  08:25:10  event.filesystem.scan_end
  ```

  No later successful `fetch_files` before the create.

### Daemon / DB

- ✔️ `File.write` then `File.register` (register finds row already created by
  write’s daemon `to_real`).
- ✔️ `filebase.is_need_approval = 0`, `last_change_type = ''` for id 110648.
- ✔️ No `file_history` row for the plan path.
- ✔️ Global pending count: `is_need_approval=1` → **0**.

So even if client refresh had not crashed, `Folder.fetch_pending_approvals`
would return empty — daemon never marked the file pending.

---

## Root cause (updated)

### Still true from 2026-07-25

✔️ **A** — Permission vs register gate mismatch (prefix vs `contains_folder`) —
**fixed and verified** on this run (register called).

✔️ **B** — Open-project `fetch_files` can still win the race / leave
`total=0` with no post-scan reload (**B′** still open).

### New / reinstated (why UI still broken)

✔️ **E — `copy_from` clears `manager` after `File.register` / `File.read`:**
RPC `parse_object` builds `File` with `manager == null`. Client
`File.register` / `File.read` `copy_from` except lists omit `"manager"`.
Same root cause as
[`2026-07-05-CLOSED-file-read-null-manager-changed-banner.md`](done/2026-07-05-CLOSED-file-read-null-manager-changed-banner.md)
(deferred, never applied). Immediate effect after create:
cache insert fails, approvals refresh fails, later RPCs on that `File` are unsafe.

✔️ **F — Approval / changed-files data path never written on daemon:**
`EditMode` / `WriteFile` set `file.is_need_approval` / `last_change_type` on the
**client** object only. `File.write` RPC does not send those fields;
daemon `write` / `to_real` / `realize` do not set `is_need_approval` or insert
pending `file_history`. Comment claims “daemon records on register/write” —
it does not. Pending list query requires both `is_need_approval = 1` and a
`file_history.status = 0` row → always empty for agent creates.

💩 **C′ — invalidate may not be reaching UI this run:** code emits on
`to_real`; client log shows none. Needs targeted debug (or confirm running
daemon binary includes the emit). Pull-down emptiness is already explained by
pre-create `total=0` + no successful post-register refresh (E).

ℹ️ **2.6.2** covers Approvals popover sizing / open-first-file UX — orthogonal
polish once the list is populated; do not treat 2.6.2 alone as the data bug.

🚫 Do not “fix” by null-checking `manager` before RPC.
🚫 Do not re-prompt permission for under-project creates.

---

## Proposed fix (await approval)

Edits are **Remove** / **Replace with** / **Add** from the tree; verify
surrounding context before applying.

| Item | Ready to apply? |
|------|-----------------|
| **E1** / **E2** `copy_from` skip `manager` | ✔️ applied |
| **F1** / **F2** daemon history + approval | ✔️ applied |
| **A′** drop dead `contains_folder` in Stream | ✔️ applied |
| **G** `to_summary` under-project label | ✔️ applied |
| **B′** / **C′** | 💩 debug only — no fences yet |

ℹ️ **Coding standards check** (router + universal + scenario slugs
`temporary-variables`, `this-prefix`, `reducing-nesting`,
`defensive-code-null-checks`, `method-names-new-methods`,
`line-length-breaking`, `string-interpolation`, `glib-namespace-prefix`,
`null-coalescing`, `switch-case`, `agent-compliance-gate`):

- ✔️ **E1/E2**, **A′**, **F1** — clean (`var`, `this.`, no new helpers, match
  surrounding / `Folder.to_real` history pattern).
- ✔️ **F2** — dropped defensive `active_project != null` on invalidate (match
  existing `to_real` emit); keep `db != null` like current `File.to_real`
  test path.
- ✔️ **G** — replaced nested status ternary with flat `if` + simple ternary.

---

### E1 — `libocfiles/File.vala` — `read()`: keep live `manager` across RPC merge

**Why:** RPC row is `GLib.Object.new` → `manager == null`. Merging without
excepting `manager` clears the live client `File.manager` (CLOSED 2026-07-05).

**Where:** `read()`, the `copy_from` call after a non-empty `response.result`.

**Depends on:** none.

#### Remove

```vala
				this.copy_from((File) files.get(0), {
					"buffer",
					"parent",
					"cursor-line",
					"cursor-offset",
					"scroll-position",
					"is-unsaved",
				});
```

#### Replace with

Preserve the instance `manager` (same pattern as `FileHistory.revert`).

```vala
				this.copy_from((File) files.get(0), {
					"manager",
					"buffer",
					"parent",
					"cursor-line",
					"cursor-offset",
					"scroll-position",
					"is-unsaved",
				});
```

---

### E2 — `libocfiles/File.vala` — `register()`: keep live `manager` across RPC merge

**Why:** Same null-`manager` wipe; this is the create path that fired the
08:26:38 criticals (`file_cache.set` / `review_files.refresh`).

**Where:** `register()`, the `copy_from` call after a non-empty `response.result`.

**Depends on:** none (pair with E1).

#### Remove

```vala
				this.copy_from((File) files.get(0), {
					"buffer",
					"parent",
					"cursor-line",
					"cursor-offset",
					"scroll-position",
					"is-unsaved",
				});
```

#### Replace with

```vala
				this.copy_from((File) files.get(0), {
					"manager",
					"buffer",
					"parent",
					"cursor-line",
					"cursor-offset",
					"scroll-position",
					"is-unsaved",
				});
```

---

### F1 — `ollmfilesd/File.vala` — `to_real()`: pending history + approval for adds

**Why:** `Folder.to_real` already inserts `FileHistory("added")`. `File.to_real`
indexes the row and emits `invalidate_cache` but never sets
`is_need_approval` / `last_change_type` or a pending `file_history` row —
so `fetch_pending_approvals` stays empty after agent creates.

**Where:** `to_real()`, replace the `if (this.manager.db != null) { saveToDB… }`
block so history runs **after** the first `saveToDB` (real `id` assigned).

**Depends on:** none. **F2** covers modifies.

🔷 **Added files:** `FileHistory.commit` does **not** create a backup for
`change_type == "added"` (reject = remove / no prior content). That matches
existing `FileHistory` rules.

#### Remove

```vala
			if (this.manager.db != null) {
				this.saveToDB(this.manager.db, null, false);
			}
```

#### Replace with

After index insert: mark pending, commit `added` history, persist flags.

```vala
			if (this.manager.db != null) {
				this.saveToDB(this.manager.db, null, false);
				this.is_need_approval = true;
				this.last_change_type = "added";
				var file_history = new FileHistory(
					this.manager.db,
					this,
					"added",
					new GLib.DateTime.now_local()
				);
				yield file_history.commit();
				this.saveToDB(this.manager.db, null, false);
			}
```

---

### F2 — `ollmfilesd/File.vala` — `write()` default (file) branch: pending history for modifies

**Why:** Agent `File.write` on an already-indexed file never records pending
history. Backup must run **before** `realize` overwrites disk (same order as
old client `create_file_history` → apply). UI save uses
`buffer.sync_to_file`, not this RPC — so marking write RPC as needing approval
does not flag ordinary editor saves.

**Where:** private `write()`, `default:` case (regular file), from
`get_file_from_active_project` through `realize`.

**Depends on:** **F1** for the `id < 0` → `to_real` add path.

#### Remove

```vala
					default: {
						var file = this.manager.get_file_from_active_project(
							p.path
						);
						if (file == null) {
							file = new File(this.manager) {
								path = p.path,
								id = -1
							};
						}
						if (file.id < 0) {
							yield file.to_real();
						}
						yield file.realize(p);
						break;
					}
```

#### Replace with

Capture add vs modify before `to_real`; for modify, history+flags before
`realize`, then `invalidate_cache` so Approvals/FileDropdown refresh.

```vala
					default: {
						var file = this.manager.get_file_from_active_project(
							p.path
						);
						if (file == null) {
							file = new File(this.manager) {
								path = p.path,
								id = -1
							};
						}
						var change_type = file.id < 0 ? "added" : "modified";
						if (file.id < 0) {
							yield file.to_real();
						}
						if (change_type == "modified" && this.manager.db != null) {
							file.is_need_approval = true;
							file.last_change_type = "modified";
							var file_history = new FileHistory(
								this.manager.db,
								file,
								"modified",
								new GLib.DateTime.now_local()
							);
							yield file_history.commit();
							file.saveToDB(this.manager.db, null, false);
						}
						yield file.realize(p);
						if (change_type == "modified") {
							this.manager.notification(new OLLMrpc.Notification() {
								method = "event.project.invalidate_cache",
								object_type = "Project",
								message = this.manager.active_project.path
							});
						}
						break;
					}
```

---

### A′ — `liboctools/EditMode/Stream.vala` — drop dead `contains_folder` before apply

**Why:** After **A**, `is_in_project` lives only in `sync_and_update_metadata`
(prefix gate). This block still RPCs `contains_folder` then never uses the
flag — wasted call; log noise at 08:26:38 id=16.

**Where:** line-apply path immediately before `create_buffer` /
`validate_complete_file_changes`.

**Depends on:** none.

#### Remove

```vala
			var project_manager = this.file.manager;
			var normalized_path = this.request.normalized_path;
			var is_in_project = (this.file.id > 0);
			
			if (!is_in_project && project_manager.active_project != null) {
				var dir_path = GLib.Path.get_dirname(normalized_path);
				if (yield project_manager.active_project.contains_folder(dir_path)) {
					is_in_project = true;
				}
			}
			
			this.file.manager.buffer_provider.create_buffer(this.file);
```

#### Replace with

```vala
			this.file.manager.buffer_provider.create_buffer(this.file);
```

---

### G — `liboctools/EditMode/Request.vala` — `to_summary()`: under-project label

**Why:** Activation UI said `Project file: no (permission required)` while
`build_perm_question` correctly skipped permission via path prefix. Summary
must use the same under-project rule as permission.

**Where:** `to_summary()`, from `norm` through the returned string.

**Depends on:** none.

#### Remove

```vala
			var norm = this.normalize_file_path (this.file_path);
			var project_manager = ((Tool) this.tool).project_manager;
			var is_in_project = project_manager.file_cache.has_key(norm);
			return "Edit mode activated for file: " + norm + "\n"
				+ "File status: " + (is_in_project ? "exists" : "will be created or is outside index") + "\n"
				+ "Project file: " + (is_in_project ? "yes (auto-approved)" : "no (permission required)");
```

#### Replace with

Index hit → exists; under-project path → create without permission; else outside.
Flat status assignment (no nested ternary — `reducing-nesting`).

```vala
			var norm = this.normalize_file_path (this.file_path);
			var project_manager = ((Tool) this.tool).project_manager;
			var in_index = project_manager.file_cache.has_key(norm);
			var is_in_project = in_index;
			if (!is_in_project && project_manager.active_project != null) {
				var dir_path = GLib.Path.get_dirname(norm);
				if (dir_path == project_manager.active_project.path
					|| dir_path.has_prefix(project_manager.active_project.path + "/")) {
					is_in_project = true;
				}
			}
			var status = "will be created or is outside index";
			if (is_in_project) {
				status = in_index ? "exists" : "will be created";
			}
			return "Edit mode activated for file: " + norm + "\n"
				+ "File status: " + status + "\n"
				+ "Project file: " + (is_in_project ? "yes (auto-approved)" : "no (permission required)");
```

---

### B′ / C′ — follow-ups (no fences yet)

⏳ Confirm `wait_scan_idle` holds before first reply when scan starts after
`fetch_files` is already in flight; confirm `invalidate_cache` is emitted and
received after write’s daemon `to_real` (F1 keeps the existing emit).

---

## Prior analysis (2026-07-25) — condensed

Original failure on `app.RooTerm`: `write_file` → **Project file: no** because
register used `contains_folder(exact parent)` while permission used path prefix.
Close/reopen: scan indexed the file; UI `fetch_files` returned `total=0`
before scan finished and never reloaded.

Applied then (still in tree): A prefix gates; B `wait_scan_idle` + client
`loading`; C `invalidate_cache` emit + SourceView/Approvals listeners.

Those were necessary but **not sufficient** — reopen shows register succeeds
and UI still fails for **E** + **F**.

---

## Attempts / changelog

- ✔️ 2026-07-25: A/B/C applied; user closed as FIXED.
- ✔️ 2026-07-27: Reproduced via session `08-25-18` + cache logs; moved bug
  back to `docs/bugs/`; linked CLOSED null-manager + plan 2.6.2.
- ✔️ 2026-07-27: Applied E1/E2, F1/F2, A′, G; `ninja -C build` clean.

---

## Next

1. ⏳ ✅ User verify: create new file under project → pull-down shows it; Approvals / changed-files lists it; no `manager` criticals.
2. ⏳ 💩 Trace **C′** invalidate on live daemon if pull-down still stale.
3. ⏳ Keep **2.6.2** as UX follow-up once the list has rows.
