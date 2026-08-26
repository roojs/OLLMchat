# Consolidate multi-file task list outputs

## Status

⏳ PENDING

## Purpose

Merge separate task output files generated during the create and iteration stages into a single consolidated file to reduce filesystem noise, simplify downstream reading, and improve reliability of multi-step task outputs.

## Problem Summary

Currently, multi-file task outputs are written individually (via `List.vala` and `Details.vala`) during task creation and iteration. This scatters related context across multiple files, making it harder for the agent to review previous work and harder for external consumers to aggregate results. We need a unified single-file format and the logic to produce it at both the creation and iteration boundaries.

## 1. Single-File Output Format

- **Issue:** Multiple files per task create noise and context fragmentation.
- **Goal:** Define a clear, machine- and human-readable single-file format that aggregates all tool outputs, diffs, and results for a given task run.
- **Format Spec (`.task.md`):**
  - **YAML Frontmatter:** `slug`, `status` (`pending`/`progress`/`completed`), `created_at`, `completed_at`.
  - **`## Task Definition`:** `What is needed`, `Skill`, `References`.
  - **`## Execution Log`:** Ordered list of runs. Each run: `### Run {n}`, `tool: <name>`, `status: <ok|failed>`, `### Output` (fenced).
- **Scope:** `liboccoder/Task/Details.vala` (builder/parser), `liboccoder/Task/Tool.vala` (append logic), `docs/` (format spec).
- **Considerations:** Append-only for execution log to avoid rewriting massive blocks. YAML frontmatter updated atomically per run.
## 2. Task Creation Stage Consolidation

- **Issue:** The initial `Runner` flow creates separate files via `task_creation_prompt`.
- **Goal:** Capture initial state and output into the `.task.md` without losing `pending`/`progress` tracking.
- **Migration Steps:**
  1. **`List.vala` (`write()`):** Keep dual-writing `task_list.md` for existing consumers, but introduce `write_task(Details t)` to create `.task.md` with frontmatter and `## Task Definition`.
  2. **`Details.vala`:** Replace direct `slug.md` write with a call to `List.write_task()` initializing the file.
  3. **`Runner.vala`:** No changes to prompt generation; `pending`/`progress` lists remain in-memory. The consolidated file replaces `task_dir/slug.md`.
- **Considerations:** `pending`/`completed` state stays in `Task.List`/`Runner`; the file acts as durable storage. File creation is guarded by `GLib.File.test()` to prevent overwrites. Backward compatibility is maintained by dual-writing legacy lists until full deprecation.
## 3. Task Iteration Stage Consolidation

- **Issue:** Iterations currently append or replace individual files via `Chat.toolsReply` and `Tool.executor_prompt`.
- **Goal:** Append run logs to `.task.md` incrementally; update YAML frontmatter status on completion.
- **Migration Steps:**
  1. **`Tool.vala` (`run()`):** After a successful run, generate the `### Run {n}` markdown block. Use a dedicated `append_execution_log(path, block)` helper to append to the bottom of `.task.md`. Update frontmatter `completed_at` and `status: "completed"` atomically on task completion.
  2. **`Chat.vala` (`toolsReply()`):** Pass the `Tool` instance to `append_execution_log` or trigger it via `Tool`'s callback. Ensure `GLib.FileUtils.set_partial_contents()` or temp-file + rename is used to prevent corruption.
  3. **`List.vala`:** Update `task_list.md` and `task_list_completed.md` by parsing the new `.task.md` frontmatter/executions instead of relying on scattered markdown files.
- **Considerations:** Appending preserves previous tool outputs for context. Frontmatter updates use a temp file + rename for atomicity. Dual-write legacy lists until downstream consumers are migrated.
## Phases

- **Phase 1:** Design and document the single-file format. Update `Details.vala` to include a builder/parser for the new structure.
- **Phase 2:** Update `Runner.vala` (create stage) and `Tool.vala` / `Chat.vala` (iteration stage) to use the new format. Add acceptance tests verifying file count and structure.

## Related Plans

## Deliverables

- Single-file format specification.
- Updated `Details.vala` builder/parser.
- Refactored `Runner` and `Tool` write paths.
- Tests covering creation and iteration edge cases.

**Outstanding:**

- Confirm whether to use append mode or atomic replace per iteration.
- Validate impact on existing downstream consumers that currently read per-file task details.