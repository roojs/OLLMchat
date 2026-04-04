---
name: research_find_files
description: Use when you need to list directories, find files by name or glob, or search for plain-text keywords in files (find/grep/ls style). Prefer analyze_codebase for semantic “where is this implemented?” code search; use this skill for path listing, filename patterns, and simple content matches.
tools: run_command
---

**During refinement**

**Purpose of this skill:** Run shell commands that **list** paths or **search** filenames and file contents. The executor only **interprets** command output — refinement must emit **## Tool Calls** with one or more **`run_command`** invocations so those commands run first.

**What is needed** should state what to locate (e.g. “all `*.vala` under `liboccoder/`”, “files whose name contains `Runner`”, “lines containing `exec_extract` in `ResultParser.vala`”). Turn that into concrete **`run_command`** calls.

### Do's

- **Emit `## Tool Calls`** — one or more fenced JSON **`run_command`** blocks; that is the main refinement output for this skill.
- **Keep scope narrow** — prefer a subdirectory, `-maxdepth`, `--include` / `-name`, or a specific path over searching the whole repo in one shot.
- **Cap noisy output** — pipe to `head -n 80` (or similar) when breadth is unknown so results stay usable.
- **Use `working_dir`** when the whole run should start in one directory — especially an **absolute path** outside the project (read-only lookup is fine); you can also use absolute paths inside **`command`**.
- **Split work across multiple tool calls** when it helps (e.g. one **`find`** for filenames, one **`grep`** for content) instead of one enormous pipeline — unless one command is clearly enough.
- **Use scoped `grep`** — give a subdirectory or `--include` / `--exclude-dir` (e.g. skip **`node_modules`**) so you do not recurse blindly from the repo root.

### Don'ts

- **Do not fill in References** — leave **References** as **—** or **(none)**; put intent only in **What is needed** and in **`run_command`** arguments.
- **Do not set `network`** or **`allow_write`** on **`run_command`** — this skill is read-only research; those flags are unnecessary and **trigger extra user permission** prompts.
- **Do not run huge unbounded searches** when a smaller directory or pattern would answer **What is needed** — avoid blasting **`node_modules`**, **`.git`**, and build output; restrict paths and use **`grep`** with **`--exclude-dir`** (or search only under **`src/`**, etc.) instead of unscoped **`grep -r`** from the repo root.

### Tool: run_command (options worth using)

- **command** (required): a single shell command string (run via `/bin/sh -c`).
- **working_dir** (optional): directory used as the **current working directory** for this run.
  - **Omitted or empty:** cwd is the **project root** when a project is open, otherwise the user’s **home** directory — **not** arbitrary paths outside the project unless you set **working_dir** or use absolute paths in **command**.
  - **Absolute path:** use this to run **inside** any directory (including **outside the repo**), e.g. `"/home/user/other-clone"` — then use relative paths in **command** (`find . …`, `grep -r … .`) from that root.
  - **Relative (non-empty):** normalized **under `$HOME`**, not under the project (special case: the string **`playground`** maps to `$HOME/playground`).
  - Prefer **`working_dir`** + short **command** over embedding `cd /path && …` when the whole run should start in one folder; either style can work.
  - **Looking outside the project** is allowed: set **`working_dir`** to an absolute path outside the repo, or use absolute paths in **`command`** — that is normal read-only research and does **not** require **`network`** or **`allow_write`**.

### Command patterns (examples — adapt paths and patterns to **What is needed**)

**Finding files (name / tree)**

- `find . -maxdepth 3 -name "*.vala"` — files by extension, limited depth.
- `find . -name "*UserHandler*"` — partial filename.
- `find . -mtime -1` — recently modified (adjust as needed).
- If **`fd`** is available: `fd -e vala . liboccoder` — often shorter than **find**.

**Listing directories**

- `ls -la` — current dir; `ls -la liboccoder/Task/` — specific path.

**Searching file contents**

