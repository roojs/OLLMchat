# 2.16 Edit output format — strategy (always-on tags vs gated `write`)

## Checklist for plans

See [`guide-to-writing-plans.md`](../guide-to-writing-plans.md) — **Checklist for plans**. This document is **strategy only**; no **Remove** / **Replace with** / **Add** until a path is chosen.

## Status

⏳ **STRATEGY** — pick Path A or Path B before implementation plans split into EDIT-2.17+.

## Purpose

Decide how Agent Pi should accept file edits from models that **fight** the current contract (`write` tool call → stream **markdown fences** in the same message). Evidence:

- [Phone/desktop `write` loops](../bugs/2026-11-23-ISSUE-phone-agent-pi-edit-file-test.md) — `ornith-1.5:35b` re-calls `write` with empty body instead of fencing.
- [Always-on POC](../bugs/2026-11-27-FEATURE-always-on-edit-brace-syntax-poc.md) — same model, **no** `write` tool, emits well-formed `<write …>…</write>` in one turn ([`last-run.txt`](../../tests/data/always-on-edit-brace-poc/last-run.txt)).
- [Edit activation plan not viable](../bugs/2026-11-27-ISSUE-edit-mode-tool-activation-plan-not-viable.md) — do not assume prompt fixes on the fence path will converge.

## Related

- [EDIT-2.15 active edit tool](EDIT-2.15-active-edit-tool.md) — opt-in system message + `---BEGIN---` blocks (different syntax; may merge or supersede).
- [EDIT-2.4 / done 2.4](../plans/done/2.4-DONE-edit-file-tool.md) — current fence-based EditMode.
- [TOOLS-2.30 pretooler filtering](TOOLS-2.30-pretooler-tool-filtering.md) — which tools/messages models see.

---

## Path A — Always-on edit (tags in assistant text)

**Idea:** File edit capability is **always** described in system/agent instructions. The model emits [`<write file="…" edit_mode="…" …>…</write>`](../bugs/2026-11-27-FEATURE-always-on-edit-brace-syntax-poc.md) (or a single canonical variant). Harness **parses the stream** (or final message) and applies via existing EditMode apply logic — **no** `write` activation round-trip.

| Topic | Implications |
| ----- | ------------ |
| **Model behavior** | POC suggests `ornith` prefers “put file in message” over “call tool then fence.” |
| **Permissions** | No tool argument gate before edit intent appears — parser must enforce **allowed paths**, sandbox, project root, and possibly **confirm/review** before apply. |
| **Security** | Any turn could contain writes; pretooler cannot hide `write` because there is no tool — instructions and parser are the control plane. |
| **Review / UI** | Same review queue as today, but triggered from **tag parse** not `Tool.activate_request`. |
| **Partial edits** | `edit_mode=line_numbers` still needs inner fence rules inside the tag (POC system copy already sketches this). |
| **Other tools** | `read`, `bash`, etc. stay as tools; only **mutation** moves to tags. |
| **Migration** | Deprecate or noop `write` on Pi agents; desktop/agents.md skills must agree on one syntax. |

**Risks**

- Models emit tags for paths outside workspace unless parser is strict.
- Accidental edits in chit-chat (“here’s an example `<write>`”) — need robust parsing + maybe “pending edit” UI.
- Divergence from EDIT-2.15 `---BEGIN---` format unless we **standardize on `<write>`** and park 2.15.

**Suggested validation (before code)**

- More POC matrix: mid-file `line_numbers`, `ast_path`, multi-file one turn, other models (not only ornith).
- Red-team: malicious path attributes, huge bodies, nested tags.

---

## Path B — Keep `write` gate; change **output contract** to tags

**Idea:** Retain **`write`** (or rename) so the harness still gets **file_path**, `edit_mode`, `overwrite`, and permission checks **before** streaming. After activation, the tool result and system copy say: “In **this** assistant message, output `<write>…</write>` (or one wrapper tag) — **not** markdown fences; do not call `write` again.” Parser on the stream accepts **tags** instead of (or as well as) fences while edit mode is active.

