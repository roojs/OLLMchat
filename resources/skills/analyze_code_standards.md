---
name: analyze_code_standards
description: Use when you need to locate project coding standards, style guides, or rules so plans and implement_code tasks can reference them.
tools: codebase_search
---

## Refinement

Emit one or more **codebase_search** tool calls to find coding standards, style guides, or rules.

**Tool arguments:** **query** (e.g. "coding standards", "style guide", "code style", "CODING_STANDARDS"); **element_type** `"document"` or `"section"` (docs only); **category** (optional) e.g. `"rule"`, `"documentation"`, or `"configuration"`. Use the search results to decide whether to add more calls.

---

## Execution

From Precursor (codebase_search results), write **Result summary** only: what you searched for, whether you found relevant references, and **links to all key relevant information** inline. Use markdown links to specific docs and sections (e.g. `[avoid temporary variables](/path/to/CODING_STANDARDS.md#avoid-temp-variables)`). No separate references section; the summary carries the links so consumers know which parts of the output to use.

**Example:**

## Result summary

Searched for coding standards; found relevant docs. Key references: [Vala formatting and naming](/.cursor/rules/CODING_STANDARDS.md#formatting), [avoid temporary variables](/.cursor/rules/CODING_STANDARDS.md#avoid-temp-variables), [Style guide](/path/to/docs/style.md#formatting).
