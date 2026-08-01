---
name: research-codebase
description: This skill should be used when the user needs to explore or understand a local indexed project — find where behaviour lives, how modules connect, or answer questions about the codebase. Prefer semantic codebase_search first, then read and bash for precise follow-up.
license: MIT
---

# Research Codebase

## Purpose

Explore a **local** project (the active / opened indexed tree) with evidence-backed answers. For web research, use `deep-research` or `webpage-reader`.

## When to Use

- “Where is X handled?”
- “How does Y work in this repo?”
- Understanding call flow, ownership, or conventions before planning or changing code
- Gathering context for `writing-plans` or `debug-review`

## Tools

- **`codebase_search`** — semantic search over the indexed project (default first step)
- **`read`** — open specific files / regions
- **`bash`** — targeted grep, find, or other read-only inspection when semantic search is not enough
- Ask the user in chat when the target project or path is unclear

## Workflow

1. **Confirm target** — default is the active project. Another codebase still means a **local** tree the host has open/indexed.
2. **Semantic first** — run `codebase_search` with a clear natural-language question. Prefer a few focused queries over one vague dump.
3. **Drill down** — `read` the best hits; use `bash` grep/find for exact symbols or paths when needed.
4. **Summarize** — answer with file paths and short quotes or line-oriented pointers; note open questions / next skills (`writing-plans`, `debug-review`).

## Progress

```
[████░░░░░░░░░░░░░░░░] 25% — Scope & query
[████████░░░░░░░░░░░░] 50% — Semantic search
[████████████░░░░░░░░] 75% — Read / grep follow-up
[████████████████████] 100% — Summary for user
```

## Critical Rules

- Start with `codebase_search` unless the user already gave an exact file path.
- Prefer evidence (paths + excerpts) over speculation.
