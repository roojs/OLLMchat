# Skills page: AgentConfig null criticals on settings open

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✅ FIXED — user closed 2026-09-02 (Settings → Skills, no criticals)

**Started:** 2026-08-05

---

## Problem

🔷 Opening Settings logs criticals:

```text
oll_mchat_settings_agent_config_get_skills: assertion 'self != NULL' failed
oll_mapp_settings_dialog_rows_skill_row_fill: assertion 'offered != NULL' failed
```

(once per skill row). Skills toggles cannot bind to offered list.

🔷 Same session also floods debug from `ToolRow.vala` property introspection
(separate, trivial — remove leftover `GLib.debug` lines).

---

## Evidence

- ✔️ Critical stack maps to `SkillsPage.load_skills` →
  `skill_row.fill(this.agent_skills.skills)` when `agent_skills` is null.
- ✔️ `SkillsPage` ctor caches `config.agents.get("agent-pi")` once.
- ✔️ Window builds Settings in ctor **before**
  `AgentPi.Factory.register_config` (mid-`initialize_client`).
- ✔️ Initialize can open Settings before that too.
- ℹ️ Tools seed at Application startup; Agent Pi config does not.

---

## Root cause

✔️ **Agent Pi `register_config` runs only when the factory is registered**
(mid-`initialize_client`), so `agents["agent-pi"]` is missing when SkillsPage
is constructed in the Window ctor.

---

## How other agents do it

ℹ️ **None** call `register_config` from Application. Pattern: call it **next to
`agent_factories.set`**, when that factory is first created.

- **JustAsk** — earliest: `History.Manager` ctor →
  `just_ask_agent.register_config(config, this.tools)` (tools often still
  empty). Uses **base** `register_config` (seed `agents[name]` only; no asserts).
- **CodeAssistant** — `Window.initialize_client` after `fill_tools` →
  `code_assistant.register_config(...)`. Base seed only (no override).
- **Agent Pi** — same place as CodeAssistant. **Only override**: seed skills +
  `GLib.error` if write/read/bash missing.
- **SkillRunner** — same place. Base seed only.
- **Chatter** — `register_default_agents()` right after those. Base seed only.

ℹ️ Base `Agent.Factory.register_config` is safe with an empty tools map.
Agent Pi’s override is the outlier (tool asserts).

ℹ️ SkillsPage is also an outlier: it reads `agents["agent-pi"]` in the
**Settings ctor**, before any of the above run. ToolsPage does **not** do that —
it binds `history_manager` in `load_tools` when the dialog is shown.

---

## Proposed fix (pick direction)

### A — Match peer timing; fix SkillsPage bind (aligned with ToolsPage)

🔷 Keep `register_config` where peers call it (beside factory registration).
Bind `agent_skills` in `load_skills` (called from `show_dialog`), not ctor.

#### Remove — `SkillsPage` ctor.

```vala
			this.agent_skills = this.dialog.app.config.agents.get("agent-pi");
```

#### Add — start of `load_skills`.

```vala
			this.agent_skills = this.dialog.app.config.agents.get("agent-pi");
```

### B — Application early call (diverges from peers)

💩 Special-case Agent Pi at Application startup (throwaway Factory, empty
tools, soft-skip asserts). Not how JustAsk / CodeAssistant / Chatter do it.

(Fences for B deferred unless chosen.)

### C — ToolRow debug (either way)

#### Remove — `ToolRow.introspect_config_properties`.

```vala
			GLib.debug("Introspecting properties for config class: %s", this.config.get_class().get_type().name());
			foreach (var pspec in this.config.get_class().list_properties()) {
				GLib.debug("Found property: %s (type: %s)", pspec.get_name(), pspec.value_type.name());
```

#### Replace with

```vala
			foreach (var pspec in this.config.get_class().list_properties()) {
```

---

## SkillsPage / Window under A

ℹ️ Window `agent_pi.register_config(...)` unchanged.
ℹ️ Ctor no longer caches a null; `load_skills` runs after registration
(normal path). Initialize failure Settings opens before agents: still null if
Skills tab is shown that early — same class of gap as today for any
agent-config UI before `initialize_client`.

---

## Attempts / changelog

- ✔️ Application early-call proposed; peers do **not** do that.
- 🔷 **A** chosen (SkillsPage bind in `load_skills`).
- ✔️ Applied A + C 2026-08-05.

## Next

- ✅ User closed 2026-09-02.
