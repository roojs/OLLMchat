---
name: implement_code
description: Use when you need to write new code or modify existing code based on a plan; supports new files or updating functions/classes via AST references.
tools: write_file
---

**During refinement**

**Purpose:** Give the executor enough **Precursor** — resolved **References** and any prior tool output — so it can implement **What is needed**. Fill **Shared references** and **Examination references** with the plan, target files, standards (paths and sections), and prior task results; they are supplied with **What is needed** when the task runs.

**Applying code is not done here.** Refinement gathers context only. The **execution** step produces **Result summary** + **Change details** (structured markdown for edits to the tree). Do **not** emit fenced JSON “tool call” blocks whose purpose is to apply patches to the tree.

**How to split references (important):**

- **Shared references** = context reused across many edits: standards/rules, plans (or specific plan sections), prior task outputs, architecture notes, and other broad guidance.
- **Examination references** = concrete edit targets for this run: files or **significant chunks** of files to be changed (prefer one target per file/chunk; use AST or line anchors when possible).

**Recommendation:** For implementation tasks, build examination references **per file** or per **significant chunk** that will be edited. Keep shared references focused on cross-cutting context; do not put broad standards/plans into examination references.

**What to prepare:** From **What is needed** and this skill body, ensure the split above is explicit and complete (paths, **AST** or line anchors, behaviour from the plan). Do **not** assume the executor can guess missing paths or symbols.

---

Use **What is needed** together with **Precursor** (resolved **References** and any tool output for this task) and the plan/precursor material to decide **what** to change. Ground every path, symbol, and edit in that material — do not guess.

**Edits:** Prefer one **`## Change details`** section per file or logical change. **New files:** **complete_file** with **output_mode** **next_section** or **fenced**, **file_path** and body from the plan and Precursor. **Modifications:** **ast_path** + **location**, line range, or **output_mode** **replace** (two fences: existing excerpt + replacement) only when Precursor gives exact, safe text.

**Result summary:** Short prose — what changed, how it meets **What is needed**, with links to files and anchors (e.g. `[Runner.vala](/path/to/Runner.vala#OLLMcoder.Skill-Runner-env)`).

### Example (modification — shape only)

Precursor included the plan and [Runner.vala](/path/to/liboccoder/Skill/Runner.vala).

## Result summary

Updated [Runner.vala](/path/to/liboccoder/Skill/Runner.vala) at [env](/path/to/liboccoder/Skill/Runner.vala#OLLMcoder.Skill-Runner-env) per plan; satisfies **What is needed**.

## Change details

- **file_path** liboccoder/Skill/Runner.vala
- **ast_path** …
- **location** …
- **output_mode** fenced

```vala
… new or replaced fragment …
```
