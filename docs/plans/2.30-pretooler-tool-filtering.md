# 2.30. Pretooler — dynamic tool filtering for standard chat

## Status

⏳ **PENDING**

## Overview

By default, the standard LLM agent (`just-ask`) receives **every** tool registered on `Manager.tools` when the model supports tool calling. That bloats each request with tool schemas the model is unlikely to need for simple prompts (e.g. “what is 2+2?” does not need `codebase_search`, `run_command`, MCP tools, etc.).

Add a **pretooler** step: before the main chat request, run a **small, tool-free** LLM call whose only job is to pick which tools are relevant to the current user message. The main request then receives a reduced tool set.

Use the existing **`---`-separated prompt template system** (`OLLMchat.Prompt.Template` / `PromptTemplate`-style loading and `{placeholder}` filling). Two templates: **initial** (first user message) and **follow-up** (later messages in the same session).

## Problem

| Area | Current behaviour |
|------|-------------------|
| Tool registration | `Agent.Base` constructor copies **all** `manager.tools` entries into `chat_call.tools` (`libollmchat/Agent/Base.vala` ~132–136). |
| Filtering hook | `factory.configure_tools()` runs afterward; `JustAskFactory` does **not** override it, so nothing is removed. |
| Cost | Every tool’s name, description, and parameter schema is serialized into the API payload (`Call.Chat` tool serialization). |
| Latency | Larger payloads; models may also be slower or noisier when choosing among many tools. |

Skills already solve a narrower version of this: a skill’s YAML `tools:` header restricts tools per skill (`Runner.fill_tools()`). The pretooler applies the same *idea* to **default chat**, but selection is **dynamic per message** instead of static in a skill file.

## Desired end state

1. **Default on** for standard chat (`just-ask`) when the session model supports tool calling.
2. Before each `send_async`, if pretooler is enabled:
   - Build a tool catalog (name + short description only — **not** full parameter schemas).
   - Fill the appropriate template (`pretooler_initial.md` or `pretooler_followup.md`).
   - Send a **non-streaming, tools-disabled** chat call to a configured pretooler model.
   - Parse the response into a list of tool names.
   - Replace `chat_call.tools` with only those tools (plus wrapped-tool aliases for the same instances, same pattern as `Child.Factory.configure_tools()`).
3. Then run the normal main `send_async` with the reduced tool set.
4. User-visible: optional debug/ui message listing selected tools (configurable; off by default).

### Verify manually

- First message “hello” → pretooler returns empty or minimal set; main call has few/no tools.
- “Search the codebase for Session.vala” → pretooler includes `codebase_search` (and possibly `Grep` / read tools).
- Follow-up “now run the tests” → pretooler sees conversation + latest message; includes `run_command`.
- Pretooler disabled in config → behaviour matches today (all tools).

## What we are NOT doing (yet)

- Pretooler for **Code Assistant**, **agent tools**, or **occoder skill Runner** flows.
- Semantic / embedding-based tool retrieval (future alternative).
- Caching pretooler results across unrelated sessions.
- Sending full assistant/tool message history to the pretooler (follow-up uses **user-side context only** for v1).
- Changing which tools are registered on `Manager` — only filtering what reaches `chat_call.tools`.

---

## Architecture

```
User message
    │
    ▼
┌─────────────────────┐
│ Pretooler (no tools)│  ← pretooler_initial.md or pretooler_followup.md
│  model: fast/cheap  │
└─────────┬───────────┘
          │ tool names (parsed)
          ▼
┌─────────────────────┐
│ Filter chat_call    │  clear + re-add selected tools (+ aliases)
│ .tools              │
└─────────┬───────────┘
          ▼
┌─────────────────────┐
│ Main chat (stream)  │  normal Agent.Base.send_async
└─────────────────────┘
```

### Integration point

**`libollmchat/Agent/Base.vala`** — override or extend `send_async()`:

1. After building message list, before `fill_model()` / main `chat_call.send()`:
2. `yield this.filter_tools_for_message(message, cancellable)` when pretooler enabled and agent is standard chat.

Alternatively, a dedicated `Pretooler` class in `libollmchat/Agent/Pretooler.vala` keeps `Base` readable; `JustAskFactory` or config gates whether it runs.

### Tool catalog format (sent to pretooler)

Build from `manager.tools`, **deduplicated by tool instance** (wrapped aliases like `Grep` / `grep` point at one `BaseTool`):

```markdown
## Available tools

- **codebase_search** — Semantic search over indexed project files.
- **run_command** — Run a shell command in the project workspace.
- **Read** — Read file contents (alias of read_file).
…
```

