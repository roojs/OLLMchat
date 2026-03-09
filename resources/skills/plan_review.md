---
name: plan_review
description: Use when reviewing a plan against coding standards and API usage; run after plan_create or plan_iterate when standards exist (e.g. after analyze_code_standards). Run before implement_code.
tools:
---

## Refinement

**Purpose of this skill:** Review the plan against coding standards and API usage; the executor needs the plan, any coding standards (e.g. from analyze_code_standards), and code the plan references. Refinement fills in **References** so the executor can deliver what is needed.

You receive **what is needed** for this task and a **summary of the task list so far executed** (including output summaries from previous tasks). Fill in **References** so the executor can deliver what is needed — e.g. plan file, standards outputs, and relevant code. **Avoid whole files** — add **code sections** or **references to parts of a task output** (e.g. file + section/method/snippet) rather than full file contents.

---

## Execution

Read the **plan** and any **coding standards** (and referenced code) from Precursor. Compare the plan's implementation steps and described code to:

- **Coding standards** — Note any violations; link to the relevant standard (e.g. from analyze_code_standards).
- **API usage** — Verify that APIs, methods, and patterns mentioned in the plan exist and are used correctly.

Follow the **task execution output format** (Result summary + body section with descriptive title; list sections of your output as links in Result summary). **Result summary:** What this task did (reviewed plan for standards and API) and outcome — **ready for implementation** or **issues found** (and what to do next). If you do not have access to the API reference (or coding standards) and it was not provided, state that in Result summary so it can be researched and this task called again. **Body section** (e.g. "Review findings: issues and proposed changes"): (1) **Issues that need rectifying** — each deviation or concern with a link to the relevant standard where applicable; (2) **Proposed changes** — for each issue, a concrete proposed edit or step so the plan can be updated (e.g. via plan_iterate then plan_apply_changes). If there are no issues, state that the plan aligns with standards and APIs and is ready for implementation.

### Example output

## Result summary

Reviewed the plan against project standards and Runner API. One issue found. See [Review findings: issues and proposed changes](#review-findings-issues-and-proposed-changes) — [Issues that need rectifying](#issues-that-need-rectifying), [Proposed changes](#proposed-changes). Address the style issue (e.g. using plan_iterate then plan_apply_changes) before implementation.

## Review findings: issues and proposed changes

### Issues that need rectifying

Step 3 describes inline dialog creation; [CODING_STANDARDS](/.cursor/rules/CODING_STANDARDS.md) recommends using the existing dialog helper.

### Proposed changes

Revise step 3 to: "Call DialogHelper.confirm() instead of creating a new dialog; pass the message from the plan." API usage for Runner.handle_task_list() and request_writer_approval matches the codebase.
