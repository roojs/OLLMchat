# Test: parse_task_list / AST-path link rendering (oc-test-gtkmd)

Content taken from history 2026/03/10 21-47-25.json — link that renders oddly.

## Reference Link (list item)

- **Reference Link** [parse_task_list](/home/alan/gitlive/OLLMchat/liboccoder/Task/ResultParser.vala#OLLMcoder.Task-ResultParser-parse_task_list)

- **Reference Link** [parse_task_list_iteration](/home/alan/gitlive/OLLMchat/liboccoder/Task/ResultParser.vala#OLLMcoder.Task-ResultParser-parse_task_list_iteration)

## Inline in paragraph (backtick-wrapped label)

Search located where task-list.md, completed-list.md, and proposed-list.md outputs are generated in `liboccoder/Skill/Runner.vala` (file) — specifically the [`run_task_list_iteration`](/home/alan/gitlive/OLLMchat/liboccoder/Skill/Runner.vala#OLLMcoder.Skill-Runner-run_task_list_iteration) method writes `task_list_latest.md` and `task_list_completed.md`, while the prompt template for iteration is generated via [`iteration_prompt`](/home/alan/gitlive/OLLMchat/liboccoder/Skill/Runner.vala#OLLMcoder.Skill-Runner-iteration_prompt). Task list parsing uses `liboccoder/Task/ResultParser.vala` with [`parse_task_list`](/home/alan/gitlive/OLLMchat/liboccoder/Task/ResultParser.vala#OLLMcoder.Task-ResultParser-parse_task_list) for initial lists and [`parse_task_list_iteration`](/home/alan/gitlive/OLLMchat/liboccoder/Task/ResultParser.vala#OLLMcoder.Task-ResultParser-parse_task_list_iteration) for refinements, both validating structure with required headings.

## Link with comma in label (References line)

- [ResultParser.vala - parse_task_list, parse_task_list_iteration](/home/alan/gitlive/OLLMchat/liboccoder/Task/ResultParser.vala#OLLMcoder.Task-ResultParser-parse_task_list)

## Minimal: single problematic link

[parse_task_list](/home/alan/gitlive/OLLMchat/liboccoder/Task/ResultParser.vala#OLLMcoder.Task-ResultParser-parse_task_list)

## Anchor format note

Anchors use AST path format with a dot in the namespace: `OLLMcoder.Task-ResultParser-parse_task_list` (not `OLLMcoder-Task-ResultParser-parse_task_list`).
