---
name: plan_iterate
description: Use when you need to produce revised plan content from an existing plan; do not use to create a new plan (use plan_create) or to write the file (use plan_apply_changes).
tools:
---

## Refinement

**Purpose of this skill:** Produce revised plan content from an existing plan; the executor needs the previous plan and what to change (e.g. feedback, new steps). Refinement fills in **References** so the executor can deliver what is needed.

You receive **what is needed** for this task and a **summary of the task list so far executed** (including output summaries from previous tasks). Fill in **References** so the executor can deliver what is needed — e.g. plan file or plan content, review feedback, and relevant sections from prior task outputs. **Avoid whole files** — add **code sections** or **references to parts of a task output** (e.g. file + section/method/snippet) rather than full file contents.

---

Input: the **previous plan** (in References — refiner ensures the plan file or plan content is in Precursor) and **What is needed** (what to change, e.g. "Add step for error handling", "Incorporate review feedback"). Take the input, goals, and the previous plan and produce **revised plan content**. Output the revised plan as your response (Result summary + plan body). Apply the requested changes while keeping the plan structure (Status, Purpose, Problem Summary, numbered sections, etc.). Do **not** code initially; describe changes. If the work involves complexity, use **phases**.

**Summary — outstanding items:** It is **very important** that the summary contains any items that are **outstanding** and need to be looked at. If the revised plan is complete, say so and that the next step can be **implement_code** or **plan_apply_changes** as appropriate. If there are gaps, list them clearly.

**This skill does not write a file.** In the summary, say what the **next task** should be: if the user wants the revised plan written to the plan file, next task: **plan_apply_changes**. Otherwise suggest more research, further iteration, or implement_code as appropriate.

**Always use link references** when referring to files or sections.

Use the same plan section types as plan_create (## Status, ## Purpose, ## Problem Summary, numbered ## 1. …, ## 2. …, Phases, Related Plans, Deliverables, etc.) for the revised plan body.

### Example output

Use the fixed header **## Result summary**; then the revised plan body with standard plan section headings.

## Result summary

Produced revised plan for [add writer approval gate](docs/plans/add_writer_approval_gate.md): added logging step and cancel-handling. See [Status](#status), [Purpose](#purpose), [Problem Summary](#problem-summary), and numbered sections below. **Outstanding:** none. Revised plan is complete; next task: **plan_apply_changes** to write to file (or **implement_code** if user prefers to proceed to implementation).

## Status

⏳ PENDING

## Purpose

…

(Full revised plan body with ## 1. …, ## 2. …, etc., as in plan_create.)
