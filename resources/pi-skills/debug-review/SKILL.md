---
name: debug-review
description: This skill should be used when the user needs to debug broken behaviour or review changed code for real defects. Follow the project bug-fix process (reproduce, bug log, root cause, propose with fences, approval before apply). Borrow a compact review checklist for diffs.
license: MIT
---

# Debug / Review

## Purpose

One playbook for two related jobs:

1. **Debug** — broken behaviour: find root cause and propose a real fix.
2. **Review** — look at a diff / change set for security, correctness, and design issues with evidence.

Spine for debug is this project’s bug-fix process (`docs/bug-fix-process.md` when present in the tree). Review ideas are a short checklist for changed code.

## When to Use

- Something is wrong and needs diagnosis
- User asks to review a patch, PR, or recent edits for bugs
- Before applying a speculative “quick fix”

Fix root causes; keep failures visible rather than masking them with extra guards.

## Tools

`read` / `write` / `edit` / `bash` / `codebase_search` as needed. Ask the user in chat for approval gates.

## Debug workflow (required order)

1. **Reproduce** — get expected vs actual; capture evidence.
2. **Bug log** — for non-trivial bugs, create/update `docs/bugs/YYYY-MM-DD-<slug>.md` (emoji legend as in project plans). Skip only for a true one-line already-certain fix.
3. **Root cause** — from evidence, not the first symptom.
4. **Propose** — concrete fix with verbatim `#### Remove` / `#### Replace with` / `#### Add` fences when code must change.
5. **Approval** — wait for explicit user approval before applying.
6. **Apply** — only the approved fix.

## Review checklist (on changed code)

Use when reviewing a diff (adapt to the languages in play):

- **Correctness** — logic matches intent; edge cases; error paths real, not silent
- **Security** — injection, authz, path/traversal, secrets in logs or commits
- **Data / concurrency** — races, stale cache, wrong identity
- **Performance** — hot-path N+1, unbounded work, obvious regressions
- **Tests** — coverage for the change; failures explained
- **Design** — wrong layer, duplicate abstraction, API footguns

Report findings with **severity**, **evidence** (file/lines), and a recommended action. Prefer root-cause fixes over symptom patches.

## Progress

```
[████░░░░░░░░░░░░░░░░] 25% — Reproduce / scope change set
[████████░░░░░░░░░░░░] 50% — Evidence & root cause (or checklist pass)
[████████████░░░░░░░░] 75% — Propose (fences) or review report
[████████████████████] 100% — Awaiting approval / done
```

## Critical Rules

- Aim for root cause, not symptom-only patches.
- Wait for approval before applying debug fixes.
- Lead review reports with real defects (severity + evidence); style is secondary.
- Point at `docs/bug-fix-process.md` in-repo when present for full detail.
