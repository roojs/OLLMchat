# OPEN: Task progress strip — rows dropped (`step_list=other`) and stuck execution on replay

**Status: OPEN**

**Related:** `Runner.on_replay`, `ProgressList.clear_pending`, `List.move_step_to_completed`, `ResultParser.exec_extract` / `parse_task_list_iteration`, `ValidateLink`.

**Log prefixes (grep):** `REPLAY MESSAGE`, `REPLAY TASK ITERATION`, `REPLAY POST EXEC`, `REPLAY EXECUTION EXTRACT`, `REPLAY EXECUTION TOOL DONE`, `REPLAY EXECUTION DETAIL DONE`, `REPLAY EXEC VALIDATE STAGE`, `REPLAY UNHANDLED`, `PROGRESS REBUILD`, `PROGRESS RUNNER ROW`, `PROGRESS CLEAR PENDING`, `PROGRESS ADD PENDING`, `PROGRESS STEP DONE`, `PROGRESS CLEAR ALL`, `TASK LIST MOVE STEP`, `TASK LIST RUN EXEC`, `LIVE EXECUTION EXTRACT`.

## Purpose (this bug doc)

- Record repro, constraints, what logs showed, what **not** to ship again.
- Point to **one** implementation plan: **`docs/plans/2026-05-07-proposed-replay-hydration-link-validation.md`**.

## Problem

- Strip rows lost after iteration / rebuild (**`step_list=other`**, orphan **`Step`**).
- Tools stuck (**`REPLAY EXECUTION EXTRACT`** **`ok=false`**) or post-exec issues (**`post_issues_len>0`**).

## Constraints (author)

- **Design:** Bookkeeping fix size — no redesign.
- **Iteration:** Transcript at **task list iteration** ⇒ prior **full step** should be done (replay should match).
- **Replay vs live:** Replay-only env errors ⇒ replay bug; transcript = ground truth.

## Evidence (logs)

**Run:** **`ollmchat --debug`** (**`ApplicationInterface.debug_log`**).

**Seen:**

- **`REPLAY TASK ITERATION CONTENT`** **`issues_empty=false`**
- **`PROGRESS CLEAR PENDING drop`** **`step_list=other`**
- **`REPLAY EXECUTION EXTRACT`** **`ok=false`** / **`Invalid reference target`**

### Capture **`/tmp/log.txt`** (2026-05-07)

