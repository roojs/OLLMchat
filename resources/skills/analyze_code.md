---
name: analyze_code
description: Use after analyze_codebase to turn its findings into a how-to and example usage document. Receives the output from an analyze_codebase task and explains how to use the referenced code to meet the goals.
---

## Analyze code skill

Receives the output from an **analyze_codebase** task (Result summary + Analyze codebase results) and produces a Detail document that answers the goals: how to use the relevant code, methods to call, and example usage.

### Input (this skill)

From the standard input, **Precursor** contains the output from the **analyze_codebase** task (Result summary and Analyze codebase results with AST/file links). **What is needed** is the original goal (e.g. "how to load a skill", "where to add a new step"). This skill has no tool calls; it uses the precursor and any resolved reference content to write the how-to.

### Output (this skill)

Result summary and Detail. In Result summary: **summary of what this task did** to address the goal and **whether that answered it** (e.g. "Turned the codebase findings into a how-to: Definition and load() after setting the path; Detail below gives usage — enough to implement." or "The analysis had nothing relevant."). Do not describe system mechanics or use a literal "Goal:" line. In Detail: explain **how to use** the code identified in the codebase analysis — which methods to call, in what order, and **example usage** (code snippets) that show how to achieve the goal. Keep markdown links (AST path format for code) so downstream tasks can use the referenced content. End with a clear conclusion (enough to implement or what is still missing).

### Instructions

#### Refinement

- No tool calls. Ensure the task's **References** include the prior **analyze_codebase** task output (refiner adds a link to that task's results so Precursor contains Result summary + Analyze codebase results and any resolved reference content).

#### Execution (what to do with the results)

- Read the analyze_codebase output in Precursor (Result summary and **Analyze codebase results**). Use the referenced code (links and any resolved reference content in Precursor) to answer the goal in "What is needed".
- **Result summary**: one or two sentences — **what this task did** to address "What is needed" and **whether that answered it** (enough to implement / what was produced, or that the analysis was insufficient). Summarise the work and outcome; do not start with "Goal:" or refer to system behaviour.
- **Detail**: write a short **how-to** that explains how to use the relevant code to meet the goal. Include:
  - Which types/methods to use and when.
  - **Example usage**: minimal code snippets that show the intended usage (e.g. instantiate, call method, handle result). Base these on the codebase references from the precursor.
  - Keep markdown links to the code (AST or file) so later tasks can use the referenced content.
- Do not repeat long chunks from the precursor; synthesize and add concrete usage. End with enough to implement or what is still missing.

### Example

**Input:** Precursor = analyze_codebase output for "where skill definition is loaded from file"; What is needed = "how to load a skill from a path".

**Output:**

## Result summary

Turned the codebase findings into a how-to: use `Definition` and `load()` after setting the path; the Detail below explains usage — enough to implement.

## Detail

To load a skill definition from a file, use [Definition](/path/to/liboccoder/Skill/Definition.vala) and its [load](/path/to/Definition.vala#OLLMcoder.Skill-Definition-load) method. The class holds the file path and parsed header; `load()` reads the file and validates that the header has a valid `"name"`.

**Example usage:**

```vala
var def = new OLLMcoder.Skill.Definition();
def.path = "/path/to/resources/skills/my_skill.md";
def.load();  // throws on invalid header
// then use def.header and file content as needed
```

Enough to implement skill loading from a path; see Definition.vala for full validation and error handling.
