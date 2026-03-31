---
name: plan_code
description: Use when turning a plan into concrete code proposals (which files, where, fenced code per change). Persists proposals into the plan document with write_file using chunked edits; does not modify application source files — implement_code applies those changes to the tree.
tools: write_file
---

**During refinement**

**Purpose of this skill:** Turn a plan into a list of concrete code changes; the executor needs the plan content and any other references (code, standards). Refinement fills in **References** so the executor can deliver what is needed.

You receive **what is needed** for this task and a **summary of the task list so far executed** (including output summaries from previous tasks). Fill in **References** so the executor can deliver what is needed — e.g. plan file, code files or sections the plan references, and relevant outputs from prior tasks. **Avoid whole files** — add **code sections** or **references to parts of a task output** (e.g. file + section/method/snippet) rather than full file contents.

When the **plan file should be updated on disk** with these proposals, include the **target plan path** (absolute or repo-relative) in **What is needed** or **References** so **Change details** can set **file_path**. If no path is given and choosing one would be guesswork, the execution step should give **Result summary** only: recommendations and the **`no changes needed`** line — **no** **Change details** that write a file.

---

Take the **plan content** and **any other references** (in **Precursor**) and produce **code change proposals**: for each change, **what** (brief), **where** (file link, optional AST or location), **add** / **replace** / **delete**, and a fenced code block with the **actual proposed code**. **Do not** edit application source files — only describe proposals for **implement_code** to apply later.

**Logical structure** (what the plan document should contain after edits): mirror the plan sections. For each relevant section, **## {section name from plan}**, then **### Changes proposed** with **What** / **Where**, then a fenced block. **Always use link references** for files (e.g. `[Runner.vala](/path/to/Runner.vala#…)`).

**When writing proposals into the plan file:** **`## Result summary`** first (prose with links; call out **Outstanding** gaps, unknown APIs, assumptions). Then one or more **`## Change details`** sections — **chunked** updates, same idea as **plan_iterate**:

- Default **`output_mode` `replace`**: **`file_path`** (the plan markdown file), then two fenced blocks — excerpt from the **current** plan file (must match uniquely) and **replacement** text that embeds the updated **##** / **### Changes proposed** / fenced code for that chunk.
- Use **several** **`## Change details`** sections (or **`## Change details (2)`**, …) when edits belong in **different** parts of the file — one distinct **replace** per chunk rather than one giant replace when avoidable.
- Use **`output_mode` `fenced`** with **`ast_path`** / **`location`** or line ranges only when that matches how the plan file is addressed for a **narrow** replacement.
- Use **`complete_file`** + **`output_mode` `next_section`** only when the user explicitly wants a **full** regenerated plan body, or the file is new and a single full document is intended.

When **file_path** cannot be chosen safely or **Precursor** lacks the real plan text needed for a safe **replace**: **Result summary** only — blocker, recommendations, **`no changes needed`** — do **not** emit **Change details** you cannot justify.

**Summary — outstanding items:** If you **could not complete** due to missing information, be **very explicit** in **Result summary** — list what is missing. **Do not guess APIs** you do not know; report unknowns and assumptions so the next step can be research or **implement_code** with the right context. Say the **next task** when clear: **implement_code**, **plan_code_iterate**, **plan_iterate**, or research.

### Example output (chunked `replace` into plan file)

Use **`## Result summary`** first, then one or more **`## Change details`** blocks. When the replacement text must include **nested** fenced code (e.g. **```vala** inside a plan section), use an **outer** fence with **more** backticks than any inner fence (e.g. **````markdown** … **```vala** … **```** … **````**).

If you are **not** persisting to the plan file this run: **Result summary** plus the same **##** / **### Changes proposed** / fenced code as the message body — **no** **Change details**.

**Example (one chunk — `replace`):**

## Result summary

Added concrete proposals for section 1 in [feature-plan.md](/path/to/docs/plans/feature-plan.md). **Outstanding:** API for `Request.get_header()` unknown. Next: research or **implement_code** once confirmed.

## Change details

- **file_path** docs/plans/feature-plan.md
- **output_mode** replace

````markdown
## 1. Add writer approval gate

### Changes proposed

**What** — *(stub from prior draft.)*  
**Where** — …
````

````markdown
## 1. Add writer approval gate

### Changes proposed

**What** — Add a check before writer tasks; request user approval once per run.  
**Where** — [Runner.vala](/path/to/liboccoder/Skill/Runner.vala), before the loop in `handle_task_list`.

```vala
if (this.run_until_writer && this.has_writer_tasks()) {
    yield request_writer_approval();
}
```
````

Add **`## Change details (2)`**, … for additional chunks elsewhere in the plan file.
