# 02. Pi-like agent

Status: ⏳ proposed

ℹ️ Checklist: `docs/guide-to-writing-plans.md` — Checklist for plans.  
ℹ️ Study: [01-pi-agent.md](01-pi-agent.md). Vala: `docs/coding-standards.md` via router when implementing.

## Purpose

- **🔷** New **liboccoder-weight** free-form coding agent: `ProjectManager`, project-required, coding prompts/UI — not a thin Chatter clone as the final product.
- **🔷** Agent id **`agent-pi`**; Vala namespace **`OLLMcoder.AgentPi`** (GIR: nested under liboccoder’s `OLLMcoder`); human title **`Agent Pi`**; `long_title` **`implementation of the Pi agent harness`**.
- **🔷** Reuse Chatter ideas for the **turn queue** later if Phase 5 reopens as Option A (summary + `session_fetch`). Chatter itself stays light.
- **✔️** Phase 5 **Option C**: no context hygiene for Agent Pi for now (no stand-in).
- **🔷** Pi good bits: `AGENTS.md` inject, Agent Skills–style soft skills, model-owned `toolsReply`.
- **🔷** Separate skill system (**`Skill`**) — **no** reuse of `OLLMcoder.Skill.Manager` / refine–execute skill files.
- **🔷** Keep permissions / approvals.
- **🔷** Open to renaming primary tools toward Pi names (`read` / `write` / …) with alias + reference updates.
- **🔷** If we **copy or derive** Pi agent prompts (or other Pi source), ship **licenses** + **SBOM** attribution (Pi is MIT).
- **⏳** Lock factory home, tool rename policy, then implement phases.

---

## Placement (liboccoder, Chatter-backed)

### Shape

- **🔷** Live under **`liboccoder/`** (like `AgentFactory` / Skill.Runner): project-aware factory, coding agent registration in `Window`, workspace from `ProjectManager`.
- **🔷** Namespace **`OLLMcoder.AgentPi`** (logical **AgentPi**; GIR nesting under liboccoder); factory `name` / agent id **`agent-pi`**; human title **`Agent Pi`**; `long_title` **`implementation of the Pi agent harness`**.
- **🔷** Types: `OLLMcoder.AgentPi.Factory`, `Agent`, `PendingMessage` (chat-only turn queue; summarize deferred).
- **🚫** Do not grow Skill.Runner into this.
- **🚫** Do not pile this into Just Ask.
- **🚫** Do not leave the shipping agent as “Chatter with extras” in `libollmchat` only — too light / wrong layer.

### What we already have

- Loop: `ChatBase.toolsReply` + `Agent.Base.execute_tools`
- Coding tools: `read_file`, `write_file`, `run_command`, search, browser, …
- Chatter: summary + hash recall + `session_fetch`
- liboccoder: `ProjectManager`, SourceView / pane patterns from other factories

---

## Tool names (`read` / `write`)

**Problem:** Pi skills say “use `write`” / `read` / …. Preferred mutate path is **EditMode** (stream fences), not `write_file`. Also agents get the full tool dump — strip per agent via config.

**✔️ Lean:** Agent-Pi-only expose + filter. Phase **1.5**. Implement only after lock.

- **✔️** Pi names via **skeleton Tool subclasses** (own `name` / `description`; same Request/exec as EditMode / ReadFile). **🚫** ToolBuilder `.tool` wraps for this.
- **✔️** Omit `write_file` on Agent Pi via seed `forbid` (user-editable in JSON).
- **✔️** `Config2.agents` map of `AgentConfig` — **`forbidden` only** (**✔️** class; no `mandatory`).
- **🔷** JSON example:

```json
"agents": {
  "agent-pi": {
    "forbidden": [ "write_file", "huggingface_hub" ]
  }
}
```

- **✔️** `Factory.register_config(config, tools)`: seed `forbidden` if missing; two `has_key` checks for `"write"` / `"read"` → `GLib.error` if absent (no `active` check).
- **✔️** **One place** builds `call.tools`: default `configure_tools` — one loop: skip `!active` and `forbidden`, then `set`.
- **🚫** `mandatory` / `mandate` on `AgentConfig`.
- **🚫** Multiple loops; remapping; hardcoded want-lists in `configure_tools`.
- **🔷** `⏳` Later (after this tool surface): Pi-style **`edit`** — exact replace with old/new text in the tool call. Not part of the current AgentConfig / `write`/`read` skeleton work.
- **ℹ️** Prefer `config.2.json` for `forbidden`.

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1b. `libollmchat/Settings/AgentConfig.vala` — drop `mandatory` / `mandate`

**✔️** Applied: type is **`forbidden` + `forbid` only**.

### 1. `libollmchat/Settings/Config2.vala` — `agents` map property

**Why:** Persist per-agent `forbidden`.

**Where:** class body after `tools_unregistered` property.

**Depends on:** `AgentConfig` (**✔️**).

**✔️** Applied.
### 2. `libollmchat/Settings/Config2.vala` — serialize `agents`

**✔️** Applied.

**Why:** Round-trip `agents` in `config.2.json`.

**Where:** `serialize_property` switch — before `case "loaded"`.

**Depends on:** §1.

#### Add — before `case "loaded":`; serialize each AgentConfig under agents.

```vala
				case "agents":
					var agents_obj = new Json.Object();
					foreach (var entry in this.agents.entries) {
						agents_obj.set_member(entry.key, Json.gobject_serialize(entry.value));
					}
					var agents_node = new Json.Node(Json.NodeType.OBJECT);
					agents_node.set_object(agents_obj);
					return agents_node;

```

### 3. `libollmchat/Settings/Config2.vala` — deserialize `agents`

