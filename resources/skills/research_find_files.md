---
name: research_find_files
description: Use when you need to list directories, find files by name or glob, or search file contents for exact text (shell-style find/ls/grep). Prefer analyze_codebase for semantic “where is this implemented?” code search instead of this skill.
tools: run_command
---

**During refinement**

**Purpose of this skill:** Run shell commands that **list** paths or **search** filenames and file contents. The executor only **interprets** command output — refinement must emit **## Tool Calls** with one or more **`run_command`** invocations so those commands run first.

**What is needed** should state what to locate (e.g. “all `*.vala` under `liboccoder/`”, “files whose name contains `Runner`”, “lines containing `exec_extract` in `ResultParser.vala`”). Turn that into concrete **`run_command`** calls — in-repo, prefer **`git ls-files`** / **`git grep`**; outside the project or without git, use **`find`** / plain **`grep`**.

### Do's

- **Emit `## Tool Calls`** — one or more fenced JSON **`run_command`** blocks; that is the main refinement output for this skill.
- **Keep scope narrow** — in a repo, use a **path prefix** on **`git ls-files`** or **`git grep`** (after **`--`**) or a tight pathspec; outside git or the project, use **`find`** with **`-maxdepth`**, **`-name`**, etc., instead of scanning everything in one shot.
- **Cap noisy output** — pipe to `head -n 80` (or similar) when breadth is unknown so results stay usable.
- **Use `working_dir`** when the whole run should start in one directory — especially an **absolute path** outside the project (read-only lookup is fine); you can also use absolute paths inside **`command`**.
- **Split work across multiple tool calls** when it helps (e.g. one **`git ls-files`** / **`git grep`** pass for file paths, one for content) instead of one enormous pipeline — unless one command is clearly enough.
- **Prefer `git ls-files --exclude-standard` (often `| grep …`) to list project files** — enumerates tracked paths from the repo root, honors standard ignore rules, and avoids walking **`.git`** and junk trees; filter with **`grep`** on the path string (substring or regex), or pass a **directory prefix** / pathspec to **`git ls-files`** to narrow first. Use **`find`** (or **`fd`**) when **`working_dir`** is **outside** the repo, the tree is **not** a git checkout, or you need **mtime** / filesystem-only queries **`git ls-files`** does not cover.
- **Prefer `git grep` for text search inside a git work tree** — same benefits as above; scope with a path after **`--`** (see examples). Use plain **`grep -r`** when you are **not** in a git repo, **`working_dir`** is outside the project, you need ignored/build-only paths, or **untracked-only** content (then consider **`git grep --untracked`** or **`git grep --no-index`** as appropriate).
- **If you use plain `grep`, keep it scoped** — subdirectory, **`--include`**, or **`--exclude-dir`** (e.g. skip **`node_modules`**) so you do not recurse blindly from the repo root.

### Don'ts

- **Do not fill in References** — leave **References** as **—** or **(none)**; put intent only in **What is needed** and in **`run_command`** arguments.
- **Do not set `network`** or **`allow_write`** on **`run_command`** — this skill is read-only research; those flags are unnecessary and **trigger extra user permission** prompts.
- **Do not run huge unbounded searches** when a smaller directory or pattern would answer **What is needed** — avoid blasting **`node_modules`**, **`.git`**, and build output; prefer scoped **`git grep`** (or restrict paths and use **`grep`** with **`--exclude-dir`**, or search only under **`src/`**, etc.) instead of unscoped **`grep -r`** from the repo root.

### Tool: run_command (options worth using)

- **command** (required): a single shell command string (run via `/bin/sh -c`).
- **working_dir** (optional): directory used as the **current working directory** for this run.
  - **Omitted or empty:** cwd is the **project root** when a project is open, otherwise the user’s **home** directory — **not** arbitrary paths outside the project unless you set **working_dir** or use absolute paths in **command**.
  - **Absolute path:** use this to run **inside** any directory (including **outside the repo**), e.g. `"/home/user/other-clone"` — then use **`find`**, plain **`grep -r`**, **`ls`**, etc. on that tree (**`git ls-files`** / **`git grep`** apply to the **git** root when cwd is the project; for arbitrary directories outside the project, **`find`** / **`grep`** are the right tools).
  - **Relative (non-empty):** normalized **under `$HOME`**, not under the project (special case: the string **`playground`** maps to `$HOME/playground`).
  - Prefer **`working_dir`** + short **command** over embedding `cd /path && …` when the whole run should start in one folder; either style can work.
  - **Looking outside the project** is allowed: set **`working_dir`** to an absolute path outside the repo, or use absolute paths in **`command`** — that is normal read-only research and does **not** require **`network`** or **`allow_write`**.

### Command patterns (examples — adapt paths and patterns to **What is needed**)

**Finding project files (inside a git repo — prefer over `find`)**

- `git ls-files --exclude-standard | grep '\.vala$'` — tracked paths whose names end with **`.vala`** (adjust the **`grep`** pattern for partial names, case, etc.).
- `git ls-files --exclude-standard | grep -i 'runner'` — path contains **`runner`** (case-insensitive).
- `git ls-files --exclude-standard liboccoder/Task/` — only under **`liboccoder/Task/`**; combine with **`| grep '\.vala$'`** when you need extension filtering.
- `git ls-files --exclude-standard -- 'liboccoder/Task/*.vala'` — pathspec (shell may need quoting so glob is left to Git).
- **`git ls-files`** lists **tracked** files; for **untracked** names use **`git ls-files -o --exclude-standard`** (optional **`--exclude-standard`** still drops ignored noise) or fall back to **`find`** for a non-git directory.

