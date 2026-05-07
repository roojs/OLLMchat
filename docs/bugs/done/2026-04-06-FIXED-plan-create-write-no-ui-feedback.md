# Skill runner: `plan_create` / write-executor — no success or error indicator after `write_file`

**Status: FIXED**

## Problem

- **Symptom:** After a **`plan_create`** task runs, the executor output can include a valid **`## Change details`** block (with **`file_path`**, **`complete_file`**, **`output_mode` `next_section`**, and a full plan body). The user has **no clear chat/history signal** that:
  - the **`write_file`** tool actually ran,
  - the file was written successfully, or
  - the write failed (permission denied, path error, user declined approval, etc.).
- **Contrast:** Skills that use **`run_command`** show a collapsed **`Execution results`** frame (`text.oc-frame-success` or `text.oc-frame-danger`) so the user can see stdout or failure at a glance.
- **Source session (local history):** `~/.local/share/ollmchat/history/2026/04/06/11-28-38.json`
- **Agent:** `skill-runner` (`qwen3.5:35b`).

## What the session shows

1. **Refinement** for task **“Plan Unified Task List File Structure”** (`plan_create`) completes; UI shows the usual “Refining …” collapsed header.
2. **UI:** `Running Tools for Task Plan Unified Task List File Structure — Tool call 1`  
   - This label is used for **every** execution run (`Details.run_exec` → first index is always “Tool call 1”), even when there is **no** JSON tool call before the executor — so it reads like a tool already ran when it may only be the executor pass.
3. **Executor** (`content-stream`, message index ~286) produces a full **`## Result summary`**, **`## Change details`** targeting **`docs/plans/task-list-consolidation.md`**, and a long **`next_section`** plan starting with `# Task list consolidation plan`.
4. **No** separate **`Execution results`** (or equivalent) frame for **`write_file`** appears after that stream completes.
5. **Later:** Refinement for **`plan_code`** fails validation: **`docs/plans/task-list-consolidation.md` does not exist** (and anchor issues). The user can infer the plan file was never persisted, but nothing in the **`plan_create`** step had already **surfaced** write failure or success — only the model’s prose in **`## Result summary`** claims the plan was “drafted”.

So the user’s observation is accurate: **the log does not tie the executor’s claimed write to an observable tool outcome.**

## Code trace (why there is no indicator)

- **Post-executor writes:** `liboccoder/Task/Tool.vala` — after `ResultParser.exec_extract` succeeds and **`WriteChange.validate`** passes, the runner calls **`yield w.exec(this)`** for each parsed write (`WriteChange.exec`).
- **`WriteChange.exec`** (`liboccoder/Task/WriteChange.vala`) calls **`write_file`** via **`impl.execute(...)`** and assigns the returned string to **`run.tool_run_result`**.
- **Nothing in this path** adds a **`ui`** message with that result (compare **`liboctools/RunCommand/Request.vala`**, which **does** `add_message` with **`Execution results`**).
- After the **`foreach`**, **`Tool.run`** rebuilds the document from the **Result summary** only when the skill lists **`write_file`**; it does **not** append **`tool_run_result`** to the session for the user.
- **Failure handling:** There is **no** check after **`w.exec`** that **`tool_run_result`** starts with **`ERROR:`** (documented return shape from **`BaseTool.execute`**). A failed write could still leave the executor response looking “successful” in the chat.

## Conclusions

- **Primary issue:** **Observability** — **`write_file`** results from the write-executor path are **not** surfaced in the chat/history the way **`run_command`** results are.
- **Secondary issue:** **Correctness / safety** — if **`write_file`** returns an error string after validation, the runner should **surface** it and **abort execution** (**fatal**); **do not** retry the LLM for that (treat as bug / invariant break).
- **UX nit:** The string **`Running Tools for Task … — Tool call N`** is wrong for examination runs and for lone executor runs; use **Examining `{path}` (i of n)** vs **Executing task: … (i of n)** per **`build_exec_runs`** (see §1).

## Proposed fix (per `docs/bug-fix-process.md` — **implemented** 2026-04-06)

