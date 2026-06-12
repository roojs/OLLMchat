---
name: plan_create
description: Use when creating a new plan after research and analysis are done; captures requirements, scope, and steps for the work — not implementation code (use plan_code to add concrete code into the plan document next).
tools: write_file
---

**During refinement**

**Purpose of this skill:** Create a new plan from goals and prior research/analysis — **requirements, scope, and steps** first; concrete code in the plan is **plan_code**. The executor needs input, goals, and reference documents from prior research or code analysis. Refinement fills in **References** so the executor can deliver what is needed.

You receive **what is needed** for this task and a **summary of the task list so far executed** (including output summaries from previous tasks). Fill in **References** so the executor can deliver what is needed — e.g. goals, prior research or analyze_code outputs, and relevant doc or code sections. **Avoid whole files** — add **code sections** or **references to parts of a task output** (e.g. file + section/method/snippet) rather than full file contents.

Put all of those links in **Shared references**; omit **Examination references**. The executor should see one precursor with everything needed to draft the plan.

When the user wants the plan **written to disk**, include the **target plan path** (absolute or repo-relative) in **What is needed** or **References** so **Change details** can set **file_path**. If no path is given and choosing one would be guesswork, give **Result summary** only: explain what to add or refine next, recommendations, and the **`no changes needed`** line — **no** **Change details** that write a file.

---

Focus on **requirements and intent**, not implementation: **what** must change, **why**, **scope** (areas of the codebase, modules, behaviours), constraints, and risks. Describe changes at the level of **goals and acceptance** — **not** fenced code, algorithms, or API-level snippets (**plan_code** adds those into the plan). Break the work into numbered sections; if it is complex, use **phases**.

**When writing the plan to a file:** **`## Result summary`** first (prose with in-document `#` links to sections below), then **`## Change details`** with a bullet list including **`file_path`**, **`complete_file`** `true`, **`overwrite`** `false` (or `true` only when replacing an existing draft the user asked to overwrite), **`output_mode`** **`next_section`**. The **entire plan document** is the **next_section** body: everything after that list to the end of the answer (not fenced). Start that body with a top-level **`#` title** (plan name), then **`## Status`**, **`## Purpose`**, **`## Problem Summary`**, numbered **`## 1. …`**, **`## 2. …`**, etc., as below.

When **file_path** cannot be chosen safely or **What is needed** is too vague to write a file: **Result summary** only — specific blocker, actionable recommendations, and the **`no changes needed`** signal. Do **not** emit **Change details** for a file you cannot justify.

**Summary — outstanding items:** It is **very important** that **Result summary** mentions any items that are **outstanding** and need follow-up. If the plan’s **requirements and scope** are ready, the usual next step is **plan_code** (add concrete code proposals into the plan document). **implement_code** applies changes to the tree **after** the plan has code proposals (and often **plan_review**). If the plan still needs non-code edits, use **plan_iterate**; if gaps remain, list them and suggest more research or refinement.

**Always use link references** when referring to files or sections.

### Example plan section types (from existing plans)

Use these as a common set of section types; include what fits the goal.

- **Status** — e.g. ⏳ PENDING, DONE, or **PLAN** (not started).
- **Purpose** or **Goal** — One paragraph: what we are trying to achieve.
- **Problem Summary** — Summarize the problem; or **propose/describe** the problem and context.
- **Numbered sections** (## 1. …, ## 2. …) — For each issue or task:
  - **Issue** — What is wrong or what is needed.
  - **Goal** — What we want to achieve for this item.
  - **Scope** — Where to change (files, modules, prompts).
  - **Considerations** — Caveats, alternatives, or follow-ups.
- **Files / sections that need changing** — List or describe which files or areas are affected and **what** behaviour or requirement changes — **not** implementation code (that belongs in **plan_code**).
- **Outstanding issues / Research needed** — In the summary or a section: what still needs researching if the plan is not ready.
- **Phases** — When the work is complex, split into phases (e.g. Phase 1: X; Phase 2: Y).
- **Related Plans** — Links to other plans this depends on or relates to.
- **Deliverables** — What will be produced or implemented.
- **Coding standards** — Reference **`docs/coding-standards.md`** for Vala rules; use **`docs/guide-to-writing-plans.md`** — Checklist for plans for plan structure and verification.

### Example output (write plan file — `next_section`)

Use **`## Result summary`** first, then **`## Change details`** with **`file_path`**, **`complete_file`**, **`overwrite`**, **`output_mode`** **`next_section`**, then the plan as the trailing section (starts with **`#` …**).

**Example (with outstanding):**

## Result summary

Plan drafted in [Add writer approval gate](#add-writer-approval-gate); see [Status](#status), [Purpose](#purpose), and numbered sections. [Runner.vala](/path/to/liboccoder/Skill/Runner.vala) and the task list flow need updates. **Outstanding:** confirm UI approval pattern with existing dialog. Once that is researched, next step: **plan_code** to add concrete proposals; then **implement_code** when ready.

## Change details

- **file_path** docs/plans/add_writer_approval_gate.md
- **complete_file** true
- **overwrite** false
- **output_mode** next_section

# Add writer approval gate

## Status

⏳ PENDING

## Purpose

…

## Problem Summary

…

## 1. …

…

(Numbered sections ## 2. …, then Phases / Related Plans / Deliverables as needed.)

**Example (complete plan, same shape):**

## Result summary

Requirements and scope are ready. See [Status](#status), [Purpose](#purpose), and numbered sections below. Next step: **plan_code** to add code proposals to the plan; then **implement_code** (and **plan_review** as needed).

## Change details

- **file_path** docs/plans/feature-x.md
- **complete_file** true
- **overwrite** false
- **output_mode** next_section

# Feature X — implementation plan

## Status

PLAN

## Purpose

…

## 1. …

…
