# Desktop review: accepting visible hunks should clear the whole pending stack

**Status:** ⏳

## User decisions required

None. — Target approved: last visible Accept → full approve in DB; tab + bar stay open; sync must not close or hide. — Tests: build **A + B + C** together (headless DB, widget stub, visual), not pick-one.

## Client repaint constraints

- 🚫 **2026-11-26 — user:** A client fix that **fully reloads** the file and **re-renders the whole document** — delete/clear the editor buffer and **reinsert the entire text** from scratch (e.g. wholesale `set_text`, “open the file again” repaint, or `File.read` solely to nuke the view before painting) — is **not acceptable** and will be **rejected**.
- 🔷 Partial accept / stacked hunks must stay **surgical**: incremental `ChangeView` / `apply_parts`, drop stale tags and GtkSource marks on accepted spans, and feed `proposal` from **plain** file text **without** replacing the whole buffer. See [source view diff tags after accept](done/2026-11-15-FIXED-source-view-diff-tags-after-accept.md) for the intended incremental story.
- 🔷 **Review timing (2026-11-26):** User reviews **once**, when Phase 1b is **finished** (surgical code in tree, `test-stacked-review-scenario` green, **Proposed fix** updated to match). **Not** for in-progress turns, abandoned drafts, or “stop and approve” mid-implementation.

## User reported

- 🔷 On desktop, open a file that needs approval with **three** visible diff hunks that do not line up cleanly with the buffer.
- 🔷 After accepting hunks, **green** diff highlighting can remain.
- 🔷 After accepting the **third** visible hunk, those matches go away and a **new** set of hunks appears for the same file.
- 🔷 The file was modified **many** times before review; approving what is on screen should approve **everything** on that path up to the current disk contents, not another chunk of history.
- 🔷 After approve: keep file open and review UI; real approve in DB, not provisional.

## Desired behavior

✅ on a line = **works today** (agent mark — correct if wrong). No tick = **gap / bug**.

- Open a file the agent changed **many times** before you reviewed it (e.g. `test-file.txt`).
  - ✅ Editor opens on that path.
  - ✅ Review bar shows the file in the queue.
  - Red/green highlights are the **whole** pending change for this visit — not “three hunks now, three different hunks later” on the same open file.
- Accept hunks one by one in the bar (or Accept on each band).
  - ✅ Accept is recorded; the bar moves to the next hunk.
  - ✅ Accepted bits can show as normal text (not still red/green).
  - No leftover green on lines you already accepted in **this** pass.
  - **No** new red/green appearing for the **same** file because the app still had an older unread change queued behind the scenes.
- Accept the **last** hunk you can see for that file.
  - File is marked fully approved in storage (nothing left “waiting for OK” for that path).
  - File drops off the “needs review” list.
  - ✅ Tab stays open after approve (editor does not jump away or close the tab).
  - Review bar stays on screen after approve; sync from the server must not hide it or treat it as “nothing left to do, tear down UI”.
    - Today when that works, the footer label often reads **“Changes accepted”** — that label is **not** the requirement; you want **bar visible**, file still open, not a second diff wave. Relabel / chrome is open.
- While you are still accepting hunks (optional, clarity):
  - Red/green should show **all** agent edits you have not **Accepted** yet for this file — not a slice from one intermediate autosave in the middle of a long run.
  - ✅ New files: highlights compare to **empty file** (that case works today).

## Run demo (phase 1)

**Headless (CI):**

```bash
ninja -C build tests/test-stacked-review-scenario
./tests/run-stacked-review-demo.sh
```

- Auto Accept 3 hunks; asserts queue clear, no second wave.
- Tab + bar: `meson test test-stacked-review-widget`.

**Visual sign-off (Tier C):**

```bash
ninja -C build tests/test-stacked-review-scenario
./tests/run-stacked-review-visual-demo.sh
```

- Same stub as headless demo; opens a window — **you** click Accept on each hunk, confirm **Changes accepted** / empty queue, close window.
- Needs `DISPLAY`. Real `ollmfilesd` + gtktest1 optional after rebuild daemon for live DB stack.

## Current behavior

- Symptom only: after the last visible accept, another hunk set can load; file can still look pending. Details → **LLM** (repro + gtktest1 DB).