**✔️** Applied.

**Why:** Load `agents` from JSON; every value is `AgentConfig`.

**Where:** `deserialize_property` switch — after the `case "tools":` block.

**Depends on:** §1.

#### Add — new `case "agents":` in `deserialize_property`; deserialize each member as AgentConfig.

```vala
				case "agents":
					if (property_node.get_node_type() != Json.NodeType.OBJECT) {
						break;
					}
					var agents_obj = property_node.get_object();
					agents_obj.foreach_member((object, key, node) => {
						var agent_cfg = Json.gobject_deserialize(typeof(AgentConfig), node) as AgentConfig;
						if (agent_cfg == null) {
							return;
						}
						this.agents.set(key, agent_cfg);
					});
					value = Value(typeof(Gee.Map));
					value.set_object(this.agents);
					return true;

```

### 4. `libollmchat/Agent/Factory.vala` — `configure_tools`: one loop (active + forbidden)

**✔️** Applied.

**Why:** Single place for available tools on an agent call. Forbidden checked when adding — no second pass. Mandatory is not used here.

**Where:** existing `configure_tools` method body.

**Depends on:** §1–3.

#### Remove

```vala
		public virtual void configure_tools(OLLMchat.Call.ChatBase call)
		{
			// Default implementation: no tools added
			// Subclasses should override to add tools from Manager to Chat
		}
```

#### Replace with — clear; one foreach: skip inactive / forbidden; set.

```vala
		public virtual void configure_tools(OLLMchat.Call.ChatBase call)
		{
			call.tools.clear();
			var manager_tools = call.agent.session.manager.tools;
			var config = call.agent.session.manager.config;
			foreach (var entry in manager_tools.entries) {
				if (!entry.value.active) {
					continue;
				}
				if (config.agents.has_key(this.name)
						&& config.agents.get(this.name).forbidden.contains(entry.key)) {
					continue;
				}
				call.tools.set(entry.key, entry.value);
			}
		}
```

### 5. `libollmchat/Agent/Base.vala` — ctor: stop copy-all; only `configure_tools`

**✔️** Applied.

**Why:** One builder; do not pre-copy then filter elsewhere.

**Where:** `Base` constructor — tool setup after `can_call` check.

**Depends on:** §4.

#### Remove

```vala
			// Copy every manager tool entry (key + value) so wrapped aliases (Grep, ls, Read, etc.) are available
			foreach (var entry in this.session.manager.tools.entries) {
				this.chat_call.tools.set(entry.key, entry.value);
			}
			this.factory.configure_tools(this.chat_call);
```

#### Replace with — leave map empty; configure_tools fills it.

```vala
			this.factory.configure_tools(this.chat_call);
```

### 6. `liboccoder/AgentPi/Factory.vala` — `register_config`

**✔️** Applied.

**Why:** Seed `forbidden` if missing; assert required tools exist (hardcoded names — programming error → `GLib.error`).

**Where:** class body — new method after constructor (user-named `register_config`).

**Depends on:** §1. Called after `fill_tools` so `tools` is populated.

#### Add — after `Factory(OLLMfiles.ProjectManager project_manager) { … }`.

```vala
		/**
		 * Seed agent config if missing; assert required tools are registered.
		 *
		 * @param config application config
		 * @param tools manager tool map (after fill_tools)
		 */
		public void register_config(
			OLLMchat.Settings.Config2 config,
			Gee.Map<string, OLLMchat.Tool.BaseTool> tools
		)
		{
			if (!config.agents.has_key(this.name)) {
				config.agents.set(this.name, new OLLMchat.Settings.AgentConfig() {
					forbid = "write_file,huggingface_hub"
				});
			}
			if (!tools.has_key("write")) {
				GLib.error("agent %s: required tool missing: write", this.name);
			}
			if (!tools.has_key("read")) {
				GLib.error("agent %s: required tool missing: read", this.name);
			}
		}
```

### 7. `ollmapp/Window.vala` — call `register_config` after registering Agent Pi

**✔️** Applied: each factory registration calls `register_config` beside `agent_factories.set`. Base default forbids `write,read`; Agent Pi overrides. JustAsk (Manager) and Chatter (`register_default_agents`) also call it.

**Why:** Wire seed at the existing factory registration site.

**Where:** after `agent_factories.set(agent_pi.name, agent_pi)`.

**Depends on:** §6. `app` is already `this.app as OllmchatApplication` above (`fill_tools`).

#### Add — immediately after `this.history_manager.agent_factories.set(agent_pi.name, agent_pi);`

```vala
			agent_pi.register_config(app.config, this.history_manager.tools);
```

### 8. Skeleton tools — thin subclasses (not ToolBuilder wraps)

**Why:** Pi wire names + own descriptions; reuse EditMode / ReadFile Request and execute path.

**Where:** new Vala files under `liboctools/`; register in `Registry.fill_tools`.

**Depends on:** before `register_config` `has_key("write")` / `has_key("read")`.

**🚫** `resources/wrapped-tools/write.tool` / `read.tool` / gresource entries for Pi names.

### 8a. Add `liboctools/EditMode/Write.vala` — skeleton `write`

**✔️** Applied.

#### Add — new file; subclass `EditMode.Tool`; own name/title/example/description/parameter_description (no references to the ''edit_mode'' tool name).

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

