# Analysis: Task list validation errors show wrong task names (planning only — do not implement yet)

## Scope: initial task list creation, not task list iteration

The bug is in the **original task list creation** flow: `Runner.send_async()` tries up to 5 times to get a valid task list. It is this **failing and retrying loop** that produces the wrong/stale issue messages. We are not talking about `run_task_list_iteration()` (the later flow that refines the list after steps complete).

## What you see (fact)

- Error messages refer to task names/sections from a **previous** try (e.g. "Analyze File Location", "Task 9", "Task 10", `task://research-task-output-structure.md`).
- The **current** task list content has different names (e.g. "Analyze Task Output Structure", different references).
- So the errors are **stale**: they are from an older try in the initial-creation loop that we should have discarded, not from the most recent parse.

## Flow in send_async (initial creation)

1. Loop (try_count 0..4): build `task_creation_prompt(..., previous_proposal, previous_proposal_issues, ...)`.
2. Send prompt, get `response`.
3. `this.pending = new List(this);` then `parser = new ResultParser(this, response); parser.parse_task_list();`
4. If `parser.issues == ""`: success, exit. Else: `previous_proposal = parser.proposal; previous_proposal_issues = parser.issues;` then `add_message("Task list had issues (retrying)", previous_proposal_issues);` and loop again.

So we **do** set a fresh `List` before each `parse_task_list()`. Parsing builds only the current response into that list; we don’t append to an existing list. So the “append to existing list / validate old+new” explanation does **not** apply to initial creation.

## Open question (to resolve)

Where do the stale issues come from in this loop?

- We set `previous_proposal_issues = parser.issues` and then `add_message(..., previous_proposal_issues)`, so the message should carry the issues from the parse we **just** did (current try).
- So either:
  - **A)** Something else is displaying an issues string that is not updated per try (e.g. a cached or once-set value), or
  - **B)** The “current task list” the user is looking at comes from a different try than the issues message (e.g. UI shows one try’s proposal and another try’s issues), or
  - **C)** There is another code path that runs during or after this loop and shows issues from an earlier run.

Next step: trace exactly what the user sees (which UI element shows the “current” list vs which shows the “issues”) and which variables feed each, so we can pin down why the issues text is from a previous try.

## Proposed way to debug (do not implement yet)

1. **Tag each try’s data in the loop**  
   In `send_async`, at the start of each loop iteration, assign a distinct “try id” (e.g. `try_count` or a short timestamp). When you set `previous_proposal` and `previous_proposal_issues` after a failed parse, also store this try id with them (e.g. in a small struct or in a single debug string). When you call `add_message(..., previous_proposal_issues)`, include the try id in the message (e.g. prefix: `[try N]` or add it to the fenced block title). That way you can see in the UI which try the displayed issues are supposed to come from.

2. **Log at parse and at display**  
   Right after `parser.parse_task_list()` (and before the `if (parser.issues == "")` branch), log once: try id, length of `response`, length of `parser.issues`, and a fixed-width snippet of the first task name or section title parsed from `response` (e.g. first “Task section” or first “Name” in the parsed list). Right before `add_message(..., previous_proposal_issues)`, log: try id, length of `previous_proposal_issues`, and the same kind of snippet from `previous_proposal_issues`. Compare: the snippet in the log at display time should match the snippet from the parse that just ran; if it matches an earlier try’s parse, the wrong variable or an old value is being shown.

3. **Confirm which document the user is looking at**  
   When the bug happens, note whether the “current” task list the user compares to the errors is (a) the last assistant message in the chat, (b) a dedicated task-list panel or file (e.g. `task_list.md` or similar), or (c) the “Previous Proposal” (or similar) section inside a prompt or a copy of it. If it’s (b) or (c), that content may be from a different try than the issues message; the try-id tagging and logs will show whether the issues message is from the same try as that content.

4. **Check for other writers of “issues” or “task list”**  
   Search the codebase for any other place that sets or appends to the string that ends up in the “Task list had issues” (or equivalent) UI, or that writes the “current” task list to the place the user is looking at. If there are multiple writers (e.g. one in the loop and one in a handler or later step), the try-id and parse-time vs display-time logs will show which code path produced the stale text.

5. **Interpretation**  
   - If the try id in the message matches the try id of the parse that just ran but the task names in the message don’t match the parsed response, the bug is in how we build `parser.issues` or `issue_label()` from the current parse.  
   - If the try id in the message is from an earlier try, the wrong variable is being passed to `add_message` or something is overwriting it before display.  
   - If the “current” list the user looks at is from a different try than the issues message (e.g. list from try 3, issues from try 2), then the UI is mixing two tries; the fix is to show issues and the list for the same try together, or to make it explicit which try each block refers to.

## Summary

| Item | Conclusion |
|------|------------|
| Where is the bug? | Initial task list creation: `send_async()` retry loop (not task list iteration). |
| Do we use a fresh List? | Yes: `this.pending = new List(this)` before each `parse_task_list()`. |
| Why might issues be stale? | TBD: need to trace source of displayed issues vs source of displayed “current” list. |