## Codebase observed behavior

- [`FileWithHistory.pending`](../../ollmfilesd/FileWithHistory.vala) sets `approve_id` to the **newest** `reviewed = 0` row for the file (subquery `ORDER BY timestamp DESC LIMIT 1`).
- [`SourceView.show_pending_diff`](../../liboccoder/SourceView.vala) loads [`FileHistory.parts`](../../ollmfilesd/FileHistory.vala) for that `approve_id` only — one history chunk at a time.
- [`FileHistory.rebuild_parts`](../../ollmfilesd/FileHistory.vala) diffs that row’s `backup_path` vs project disk unless the **oldest** pending row is `added` with empty `backup_path` (then backup side is empty).
- [`FileDiffPart.commit`](../../ollmfilesd/FileDiffPart.vala) when the last hunk on a chunk closes:
  - Marks only that `file_history_id` `reviewed = 1`.
  - If other `reviewed = 0` rows remain, calls `FileHistory.approve` **only** when oldest pending is `added` + empty backup (`stack_added && action == 1`); otherwise sets `since_id` on the next pending row and returns — client refresh loads **parts for the next chunk**.
- [`FileHistory.approve`](../../ollmfilesd/FileHistory.vala) already marks **all** `reviewed = 0` rows on the path reviewed and clears `is_need_approval`.
- [`SourceView`](../../liboccoder/SourceView.vala) `review_files.refreshed` handler calls `show_pending_diff` again while the path stays in the pending map — repaints the next chunk’s hunks.

## Debugging

### Current debug output

- `~/.local/share/ollmchat/files.sqlite` — **2026-11-24** (agent query, user’s `gtktest1` session):
  - `filebase` `113056` — `/home/alan/gitlive/gtktest1/test-file.txt`, `is_need_approval = 1`.
  - `file_history` — `reviewed = 0` rows `43162`–`43180` (nineteen stacked `modified` chunks); newer rows `43181`+ already `reviewed = 1`.
  - `file_diff_part` counts per open chunk include `10` parts on `43173`, `4` on `43165` and `43180`, mostly `2` elsewhere.

### Debug code added (remove when complete)

None.

## Proposed fix

### Phase 1 — Applied: full path approve on last visible hunk accept (daemon)

- Why
  - After the last hunk on the head chunk, commit only bulk-approved when oldest pending was `stack_added`; stacked `modified` only poked `since_id` → client loaded the next chunk’s hunks.
- Change
  - When the chunk closes and more `reviewed = 0` rows remain, **`action == 1`** calls existing `FileHistory.approve` (clears all pending on path). Reject/other actions still poke `since_id` on the next row.
- **Remove** (`ollmfilesd/FileDiffPart.vala`, stacked-close branch inside `left.size > 0`):

```vala
				var oldest = new Gee.ArrayList<FileHistory>();
				FileHistory.query(db).select(
					"WHERE path = '" + histories.get(0).path.replace("'", "''") +
						"' AND reviewed = 0 ORDER BY id ASC LIMIT 1",
					oldest
				);
				var stack_added = oldest.size > 0
					&& oldest.get(0).change_type == "added"
					&& oldest.get(0).backup_path == "";
				if (stack_added && action == 1) {
					… approve …
					return;
				}
				left.get(0).since_id = poke;
```

- **Replace with:**

```vala
				if (action == 1) {
					… same resolve row + histories.get(0).approve(db, row) …
					return;
				}
				left.get(0).since_id = poke;
```

- Verify
  - `meson test test-stacked-review-scenario test-stacked-review-widget` pass; manual gtktest1 after rebuild `ollmfilesd`.
- Client
  - No `SourceView` change required if queue clears on refresh (Tier B already expects empty pending + bar visible).

### Phase 1b — Client partial-accept paint (proposed, **not applied** — 2026-11-26)

- Status
  - **⏳** Not started in tree (agent to implement surgical direction, then mark **✔️** here and point user at one **Proposed fix** pass — no review until then).
