# 02. Pi-like agent

Status: ⏳ proposed

ℹ️ Checklist: `docs/guide-to-writing-plans.md` — Checklist for plans.  
ℹ️ Study: [01-pi-agent.md](01-pi-agent.md); harness meaning: [04-pi-harness-what-it-actually-does.md](04-pi-harness-what-it-actually-does.md). Vala: `docs/coding-standards.md` via router when implementing.  
ℹ️ Split-out plans: [06 urgent/follow-up](06-urgent-follow-up.md), [07 project-summary tool](07-project-summary-tool.md), [09 offer AGENTS.md](09-offer-agents-md.md); base skills [03](03-base-skills.md).

## Purpose

- **🔷** New **liboccoder-weight** free-form coding agent: `ProjectManager`, project-required, coding prompts/UI — not a thin Chatter clone as the final product.
- **🔷** Agent id **`agent-pi`**; Vala namespace **`OLLMcoder.AgentPi`** (GIR: nested under liboccoder’s `OLLMcoder`); human title **`Agent Pi`**; `long_title` **`implementation of the Pi agent harness`**.
- **🔷** Reuse Chatter ideas for the **turn queue** later if Phase 5 lands (summary + `session_fetch`). Chatter itself stays light.
- **🔷** Phase 5: Pi **cutoff + structured summary template**, plus **hash reference tags** and **`session_fetch`** so dropped history stays recoverable.
- **✔️** Phase 5 wiring landed (`Summarizer` prompt props + `compact.md` + Agent Pi threshold compact).
- **🔷** Pi good bits: `AGENTS.md` inject, Agent Skills–style soft skills, model-owned `toolsReply`.
- **🔷** Separate skill system (**`Skill`**) — **no** reuse of `OLLMcoder.Skill.Manager` / refine–execute skill files.
- **🔷** `⏳` Base skill pack (Phase 2.1) — curated `SKILL.md` dirs shipped with the app; not npm.
- **🔷** Keep permissions / approvals.
- **✔️** Pi-facing tool names on Agent Pi (`read` / `write` / `bash` + forbid long names). Phase 4 done for that lean scope.
- **✔️** Phase 8 licenses inventory; Phase 3 prompt copy attributed under MIT.
- **⏳** Remaining backlog lives in sibling plans ([06](06-urgent-follow-up.md), [07](07-project-summary-tool.md), [09](09-offer-agents-md.md), [03](03-base-skills.md)); lock policy there, then implement.

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
- **✔️** Omit `write_file` / `edit_mode` / `read_file` / `run_command` on Agent Pi via seed `forbid` (user-editable in JSON); Pi-facing tools are `write` / `read` / `bash` (EditMode / ReadFile / RunCommand skeletons).
- **✔️** `Config2.agents` map of `AgentConfig` — **`forbidden` only** (**✔️** class; no `mandatory`).
- **🔷** JSON example:

```json
"agents": {
  "agent-pi": {
    "forbidden": [ "write_file", "edit_mode", "read_file", "run_command" ]
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
					forbid = "write_file,edit_mode,read_file,run_command"
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
- **🔷** A skill is **generic content**: `SKILL.md` (frontmatter + markdown) plus optional helper **scripts** (shell or whatever the skill documents) and assets beside it — Agent Skills–shaped, not an npm module type.
- **ℹ️** Pi’s `pi install` / npm / git packages are only **their** distribution story for bundling skills with extensions. The skill format itself is not tied to npm or Node.
- **🚫** Do not adopt npm / `pi install` / Node package gallery as how OLLMchat ships or discovers skills.
- **🔷** Storage (user-editable):
  - user/global: `~/.local/share/ollmchat/pi-skills/`
  - project: `.pi/skills/` and `.agents/skills/` under project root
- **🔷** `⏳` **Base set** — ship a small curated pack of Pi-format skills with the app (see **Phase 2.1**). Not empty-forever.
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
- **🚫** Context hygiene not shipped yet — Phase 0 stays full transcript; Phase 5 design locked below (not “defer forever”).
- **ℹ️** GIR forces nest under `OLLMcoder` (secondary top-level namespaces unsupported).
- **ℹ️** Environment: date / OS via `{environment}`; **Current working directory: `{cwd}`** where cwd is the **project path** (or home) — we pretend the shell cwd is the project.
- **🔷** Existing-code changes require review before apply (Phase 5: `Summarizer.prompt_base_dir` / `prompt_filename` + AgentPi construct/wiring — **🚫** rewrite `chatter_summary.md`; **🚫** new Factory helper).

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
- **🚫** Fake AGENTS path / `agent/` subdir / size policy (size = after [09](09-offer-agents-md.md)).
- **ℹ️** Offer-to-create: [09](09-offer-agents-md.md).

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

- **✔️** `liboccoder/AgentPi/Skill.vala`, `SkillSet.vala` — see sources (not reproduced here).
- **✔️** Wire: `PendingMessage.run` scans/`to_prompt` → `{skills_md}`; `resources/pi-prompts/initial.md`; meson lists both files.

### Phase 2.1 — Base skill pack (backlog)

- **🔷** `⏳` Offer a **base set** of Agent Pi skills so a fresh install is not catalog-empty.
- **ℹ️** Research / options: [03-base-skills.md](03-base-skills.md) — collections, acquisition open (vendor vs seed vs docs-only; **🚫** npm).
- **🔷** Content shape only: each skill = directory with `SKILL.md` (+ optional shell/scripts/assets the markdown points at). Language-agnostic text + scripts — **not** Node packages.
- **🚫** npm / `pi install` / package gallery as the delivery mechanism.
- **🔷** Ship in-tree under something like `resources/pi-skills/` (or similar) — **not** `resources/skills/` (Runner refine/execute).
- **💩** Delivery into the scan: gresource extract / copy-on-first-use into `~/.local/share/ollmchat/pi-skills/` vs scan a read-only gresource root vs install-tree share dir — lock at implement (`SkillSet.scan` may need one more root).
- **💩** Which skills belong in the base set — lock via 03 shortlist when implementing.
- **ℹ️** User/project dirs still override / add skills (same name replace rules as Phase 2).
- **ℹ️** Third-party skills later = drop folders into those dirs (or a future non-npm share format) — not a Node registry.

---

### Phase 3 — System prompt assembly (Pi-shaped)

**What this is not:** inventing a new “liboccoder prompt product.” We already have `resources/pi-prompts/initial.md` + inject slots.

**What Pi does:** `packages/coding-agent/src/core/system-prompt.ts` `buildSystemPrompt` — default harness text (role, available tools + one-line snippets, guidelines, cwd), then optional project context / skills. Not a separate markdown package of many templates.

**What we have now:**

- **✔️** `pi-prompts/initial.md` — derived from Pi `buildSystemPrompt` (MIT; see `licenses/` + `pi-prompts/NOTICE`).
- **✔️** `{agents_md}` / `{skills_md}` / `{environment}` (date, OS) / `{cwd}` (= project path) inject (Phases 1–3).
- **✔️** Control loop is already `toolsReply`.

**Phase 3 work:**

- **✔️ Locked: Option A** — copy/derive Pi’s default system-prompt wording.
- **✔️** `licenses/README.md` lists `resources/pi-prompts/initial.md`.
- **✔️** Pi-shaped assembly: role / tools + snippets / guidelines / cwd (filled with project path); agents + skills; no pi docs path block.
- **✔️** Tool one-liners: `read`, `write` (EditMode), `bash` (RunCommand), `codebase_search`, `browser`. **🚫** `write_file` / `edit_mode` / `read_file` / `run_command` (forbidden on Agent Pi).
- **🚫** Do not add `followup.md` / summary templates in Phase 3 — those land with Phase 5.
- **🚫** Option B (write original short text, skip Phase 8) — not the path.
- **💩** Default tool subset ([2.30](../plans/2.30-pretooler-tool-filtering.md)) — optional, not the core of Phase 3.

### Phase 4 — Tool rename / aliases

- **✔️** Locked lean path (Agent Pi only): skeletons `read` / `write` / `bash` + seed `forbid` of long names — see **Tool names** above (Phase 1.5).
- **✔️** Agent Pi prompt one-liners use those Pi names.
- **🚫** Global rename of `write_file` / `run_command` / … across Skill.Runner YAML and every agent — not required; other agents keep long names.
- **🔷** `⏳` Later (not Phase 4): Pi-style exact **`edit`** tool — still backlog under Tool names.

### Phase 5 — Context hygiene

**✔️** Implemented (agent): Summarizer `prompt_base_dir` / `prompt_filename`; `pi-prompts/compact.md`; Agent Pi threshold compact + `create_summary()` outbound. Hybrid: Pi **when/how to cut** + Pi **summary sections**, plus our **reference tags** and **history recall tool**.

Study refs (background only): [01 §7](01-pi-agent.md#7-context-growth-pi-compaction-vs-chatter); Pi `packages/coding-agent/src/core/compaction/`; hash/`session_fetch` patterns in [2.31](../plans/2.31-just-ask-summary-history.md). **🚫** Slash `/compact` — we do not support slash commands.

#### What Agent Pi will do

- **Trigger / cutoff:** when context token usage crosses a threshold, compact. Keep a recent tail (~Pi `keepRecentTokens`, default ~20k). Older path entries are **omitted from the next LLM context**. **🚫** Compact after every turn. **🚫** Manual slash compact.
- **Summary blob:** one structured checkpoint (copy/derive Pi’s compaction sections → Agent Pi–owned prompt under `pi-prompts/`; Phase 8 if copying text):
  - Goal
  - Constraints & Preferences
  - Progress (Done / In Progress / Blocked)
  - Key Decisions
  - Next Steps
  - Critical Context
  - Later compacts **update** prior summary (Pi `<previous-summary>` style) rather than starting from scratch; append read/modified file lists from tool ops where useful.
- **Reference tags (required add-on):** summarizer input includes headed turn rows with hash links (`[#user-N](#user-N)`, `[#think-N](#think-N)`, `[#agent-N](#agent-N)`, `[#tool-N](#tool-N)`) and an **Allowed references** set. Checkpoint text **must cite** relevant tags so the main agent can recover detail. Validate emitted links (retry once) — same discipline as Chatter’s summarizer contract.
- **History recall:** main agent always has **`session_fetch`** (tag like `user-1` / `tool-6`, or `"index"`) to load the **exact** stored message for anything dropped from context. Continuity = checkpoint + recent tail + on-demand fetch — **not** “hope it fit in the summary.”
- **Model sees after compact:** system/checkpoint (with tags) + recent tail (+ current turn). Full UI history can remain; API context is cut.
- **Prompts:** Agent Pi–owned summary template + any follow-up / tool-hint copy that tells the model to use tags + `session_fetch`. **🚫** Point Agent Pi at `chatter_summary.md` “for now.” **🚫** Ship a throwaway summary prompt we expect to delete.
- **Code:** Reuse `OLLMchat.Agent.Summarizer`; Agent Pi sets **`prompt_base_dir`** / **`prompt_filename`** when constructing it. Threshold / assembly live in Agent Pi (see **Code plan**).
- **ℹ️** Exact threshold / `keepRecentTokens` / whether summary is a `summary` role row vs system inject — **💩** at implement.

#### Code plan

Edits are **Remove** / **Replace with** / **Add** from the tree;
verify surrounding context before applying.

- **🔷** Reuse `OLLMchat.Agent.Summarizer` (no second summarizer class).
- **🔷** Template location = **`prompt_base_dir`** + **`prompt_filename`** on `Summarizer`, set when the agent constructs it — pass straight into `Prompt.Template` (no path splitting).
- **🔷** Defaults: `chat-prompts` + `chatter_summary.md` (Chatter / Coding Assistant unchanged at call site).
- **🔷** Agent Pi: `new Summarizer(agent) { prompt_base_dir = "pi-prompts", prompt_filename = "compact.md" }`.
- **🔷** `⏳` Agent Pi trigger = token threshold (not every turn); assembly uses `create_summary()` — fences for PendingMessage/Agent when that slice is locked.
- **💩** `⏳` Extra `Summarizer.run` slice options (A→B / keep-recent-tail) — only if one-turn fold under threshold is not enough.
- **ℹ️** `session_fetch` already exists; ensure not in Agent Pi `forbidden`.
- **🚫** `Factory.load_summary_prompt` (or any new Factory/Summarizer helper method for loading).
- **🚫** Single combined path string that we split on `/`.

### 5a. `libollmchat/Agent/Summarizer.vala` — `prompt_base_dir` / `prompt_filename`

**✔️** Applied.

**Where:** class body — properties near the top with the other fields.

**Depends on:** none.

#### Add — immediately after `private static GLib.Regex hash_ref_regex;`.

```vala
		/**
		 * Gresource pack for the summary template (e.g. ''chat-prompts'').
		 */
		public string prompt_base_dir { get; set; default = "chat-prompts"; }

		/**
		 * Summary template filename within {@link prompt_base_dir}.
		 */
		public string prompt_filename { get; set; default = "chatter_summary.md"; }
```
### 5b. `libollmchat/Agent/Summarizer.vala` — `run`: pass properties into `Prompt.Template`

**✔️** Applied.

**Where:** `run` — inside the `try` at the start of each validation attempt, where `Prompt.Template` is constructed and `load()`’d.

**Depends on:** §5a.

#### Remove
```vala
					var tpl = new Prompt.Template("chatter_summary.md") {
						source = "resource:///",
						base_dir = "chat-prompts"
					};
					tpl.load();
```

#### Replace with — same `Prompt.Template` construction, values from properties.
```vala
					var tpl = new Prompt.Template(this.prompt_filename) {
						source = "resource:///",
						base_dir = this.prompt_base_dir
					};
					tpl.load();
```

### 5c. Add `resources/pi-prompts/compact.md`

**✔️** Applied (Pi section headings + hash-link / `session_fetch` rules).

**Where:** new file beside `resources/pi-prompts/initial.md`.

**Depends on:** Phase 8 if text is derived from Pi.

- **🔷** `⏳` Sections: Goal; Constraints & Preferences; Progress; Key Decisions; Next Steps; Critical Context; update prior summary; cite only allowed `#user-N` / `#think-N` / `#agent-N` / `#tool-N`; tell model to use `session_fetch` for exact recall.
- **💩** `⏳` Exact markdown body — draft at implement (copy/derive Pi compact prompt + Chatter reference rules); show full **Add** fence before apply.

### 5d. `resources/gresources.xml` — register `compact.md`

**✔️** Applied.

**Where:** `<gresource prefix="/pi-prompts">` block.

**Depends on:** §5c file exists.

#### Add — immediately after `<file>initial.md</file>` inside the pi-prompts gresource.
```xml
    <file>compact.md</file>
```

### 5e. Agent Pi outbound + when to summarize

**✔️** Applied in `PendingMessage`: `create_summary()` inject + threshold (`ctx - 16384`, estimate `content.length / 4`); Summarizer with `pi-prompts` / `compact.md`. Compact failure is warned, does not fail the chat turn.
- **💩** Exact threshold / char÷4 estimate — revisit if token metering improves.

### Phase 6 / 7 / 9 — moved

- **ℹ️** Urgent / follow-up (agent + UI): [06](06-urgent-follow-up.md).
- **ℹ️** Project-summary tool: [07](07-project-summary-tool.md).
- **ℹ️** Offer to create `AGENTS.md`: [09](09-offer-agents-md.md).

### Phase 8 — Licenses + inventory (required with Phase 3)

Pi harness is **MIT** (Copyright Mario Zechner — upstream `LICENSE`). MIT requires preserving copyright + permission notice in copies/substantial portions.

**✔️ Locked with Phase 3 Option A** — copy/derive prompt text; attribution required.

**✔️ Format locked:** no CycloneDX. Inventory = [`licenses/README.md`](../../licenses/README.md): project is **LGPL-3.0 except** the listed paths.

- **✔️** `licenses/pi-coding-agent/LICENSE` — upstream MIT text.
- **✔️** `licenses/README.md` — exception table + component note (bill of materials).
- **✔️** Top-level `README.md` License section points at `licenses/`.
- **✔️** Derived prompt listed: `resources/pi-prompts/initial.md` (+ `resources/pi-prompts/NOTICE`).
- **🚫** Do not copy Pi code/prompts without the MIT notice nearby (`licenses/pi-coding-agent/LICENSE` + table row).


---

## Out of this plan

- **🚫** Skill.Runner / old `Skill.Manager` crossover for Pi skills.
- **🚫** Using `resources/skills/*.md` (refine/execute) as Skill sources.
- **🚫** npm / `pi install` / Node package gallery as skill distribution.
- **🚫** Parallel tool execution as a goal.
- **🚫** Pi extensions / packages / TUI / RPC.
- **ℹ️** Pi-style exact **`edit`** (old/new text in args) — later phase after current tool surface; not in this hunk set.

---

## Suggested order

1. Phase 0 — `AgentPi` / `agent-pi` factory (chat-only; full transcript until Phase 5)  
2. Phase 1 — AGENTS.md (global + home-capped parent walk + inject; omit if missing)  
2.5. Phase 1.5 / Phase 4 — tool names (`read` / `write` / `bash` + forbid) — **✔️**  
3. Phase 2 — Skill loader + catalog — **✔️**  
3.5. Phase 2.1 — base skill pack (`resources/pi-skills/` or equivalent; no npm)  
4. Phase 3 — copy/derive Pi system prompt (**update** `licenses/README.md` exception table)  
5. Phase 5 — compact on threshold (Pi template) + reference tags + `session_fetch`  
6. [06](06-urgent-follow-up.md) — urgent/follow-up (6a agent, then 6b UI)  
7. [07](07-project-summary-tool.md) — project-summary tool  
8. [09](09-offer-agents-md.md) — offer to create `AGENTS.md`  
9. After [09](09-offer-agents-md.md) — AGENTS inject soft-cap as a % of active model context  

---

## LLM notes

- **ℹ️** Study: [01-pi-agent.md](01-pi-agent.md); siblings [03](03-base-skills.md), [04](04-pi-harness-what-it-actually-does.md), [06](06-urgent-follow-up.md), [07](07-project-summary-tool.md), [09](09-offer-agents-md.md).
- **ℹ️** Pi skill load: `packages/coding-agent/src/core/skills.ts` (`loadSkillFromFile`, `formatSkillsForPrompt`); docs `packages/coding-agent/docs/skills.md`.
- **ℹ️** Chatter kernel: `libollmchat/Chatter/`, [2.31](../plans/2.31-just-ask-summary-history.md).
- **ℹ️** liboccoder weight: `OLLMcoder.AgentFactory`, `OLLMcoder.Skill.Factory`.
- **🔷** Namespace **`OLLMcoder.AgentPi`**; agent id **`agent-pi`**; title **`Agent Pi`**; `long_title` **`implementation of the Pi agent harness`**.
- **ℹ️** Pi license: MIT — vendored at [`licenses/pi-coding-agent/LICENSE`](../../licenses/pi-coding-agent/LICENSE); exception list in [`licenses/README.md`](../../licenses/README.md).
- **🚫** Do not use `OLLMcoder.Skill.Manager` for Skill.
- **🚫** Do not merge this agent into Skill.Runner.
- **🚫** Do not copy Pi prompts without listing them in `licenses/README.md` and keeping the MIT text under `licenses/pi-coding-agent/`.