- `grep -rIin "pattern" liboccoder/` — recursive, line numbers, binary-ignore, case-insensitive (drop **i** when case matters).
- `grep -rIin --include="*.vala" "pattern" .` — limit by extension.
- `grep -rIin --exclude-dir=node_modules --exclude-dir=.git "pattern" liboccoder/` — recurse but skip heavy dirs (add more **`--exclude-dir`** as needed).

### Example refinement output (research_find_files)

For this skill, leave **References** as **—**; use **## Tool Calls** only. Example:

## Task

- **What is needed** List Vala files under liboccoder/Task and show where `exec_extract` appears.
- **Skill** research_find_files
- **References** —
- **Expected output** Short result summary naming matching files and how they relate to the question.

## Tool Calls

```json
{ "name": "run_command", "arguments": { "command": "find liboccoder/Task -maxdepth 2 -name \"*.vala\" 2>/dev/null | head -100" } }
```

```json
{ "name": "run_command", "arguments": { "command": "grep -rIn \"exec_extract\" liboccoder/Task --include=\"*.vala\" 2>/dev/null | head -80" } }
```

Do **not** add file paths or URLs under **References** unless a different instruction requires them — for **research_find_files**, keep **References** as **—**.

---

**At execution**

You receive **run_command** output (and any **References** if present) in **Tool Output and/or Reference information**. You **do not** run tools; you **summarize** what the commands showed.

### Do's

- **Write `## Result summary`** — required; it is what **`task://…`** / later refinement usually sees from this task, so put **useful** paths, conclusions, and gaps there; stay **tight** (no essays).
- **Answer What is needed** — say what matched (files, lines, or “nothing found”) and how it relates to the question.
- **Use correct file links** — **project-relative** paths (**no** leading `/`, e.g. `liboccoder/Foo.vala`) or a **real** filesystem absolute path; normalize paths using **project root** / workspace from the precursor when command output is cwd-relative or abbreviated.
- **Say when commands failed or were empty** — note errors, missing files, or insufficient output so follow-up work is not misled.
- **End with `no further tool calls needed`** on its own **last** line when this run’s output **fully** answers **What is needed** with no guesswork; **omit** that line when results are partial or more search is clearly needed (see execution prompt rules).

### Don'ts

- **Do not run tools** — do not emit **`run_command`** or ask for more shell runs here; you only interpret output already in **Tool Output and/or Reference information**.
- **Do not paste long logs** — summarize hits and use **markdown links** instead of dumping command output.
- **Do not** use a leading **`/`** on a project path unless it is a **full** OS path — **`/liboccoder/...`** resolves from the filesystem root, not the repo.
- **Do not** add extra **`##`** sections or fenced deliverables unless **What is needed** explicitly asks — default is **`## Result summary`** only.
- **Do not** pad with process narration or background that does not serve **What is needed**.

**## Result summary** (required) — **one short paragraph** (two at most if there are distinct groups of hits). State:

- **What matched** **What is needed** — file paths and, for grep-style output, that the listed lines/snippets address the question.
- **File links in this summary** — follow the same path rules as task reference links: **do not** start a project path with **`/`** unless it is a **full filesystem path** from the OS root (e.g. **`/home/user/project/lib/Foo.vala`**). **Do** use **project-relative** paths with **no** leading slash (e.g. **`liboccoder/Skill/Runner.vala`**). Tool output often shows paths **relative to the command’s working directory** or abbreviated; combine that with **Project** / **workspace** / **project root** from the precursor so links are unambiguous — normalize to project-relative from the root you were given, not a fake **`/lib/...`** that looks like the filesystem root.
- Use **markdown file links** `[label](path/to/file)` (project-relative) or `[label](/full/filesystem/path/to/file)` when you truly have an absolute path; add `#anchor` only when the output gives a stable line or you can point to a known section. Do **not** paste long command logs — summarize and link.
- If commands failed, errored, or returned nothing useful, say so and what is missing.
- If the output is **enough** to answer **What is needed** with no guesswork, end the full markdown with **`no further tool calls needed`** on its own **last** line (see execution prompt rules). If more searches would be needed, **omit** that line and note the gap in **## Result summary**.