namespace OLLMtools.EditMode
{
	/**
	 * Pi-facing ''write'' tool — same Request/exec as {@link Tool}.
	 */
	public class Write : Tool
	{
		public override string name { get { return "write"; } }
		public override string title { get { return "Write"; } }
		public override string example_call {
			get {
				return "{\"name\": \"write\", \"arguments\": {\"file_path\": \"src/main.vala\", \"edit_mode\": \"ast_path\"}}";
			}
		}
		public override string description { get {
			return """
Write or edit a file using stream-captured code fences.

Call this tool with the target path, then emit fenced code blocks. When the turn
completes, captured blocks are applied to the file.

Supported formats:
- ast_path (default, preferred): use type:Namespace-Class-Method
- complete_file: replace or create a full file with a bare language tag
- line_numbers (not recommended): edit an existing file with type:startline:endline
An editing session cannot mix output formats.

Code block format depends on the mode:
- ast_path: Code blocks must include AST path in format type:Namespace-Class-Method.
- ast_path suffixes: `:before-comment`, `:after`, `:remove`, `:with-comment` (comments apply to replace/remove/before-comment).
- line_numbers: Code blocks must include line range in format type:startline:endline (e.g., vala:10:15, vala:1:5). The range is inclusive of the start line and exclusive of the end line. Line numbers are 1-based.
- complete_file: Code blocks should only have the language tag (e.g., ```vala). The entire file content will be replaced. If the file doesn't exist, it will be created. If it exists and overwrite=true, it will be overwritten. If overwrite=false and the file exists, an error will be returned.

When edit_mode=complete_file, do not include line numbers or ast-path in the code block.

CRITICAL: You MUST include both opening and closing markdown code block tags. For example:
```
content to write
```
Don't forget to close the code block with the closing ``` tag. If you don't close it, the changes will not be captured and applied.""";
		} }
		public override string parameter_description { get {
			return """
@param file_path {string} [required] The path to the file to write or edit.
@param edit_mode {string} [optional] One of: ast_path, line_numbers, complete_file. Default is ast_path.
@param overwrite {boolean} [optional] If true and edit_mode=complete_file, overwrite existing file. If false and file exists, return error. Default is false.""";
		} }

		public Write(OLLMfiles.ProjectManager? project_manager = null)
		{
			base(project_manager);
		}

		public override OLLMchat.Tool.BaseTool? clone()
		{
			return new Write(this.project_manager);
		}
	}
}
```

### 8b. Add `liboctools/ReadFile/Read.vala` — skeleton `read`

**✔️** Applied.

#### Add — new file; subclass `ReadFile.Tool`; own name/title/example/description/parameter_description (no references to the ''read_file'' tool name).

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

namespace OLLMtools.ReadFile
{
	/**
	 * Pi-facing ''read'' tool — same Request/exec as {@link Tool}.
	 */
	public class Read : Tool
	{
		public override string name { get { return "read"; } }
		public override string title { get { return "Read"; } }
		public override string example_call {
			get {
				return "{\"name\": \"read\", \"arguments\": {\"file_path\": \"src/main.vala\", \"start_line\": 1, \"end_line\": 30}}";
			}
		}
		public override string description { get {
			return """
Read the contents of a file (and the outline).

If you want to understand what is in a file, you are recommended to call summarize on it first. This will give you an overview of the file's structure and contents before reading specific sections. The summary shows the hierarchical structure of code elements (classes, methods, functions, etc.) with AST paths by default, making it easy to identify and reference specific elements.

You can read specific code elements using AST paths (e.g., "Namespace-Class-Method") instead of line numbers. This is more reliable than line numbers, especially when code changes. AST paths work for files in the active project and automatically resolve to the correct line range, including any preceding documentation comments when available.

When using this tool to gather information, it's your responsibility to ensure you have the COMPLETE context. Each time you call this command you should:
1) Assess if contents viewed are sufficient to proceed with the task.
2) Take note of lines not shown.
3) If file contents viewed are insufficient, and you suspect they may be in lines not shown, proactively call the tool again to view those lines.
4) When in doubt, call this tool again to gather more information. Partial file views may miss critical dependencies, imports, or functionality.

If reading a range of lines is not enough, you may choose to read the entire file.
Reading entire files is often wasteful and slow, especially for large files (i.e. more than a few hundred lines). So you should use this option sparingly.
Reading the entire file is not allowed in most cases. You are only allowed to read the entire file if it has been edited or manually attached to the conversation by the user.""";
		} }
		public override string parameter_description { get {
			return """
@param file_path {string} [required] The path to the file to read.
@param ast_path {string} [optional] AST path to locate code elements (e.g., "Namespace-Class-Method"). Alternative to start_line/end_line. Resolves to line range automatically and includes preceding documentation comments when available. Only works for files in the active project.
@param start_line {integer} [optional] The starting line number to read from. Ignored if ast_path is provided.
@param end_line {integer} [optional] The ending line number to read to. Ignored if ast_path is provided.
@param read_entire_file {boolean} [optional] Whether to read the entire file. Only allowed if the file has been edited or manually attached to the conversation by the user.
@param show_lines {boolean} [optional] If true, output content with line numbers prefixed to each line (e.g., "1: content", "2: content"). We recommend you do this if you are going to edit code, as it will make it easier to work out which lines to edit.
@param find_words {string} [optional] Search for lines containing this string and return only matching lines with line numbers. Case-insensitive search.
@param summarize {boolean} [optional] If true, generate a tree-sitter based summary of the file structure instead of reading the file contents. The summary shows the hierarchical structure (classes, methods, functions, etc.) with AST paths by default. If you want line numbers instead, use show_lines parameter.""";
		} }

		public Read(OLLMfiles.ProjectManager? project_manager = null)
		{
			base(project_manager);
		}

		public override OLLMchat.Tool.BaseTool? clone()
		{
			return new Read(this.project_manager);
		}
	}
}
```

