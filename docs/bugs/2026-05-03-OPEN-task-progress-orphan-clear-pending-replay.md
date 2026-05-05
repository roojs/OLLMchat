# OPEN: Task progress strip — rows dropped (`step_list=other`) and stuck execution on replay

**Status: OPEN** — Root cause not fully fixed; **instrumentation** added to confirm hypotheses before further code changes.

**Related code:** `liboccoder/Skill/Runner.on_replay` (TASK_LIST_ITERATION), `liboccoder/Task/ProgressList.clear_pending`, `liboccoder/Task/List.move_step_to_completed`, `liboccoder/Task/ResultParser.exec_extract` / `parse_task_list_iteration`, `liboccoder/Task/ValidateLink`.

**Log prefixes (grep):** `REPLAY MESSAGE`, `REPLAY TASK ITERATION` (step / migrated / swap / content), `REPLAY POST EXEC`, `REPLAY EXECUTION EXTRACT`, `REPLAY EXECUTION TOOL DONE`, `REPLAY EXECUTION DETAIL DONE`, `REPLAY EXEC VALIDATE STAGE`, `REPLAY UNHANDLED`, `PROGRESS REBUILD`, `PROGRESS RUNNER ROW`, `PROGRESS CLEAR PENDING`, `PROGRESS ADD PENDING`, `PROGRESS STEP DONE`, `PROGRESS CLEAR ALL`, `TASK LIST MOVE STEP`, `TASK LIST RUN EXEC`, `LIVE EXECUTION EXTRACT`.

## Problem

1. **Progress strip:** After **task list iteration** and **`clear_pending` / `rebuild`**, **completed**-looking task rows **disappear** or the model shows inconsistent rows. Debug showed **`PROGRESS CLEAR PENDING drop`** with **`step_list=other`**: the **`Step`** for a **`Details`** row points at a **list** that is neither **`runner.pending`** nor **`runner.completed`** (orphan list after **`pending`** was replaced).

2. **Stuck “review” / tool row:** **`REPLAY EXECUTION EXTRACT`** … **`ok=false`** when executor output fails **`exec_extract`** (e.g. **invalid reference** to a missing path such as **`.cursor/plans/...`**). The tool run does not reach **COMPLETED** in replay for that message.

**Expected:** Progress rows stay consistent with **pending** / **completed** **Step** lifetimes; replay matches transcript without random tree state.

**Actual:** Orphan **`Step`** references when **`runner.pending`** is replaced before migrate/completed bookkeeping catches up; validation failures leave tools incomplete.

## Constraints (author answers — short)

- **Design:** No redesign of the overall model; fix should match existing intent (**bookkeeping bug**, not “change the design”).
- **Iteration vs step:** If the transcript **reaches task list iteration**, that **implies the previous step (one full step) has completed** — we iterate **after each step**. Replay should line up with that (**`REPLAY TASK ITERATION STEP`** shows **`exec_done`** vs **`TASK LIST MOVE STEP`** / **`is_exec_done()`**).
- **Replay vs live errors:** If **replay** reports validation errors that the **original run did not** have, treat that as a **replay bug** (reconstructing wrong state / order / env). In principle, **errors produced only by replay code** can be **ignored** for judging the **session** — but the **transcript** is still ground truth.
- **Input = ground truth:** **Support what we get in**; **(2)** and **(3)** are the main **replay** health checks (step completed before iteration; replay not inventing failures the session didn’t have).

## Evidence (logs)

Captured with **`ollmchat --debug`** (see **`ApplicationInterface.debug_log`** / project logging conventions).

**Symptoms observed:**

- **`REPLAY TASK ITERATION CONTENT`** with **`issues_empty=false`** — iteration markdown fails validation (e.g. **`task://…`** references to tasks no longer in the new list).
- **`PROGRESS CLEAR PENDING drop`** … **`step_list=other`** — **`det.step.list`** not **pending** or **completed**.
- **`REPLAY EXECUTION EXTRACT`** … **`ok=false`** followed by **`Invalid reference target`** lines — **`exec_extract`** / link validation failure.

**Example hypothesis chain:** **`TASK_LIST_ITERATION`** assigns **`this.pending = new List`**; if **`move_step_to_completed`** did not run (**`is_exec_done()`** false) or steps are otherwise left on the **old** list, existing **`Details`** rows still reference **old** **`Step`** objects → **`clear_pending`** drops them ( **`Step.status` ≠ `COMPLETED_DONE`** and/or orphan list).

