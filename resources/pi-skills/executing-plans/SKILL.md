---
name: executing-plans
description: This skill should be used when the user has a written implementation plan to execute in a separate session with review checkpoints.
license: MIT
---

# Executing Plans

## Purpose

Execute approved implementation plans in controlled batches with checkpoints, verification, and review gates.

## When to Use

Use this skill when:
- A written implementation plan already exists
- Work must be executed with periodic review checkpoints
- Risk of regressions requires strict plan adherence and verification

## Progress Tracking

**Source of truth:** the plan file’s `## To-do` section (checkboxes or `⏳` / `✔️` / `✅`).

Also display a short gauge before each batch:

```
[████░░░░░░░░░░░░░░░░] 20% — Phase 1: Loading & Reviewing Plan
[████████░░░░░░░░░░░░] 40% — Phase 2: Executing Batch N
[████████████░░░░░░░░] 60% — Phase 3: Reporting & Verification
[████████████████░░░░] 80% — Phase 4: Awaiting Feedback
[████████████████████] 100% — Phase 5: Final Verification Complete
```

For plans with many tasks: `X/Y tasks done (N%)`.

## Workflow

1. Load and review plan critically
2. Execute first batch of tasks
3. After each finished task, **edit the plan** to update To-do
4. Report results and verification output
5. Pause for feedback and continue in batches

## Overview

Load plan, review critically, execute tasks in batches, report for review between batches.

**Core principle:** Batch execution with checkpoints for architect review.

**Announce at start:** "I'm using the executing-plans skill to implement this plan."

**Tools:** Agent Pi `read` / `write` / `edit` / `bash`. Prefer `edit` for updating the plan’s To-do. Ask the user in chat when blocked.

## The Process

### Step 1: Load and Review Plan
1. `read` the plan file
2. Review critically - identify any questions or concerns about the plan
3. If concerns: Raise them with your human partner before starting
4. If no concerns: ensure a `## To-do` exists (or treat Suggested order / `⏳` bullets as the To-do), then proceed

### Step 2: Execute Batch
**Default: First 3 tasks**

For each task:
1. Mark the To-do item in progress (edit the plan: e.g. `[~]` or `⏳` on that line)
2. Follow each step exactly (plan has bite-sized steps)
3. Run verifications as specified
4. **After the task is finished:** `edit` the plan and mark that To-do item done (`[x]` or `✔️`) before starting the next task

### Step 3: Report
When batch complete:
- Show what was implemented
- Show verification output
- Say: "Ready for feedback."

### Step 4: Continue
Based on feedback:
- Apply changes if needed
- Execute next batch
- Repeat until complete

### Step 5: Complete
After all tasks complete and verified:
- Confirm To-do is fully checked off in the plan file
- Summarize what landed and any follow-ups
- Offer optional commit / PR steps if the user wants them

## When to Stop and Ask for Help

**STOP executing immediately when:**
- Hit a blocker mid-batch (missing dependency, test fails, instruction unclear)
- Plan has critical gaps preventing starting
- You don't understand an instruction
- Verification fails repeatedly

**Ask for clarification rather than guessing.**

## When to Revisit Earlier Steps

**Return to Review (Step 1) when:**
- Partner updates the plan based on your feedback
- Fundamental approach needs rethinking

**Don't force through blockers** - stop and ask.

## Remember
- Review plan critically first
- Follow plan steps exactly
- Don't skip verifications
- Progress lives in the plan’s To-do — update it with `edit` after each finished task
- Between batches: just report and wait
- Stop when blocked, don't guess
- Never start implementation on main/master branch without explicit user consent

## Integration

- **writing-plans** — creates plans this skill executes (with a `## To-do` section)

## Critical Rules

- Stop immediately on blockers and ask for clarification.
- Run every verification command defined in the plan.
- After each batch, report and wait for feedback before continuing.
- Keep progress in the plan file To-do (`edit` after each finished task).

## Error Handling

| Error | Likely Cause | Action |
|-------|-------------|--------|
| Plan file not found | Path provided doesn't exist or file was moved | Ask user to confirm file path; list available plan files in `docs/plans/` |
| Ambiguous task description | Step in plan is unclear or underspecified | Stop and ask user for clarification before proceeding |
| Task depends on failed prerequisite | Earlier task failed or was skipped | Report the dependency failure; do not continue until resolved |
| Verification command fails | Tests or checks defined in plan are failing | Stop immediately, report full error output, wait for user instruction |
| Blocker encountered mid-execution | Unexpected state, conflicting files, or missing context | Pause, report the exact blocker, and ask user how to proceed |
| Batch completed with partial failures | Some tasks in batch failed | Report which succeeded and which failed; ask user whether to retry or skip |
| No To-do section | Plan authored without checklist | Add a To-do from task headings (ask first if unclear), then proceed |

## Example Usage

1. "Use executing-plans to implement `docs/plans/2026-02-20-api-hardening.md`."
2. "Use executing-plans to run the next 3 tasks and stop for review."
3. "Use executing-plans to finish remaining tasks and report final checks."
