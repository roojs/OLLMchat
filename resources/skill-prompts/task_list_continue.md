
## Do not put the original prompt in your output

**Do not put the original prompt in your output.** You receive the locked **Original prompt** below for context only. It must **not** appear in your response. If you include **## Original prompt**, the Runner discards it.

## Do not output completed tasks

**Do NOT add or repeat completed tasks in ## Tasks.** Output **only** new or revised **outstanding** tasks. Completed tasks (those with a **##### Result summary** block) are context only — reference them via **task://** links in new tasks, but do not list them as tasks to be done. Including completed tasks would re-run them and loop endlessly.

## What you receive

- **Original prompt** (context only — do not output)
- **Follow-up prompts so far** (prior prompt-box messages — already stored; do **not** output **## Follow-up prompts**)
- **Goals / summary** (current plan intent — you output a **revised** version)
- **Completed tasks** — only these have **##### Result summary**
- **Outstanding tasks** — not yet run; you may replace/revise them in **## Tasks**
- **This follow-up message** — the user's new prompt-box text (Runner appends to **`user_prompts`**; use it when revising goals and tasks)
- When retrying: **Issues with the tasks**, **Proposed (your last response — had issues)**
- **Skill catalog**, environment, project description

{skill_catalog}

## Rectification

When you receive **previous proposal issues** (or **Issues with the tasks**), fix the problems in your revised output. You may include optional **## Issues with the tasks (what I changed)** listing each issue and how you addressed it. When no issues are supplied, omit that section. For invalid **task://** references: re-derive the slug from the task **Name** on a completed or outstanding task.

## Focus on the expanded plan

Stay aligned with the **original prompt**, all **follow-up prompts**, and the **revised goals**. The user's latest message may **expand** scope — reflect that in **Goals / summary** and in **Tasks**. Do **not** drift into unrelated work.

## Code and document changes — do not assume

Do **not** add tasks that modify code or documents unless the user's prompts **explicitly** allow it. When in doubt, do not add implementation or edit tasks.

## When adding or revising tasks — RAPIR and ordering

Order work in **RAPIR** order: Research → Analyze → Planning → Implementation → Review. Put independent tasks in the same **task section** (may run in parallel). Put tasks that depend on another task's output in a **later** section. If a task references **task://slug.md**, it must be in a **later** section than the producer. **Sections run sequentially**; within a section, tasks may run **in parallel** — **no** references to another task in the **same** section.

## Tasks that require user approval

Any task that **modifies code or files** must include **Requires user approval** (exact label). Omit for read-only tasks. When in doubt for file-modifying work, include it.

## No assumptions

Do **not** assume information that research can obtain. Add explicit **research** tasks instead of guessing APIs, layout, or standards.

## Goals / summary (revised — you must output this section)

Summarize what the **whole** plan is trying to achieve **now**: original prompt + all follow-ups + relevant completed-task outcomes.

- **Prefer** one **short paragraph** when goals stay focused.
- If there are **many distinct goals**, use **markdown `-` bullets**; **prefer nested bullets** for sub-goals — **not** multiple long prose paragraphs.
- **Length cap:** no more **top-level** goal bullets than user prompts in this session (original plus each follow-up **including this message**). Merge related aims; do not inflate.
- Do **not** paste full prompt text or task output bodies — state intent and outcomes only.

## Your job

When **issues** are supplied, fix them and optionally add **Issues with the tasks (what I changed)**; then:

1. **## Goals / summary** — revised per **Goals / summary (revised)** above.
2. **## Tasks** — **only** outstanding work to run next (new or revised); all discipline below applies.
3. **Do not** output **## Original prompt** or **## Follow-up prompts** — the Runner records the prompt-box message.

***

## Markdown output

If text could be mistaken for markdown structure, wrap it in a fenced `text` block so the parser does not misread it.

## Output format (machine-parsed — follow exactly)

Produce these sections **in order** (continuation-specific — same idea as iteration tasks-only plus goals):

### ## Goals / summary

Revised goals per **Goals / summary (revised)** above.

### ## Tasks (and optional issues on retry)

- **## Goals / summary** and **## Tasks** — required.
- Optionally **## Issues with the tasks (what I changed)** when retrying after parse failures.
- **Do not** output **## Follow-up prompts** or **## Original prompt**.

**## Tasks** — Split into **task sections** (`### Task section 1`, `### Task section 2`, …). **Sections run sequentially**; **within a section** tasks may run **in parallel**. Under each section, for each task: every line starts with `-`. For each task provide:

- **Name** (optional) — stable name when others will reference this task's output. Slug: lowercase Name; each run of spaces and non-alphanumeric → **one** hyphen (e.g. "Analyze Current Structure" → task://analyze-current-structure.md).
- **What is needed** (required)
- **Skill** (required) — exactly one skill from the catalog; name must match catalog exactly
- **References** (optional) — markdown links only; see **Reference link types**
- **Expected output**
- **Requires user approval** (optional) — when modifying code or files

**Invalid links are forbidden.** Be **100% certain** every link is valid before output. **Do not** guess paths, slugs, or anchors. If uncertain, omit the link and add a **research** task.

**Do not** include **Output** or a **##### Result summary** block on tasks in your output — only completed tasks have those; the parser rejects them on new tasks.

## Referencing previous task results

Use **task://{slug}.md** only for **completed** tasks (URL ends at **`.md`**). In **What is needed**, say which part of that output matters. **Never** append `#anchor` to a **task://** URL.

## Task reference naming (critical)

- **Do** — Lowercase the **Name**; each maximal run of spaces and non-alphanumeric → **one** hyphen; trim ends.
- **Do** — **task://{slug}.md** stops at **`.md`**
- **Don't** — Stack hyphens (`--`) from character-by-character substitution
- **Don't** — Put anything after **`.md`** in **task://**
- **Spelling matters:** "Analyze …" and "Analysis …" produce **different** slugs — match the task **Name** exactly.

**Double-check every task:// link** against completed/outstanding task **Names** before output.

## Reference link types (use only these)

- **Do** — `[Title](path)` for **concrete files** (optional `#anchor`), **task://…**, **http(s) URLs** in **References** — not directory-only or glob paths
- **Do** — Project-relative paths with **no** leading `/` for repo files (e.g. `liboccoder/File.vala`), or full filesystem paths from `/`
- **Do** — `#anchor` on files: lowercase heading; spaces/punctuation → **one** hyphen between word runs
- **Don't** — Guess or invent paths, slugs, or URLs
- **Don't** — Use `/.cursor/...` or `/liboccoder/...` for in-repo files (leading `/` is OS root, not project root)
- **Don't** — Paste file bodies into the task list

## Strict format (required for parsing)

- **Section headings** — Exactly `## Goals / summary`, `## Tasks` (plus optional `## Issues with the tasks (what I changed)`). Under Tasks: exactly `### Task section 1`, …
- **Every task line starts with `-`** — `- **Name** ...`, `- **What is needed** ...`, etc. **No colon after the label** (**Skill** not **Skill:**). Blank line between tasks.
- **No numbered lists** for tasks
- **No variations** in section or field names

## Example structure (continuation output — illustrative only)

## Goals / summary

- Deliver the API changes from the original request
  - Include validation and error handling per the latest follow-up

## Tasks

### Task section 1

- **Name** Research API errors
- **What is needed** Find how errors are handled in the existing API code.
- **Skill** analyze_codebase
- **References** [Prior API task](task://implement-api.md)
- **Expected output** Findings on current error paths.

---

{original_prompt}
{follow_up_prompts}
{goals_summary}
{completed_task_list}
{outstanding_task_list}
{user_follow_up}
{environment}
{project_description}
{previous_proposal_issues}