### 8c. `liboctools/meson.build` — list new sources

**✔️** Applied.

**Where:** `octools_src` (or equivalent) next to `EditMode/Tool.vala` / `ReadFile/Tool.vala`.

#### Add — after the existing EditMode / ReadFile Tool.vala entries.

```meson
  'EditMode/Write.vala',
  'ReadFile/Read.vala',
```

### 8d. `liboctools/Registry.vala` — `fill_tools` register skeletons

**✔️** Applied.

**Where:** `fill_tools` after existing `ReadFile.Tool` / `EditMode.Tool` registration.

#### Add — immediately after `manager.register_tool(new EditMode.Tool(project_manager));` (and ReadFile line as needed).

```vala
			manager.register_tool(new EditMode.Write(project_manager));
			manager.register_tool(new ReadFile.Read(project_manager));
```

(**ℹ️** Keep registering `edit_mode` / `read_file` too; Agent Pi `forbid` can drop the long names. Android fill path **💩** if it has its own list.)

- **💩** `⏳` `bash` skeleton on `RunCommand.Tool` the same way.
- **🚫** Changing existing `resources/wrapped-tools/Read.tool`.

---

## How Pi loads `SKILL.md` (reference)

Not our refine/execute skills. Pi (Agent Skills–shaped):

1. **Scan dirs** — e.g. `~/.pi/agent/skills`, `.pi/skills`, `.agents/skills`, package skills, settings paths.
2. **Per directory** — if `SKILL.md` exists, that dir is a skill root (no recurse into it for nested skills); else recurse; some roots also allow loose `*.md`.
3. **Parse file** — YAML frontmatter: required `description`; `name` (or parent dir name); optional `disable-model-invocation`, etc. Body = free markdown (+ scripts/refs beside it).
4. **Catalog only in system prompt** — name, description, **absolute path** to `SKILL.md` (`<available_skills>` XML).
5. **Full body on demand** — model uses **`read`** on that path.
6. Relative paths inside the skill resolve against the **skill directory** (parent of `SKILL.md`).

Our `OLLMcoder.Skill.Definition` is different: YAML + **refine** / **execute** sections, host-bound into Runner stages. **Wrong loader for Pi-like.**

---

## `Skill` — separate from old skills

- **🔷** Types live under **`OLLMcoder.AgentPi`**: **`Skill`** (entry) + **`SkillSet`** (scan + `to_prompt`). Detail: **Phase 2**.
- **🔷** **Wiring only in Agent Pi** (`SkillSet` in `PendingMessage` → `pi-prompts/initial.md`).
- **🚫** No shared `Skill.Manager`, **no** shared skill directories with Runner builtins unless we deliberately dual-publish later.
- **🔷** Storage:
  - user/global: `~/.local/share/ollmchat/pi-skills/`
  - project: `.pi/skills/` and `.agents/skills/` under project root
  - optional later: gresource pack of Pi-format skills (not `resources/skills/` Runner files)
- **🔷** On system build: scan → catalog in prompt → model uses `read` on `location`.
- **🚫** No slash-command / forced skill-inject UI — catalog + `read` only.
- **🚫** Do not parse refine/execute or call `Skill.Manager.validate`.
- **🚫** Do not feed Skill entries into task-list skill assignment.
- **🚫** Do not wire into JustAsk / Chatter / other factories.

---

## Key sections (phases)

### Phase 0 — Factory in liboccoder (`AgentPi` / `agent-pi`)

- **✔️** `OLLMcoder.AgentPi.Factory` + `Agent` + `PendingMessage` under `liboccoder/AgentPi/`.
- **✔️** Factory `name = "agent-pi"`; `title = "Agent Pi"`; `long_title = "implementation of the Pi agent harness"`.
- **✔️** Prompt **`pi-prompts/initial.md`** only; chat-only FIFO (full transcript).
- **✔️** SourceView activate/deactivate (liboccoder weight); project required on send.
- **✔️** Registered in `ollmapp/Window.vala` agent factories.
- **🚫** Paired summarize / `followup.md` / shared `Summarizer` stand-in.
- **🚫** RAPIR / task list / progress conductor.
- **🚫** Context hygiene — locked **Phase 5 Option C**.
- **ℹ️** GIR forces nest under `OLLMcoder` (secondary top-level namespaces unsupported).
- **ℹ️** Environment block today matches **Chatter** (date / OS / shell / workspace), not Pi (cwd line only + AGENTS/skills in system prompt — Phases 1–3).
- **🔷** Existing-code changes (e.g. `Agent.Summarizer`) require review before apply.

### Phase 1 — `AGENTS.md`

#### What Pi does when the file is missing (re-checked)

**No default `AGENTS.md` content is injected.** Discovery returns `[]`; `buildSystemPrompt` only emits `<project_context>` when `contextFiles.length > 0`. Tests pass empty `contextFiles: []` as the normal case. Docs say “Add an AGENTS.md…” — optional, not auto-created. No install/onboard path writes one. Repo-root `AGENTS.md` in pi-mono is **their** project file when you run pi there, not a packaged fallback for empty dirs.

What you still always get (easy to confuse with “a default agent file”):

- **Built-in system prompt** — role (“expert coding assistant…”), tool list + snippets, short guidelines (“Be concise…”, “Show file paths…”), pointers to pi’s own docs paths, then `Current working directory: …`.
- Optional overlays if **present**: `SYSTEM.md` (replace), `APPEND_SYSTEM.md` (append), then any discovered AGENTS/CLAUDE files, then skills catalog.

So: missing agents file ⇒ **omit the project-instructions block**; the harness prompt remains. Not “inject a canned AGENTS.md.”

