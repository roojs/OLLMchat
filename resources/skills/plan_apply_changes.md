---
name: plan_apply_changes
description: Use when you need to update the plan file based on plan_iterate or plan_create content.
tools: write_file, write_chunk
---

## Refinement

Use the **reference information** (plan_iterate or plan_create output in Precursor) to build the tool calls. Update the plan exactly as specified there.

**New plan or full replacement:** Emit one **write_file** call with **file_path** (plan_path) and **code_content** exactly as given in the reference.

**Update to existing plan:** Emit one or more **write_chunk** call(s) with **file_path**, **reference_type** and **reference** (e.g. section or AST location), **new_content** exactly as given in the reference.

**Only follow what is in the plan; do not modify or change anything.**

---

## Execution

Report what was written and whether it was successful. **Always use link references** when referring to the file (and, for write_chunk, the updated location).

**write_file:** Report e.g. "Successfully wrote plan to [plan-name.md](/path/to/docs/plans/plan-name.md)" or that the write failed.

**write_chunk:** Report e.g. "Successfully updated [plan-name.md](/path/to/docs/plans/plan-name.md) at [section-name](#section-name)" or that the update failed.

### Example (write_file)

**Input:** write_file with `file_path` and `code_content` from plan_create output (Precursor).

**Output:**

## Result summary

Successfully wrote plan to [add_writer_approval_gate.md](/path/to/docs/plans/add_writer_approval_gate.md).