- Why
  - Headless `test-stacked-review-scenario` fails after 1st Accept: accepted hunk line still has `diff-*` GtkSource marks (tags can clear; marks linger).
  - `ChangeView.proposal` uses `file.buffer.get_text()` while the editor buffer holds **diff-expanded** text (remove/add lines), so accepted runs and gaps use wrong line slices after repaint.
  - Incremental `apply_parts` can **skip** spans (`compare` + `unchanged` match) and leave stale source marks on accepted lines.
  - After last hunk: `send_part` refreshes queue; `review_files.refreshed` can run **sync** `proposal`/`apply` on the same stale buffer → ghost lines (e.g. `three|THREE|four`).
- Surgical direction (implement this; **final** Remove/Replace blocks appear below only when complete)
  - **Plain text for `proposal`:** pass disk/project text into `proposal` (e.g. field set on read, or RPC `msg` from last `File.read`), not the painted `GtkSource.Buffer` text.
  - **`apply_parts`:** when a hunk flips to decided (`unchanged` + `accepted != 0`), **replace** buffer span and strip `diff-add` / `diff-remove` tags and marks on that span; extend existing [source view diff tags after accept](done/2026-11-15-FIXED-source-view-diff-tags-after-accept.md) rules (`unchanged` compare, `accepted` on proposed parts).
  - **Chunk close:** paint decided parts once (incremental or final `apply_parts` pass), then refresh; avoid second sync paint in `refreshed` on a stale buffer (async hand-off or skip if `part_sending` / chunk just closed).
  - **Verify:** `./build/tests/test-stacked-review-scenario` headless three Accepts; per-step audit: accepted lines clean, pending lines still red/green; final buffer `one|two|three|four`.
- ~~Abandoned agent draft (reference only — do not review)~~ — [`liboccoder/ChangeView.vala`](../../liboccoder/ChangeView.vala)
  - **Add** `accepted = inc.accepted` when building decided `unchanged` part in `proposal` (so `apply` can detect decided hunks).
  - **Replace** `apply` entry guard:

```vala
// Remove
			if (this.parts.size > 0) {
				this.apply_parts(next);
				return;
			}

// Replace with (still uses full set_text when any decided hunk — violates constraint)
			var full_repaint = false;
			foreach (var part in next.parts) {
				if (part.accepted != 0) {
					full_repaint = true;
					break;
				}
			}
			if (this.parts.size > 0 && !full_repaint) {
				this.apply_parts(next);
				return;
			}
```

  - **Add** before `set_text` in full-apply path (wipe before full insert — **violates constraint**):

```vala
			Gtk.TextIter wipe_start;
			Gtk.TextIter wipe_end;
			this.buffer.get_bounds(out wipe_start, out wipe_end);
			this.buffer.remove_all_tags(wipe_start, wipe_end);
			this.buffer.remove_source_marks(wipe_start, wipe_end, null);
```

- WIP draft — [`liboccoder/SourceView.vala`](../../liboccoder/SourceView.vala)
  - **`show_pending_diff`:** **Add** `yield file.read()` before `proposal` when `parts.size > 0` — **violates constraint**; replace with plain-text source for `proposal` instead.
  - **Add** method `repaint_review_parts` (same read + proposal + apply) — **violates constraint**; chunk-close path should call incremental paint only.
  - **`review_files.refreshed`:** **Replace** sync `proposal`/`apply` on chunk closed with `repaint_review_parts.begin(...)` — direction OK, implementation must not use `File.read` nuke.

```vala
// Remove (chunk_closed branch)
							var proposal = this.change_view.proposal(
								this.current_file, this.review_bar.parts);
							this.change_view.apply(proposal);
							(this.source_view.buffer as GtkSource.Buffer).set_modified(false);
							this.review_bar.update_diff(
								this.review_bar.parts, this.review_bar.file_index);

// Replace with
							this.repaint_review_parts.begin(
								this.current_file, this.review_bar.parts);
```

- WIP draft — [`liboccoder/Diff/ReviewBar.vala`](../../liboccoder/Diff/ReviewBar.vala) — **Add** before `refresh` when chunk closed:

```vala
			if (file != null && !chunk_open && this.parts.size > 0) {
				yield this.source_view.repaint_review_parts(file, this.parts);
				this.update_diff(this.parts, this.file_index);
			}
```

### Phase 2 — Cumulative diff display (optional, not done)

- Why
  - User may still want one diff surface (oldest backup → disk) instead of per-chunk hunks before approve-all; separate from Phase 1 queue semantics.
