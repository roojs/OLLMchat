# ORCA-1.0 — summary

> **ON HOLD** — skills / conductor / task-orchestration track. Not pursuing for now; Agent Pi under [`CODER`](CODER-1.0-summary.md) is the active coder approach. Archived plans live in [`done/`](done/) with **`ON-HOLD`** in the slug.

**Prefix:** `ORCA` · **All categories:** [`-README.md`](-README.md)

Code for this track still lives under `liboccoder` (SkillRunner, task pipeline, Action layer, progress tree). These plans describe the orchestrator design we started and then paused.

---

## Status

We are **not actively developing ORCA** for the time being. Open work is archived as **ON-HOLD** so it stays findable if we resume. Prefer Agent Pi (`CODER-6.1*`) for new coding-agent work.

---

## 1.23 — Skills agent & Conductor

Original vision: a **SkillRunner** agent that loads skill markdown from `resources/skills` and runs a **Conductor** as the first skill — a process enforcer/router that phases work (research → planning → implementation → review → finalize) and directs other skills rather than doing the work itself. Much of the task-list / refine / execute pipeline that grew out of this line is already in the tree (see historical `done/1.23.*`); the parent conductor plan itself was never finished as a product surface.

**Archived:** [ORCA-1.23-ON-HOLD-skills-agent-conductor.md](done/ORCA-1.23-ON-HOLD-skills-agent-conductor.md)

### 1.23.30 — Reference content length validation

Deferred hardening for the task-list path: after parse, resolve reference content the same way as precursor injection and reject (or force a creator retry) when any resolved block exceeds a configured max length. Optional HTTP URL sanity checks at list stage. Not started.

**Archived:** [ORCA-1.23.30-ON-HOLD-reference-content-length-validation.md](done/ORCA-1.23.30-ON-HOLD-reference-content-length-validation.md)

### 1.23.31 — File reference anchors / AST

Validate `file_path#anchor` beyond “file exists”: confirm the hash resolves to a real markdown heading slug and/or AST symbol, aligned with how `link_content` injects those refs. Not started.

**Archived:** [ORCA-1.23.31-ON-HOLD-reference-file-anchor-ast.md](done/ORCA-1.23.31-ON-HOLD-reference-file-anchor-ast.md)

---

## 6.0 — Unified task / plan file format

Consolidate plan/task file conventions (`Status:` as source of truth, summary generation, archive naming) so ORCA task docs and the plans tree stay consistent. Parked with the rest of the orchestrator track.

**Archived:** [ORCA-6.0-ON-HOLD-unified-task-file-format.md](done/ORCA-6.0-ON-HOLD-unified-task-file-format.md)

---

## 6.3 — Consolidate task-list outputs

Merge multi-file task outputs from create/iteration into a single `.task.md`-style file (frontmatter + definition + execution log) so the agent and tools do not scatter context across many files.

**Archived:** [ORCA-6.3-ON-HOLD-consolidate-task-list-outputs.md](done/ORCA-6.3-ON-HOLD-consolidate-task-list-outputs.md)

---

## 7.14 — Task progress / replay UI (open follow-ups)

Skills progress tree and session continue/replay polish that sat under CODER; belongs with the ORCA runner UX. Core progress tree work already shipped (`done/7.14*`); these are leftover open slices.

### 7.14.6 — Continue / replay-as-new / “start from here”

Backend + UI for continuing a skill session from a review point (`replay_as_new`, continue-from-here). ChatView control was already on hold; parent continue plan unfinished.

**Archived:** [ORCA-7.14.6-ON-HOLD-continue-replay-as-new.md](done/ORCA-7.14.6-ON-HOLD-continue-replay-as-new.md), [ORCA-7.14.6-ON-HOLD-chatview-start-from-here.md](done/ORCA-7.14.6-ON-HOLD-chatview-start-from-here.md)

### 7.14.11 — Tool-call summary on replay

Persist `tool-call-summary` in the transcript so progress-tree tooltips survive restore/replay (today `tool_request` is null when execute is skipped).

**Archived:** [ORCA-7.14.11-ON-HOLD-tool-call-summary-replay-tooltip.md](done/ORCA-7.14.11-ON-HOLD-tool-call-summary-replay-tooltip.md)

### 7.14.14 / 7.14.15 — Progress collapse header

Collapse the progress ColumnView behind a “Skill activity” header (default collapsed), and when collapsed show the active row title instead of a static label.

**Archived:** [ORCA-7.14.14-ON-HOLD-progress-tree-collapse-header.md](done/ORCA-7.14.14-ON-HOLD-progress-tree-collapse-header.md), [ORCA-7.14.15-ON-HOLD-progress-header-active-title.md](done/ORCA-7.14.15-ON-HOLD-progress-header-active-title.md)

---

## 7.16 — Iterative task execution loop

Parent for turning path-B execution into a **task iteration** loop: refine schedules one tool call, then iterate (summary + optional next tool) with cumulative history until the model stops. Path A (exam-only) mostly unchanged. Includes Action-layer design, session schema bump, and dropping multi-tool refine/merge on B. Partially implemented; remaining work parked.

**Archived:** [ORCA-7.16-ON-HOLD-iterative-task-execution-loop.md](done/ORCA-7.16-ON-HOLD-iterative-task-execution-loop.md)

### 7.16.1 — Copy execution into `Action.*`

Landed: copy task execution into `liboccoder/Action/`, with `Action.Base` extending chat agent base and extraction helpers on Base. Prep for looping; wiring incomplete.

**Archived:** [ORCA-7.16.1-ON-HOLD-action-copy.md](done/ORCA-7.16.1-ON-HOLD-action-copy.md)

### 7.16.1b — Wire `Action.*` into `Details`

In progress when paused: extraction/build done; still needed `Details.run_action` dispatch and trimming duplicated `run_exec` / `run_post_exec` bodies.

**Archived:** [ORCA-7.16.1b-ON-HOLD-action-wire.md](done/ORCA-7.16.1b-ON-HOLD-action-wire.md)

### 7.16.2 — Session markers and replay

Proposed: bump skill-session `schema_version`, richer transcript markers, replay hydrated from Action runs; old sessions non-replayable or chat-only.

**Archived:** [ORCA-7.16.2-ON-HOLD-session-markers-replay.md](done/ORCA-7.16.2-ON-HOLD-session-markers-replay.md)

### 7.16.3 — `Action.Iterate` and wire-in

Proposed: replace path-B `RunTools` with `Action.Iterate` (one refine tool, then iteration loop, tool-call history, cycle cap, `task_iteration` stage).

**Archived:** [ORCA-7.16.3-ON-HOLD-action-iterate-wire.md](done/ORCA-7.16.3-ON-HOLD-action-iterate-wire.md)

### 7.16.4 — Iterate collateral

Proposed close-out: prompts, parser, skills, progress labels, docs, and cleanup once Iterate ships (rename post-exec → task iteration, drop legacy multi-tool refine).

**Archived:** [ORCA-7.16.4-ON-HOLD-iterate-collateral.md](done/ORCA-7.16.4-ON-HOLD-iterate-collateral.md)

---

## Related

- [`CODER`](CODER-1.0-summary.md) — Agent Pi (active coder approach)
- [`docs/task-and-skills-flow.md`](../task-and-skills-flow.md) — current skills/task pipeline behaviour
- Historical done work under `done/1.23.*` / `done/7.14*` (unprefixed era) remains the changelog for what already shipped
