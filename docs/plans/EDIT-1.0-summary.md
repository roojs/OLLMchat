# EDIT-1.0 — summary

> Category index for **EDIT** — agent file mutation in `liboctools` (`EditMode`, `WriteFile`, planned `ActiveEdit`). **Not** the generic **TOOLS** bucket (`run_command`, `read_file`, `browser`, …).

**Prefix:** `EDIT` · **All categories:** [`-README.md`](-README.md)

**Code:** `liboctools/EditMode/`, `liboctools/WriteFile/`

---

## Shipped (no open plan)

| Wire name | Class / path | Notes |
|-----------|--------------|--------|
| `edit_mode` | `EditMode.Tool` + `Stream` | Streaming fenced edits; AST path + line modes |
| `write` | `EditMode.Write` | Pi skeleton alias (same Request path) |
| `write_file` | `WriteFile.Tool` | One-shot write — plan archived [`done/EDIT-2.22-DONE-write-file-tool.md`](done/EDIT-2.22-DONE-write-file-tool.md) |

**ℹ️** Historical done (unprefixed): [`done/2.4-DONE-edit-file-tool.md`](done/2.4-DONE-edit-file-tool.md), [`done/2.1.4-DONE-ast-path-editfile-integration.md`](done/2.1.4-DONE-ast-path-editfile-integration.md), [`done/6.2-DONE-write-file-replace-support.md`](done/6.2-DONE-write-file-replace-support.md).

---

## Current plans

| Plan | Status | Worth doing? |
|------|--------|----------------|
| [EDIT-2.1.8-ast-path-incremental-application.md](EDIT-2.1.8-ast-path-incremental-application.md) | 📋 planned, **not urgent** | Only if multiple AST-path edits in **one** message mis-resolve today; single edits work |
| [EDIT-2.15-active-edit-tool.md](EDIT-2.15-active-edit-tool.md) | ⏳ **NOT STARTED** | Speculative (edits in prose, no tool call) — defer unless product wants it |

---

## Related (other categories)

- [BWRAP-2.6.2-open-first-changed-file.md](BWRAP-2.6.2-open-first-changed-file.md) — after `edit_file` / bwrap `run_command`, auto-open first modified/added file
- [TOOLS-2.23-tool-results-to-markdown.md](TOOLS-2.23-tool-results-to-markdown.md) — skills agent markdown tool output (all tools, not edit-only)