Use `tool.name` and first paragraph of `tool.description` (strip `@param` blocks). Do **not** include `parameter_description` or JSON schema.

### Pretooler response format (easy to parse)

Require a single markdown section the parser can find reliably:

```markdown
## Selected tools

- codebase_search
- Read
```

Rules for the model (in template):

- Output **only** `## Selected tools` with a bullet list of **exact tool names** from the catalog.
- If **no** tools are needed, output the section with a single bullet: `- none`
- Do not invent names; invalid names are dropped with a warning.

Parser: extract section, split bullets, trim, map `- none` → empty list, validate against catalog keys (match case-sensitive; also accept any alias that maps to the same tool instance).

### Wrapped-tool aliases

When pretooler selects `read_file`, also register every `manager.tools` key whose value is the same instance (mirror `Child.Factory.configure_tools()` in `liboctools/Child/Factory.vala` ~85–88). Same for `run_command` / `Grep` / etc.

### Follow-up vs initial

| Turn | Template | User-side context in prompt |
|------|----------|-----------------------------|
| First user message in session | `pretooler_initial.md` | `{user_prompt}` only |
| Later user messages | `pretooler_followup.md` | `{conversation}` (prior user messages, numbered) + `{user_prompt}` (latest) |

**Follow-up `{conversation}`** — user prompts only, not assistant replies or tool output:

```markdown
## Conversation

1. How does Session save messages?
2. Can you show me the relevant code?
```

Latest message is repeated in `{user_prompt}` so the template can say “this is what the user just said”.

Do **not** include full chat history in v1; if the latest message is ambiguous (“do that again”), pretooler may over- or under-select — acceptable tradeoff for a lightweight pass.

---

## Template mockups

Templates live under `resources/chat-prompts/` (new gresource prefix `/chat-prompts`, loaded via a small `OLLMchat.Prompt.ChatTemplate` wrapper mirroring `OLLMcoder.Skill.PromptTemplate`).

Both use the standard `---` split: **system** above, **user template** below.

### `pretooler_initial.md`

```markdown
You are a **tool selector**. You do not answer the user's question and you do not call tools. Your only job is to decide which tools from the catalog might be needed to handle the user's request.

Be **conservative but not empty**: include a tool if the request might plausibly need it; omit tools that are clearly irrelevant.

If the user message is casual chat, greetings, or general knowledge with no project/code/shell/file/web need, output `- none`.

## Output format

Output **only** one section:

## Selected tools

- tool_name_1
- tool_name_2

Use **exact** tool names from the catalog. If no tools apply, output a single bullet: `- none`. Do not add explanation or other sections.

---

## User prompt

{user_prompt}

{tool_catalog}
```

**Fill keys:** `user_prompt`, `tool_catalog`

### `pretooler_followup.md`

```markdown
You are a **tool selector** for an ongoing conversation. You do not answer the user and you do not call tools. Your only job is to decide which tools from the catalog might be needed for the **latest user message**, given what they have already asked in this conversation.

Be **conservative but not empty**: include a tool if the latest message (with conversation context) might plausibly need it.

If the latest message is casual follow-up with no project/code/shell/file/web need, output `- none`.

## Output format

Output **only** one section:

## Selected tools

- tool_name_1
- tool_name_2

Use **exact** tool names from the catalog. If no tools apply, output a single bullet: `- none`. Do not add explanation or other sections.

---

## Conversation

{conversation}

## Latest user message

{user_prompt}

{tool_catalog}
```

**Fill keys:** `conversation`, `user_prompt`, `tool_catalog`

**`{conversation}` fill helper:** if only one prior user message exists, still use numbered list; if none (should not happen on follow-up template), use `(no prior user messages)`.

---

## Configuration

Add to `Config2` (or a nested pretooler section under `usage` / new top-level key):

| Key | Default | Meaning |
|-----|---------|---------|
| `pretooler.enabled` | `true` | Master switch for standard chat |
| `pretooler.model_usage` | copy of `default_model` or a dedicated fast model | Which connection/model runs the pretooler call |
| `pretooler.show_selection` | `false` | Emit `ui` message listing selected tools |

Pretooler call settings:

- `stream = false`
- `think = false`
- **No tools** on the pretooler `Chat` instance
- Low temperature (e.g. 0.1) via pretooler-specific options or reuse model options

Settings UI: optional toggle on Tools page or Advanced — can be a follow-up sub-plan if needed; config file support is enough for v1.

---

## Implementation phases

### Phase 1 — Templates and catalog builder