#### Our Phase 1 design (lock before implement)

- **✔️** Load, if present (concatenate in this order):
  1. **User global:** `~/.local/share/ollmchat/AGENTS.md`
  2. **Ancestors under home:** if project under `$HOME`, walk up to `$HOME` (outer → inner); outside `$HOME` → project root only (+ global).
- **✔️** Prefer `AGENTS.md` over `CLAUDE.md` in the same directory.
- **✔️** If nothing found: omit inject.
- **✔️** `Factory.build_agents_md(project_path)` + `{agents_md}` in `pi-prompts/initial.md`.
- **ℹ️** Separate from vector `project_description()`; may show both later if wanted.
- **🚫** Fake AGENTS path / `agent/` subdir / size policy (size = after Phase 9).
- **ℹ️** Offer-to-create is **Phase 9**.

### Phase 2 — `Skill` loader + catalog

**Wiring scope:** **🔷** Agent Pi only (`OLLMcoder.AgentPi`).  
**🚫** JustAsk, Chatter, Skill.Runner, `OLLMcoder.Skill.Manager`, other factories.

#### Classes (under `liboccoder/AgentPi/`)

| Class | Role |
|-------|------|
| **`Skill`** | One catalog entry: `name`, `description`, absolute `path` to `SKILL.md`, `base_dir` (parent of that file), `disable_model` (`disable-model-invocation`). |
| **`SkillSet`** | Scanner + catalog formatter. Holds `Gee.ArrayList<Skill> items`. Methods: **`scan`**, **`to_prompt`**. |

- **🔷** Namespace stays **`OLLMcoder.AgentPi`** (same as Factory) so GIR nesting and “Agent Pi only” stay obvious.
- **🚫** Soft-skill types live only as **`OLLMcoder.AgentPi.Skill`** / **`SkillSet`** — not a new top-level package, and not inside **`OLLMcoder.Skill.*`** (Runner).
- **🚫** No shared types with `OLLMcoder.Skill.*`.

#### `Skill` — entry

- **🔷** Plain `GLib.Object` data class (properties above).
- **🔷** Named ctor / load path: **`Skill.load(string skill_md_path)`** → entry or skip (missing/empty `description`).
- **🔷** Frontmatter (minimal YAML, same shape as Pi / Child agent files):
  - required: `description`
  - optional: `name` (else parent directory name), `disable-model-invocation: true`
- **🚫** Do not parse refine/execute sections.
- **🚫** Do not validate against Runner skill schema.

#### `SkillSet` — scan + format

**`scan(string project_path)`**

Roots (in order; skip missing):

1. `~/.local/share/ollmchat/pi-skills/`
2. `{project}/.pi/skills/` when `project_path` non-empty
3. `{project}/.agents/skills/` when `project_path` non-empty (interop)

Walk rule:

- For each root, list **immediate** child directories (skip hidden names starting with `.`).
- If `{child}/SKILL.md` exists → `Skill.load`; otherwise ignore that child (no deep recurse).
- Later skills with the same `name` replace earlier (project wins over global if scanned last).

**`to_prompt()`**

- Skip entries with `disable_model == true`.
- Empty → `""` (omit block, like missing AGENTS).
- Else Pi-style XML catalog:

```text
## Skills

The following skills provide specialized instructions for specific tasks.
Use the read tool to load a skill's file when the task matches its description.
When a skill file references a relative path, resolve it against the skill directory
(parent of SKILL.md) and use that absolute path in tool commands.

<available_skills>
  <skill>
    <name>…</name>
    <description>…</description>
    <location>…/SKILL.md</location>
  </skill>
  …
</available_skills>
```

#### Agent Pi wiring only

| Site | Change |
|------|--------|
| `PendingMessage.run` | `new SkillSet()` → `scan` → pass `to_prompt()` as `"skills_md"` beside `agents_md` (no Factory wrapper). |
| `resources/pi-prompts/initial.md` | Add `{skills_md}` after `{agents_md}`. |
| `liboccoder/meson.build` | List `AgentPi/Skill.vala`, `AgentPi/SkillSet.vala`. |

- **🚫** Do not scan/inject SkillSet from Chatter / JustAsk / Skill.Factory / Window except via Agent Pi’s own send path.
- **🚫** No slash-command / forced skill-inject UI (catalog + `read` only).
- **🚫** No thin `Factory.build_skills_md` — call `SkillSet` at the send site.

#### Status

- **✔️** Classes + Agent Pi wire applied (await user verify).

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 2a. Add `liboccoder/AgentPi/Skill.vala` — catalog entry + load

**Why:** One Agent Skills–shaped row for the prompt catalog.

**Where:** new file under `AgentPi/`.

**Depends on:** none.

#### Add — new file `Skill` in `OLLMcoder.AgentPi`.

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

namespace OLLMcoder.AgentPi
{
	/**
	 * One Pi-format soft skill (Agent Skills ''SKILL.md'' entry).
	 *
	 * Catalog-only for Agent Pi: name/description/path go in the system prompt;
	 * the model loads the body with the ''read'' tool. Not an
	 * {@link OLLMcoder.Skill.Definition}.
	 */
	public class Skill : GLib.Object
	{
		public string name { get; set; default = ""; }
		public string description { get; set; default = ""; }
		public string path { get; set; default = ""; }
		public string base_dir { get; set; default = ""; }
		public bool disable_model { get; set; default = false; }