Original workflow: **debug → understand → propose → approval → apply**. Scope was **only** observability and correctness for write-executor **`write_file`** runs; no unrelated refactors.

### Planning alignment (workspace rules)

- **Implement only what is approved** here (or a later explicit tweak). Do not expand scope (extra refactors, unrelated **`Tool`** / **`Details`** cleanups, or prompt/skill edits) without a separate OK.
- If **`ERROR:`** handling collides with replay, multi-write ordering, or post-exec synthesis, **document the blocker in this bug file**, **revert** speculative code, and **stop for approval** — same spirit as **`docs/guide-to-writing-plans.md`** (**Plan implementation workflow**) when a design gap appears.
- **No surprise fixes:** no defensive checks that only hide failures; surface **`write_file`** errors and **abort** per §4 (**no** LLM retry on write failure).

### Root cause (what we fix)

- **Wrong label:** **`Details.run_exec`** always prepends **“Running Tools for Task … — Tool call N”** before **`ex.run()`**, even when no refinement JSON tool runs first — it reads like a generic “tools” step, not “executor then optional disk write”.
- **Missing signal:** **`WriteChange.exec`** stores **`write_file`** output in **`tool_run_result`** but never **`add_message`**’s it; **`run_command`** does (**`Execution results`**).
- **Missing failure path:** **`ERROR:`** returns from **`write_file`** are not surfaced as **fatal** (stop + fix bug); the run can look successful, or only the LLM retry path applies — wrong for post-validation disk I/O.

### 1. Replace the misleading **`run_exec`** banner (never “Running tools”)

**File:** `liboccoder/Task/Details.vala` — **`run_exec()`** (the **`add_message`** before **`yield ex.run()`**).

**Context:** **`build_exec_runs()`** builds **`exec_runs`** in three cases: (1) **examination references** — one **`Tool`** per **`exam_reference`**; (2) **refinement JSON tools** — one **`Tool`** per scheduled tool call; (3) **else** a single **`exec`** run. The old string **“Running Tools for Task … — Tool call N”** is wrong for (1) and (3) (nothing necessarily “ran” yet).

- **Banner text:** **`ex.exam_reference != null`** → **“Examining ”** + **`Format.path`**; else **“Executing task: ”** + **`task_name`**. Always append a run counter in parentheses: **` (i of n)`** using 1-based **`i`** and **`exec_runs.size`** as **`n`** (e.g. **`(1 of 1)`** for a single run — no **`if`** on **`n`**, no word **“step”**).
- **Never** use the phrase **“Running tools”** in this banner.
- **Why not “Writing to File …” here?** The target path exists only **after** **`ResultParser.exec_extract`** fills **`WriteChange.file_path`**. The explicit **Writing to File** line is **§2**, immediately before **`write_file`**.

### 2. **“Writing to File `{path}`”** immediately before each disk write

**File:** `liboccoder/Task/Tool.vala` — inside **`run()`**, after **`exec_extract`** / validation succeed and **before** **`yield w.exec (this)`** for each **`WriteChange`**.

- **`add_message`** a short **`ui`** line: **“Writing to File `{file_path}`”** using **`w.file_path`** (same string sent to **`write_file`**).
- This is the user-visible **writing-to-file** moment the session lacked; it must live **here** (path known), not in **`run_exec`**.

### 3. Surface **`write_file`** outcome (match **`run_command`**)

**File:** `liboccoder/Task/Tool.vala` — **after** each **`yield w.exec (this)`** (or inside **`WriteChange.exec`** if we prefer one responsibility — prefer **`Tool.run`** so all **`add_message`** stays in one place).

- **`add_message`** a fenced block mirroring **`liboctools/RunCommand/Request.vala`**: **`text.oc-frame-success.collapsed Execution results`** on success, **`text.oc-frame-danger.collapsed Execution results`** (or **“Write failed”**) when the return indicates failure.
- Body: the same string returned by **`write_file`** (trimmed), consistent with command stdout/stderr visibility.

