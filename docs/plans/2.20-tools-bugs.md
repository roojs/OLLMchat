# 2.20. Tools bugs

## Status

⏳ **PENDING**

## Purpose

Track and fix tool-related bugs. Current item: tool list missing descriptions for 6 of 16 tools (API payload / UI use `tool.function.description`).

## Background

- The **tool list** sent to the chat API is built by serializing each tool; `BaseTool` serializes the `function` property. So `function.description` is what the model (and any schema-driven UI) sees.
- Tools come from several code paths: standard liboctools/libocvector tools, wrapped tools (ToolBuilder + .tool files), and agent tools (Child.Parser).

## Bug: 16 tools but 6 without description

### Observation

With 16 tools registered, 6 have no description in the tool list (API payload / UI). Some code path is leaving `tool.function.description` empty.

### Where description is set

1. **Standard tools** (ReadFile, RunCommand, WebFetch, EditMode, GoogleSearch, CodebaseSearchTool): `BaseTool.init()` builds `function` from `this.name`, `this.description`, `this.parameter_description`. So the class’s abstract `description` getter must return non-empty.
2. **Wrapped full tools** (Grep, LS, Glob): `ToolBuilder` sets `new_tool.function = new Function() { description = parser.description, ... }` and does **not** call `init()`. So the only source is `parser.description` (lines before first `@` in the .tool file).
3. **Wrapped aliases** (Read, WebSearch, WebFetch): Same instance as base tool; they keep the base tool’s `function`, so they already have a description.
4. **Agent tools** (from `Child.Parser`): Created with `new Tool() { agent_description = parser.description, ... }`; `base()` calls `init()`, which builds `function` from `this.description` (≡ `agent_description`). Parser skips registration if `parser.description == ""`, so registered agents should have a description.

So in theory every registered tool should get a description from one of these paths. The 6 without description imply either: a path that never sets `function.description`, or that sets it to `""` (e.g. parser or init running before a property is set), or a different list (e.g. 16 entries keyed by config with 6 configs lacking a description field).

### Proposed fix (in code)

Add a **defensive fallback** so the tool list never sends an empty description when we have a title or name:

1. **ToolBuilder** (`liboctools/ToolBuilder.vala`): When building the `Function` for a full wrapped tool, if `parser.description == ""` and `parser.title != ""`, set `function.description = parser.title`. That way wrapped tools always get at least a title as description even if the .tool file has no leading description block.
2. **BaseTool serialization** (`libollmchat/Tool/BaseTool.vala`): When serializing the `function` property, if `this.function.description == ""` and `this.title != ""`, serialize a function object that uses `this.title` as the description (or ensure `Function` is updated once at serialization time). That covers any tool (not just wrapped) that has `title` but empty `description`.

Prefer doing (1) in ToolBuilder so wrapped tools get a description at registration time. Optionally add (2) as a safety net so any tool with a title never sends an empty description to the API.

### Investigation (optional)

- Log or assert which tools have `function == null` or `function.description == ""` after registration and after `rebuild_tools()`, to identify the exact 6.
- Confirm whether the “16 tools, 6 without description” count is from the API payload (`chat.tools.values`), from the UI (e.g. config entries), or from another list.

## Future items (optional)

- **Convention**: Document in 2.16 or this plan that every full wrapped .tool file must have at least one description line before the first `@` so the tool list has a description.
