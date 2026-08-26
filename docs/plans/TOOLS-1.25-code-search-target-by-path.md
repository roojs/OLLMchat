# Plan 1.25: Code search — target by directory or file

**Source:** [Plan 1.23.23](done/1.23.23-DONE-task-iterator-skills-grep.md) Phase 9; previously [1.23.26](done/1.23.26-DONE-task-creator-guidance.md) item 2; [1.23.22](done/1.23.22-DONE-testing-issues.md) §1.

## Status

TODO — not started.

## Goal

Code search (`codebase_search`) should support restricting search to a **specific file** or **directory** (path scope) so the LLM can answer “search only in X” instead of the whole repo.

## Scope

- **`libocvector/Tool/RequestCodebaseSearch.vala`** — add a parameter (e.g. `path`, `path_scope`, or `target_path`) accepted by the tool API.
- Behaviour: limit vector/query execution to entries under that path (file = that file only; directory = that subtree).
- **Tool schema / registration** — expose the parameter to the model with clear description.

## Current behaviour

`RequestCodebaseSearch` exposes query, language, element_type, category, max_results — **no** path restriction today.

## Related

- **1.23.26** (done): Task creator guidance; code search split out here.
- **1.23.22** (done): Earlier mention of code search targeting.
