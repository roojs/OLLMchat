# 6.1.4 What Pi’s “harness” actually does


> **DONE** — study archived. Parent: [`CODER-6.1-agent-pi.md`](../CODER-6.1-agent-pi.md).

Status: ⏳ study (not an implement plan)

ℹ️ Parent: [6.1.2](done/6.1.2-DONE-pi-like-agent.md). Prior: [6.1.1](CODER-6.1.1-DONE-pi-agent.md), [done/6.1.3](done/6.1.3-DONE-base-skills.md).  
ℹ️ Sources: `/home/alan/git/pi` (`pi-agent-core`, `pi-coding-agent` README Philosophy / Extensions); [Bitter Frontier profile](https://frontier.bitter.sh/profiles/pi-coding-agent/) (“harness that refuses to govern”).

## Purpose

- 🔷 Answer: if Pi claims to be a **harness**, what does it actually harness — beyond context cleanup and skill-catalog injection?
- 🔷 Clarify why that project is regarded as special when soft skills look ordinary.
- 🔷 Compare to our **Skill.Runner** conductor (real check/balance stages) vs Pi’s thin loop.
- 🔷 Decide whether urgent/follow-up ([06](done/6.1.6-DONE-urgent-follow-up.md)) is the missing “harness,” or whether we were looking for the wrong kind of harness.

---

## Verdict (read this first)

- ℹ️ **Pi does not harness model output quality.** No plan gate, no skill-was-followed check, no RAPIR stages, no host retry that “you skipped the skill.” Soft skills fail open ([01 §4](CODER-6.1.1-DONE-pi-agent.md#4-skills-in-pi--catalog-cheap-body-on-demand)).
- ℹ️ In Pi’s vocabulary, **harness ≈ substrate around the model**: LLM call → tool args validate → run tools → optional mid-run inject → compact context → repeat. Plus hooks so *you* can add governance as extensions.
- ℹ️ The famous bit is **refusal**: no baked-in permissions, plan mode, MCP, sub-agents, or todos. “Special” = minimal core + typed extension surface + packaging, **not** a smarter conductor than Skill.Runner.
- 🔷 Our Agent Pi so far (AGENTS inject, skill catalog, lean tools, threshold compact) is a fair port of the **coding-agent defaults**. It is **not** a port of a hidden output-checking layer — that layer does not exist in core.
- 🔷 Urgent/follow-up ([06](done/6.1.6-DONE-urgent-follow-up.md)) is real loop plumbing, still **not** output QA. Do **not** replace it with this study; keep it as later UX. This doc answers “why bother,” not “what to build next instead of urgent queues.”

---

## Two meanings of “harness”

| Sense | What people expect | Pi? | Our Skill.Runner? |
|-------|--------------------|-----|-------------------|
| **A. Governance / check-and-balance** | Host parses plan, binds skill, refine → execute → interpret, validates structure, retries bad output | **No** (by design) | **Yes** (that was the product) |
| **B. Substrate / Agent = Model + Harness** | Provider API, tool schemas, agent loop, session, context transform, extension hooks | **Yes** — this is what they sell | Partial — we already had `toolsReply` + tools + approvals |

- 🔷 User expectation (“harness should check and balance output”) = sense **A**.
- ℹ️ Pi marketing / `pi-agent-core` / “agent harness” monorepo name = sense **B**.
- ℹ️ External writeups call Pi *“the harness that refuses to govern, so the floor others build their rules on.”* Refusal is the thesis, not a missing feature list.

---

## Inventory: what core Pi actually does

### Sense B — substrate (real)

| Piece | What it does | Output QA? |
|-------|--------------|------------|
| **`pi-ai`** | Multi-provider stream / tool-call parsing | No |
| **`agent-loop`** | Stream assistant → if tools, run → else maybe follow-ups → stop | No |
| **Tool arg validate** | Schema/parse before execute (`validateToolArguments`) | Args only, not “was the edit good” |
| **`beforeToolCall`** | Hook can **block** a tool (extensions wire permission UI here) | Optional; empty in default CLI |
| **`transformContext`** | Prune / reshape messages before LLM | Context hygiene |
| **Urgent / follow-up queues** | Inject user text after tool batch / when about to stop | Mid-run UX, not QA |
| **Compaction** | Summarize older span; keep recent tail | Context hygiene |
| **Four tools** | `read` / `write` / `edit` / `bash` (+ extras in CLI) | Thin mutate surface |
| **System prompt assembly** | Role + tool one-liners + cwd + AGENTS full paste + skill menu | Prompt engineering |
| **Sessions / branch / TUI / RPC / SDK** | Product shell around the loop | Packaging |
| **Extensions API** | TS modules: events, `registerTool`, block tools, custom compact, commands | **Where sense A can live** — not shipped as core policy |
| **Skills / packages** | Soft `SKILL.md` + npm/git share | Docs + scripts; soft fail |

### Sense A — governance (absent in core)

- 🚫 No mandatory plan before edits.
- 🚫 No host bind of skill refine/execute sections.
- 🚫 No parse/validate of “task list” or “skill applied.”
- 🚫 No permission popups (docs: containerize or build extension).
- 🚫 No built-in MCP / sub-agents / plan mode / todos.

Philosophy (coding-agent README): extensible **so it doesn’t dictate workflow**; ask the agent or install a package for the missing pieces.

---

## Skills are not the special part

- ℹ️ Soft skills = catalog in prompt + model `read`s body. Same idea as Agent Skills / Claude skills / our Phase 2.
- ℹ️ Pi’s skill loader validates **frontmatter shape** (name/description), not runtime compliance.
- 🔷 If Agent Pi only ships a skill pack + injection, that alone does **not** explain Pi’s reputation.
- ℹ️ What *is* adjacent and more interesting: **extensions** (code hooks in the loop) vs **skills** (markdown playbooks). We skipped Pi extensions ([02 Out of this plan](done/6.1.2-DONE-pi-like-agent.md#out-of-this-plan)). That skip removes most of Pi’s “build your own governance” story.

---

## Why people still treat Pi as special

Not because it out-harnesses Skill.Runner on output control.

1. **Clear product thesis** — four tools, short system prompt, everything else opt-in.
2. **Extension platform** — typed lifecycle hooks without forking the agent (permissions, checkpoints, custom tools as *code*).
3. **Packaging** — `pi-ai` + agent-core + coding-agent CLI + TUI + RPC/SDK; easy embed (OpenClaw etc. cite it).
4. **Context-file contract** — `AGENTS.md` always-inlined; skills progressive — clean prompt pattern ([01](CODER-6.1.1-DONE-pi-agent.md)).
5. **Anti-Claude-Code stance** — no MCP/subagent/plan baked in; community likes the floor-not-cathedral pitch.
6. **Author / community signal** — Mario Zechner / Earendil; demos; session sharing for evals.

None of those are “the host verifies the model did the skill correctly.”

---

## Vs our Skill.Runner (the thing that *did* harness in sense A)

| | Pi core | Skill.Runner |
|--|---------|--------------|
| Skill role | Menu + optional `read` | Catalog → **host-bind** refine/execute |
| Structure | Free-form `toolsReply` | Task list, stages, interpreters |
| Failure mode | Soft (freestyle) | Harder (parse/validate/retry paths) |
| Product bet | Model + thin loop + extensions | Conductor owns workflow |
| Outcome for us | Fashionable / portable | Didn’t succeed as shipping agent (user) |

- 🔷 Runner had **more** sense-A harnessing. Pi is regarded higher for a **different bet**: trust the model + keep the floor thin.
- 🔷 Copying Pi’s injection/compaction does **not** recreate Runner’s checks. If we want checks again, that is **our** design (approvals we kept, or new stages) — not something waiting in [06](done/6.1.6-DONE-urgent-follow-up.md).

---

## What Agent Pi has borrowed so far

| Borrowed | Sense |
|----------|--------|
| Factory + lean `read`/`write`/`bash` | B — tool surface |
| AGENTS.md walk + inject | B — standing contract |
| Soft skill catalog | B — progressive disclosure |
| Compact template + threshold | B — context hygiene |
| Permissions / approvals (ours) | A — **we** add governance Pi refuses |
| Hash tags + `session_fetch` | B+ — our stronger recall than Pi alone |

Open: [09](CODER-6.1.9-offer-agents-md.md), [10](CODER-6.1.10-DONE-skills-configuration.md), [11](CODER-6.1.11-extended-base-skills.md). ✅ [done/02](done/6.1.2-DONE-pi-like-agent.md); ✅ [done/03](done/6.1.3-DONE-base-skills.md); ✅ [done/07](done/6.1.7-DONE-project-summary-tool.md); ✅ [06](done/6.1.6-DONE-urgent-follow-up.md).

---

## Urgent / follow-up ([06](done/6.1.6-DONE-urgent-follow-up.md)) — keep, don’t replace with this study

[06](done/6.1.6-DONE-urgent-follow-up.md) today:

- **Urgent** after current tool batch, before next LLM call (Phase 6a agent; 6b UI reserved). Pi called this **steer**.
- **Follow-up** when the agent would otherwise stop.
- Chatter FIFO ≠ between-tool-batch inject ([01 §9](CODER-6.1.1-DONE-pi-agent.md#9-urgent--follow-up-requirement-not-the-headline)).

- 🔷 That **is** harnessing the **conversation timeline** (sense B), not verifying code/skill quality (sense A).
- 🚫 Do not delete [06](done/6.1.6-DONE-urgent-follow-up.md) and substitute “figure out real harness.” This study already answers: core Pi has no secret sense-A layer.
- 💩 If we want sense-A later: separate backlog (e.g. extension-like hooks, stronger tool gates, optional plan gate) — **not** rename 06.

---

## Implications for Agent Pi

1. **Stop expecting Pi to supply check-and-balance.** Name `long_title = implementation of the Pi agent harness` means sense **B**, not Runner 2.0.
2. **Skills pack** = playbooks; value is curation + tool retarget ([done/03](done/6.1.3-DONE-base-skills.md)), not a new control plane.
3. **Our differentiators already** = writer approval, sandbox, `session_fetch` + hash refs, project/index tools — more sense-A than default Pi.
4. **If “special” feels empty:** either (a) ship a good free-form coding agent with Pi-shaped prompt/tools/compact (honest thin), or (b) deliberately add sense-A features Pi refused — knowing that is **leaving** Pi orthodoxy.
5. **Extensions:** largest unported Pi idea; only worth it if we want in-process TS-style hooks in Vala (unlikely 1:1). Approvals + tools already cover many extension examples.

---

## Open questions (user)

- 🔷 Are we happy Agent Pi stays **thin sense-B** + our permissions, or do we want a **sense-A** slice (plan gate, skill-must-read, post-edit check) as a later phase?
- 💩 Port any extension *ideas* (path protect, git checkpoint) as Vala/host features without Pi’s TS extension API?
- ℹ️ No change required to [06](done/6.1.6-DONE-urgent-follow-up.md) wording unless we want a one-line cross-link to this study.

---

## LLM notes

- ℹ️ This is a **study**, not a Vala implement plan. No fences.
- 🔷 Emoji: **🔷** user concern / decision; **ℹ️** fact from Pi tree / prior study; **💩** optional product fork; **🚫** wrong expectation.
- 🚫 Do not invent a Pi “output verification” phase that does not exist upstream.
- 🚫 Do not treat soft skills as the reason Pi is special.
- 🚫 Do not replace [06](done/6.1.6-DONE-urgent-follow-up.md) with this file; link here for rationale only.
