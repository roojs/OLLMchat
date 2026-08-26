# 6.1.12 Write `AGENTS.md` skill

Status: ⏳ proposed

> **`docs/plans/CODER-1.0-summary.md` is not updated** for this sub-plan until it is done and archived.

ℹ️ Checklist: `docs/guide-to-writing-plans.md` — Checklist for plans.  
ℹ️ Parent: [6.1](CODER-6.1-agent-pi.md). Inject today: [done/6.1.2](done/6.1.2-DONE-pi-like-agent.md) Phase 1.  
ℹ️ Banner offer: [6.1.9](CODER-6.1.9-offer-agents-md.md). Default offer list: [6.1.10](CODER-6.1.10-skills-configuration.md).  
ℹ️ Indexed summary: [done/6.1.7](done/6.1.7-DONE-project-summary-tool.md) (`codebase_search` `element_type = "project"`).  
ℹ️ Wiki skill (separate plan): [5.5](APP-5.5-wiki-maker.md).

## Purpose

- 🔷 `⏳` Ship an Agent Pi skill that **creates and refreshes** project-root `AGENTS.md`.
- 🔷 `⏳` When the project has no `AGENTS.md`, the agent must be told to **run that skill** and make one (not wait for the user to ask, not dump a canned stub).
- 🔷 `AGENTS.md` is the always-on standing contract (already injected). Keep it **short**. Deep material lives elsewhere and is linked, not copied.
- 🔷 The file must carry: a **brief** project summary, how to fetch the **thorough** indexed summary, whether that summary is **complete**, **when it was created**, **when to update it**, standing **working requirements** (not “preferences”), and **where things are found**.
- 🔷 Wiki (`docs/wiki/`) is the LLM’s **memory**. Plans / bugs / human docs have their own trees. Retrieve from the wiki **first** when it exists.
- ℹ️ Assessment of public “write AGENTS.md” skills is in **Existing skills** below. We do **not** vendor any of them wholesale.

---

## Concept

- 🔷 **`AGENTS.md`** (project root) — always inlined. Map + standing requirements + pointers. Paid for every turn, so stay lean.
- 🔷 **`writing-agents-md` skill** — procedure to write or refresh that file. Progressive disclosure: catalog line always; body only when the model `read`s it.
- 🔷 **Indexed project summary** — detailed overview via `codebase_search` with `element_type = "project"`. Not a substitute for `AGENTS.md` ([done/07](done/6.1.7-DONE-project-summary-tool.md) already forbids pasting it into `{agents_md}`).
- 🔷 **`docs/`** — human project documentation.
- 🔷 **`docs/plans/`** — implementation plans (`done/` when archived).
- 🔷 **`docs/bugs/`** — bug investigations (`done/` when fixed). See `docs/bug-fix-process.md`.
- 🔷 **`docs/wiki/`** — LLM memory. Build/read is the **wiki skill** in [5.5](APP-5.5-wiki-maker.md), not this plan.
- 💩 Skill folder name **`writing-agents-md`** (matches `writing-plans`). Rename if you prefer `write-agents-md` / `agents-md`.

---

## Missing file → run the skill

Phase 1 today **omits** `{agents_md}` when nothing is found. That is no longer enough.

- 🔷 `⏳` If the **project root** has no `AGENTS.md` (and no `CLAUDE.md` to inject instead), the host must **tell the model** to `read` `writing-agents-md` and create the file before substantial work.
- 🔷 This is the “tool that says: you don’t have one, run this.”
- 🚫 Do **not** add a new Vala `BaseTool` for this.
- 🚫 Do **not** write a packaged stub body and call it `AGENTS.md` ([6.1.9](CODER-6.1.9-offer-agents-md.md) stub is out).
- 💩 Host hint is a short block from `Factory.build_agents_md` when project-root context file is missing (still emit ancestor / global files if those exist).
- 💩 Also one sentence on the existing `codebase_search` tool description (already “mandatory when starting work on a project”).
- 💩 Banner Create in [6.1.9](CODER-6.1.9-offer-agents-md.md) starts this skill path (user message / agent turn), not a template write.

Hint copy (host, not a fake agents file):

```
<missing_project_agents>
This project has no AGENTS.md at the project root.
Read the writing-agents-md skill and create one before substantial work.
</missing_project_agents>
```

