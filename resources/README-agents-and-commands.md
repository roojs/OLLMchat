## Agents and commands (imported)

The `resources/agents/` and `resources/commands/` folders are copied from
https://github.com/humanlayer/humanlayer.

We are investigating how to integrate these definitions into our coding flow.
For now they are kept as-is for reference and comparison against upstream.

If you update or replace any files in these folders, document the source
revision and reasoning in this file so we can track changes over time.

## Working model for workflows

We are treating `resources/commands/` as workflow definitions. The orchestrator
should:

1. Analyze the user's request.
2. Propose a ranked list of workflows that fit the request, with a short reason
   for each.
3. Ask a clarifying question if needed:
   - "The user asked: <restated request>"
   - "We think <workflow> fits best."
   - "Please fix any typos/spelling in the request so we can apply the workflow."
4. Once confirmed, use the selected workflow as the system message for the LLM
   execution step.

## Workflow categories (commands)

Grouped by what the user is trying to do. Names only for now.

### Workflow tree map (summary)
- Plan-based flow
  - `create_plan.md`, `create_plan_generic.md`, `create_plan_nt.md`
    - `iterate_plan.md`, `iterate_plan_nt.md`
      - `validate_plan.md`
        - `implement_plan.md`
          - `local_review.md`
            - `describe_pr.md`, `describe_pr_nt.md`, `ci_describe_pr.md`
              - `commit.md`, `ci_commit.md`
          - `create_handoff.md`
            - `resume_handoff.md`
- One-shot flow
  - `oneshot_plan.md`
    - `oneshot.md`
- Research flow
  - `research_codebase.md`, `research_codebase_generic.md`,
    `research_codebase_nt.md`
  - `ralph_research.md` (RALPH = Research, Analyze, Plan, Launch, Handoff)
- RALPH flow (Research, Analyze, Plan, Launch, Handoff)
  - `ralph_plan.md`
    - `ralph_impl.md` (RALPH implementation step)
- Debug flow
  - `debug.md`
- Setup and ops flow
  - `create_worktree.md`
  - `linear.md`
- Mode flow
  - `founder_mode.md`


## Agents (sub-agent) summary

The agents in `resources/agents/` are specialized helpers that can be invoked
by workflows:

- `codebase-locator`: Find where relevant code lives (paths only).
- `codebase-analyzer`: Explain how existing code works (implementation detail).
- `codebase-pattern-finder`: Find similar patterns and show concrete examples.
- `thoughts-locator`: Locate relevant notes in the `thoughts/` hierarchy.
- `thoughts-analyzer`: Extract high-value insights from those notes.
- `web-search-researcher`: Perform web research and summarize sources.

We should note which workflows call out to these agents and under what
conditions (e.g., "research_codebase*" uses locator/analyzer/pattern-finder,
"ralph_research" uses web-search-researcher).