**Finding files outside the project or without git (`find` / `fd`)**

- `find . -maxdepth 3 -name "*.vala"` — by extension, limited depth.
- `find . -name "*UserHandler*"` — partial filename.
- `find . -mtime -1` — recently modified (**`git ls-files`** has no mtime; use this when you need it).
- If **`fd`** is available: `fd -e vala . liboccoder` — often shorter than **`find`**.

**Listing directories**

- `ls -la` — current dir; `ls -la liboccoder/Task/` — specific path.

**Searching file contents (prefer `git grep` in a repo)**

- `git grep -nI "pattern" -- liboccoder/` — line numbers, skip binary-like files; limit to **`liboccoder/`** (path after **`--`**).
- `git grep -nIi "pattern" -- liboccoder/` — same, case-insensitive (drop **`i`** when case matters).
- `git grep -nI "pattern" -- '*.vala'` — limit by pathspec (all **`*.vala`** from repo root); add a directory: **`-- 'liboccoder/**/*.vala'`** if you need a subtree glob.
- `git grep -nI "pattern" -- lib/foo.vala` — single file.
- `git grep -nI --untracked "pattern" -- src/` — include **untracked** files in addition to tracked (still respects ignore rules unless you add **`--no-exclude-standard`**).
- **Fallback: plain `grep`** — `grep -rIin --include="*.vala" "pattern" liboccoder/` when not using git, or searching paths git ignores; still scope the path and use **`--exclude-dir`** as needed.

### Example refinement output (research_find_files)

For this skill, leave **References** as **—**; use **## Tool Calls** only. Example:

## Task

- **What is needed** List Vala files under liboccoder/Task and show where `exec_extract` appears.
- **Skill** research_find_files
- **References** —
- **Expected output** Short result summary naming matching files and how they relate to the question.

## Tool Calls

```json
{ "name": "run_command", "arguments": { "command": "git ls-files --exclude-standard liboccoder/Task/ | grep '\\.vala$' 2>/dev/null | head -100" } }
```

```json
{ "name": "run_command", "arguments": { "command": "git grep -nI \"exec_extract\" -- liboccoder/Task/ 2>/dev/null | head -80" } }
```

Narrow by extension when needed: **`git grep -nI \"pattern\" -- '*.vala'`** or **`git grep -nI \"pattern\" -- 'liboccoder/Task/**/*.vala'`** (quote pathspecs so the shell does not expand them early).

Do **not** add file paths or URLs under **References** unless a different instruction requires them — for **research_find_files**, keep **References** as **—**.

---

**At execution**

You receive **run_command** output (and any **References** if present) in **Tool Output and/or Reference information**. You **do not** run tools; you **summarize** what the commands showed.

### Do's

- **Write `## Result summary`** — required; it is what **`task://…`** / later refinement usually sees from this task, so put **useful** paths, conclusions, and gaps there; stay **tight** (no essays).
- **Answer What is needed** — say what matched (files, lines, or “nothing found”) and how it relates to the question.
- **Use correct file links** — **project-relative** paths (**no** leading `/`, e.g. `liboccoder/Foo.vala`) or a **real** filesystem absolute path; normalize paths using **project root** / workspace from the precursor when command output is cwd-relative or abbreviated.
- **Say when commands failed or were empty** — note errors, missing files, or insufficient output so follow-up work is not misled.

### Don'ts

- **Do not run tools** — do not emit **`run_command`** or ask for more shell runs here; you only interpret output already in **Tool Output and/or Reference information**.
- **Do not paste long logs** — summarize hits and use **markdown links** instead of dumping command output.
- **Do not** use a leading **`/`** on a project path unless it is a **full** OS absolute path. **`/`** is filesystem root, not project root — **`/.cursor/...`**, **`/liboccoder/...`** are **wrong** for repo files (they resolve to **`/.cursor`**, **`/liboccoder`** on disk). Use **`.cursor/...`**, **`liboccoder/...`** with **no** leading slash.
- **Do not** add extra **`##`** sections or fenced deliverables unless **What is needed** explicitly asks — default is **`## Result summary`** only.
- **Do not** pad with process narration or background that does not serve **What is needed**.

**## Result summary** (required) — **one short paragraph** (two at most if there are distinct groups of hits). State:

- **What matched** **What is needed** — file paths and, for grep-style output, that the listed lines/snippets address the question.
- **File links in this summary** — follow the same path rules as task reference links: **do not** start a project path with **`/`** unless it is a **full filesystem path** from the OS root (e.g. **`/home/user/project/lib/Foo.vala`**). **`/.cursor/...`**, **`/lib/...`** without a real home prefix are **wrong** — use **`.cursor/...`**, **`lib/...`** project-relative. Tool output often shows paths **relative to the command’s working directory** or abbreviated; combine that with **Project** / **workspace** / **project root** from the precursor so links are unambiguous — normalize to project-relative from the root you were given, not a fake absolute under **`/`**.
- Use **markdown file links** `[label](path/to/file)` (project-relative) or `[label](/full/filesystem/path/to/file)` when you truly have an absolute path; add `#anchor` only when the output gives a stable line or you can point to a known section. Do **not** paste long command logs — summarize and link.
- If commands failed, errored, or returned nothing useful, say so and what is missing.
- If results are partial or **What is needed** is not fully addressed, say so clearly in **## Result summary** (what is missing, what further search would help).
