---
name: plan_code
description: Use when you need to turn a plan into a list of concrete code changes (which files, where, and fenced code for each change). Does not apply changes; outputs the proposed changes for review or for implement_code/plan_apply_changes to apply later.
tools:
---

## Refinement

**Purpose of this skill:** Turn a plan into a list of concrete code changes; the executor needs the plan content and any other references (code, standards). Refinement fills in **References** so the executor can deliver what is needed.

You receive **what is needed** for this task and a **summary of the task list so far executed** (including output summaries from previous tasks). Fill in **References** so the executor can deliver what is needed — e.g. plan file, code files or sections the plan references, and relevant outputs from prior tasks. **Avoid whole files** — add **code sections** or **references to parts of a task output** (e.g. file + section/method/snippet) rather than full file contents.

---

## Execution

Take the **plan content** and **any other references** (in Precursor) and output a **list of changes** — where they should occur (which files, before/after, AST location) and **fenced code blocks** for each replacement. You do **not** actually apply the changes; you only list them. Follow the plan you receive.

For each change, state whether it is **add**, **replace**, or **delete**. Give: **what** (brief description), **where** (file path, and if relevant AST reference or “before X” / “after Y”), then a fenced code block with the **actual code** (the new code for add/replace, or indicate deletion). **Always use link references** when referring to files (e.g. [filename](/path/to/file) or [symbol](/path/to/file#AST-path)).

**Output structure:** Mirror the plan sections. For each relevant section of the plan, output:

## {section name from plan}

### Changes proposed

**What** — brief description of the change.  
**Where** — file (link), and optionally AST symbol or location (e.g. before method `foo`, after line 42, replace in [Runner.vala](/path/to/Runner.vala#Namespace-Runner-env)).

```language
(code to add or replacement code; for delete, state "Delete the block above" or similar)
```

Repeat for each change in that section. Use as many ## {section} / ### Changes proposed blocks as the plan needs.

**Summary:** Use the fixed header **## Result summary**. If you think you have **completed** the tasks in the plan, say so clearly. If you **could not complete** due to missing information, be **very explicit** — list what is missing (e.g. API signatures, file paths, behaviour of X). **Do not guess APIs** you do not know; if you are unsure, report it in the summary (e.g. "Unknown: exact signature of Y; assumed Z — needs verification"). Be explicit about any assumptions or gaps so the next step can be research or implement_code with the right context.

### Example output

## Result summary

Completed proposed changes for sections 1 and 2 of the plan. See [1. Add writer approval gate](#1-add-writer-approval-gate), [2. Implement request_writer_approval](#2-implement-request_writer_approval). **Outstanding:** API for `Request.get_header()` is unknown — did not add that call; needs research. If that is confirmed, consider **implement_code** or **plan_apply_changes** to apply these changes.

## 1. Add writer approval gate

### Changes proposed

**What** — Add a check before running writer tasks; request user approval once per run.  
**Where** — [Runner.vala](/path/to/liboccoder/Skill/Runner.vala), before the loop in `handle_task_list`; add call to new method `request_writer_approval()`.

```vala
if (this.run_until_writer && this.has_writer_tasks()) {
    yield request_writer_approval();
}
```

## 2. Implement request_writer_approval

### Changes proposed

**What** — Add method to prompt user and wait for approval.  
**Where** — [Runner.vala](/path/to/liboccoder/Skill/Runner.vala), add new method after `handle_task_list`.

```vala
private async void request_writer_approval() throws GLib.Error {
    // TODO: wire to UI approval dialog; yield until user confirms or cancels
}
```
