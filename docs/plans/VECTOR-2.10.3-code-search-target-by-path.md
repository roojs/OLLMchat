# VECTOR-2.10.3: Code search — target by directory or file

**Source:** [Plan 1.23.23](done/1.23.23-DONE-task-iterator-skills-grep.md) Phase 9; previously [1.23.26](done/1.23.26-DONE-task-creator-guidance.md) item 2; [1.23.22](done/1.23.22-DONE-testing-issues.md) §1. Moved from `TOOLS-1.25` — path scoping is vector/index filtering work (`ollmfilesd` + `libocvector2`), not a generic tool concern.

## Status

⏳ **TODO** — not started.

## Goal

Code search (`codebase_search`) should support restricting search to a **specific file** or **directory** (path scope) so the LLM can answer “search only in X” instead of the whole repo.

## Scope

- **`liboctools/CodebaseSearch/Request.vala`** and **`Tool.vala`** — add a parameter (e.g. `path` or `path_scope`) accepted by the tool API; pass through on the `Codebase.search` RPC call.
- **`ollmfilesd/Codebase.vala`** — restrict `file_ids` (before `vector_metadata` filter / FAISS) to the given path: file = that file only; directory = that subtree.
- **Tool schema / registration** — expose the parameter to the model with clear description.

## Current behaviour

`RequestCodebaseSearch` exposes query, language, element_type, category, max_results — **no** path restriction today. `Codebase.search` already takes a project root `path` arg (not a scope filter).

## Related

- [VECTOR-2.10.2](VECTOR-2.10.2-background-scan-pause-and-foreground-reload.md) — other vector/index UX.
- **1.23.26** (done): Task creator guidance; code search split out here.
- **1.23.22** (done): Earlier mention of code search targeting.
