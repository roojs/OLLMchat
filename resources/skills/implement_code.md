---
name: implement_code
description: Use when you need to write new code or modify existing code based on a plan; supports new files or updating functions/classes via AST references. Multiple implement_code tasks should be created for all implementation steps (e.g. one per step or per file); the task iterator typically creates these after the user has reviewed and approved plans.
tools: write_file, write_chunk
---

## Implement code skill

Writes or modifies code files based on a plan or specification. Supports creating new files or updating existing ones using AST references. **Task list design:** create **multiple implement_code tasks** for all implementation steps (e.g. one task per plan step or per file to modify). These tasks are usually added by the **task iterator** after the user has reviewed and approved the plan(s).

### Input (this skill)

From the standard input, **What is needed** and **Precursor** (e.g. plan, code references, or analyze_code_standards output) define what to implement. The refinement step produces tool calls with:

**New file:** `file_path`, `code_content`.

**Modification:** `file_path`, `ast_reference` (e.g. "method:env"), `new_code`.

### Output

Confirmation message: "Successfully wrote to [file_path]" or "Successfully updated [file_path] at [ast_reference]".

### Instructions

#### Refinement

- For **new file**: emit one **write_file** tool call with **file_path** and **code_content** (or equivalent arguments from the tool definition). Path and content should be concrete from "What is needed" and Precursor (e.g. plan, code references).
- For **modification**: emit one **write_chunk** tool call with **file_path**, **reference_type**: "ast", **reference**: `ast_reference` (e.g. "method:env"), **new_content**: `new_code`. Resolve file path and AST reference from References/Precursor.

#### Execution (what to do with the results)

- **New file:** Use the `write_file` tool output (if any) or confirm from Precursor; ensure the directory exists (create it or handle error if not). Report success: "Successfully wrote to [file_path]".
- **Modification:** Use the `write_chunk` tool result; report "Successfully updated [file_path] at [ast_reference]".
- Ensure the new code is syntactically correct and follows the project's style. When Precursor or References include **analyze_code_standards** output (or links to coding standards), apply those standards; otherwise use any referenced CODING_STANDARDS or project rules. Optional: verify by reading back if a read tool exists.

### Example (modification)

**Input:**

- `file_path = "liboccoder/Skill/Runner.vala"`
- `ast_reference = "method:env"`
- `new_code` = updated `env()` method body (e.g. adding a new line to the returned string)

**Output:** "Successfully updated liboccoder/Skill/Runner.vala at method:env"
