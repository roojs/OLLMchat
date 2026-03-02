---
name: plan_iterate
description: Use when you need to produce revised plan content (proposed changes or full revised plan) from an existing plan; do not use to create a new plan (use plan_create) or to write the file (use plan_apply_changes). Ensure the plan is in References so Precursor has the current content.
tools:
---

## Plan iterate skill

**One job:** Produces the iteration — revised plan content or a clear list of proposed changes. Does **not** read or write files; the existing plan and any inputs come via **References** (refiner adds link to the plan file so Precursor has the content). A separate **plan_apply_changes** task writes the result to the plan file.

### Input (this skill)

From the standard input, **What is needed** describes what to change (e.g. "Add step for error handling", "Incorporate review feedback", "Split step 3 into two steps"). **Precursor** contains the existing plan content (via Reference to the plan file — refiner adds the link; no read_file). The refinement step passes **plan_path** (for downstream use) and **change_description** (concrete description of edits).

### Output (this skill)

Result summary and Detail. **Detail must contain** the **revised plan content** (full plan text with the requested changes applied, keeping structure: Objective, Research summary, Code analysis, Coding standards, Implementation steps, Code references) so that **plan_apply_changes** can write it to the plan path. Result summary: what this task did (produced revised plan content for X, Y) and that it is ready for plan_apply_changes.

### Instructions

#### Refinement

- Pass **plan_path** (full path to the existing plan file) and **change_description** (concrete description of edits). **Do not emit read_file** — ensure the task's **References** include the plan file so the executor receives the current plan content in Precursor.

#### Execution (what to do with the results)

- Use the plan content from Precursor (from References). Apply the requested changes in memory (revise steps, add/remove sections, incorporate feedback) while keeping the plan structure.
- Output the **full revised plan content** in **Detail** (or in a single block so plan_apply_changes can use it). Do not write any file; plan_apply_changes does that.
- **Result summary**: what this task did (produced revised plan with …) and that the content is ready for plan_apply_changes.

### Example

**Input:** plan_path = `docs/plans/add_writer_approval_gate.md`, change_description = "Add a step to log when approval is requested; add error handling if user cancels." Precursor = existing plan content (via Reference).

**Output:** Result summary: Produced revised plan content adding logging and cancel-handling steps — ready for plan_apply_changes. Detail: [full revised plan markdown text]
