# Vector scan does not start / ActivityBanner shows no vector indexing

**Status:** **FIXED** — verified 2026-07-09 (embed race, path capture, filesystem gitignore / `copy_from`)

**Started:** 2026-07-09

**Process:** `docs/bug-fix-process.md`

**Related:**

- [`docs/plans/2.10.4.30-ACTIVE-startup-and-daemon-status-ui.md`](../plans/2.10.4.30-ACTIVE-startup-and-daemon-status-ui.md) — ActivityBanner + daemon activity wiring
- [`docs/plans/done/2.10.4.14-DONE-daemon-scan-update-notification.md`](../plans/done/2.10.4.14-DONE-daemon-scan-update-notification.md) — `event.vector.*` wire format
- [`docs/plans/done/2.10.4.29-DONE-vector-cli-rpc-migration.md`](../plans/done/2.10.4.29-DONE-vector-cli-rpc-migration.md) — vector queue lives in `ollmfilesd`
- [`docs/bugs/done/2026-05-15-FIXED-background-scan-ui-sluggish.md`](done/2026-05-15-FIXED-background-scan-ui-sluggish.md) — prior background scan behaviour (pre-RPC daemon)

---

## Problem

After plan **2.10.4.30** work (`ActivityBanner`, deferred project load, daemon activity notifications), **vector indexing does not appear to run** in normal desktop use: the activity banner does not show *Vector indexing…* progress, and semantic index work that previously happened on project open may not be happening at all.

**Expected:**

- On project activate (session restore or manual open), daemon runs filesystem scan then background vector queue.
- Client receives `event.vector.scan_start`, `event.vector.scan_update`, `event.vector.scan_end` on the RPC notification channel.
- `ActivityBanner` shows *Vector indexing: \<file\> — X/Y* with a progress bar.

**Actual (user report, 2026-07-08 / 2026-07-09):**

- User does **not** see vector scan starting in the UI after build + test.
- Embed / analysis models **are** configured and have worked for months in Settings (`~/.config/ollmchat/config.2.json`: `codebase_search.embed` → `bge-m3:latest`, `analysis` → `qwen3.6:latest`, connection `https://ollama.roojs.com/api`).
- Filesystem scan notifications may appear; vector phase does not.

---

## Investigation loop

Follow **`docs/bug-fix-process.md`**. **Only debug code may be added without approval**; remove unhelpful debug in the same round — do not accumulate layers.

Each **round** is one pass through this loop. Stop when evidence is enough to confirm or rule out hypotheses, then **report** (update this doc) before proposing a fix.

| Step | Action |
|------|--------|
| **1 — Strategy** | Pick **one** hypothesis (or one narrow question). State what would confirm or rule it out. |
| **2 — Instrument** | Add **minimal** `GLib.debug()` (or use existing lines) at the boundaries that answer the question. **Remove** any debug from prior rounds that did not help. |
| **3 — Run** | Reproduce with **CLI tools first** (§ Reproduce B/C below), then desktop if needed. Capture logs / command output — do not guess. |
| **4 — Report** | Update **Round log**, **Evidence**, **Hypotheses** status, **Attempts / changelog**. Say what is ruled in/out. |
| **5 — Continue or stop** | If still uncertain → next round with a **new** strategy (back to step 1). If certain → **Propose fix** (§ below) and wait for approval. **No product fix without approval.** |

**Agent must not:** splatter debug across the tree; keep stale debug from failed rounds; apply a fix before evidence and approval; skip CLI verification when it can answer the question.

### Round log

