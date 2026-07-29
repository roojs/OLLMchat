# Study: Pi coding agent vs OLLMchat

Source checkout: `/home/alan/git/pi` (Pi agent harness — `@earendil-works/pi-agent-core`, `@earendil-works/pi-coding-agent`).

Focus: **how standing instructions and skills get into the model** — especially `AGENTS.md` and skill catalogs — and how that could map onto **JustAsk / Chatter** (and where Skill.Runner already has related slots). Mid-run message queuing is a solid requirement but not treated as the main lesson.

**Sensible comparison:** Pi’s free-form coding agent vs our tool-chat agents. Skill.Runner is a different product (host conductor); noted only where injection already exists.

---

## 1. What Pi is

A **minimal agent loop** plus a coding harness:

- **`pi-agent-core`**: stream LLM → tool calls → results → repeat until the model stops.
- **`pi-coding-agent`**: default tools `read` / `write` / `edit` / `bash`, system-prompt assembly (context files + skill catalog), sessions, compaction, extensions.

Philosophy: no built-in permission popups, plan mode, MCP, or sub-agents. Permissions are thin for an IDE (§8). The sharp idea for us is **prompt assembly**: what is always inlined, what is only a pointer, what the model must fetch.

---

## 2. Loop sketch (for orientation)

```
prompt(user)
  loop:
    [optional steer inject]
    stream assistant   // system already has AGENTS.md + skill blurbs
    if toolCalls → run → continue
    else if follow-ups → inject → continue
    else stop
```

Steer/follow-up and compaction are real (§9–§10). **AGENTS.md + skills** (§3–§6) are the interesting comparison.

---

## 3. AGENTS.md / CLAUDE.md — what Pi actually does

### Discovery

At session start (and on reload), Pi loads:

1. `~/.pi/agent/AGENTS.md` (global)
2. Every ancestor of cwd, walking toward filesystem root, for `AGENTS.md` or `CLAUDE.md`
3. cwd itself

Several files can apply (global + monorepo root + nested package). Order: global first, then outermost ancestor → cwd.

Trust: **context files load even before project trust**; project-local skills/extensions wait. AGENTS.md is “instructions,” not “run this package code.”

### Injection — always-on, **full text**

`buildSystemPrompt()` pastes **entire file contents** into the system prompt:

```text
<project_context>
Project-specific instructions and guidelines:

<project_instructions path="…/AGENTS.md">
…full markdown…
</project_instructions>
</project_context>
```

No progressive disclosure. A large AGENTS.md is paid for on every turn (unless `--no-context-files`, or you replace the prompt via `SYSTEM.md`).

Related files:

| File | Role |
|------|------|
| `AGENTS.md` / `CLAUDE.md` | Standing project/user instructions (appended) |
| `.pi/SYSTEM.md` or `~/.pi/agent/SYSTEM.md` | **Replace** default system prompt |
| `APPEND_SYSTEM.md` | Append without replacing |

### What it’s for

Pi’s own `AGENTS.md` is standing orders: tone, code-quality rules, which commands agents may run, git safety with concurrent sessions, etc. Always in force — not something the model opts into via `read`.

### What we do today

| Slot | Us | vs Pi |
|------|----|-------|
| Project text in prompts | `Folder.project_description()` → vector `ProjectAnalysis` blurb | Generated index summary, not a checked-in markdown contract |
| Coding standards | Skill.Runner tells the **task list** to add a research task | Delayed / soft; not auto-injected every turn |
| JustAsk | Tools + user turns; little project constitution | No AGENTS walk |
| Chatter | Conversation summary + `session_fetch` | Not project AGENTS |

Skill.Runner already has an injection placeholder (`{project_description}` in `task_creation_initial.md`), but the **payload** is indexer text, not “walk disk for `AGENTS.md` and always paste it.” Pi’s bet: **authors write the contract; harness always injects it.**

---

## 4. Skills in Pi — catalog cheap, body on demand

Symmetric contrast to AGENTS.md:

| Layer | In system prompt | Full body |
|-------|------------------|-----------|
| **AGENTS.md** | Full text always | Already there |
| **Skills** | Name + description + path only | Model `read`s `SKILL.md` |

Catalog shape:

```xml
<available_skills>
  <skill>
    <name>…</name>
    <description>…</description>
    <location>/abs/path/SKILL.md</location>
  </skill>
</available_skills>
```

Plus: “Read the full skill file when the task matches… resolve relative paths against the skill directory.”

Discovery: `~/.pi/agent/skills`, `.pi/skills`, `.agents/skills`, packages — Agent Skills–style `SKILL.md` (frontmatter + markdown; optional helper scripts via `bash`).

**Soft failure:** if the model never reads the skill, it freestyles. No host retry that “skill was applied.”

---

## 5. Our skills today (coder)

`OLLMcoder.Skill.Manager`:

1. Scan built-in gresource skills + `~/.local/share/ollmchat/skills/`
2. **Catalog** = `to_markdown()` → `- **name** - description` lines
3. Injected into task-creation / iteration system prompts as `{skill_catalog}`
4. Task list **must name a skill** from the catalog; `validate()` binds `Definition`
5. Host then injects **full** `skill.refine` / `skill.execute` into refine/executor/post-exec templates

So we already do Pi’s **catalog step** for Skill.Runner — but then we **host-bind** the full skill into structured stages. Pi stops at “here’s the menu; you go read.”

JustAsk / Chatter do **not** currently advertise that catalog or load skill bodies.

---

## 6. How we could use Pi’s pattern with our method

Three separable ideas. None requires becoming Pi’s loop.

### A. AGENTS.md (or equivalent) as standing context — JustAsk / Chatter / Runner

**Behaviour:** On project open / agent send, walk project root (and optionally ancestors / user global) for `AGENTS.md` / `CLAUDE.md` / maybe our own name. Inject full text into the system (or first user) template.

**Where to plug in:**

| Agent | Hook |
|-------|------|
| JustAsk | Factory / `system_message` (or a shared “project context” filler) before `chat_call.send` |
| Chatter | Same slot in `chatter_initial.md` / `chatter_followup.md` (beside summary) |
| Skill.Runner | Fill `{project_description}` with AGENTS.md **plus** or **instead of** vector blurb; or a new `{agents_md}` placeholder |

**Design choices:**

- Cap size / truncate with “full file at path X via read_file” if huge (Pi doesn’t; we might want to).
- Prefer project-root file over ancestor spam, or concatenate with clear path labels like Pi.
- Keep approvals unchanged — AGENTS.md is prompt text, not a permission bypass.

This is the closest “game changer” relative to today: standing orders without a research task.

### B. Soft skills on JustAsk / Chatter — Pi-style progressive disclosure

Reuse **our** skill files (or Agent Skills `SKILL.md` dirs) without Skill.Runner:

1. `Skill.Manager.scan()` (or a lighter catalog scanner).
2. Put `Manager.to_markdown()` (or XML like Pi) into JustAsk/Chatter system prompt: “available skills — use `read_file` / `session_fetch` / dedicated loader when relevant.”
3. Full body only when the model reads the skill path.

Loop stays `toolsReply`. Skills are **docs + optional scripts**, not refine/exec sections.

**Fit with Chatter:** catalog in system prompt; skill bodies recalled like other files; summary can hash-link a prior skill load if useful.

**Does not replace Skill.Runner** for conducted RAPIR workflows. It gives free-form agents the same “menu of playbooks” Pi has.

### C. Hybrid on Skill.Runner — keep host bind, optionally Pi-load extras

Runner already:

- catalogs skills for the planner
- host-injects refine/execute for the chosen skill

Possible additions without ditching the conductor:

1. **AGENTS.md into task creation** (A) so the planner doesn’t need a “find coding standards” task for the common case.
2. **Optional soft skills** in the catalog that are documentation-only (no refine/execute split) — planner may assign them; refine stage just pastes body (closer to Pi `read`).
3. Keep structured skills as today for tools/`write_file`/approval gates.

The interesting hybrid: **AGENTS.md always-on** + **structured skills for execution** + **soft skills for playbooks** on JustAsk.

### What not to copy blindly

- Pasting unbounded AGENTS.md every turn with no size policy.
- Relying on the model to `read` skills with no host check, if the skill encodes safety or required steps (our Runner exists partly because soft skills fail open).
- Treating Pi skills and `OLLMcoder.Skill` as the same type — same noun, different control plane (§5 vs §4).

