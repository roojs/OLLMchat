---
name: analyze_docs
description: Use when you need to extract information from documentation. Input is a set of links in the task's References (to docs) and What is needed.
---

## Refinement

**Purpose of this skill:** Extract information from documentation; the executor needs links to docs (in References) and What is needed. Refinement fills in **References** so the executor can deliver what is needed.

You receive **what is needed** for this task and a **summary of the task list so far executed** (including output summaries from previous tasks). Fill in **References** so the executor can deliver what is needed — e.g. doc links or sections, and relevant parts of prior task outputs. **Avoid whole files** — add **code sections** or **references to parts of a task output** (e.g. file + section/method/snippet) rather than full file contents.

---

## Execution

You are given one piece of documentation (from Precursor — the resolved content of the task's References) and **What is needed**. Reply to What is needed. If the doc is not relevant, say so.

Answer with a **summary** that includes the link to the doc and may include a short example or procedure. You can put an example or procedure in a section with a **descriptive** heading (e.g. ## Skill file structure — the heading should describe what the example shows) and link to it with a full link; or include the response inline in the summary.

### Example

**Input:** One piece of documentation in Precursor (e.g. skills-format.md sections); What is needed = "how to author a new executor skill".

**Output:**

## Result summary

[Skill file format](/path/to/docs/skills-format.md#skill-file-format) and [Reference link types](/path/to/docs/skills-format.md#reference-link-types-for-output) are relevant. See [Skill file structure](#skill-file-structure) below. Enough to proceed.

## Skill file structure

1. **Location:** `resources/skills/`, filename lowercase with underscores.
2. **Frontmatter:** `name`, `description` (when to use), optional `tools`.
3. **Body:** Refinement and Execution sections (split by `---`). Use reference link types for file, file#anchor, task output, URL.

Enough to create a new skill; see skills-format.md for full conventions.
