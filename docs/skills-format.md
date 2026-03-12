# Skills format

This document defines the standard used to author executor skills in `resources/skills/`. Use it when creating or updating skill files. The flow is: **task creation** (coarse task list) → **refinement** (per task: concrete Skill call + Tool calls) → **execution** (run tools, then run the skill; it produces Result summary + Detail) → **iteration** (optional: compare outputs to goals, add tasks if needed).

---

## Task creator and summary

### Task creator

The **task creator** is what turns the user’s request into a task list. It does not run tools or execute tasks; it only produces the list. It receives:

- The **user’s request** (natural language).
- **Context**: environment (OS, workspace path, shell, date), optional project description, the currently open file (path and contents) if any, and optional other open/recent file paths. If a previous task list had issues, it may also receive that list and the issues so it can revise.
- The **skill catalog**: every executor skill in `resources/skills/`, each as **name** and **description**. The task creator must assign only skills from this catalog. The **description** is the “when to use” line from the skill’s frontmatter — it is what the task creator uses to choose the right skill per task.

It produces a **task list** with:

- **Original prompt** — The user’s request as stated.
- **Goals / summary** — One short paragraph: what we are trying to achieve with this task list (see below).
- **Tasks** — Split into **task sections** (e.g. Task section 1, Task section 2). Sections run **sequentially**; tasks **within** a section may run **in parallel**. Each task has: **Name** (optional), **What is needed**, **Skill** (from the catalog), **References** (markdown links), **Expected output**, and optionally **Requires user approval**.

Discipline (RAPIR, no assumptions, research before code changes, etc.) is applied when creating and updating the list; the skill catalog is the single source of skill names and when to use them.

### Goals / summary

**Goals / summary** is the one-paragraph summary of what the task list is for. It is set when the task list is first created and preserved when the list is updated. It is used to:

- Orient anyone reading the list.
- Decide, after a round of execution, whether the **goals are complete** or more tasks are needed.

So the summary drives both the initial plan and the decision to add more work. Executor tasks do not receive Goals / summary directly; they receive **What is needed** and **Precursor**. The summary is list-level context for the task creator and for the iteration step.

### Task list iteration

After a round of task execution, the runner may send the **current task list** (with each completed task’s **##### Result summary** block with raw summary text) to an **intermediary analyst**. The analyst:

- Compares completed outputs to the **Goals / summary**.
- If the goals are satisfied, returns the same list (no new tasks).
- If not, returns the full list **plus new tasks** in the same format, in RAPIR order, using only skills from the catalog. New tasks do not have a result summary block yet.

So the task list can grow over time; the summary stays the same and is the yardstick for “are we done?”.

---

## Refinement

Between task creation and execution, **each task is refined**. The refiner turns one **coarse** task (What is needed, Skill, References, Expected output) into a **concrete** task with a **Skill call** (skill name plus full arguments) and **all Tool calls** needed so the skill has the information it needs. The refiner does not run tools or execute the skill; it only produces the refined task and the list of tool calls. The runner then runs those tools and passes their outputs to the executor.

### What the refiner receives

- **One coarse task** — Name, What is needed, Skill name, References (markdown links), Expected output. This is a single task from the task list.
- **The skill document** — The full content of the assigned skill. The refiner uses it to see what the skill needs (inputs, tools) and what information to gather via tool calls before the skill runs.
- **Tools definition** — Tool names, descriptions, and parameters. This defines how to invoke each tool (e.g. one fenced JSON block per call with **name** and **arguments**). The refiner builds the Tool Calls section in this format.
- **Task reference contents** — The **resolved** content of this task's References only (environment, project description, current file, file contents, prior task outputs, URLs). The refiner uses this to fill in concrete values for the Skill call and to decide what to request via tool calls (e.g. avoid requesting a whole file if it's already in References; use a tool for a specific line range if needed).
- **Completed tasks (so far)** — When present, a list of tasks that have already been executed. The runner injects this via the **`{completed_task_list}`** placeholder. Format: **task name** (from the task’s Name field) plus **Result summary** (the task’s raw summary text; no **Output** line). Reference links (file paths, task output anchors, URLs) live **inside** the summary content, not as a separate section. The refiner uses this to fill in References only when relevant; for tool calls, include prior task/output in References only when very relevant.