- Investigate
  - `rebuild_parts` / `approve_id` vs [stacked add diff baseline](done/2026-11-21-FIXED-test-file-stacked-add-diff-baseline.md).

### Phase 3 — Diff baseline vs stacked `modified` (if mismatch persists)

- Why
  - Head-chunk backup vs disk can show red/green that do not match “all edits since last approval”.
- Investigate
  - Whether baseline should follow oldest pending backup (or last approved) for display while still storing per-chunk history — related closed work: [stacked add diff baseline](done/2026-11-21-FIXED-test-file-stacked-add-diff-baseline.md) (empty baseline only for `added`).

### Automated reproduction (test harness)

Goal: replay **disk file + backup cache + SQLite rows** and assert queue / `reviewed` / `is_need_approval` after each accept — not manual gtktest1 clicks.

#### What exists today

- [`examples/oc-test-source-diff`](../../examples/oc-test-source-diff.vala) (**built**)
  - Default: baseline/current **text file pairs** → mock diff only; **no** `FileHistory`, **no** DB.
  - `--selectors` / `--test-flow`: real [`CoderView`](../../liboccoder/) + live **ollmfilesd** (or `ClientBoot`); `--test-flow` only exercises **folder type filters**, not review Accept.
- [`tests/review-flow-test.vala`](../../tests/review-flow-test.vala) (**`meson test`**, `suite: coder`)
  - Real [`SourceView`](../../liboccoder/SourceView.vala) + [`ReviewBar`](../../liboccoder/Diff/ReviewBar.vala); **stub** RPC (`MockDispatch`) with hand-authored `FileWithHistory` + `FileHistory.parts`.
  - Covers queue navigation and `approve_id` hand-off between files; **does not** implement `FileDiffPart.apply` / `FileHistory.decide` or real [`FileDiffPart.commit`](../../ollmfilesd/FileDiffPart.vala).
  - **Cannot** point at a database — all state is in-memory in the stub.
- RPC script suite ([`tests/test-rpc-t2.sh`](../../tests/test-rpc-t2.sh), [`tests/test-rpc-common.sh`](../../tests/test-rpc-common.sh))
  - `OLLMFILES_IS_TEST=1 ollmfilesd --data-dir="$TEST_DIR" --interactive --rpc-script=…`
  - Isolated `files.sqlite` per run; `sqlite_count_ok` helper; fixture tree [`tests/rpc-fixtures/minimal-project`](../../tests/rpc-fixtures/minimal-project).
  - **No** scripts yet for `FileHistory.parts`, `FileDiffPart.apply`, or stacked `file_history`.
- [`examples/oc-test-files`](../../examples/oc-test-files.vala) + [`tests/data/2.edit-test-*-db.sql`](../../tests/data/2.edit-test-6-db.sql)
  - Had `--test-db` and SQL **`filebase`** seeds for edit-tool tests; **`if false`** in [`examples/meson.build`](../../examples/meson.build) (RPC rewrite pending). Seeds do **not** model stacked pending review.

#### Recommended tiers (in build order)

- **Tier A — Daemon RPC replay (CI, no display)**
  - Add tracked fixture e.g. `tests/rpc-fixtures/stacked-review-pending/`:
    - Small project tree with one `test-file.txt` on disk (current content).
    - `files.sqlite` subset: `filebase`, `file_history` (N stacked `modified`, `reviewed=0`), `file_diff_part` for **head** row only (or full set).
    - Copy of `~/.cache/ollmchat/edited/…` backup files referenced by `backup_path` (paths in SQL rewritten to fixture-relative or test `data-dir` cache dir).
  - Shell test: copy fixture → `run_rpc_script` with NDJSON calling `ProjectManager.rpc_activate_project`, `Folder.fetch_pending_approvals`, `FileHistory.parts` (head id), repeated `FileDiffPart.apply` until chunk closes, `fetch_pending_approvals` again.
  - Assert with `sqlite3`: after accepting **all hunks on head chunk**, either whole path is approved (**desired fix**) or next `approve_id` drops to older row (**current bug**); `is_need_approval` and count of `reviewed=0` for path.
  - **Export** from live gtktest1: script to dump rows for one `path` + copy backup files + normalize paths (one-time; refresh when schema changes).