- ℹ️ Global `~/.local/share/ollmchat/AGENTS.md` does **not** count as the project file. Hint still fires if only the global exists.
- 💩 CLAUDE-only at project root: inject already works; do not hint. Creating `AGENTS.md` beside it stays the [6.1.9](CODER-6.1.9-offer-agents-md.md) edge case.

---

## `AGENTS.md` content contract

What the skill must write. Omit empty sections. Do not turn this into a README.

### Brief summary + thorough fetch

- 🔷 Short project summary (a few sentences). Purpose, stack, layout — not a tour.
- 🔷 Point at the thorough indexed summary: `codebase_search` with `element_type = "project"` (no query).
- 🔷 Record whether that indexed summary was **complete** when this file was written.
  - Complete — indexer had a real `project_description`.
  - Incomplete / missing — tool returned empty / “No project summary is indexed yet”.
- 🔷 If incomplete or missing: say so, and tell later agents to **call `"project"` again** and refresh the brief once it exists.
- ℹ️ Today completeness is the empty vs non-empty `project_description()` string ([`ollmfilesd/Codebase.vala`](../../ollmfilesd/Codebase.vala) already replies “No project summary is indexed yet”).
- 💩 No new completeness API in this plan. Empty tool reply is the signal.

### Created date

- 🔷 Record **when** the file was created (ISO date).
- 💩 On refresh, keep created date; add **Last updated: YYYY-MM-DD**.

### Standing requirements (refresh focus)

- 🔷 This is **not** a “user preferences” dump.
- 🔷 Record how the user **actually works** with agents on this repo — standing requirements that later sessions must not rediscover.
- 🔷 Example: the user usually requires the coding standard to be followed, so that belongs here as essential, not optional flavour.
- 🔷 On **refresh**, prefer adding/tightening these over rewriting the map.

### When to update

- 🔷 Update when the user **guided you to do the work a certain way** and you had done (or were about to do) it differently.
- 🔷 Write the correction as a standing requirement so future agents follow it.
- 🔷 Also update when the indexed summary becomes complete, or the “where things live” map is wrong.
- 💩 Do not refresh on every turn. Do not grow the file with one-off task notes.

### Where things are found

- 🔷 A short map, not a directory tree.
- 🔷 Plans → `docs/plans/` (archived → `docs/plans/done/`).
- 🔷 Bugs → `docs/bugs/` (fixed → `docs/bugs/done/`). Follow `docs/bug-fix-process.md`.
- 🔷 Human project docs → `docs/` (not the wiki).
- 🔷 LLM memory → `docs/wiki/` (see **Wiki as memory**).
- 💩 Optional extra pointers only when they prevent real mistakes (e.g. `docs/coding-standards-router.md` before Vala edits). Link, don’t paste.

### Keep it lean

- 💩 Target under ~80 lines. Hard cap ~120.
- 🚫 Kitchen-sink setup / test / PR / deployment sections unless a command is **non-obvious** and not in the indexed summary.
- 🚫 Copying README, wiki pages, or the full `project_description` into `AGENTS.md`.
- 🚫 Generic advice (“write clean code”, “add tests”).

---

## Wiki as memory

[5.5](APP-5.5-wiki-maker.md) is the wiki **skill** (build / read under `docs/wiki/`). This plan only locks what **`AGENTS.md` tells agents** about it.

- 🔷 Wiki is the LLM’s **memory space**, not human product docs.
- 🔷 Human-facing project documentation stays in **`docs/`**.
- 🔷 Durable work product still goes to the right tree:
  - plans → `docs/plans/`
  - bugs → `docs/bugs/`
  - wiki pages → `docs/wiki/` (findings, maps, distilled memory)
- 🔷 When asked for project information, **check the wiki first** if `docs/wiki/` exists (start at `docs/wiki/index.md`, then follow links / wiki-read skill).
- 🔷 If it is not there, then search code / `docs/` / plans / bugs as today.
- ℹ️ [5.5](APP-5.5-wiki-maker.md) already wanted wiki as first port of call for coding prep. `AGENTS.md` is how Agent Pi **always** sees that rule.
- 💩 Until 5.5 ships, the map still names `docs/wiki/`. If the tree is absent, do not invent wiki pages from this skill — point at 5.5 / say memory is not built yet.
- 🚫 This plan does not implement `wiki_build` / `wiki_read`.
- 🚫 Do not paste wiki content into `AGENTS.md`. One line: memory lives there; retrieve first.