When a previous refinement attempt had issues (e.g. invalid tool, malformed output), the refiner also receives **Issues with the current call** and the **current task data** so it can correct and re-output.

### What the refiner produces

1. **Refined task** — The same task fields (What is needed, Skill, References, Expected output) plus **Skill call**: the skill name and **all required and optional arguments with concrete values**. Those values come from "What is needed" and the task reference contents. This is what ties the coarse instruction to the actual inputs the skill will see (e.g. `topic = "async main loop Vala"` for research_online_search).
2. **Tool Calls** — Zero or more fenced blocks; each block is one JSON object with **name** (required) and **arguments** (optional object). One block per tool call. The runner executes each call, collects outputs, and passes them into the **Precursor** for the executor. Prefer **multiple** tool calls when that is more effective (e.g. several searches or codebase queries rather than one).

So: the **task creator** chooses *which* skill and *what* is needed at a high level; the **refiner** decides *exactly* what to pass to the skill and *which tools* to run first; the **executor** then receives What is needed, Skill definition, and Precursor (references + tool outputs) and produces Result summary + Detail. Refinement is what makes the design work — without it, the executor would get only coarse "What is needed" and references, with no concrete skill arguments or tool runs.

---

## Standard task input

After refinement, the runner runs the tool calls and then runs the executor for that task. Every executor task receives the same set of inputs when it runs. Skill definitions should describe only how *this* skill uses them; the full standard is below.

### What the executor receives

- **Name** (optional) — The task name, if set. Downstream tasks can refer to this task's output via `task://taskname.md` or `task://taskname.md#section` (slug = task name lowercased, non-alphanumeric → hyphen).
- **What is needed** — From the task list, in natural language. This is the main instruction for the task.
- **Skill definition** — The full content of this skill's markdown file. The executor uses it to guide interpretation and output.
- **Tool Output and/or Reference information** — Reference content (resolved References) and/or tool output (tool call(s) + result(s)). When the task had tool calls: tool output plus reference content. When the task has no tool calls, this section is from References only (once per reference or one combined run per skill header `execute-combined`). Each execution run is stored as a **Tool** (id, summary, document); the completed-task list uses Tool summary.
- Executor output: **Result summary** (required) and body sections with descriptive titles; list sections as links. No separate Output References section.

### Where What is needed and Expected output come from

The task list is created earlier (task creation / iteration). It has:

- **Goals / summary** — One short paragraph at list level: what we are trying to achieve with this task list.
- **Per task** — Each task has:
  - **What is needed** — Passed through to the executor as the main instruction when the task runs.
  - **Expected output** — What we expect from this task (for humans and for iteration; the skill’s output is compared to this).
  - **References** — Links to files, project description, or prior task results. Their resolved content is in **Precursor** when the task runs.

So: goals and expected output are set when the task list is created; the skill receives What is needed and Precursor at execution time.

---

## Executor output format

Every skill must produce output in this shape so the runner can parse it and show it in the task list.

### Required: Result summary