- **Tier B — Extend `test-review-flow`**
  - Teach stub `dispatch` `FileDiffPart.apply` + optional `FileHistory.decide`: mutate in-memory `pending`, `parts`, and `reviewed` flags to mirror [`FileDiffPart.commit`](../../ollmfilesd/FileDiffPart.vala) + `since_id` poke.
  - Add scenario **stacked-same-file**: one path, history ids `3 → 2 → 1`, three hunks on id `3`; after third accept, assert client still on same file vs advances chunk vs clears queue — matches user repro without GTK manual step.
  - Faster than Tier A for **client** refresh logic; does not exercise real `rebuild_parts`.

- **Tier C — `oc-test-source-diff` + isolated daemon (optional visual)**
  - Start `ollmfilesd --data-dir=<fixture>` (same tree as Tier A); run `oc-test-source-diff --selectors` with env/config so `ClientBoot` uses that daemon (today it uses user config / default socket).
  - New `--test-flow-review` (or extend `--test-flow`): open gtktest1 project, open pending file, loop `ReviewBar` Accept via existing widget walk pattern in [`test_flow`](../../examples/oc-test-source-diff.vala).
  - Needs display / headless GTK; keep as supplement, not gate for fix.

#### Success criteria for harness (before Phase 2 product fix)

- Tier A fails on **current** tree: e.g. accept all parts on head `file_history_id`, `is_need_approval` still `1`, nineteen → eighteen `reviewed=0` rows (or `approve_id` steps to older id).
- Tier A passes after Phase 2: one wave of accepts clears path.

## LLM

- ℹ️ Split from user chat **2026-11-24** (desktop approval UX); not the GLib criticals track in [gtktest1 review criticals](done/2026-11-24-FIXED-gtktest1-review-criticals-overlay-run.md) (**✅**).
- ℹ️ Related closed: [review-queue multi-history](done/2026-11-15-FIXED-review-queue-multi-history-and-db-sync.md) (`since_id` poke + client stale queue), [stacked add diff baseline](done/2026-11-21-FIXED-test-file-stacked-add-diff-baseline.md) (`stack_added` bulk approve only).
- ℹ️ Parent harness context: [phone Agent Pi edit-file test](2026-11-23-ISSUE-phone-agent-pi-edit-file-test.md), [desktop write loop](done/2026-11-20-FIXED-desktop-write-file-edit-loop.md).
- 💩 Hypothesis: nineteen pending `modified` rows force **per-chunk** hunk UI; accepting chunk `43180` does not call `FileHistory.approve`, so refresh shows chunk `43179` — matches “new set after third accept”.
- ℹ️ **2026-11-24** — User asked for DB-backed automated repro; inventory + Tier A/B/C plan under **Proposed fix → Automated reproduction**.
- ℹ️ **2026-11-24** — Product intent: server-side full approve for stacked edits; client keeps tab + review bar after refresh ([`ReviewBar.sync_pending`](../../liboccoder/Diff/ReviewBar.vala) already has a “Changes accepted” path when queue is empty but parts are decided — extend that story for stacked modified, avoid `show_pending_diff` loading the next chunk).
- ✔️ User: product target confirmed; test plan = A+B+C in parallel.
- ✔️ Tests: `test-stacked-review-scenario`, `test-stacked-review-widget` pass after Phase 1; `test-rpc-stacked-review` (daemon, `should_fail`), `test-stacked-review-visual` (optional).
- ✔️ Phase 1 product fix in [`FileDiffPart.commit`](../../ollmfilesd/FileDiffPart.vala) (2026-11-24).
- ⏳ Tier A: checked-in `tests/rpc-fixtures/stacked-review/` SQLite seed (history was not persisting from write-only RPC setup).
- ℹ️ Report shape: **Desired behavior** is the spec (action → expect; ✅ = works today). Repro symptoms → **User reported** + **LLM**.
- 🚫 **2026-11-26** — User constraint: **Client repaint constraints** — no full-buffer wipe + full reinsert; any agent proposal that depends on that should be reworked before review.
- ℹ️ **2026-11-26** — User asked to **revert** in-progress client WIP from tree (parallel commits); user reviews **Phase 1b only when complete**, not mid-flight.