---
name: analyze_codebase
description: Use when you need to locate particular pieces of code in the codebase (usages, methods, classes, or code related to a concept or feature).
tools: codebase_search
---

## Refinement

**What is needed** is the description of what to find in the codebase (e.g. "where task list is parsed", "skill definition load", "how to call the runner"). Produce one or more **codebase_search** tool calls with **query** and, when useful, the optional parameters below.

### Tool: codebase_search (options worth using)

- **query** (required): search text describing what code to find. See **Formulating queries** below for two ways to phrase queries.
- **element_type** (optional): narrow results to specific kinds of elements so you get **methods or classes instead of whole files**. Code: `"method"`, `"class"`, `"function"`, `"constructor"`, `"property"`, `"field"`, `"struct"`, `"interface"`, `"enum_type"`, `"enum"`, `"delegate"`, `"signal"`, `"constant"`, `"file"`. Prefer **method**, **class**, or **function** when the goal is "how to use X" or "where X is implemented"; use **file** only when the whole file is the unit of interest. **Note:** The tool treats `"function"` and `"method"` the same (a search with either returns both). In OOP codebases, callable symbols are often indexed as `"method"`; using either element_type is fine.
- **language** (optional): filter by language (e.g. `"vala"`, `"python"`, `"javascript"`). Use when the project or goal is language-specific to reduce noise.
- **max_results** (optional): max hits to return (default 10). Increase when you want more candidates; decrease for a tight shortlist.
- **category** (optional): for documentation elements only (`element_type` "document" or "section"). Values: `"plan"`, `"documentation"`, `"rule"`, `"configuration"`, `"data"`, `"license"`, `"changelog"`, `"other"`. Omit when searching source code.

**Formulating queries** — use multiple words and match how code is described:

- **Use multiple words.** Searching for a single specific method or symbol name will usually fail. The index stores **descriptions of what code does** (from analysis), so phrase queries in terms of behaviour or purpose, not just names.
- **Matching is fuzzy** — you don't need synonyms or minor variations (e.g. "parse" vs "parsing" adds little). Different concepts (e.g. parse vs tokenize) can help a bit. A **mix of long sentences and short 3–4 word phrases** often works better: e.g. one query like "where the skill definition is loaded from file" and another like "load skill from file".
- **How it would be described:** Think about how the code you want would be described—in a comment, docstring, or the analysis summary. Search for that. For example, "load skill definition from file" or "loads skill from file" rather than a single method name. Matching descriptions of behaviour works better than guessing symbol names.
- **Distinct types or names:** If you know distinct types or property names that might be used by the code you're looking for (e.g. `OptionEntry`), try searching for those as well.

**Encourage:** Multiple tool calls with different **element_type** or **query** (e.g. one call with `element_type: "method"` and one with `element_type: "class"`) to get both call sites and type definitions. Including **element_type** yields symbol-level results; omitting it often returns more whole-file or mixed results.

---

Summarize the result in a **short paragraph** that lists all relevant information found, with links (whole file or part of file) and why each is relevant. If you did not find anything, say so clearly. If a search did not produce useful results, say that (e.g. searching for X was not a good idea as it did not produce any results).

Use markdown links: whole file (path only) or part of file (path#anchor — use AST path format for code symbols, e.g. `#Namespace-Class-methodName`, not plain symbol names). Prefer symbol-level links (methods, classes) when a specific part is relevant; link to the whole file when the file as a whole is the unit of interest. Do not paste long code.

Output **Result summary** only: that short paragraph with inline links and why each link is relevant. No separate section.

### Example

**Input:** codebase_search result(s) in Precursor.

**Output:**

## Result summary

Searched for skill loading. Found [Definition.load](/path/to/liboccoder/Skill/Definition.vala#OLLMcoder.Skill-Definition-load) — loads skill from file, validates header has "name"; and [Definition](/path/to/liboccoder/Skill/Definition.vala) (class) — holds path and header, call load() on an instance. These are the relevant pieces for loading a skill by path.