| Topic | Implications |
| ----- | ------------ |
| **Model behavior** | Open question: does `ornith` still **loop on empty `write`** when the tool means “open editor” but content must be tags? **Must probe** — see probes below. |
| **Permissions** | Unchanged — tool call remains the gate. |
| **Harness** | [`Stream.vala`](../../liboctools/EditMode/Stream.vala) gains tag parser branch; [`Request.vala`](../../liboctools/EditMode/Request.vala) tool result text rewritten. |
| **UX** | User still sees “Edit mode activated” tied to a path; clearer than always-on. |
| **Failure mode** | If model still treats `write` as “submit file body in tool args,” Path B fails and we fall back to Path A or body-in-args escape hatch ([phone issue](../bugs/2026-11-23-ISSUE-phone-agent-pi-edit-file-test.md)). |

**Risks**

- Two-step mental model (tool + tags) may confuse **some** models more than always-on.
- Must maintain **both** parsers during transition if fences stay for legacy agents.

---

## Comparison (decision table)

| Criterion | Path A — always-on tags | Path B — `write` then tags |
| --------- | ------------------------ | --------------------------- |
| Fits ornith POC | Strong (proven no-tool) | Unknown — needs hybrid probe |
| Permission gate | Parser + policy only | Tool call first |
| Prompt/tool loop bug | Avoids `write` loop | May or may not fix loop |
| Implementation size | Parser + pretooler/system overhaul + review hooks | Smaller delta on EditMode |
| Product story | “Edits are part of the message” | “Call write, then stream edit block” |

---

## Probes (no product code until path chosen)

| Id | What | Where | Pass signal |
| -- | ---- | ----- | ----------- |
| **A0** | ✔️ Complete file, no tools | [`run-always-on-edit-brace-poc.sh`](../../tests/run-always-on-edit-brace-poc.sh) | One `<write>…</write>`, ~50 lines |
| **A1** | Mid-file `line_numbers` | Same CLI fixtures (new user prompt) | One or more tags with inner fences |
| **B0** | **First** — `write` + tool result copy → tags (in tree) | Desktop or `ollmchat-cli --project=…` | After `write`: tags vs fences vs empty vs repeat `write` (apply still fence-only until parser) |
| **B1** | CLI scripted multi-turn (future) | CLI markers + loop | Same as B0 under `expect`-style driver |
| **B2** | Full Agent Pi + gtktest1 | Harness test flag (future) | Same as B0 under real `Stream` handler |

**B0 detail**

- [`Write.description`](../../liboctools/EditMode/Write.vala) and post-`write` copy in [`Request`](../../liboctools/EditMode/Request.vala) instruct `<write>` tags; fence parser unchanged until chosen.
- Manual: desktop Agent Pi or `ollmchat-cli --project=…`; paste assistant + tool trace into the issue.

Document results in [activation-not-viable issue](../bugs/2026-11-27-ISSUE-edit-mode-tool-activation-plan-not-viable.md) **Current behavior**.

---

## CLI scriptable mode (future — not implemented)

Goal: lightweight scriptable harness like desktop, with **line-oriented markers** so bash can `read` until a sentinel and send the next user message (multi-turn probes without a custom Vala test).

| Marker (proposal) | When emitted |
| ----------------- | ------------ |
| `---OLLMCHAT:READY---` | Manager connected; safe to send first user line |
| `---OLLMCHAT:TOOL_BEGIN name=write---` | Tool execution started |
| `---OLLMCHAT:TOOL_END name=write---` | Tool result handed to model |
| `---OLLMCHAT:STREAM_END---` | Assistant turn complete (stream drained) |
| `---OLLMCHAT:TURN_END---` | Full agent turn done (tools + follow-up generation finished) |

Possible flags: `--script-markers`, or env `OLLMCHAT_CLI_MARKERS=1`. stdin lines after `READY` become user messages until EOF. Enables B1 without Expect/Tcl — **defer** until B0 is recorded.

---

## User decisions required

- 💩 **Path A** or **Path B** (or hybrid: A for Pi, B for skills agent — discouraged unless necessary).
- 💩 Canonical syntax: `<write …>` (POC) vs merge with [EDIT-2.15](EDIT-2.15-active-edit-tool.md) `---BEGIN---` blocks.
- 💩 After path pick: authorize EDIT-2.17 implementation plan (parser, copy, permissions) — **not written yet**.

## LLM

- ℹ️ Created **2026-11-27**; no Vala changes per user request.
- ℹ️ Link from [EDIT-1.0-summary](EDIT-1.0-summary.md) when user confirms strategy doc is the index entry.