## Root cause (working theory — confirm with logs)

| Id | Theory | What would confirm in logs |
|----|--------|---------------------------|
| **Theory 1** | Task list iteration runs before replay thinks the step is done → **no** **`move_step_to_completed`** → **`pending`** list replaced anyway → orphan **Steps** → **clear pending** drops rows (**orphan_list=true**). | **`exec_done=false`** on **`REPLAY TASK ITERATION STEP`**, then **`REPLAY TASK ITERATION SWAP`**; no **`TASK LIST MOVE STEP`**; **`PROGRESS CLEAR PENDING drop`** with **`orphan_list=true`**. |
| **Theory 2** | **`move_step_to_completed`** ran, but a drop still shows the detail as **COMPLETED** while we drop it — mismatch between **row status** and **step/list**. | **`TASK LIST MOVE STEP`** in log; **`PROGRESS CLEAR PENDING drop`** with **`detail_completed=true`**. |
| **Theory 3** | **`exec_extract`** / **`post_exec`** validation fails on **broken links** → task/step never fully “done” in model → worse timing before iteration. | **`REPLAY EXECUTION EXTRACT`** **`ok=false`**, **`REPLAY POST EXEC`** **`post_issues_len>0`**. |

Fix direction: align **Runner** replay with **(2)** — when **task list iteration** runs, the **current** step in replay should **already** be in the same “finished” state live would have had (**`move_step_to_completed`** / exec_done), so **`pending`** swap does not orphan **Steps**. Use logs to see if **`exec_done=false`** at task list iteration is **replay-only** misprediction vs transcript.

## Attempted fix (reverted)

**Idea:** On **task list iteration** parse failure (`**p1.issues != ""**`), **restore** previous **`pending`** before continuing replay.

**Result:** **Worse** — transcript **continues** as if the **new** iteration applied (**refinement** / **exec** target **new** slugs) while **`pending`** was **old** → **replay cursors** and **UI** pointed at the **wrong** tasks (“random” tree).

**Action:** **Reverted.** Do not restore **`pending`** on failed parse without a full replay contract (or a different fix: e.g. reparent steps to **`completed`**, or adjust **`clear_pending`** only).

**Git:** Revert any commit that reintroduces “restore **`pending`** on task list iteration issues” in **`Runner.vala`**.

## Proposed fix (pending): bypass link validation during replay / re-hydration

### Summary

Skip **`ValidateLink`** when **`OLLMcoder.Skill.Runner.in_replay`** is **`true`**, so **`ResultParser.exec_extract`** / **`exec_post_extract`** can populate **`Details`** / **`Tool`** state from transcript text **without** failing on links that depend on **current** workspace state (missing files, moved paths, **`task://`** registry timing).

### Rationale

| Pro | Con / mitigation |
|-----|-------------------|
| Re-hydration matches the **transcript** instead of **today’s disk**; avoids replay-only failures that are not “session truth.” | Restored UI may show markdown whose links are **not** re-checked against the repo until the user acts. |
| **`Runner`** already exposes **`in_replay`** for exactly this kind of branch (see **`Details.run_post_exec`** replay guard on **`session.add_message`**). | Narrow scoping: **live** and **continuation after restore** must still validate. |

**Why acceptable:** After restore, **refinement** and normal **live** execution paths continue to use **`ValidateLink`** unchanged. Replay is **hydration**, not the last line of defense for link correctness.

### Implementation (preferred)

**Single choke-point — `ValidateLink.validate_all`**

At the start of **`validate_all`**, if **`this.details.runner.in_replay`**, **return** without iterating links (no **`validate`** calls). Optionally document on **`ValidateLink`** that replay skips link checks by design.

**Alternative — `ResultParser`**

Omit **`vl_sum.validate_all(...)`** (and any analogous **`ValidateLink`** usage in **`exec_extract`**) when **`task.runner.in_replay`**. More scattered; prefer **`ValidateLink`** unless profiling shows a reason to avoid constructing **`ValidateLink`** at all.

### Evidence this addresses