Proves GTK restore never saw **`in_replay`** until **`Runner.on_replay`** was wrapped (**plan §### 1**):

- **`REPLAY HYDRATE FLAGS`** · **`in_replay=false`** on **every** message (sample: **`idx=0`** … **`idx=61`**).
- **`VALIDATE LINK ALL`** · **`runner_in_replay=false`** during **`LIST`** / **`REFINEMENT`** / **`EXECUTION`**.
- **`REPLAY POST EXEC`** **`research-current-file-formats`** · **`post_issues_len=137`** · **`exec_done=false`** · **`detail_status=POST_EXEC`** — link validation filled **`parser.issues`** while hydrating from transcript.
- **`REPLAY TASK ITERATION`** · blocking child **`research-current-file-formats`** **`exec_done=false`** · **`SWAP`** · **`issues_empty=false`** → **`PROGRESS CLEAR PENDING`** **`step_list=other`** **`orphan_list=true`** (matches **H1** chain).

**Fix applied (same session):** **`docs/plans/2026-05-07-proposed-replay-hydration-link-validation.md`** **`### 1`** + **`### 2`** — **`in_replay`** during **`on_replay`**; **`ValidateLink.validate_all`** no-op when **`runner.in_replay`**. Re-run restore and grep **`REPLAY HYDRATE FLAGS`** (**`in_replay=true`**) and **`REPLAY POST EXEC outcome`** (**`issues_empty=true`** for env-only failures).

## Hypotheses vs logs

No single confirmed root cause — table is **hypothesis → log signal → status**.

| Id | Hypothesis | Log signal | Status |
|----|------------|------------|--------|
| **H1** | Iteration swaps **`pending`** before step **`exec_done`** / **`move_step_to_completed`** → orphan rows | **`REPLAY TASK ITERATION STEP`** **`exec_done=false`** · **`blocking child`** **`exec_done=false`** · **`SWAP`** · **no** **`TASK LIST MOVE STEP`** · **`orphan_list=true`** | **Matches** captured logs — primary strip bug chain |
| **H2** | Row **`detail_completed`** but **Step** on wrong list | **`detail_completed=true`** + **`orphan_list=true`** same rebuild | **Observed** |
| **H3** | **`exec_done`** never set → feeds **H1** | **`ok=false`** · **`post_issues_len>0`** | **Confirmed** **`/tmp/log.txt`**: hydrate **`in_replay=false`** · **`VALIDATE LINK ALL`** **`runner_in_replay=false`** · **`post_issues_len=137`** → **`exec_done=false`** · **H1** · **fix: §### 1** + **§### 2** |

**Next fix (hydration):** **`docs/plans/2026-05-07-proposed-replay-hydration-link-validation.md`** **`## Concrete code proposals`** (**### 1** then **### 2**).

**If H1 remains after that:** cursor / **`move_step_to_completed`** — use **§ Debug gaps** optional lines.

### Debug gaps (optional — only if H1 persists)

| Prefix | Place | Fields |
|--------|-------|--------|
| **`REPLAY HYDRATE FLAGS`** | Start **`Runner.on_replay`** after **`can_replay`** guard | **`idx`** **`can_replay`** **`in_replay`** |
| **`REPLAY POST EXEC hydrate`** | Before **`exec_post_extract`** in **`POST_EXEC`** **`content-stream`** | **`slug`** **`runner_in_replay`** |

Remove when **FIXED**.

## Attempted fix (reverted — do not repeat)

- **Idea:** Restore old **`pending`** on task-list-iteration parse failure.
- **Result:** Transcript advanced but **`pending`** stayed stale → wrong tree.
- **Git:** Do not reintroduce that **`Runner`** branch.

## Observation (`in_replay` vs GTK)

ℹ️ **`in_replay`** only set in **`Runner.replay()`**.

ℹ️ **`restore_messages`** calls **`on_replay`** without **`Runner.replay()`** → **`in_replay`** false on GTK restore.

🔷 Approved implementation: **`docs/plans/2026-05-07-proposed-replay-hydration-link-validation.md`**.

🚫 No **`SessionBase.restoring_history`**.

## Debug added (2026-05-03)

| File | Prefix |
|------|--------|
| `Runner.vala` | **`REPLAY TASK ITERATION STEP`** |
| `Runner.vala` | **`REPLAY TASK ITERATION SWAP`** |
| `List.vala` | **`TASK LIST MOVE STEP`** |
| `ProgressList.vala` | **`PROGRESS CLEAR PENDING drop`** (**`detail_completed`**, **`orphan_list`**) |

Remove after **FIXED**.

## Reproduction

1. **`ninja -C build`**
2. Multi-step session · iteration · bad refs / missing paths.
3. Grep prefixes above.

## Follow-ups

- **⏳** Re-open session with **`--debug`** · confirm **`REPLAY HYDRATE FLAGS`** **`in_replay=true`** · no **`step_list=other`** on same repro · then mark bug **FIXED** if clean
- **⏳** If **H1** still · **§ Debug gaps**
- **ℹ️** Related **FIXED** replay bugs · **`docs/bugs/2026-04-07-FIXED-*.md`**

## Changelog

- 2026-05-03 — OPEN · constraints · debug table · repro.
- 2026-05-03 — ALL CAPS log prefixes.
- 2026-05-03 — **`REPLAY TASK ITERATION STEP`** rename.
- 2026-05-07 — Reverted **`ValidateLink`** / **`restoring_history`** experiments · plan-only proposals.
- 2026-05-07 — Hypotheses table · debug gaps · trimmed prose (**guide-to-writing-plans** style).
- 2026-05-07 — Evidence from **`/tmp/log.txt`** (**H3**/**H1** chain) · implemented **`2026-05-07-proposed-replay-hydration-link-validation.md`** **`### 1`** **`### 2`** (**`Runner.on_replay`** **`in_replay`** save/set at start · restore at end · **`ValidateLink.validate_all`** skip when **`in_replay`**).
