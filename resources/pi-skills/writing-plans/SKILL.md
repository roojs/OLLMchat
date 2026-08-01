---
name: writing-plans
description: This skill should be used when the user has a spec or requirements for a multi-step task before touching code.
license: MIT
---

# Writing Plans

## Purpose

Create executable, low-ambiguity implementation plans that another engineer can run task-by-task with predictable outcomes.

## When to Use

Use this skill when:
- Requirements/specs exist but implementation has not started
- Work is multi-step and requires coordination across files and tests
- A handoff-ready plan is needed for another session or engineer

## Progress Tracking

Display progress at each planning phase:

```
[████░░░░░░░░░░░░░░░░] 25% — Phase 1/4: Gathering Context & Constraints
[████████░░░░░░░░░░░░] 50% — Phase 2/4: Decomposing Into Tasks
[████████████░░░░░░░░] 75% — Phase 3/4: Specifying Files & Commands
[████████████████████] 100% — Phase 4/4: Writing & Saving Plan
```

## Workflow

1. Gather context and constraints
2. Break work into bite-sized, test-first tasks
3. Specify exact files, code snippets, and commands
4. Add validation criteria and expected outputs
5. Save plan (including a **To-do** section) and hand off to `executing-plans`

## Overview

Write comprehensive implementation plans assuming the engineer has zero context for our codebase and questionable taste. Document everything they need to know: which files to touch for each task, code, testing, docs they might need to check, how to test it. Give them the whole plan as bite-sized tasks. DRY. YAGNI. TDD. Frequent commits.

Assume they are a skilled developer, but know almost nothing about our toolset or problem domain. Assume they don't know good test design very well.

**Announce at start:** "I'm using the writing-plans skill to create the implementation plan."

**Tools:** `read` / `write` / `edit` / `bash` (and `codebase_search` when researching the tree). Ask clarifying questions in chat.

**Save plans to:** `docs/plans/YYYY-MM-DD-<feature-name>.md` (or the path the user names).

## Bite-Sized Task Granularity

**Each step is one action (2-5 minutes):**
- "Write the failing test" - step
- "Run it to make sure it fails" - step
- "Implement the minimal code to make the test pass" - step
- "Run the tests and make sure they pass" - step
- "Commit" - step

## Plan Document Header

**Every plan MUST start with this header:**

```markdown
# [Feature Name] Implementation Plan

> **For the executor:** Use the `executing-plans` skill to implement this plan task-by-task.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

---
```

## Required: To-do section

**Every plan MUST include a `## To-do` section** listing the tasks the executor will walk. Use checkboxes (or `⏳` / `✔️` / `✅` if matching project plan style). `executing-plans` updates this section as work proceeds.

Example:

```markdown
## To-do

- [ ] Task 1: …
- [ ] Task 2: …
- [ ] Task 3: …
```

Keep To-do items aligned with the detailed `### Task N` sections below.

## Task Structure

````markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/file.vala`
- Modify: `exact/path/to/existing.vala`
- Test: `tests/exact/path/to/test`

**Step 1: Write the failing test**

(concrete code or commands)

**Step 2: Run test to verify it fails**

Run: `…`
Expected: FAIL with …

**Step 3: Write minimal implementation**

(concrete code)

**Step 4: Run test to verify it passes**

Run: `…`
Expected: PASS

**Step 5: Commit** (only if the user wants commits)

```bash
git add …
git commit -m "…"
```
````

## Remember
- Exact file paths always
- Complete code in plan (not "add validation")
- Exact commands with expected output
- Always include `## To-do`
- DRY, YAGNI, TDD, frequent commits when the user wants git history

## Execution Handoff

After saving the plan, offer:

**"Plan complete and saved to `docs/plans/<filename>.md`. Continue in this session with `executing-plans`, or open a new session pointed at that file?"**

## Critical Rules

- Always include exact paths and exact commands.
- Always define expected outcomes for test/verification steps.
- Spell out concrete code intent in each step (not vague “implement validation”).
- Always include `## To-do`.

## Example Usage

1. "Use writing-plans to plan migration from REST to GraphQL."
2. "Use writing-plans to break down an auth refactor into TDD tasks."
3. "Use writing-plans to prepare a handoff plan for a new caching layer."
