---
name: analyze_docsbase
description: Use when you need to locate particular documentation in the project (plans, rules, docs, config) — how-to, conventions, or policies.
tools: codebase_search
---

## Refinement

**What is needed** is the description of what documentation to find (e.g. "skill authoring format", "task refinement conventions", "how RAPIR is applied"). Produce one or more **codebase_search** tool calls with **query** and the documentation-specific options below.

### Tool: codebase_search (documentation options)

- **query** (required): search text describing what documentation to find.
- **element_type** (required for docs): use `"document"` for whole doc files or `"section"` for doc sections. Do **not** search code; use **analyze_codebase** for that.
- **category** (optional): narrow by doc kind. Values: `"plan"`, `"documentation"`, `"rule"`, `"configuration"`, `"data"`, `"license"`, `"changelog"`, `"other"`. Use when the goal targets a specific type (e.g. `"rule"` for .cursor/rules, `"plan"` for docs/plans).
- **max_results** (optional): max hits (default 10). Increase for broad topics; decrease for a shortlist.

**Formulating queries** — use multiple words and match how docs are described. If you know specific doc names or section headings (e.g. "skill file format", "reference link types"), try searching for those as well.

**Encourage:** Multiple tool calls with different **query** phrasings or **category** (e.g. one for "skill format" in documentation, one for "task refinement" in rules) to cover plans, rules, and general docs.

---

## Execution

Summarize the result in a **short paragraph** that lists all relevant information found, with links (whole file or part of file) and why each is relevant. If you did not find anything, say so clearly. If a search did not produce useful results, say that (e.g. searching for X was not a good idea as it did not produce any results).

Use markdown links: whole file (path only) or part of file (path#heading — use GFM heading anchor for doc sections, e.g. `#skill-file-format`). Prefer section-level links when a section is the relevant unit; link to the whole file when the entire doc is relevant. Do not paste long doc text.

Output **Result summary** only: that short paragraph with inline links and why each link is relevant. No separate section.

### Example

**Input:** codebase_search result(s) in Precursor.

**Output:**

## Result summary

Searched documentation for skill authoring format. Found [Skills format](/path/to/docs/skills-format.md) — overall format doc; [Skill file format](/path/to/docs/skills-format.md#skill-file-format) — location, frontmatter, body; and [Reference link types](/path/to/docs/skills-format.md#reference-link-types-for-output) — how to link to files, AST, task output. Enough for a follow-up summary.