What belongs where (for the skill’s “where things live” section):

- 🔷 **Wiki** — distilled, linkable memory the model wrote for later models (architecture notes, “how X works”, entity pages). Update via wiki skill when that exists.
- 🔷 **Plans** — executable / reviewable design for a change. Not a scratchpad.
- 🔷 **Bugs** — reproduce, evidence, root cause. Not a chat log.
- 🔷 **`docs/`** — docs a human would read (standards, build, how the product works).
- 💩 If the user asked to remember something that is not a plan, not a bug, and not human docs → wiki (once 5.5 exists). Until then, a standing requirement in `AGENTS.md` is acceptable only if it must be always-on.

---

## Skill workflow

Packaging: `resources/pi-skills/writing-agents-md/SKILL.md`, gresource `/pi-skills`, same scan as [done/03](done/6.1.3-DONE-base-skills.md).

- 🔷 `⏳` Default **offered** (add to [6.1.10](CODER-6.1.10-skills-configuration.md) seed). Critical enough to be in the catalog.
- 🔷 Tools: `read`, `write`, `codebase_search`, `bash` as needed. Ask in chat when the project root is unclear.

### Create

1. Confirm project root (active project / `{cwd}`).
2. If `AGENTS.md` already exists → **refresh** path, do not blind-replace.
3. `codebase_search` `element_type = "project"`. Note complete vs missing.
4. Skim only what the map needs: README opening, `docs/` layout, whether `docs/wiki/`, `docs/plans/`, `docs/bugs/` exist.
5. Write project-root `AGENTS.md` from the contract above.
6. Tell the user it was created; next send will inject it.

### Refresh

1. Read the existing file. Keep created date and still-valid standing requirements.
2. Focus on:
   - new standing requirements from **this session’s corrections**
   - completeness of the indexed summary
   - broken “where things live” pointers
3. Do not rewrite the brief summary unless it is wrong or was written while the index was empty.

- 💩 Show a short diff summary in chat after refresh (not a second copy of the file).

---

## Existing skills (assessment)

Looked at public skills that write `AGENTS.md`. None match this contract. Do not vendor them.

### `create-agentsmd` (github/awesome-copilot)

- ℹ️ https://github.com/github/awesome-copilot/blob/main/skills/create-agentsmd/SKILL.md
- Kitchen-sink “README for agents”: overview, setup, workflow, testing, style, build, PR.
- Follows https://agents.md/ sample shape.
- **Vs us:** too long for always-on inject. No indexed-summary completeness. No standing-requirements / correction loop. No wiki-first memory map.
- 🚫 Do not use as the template.

### `create-agents-md` (alexmandrikdev/agent-skills)

- ℹ️ https://github.com/alexmandrikdev/agent-skills/blob/main/create-agents-md/SKILL.md
- Lean (30–80 lines, cap ~120), tool-agnostic, commands over prose, surgical update vs rewrite.
- Auto-update when the **agent’s own** changes stale the file.
- **Vs us:** closest on **length**. Still command-centric. No project-summary tool, no completeness bit, no “user corrected you” standing requirements, no wiki/plans/bugs split.
- 💩 Steal: lean cap, surgical refresh, don’t copy README.

### `agents-md-generate` (walterfan/lazy-rabbit-skills)

- ℹ️ https://github.com/walterfan/lazy-rabbit-skills/blob/master/skills/agents-md-generate/SKILL.md
- `AGENTS.md` as operating map + **links**; deep text stays in `docs/` / PKB.
- “Keeping Current” + learning loop after user corrections.
- Bash discover script, templates, optional `CLAUDE.md` / `GEMINI.md` symlinks.
- **Vs us:** closest on **link-out** and **update after corrections**. Extra harness (scripts, symlinks, multi-tool ask) we don’t want. No indexed summary / wiki-as-memory.
- 💩 Steal: link don’t copy; keep-current after corrections.
- 🚫 Symlinks / “which AI tool?” interview.

### `agent-init` (kvokov/oh-my-ai)

- ℹ️ https://github.com/kvokov/oh-my-ai/blob/main/skills/agent-init/SKILL.md
- Discoverability filter: only what agents **cannot** learn from the repo. Forbids stack, architecture, directory overviews, and generic “follow the coding style.”
- Strong on landmines and hidden commands.
- **Vs us:** **conflicts**. We **want** a brief summary, a map, and standing requirements such as “coding standards are essential.” Those would fail their quality gate.
- 💩 Optional **Landmines** bullets if something is truly hidden.
- 🚫 Do not adopt discoverability-only as the whole philosophy.

