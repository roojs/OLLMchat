---
name: implement_code
description: Use when you need to write new code or modify existing code based on a plan; supports new files or updating functions/classes via AST references.
tools: write_file, write_chunk
---

## Refinement

Prepare the change blocks. Emit tool calls with concrete arguments from **What is needed** and **Precursor** (plan, code references, standards).

**New file:** Emit one **write_file** call with **file_path** and **code_content** (path and content concrete from Precursor).

**Modification:** Emit one **write_chunk** call with **file_path**, **reference_type**: "ast", **reference** (e.g. "method:env"), **new_content**. Resolve file path and AST reference from References/Precursor.

---

## Execution

Report what was changed and whether it was successful. **Always use link references** when referring to files and changes (e.g. [filename](/path/to/file) for the file; [symbol](/path/to/file#AST-path) for the changed location).

**New file:** Report e.g. "Successfully wrote to [filename](/path/to/file)" or that the write failed.

**Modification:** Report e.g. "Successfully updated [filename](/path/to/file) at [symbol](/path/to/file#AST-path)" or that the update failed.

### Example (modification)

**Input:** write_chunk with `file_path = "liboccoder/Skill/Runner.vala"`, `ast_reference = "method:env"`, `new_content` = updated method body.

**Output:**

## Result summary

Successfully updated [Runner.vala](/path/to/liboccoder/Skill/Runner.vala) at [env](/path/to/liboccoder/Skill/Runner.vala#OLLMcoder.Skill-Runner-env).
