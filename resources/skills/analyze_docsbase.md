---
name: analyze_docsbase
description: Use when you need to search project documentation (plans, rules, docs, config) for how-to, conventions, or policies. Always follow this task with analyze_docs, which receives this task's output and produces a synthesized summary.
tools: codebase_search
---

## Analyze docsbase skill

Searches **documentation** in the project (tool: **codebase_search**) using element_type "document" or "section". Use when the goal is to find how things are documented, project conventions, plans, or rules — not source code.

### Input (this skill)

From the standard input, **What is needed** is the description of what documentation to find (e.g. "skill authoring format", "task refinement conventions", "how RAPIR is applied"). The refinement step produces one or more **codebase_search** tool calls with **query** and documentation-specific options below.

### Tool: codebase_search (documentation options)

- **query** (required): search text describing what documentation to find.
- **element_type** (required for docs): use `"document"` for whole doc files or `"section"` for doc sections. Do **not** search code; use **analyze_codebase** for that.
- **category** (optional): narrow by doc kind. Values: `"plan"`, `"documentation"`, `"rule"`, `"configuration"`, `"data"`, `"license"`, `"changelog"`, `"other"`. Use when the goal targets a specific type (e.g. `"rule"` for .cursor/rules, `"plan"` for docs/plans).
- **max_results** (optional): max hits (default 10). Increase for broad topics; decrease for a shortlist.

**Encourage:** Multiple tool calls with different **query** phrasings or **category** (e.g. one for "skill format" in documentation, one for "task refinement" in rules) to cover plans, rules, and general docs.

### Output (this skill)

- **Result summary** (required): **summary of what this task did** to address the goal and **whether that answered it** (e.g. "Searched docs for skill authoring format; found skills-format and link types — enough for a follow-up summary." or "Nothing relevant found."). Do not describe system mechanics or use a literal "Goal:" line.
- **Analyze docsbase results**: list of documentation locations with markdown links. Use **file path** and, when pointing to a section, **GFM heading anchor** (e.g. `#skill-file-format`). Include a short summary of why each reference is useful. Optionally list **Top places to study**: the few doc files or sections most important for the goal. This section is the input for a follow-up **analyze_docs** task.

### Instructions

#### Refinement

- Emit one or more **codebase_search** tool calls with **element_type** `"document"` or `"section"`. Pass **query** from "What is needed". Include **category** when the goal targets a specific doc type (e.g. rules, plans). Use multiple calls with different query phrasings or category to get broader coverage. Optional: **max_results**.

#### Execution (what to do with the results)

- Use the tool output(s) from Precursor. Prefer **section-level** links (file#heading-anchor) when a section is the relevant unit; link to whole files when the entire doc is relevant.
- For each result: record doc/section with a link and why it is relevant. Prioritize by relevance; limit to the top 5–10 most relevant if there are many.
- Optionally start **Analyze docsbase results** with **Top places to study**: 2–4 doc locations that should be read first. Then list the full set of findings.
- Write **Result summary**: one or two sentences — **what this task did** (e.g. what was searched, what was found) and **whether that answered the goal** (enough for follow-up / nothing relevant). Summarise the work and outcome; do not start with "Goal:".
- In **Analyze docsbase results**, use markdown links (path or path#section-name for headings). Do not paste long doc text; links let the next task use the referenced content.

### Example

**Input:** e.g. codebase_search with `query = "skill authoring format and structure"`, `element_type = "section"`, optionally `category = "documentation"`.

**Output:**

## Result summary

Searched documentation for skill authoring format; found skills-format and reference link types in docs/skills-format.md — enough for a follow-up summary.

## Analyze docsbase results

**Top places to study:** [Skills format](/path/to/docs/skills-format.md#skills-format), [Skill file format](/path/to/docs/skills-format.md#skill-file-format) — these define the skill structure and output.

- [Skills format](/path/to/docs/skills-format.md) — overall format doc; use for conventions.
- [Skill file format](/path/to/docs/skills-format.md#skill-file-format) — location, frontmatter, body; required when authoring a skill.
- [Reference link types](/path/to/docs/skills-format.md#reference-link-types-for-output) — how to link to files, AST, task output.