### Official `AGENTS.md` spec

- ℹ️ https://agents.md / https://github.com/agentsmd/agents.md
- Flexible markdown, no required fields. Typical samples are commands / tests / PR.
- **Vs us:** we keep the **filename and always-on convention**. We do not take their sample sections as mandatory.

### SKILL.md vs AGENTS.md (ecosystem)

- ℹ️ Common split (e.g. localskills.sh): `AGENTS.md` = always-on facts and boundaries; `SKILL.md` = on-demand procedure.
- 🔷 That split is correct here: this skill is the procedure; the file it writes is the contract.
- ℹ️ Wiki skill ([5.5](APP-5.5-wiki-maker.md)) is also a procedure. Wiki **pages** are memory, not always-on.

---

## Host wiring

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `liboccoder/AgentPi/Factory.vala` — `build_agents_md`: missing-project hint

**Why:** Model must be told to run `writing-agents-md` when project-root has no agents file.

**Where:** `build_agents_md` — after collecting path blocks, before the empty/`project_context` return.

**Depends on:** skill name locked.

#### Add — Immediately before today’s `if (blocks.length == 0) return "";`. Append a missing-project hint when the project root has neither `AGENTS.md` nor `CLAUDE.md`. Empty return still applies only when there are no blocks at all (no project path).

```vala
			var project_root_has_agents = false;
			if (project != "") {
				var root_prefix = project;
				if (root_prefix.has_suffix(GLib.Path.DIR_SEPARATOR_S)) {
					root_prefix = root_prefix.substring(
						0,
						root_prefix.length - GLib.Path.DIR_SEPARATOR_S.length);
				}
				root_prefix = root_prefix + GLib.Path.DIR_SEPARATOR_S;
				if (GLib.FileUtils.test(root_prefix + "AGENTS.md", GLib.FileTest.EXISTS)
					|| GLib.FileUtils.test(root_prefix + "CLAUDE.md", GLib.FileTest.EXISTS)
				) {
					project_root_has_agents = true;
				}
			}
			if (!project_root_has_agents && project != "") {
				blocks += "<missing_project_agents>\n"
					+ "This project has no AGENTS.md at the project root.\n"
					+ "Read the writing-agents-md skill and create one before substantial work.\n"
					+ "</missing_project_agents>";
			}
```

ℹ️ Place this immediately before today’s `if (blocks.length == 0) return "";`. Keep the existing `<project_context>` wrap for the joined blocks.

### 2. `liboccoder/AgentPi/Factory.vala` — `register_config` seed

**Why:** Skill must be in the default offered catalog.

**Where:** `skills.add_all_array` in `register_config`.

**Depends on:** §1 skill name.

#### Add — After `"webpage-reader",` in the seed array.

```vala
					"writing-agents-md",
```

### 3. `resources/gresources.xml` — pack the skill

**Why:** Resource scan picks up `/pi-skills/writing-agents-md/SKILL.md`.

**Where:** `<gresource prefix="/pi-skills">` file list.

**Depends on:** §4 file exists.

#### Add — After `debug-review/SKILL.md`.

```xml
    <file>writing-agents-md/SKILL.md</file>
```

### 4. `resources/pi-skills/writing-agents-md/SKILL.md` — new skill

**Why:** Procedure the model `read`s.

**Where:** new folder beside the other pi-skills.

**Depends on:** none.

#### Add — New file. Full contents:

~~~markdown
---
name: writing-agents-md
description: >
  Create or refresh the project-root AGENTS.md standing contract.
  Use when the project has no AGENTS.md, when the host reports
  missing_project_agents, or when this session’s corrections should
  be recorded for later agents.
license: MIT
---

# Writing AGENTS.md

## Purpose

Write a **short** project-root `AGENTS.md` that later Agent Pi sessions
always inject. Map + standing requirements + pointers. Not a README.
Not a wiki dump.

## When to Use

- Project root has no `AGENTS.md` (including a `missing_project_agents` hint)
- User asks to create or refresh agent instructions
- The user corrected you, or required a different approach than you took —
  record that as a standing requirement
- The brief summary was written before the indexed project summary was complete

## Tools

