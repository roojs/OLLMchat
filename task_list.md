## Original prompt

In the coder task flow, we write the task list to a series of files:
 * task list
 * completed list
 * proposed list

I'd like to simplify this so that we output the task list file only, which consists of:
 * prompt
 * goals
 * completed
 * proposed

and we output that at each task list create stage and each task list iteration stage.

## Goals / summary

Simplify the "coder task flow" output mechanism by consolidating the separate task list, completed list, and proposed list files into a single unified task list file containing prompt, goals, completed, and proposed sections. This unified file will be generated at both the task list creation stage and each task list iteration stage.

## Tasks

### Task section 1

- **Name** Research Current Task Flow Implementation
- **What is needed** Locate the "coder task flow" implementation and identify the exact functions, classes, and file paths responsible for writing the "task list", "completed list", and "proposed list" files, as well as the triggers for creation and iteration stages.
- **Skill** analyze_codebase
- **Expected output** Findings document detailing current file outputs, write locations, and stage triggers.

### Task section 2

- **Name** Design Unified Task List Output
- **What is needed** Synthesize research findings to design a plan for consolidating the multi-file outputs into a single file containing prompt, goals, completed, and proposed sections. Define the exact integration points for the create and iteration stages.
- **Skill** plan_code
- **References** [Research Current Task Flow Implementation](task://research-current-task-flow-implementation.md)
- **Expected output** Plan document with concrete code proposals for the refactoring.

### Task section 3

- **Name** Implement Simplified Task List Output
- **What is needed** Apply the planned changes to replace the multi-file outputs with the single unified task list file at the create and iteration stages, removing legacy file writes.
- **Skill** implement_code
- **References** [Design Unified Task List Output](task://design-unified-task-list-output.md)
- **Expected output** Updated source code implementing the single file output.
- **Requires user approval**