# Tool list: six of sixteen tools missing `function.description`

**Status:** 🚫 **CLOSED** (2026-09-02) — obsolete UI; tools pulldown no longer used

**Started:** (prior plan; no single report date)

**Process:** `docs/bug-fix-process.md`

**Related:**

- ℹ️ Former plan slot: `TOOLS-2.20-tools-bugs.md` (retired — bugs live in `docs/bugs/`)
- ℹ️ Parent vector/scanner work: [`../plans/done/2.20-DONE-codebase-scanner-improvements.md`](../plans/done/2.20-DONE-codebase-scanner-improvements.md)
- ℹ️ Wrapped tools: `liboctools/ToolBuilder.vala`, `resources/wrapped-tools/*.tool`
- ℹ️ Serialization: `libollmchat/Tool/BaseTool.vala`

---

## Why closed

🔷 Symptom was empty `function.description` in the **tools pulldown / tool-list UI**. That pulldown is **gone** — we do not surface tools that way anymore — so this bug is **irrelevant**. Not fixing for a removed UI.

---

## Problem (archived)

🔷 With **16** tools registered, **6** have no `function.description` in the tool list (API payload / UI). The model and schema-driven UI see empty descriptions for those tools.

🔷 Expected: every registered tool has a non-empty `function.description` (from class `description`, wrapped `.tool` preamble, or agent `agent_description`).

---

## Evidence

- ℹ️ Tool list is built by serializing each tool; `BaseTool` serializes `function` — `function.description` is what the API/UI sees.
- ℹ️ Registration paths:
  1. **Standard tools** (`ReadFile`, `RunCommand`, `WebFetch`, …): `BaseTool.init()` from `this.description` / `this.parameter_description`.
  2. **Wrapped full tools** (`Grep`, `LS`, `Glob`): `ToolBuilder` sets `function.description = parser.description` (lines before first `@` in `.tool` file); does **not** call `init()`.
  3. **Wrapped aliases** (`Read`, `WebSearch`, …): reuse base tool `function`.
  4. **Agent tools**: `init()` from `agent_description`; parser skips empty description at registration.
- 💩 **Hypothesis:** one path leaves `function.description` empty, or sets it before properties are ready, or the “16 / 6” count is from config entries rather than `chat.tools.values`.

---

## Root cause

⏳ **Not confirmed** — identify the exact six tools and which registration path they use before fixing.

---

## Proposed fix direction

⏳ 🔷 **First:** log or assert which tools have `function == null` or `function.description == ""` after registration / `rebuild_tools()`.

💩 **If a path omits description:** fix that path (e.g. missing preamble in a `.tool` file, or `init()` ordering) — **not** only a title fallback.

🚫 **Do not** ship a blanket defensive fallback as the sole fix if it masks which tools/paths are wrong (`docs/bug-fix-process.md`).

💩 **Optional safety net** (only after root cause fixed or with explicit approval): `ToolBuilder` use `parser.title` when preamble empty; or `BaseTool` serialization use `title` when description empty.

---

## Attempts / changelog

- ✔️ 2026-09-02 — Moved from `docs/plans/TOOLS-2.20-tools-bugs.md` to `docs/bugs/` (not a plan).
- ✔️ 2026-09-02 — **CLOSED** — tools pulldown retired; archived under `docs/bugs/done/`.