		/**
		 * Load a skill from an absolute ''SKILL.md'' path.
		 *
		 * @param skill_md_path absolute path to ''SKILL.md''
		 * @return skill, or null when description is missing
		 */
		public static Skill? load(string skill_md_path)
		{
			uint8[] raw;
			string etag;
			try {
				GLib.File.new_for_path(skill_md_path).load_contents(null, out raw, out etag);
			} catch (GLib.Error e) {
				return null;
			}
			var name = "";
			var description = "";
			var disable_model = false;
			var in_frontmatter = false;
			var found_first = false;
			foreach (var line in ((string) raw).split("\n")) {
				var stripped = line.strip();
				if (stripped == "---") {
					if (!found_first) {
						found_first = true;
						in_frontmatter = true;
						continue;
					}
					break;
				}
				if (!in_frontmatter) {
					continue;
				}
				if (stripped == "" || stripped.has_prefix("#")) {
					continue;
				}
				var colon = stripped.index_of(":");
				if (colon < 0) {
					continue;
				}
				var key = stripped.substring(0, colon).strip();
				var value = stripped.substring(colon + 1).strip();
				switch (key) {
					case "name":
						name = value;
						break;
					case "description":
						description = value;
						break;
					case "disable-model-invocation":
						disable_model = (value == "true");
						break;
				}
			}
			if (description.strip() == "") {
				return null;
			}
			var base_dir = GLib.Path.get_dirname(skill_md_path);
			if (name == "") {
				name = GLib.Path.get_basename(base_dir);
			}
			return new Skill() {
				name = name,
				description = description,
				path = skill_md_path,
				base_dir = base_dir,
				disable_model = disable_model
			};
		}
	}
}
```

### 2b. Add `liboccoder/AgentPi/SkillSet.vala` — scan + `to_prompt`

**Why:** Own scanner for Agent Pi soft skills; format catalog XML.

**Where:** new file under `AgentPi/`.

**Depends on:** §2a.

#### Add — new file `SkillSet` with `scan` + `to_prompt` (plan-named).

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

namespace OLLMcoder.AgentPi
{
	/**
	 * Scan Pi-format skill directories and format the Agent Pi catalog.
	 *
	 * Roots: ''~/.local/share/ollmchat/pi-skills/'', project ''.pi/skills/'',
	 * project ''.agents/skills/''. Used from {@link PendingMessage.run}.
	 */
	public class SkillSet : GLib.Object
	{
		public Gee.ArrayList<Skill> items {
			get;
			private set;
			default = new Gee.ArrayList<Skill>();
		}

		/**
		 * Clear and rescan global + project skill roots.
		 *
		 * @param project_path active project path (may be empty)
		 */
		public void scan(string project_path)
		{
			this.items.clear();
			var by_name = new Gee.HashMap<string, Skill>();
			string[] roots = {};
			var global_root = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "ollmchat", "pi-skills");
			if (GLib.FileUtils.test(global_root, GLib.FileTest.IS_DIR)) {
				roots += global_root;
			}
			var project = project_path.strip();
			if (project != "") {
				var pi_root = GLib.Path.build_filename(project, ".pi", "skills");
				if (GLib.FileUtils.test(pi_root, GLib.FileTest.IS_DIR)) {
					roots += pi_root;
				}
				var agents_root = GLib.Path.build_filename(project, ".agents", "skills");
				if (GLib.FileUtils.test(agents_root, GLib.FileTest.IS_DIR)) {
					roots += agents_root;
				}
			}
			foreach (var root in roots) {
				try {
					var enumerator = GLib.File.new_for_path(root).enumerate_children(
						"standard::name,standard::type",
						GLib.FileQueryInfoFlags.NONE,
						null);
					GLib.FileInfo? info = null;
					while ((info = enumerator.next_file(null)) != null) {
						var name = info.get_name();
						if (name.has_prefix(".")) {
							continue;
						}
						if (info.get_file_type() != GLib.FileType.DIRECTORY) {
							continue;
						}
						var skill_md = GLib.Path.build_filename(root, name, "SKILL.md");
						if (!GLib.FileUtils.test(skill_md, GLib.FileTest.IS_REGULAR)) {
							continue;
						}
						var skill = Skill.load(skill_md);
						if (skill != null) {
							by_name.set(skill.name, skill);
						}
					}
				} catch (GLib.Error e) {
				}
			}
			foreach (var entry in by_name.entries) {
				this.items.add(entry.value);
			}
		}

		/**
		 * Build the system-prompt skills block (empty when nothing visible).
		 *
		 * @return markdown + XML catalog, or empty string
		 */
		public string to_prompt()
		{
			string[] blocks = {};
			foreach (var skill in this.items) {
				if (skill.disable_model) {
					continue;
				}
				blocks += @"  <skill>
    <name>$(skill.name)</name>
    <description>$(skill.description)</description>
    <location>$(skill.path)</location>
  </skill>";
			}
			if (blocks.length == 0) {
				return "";
			}
			return @"## Skills

The following skills provide specialized instructions for specific tasks.
Use the read tool to load a skill's file when the task matches its description.
When a skill file references a relative path, resolve it against the skill directory
(parent of SKILL.md) and use that absolute path in tool commands.

<available_skills>
$(string.joinv("\n", blocks))
</available_skills>
";
		}
	}
}
```

### 2c. `liboccoder/AgentPi/PendingMessage.vala` — pass `skills_md`

**Why:** Only Agent Pi send path injects the catalog. Inline `SkillSet` here — do not add a Factory pass-through.

**Where:** `run`, after resolving `project_path`, the `system_fill` call.

**Depends on:** §2b + prompt §2d.

#### Remove

```vala
			outbound.add(new OLLMchat.Message("system", tpl.system_fill(
				"environment", factory.build_environment(agent.session),
				"agents_md", factory.build_agents_md(project_path))));
```

#### Replace with

