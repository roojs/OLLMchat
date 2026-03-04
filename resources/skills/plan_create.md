---
name: plan_create
description: Use when creating a new plan after research and analysis are done; plan needs objectives, steps, and references from prior research/code analysis.
tools:
---

## Refinement

**Purpose of this skill:** Create a new plan from goals and prior research/analysis; the executor needs input, goals, and reference documents from prior research or code analysis. Refinement fills in **References** so the executor can deliver what is needed.

You receive **what is needed** for this task and a **summary of the task list so far executed** (including output summaries from previous tasks). Fill in **References** so the executor can deliver what is needed — e.g. goals, prior research or analyze_code outputs, and relevant doc or code sections. **Avoid whole files** — add **code sections** or **references to parts of a task output** (e.g. file + section/method/snippet) rather than full file contents.

---

## Execution

Take the **input, goals, and reference documents** and write a plan to solve the issues needed. Output the plan as your response (Result summary + plan body). Do **not** code initially: break down the task into **sections and files that need changing** and **describe the changes**. If the work involves complexity, use **phases**.

**Summary — outstanding items:** It is **very important** that the summary contains any items that are **outstanding** and need to be looked at. If we have everything we need, say that the **initial plan is complete** and the next step can be the plan code writing skill (implement_code). If there are gaps, list them clearly so more research or refinement can be done.

**This skill does not write a file.** In the summary, say what the **next task** should be: if the user asked to write the plan to a specific location, say the next task should be **plan_apply_changes**. Otherwise suggest more research or the code writing skill (implement_code) as appropriate.

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
- **Files / sections that need changing** — List or describe which files and what changes (do not write code here; describe the changes).
- **Outstanding issues / Research needed** — In the summary or a section: what still needs researching if the plan is not ready.
- **Phases** — When the work is complex, split into phases (e.g. Phase 1: X; Phase 2: Y).
- **Related Plans** — Links to other plans this depends on or relates to.
- **Deliverables** — What will be produced or implemented.
- **Coding standards** — Reference project coding standards (e.g. .cursor/rules/CODING_STANDARDS.md) when relevant.

### Example output

Use the fixed header **## Result summary**; then the plan body with standard plan section headings (## Status, ## Purpose, ## Problem Summary, numbered ## 1. …, ## 2. …, etc.).

**Example (with outstanding):**

## Result summary

Plan created for [add writer approval gate](docs/plans/add_writer_approval_gate.md). See [Status](#status), [Purpose](#purpose), [Problem Summary](#problem-summary), and numbered sections below. [Runner.vala](/path/to/liboccoder/Skill/Runner.vala) and the task list flow need updates. **Outstanding:** confirm UI approval pattern with existing dialog. Once that is researched, initial plan is complete; next step: **implement_code**. If the user wants this plan written to a file, next task: **plan_apply_changes**.

## Status

⏳ PENDING

## Purpose

…

## Problem Summary

…

(Numbered sections ## 1. …, ## 2. …, then Phases / Related Plans / Deliverables as needed.)

**Example (complete):**

## Result summary

Initial plan is complete; we have everything we need. See [Status](#status), [Purpose](#purpose), [Problem Summary](#problem-summary), and numbered sections below. Next step: **implement_code**. If the user wants this plan persisted to a specific path, next task: **plan_apply_changes**.
