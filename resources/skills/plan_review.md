---
name: plan_review
description: Use when reviewing a plan against coding standards and API usage; run after plan_create or plan_iterate when standards exist (e.g. after analyze_code_standards). Do not use without the plan in References; do not skip if coding standards were researched — always run after creating or updating a plan to ensure correctness. Run before implement_code.
tools:
---

## Plan review skill

**One job:** Reviews a plan against coding standards and API usage; outputs issues and proposed changes. Does **not** read or write files; the plan and standards come via **References** (refiner adds links so Precursor has the plan and any coding-standards docs). **When coding standards have been researched and are available:** always run this after **plan_create** or after **plan_iterate** / **plan_apply_changes** so the plan stays correct before implementation.

### Input (this skill)

From the standard input, **What is needed** is the review focus (e.g. "Review plan for coding standards", "Verify API usage in implementation steps"). **Precursor** includes the plan (via Reference to the plan file — refiner adds the link; no read_file) and ideally **analyze_code_standards** output or references to coding-standards docs. The refinement step passes **plan_path**; ensure References include the plan file (and optionally code files the plan references) so their content is in Precursor.

### Output (this skill)

Result summary and Detail. Result summary: **summary of what this task did** (reviewed the plan for standards and API usage) and **whether the plan is ready** or what issues were found. **Detail must contain:** (1) **Issues that need rectifying** — deviations from coding standards (with links to the standards), API or usage concerns; (2) **Proposed changes** — concrete edits or steps to fix each issue. If there are no issues, state that the plan aligns with standards and APIs and is ready for implementation.

### Instructions

#### Refinement

- Pass **plan_path** (path to the plan file). **Do not emit read_file.** Ensure the task's **References** include the plan file (and optionally analyze_code_standards results or coding-standards docs, and any code files the plan references) so the executor has everything in Precursor.

#### Execution (what to do with the results)

- Read the plan from Precursor (and any code snippets or referenced files). Compare implementation steps and described code to:
  - **Coding standards** — use References/Precursor to standards (e.g. from analyze_code_standards); note any violations and link to the relevant standard.
  - **API usage** — verify that APIs, methods, and patterns mentioned in the plan exist and are used correctly in the codebase (or in the plan’s intended changes).
- **Result summary**: what this task did (reviewed plan for standards and API) and outcome (ready / issues found).
- **Detail**: (1) **Issues that need rectifying** — list each deviation or concern with a link to the relevant standard where applicable; (2) **Proposed changes** — for each issue, give a concrete proposed change (edit or step) so the plan can be updated (e.g. via plan_iterate then plan_apply_changes). If no issues, state that the plan aligns with standards and APIs. End with "Plan ready for implementation" or "Address the issues above (e.g. using plan_iterate then plan_apply_changes) before implementation."

### Example

**Input:** plan_path = `docs/plans/add_writer_approval_gate.md`; Precursor includes plan content and references to CODING_STANDARDS.md / analyze_code_standards output.

**Output:** Result summary: Reviewed the plan against project standards and Runner API; one issue found (see Detail). Detail: **Issues that need rectifying:** Step 3 describes inline dialog creation; [CODING_STANDARDS](/path/to/.cursor/rules/CODING_STANDARDS.md) recommends using the existing dialog helper. **Proposed changes:** Revise step 3 to "Call DialogHelper.confirm() instead of creating a new dialog; pass the message from the plan." API — Runner.handle_task_list() and request_writer_approval usage match codebase. Address the style issue above (e.g. using plan_iterate then plan_apply_changes) before implementation.