```vala
			var skill_set = new SkillSet();
			skill_set.scan(project_path);
			outbound.add(new OLLMchat.Message("system", tpl.system_fill(
				"environment", factory.build_environment(agent.session),
				"agents_md", factory.build_agents_md(project_path),
				"skills_md", skill_set.to_prompt())));
```

### 2d. `resources/pi-prompts/initial.md` — `{skills_md}` slot

**Where:** after `{agents_md}`.

#### Remove

```markdown
{agents_md}
---
```

#### Replace with

```markdown
{agents_md}
{skills_md}
---
```

### 2e. `liboccoder/meson.build` — list sources

#### Add — after `AgentPi/PendingMessage.vala`.

```meson
  'AgentPi/Skill.vala',
  'AgentPi/SkillSet.vala',
```

---

### Phase 3 — System prompt assembly

- **🔷** `⏳` liboccoder prompt templates for this agent:
  - role / guidelines
  - environment (from project)
  - `AGENTS.md` block
  - `Skill` catalog
  - follow-up / summary slot **only if Phase 5 Option A** (otherwise keep growing transcript + `initial.md`-style system)
- **🔷** `⏳` `toolsReply` only control loop.
- **💩** Default tool subset for this agent ([2.30](../plans/2.30-pretooler-tool-filtering.md)).

### Phase 4 — Tool rename / aliases

- **🔷** `⏳` Lock Option A vs B (§ Tool names).
- **🔷** `⏳` Update references (skills YAML, prompts, wrapped tools, tests) so old names do not break Runner or history replay where needed.
- **ℹ️** Prefer aliases if rename churn on Runner is too high.

### Phase 5 — Context hygiene (deferred — **Option C**)

**✔️ Locked: Option C** — do not implement for Agent Pi until we deliberately reopen A vs B. No stand-in.

Same problem as Pi: long sessions drown the next LLM call. When we reopen, pick **A** or **B** and do it properly.

