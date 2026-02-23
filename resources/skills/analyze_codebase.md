---
name: analyze_codebase
description: Use when you need to search the codebase for usages, methods, or code related to a concept or feature. Always follow this task with analyze_code, which receives this task's output and produces a how-to and example usage document.
tools: codebase_search
---

## Analyze codebase skill

Searches the codebase semantically (tool: **codebase_search**) to find existing code: usages, methods, classes, or features related to what is needed.

### Input (this skill)

From the standard input, **What is needed** is the description of what to find in the codebase (e.g. "where task list is parsed", "skill definition load", "how to call the runner"). The refinement step produces one or more **codebase_search** tool calls with **query** and, when useful, the optional parameters below.

### Tool: codebase_search (options worth using)

- **query** (required): search text describing what code to find.
- **element_type** (optional): narrow results to specific kinds of elements so you get **methods or classes instead of whole files**. Code: `"method"`, `"class"`, `"function"`, `"constructor"`, `"property"`, `"field"`, `"struct"`, `"interface"`, `"enum_type"`, `"enum"`, `"delegate"`, `"signal"`, `"constant"`, `"file"`. Prefer **method**, **class**, or **function** when the goal is "how to use X" or "where X is implemented"; use **file** only when the whole file is the unit of interest.
- **language** (optional): filter by language (e.g. `"vala"`, `"python"`, `"javascript"`). Use when the project or goal is language-specific to reduce noise.
- **max_results** (optional): max hits to return (default 10). Increase when you want more candidates; decrease for a tight shortlist.
- **category** (optional): for documentation elements only (`element_type` "document" or "section"). Values: `"plan"`, `"documentation"`, `"rule"`, `"configuration"`, `"data"`, `"license"`, `"changelog"`, `"other"`. Omit when searching source code.

**Encourage:** Multiple tool calls with different **element_type** or **query** (e.g. one call with `element_type: "method"` and one with `element_type: "class"`) to get both call sites and type definitions. Including **element_type** yields symbol-level results; omitting it often returns more whole-file or mixed results.

### Output (this skill)

- **Result summary** (required): **summary of what this task did** to address the goal and **whether that answered it** (e.g. "Searched the codebase for skill loading; found Definition and load() in Definition.vala — enough for a follow-up how-to." or "Nothing relevant found."). Do not describe system mechanics or use a literal "Goal:" line.
- **Analyze codebase results**: Prefer **methods and symbols** (AST path links) over whole-file links unless the entire file is relevant. Use **AST path** format for code symbols (e.g. `[load](/path/to/Definition.vala#Namespace-Class-methodName)` — see project AST path format, not plain symbol names). Include a short summary of why each reference is useful. Optionally list **Top places to study**: the few locations (methods, classes, or files) that are most important to study first for the goal. This section is the input for a follow-up **analyze_code** task.

### Instructions

#### Refinement

- Emit one or more **codebase_search** tool calls. Pass **query** from "What is needed" (or concrete phrasings). Prefer **element_type** (e.g. `"method"`, `"class"`, `"function"`) so results are symbol-level; add **language** when the project is single-language.
- Use multiple calls with different element_type or query phrasings (e.g. "where X is used", "method that does Y", "class that defines Z") to get richer results. Optional: **max_results** if more or fewer hits are needed.

#### Execution (what to do with the results)

- Use the tool output(s) from Precursor. Prefer **symbol-level references** (methods, classes, functions) over whole-file links; link to whole files only when the file as a whole is the relevant unit (e.g. a small module or single-purpose file).
- For each result: record symbol or location with an AST link where possible, and why it is relevant. Prioritize by relevance; limit to the top 5–10 most relevant if there are many.
- Optionally start **Analyze codebase results** with **Top places to study**: 2–4 locations (methods or files) that should be studied first. Then list the full set of findings.
- Write **Result summary**: one or two sentences — **what this task did** (e.g. what was searched, what was found) and **whether that answered the goal** (enough for follow-up / nothing relevant). Summarise the work and outcome; do not start with "Goal:".
- In **Analyze codebase results**, use markdown links (prefer file#ast_path for methods/classes). Do not paste long code; links let the next task use the referenced content.

### Example

**Input:** e.g. codebase_search with `query = "where skill definition is loaded from file"`, optionally `element_type = "method"` or `"class"` to target symbols.

**Output:**

## Result summary

Searched the codebase for skill loading; found Definition and load() in `liboccoder/Skill/Definition.vala` — enough for a follow-up how-to.

## Analyze codebase results

**Top places to study:** [Definition.load](/path/to/liboccoder/Skill/Definition.vala#OLLMcoder.Skill-Definition-load), [Definition](/path/to/liboccoder/Skill/Definition.vala) (class) — these define how a skill is loaded and validated.

- [Definition.load](/path/to/liboccoder/Skill/Definition.vala#OLLMcoder.Skill-Definition-load) — loads skill from file, validates header has "name". Use this to load a skill by path.
- [Definition](/path/to/liboccoder/Skill/Definition.vala) — class holding path and header; call load() on an instance (whole file relevant here; small class).