---

## 7. Context growth (Pi compaction vs Chatter)

Same problem: next LLM call must not drown in history.

| | Pi | Chatter |
|--|----|---------|
| Trigger | Token threshold / `/compact` | After each turn (background) |
| Mechanism | Summarize older transcript span; keep recent tail | Rolling `summary` message + hash links; `session_fetch` for recall |
| Same loop? | Yes | Yes |

JustAsk without Chatter ≈ pre-compaction Pi (growing `messages`). Skill.Runner often uses **fresh short system+user** per phase — a third strategy, not the AGENTS/skills comparison.

---

## 8. Permissions

Pi: no popups; sandbox the process. We: writer approval, file review, tool flags, bwrap. **Keep ours.** Nothing to learn except that they deferred product-level approval.

---

## 9. Steer / follow-up (requirement, not the headline)

While the agent is busy:

| Action | When injected |
|--------|----------------|
| **Steer** (Pi: Enter) | After current tool batch, before next LLM call |
| **Follow-up** (Pi: Alt+Enter) | When the agent would otherwise stop |

“First-class queues” = those lists live **inside** the agent loop and are polled each turn — not only “UI waits until idle.”

Our Chatter FIFO is **whole turns** (chat then summarize), not between tool batches. Worth having as a requirement for JustAsk/Chatter later; not the main differentiator vs Pi’s skill/`AGENTS.md` story.

**Implement plan:** [06-steer-follow-up.md](06-steer-follow-up.md) (6a agent loop, 6b UI reserved).

---

## 10. Edit path (one line)

Pi: mutate inside tool args (`edit` exact replace / `write`). Us: often `edit_mode` + stream-captured fences. Orthogonal to skills/AGENTS.

---

## 11. Skill.Runner vs Pi

Weak scoreboard. Pi skipped host plan mode; Runner is that mode. Use Pi for **injection patterns** on free-form agents and for **AGENTS.md-as-contract**. Don’t use Pi to decide whether RAPIR/conductor is “correct.”

---

## 12. Practical takeaways

1. **AGENTS.md always-inlined** — clearest import: standing project instructions without a research task. Natural slots: JustAsk/Chatter system prompt; Skill.Runner `{project_description}` / new placeholder. Prefer over hoping the planner invents a standards task.
2. **Soft skill catalog on JustAsk/Chatter** — reuse `Skill.Manager.to_markdown()` + `read_file`. Same progressive-disclosure idea as Pi; stays in `toolsReply`. Does not require Runner.
3. **Runner skills stay host-bound** — catalog + full refine/execute inject is already stricter than Pi; keep for structured/mutating work. Optionally add AGENTS.md beside the vector blurb.
4. **Queuing** — good requirement; not the game changer.
5. **Permissions** — keep ours.
6. **Compaction** — Chatter already owns the JustAsk-adjacent answer; compare further there, not via Runner.

---

## 13. Source map

| Topic | Pi | OLLMchat |
|-------|----|----------|
| AGENTS / context files | `resource-loader.ts` `loadProjectContextFiles`; `system-prompt.ts` `<project_context>` | `Folder.project_description()` (vector); no AGENTS walk yet |
| Skill catalog in prompt | `formatSkillsForSystemPrompt` / coding-agent `formatSkillsForPrompt` | `Skill.Manager.to_markdown()` → `{skill_catalog}` |
| Full skill body | `read` tool | Runner templates: `skill.refine` / `skill.execute` |
| Loop | `agent-loop.ts` | `ChatBase.toolsReply` |
| Summary / compact | coding-agent compaction | `Agent.Summarizer`, `Chatter/*` |

---

## 14. One-line summary

**Pi:** always paste `AGENTS.md`; advertise skills as a menu and let the model `read` bodies — thin host, same tool loop.  
**Us today:** vector project blurb + (on Runner) catalog then **host-forced** skill sections; JustAsk has neither AGENTS nor soft skills.  
**Likely borrow:** AGENTS.md injection + optional soft skill catalog on JustAsk/Chatter; keep Runner’s hard bind for conducted work.