| Round | Strategy | Instrumentation | Run | Result |
|-------|----------|-----------------|-----|--------|
| **R1** | Baseline CLI: does Reproduce **B** (`--scan-project`) vs **C** (`--rpc-script`) agree? Is harness C valid? | Existing debug only | B + C (see commands below) | **B ✅** — embed probe OK, 2 files indexed, ~14s. **C ❌ as test** — daemon exits before `open_vector_db.begin()` (`Application.vala` ~301–306 returns early when `--rpc-script` set; that call is at ~335). Activate’s `yield read_dir` never finishes; only `event.filesystem.scan_start` seen. **H1 strengthened** by code review: production path uses un-awaited `open_vector_db.begin()`; `queue_project` silent when `dimension==0`. |
| **R2** | **H1 timeline** — on interactive daemon that stays alive, does `queue_project` hit before `open_vector_db` completes? | `vector index dimension=%d` at end of `open_vector_db`; skip logs in `queue_project` (unset vs dimension=0) | Reproduce **D** (interactive stdin) | **H1 confirmed** — skip `vector_db unset` at +4 ms after filesystem scan; `dimension=1024` ~1.2 s later. No `queue project` / `event.vector.*`. |
| **R3** | **Causal proof** — if activate waits until after probe, does vector indexing + notifications work? | Existing debug only | Reproduce **D** with **5 s delay** before `activate_project` | **100% causal** — `dimension=1024` first, then `queue project`, 2 files queued, full `event.vector.scan_start/update/end` on stdout. H4/H6 ruled out when queue runs. |
| **R4** | **No recovery** — after probe completes on fast activate, is `queue_project` ever called again? | `activate vector queue path=` in `ProjectManager`; `probe done dimension= active=` in `open_vector_db` (replaces bare dimension log) | Fast Reproduce **D** (0.2 s delay) | **100% no recovery** — skip at activate; probe done ~1.2 s later with `active=<path>` but **zero** subsequent `queue project`. Bug is permanent for that activate. |
| **Fix** | Yield for embed probe (15 s timeout) before `queue_project` on activate; fatal exit if probe fails | Coalesced `open_vector_db` via `open_vector_db_wait` promise | Fast Reproduce **D** post-fix | **✅** — 2 files queued, full `event.vector.*` without artificial delay |
| **R5** | Why is main project slow before `event.vector.scan_start`? | Boundary debug: `scan yield returned scanning_active=`, `defer check`, `filesystem idle`, `scan complete` | OLLMchat activate, interactive | **Two delays:** (1) ~7 s — vector waits for `background_recurse` subtree scan (`scanning_active` 195→0); `event.filesystem.scan_end` fires at ~7 ms with 10 files while scan still running. (2) ~3 min 20 s — `queueProject` walks 54709 files to build queue. |
| **R6** | Deferred callback path garbage (`POTFILES.skip`, `(null)`) | Remove `owned SourceFunc`; resolve path from `active_project` at callback | Same repro | **Bug fixed** — `event.vector.scan_start` on main project after ~3.5 min total |

---

## Reproduce

### A — Desktop app (primary report)

1. Ensure Ollama / remote embed endpoint reachable and `codebase_search` models configured (as above).
2. Build: `ninja -C build`.
3. Run: `build/ollmapp/ollmchat --debug`.
4. Open or restore a session with an active project (e.g. `OLLMchat`).
5. Watch header **`ActivityBanner`** during / after filesystem scan.

**Observe:** No *Vector indexing…* banner; no vector progress bar.

**Optional log grep** (`~/.cache/ollmchat/ollmchat.debug.log` and `ollmfilesd.debug.log`):

```bash
rg 'event\.vector\.|vector index|scan-project vector' ~/.cache/ollmchat/*.debug.log
```

### B — CLI isolated daemon (`--scan-project`, diagnostic only)

```bash
TEST_DIR=/tmp/ollm-scan-$$
mkdir -p "$TEST_DIR"
cp -a tests/rpc-fixtures/minimal-project "$TEST_DIR/minimal"
PROJ=$(cd "$TEST_DIR/minimal" && pwd)

build/ollmfilesd/ollmfilesd --debug \
  --data-dir="$TEST_DIR/data" \
  --scan-project="$PROJ" \
  2>&1 | rg 'scan-project|vector index|event\.vector'
```

**Note:** `--scan-project` exits after scan (no RPC listener). It is **not** the production daemon path but useful to time filesystem vs vector phases; it **awaits** `open_vector_db()` before queueing (unlike socket startup).

