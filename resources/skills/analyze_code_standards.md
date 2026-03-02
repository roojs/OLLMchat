---
name: analyze_code_standards
description: Use when you need to locate project coding standards, style guides, or rules so plans and implement_code tasks can reference them. Outputs references to the relevant docs/sections.
tools: codebase_search
---

## Analyze code standards skill

Searches the project for **coding standards**, style guides, and related rules (e.g. CODING_STANDARDS, .cursor/rules, language-specific conventions). Outputs a list of references (links) so that plan_review and implement_code can use them.

### Input (this skill)

From the standard input, **What is needed** is the description of what standards to find (e.g. "coding standards for Vala", "project style guide", "rules for this repo"). The refinement step produces one or more **codebase_search** tool calls with **query** and documentation options (element_type "document" or "section", category e.g. "rule" or "documentation").

### Tool: codebase_search (for standards)

- **query** (required): e.g. "coding standards", "style guide", "code style", "CODING_STANDARDS".
- **element_type**: `"document"` or `"section"` (docs only).
- **category** (optional): `"rule"` (e.g. .cursor/rules), `"documentation"`, or `"configuration"` as appropriate.

### Output (this skill)

- **Result summary** (required): **summary of what this task did** (searched for coding standards) and **whether it found relevant docs** (with references below / nothing found).
- **Code standards references**: list of markdown links to the relevant docs or sections (file path and, if useful, GFM heading anchor). Include a one-line note per link (what it covers). This section is for use in References by plan_review and implement_code.

### Instructions

#### Refinement

- Emit one or more **codebase_search** calls with **element_type** `"document"` or `"section"`, **query** about coding standards/style, and **category** if targeting rules (e.g. "rule") or general docs.

#### Execution (what to do with the results)

- Use the tool output(s) from Precursor. List each relevant doc/section with a link (path or path#section-name) and a short note (e.g. "Vala style and formatting", "Project rules for agents").
- Write **Result summary**: what this task did (searched for standards) and whether it found relevant references.
- In **Code standards references**, use markdown links only; do not paste long doc text. Downstream tasks (plan_review, implement_code) can add these links to their References to get the content when they run.

### Example

**Input:** codebase_search with `query = "coding standards style guide"`, `element_type = "section"`, `category = "rule"`.

**Output:**

## Result summary

Searched for coding standards; found .cursor/rules/CODING_STANDARDS.md and a style section in docs — references below for plan_review and implement_code.

## Code standards references

- [CODING_STANDARDS](/.cursor/rules/CODING_STANDARDS.md) — Vala formatting, naming, and project conventions.
- [Style guide](/path/to/docs/style.md#formatting) — Formatting and indentation rules.
