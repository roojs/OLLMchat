---
name: plan_code_iterate
description: Use when you need to revise a plan that already has code proposals; receives the plan with existing code and often clarifications or feedback. Outputs a revised list of changes that replaces the previous proposals.
tools:
---

## Refinement

**Purpose of this skill:** Revise a plan that already has code proposals; the executor needs the plan with existing code, clarifications or feedback, and any prior plan_code output. Refinement fills in **References** so the executor can deliver what is needed.

You receive **what is needed** for this task and a **summary of the task list so far executed** (including output summaries from previous tasks). Fill in **References** so the executor can deliver what is needed — e.g. plan file, prior plan_code or plan_code_iterate output, and relevant code sections. **Avoid whole files** — add **code sections** or **references to parts of a task output** (e.g. file + section/method/snippet) rather than full file contents.

---

You receive a **plan with existing code** (from a previous plan_code or plan_code_iterate run) and often **clarifications** about existing problems (in What is needed or Precursor). Produce a **revised list of changes** that **replaces** the previous proposals. You do **not** apply changes; you only output the revised list.

**Existing code:** If a section or change does **not** need changing, output the existing code as-is (same ## {section}, ### Changes proposed, what/where, and fenced code). That keeps it in the plan.

**New or revised code:** Add or revise by outputting **### Changes proposed** with **what**, **where**, and a fenced code block. Your full output is the new canonical list: unchanged sections plus any new or revised changes. The previous proposals are superseded by this output.

Follow the **same structure** as plan_code: for each relevant section, **## {section name from plan}**, then **### Changes proposed** with **what** (brief description), **where** (file link, optional AST or location), and a fenced code block. State **add**, **replace**, or **delete** where relevant. **Always use link references** for files.

**Clarifications:** If you receive clarifications about existing problems (e.g. "fix the approval logic", "use the dialog API from Widget"), incorporate them into the revised proposals. If something is still unclear or you lack information, **report it in the summary** — be **very explicit** about what is missing. **Do not guess APIs** you do not know; report unknowns in the summary (e.g. "Unknown: dialog API — needs research"). Same pattern as plan_code: completion, outstanding items, and gaps called out clearly.

**Summary:** Use the fixed header **## Result summary**. If you have **completed** the revised tasks, say so. If you **could not complete** due to missing information or unclear clarifications, be **very explicit** — list what is missing or what needs verification. Be explicit about assumptions or gaps so the next step can be research, another iteration, or implement_code.

### Example output

## Result summary

Revised sections 1 and 2 per clarification: approval now uses the dialog from [ChatWidget](/path/to/ChatWidget.vala). See [1. Add writer approval gate](#1-add-writer-approval-gate), [2. Implement request_writer_approval](#2-implement-request_writer_approval). **Outstanding:** return value of `dialog.run_async()` not confirmed — left as yield; needs verification. Rest of existing code unchanged. If complete, next task: **implement_code** or **plan_apply_changes**.

## 1. Add writer approval gate

### Changes proposed

**What** — Add check before running writer tasks; request user approval via ChatWidget dialog.  
**Where** — [Runner.vala](/path/to/liboccoder/Skill/Runner.vala), before the loop in `handle_task_list`.

```vala
if (this.run_until_writer && this.has_writer_tasks()) {
    yield this.request_writer_approval();
}
```

## 2. Implement request_writer_approval

### Changes proposed

**What** — Add method; call ChatWidget dialog (per clarification).  
**Where** — [Runner.vala](/path/to/liboccoder/Skill/Runner.vala), after `handle_task_list`.

```vala
private async void request_writer_approval() throws GLib.Error {
    yield this.chat_widget.show_approval_dialog("Approve writer tasks?");
}
```

(Sections with no changes: output their existing ### Changes proposed and fenced code unchanged.)
