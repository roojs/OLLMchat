---
name: plan_code_iterate
description: Use when revising a plan that already has code proposals; incorporates clarifications or feedback. Persists revised proposals into the plan document with write_file using chunked edits — same pattern as plan_code.
tools: write_file
---

**During refinement**

**Purpose of this skill:** Revise a plan that already has code proposals; the executor needs the plan with existing code, clarifications or feedback, and any prior **plan_code** or **plan_code_iterate** output. Refinement fills in **References** so the executor can deliver what is needed.

You receive **what is needed** for this task and a **summary of the task list so far executed** (including output summaries from previous tasks). Fill in **References** so the executor can deliver what is needed — e.g. plan file, prior **plan_code** or **plan_code_iterate** output, and relevant code sections. **Avoid whole files** — add **code sections** or **references to parts of a task output** (e.g. file + section/method/snippet) rather than full file contents.

When the **plan file should be updated on disk** with revised proposals, include the **target plan path** (absolute or repo-relative) in **What is needed** or **References** so **Change details** can set **file_path**. If no path is given and choosing one would be guesswork, the execution step should give **Result summary** only: recommendations and the **`no changes needed`** line — **no** **Change details** that write a file.

---

You receive a **plan with existing code proposals** (from **plan_code** or a prior **plan_code_iterate**) and **What is needed** / **Precursor** (clarifications, feedback). Produce a **revised** list of proposals that **supersedes** the previous ones for any section you touch. **Do not** edit application source files — only update the plan document’s proposal text for **implement_code** to use later.

**Unchanged sections:** If a section’s proposals stay valid, you can leave that region of the plan file untouched (no **Change details** chunk for it), or re-output unchanged **### Changes proposed** content in **Result summary** only if you need to confirm nothing changed.

**Revised sections:** Use the same **##** / **### Changes proposed** / **What** / **Where** / fenced code shape as **plan_code**.

**When writing revisions into the plan file:** **`## Result summary`** first, then **chunked** **`## Change details`** sections — same rules as **plan_code** / **plan_iterate**:

- Default **`output_mode` `replace`**: **`file_path`**, two fences (existing excerpt from the plan file + replacement text). Use **several** **Change details** sections when edits target **different** regions of the file.
- If replacement text includes **fenced code** inside markdown, use an **outer** fence with **more** backticks than inner fences (e.g. **````markdown** wrapping **```vala**).
- Use **`complete_file`** + **`next_section`** only when the user explicitly wants a **full** regenerated plan-with-code body.

When **file_path** cannot be chosen safely or **Precursor** lacks exact plan text for a safe **replace**: **Result summary** only — blocker, recommendations, **`no changes needed`** — do **not** emit bad **Change details**.

**Clarifications:** Incorporate feedback into the revised proposals; if something is still unclear, say so in **Result summary** (**Outstanding**). **Do not guess APIs** — report unknowns explicitly.

**Next task** when clear: **implement_code**, another **plan_code_iterate**, **plan_iterate** (non-code plan edits), or research.

### Example output (chunked `replace`)

## Result summary

Revised section 2 in [feature-plan.md](/path/to/docs/plans/feature-plan.md): approval now uses [ChatWidget](/path/to/ChatWidget.vala) per clarification. **Outstanding:** `dialog.run_async()` return not verified. Next: **implement_code** or another iteration.

## Change details

- **file_path** docs/plans/feature-plan.md
- **output_mode** replace

````markdown
## 2. Implement request_writer_approval

### Changes proposed

**What** — Add method; placeholder UI.  
**Where** — [Runner.vala](/path/to/Runner.vala), after `handle_task_list`.

```vala
private async void request_writer_approval() throws GLib.Error {
    // TODO
}
```
````

````markdown
## 2. Implement request_writer_approval

### Changes proposed

**What** — Add method; call ChatWidget approval dialog (per clarification).  
**Where** — [Runner.vala](/path/to/Runner.vala), after `handle_task_list`.

```vala
private async void request_writer_approval() throws GLib.Error {
    yield this.chat_widget.show_approval_dialog("Approve writer tasks?");
}
```
````