Study: [01 §7](01-pi-agent.md#7-context-growth-pi-compaction-vs-chatter). Chatter design: [2.31](../plans/2.31-just-ask-summary-history.md). Pi source: `packages/coding-agent/src/core/compaction/`.

#### What Pi does (compaction)

- **Trigger:** context token usage crosses a threshold, or user `/compact` (optional custom instructions).
- **Cut:** keep a recent tail (~`keepRecentTokens`, default ~20k); older path entries are **omitted from the next LLM context**.
- **Replace with:** one `compactionSummary` message (structured checkpoint), then the kept recent entries.
- **Summary shape (LLM, fixed sections):** Goal; Constraints & Preferences; Progress (Done / In Progress / Blocked); Key Decisions; Next Steps; Critical Context. Later compacts **update** a `<previous-summary>` rather than starting from scratch. Appends read/modified file lists from tool ops.
- **Recall of dropped turns:** **none in-loop.** Old entries may still exist on the session path for UI/history, but the model does **not** get a `session_fetch`-style tool to pull exact prior tool output by id. Continuity is whatever survived in the checkpoint text + the recent tail.
- **Cadence:** occasional / on pressure — not after every user turn.

#### What we do (Chatter summarizer + references)

- **Trigger:** after **every** completed chat turn (background, paired FIFO with chat).
- **Replace with:** a rolling `summary` role message injected into the **system** prompt on follow-ups; API messages are only **since** that summary (plus current turn).
- **Full list to the summarizer:** `{turn_references}` — every row of the completed turn as headed sections with hash links (`[#user-N](#user-N)`, `[#think-N](#think-N)`, `[#agent-N](#agent-N)`, `[#tool-N](#tool-N)`), plus an **Allowed references** set. Summarizer must only emit links from that set (validated + one retry).
- **Recall:** main agent calls **`session_fetch`** with a tag (`user-1`, `tool-6`, or `"index"`) to load the **exact** stored message. Summary stays short; details stay recoverable.
- **Cadence:** continuous rolling memory — stronger for “what did that tool return?”; costs an extra LLM call per turn.

#### Why the half-measure is wrong

- **🚫** Point Agent Pi at shared `Summarizer` + `chatter_summary.md` “for now.”
- **🚫** Add `pi-prompts/summary.md` (or similar) that we expect to delete when “doing it properly.”
- **🚫** Ship `followup.md` written for hash/`session_fetch` while summarization is unfinished or uses the wrong prompt.

#### Options when reopened

| | Option A — Chatter-style | Option B — Pi-style compaction | Option C — defer (**current**) |
|--|--------------------------|--------------------------------|--------------------------------|
| When | Every turn (or later: threshold) | Token threshold / explicit compact | Never for Agent Pi yet |
| Prompt | Agent Pi–owned summary template (AGENTS / Skill-aware) | Structured Goal/Progress/… checkpoint (copy/derive → Phase 8) | — |
| Model sees | System summary + recent turns | Compaction blob + recent tail | Full history until OOM/context fail |
| Exact recall | **`session_fetch` + hash links** | Text left in checkpoint only | N/A (everything still in context) |
| Shared code | Needs reviewed `Summarizer` flexibility **or** AgentPi-local summarizer | New compact path (cut point + reload) | Chat-only (done for Phase 0) |

- **✔️** Option C applied: no paired summarize; only `initial.md`; full transcript via `create_summary()` (skipping any stray `summary` rows).
- **🔷** When reopening: lock A vs B before implement.
- **🔷** If **A**: proper Agent Pi summary prompt + followup contract + `session_fetch`; any `Summarizer.vala` change is review-before-apply.
- **🔷** If **B**: cut + checkpoint (+ Phase 8 if copying Pi prompt text).
- **ℹ️** Lean later: **A** keeps reference list + recall; **B** matches Pi’s trigger economics.

### Phase 6 — Steer / follow-up (later)

- **🔷** Requirement later; not blocking Phases 0–3.
- **ℹ️** Chatter FIFO ≠ between-tool-batch steer.

### Phase 7 — Permissions

- **🔷** Keep writer approval / file review / sandbox.
- **🚫** No Pi “no popups.”

### Phase 8 — Licenses + SBOM (when copying Pi prompts)

Pi harness is **MIT** (Copyright Mario Zechner / Earendil — see `/home/alan/git/pi/LICENSE`). MIT requires preserving copyright + permission notice in copies/substantial portions.

- **🔷** `⏳` Add a **`licenses/`** (or `third_party/`) folder when we take Pi prompt text (or other Pi files), e.g.:
  - `licenses/pi-coding-agent/LICENSE` (upstream MIT text)
  - short `NOTICE` / README: what we copied (paths), upstream repo/ref, date
- **🔷** `⏳` Maintain an **SBOM** entry (or small `sbom` / dependency note) listing Pi as a **source component** for those prompts — even if we do not vendor the whole package.
- **🔷** `⏳` Mark derived prompt files in-tree (comment or adjacent `.NOTICE`) so later editors know origin.
- **ℹ️** Original prompts we write ourselves need no Pi license file; only copied/derived content.
- **💩** Exact SBOM format (CycloneDX JSON vs a markdown inventory under `licenses/`) — lock at implement; markdown inventory is enough for a first cut.
- **🚫** Do not copy Pi code/prompts without the MIT notice nearby.

### Phase 9 — Offer to create `AGENTS.md` (later)

Pi never prompts. We may when **Agent Pi is selected** and a **project is active/opened** and project-root has no `AGENTS.md` (CLAUDE-only **💩**):

> This project has no AGENTS.md — create one?

**Where:** [`ollmapp/ActivityBanner`](../../ollmapp/ActivityBanner.vala) — header status strip used for scan/vector/download progress ([5.0.6](../plans/done/5.0.6-DONE-activity-progress-actions.md)). Same spine: `History.Manager.notification` → banner; action via `action` / `action_label` → `notification_reply`.

- **🔷** `⏳` Emit a `client.*` (or similar) notification: message = missing-AGENTS copy; `action_label` = e.g. `Create`; `action` = handler id for Agent Pi / Window.
- **🔷** `⏳` On Create: write a starter `AGENTS.md` at **project root** (template content **💩** — short stub vs richer scaffold).
- **🔷** Trigger when: switch **to** `agent-pi` with a project already active, **and/or** activate/open a project while Agent Pi is current. Debounce / once-per-project-per-session **💩**.
- **💩** Dismiss without Create — banner auto-hide timeout already exists; explicit Dismiss needs a second button (banner today has **one** action) or treat hide-as-dismiss.
- **💩** Collision with live progress (scan/index/download): don’t clobber an in-flight progress notification; queue or wait until banner idle (**💩** exact policy).
- **ℹ️** Not a default inject — Phase 1 still omits when missing; this only offers to create a real file.
- **🚫** Not part of Phase 1 implement.
---

## Out of this plan

- **🚫** Skill.Runner / old `Skill.Manager` crossover for Pi skills.
- **🚫** Using `resources/skills/*.md` (refine/execute) as Skill sources.
- **🚫** Parallel tool execution as a goal.
- **🚫** Pi extensions / packages / TUI / RPC.
- **ℹ️** Pi-style exact **`edit`** (old/new text in args) — later phase after current tool surface; not in this hunk set.

---

## Suggested order

1. Phase 0 — `AgentPi` / `agent-pi` factory (chat-only; Option C)  
2. Phase 1 — AGENTS.md (global + home-capped parent walk + inject; omit if missing)  
2.5. Phase 1.5 — tool rename audit/lock then apply (`read` / `write` / …)  
3. Phase 2 — Skill  
4. Phase 3 — prompts (**with Phase 8** if any Pi prompt text is copied)  
5. Phase 4 — tool rename/aliases (can start earlier if it unblocks prompts)  
6. Phase 5 — deferred (Option C); reopen A vs B later if needed  
7. Phase 6 — steer/follow-up when wanted  
8. Phase 8 — `licenses/` + SBOM whenever Phase 3/5 takes upstream text  
9. Phase 9 — offer to create `AGENTS.md` (ActivityBanner)  
10. After Phase 9 — AGENTS inject soft-cap as a % of active model context  

---

## LLM notes

- **ℹ️** Study: [01-pi-agent.md](01-pi-agent.md).
- **ℹ️** Pi skill load: `packages/coding-agent/src/core/skills.ts` (`loadSkillFromFile`, `formatSkillsForPrompt`); docs `packages/coding-agent/docs/skills.md`.
- **ℹ️** Chatter kernel: `libollmchat/Chatter/`, [2.31](../plans/2.31-just-ask-summary-history.md).
- **ℹ️** liboccoder weight: `OLLMcoder.AgentFactory`, `OLLMcoder.Skill.Factory`.
- **🔷** Namespace **`OLLMcoder.AgentPi`**; agent id **`agent-pi`**; title **`Agent Pi`**; `long_title` **`implementation of the Pi agent harness`**.
- **ℹ️** Pi license: MIT — `/home/alan/git/pi/LICENSE` (and published `@earendil-works/pi-coding-agent`).
- **🚫** Do not use `OLLMcoder.Skill.Manager` for Skill.
- **🚫** Do not merge this agent into Skill.Runner.
- **🚫** Do not copy Pi prompts without Phase 8 attribution.