### C — Interactive RPC harness (`--rpc-script`; limited)

```bash
TEST_DIR=/tmp/ollm-rpc-$$
mkdir -p "$TEST_DIR/projects"
cp -a tests/rpc-fixtures/minimal-project "$TEST_DIR/projects/minimal"
PROJ=$(cd "$TEST_DIR/projects/minimal" && pwd)

cat >"$TEST_DIR/script" <<EOF
{"id":1,"method":"Daemon.hello","*type":"Request","param":{"*type":"DaemonParams","protocol":1,"client":"notify-test"}}
{"id":2,"method":"ProjectManager.create_project","*type":"Request","param":{"*type":"ProjectParams","path":"$PROJ"}}
{"id":3,"method":"ProjectManager.activate_project","*type":"Request","param":{"*type":"ProjectParams","path":"$PROJ"}}
EOF

OLLMFILES_IS_TEST=1 build/ollmfilesd/ollmfilesd --interactive \
  --data-dir="$TEST_DIR/data" \
  --rpc-script="$TEST_DIR/script" \
  2>&1 | rg 'event\.(filesystem|vector)|vector index'
```

**Note:** `--rpc-script` exits after draining the main loop once (`Application.vala` ~301–306) **before** `open_vector_db.begin()` (~335) and usually before `activate_project`’s async `read_dir` completes. **Not reliable for vector tests** (R1 confirmed).

### D — Interactive stdin (stays alive; production-shaped startup)

```bash
TEST_DIR=/tmp/ollm-stdio-$$
mkdir -p "$TEST_DIR/projects"
cp -a tests/rpc-fixtures/minimal-project "$TEST_DIR/projects/minimal"
PROJ=$(cd "$TEST_DIR/projects/minimal" && pwd)

{
  echo '{"id":1,"method":"Daemon.hello","*type":"Request","param":{"*type":"DaemonParams","protocol":1,"client":"notify-test"}}'
  sleep 0.2
  echo "{\"id\":2,\"method\":\"ProjectManager.create_project\",\"*type\":\"Request\",\"param\":{\"*type\":\"ProjectParams\",\"path\":\"$PROJ\"}}"
  sleep 0.2
  echo "{\"id\":3,\"method\":\"ProjectManager.activate_project\",\"*type\":\"Request\",\"param\":{\"*type\":\"ProjectParams\",\"path\":\"$PROJ\"}}"
  sleep 25
} | OLLMFILES_IS_TEST=1 build/ollmfilesd/ollmfilesd --debug --interactive \
  --data-dir="$TEST_DIR/data" \
  2>&1 | tee "$TEST_DIR/out.log" | rg 'vector index|event\.vector|dimension|skip|activate vector|probe done'
```

### E — Delayed activate (proves fix direction; R3)

Same as **D** but **sleep 5** before `activate_project` (after `create_project`). Probe finishes first → vector queue + notifications run. Use to verify a fix or sanity-check embed config.

---

## Evidence collected (2026-07-08 CLI session)

| Run | Filesystem `event.filesystem.*` | Vector `event.vector.*` | Notes |
|-----|--------------------------------|-------------------------|-------|
| **R1** `--scan-project` fresh data-dir (2026-07-09) | ✅ | ✅ 2 files | Embed probe OK; ~14s |
| **R1** `--rpc-script` harness | ✅ start only | ❌ | Harness exits before `open_vector_db`; invalid test |
| **R2** Reproduce **D** interactive stdin (fast activate) | ✅ | ❌ | Skip `vector_db unset` then `probe done` ~1.2s later — **H1** |
| **R3** Reproduce **E** delayed activate (5 s wait) | ✅ | ✅ full cycle | Probe before activate → 2 files, all `event.vector.*` |
| **R4** Reproduce **D** fast + recovery check | ✅ | ❌ | `probe done active=<path>` but no second `queue project` |
| Interactive RPC + minimal fixture (2026-07-08) | ✅ present | ❌ often absent | Same harness flaw as R1 |
| `--scan-project` + fresh `--data-dir` (before config registration change) | ✅ | ❌ skipped `(no embed model)` | **Misleading message** — user config is valid |
| `--scan-project` after `VectorToolConfig` registration in `ollmfilesd/Application.vala` | ✅ | ✅ 2 files indexed | Only on **fresh temp data-dir**; not retested in app by user |