Log pattern: **`REPLAY POST EXEC`** … **`post_issues_len>0`** immediately adjacent to **`Invalid reference target`** **`… plan.md`** **`file does not exist (resolved from project folder)`** — validation tied to **filesystem**, not transcript integrity.

### Risks (explicit)

- **No** promise that replayed **`agent-issues`** content matches what a full re-parse would emit today.
- If any feature assumed “links validated ⇒ safe to resolve,” that assumption must **not** apply to **`in_replay`** paths only.

### Files to touch

| File | Change |
|------|--------|
| **`liboccoder/Task/ValidateLink.vala`** | Early return in **`validate_all`** when **`details.runner.in_replay`** (and short docblock note). |

**Verify:** **`ninja -C build`**; replay session that previously failed **`POST_EXEC`** / **`EXECUTION`** on missing **`file:`** paths; confirm **`exec_done`** / progress strip align with transcript; then continue session **live** and confirm refinement still surfaces link issues when appropriate.

## Debug added (2026-05-03)

**Purpose:** Confirm **theory 1–3** from one run; **no** product behavior change beyond **`GLib.debug`** (per **`.cursor/rules/CODING_STANDARDS.md`** — no throttling; message text without class/method prefix).

| Location | Prefix | What it logs |
|----------|--------|----------------|
| `Runner.vala` | **`REPLAY TASK ITERATION STEP`** | **`si`**, **`exec_done`**, **`step_title`**, step task count, **`pend_steps`**, **`comp_steps`** before deciding to move the step to completed. |
| `Runner.vala` | **`REPLAY TASK ITERATION SWAP`** | **`pend_steps`**, **`comp_steps`** immediately before **`new List`**. |
| `List.vala` | **`TASK LIST MOVE STEP`** | **`move_step_to_completed`**: index, title, task count, **`pend_steps_before`**, **`comp_steps_before`**. |
| `ProgressList.vala` | **`PROGRESS CLEAR PENDING drop`** | **`detail_completed`**, **`orphan_list`**. |

**Remove:** Delete these lines once the issue is **FIXED** and verified (same as other bug docs).

## Reproduction / verification

1. **`ninja -C build`**
2. Reproduce: session with **multi-step** task list, **task list iteration** that can **fail validation** (bad **`task://`** refs) and/or **executor** output with **invalid file links**.
3. Capture log; grep **`REPLAY TASK ITERATION`**, **`TASK LIST MOVE STEP`**, **`PROGRESS CLEAR PENDING`**, **`REPLAY EXECUTION EXTRACT`**, **`REPLAY POST EXEC`**.

**Closing criteria:** **FIXED** doc with root cause, implementation, and manual log showing no orphan drops in the intended scenario; **or** explicit **WONTFIX** / product decision documented.

## Follow-ups

- **Replay validation bypass:** Implement **“Proposed fix (pending): bypass link validation during replay”** above; then re-check **theory 1** (**`exec_done`** at task list iteration) on the same repro — remaining orphan drops may be bookkeeping only.
- **Theory 1 + constraints:** If transcript has **task list iteration** but **`exec_done=false`** **after** replay validation bypass, treat as cursor / **`move_step_to_completed`** alignment (not environmental link failure).
- **Replay-only errors:** Compare **same idx** live vs replay if disputes remain — **`exec_done`**, cursor.
- Link **FIXED** replay bugs under **`docs/bugs/2026-04-07-FIXED-*.md`** family if cursor/multi-tool overlap.

## Changelog

- 2026-05-03 — **OPEN** doc: problem, evidence, theories, reverted “restore **pending**” attempt, **debug** table, repro / follow-ups.
- 2026-05-03 — **Constraints** section: author answers (design OK; iteration ⇒ prior step done; replay errors vs live; transcript ground truth).
- 2026-05-03 — **Log prefixes:** short **ALL CAPS** (`REPLAY …`, `PROGRESS …`, `TASK LIST …`, `LIVE EXECUTION …`).
- 2026-05-03 — Renamed **`REPLAY TASK ITERATION GATE`** → **`REPLAY TASK ITERATION STEP`** (avoid jargon “gate”).
- 2026-05-03 — **Proposed fix:** bypass **`ValidateLink`** during **`in_replay`** ( **`validate_all`** choke-point); rationale (live/refinement re-validates); evidence (**`file does not exist`** on replay); risks; follow-ups updated.