- **## Result summary** (required) — The content of this section is what appears in the task list under **##### Result summary** (raw; no **Output** line) as the task’s **Output**.
- It must be a **summary of what the task did** to address the goal and **whether that answered it** (one or two sentences). Use outcome-focused language (e.g. "Searched the codebase for X; found Y — enough for a follow-up."). Do not use a literal "Goal:" line or describe system mechanics.
- **Always list sections of the output as links** when describing what the task did (e.g. [Sources and findings](#sources-and-findings), [Issues that need rectifying](#issues-that-need-rectifying)). Use markdown links to each section heading — this is **very important**: it is the only visible information that later tasks can use to enhance their information; without section links, downstream tasks cannot discover what is in your output.
- If nothing relevant was found, say that clearly (e.g. "Nothing relevant found.").
- No long prose here; the detail goes in the next section.

### Body sections (descriptive titles only)

- **Never use generic section titles** (e.g. "Detail"). Use a **descriptive title** that states what the section contains (e.g. "Sources and findings", "Vala async: yield, main loop, and example of calling async methods", "Review findings: issues and proposed changes"). Be specific to the content — avoid generic titles like "Synthesis and sample code".
- The full breakdown is injected into the **Precursor** of any later task that references this task’s output.
- Structure: **heading + body** or **heading + subsections with links**.
- **Body sections can contain markdown links** and **short summaries about the references and why they are useful** (e.g. “The [Vala async docs](url) cover async/yield and main loop; [Runner.vala](path#OLLMcoder.Skill-Runner-task_creation_prompt) is where the prompt is built.”). Links can be URLs, file paths, or **AST references** for code — use the project AST path format (e.g. `#Namespace-Class-methodName`); see "Reference link types" below. Do not use plain symbol names like `#task_creation_prompt`. Downstream tasks receive the body and can have the refiner add those links to References so their content is injected too.
- End with a clear conclusion: e.g. "Enough information to proceed." or "More research needed: [what to search next]."

Optional sections (e.g. Output References, Skill output in fenced blocks) may be specified by the skill; the runner still requires a **Result summary** section and uses the body sections when resolving references.

### Two-step flows and secondary sections

Some skills are used in pairs: the first produces raw findings; the second consumes that output and produces a synthesized result.

- **research_online_search** → **research_web_page**: research_online_search does web searches and outputs Result summary + Detail; research_web_page receives that as Precursor and produces a concise summary (and optionally sample usage).
- **analyze_codebase** → **analyze_code**: analyze_codebase searches the codebase (codebase_search with code element_type) and outputs **Result summary** plus **## Analyze codebase results** — code locations with AST/file links. analyze_code receives that as Precursor and produces **Result summary + Detail** with how to use the code and example usage (code snippets).
- **analyze_docsbase** → **analyze_docs**: analyze_docsbase searches **documentation** (codebase_search with element_type "document" or "section", optionally category). Outputs **Result summary** plus **## Analyze docsbase results** — doc/section locations with file and GFM heading links. analyze_docs receives that as Precursor and produces **Result summary + Detail** that synthesizes the docs: key points, how to apply them, and example procedures from the documentation.

### Planning and implementation

- **plan_create**: creates a new plan (write only; write_file). Use when starting implementation planning. Plan content comes from Precursor (References).
- **plan_iterate**: produces revised plan content (no tools). Plan comes via References; output is the revised content in Detail for **plan_apply_changes** to write. Use when the plan needs changes after review or new information.
- **plan_apply_changes**: writes the plan file (write_file only). Content to write comes from Precursor (e.g. plan_iterate or revised content). Use after plan_iterate to persist the plan.
- **plan_review**: reviews a plan against **coding standards** and API usage (no tools; plan and standards via References). Output: issues and proposed changes. Use before or alongside implement_code.
- **analyze_code_standards**: locates project coding standards and style guides (e.g. .cursor/rules, CODING_STANDARDS); outputs **Code standards references** (links). Use so plan_review and implement_code can reference standards. No follow-up skill required; the references are added to task References.
- **implement_code**: writes or modifies code from a plan. **Multiple implement_code tasks** should be created for all implementation steps (e.g. one per step or per file). The **task iterator** typically adds these after the user has reviewed and approved the plan(s).

---

## Skill file format

Each skill file is split by the **double-dash separator** (`---`) into **three parts**. Use a separator between each part:

1. **Front matter** (YAML header) — then `---`
2. **Refinement** — body section under `## Refinement` — then `---`
3. **Execution** — body section under `## Execution`

The runner uses the Refinement section when refining the task and the Execution section when running the skill.

### Writing rules (stage-focused content)

**Refinement section:** Write only what the **refiner** needs to do its job. Include: which tool(s) to call, what arguments to pass, and what to expect back from the tools. Do **not** describe how the execution stage works, what execution will do with the output, or how downstream tasks use results. Do not describe the system; give instructions.

**Execution section:** Write only what the **executor** needs to do its job. Include: what to do with Precursor (tool outputs and references), what output sections to produce (e.g. Result summary, skill-specific sections), and optionally an example. Do **not** describe the refinement stage, the runner, or downstream tasks (e.g. "plan_review will add these to References"). Do not describe the system; give instructions.

### Location and naming

- Path: `resources/skills/`.
- Filename: **lowercase with underscores** (e.g. `research_online_search.md`, `plan_create.md`). No UpperCamel or kebab-case in filenames.

### Part 1: Front matter (YAML header)

Required keys:

- **name** — Skill name, lowercase with underscores (e.g. `research_online_search`). Must match the runner’s catalog.
- **description** — **When to use** this skill — that is its only job. One line, shown in the task list and skill catalog; the task creator uses it to choose the right skill per task. Include when the planner should choose it and hints about when not to use it (e.g. do not use before research is done; ensure prerequisites have been run). Do not describe what the skill outputs or how it works; that belongs in the Refinement and Execution sections.

Optional:

- **tools** — Comma-separated list of tool names this skill uses (e.g. `web_search` or `read_file`, `grep` — use the exact name from the wrapped-tool @name). Omit if the skill uses no tools.

**Principles:** (A) **Do not use read_file** — put content the skill needs in **References** so the runner injects it into Precursor. (B) **Each skill does one job** — e.g. produce revised content (plan_iterate) vs write the file (plan_apply_changes); do not combine read-then-write in one skill.

**Separator:** Use exactly `---` (double dash) on its own line after the front matter and again between the Refinement and Execution sections. So the file reads: front matter, `---`, `## Refinement` and its content, `---`, `## Execution` and its content. Do not duplicate the execution system template (task_execution.md); it already defines standard inputs and the Result summary / Detail shape. Skills add only what is **specific** to this skill. Do **not** reference docs/skills-format.md or any other doc path in skill files; the LLM does not have access to them.

### Part 2: Refinement

Under **## Refinement**, write only what the refiner needs: which tool calls to emit and with what arguments (or "No tool calls" and what to put in References); what information to **put in** (e.g. query phrasing, element_type, paths); what to **expect out** of the tools so the refiner can judge whether more calls are needed. If the skill uses multiple tool calls, state whether execution runs once on all outputs (combined) or once per tool result. Do not describe execution behaviour or downstream use of the output.

### Part 3: Execution (heading in skill file: `## Execution`)

Under **## Execution**, write only what the executor needs: how to build Result summary, Detail, and any skill-specific sections from Precursor; what output sections this skill produces (beyond the standard); optionally an example. Do not describe refinement, the runner, or how other tasks use the output. Use heading + body or heading + sections with links consistently.

---

## Reference link types (for output)

When skill output refers to other content, use only these link forms so the runner can resolve them.

**AST path format (for code):** The anchor for code symbols is **not** a plain name like `#task_creation_prompt`. It is the project’s AST path: **hyphen-separated**, with namespace parts using `.`. Example: `#Namespace-Class-methodName` or `#Namespace.SubNamespace-Class-Method`. So a link to a method is `[Title](/absolute/path/to/file.vala#OLLMcoder.Skill-Runner-task_creation_prompt)`. See the codebase (e.g. docs/plans/done/2.1.2, or codebase search AST path output) for the exact format your project uses.

- **File:** `[Title](/absolute/path/to/file)` — base name for title, absolute path.
- **File section / AST reference:** `[Title](/absolute/path/to/file#anchor)` — anchor can be a **GFM heading** (e.g. `#section-name`) or an **AST path** for code. **AST paths do not use plain symbol names**; they use the project’s AST path format: hyphen-separated, with namespace parts optionally using `.`. Example: `#Namespace-Class-methodName` or `#Namespace.SubNamespace-Class-Method`. So for code use e.g. `[task_creation_prompt](/path/to/Runner.vala#OLLMcoder.Skill-Runner-task_creation_prompt)`, not `#task_creation_prompt`. The runner resolves the AST path to inject that symbol.
- **Task output:** `[Task Name Results](task://taskname.md)` or `[Task Name Results](task://taskname.md#section)` — slug = task name lowercased, non-alphanumeric → hyphen.
- **URL:** `[Title](https://…)`

Do not paste long file or precursor content into the task list or into output; use links. The runner injects resolved content when a task runs.