**User pushback (2026-07-09):** The hypothesis that `ollmfilesd` “does not load config correctly” is **not accepted** — Settings / embed config has been correct for ~9 months and vector search **did work** before the RPC daemon migration UI work. Rebuild + test in the **app** still fails after the registration patch.

---

## Hypotheses (open — not ruled in as root cause)

| ID | Hypothesis | Why it might explain symptoms | Status |
|----|------------|------------------------------|--------|
| **H1** | **`open_vector_db()` race** — `initialize()` ends with `open_vector_db.begin()` (not awaited); `queue_project()` returns immediately when `vector_db` is unset or `dimension == 0`; **no re-queue after probe** | Silent permanent no-op on first activate | **Root cause (R2–R4)** — fast: skip then probe ~1.2s later, no recovery; delayed activate: full vector + notifications |
| **H2** | **Empty vector queue** — all files have `last_vector_scan >= mtime_on_disk()` | No `event.vector.*` even when daemon is healthy | **Ruled out** on fresh fixture (R3 queued 2 files when probe ready) |
| **H3** | **`ollmfilesd` config tool registration** | `check_required_models_available()` → false → dimension 0 | **Ruled out** — R3 probe `dimension=1024` with same config path |
| **H4** | **Notification not reaching client** | Banner never updates though daemon indexes | **Ruled out** as primary — R3 emitted all `event.vector.*` on interactive stdout when queue ran |
| **H5** | **`activate_project` skipped** — already active | No new scan / queue on second app attach | **Open** for reconnect scenarios only; not first-open bug |
| **H6** | **UI wiring** — ActivityBanner handler gap | Daemon emits but banner ignores | **Ruled out** as primary — daemon never emits on fast path (H1); R3 shows wire format OK |
| **H7** | **Long-lived daemon stale state** | `dimension == 0` from failed probe | **Ruled out** as primary — R4 shows valid `dimension=1024` after probe; failure is skipped queue not stale dim |

---

## Code paths (reference)

**Daemon activate → vector queue**

```350:353:ollmfilesd/ProjectManager.vala
			if (this.vector_scan != null) {
				this.vector_scan.queue_project(project);
			}
```

**Queue gated on dimension at call time (silent return)**

```73:78:ollmfilesd/Vector/BackgroundScan.vala
        public void queue_project (OLLMfilesd.Folder? project)
        {
            if (project == null
                || this.project_manager.vector_db.dimension == 0) {
                return;
            }
```

**Vector DB opened asynchronously at daemon boot**

```335:335:ollmfilesd/Application.vala
			this.project_manager.vector_scan.open_vector_db.begin();
```

**Client notification → banner**

```434:438:ollmapp/Window.vala
			this.project_manager.rpc.notification.connect((notif) => {
				GLib.Idle.add(() => {
					this.activity_notification(notif);
					return false;
				});
			});
```

**App vs daemon config load (separate processes)**

- `ollmapp/Application.vala` — `tools_registry.init_config()` **before** `load_config()`.
- `ollmfilesd/Application.vala` — loads its **own** `Config2` via `base_load_config()` (~/.config/ollmchat/config.2.json). Recent change registers `VectorToolConfig` before load (uncommitted / local — verify on branch).

---

## Attempts / changelog

