---
name: implement_code
description: Use when you need to write new code or modify existing code based on a plan; supports new files or updating functions/classes via AST references.
---

## Implement code skill

Use this skill when you need to write new code or modify existing code based on a plan. It handles creating new files or updating specific functions/classes via AST references.

### Description

Writes or modifies code files based on a specification. Supports creating new files or updating existing ones using AST references.

### Input

**New file:**

- **file_path** (string): Path where the new file should be created.
- **code_content** (string): Full content of the file.

**Modification:**

- **file_path** (string): Path to the existing file.
- **ast_reference** (string): Name of the function, class, or method to replace (must be uniquely identifiable in the AST).
- **new_code** (string): The new code for that chunk (e.g. the entire function body or definition).

### Output

Confirmation message: "Successfully wrote to [file_path]" or "Successfully updated [file_path] at [ast_reference]".

### Instructions

- **New file:** Use the `write_file` tool with the full `code_content`. Ensure the directory exists (create it or handle error if not).
- **Modification:** Use the `write_chunk` tool with `file_path`, `reference_type`: "ast", `reference`: `ast_reference` (e.g. "function:factorial"), `new_content`: `new_code`.
- After writing, you may optionally verify by reading back if a read tool exists; not required.
- Ensure the new code is syntactically correct and follows the project's style.

### Example (modification)

**Input:**

- `file_path = "math_utils.py"`
- `ast_reference = "function:fibonacci"`
- `new_code` = the iterative fibonacci function body/definition

**Output:** "Successfully updated math_utils.py at function:fibonacci"
