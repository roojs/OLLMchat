---
name: plan_apply_changes
description: Use when you need to write revised plan content to the plan file. One job only: apply/write; do not read or produce the content (use plan_iterate to produce revisions, or use plan_review for proposed changes). Ensure the content to write is in Precursor (e.g. from plan_iterate or plan_review output).
tools: write_file
---

## Plan apply changes skill

**One job:** Writes the plan file. Does **not** read files or produce the revised content; content and path come from **Precursor** (e.g. from a prior **plan_iterate** or **plan_review** task whose output is in References). Use after plan_iterate (or after incorporating plan_review proposed changes into revised content) to persist the plan.

### Input (this skill)

From the standard input, **What is needed** is the plan path to write to (or "Apply the revised plan to docs/plans/X.md"). **Precursor** contains the **content to write** (e.g. the Detail or output from plan_iterate with the full revised plan text) and the **plan_path** (from the prior task or Skill call). The refinement step passes **plan_path** and ensures References include the task that produced the revised content so it is in Precursor.

### Output (this skill)

Result summary and the file path written. Result summary: **summary of what this task did** (wrote the plan to path X) and **whether that addressed the goal**. No file read; one write only.

### Instructions

#### Refinement

- Pass **plan_path** (full path to the plan file to write). Ensure the task's **References** include the **plan_iterate** (or other) task output that contains the revised plan content, so the executor has the content in Precursor. Do not emit read_file.

#### Execution (what to do with the results)

- Take the revised plan content from Precursor (from the referenced plan_iterate or plan_review output). Use **write_file** with **plan_path** and that content. Do not read the file first; write only.
- **Result summary**: what this task did (wrote plan to …) and that the goal was addressed. Return the plan file path.

### Example

**Input:** plan_path = `docs/plans/add_writer_approval_gate.md`; Precursor = revised plan content from plan_iterate output (via Reference).

**Output:** Result summary: Wrote the revised plan to `docs/plans/add_writer_approval_gate.md` — goal addressed. File path: `docs/plans/add_writer_approval_gate.md`