| Date | Change | Result |
|------|--------|--------|
| 2026-07-08 | Extended `--scan-project` to run vector queue after filesystem scan (`Application.vala`) | CLI temp-dir: vector phase runs when embed probe succeeds |
| 2026-07-08 | Register `VectorToolConfig` before `load_config()` in `ollmfilesd/Application.vala` | CLI temp-dir: embed probe succeeds; **user reports app still broken** |
| 2026-07-08 | Temporary diagnostic chain in `BackgroundScan.open_vector_db()` | Reverted — too messy; not the right layer |
| 2026-07-09 | **R1** CLI baseline (`--scan-project` ✅; `--rpc-script` harness invalid) | H1 strengthened; Reproduce C documented as unreliable |
| 2026-07-09 | **R3** delayed activate (Reproduce E) | Causal proof — vector works when probe finishes first |
| 2026-07-09 | **R4** fast activate + no-recovery check | `probe done active=<path>` but no re-queue |
| 2026-07-09 | **Fix** inline wait in `activate_project`; coalesced `open_vector_db` in `BackgroundScan` | CLI fast activate: vector queue + notifications OK |

**Not tried yet (optional after fix):**

- Paired app + daemon logs on desktop repro (confirm banner receives R3-equivalent notifications).
- H5 reconnect: second app attach when project already active.

---

## Conclusions (100% — root cause)

**Root cause:** On daemon startup, `Application.vala` calls `open_vector_db.begin()` without awaiting. When the app (or any client) calls `activate_project` before the embed probe finishes (~1–2 s on remote Ollama), `ProjectManager` calls `queue_project` while `vector_db` is still **null** → silent skip. When the probe completes, **`vector_db` is set but nothing re-queues** — vector indexing never runs for that activate. ActivityBanner never receives `event.vector.*`.

**Proof chain:**

1. **R2** — fast activate: `skip vector_db unset` then `probe done dimension=1024` ~1.2 s later; no vector events.
2. **R3** — delayed activate (probe first): 2 files queued, full `event.vector.scan_start/update/end`.
3. **R4** — `probe done active=<project>` proves probe succeeds and project is active, yet **no** second `queue project` call.

**Ruled out as primary cause:** config/embed (H3), empty queue on fresh project (H2), notification wiring (H4/H6), stale dimension (H7).

**Fix direction (await approval):** Same ordering as `--scan-project` (`yield open_vector_db()` before queue) or defer/re-queue active project when probe completes.

---

## Fix applied (2026-07-09)

**`ProjectManager.activate_project`** — before `queue_project`, `yield open_vector_db()` when unset (15 s `GLib.Timeout` then fatal exit). No background probe at daemon startup; probe runs on first activate only.

| **R7** | **Gitignore / queue size** — why ~50k files queued? `is_repo=0` on root; `copy_from` clobbered `is_ignored` | Boundary debug at enumerate + `read_dir_update` | `--scan-project` | **Fixed** — root `is_repo=1`; `subprojects/` `is_ignored=1`; `project_files` 1,280; FS scan ~6 s; vector re-enabled |

---

## Conclusions (filesystem gitignore — R7)

**Root cause:** `discover_repository()` returned early when `is_repo==0`, so the project root never re-attached git. `read_dir_update` called `copy_from` with underscore except names that did not match GObject properties (`is-ignored`), so scan-time `is_ignored=true` was overwritten from stale DB rows.

**Fix:** `discover_repository(bool force)` on project folders; `copy_from` except uses dash names; `Copyable` fatals on underscore except names; preserve `is-ignored` / `is-repo` on rescan.

---

## Proposed next steps

~~Verify in desktop app (Reproduce A)~~ — user confirmed scanning and notifying OK (2026-07-09). Bug closed.

**Optional follow-up:** soft-delete stale `subprojects/` rows left in DB from pre-fix scans.

---

## Verification plan (when fix exists)

1. Cold start: kill `ollmfilesd`, launch app, restore project with known unindexed files → banner shows filesystem then vector progress.
2. Daemon log + client log both contain matching `event.vector.scan_start` / `scan_update` / `scan_end`.
3. Second app startup on same daemon — behaviour documented (re-scan vs skip) matches product intent.
4. `--scan-project` remains a useful CLI diagnostic; not a substitute for socket notification test.