### 4. Treat **`ERROR:`** from **`write_file`** as **fatal** (no retry; stop execution)

**File:** `liboccoder/Task/Tool.vala` — after each **`yield w.exec(this)`** when the return indicates failure.

**Policy (approved intent):**

- **`WriteChange.validate`** and the executor contract are supposed to ensure the write can succeed. A failed **`write_file`** after that (**`ERROR:`** prefix from **`BaseTool.execute`**) is **not** something to “fix” by re-asking the LLM — it indicates an **internal bug**, **environment fault**, or **broken invariant**.
- **Do not** **`continue`** the executor **for**/**try_count** loop on write failure (no retry of the model for this reason).
- **Do:** show the danger **`Execution results`** frame (§3), append to **`this.parent.issues`**, then **`throw`** an error (e.g. **`GLib.IOError.FAILED`**) so **task execution stops** and the failure propagates to the runner — same severity as “we must fix the bug before continuing”.

This is **not** a defensive null-guard; it **surfaces** a failure that must not be masked.

### Concrete code (proposed) — explicit patches

Planning guidelines: proposed changes are spelled out as **concrete code blocks** (implementer copies/adjusts; not pseudocode).

---

#### A. `liboccoder/Task/Details.vala` — `run_exec()`

**Current:**

```vala
var task_name = this.task_data.get("name").to_markdown().strip();
for (var i = 0; i < this.exec_runs.size; i++) {
	var ex = this.exec_runs.get(i);
	this.add_message(new OLLMchat.Message("ui",
		"Running Tools for Task " + task_name + " — Tool call " +
		(i + 1).to_string()));
	yield ex.run();
}
```

**Proposed:**

```vala
var task_name = this.task_data.get("name").to_markdown().strip();
for (var i = 0; i < this.exec_runs.size; i++) {
	var ex = this.exec_runs.get(i);
	this.add_message(new OLLMchat.Message("ui",
		(ex.exam_reference != null
			? "Examining " + ex.exam_reference.path
			: "Executing task: " + task_name)
		+ " (" + (i + 1).to_string() + " of " + this.exec_runs.size.to_string() + ")"));
	yield ex.run();
}
```

---

#### B. `liboccoder/Task/Tool.vala` — replace the **`foreach (var w in this.writes)`** body that only calls **`yield w.exec`**

**Current:**

```vala
foreach (var w in this.writes) {
	yield w.exec (this);
}
```

**Proposed** (banner per write + **`Execution results`**; **`ERROR:`** → **fatal**, no executor retry):

```vala
foreach (var w in this.writes) {
	this.add_message(new OLLMchat.Message("ui",
		"Writing to File `" + w.file_path + "`"));
	yield w.exec(this);
	if (this.tool_run_result.has_prefix("ERROR:")) {
		this.add_message(new OLLMchat.Message("ui",
			OLLMchat.Message.fenced("text.oc-frame-danger.collapsed Execution results",
				this.tool_run_result)));
		this.parent.issues += "\nwrite_file failed: " + this.tool_run_result;
		throw new GLib.IOError.FAILED("write_file failed: " + this.tool_run_result);
	}
	this.add_message(new OLLMchat.Message("ui",
		OLLMchat.Message.fenced("text.oc-frame-success.collapsed Execution results",
			this.tool_run_result)));
}
```

**Rationale:** Do **not** **`continue`** the **`try_count`** loop — a write failure after validation is not recoverable by re-prompting the model; **stop execution** so the bug can be fixed.

**Then** (existing code — still runs only when all writes succeeded; do not drop):

```vala
if (this.parent.skill.tools.contains ("write_file")) {
	var summary_only = new Markdown.Document.Render ();
	summary_only.parse (this.summary.to_markdown_with_content ());
	this.document = summary_only.document;
}
return;
```

**Notes for implementation:**

- Verify **callers** of **`Tool.run()`** propagate **`GLib.Error`** from a thrown **`IOError.FAILED`** ( **`run_exec`** / runner) so the session stops cleanly with a visible error path.
- If **`writes`** is empty (skill has **`write_file`** but model omitted **`Change details`**), this block is skipped — unchanged from today.
- **Replay:** if **`in_replay`** records write outcomes, align with **`throw`** behavior (document in **Attempts / changelog** when implementing).

---

#### C. Reference pattern — `liboctools/RunCommand/Request.vala` (no edit; match style)

Success path (truncated):

```vala
this.agent.add_message(new OLLMchat.Message("ui",
	OLLMchat.Message.fenced("text.oc-frame-success.collapsed Execution results", output)));
```

Failure path uses **`text.oc-frame-danger.collapsed Execution results (Command Failed)`** when the subprocess exit status is non-zero — **`write_file`** should use the same **success vs danger** split based on **`ERROR:`** prefix (§4), not exit codes.

### 5. Tests / verification (after implementation)

- Manual: run a **`plan_create`** task that emits **`Change details`**; confirm order: banner **… (1 of 1)** (or **Examining `path` (1 of n)** / **Executing task: … (i of n)**) → executor stream → **Writing to File `…`** → **Execution results** for the **`write_file`** return.
- Manual: force a failing **`write_file`** (read-only path if available); confirm danger frame, **issues** populated, and execution **stops** (**no** LLM retry for that failure).
- Optional: unit or integration hook if the project already tests **`Tool.run`** / **`WriteChange`** (only if already in scope).

### Out of scope (unless separately approved)

- Changing skill prompts or **`plan_create.md`** text.
- Broader rename of every **“Tool call”** string outside **`Details.run_exec`**.
- Papering over failed writes without surfacing **`ERROR:`** to the user.

### Approval gate

**Applied 2026-04-06** — fix was approved in chat; implementation matches **Proposed fix** / **Concrete code** sections above.

## Attempts / changelog

- **2026-04-06** — Bug filed; **Proposed fix** expanded (UI copy, **`Execution results`**, **`ERROR:`** handling, planning alignment, approval gate). **Concrete code blocks** added for **`Details.run_exec`** and **`Tool.run`** write loop. Implementation not started.
- **2026-04-06** — **Banner:** exam branch → **Examining** + **`path`** only; no **“Running tools”**; **`run_exec`** proposal: exam vs task **?:** + always **` (i of n)`** (e.g. **`(1 of 1)`**), no **“step”**, no **`if`** on **`n`**. **Write failure:** fatal **`throw`**, **no** executor retry (policy: invariant violation / bug path).
- **2026-04-06** — **Implemented:** `liboccoder/Task/Details.vala` — **`run_exec`** UI strings as above. `liboccoder/Task/Tool.vala` — before each **`write_file`**, **`Writing to File \`path\``**; after each write, fenced **`Execution results`**; on **`ERROR:`** prefix, append **`parent.issues`**, **`throw new GLib.IOError.FAILED`**. **`meson compile -C build`** succeeds.

## After the fix

- **`Details.run_exec`:** No **“Running Tools … Tool call”**; exam runs show **Examining `{path}` (i of n)**; others **Executing task: {name} (i of n)**.
- **`Tool.run`:** Each write shows tool output in chat; **`write_file`** failure aborts the task (**`run_exec`** / **`run_child`** propagate **`GLib.Error`**).

## Open questions

- Confirm on disk whether the session’s plan path was ever created (workspace / permissions / approval gate). The repo today has **no** `docs/plans/task-list-consolidation.md` in this checkout; whether that is failed write vs never committed is **orthogonal** to missing UI — the user still could not see tool output at execution time.

## References

- Skill: `resources/skills/plan_create.md` — **`tools: write_file`**, **`## Change details`** / **`next_section`** contract.
- `liboccoder/Task/Tool.vala` — executor loop; **`write_file`** UI (**`Writing to File`**, **`Execution results`**, fatal on **`ERROR:`**).
- `liboccoder/Task/WriteChange.vala` — **`exec`** → **`write_file`**.
- `liboctools/RunCommand/Request.vala` — pattern for **`Execution results`** user-visible frames.
