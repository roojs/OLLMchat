---
name: plan_create
description: Use when creating a new plan after research and analysis are done; plan needs objectives, steps, and references from prior research/code analysis. Do not use before research — do not jump in and assume; run research_topic/research_pages and/or analyze_codebase/analyze_code (and optionally analyze_code_standards) first so the plan has concrete references.
tools: write_file
---

## Plan create skill

Creates a new plan document for a coding task. The plan includes objectives, step-by-step implementation steps, and references to code locations or research.

### Input (this skill)

From the standard input, **What is needed** gives the high-level goal; **Precursor** may include research_topic/research_pages, analyze_codebase/analyze_code, analyze_docsbase/analyze_docs, or analyze_code_standards outputs (via References to prior task results). The refinement step typically passes: **plan_title** (for filename, e.g. "Add async runner step"), **task_description** (what needs to be done); research_summary and code_analysis come from precursor when referenced.

### Output (this skill)

Result summary and the file path of the created plan (e.g. `docs/plans/add_async_runner_step.md`). Result summary: **summary of what this task did** (created a plan with objective, steps, references) and **whether that addressed the goal**.

### Instructions

#### Refinement

- Pass **plan_title** (for filename, e.g. "Add async runner step"), **task_description** (what needs to be done). If the task References include prior research, analysis, or code-standards outputs, they are in Precursor. No tool calls required unless the refiner needs a file read; the executor uses Precursor to build the plan.

#### Execution (what to do with the results)

- Determine the file name: convert **plan_title** to a suitable filename (lowercase, underscores) and place in `docs/plans/` (e.g. `docs/plans/add_async_runner_step.md`).
- Use the **write_file** tool to create the file with: **Objective**, **Research summary** (from precursor or "None"), **Code analysis** (from precursor or "None"), **Coding standards** (from analyze_code_standards if referenced, or "None"), **Implementation steps** (numbered, concrete), **Code references** (file paths or methods to modify). Populate from What is needed and Precursor; steps should be concrete (e.g. "Add async method to Runner", "Add null check in Definition.load()").
- Write **Result summary**: what this task did (created the plan) and whether it addressed the goal. Return the file path (e.g. in Result summary or as main output).

### Example

**Input:**

- `plan_title = "Add writer approval gate"`
- `task_description = "Before running writer tasks, request user approval once per run."`
- `research_summary = "UI pattern: single confirmation dialog then proceed with all writer tasks."`
- `code_analysis = "Runner.handle_task_list() runs tasks; has request_writer_approval stub."`

**Output:** Result summary: Created plan at `docs/plans/add_writer_approval_gate.md` with objective, steps, and code references — ready for review. File path: `docs/plans/add_writer_approval_gate.md`
