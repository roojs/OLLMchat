# Codebase search: tool output not markdown-friendly

**Status:** ⏳ OPEN — moved from `docs/plans/TOOLS-2.23-codebase-output-improvements.md` 2026-09-02

**Started:** (prior plan)

**Process:** `docs/bug-fix-process.md`

**Package / area:** `codebase_search` — `ollmfilesd/Codebase.vala` (`format_results()`), vector metadata (`libocvector2` / daemon RPC)

**Related:**

- ℹ️ Former plan: `TOOLS-2.23-codebase-output-improvements.md` (retired — vector output bug, not generic TOOLS)
- ℹ️ Vector category: [`VECTOR-1.0-summary.md`](../plans/VECTOR-1.0-summary.md)
- ℹ️ Parent tool: [`done/2.10-DONE-codebase-search-tool.md`](../plans/done/2.10-DONE-codebase-search-tool.md)
- ℹ️ Output polish sibling: [`TOOLS-2.23-tool-results-to-markdown.md`](../plans/TOOLS-2.23-tool-results-to-markdown.md) (skills agent path — different scope)

---

## Problem

🔷 `codebase_search` formatted results are hard to read in chat UIs and LLM context:

- Plain `Description:` / `ast-path:` labels (not bold markdown keys).
- Numbered results (`1. name (type) - path:lines`) instead of structured bullets.
- Code fences use `start:end:path` in the info string, not language tags.
- **Distance** (L2 relevance) is available on results but not shown.

🔷 Expected: bullet key/value lines (` - **Element** …`, ` - **Location** …`, ` - **Distance** …`), markdown **Link**, ` ```vala` fences, truncation comment inside the block.

---

## Evidence

- ✔️ `ollmfilesd/Codebase.vala` — `format_results()` still uses numbered headers and `Description:` / `ast-path:` plain labels.
- ✔️ Plan documented current vs proposed format and concrete replacement for the result loop (see **Proposed fix** below).

---

## Root cause

⏳ **Confirmed:** `format_results()` format was never updated after codebase search shipped; output layout predates markdown-friendly tool replies.

---

## Proposed fix direction

🔷 **File:** `ollmfilesd/Codebase.vala` — `format_results()`

🔷 Per-result bullets (no `1.` / `2.` numbering):

- ` - **Element** name (type)`
- ` - **Location** path:start-end`
- ` - **Link** [element_name](path#ast_path)`
- ` - **Distance**` (float, `%.4f`)
- ` - **Description**` and ` - **AST path**` always present (may be empty)

🔷 Code fence: opening line ` ```{language}` from `file.language`; if snippet contains ` ``` `, use longer fence (e.g. four backticks). When truncated (>50 lines), append inside block: `// content truncated - original code was N lines`.

💩 Full verbatim replacement loop was in the retired plan — copy from git history of `TOOLS-2.23-codebase-output-improvements.md` or re-draft fences here before implement.

---

## Attempts / changelog

- ✔️ 2026-09-02 — Moved from TOOLS plans to `docs/bugs/` (vector search output, not liboctools plan).

## Next

⏳ 🔷 Add verbatim **Remove** / **Replace with** fences in this file → approval → implement in `Codebase.vala`.
