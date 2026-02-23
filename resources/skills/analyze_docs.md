---
name: analyze_docs
description: Use after analyze_docsbase to turn its findings into a synthesized summary. Receives the output from an analyze_docsbase task and produces a concise how-to or summary of the relevant documentation.
---

## Analyze docs skill

Receives the output from an **analyze_docsbase** task (Result summary + Analyze docsbase results) and produces a Detail document that synthesizes the documentation: key points, how to apply it, and any procedures or examples from the docs.

### Input (this skill)

From the standard input, **Precursor** contains the output from the **analyze_docsbase** task (Result summary and Analyze docsbase results with doc/section links). **What is needed** is the original goal (e.g. "how to author a skill", "what refinement must produce"). This skill has no tool calls; it uses the precursor and any resolved reference content to write the summary.

### Output (this skill)

Result summary and Detail. In Result summary: **summary of what this task did** to address the goal and **whether that answered it** (e.g. "Synthesized the docs into a how-to for skill authoring; Detail below gives structure and link types — enough to proceed." or "The docs search had nothing useful."). Do not use a literal "Goal:" line. In Detail: synthesize the **relevant documentation** — key conventions, steps, or policies; how to apply them; and any **example procedures or snippets** from the docs. Keep markdown links (file path or path#section-name) so downstream tasks can use the referenced content. End with a clear conclusion (enough to proceed or what is still unclear).

### Instructions

#### Refinement

- No tool calls. Ensure the task's **References** include the prior **analyze_docsbase** task output (refiner adds a link to that task's results so Precursor contains Result summary + Analyze docsbase results and any resolved reference content).

#### Execution (what to do with the results)

- Read the analyze_docsbase output in Precursor (Result summary and **Analyze docsbase results**). Use the referenced documentation (links and any resolved reference content in Precursor) to answer the goal in "What is needed".
- **Result summary**: one or two sentences — **what this task did** (synthesized the docs for the goal) and **whether that answered it** (enough to proceed / analysis insufficient). Summarise the work and outcome; do not start with "Goal:".
- **Detail**: write a short **synthesis** of the documentation. Include:
  - Key points, conventions, or requirements from the docs.
  - **How to apply** them (steps or checklist where relevant).
  - Any **example procedures, formats, or snippets** from the referenced docs (so downstream tasks can follow them).
  - Keep links to the docs so later tasks can use the referenced content.
- Do not repeat long chunks from the precursor; synthesize and add clear guidance. End with enough to proceed or what is still missing.

### Example

**Input:** Precursor = analyze_docsbase output for "skill authoring format"; What is needed = "how to author a new executor skill".

**Output:**

## Result summary

Synthesized the docs into a how-to for skill authoring; Detail below gives structure, frontmatter, and link types — enough to proceed.

## Detail

To author a new executor skill (see [Skill file format](/path/to/docs/skills-format.md#skill-file-format)):

1. **Location:** `resources/skills/`, filename lowercase with underscores (e.g. `my_skill.md`).
2. **Frontmatter:** `name` (matches catalog), `description` (when to use), optional `tools` (comma-separated).
3. **Body:** Input (this skill), Output (this skill), Instructions, Example. Do not duplicate the execution template; only skill-specific content.
4. **Links:** Use [Reference link types](/path/to/docs/skills-format.md#reference-link-types-for-output) — file, file#anchor (GFM for docs, AST path for code), task output, URL.

Enough to create a new skill; see skills-format.md for full conventions and two-step flows.