- `codebase_search` — `element_type` `"project"` for the thorough indexed summary
- `read` / `write` / `bash` — layout check and file write
- Ask in chat if the project root is unclear

## Workflow

1. Confirm the project root. If `AGENTS.md` exists, refresh (below); do not blind-replace.
2. Call `codebase_search` with `element_type` `"project"` (no query).
   - Non-empty summary → **complete**
   - Empty / “not indexed yet” → **missing** (or incomplete). Say so in the file.
3. Check whether `docs/`, `docs/plans/`, `docs/bugs/`, `docs/wiki/` exist. Do not invent them.
4. Write `AGENTS.md` at the project root using the skeleton. Keep it under ~80 lines (cap ~120).
5. Tell the user. The next send injects the file.

### Refresh

- Keep **Created** and still-valid standing requirements.
- Set **Last updated** to today.
- Prefer adding standing requirements from **this session’s corrections**.
- Re-fetch `"project"` if the file still says the indexed summary was missing.
- Do not rewrite the map unless it is wrong.

## Skeleton

```markdown
# AGENTS.md

Created: YYYY-MM-DD

Indexed summary: complete | missing (as of YYYY-MM-DD)

## Project

<2–4 sentences. Not a tour.>

Thorough overview: codebase_search with element_type "project" (no query).
If indexed summary is missing, call that again before relying on this brief.

## Where things live

- `docs/` — human project documentation
- `docs/plans/` — implementation plans (`docs/plans/done/` when archived)
- `docs/bugs/` — bug investigations (`docs/bugs/done/` when fixed)
- `docs/wiki/` — LLM memory. If this tree exists, retrieve from it **first**
  when asked about the project (start at `docs/wiki/index.md`).
  Do not put human docs or plans/bugs here.

## Standing requirements

<How the user actually works on this repo. Example: coding standards
are required, not optional. Not a preferences dump.>

## Update this file when

- The user guided you to do the work a different way than you did
- Record that requirement so later agents follow it
- The indexed summary becomes complete, or this map is wrong
```

## Critical rules

- Brief summary only. Thorough text stays behind `element_type` `"project"`.
- Wiki is memory; `docs/` is human docs; plans and bugs have their own trees.
- Check wiki first when it exists. Do not paste wiki pages into this file.
- Do not create `docs/wiki/` from this skill.
- Do not copy README or the full project summary.
- Do not add generic advice or kitchen-sink setup/test/PR sections.
- Standing requirements are essential working rules, not “user preferences.”
~~~

### 5. `liboctools/CodebaseSearch/Tool.vala` — `description` one-liner

**Why:** Start-work tool already mandatory for `"project"`; point at the skill when `AGENTS.md` is missing.

**Where:** `description` getter, after the `"project"` paragraph.

**Depends on:** §4.

#### Add — After “No query is needed in that mode.”

```
If the project has no AGENTS.md, read the writing-agents-md skill and create one
before relying on a brief standing contract.
```

### 6. [6.1.10](CODER-6.1.10-skills-configuration.md) — default offered list

**Why:** Seed in Settings matches Factory.

**Where:** Recommended initial set + any duplicated name lists in that plan.

#### Add — `writing-agents-md` next to `research-codebase` / `debug-review` (on by default).

---

## Suggested order

1. 🔷 Lock skill name + content contract + wiki-as-memory wording.
2. 🔷 `⏳` Add `SKILL.md` + gresource.
3. 🔷 `⏳` Missing-project hint in `build_agents_md`.
4. 🔷 `⏳` Default offer seed ([10](CODER-6.1.10-skills-configuration.md) + Factory).
5. 💩 `⏳` `codebase_search` description line.
6. 🔷 `⏳` Point [6.1.9](CODER-6.1.9-offer-agents-md.md) Create at this skill (no stub).
7. ℹ️ Wiki build/read remains [5.5](APP-5.5-wiki-maker.md).

---

## LLM notes

- ℹ️ Agent id `agent-pi`. Skill format: [agentskills.io](https://agentskills.io/).
- 🚫 Do not implement [5.5](APP-5.5-wiki-maker.md) here.
- 🚫 Do not vendor the public skills in **Existing skills**.
- 🚫 Do not paste `project_description()` into always-on inject.
- 🚫 Do not add a new tool name.
- ℹ️ Soft-cap for AGENTS inject size remains the later item on [done/02](done/6.1.2-DONE-pi-like-agent.md) after this file exists and stays short.
