---
name: plan_task
description: Use when you need to create a detailed plan for implementing a coding task, with objectives, steps, and references from research and code analysis.
---

## Plan task skill

Use this skill when you need to create a detailed plan for implementing a coding task. It organizes objectives, steps, and references based on research and code analysis.

### Description

Creates a new plan document for a coding task. The plan includes objectives, step-by-step instructions, and references to code locations or research.

### Input

- **plan_title** (string): Title for the plan (used as basis for filename, e.g. "AddFactorialFeature").
- **task_description** (string): High-level description of what needs to be done.
- **research_summary** (string, optional): Output from research_topic.
- **code_analysis** (string, optional): Output from analyze_code.

### Output

The file path of the created plan (e.g. `plans/add_factorial_feature.md`).

### Instructions

1. Determine the file name: convert `plan_title` to a suitable filename (lowercase, underscores) and place in a `plans/` directory (e.g. `plans/add_factorial_feature.md`).
2. Use the `write_file` tool to create the file with this structure:

   - **Objective** — Clear statement of what the task accomplishes.
   - **Research summary** — Include `research_summary` if provided, else state "None".
   - **Code analysis** — Include `code_analysis` if provided, else state "None".
   - **Implementation steps** — Numbered steps (concrete and actionable).
   - **Code references** — File paths or functions to modify.

3. Populate each section from the inputs. Steps should be concrete (e.g. "Create a new function in utils.py", "Add import statement").
4. Return the file path as a string.

### Example

**Input:**

- `plan_title = "AddFibonacciFunction"`
- `task_description = "Implement a function to compute Fibonacci numbers efficiently."`
- `research_summary = "Dynamic programming approach reduces time complexity to O(n)."`
- `code_analysis = "Existing fibonacci function in math_utils.py uses recursion."`

**Output:** `plans/add_fibonacci_function.md`
