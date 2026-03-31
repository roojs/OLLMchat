---
name: plan_iterate
description: Use when revising an existing plan from feedback or new information; not for creating a new plan from scratch (use plan_create).
tools: write_file
---

**During refinement**

**Purpose of this skill:** Produce revised plan content from an existing plan; the executor needs the previous plan and what to change (e.g. feedback, new steps). Refinement fills in **References** so the executor can deliver what is needed.

You receive **what is needed** for this task and a **summary of the task list so far executed** (including output summaries from previous tasks). Fill in **References** so the executor can deliver what is needed — e.g. plan file or plan content, review feedback, and relevant sections from prior task outputs. **Avoid whole files** — add **code sections** or **references to parts of a task output** (e.g. file + section/method/snippet) rather than full file contents.

When the user wants the **revised plan written to disk**, include the **target plan path** (usually the existing plan file — absolute or repo-relative) in **What is needed** or **References** so **Change details** can set **file_path**. If no path is given and choosing one would be guesswork, give **Result summary** only: explain what to add or refine next, recommendations, and the **`no changes needed`** line — **no** **Change details** that write a file.

---

Input: the **previous plan** (in **References** — ensure the plan file or relevant plan sections are in **Precursor**) and **What is needed** (what to change, e.g. "Add step for error handling", "Incorporate review feedback"). Produce revisions as targeted plan edits. Apply the requested changes while keeping the plan structure (**Status**, **Purpose**, **Problem Summary**, numbered sections, etc.). Do **not** code initially; describe changes. If the work involves complexity, use **phases**.

**When writing revised plan changes to a file:** **`## Result summary`** first (prose with links), then one or more **`## Change details`** sections.

- Default to **`output_mode` `replace`** for iterative plan updates. Include **`file_path`**, **`output_mode`** `replace`, then two fenced blocks: existing excerpt (must uniquely match) and replacement text.
- Use **`output_mode` `fenced`** only when you have a precise target (**`ast_path`** + **`location`**, or line-range fields) and only that section should be replaced.
- Use full-file rewrite (**`complete_file`** + **`next_section`**) only when the user explicitly asks for a full regenerated plan, or when targeted edits are not viable and full replacement is clearly intended.

When **file_path** cannot be chosen safely or **What is needed** is too vague to write a file: **Result summary** only — specific blocker, actionable recommendations, and the **`no changes needed`** signal. Do **not** emit **Change details** for a file you cannot justify.

**Summary — outstanding items:** It is **very important** that **Result summary** mentions any items that are **outstanding** and need follow-up. If the revised plan is complete, say so; next step can be **implement_code**, or further **plan_iterate** / research as appropriate.

**Always use link references** when referring to files or sections.

Use the same plan section types as **plan_create** (**## Status**, **## Purpose**, **## Problem Summary**, numbered **## 1. …**, **## 2. …**, Phases, Related Plans, Deliverables, etc.) when editing affected sections.

### Example output (write revised plan — `replace`)

Use **`## Result summary`** first, then **`## Change details`** with **`file_path`** and **`output_mode`** **`replace`**, followed by two fenced blocks: existing excerpt, then replacement.

**Example:**

## Result summary

Revised [add_writer_approval_gate.md](/path/to/docs/plans/add_writer_approval_gate.md) with logging and cancel-handling updates in [Section 2](#change-details). **Outstanding:** none. Next step: **implement_code**.

## Change details

- **file_path** docs/plans/add_writer_approval_gate.md
- **output_mode** replace

```markdown
## 2. Execution flow

- Prompt user for approval before write phase.
- If rejected, abort and return status.
```

```markdown
## 2. Execution flow

- Prompt user for approval before write phase.
- If rejected, abort and return status.
- Add cancel-handling branch and user-facing message.
- Add structured logging for approval decisions.
```