- [ ] Add `resources/chat-prompts/pretooler_initial.md` and `pretooler_followup.md` (content as above).
- [ ] Register `/chat-prompts` in `resources/gresources.xml`.
- [ ] Add `libollmchat/Prompt/ChatTemplate.vala` — extends `OLLMchat.Prompt.Template`, `base_dir = "chat-prompts"`, static `template()` + `fill()` / `system_fill()` (can copy pattern from `OLLMcoder.Skill.PromptTemplate`).
- [ ] Add `libollmchat/Agent/ToolCatalog.vala` — `build_markdown(Manager)` deduplicated catalog string.

### Phase 2 — Pretooler runner and parser

- [ ] Add `libollmchat/Agent/Pretooler.vala`:
  - `select_tools_async(Session, Message, Cancellable)` → `Gee.ArrayList<string>`
  - Chooses initial vs follow-up template from session message count (user messages == 1 → initial).
  - Builds `{conversation}` from prior user `Message`s in `session.messages`.
  - Creates ephemeral `Call.Chat` (no tools), sends system + filled user template.
  - Parses `## Selected tools` section.
- [ ] Add unit-testable parser for selected-tools section (invalid names, `- none`, markdown noise).

### Phase 3 — Wire into standard chat

- [ ] Call pretooler from `Agent.Base.send_async()` when enabled and factory is `just-ask` (or add virtual `use_pretooler()` default true for JustAsk, false for subclasses).
- [ ] Implement `apply_tool_selection(call, names)` — clear tools, add selected (+ aliases).
- [ ] Fix `rebuild_tools()` interaction: pretooler runs per message, not only on rebuild; document order (pretooler after rebuild if config changed mid-session).

### Phase 4 — Config and observability

- [ ] Config keys + defaults in `Config2.setup_defaults()`.
- [ ] Optional `ui` debug line when `show_selection` is true.
- [ ] Log warnings for pretooler parse failures; **fallback: all tools** (safe default, same as today).

### Phase 5 — Tests and manual QA

- [ ] Parser tests (section extraction, `- none`, unknown tools).
- [ ] Integration test with mock LLM returning fixed pretooler output (if test harness exists).
- [ ] Manual matrix (see Desired end state).

---

## Edge cases

| Case | Behaviour |
|------|-----------|
| Pretooler model unavailable | Log warning; use all tools (fallback). |
| Parse failure / empty section | Fallback all tools. |
| Pretooler selects unknown name | Skip name; warn. |
| Pretooler selects `- none` | Main call with **zero** tools (still valid chat). |
| Model without tool calling | Pretooler skipped entirely (`can_call` false). |
| Session replay / restore | Pretooler runs again on replay send (determinism depends on model; acceptable v1). |
| Very long conversation | Cap `{conversation}` to last N user messages (e.g. 10) with note in template fill. |

---

## Performance

- Extra LLM round-trip per user message when enabled — mitigate with a fast/cheap pretooler model config.
- Tool catalog is O(n tools) text only — much smaller than full schemas sent to main model.
- Net win when main model receives substantially fewer tools (typical occoder + MCP installs).

---

## Related code

| File | Relevance |
|------|-----------|
| `libollmchat/Agent/Base.vala` | Tool copy, `send_async`, `rebuild_tools` |
| `libollmchat/Agent/JustAskFactory.vala` | Default agent — pretooler target |
| `liboctools/Child/Factory.vala` | Static tool filtering + alias registration pattern |
| `liboccoder/Skill/PromptTemplate.vala` | Template load/fill pattern to mirror |
| `libollmchat/Prompt/Template.vala` | Base `---` template loader |
| `docs/plans/done/2.18-DONE-agent-tool.md` | Prior art for `configure_tools` filtering |

---

## Open decisions (resolve before implementation)

1. **Pretooler model default** — same as chat model vs dedicated `usage.pretooler_model` entry (recommend dedicated fast model).
2. **Fallback on failure** — all tools (proposed) vs no tools (safer but breaks tool-reliant prompts).
3. **UI toggle in v1** — config-only vs Tools page checkbox (config-only for first ship).

---

## Success criteria

### Automated

- [ ] Project builds with new Vala files and gresources.
- [ ] Parser unit tests pass.
- [ ] No regression in agents that disable pretooler (`Child`, skills).

### Manual

- [ ] Simple greeting uses few/no tools in main API payload.
- [ ] Code/search prompt includes search/read tools.
- [ ] Follow-up command prompt includes terminal tool after code discussion.
- [ ] Disabling pretooler restores full tool list behaviour.
