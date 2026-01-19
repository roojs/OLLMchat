# 5.3. Agent Sandbox

## Overview

A new agent for experimenting with system and user message prompts. It provides two editable prompt templates (system and user wrapper), a test harness to run them against an LLM, and a dedicated chat mode where the LLM acts as a "prompt creator" that can modify both prompts via a structured output format.

## Status

⏳ **TODO** - To be implemented.

## Goals

- Experiment with system and user prompts without affecting normal chats
- Persist prompt combinations (PromptSets) with model info, similar to history sessions
- Use a git-backed project for promptset files to track modifications and history
- Test prompts via a Test button and test script, using hidden sessions (excluded from session history)
- Refine prompts through chat: the LLM outputs modified prompts in a delimited format that we parse and apply to the editors

## UI Layout

The agent provides a right-pane widget (like the Code Editor agent via `get_widget()`).

### Right Pane Structure

- **ListView (promptsets)**  
  - Left part of the right pane (sidebar, similar to HistoryBrowser)
  - Lists PromptSets: name, model, last modified
  - Selection loads that PromptSet into the system/user editors and sets the model

- **Editor area** (main part of the right pane, two SourceViews + test script)
  - **Top: System prompt** – `GtkSource.View` for the system message
  - **Middle: User prompt wrapper** – `GtkSource.View` for the user message template (often contains a placeholder such as `{{USER_MESSAGE}}` or `{input}` that is replaced by the test script when testing)
  - **Bottom: Test script** – text box (e.g. `GtkSource.View` or `Gtk.TextView`) for the user-message content used when hitting Test

- **Test button**  
  - In the header or toolbar
  - Runs: system prompt (as-is) + user prompt (with test script substituted for the user part) → LLM
  - Output is shown in the standard chat/output view (same rendering as normal LLM replies)
  - Test runs use **hidden sessions** (see below) and do not appear in the session history list

- **Tool configuration (per PromptSet)**  
  - Same style as occoder: list of tools with enabled/disabled and tool-specific options (e.g. Adw.ExpanderRow per tool, like ToolsPage). Bound to the **current PromptSet’s `tools`**; changes are saved with the promptset. When running Test or Prompt Creator chat, only tools enabled in `PromptSet.tools` (merged with `Config2.tools`) are added to the Chat.

Layout sketch:

```
+----------------------------------+------------------------------------------+
| Chat (left pane)                 | Right pane (Prompt Sandbox)              |
|                                  | +----------------+------------------------+|
|                                  | | PromptSets     | System prompt (SourceView)||
|                                  | | ListView       |-------------------------||
|                                  | |                | User prompt (SourceView) ||
|                                  | | - Set A (qwen) |-------------------------||
|                                  | | - Set B (...)  | Test script (textarea)   ||
|                                  | |                |         [Test]          ||
|                                  | +----------------+------------------------+|
+----------------------------------+------------------------------------------+
```

## Data Model: PromptSet

`PromptSet` is a **class** with:

- `name` (string) – unique id and filename stem (`{name}.json`)
- `system_prompt` (string)
- `user_prompt` (string) – wrapper/template for the user message
- `model` (string) – LLM model id (e.g. from `model_usage.model`)
- Optional: `model_usage` or connection info if we need more than `model` for the test/client
- `updated_at` (int64) – Unix timestamp for sorting and “last modified” in the ListView
- **`tools`** (tool config for this agent) – which tools this agent has access to; structure mirrors `Config2.tools` (e.g. `tool_id -> { enabled: bool, ... }`). Used when running Test or Prompt Creator chat: we filter/override `Manager.tools` using this. Changes are made via the same kind of tool UI as in occoder (ToolsPage-style) and are **saved against the promptset**.

Stored as one JSON file per PromptSet under the promptsets directory.

### JSON Schema (per file)

```json
{
  "name": "my-set",
  "system_prompt": "...",
  "user_prompt": "...",
  "model": "qwen3:latest",
  "updated_at": 1234567890,
  "tools": {
    "read_file": { "enabled": true },
    "edit_file": { "enabled": true },
    "web_fetch": { "enabled": false }
  }
}
```

- `name`: unique id and filename stem (`{name}.json`)
- `updated_at`: Unix timestamp for sorting and “last modified” in the ListView
- `tools`: optional; which tools this promptset’s agent can use. Omissions can fall back to `Config2.tools` or a default. When building Chat for Test or Prompt Creator, merge with global config and only add tools enabled for this promptset.

### Tool configuration (per PromptSet)

- **UI**: Same pattern as occoder / ToolsPage: list of available tools (from `Manager.tools`), each with an enabled toggle and optional tool-specific options in an expandable row. This UI is shown in the sandbox widget when a PromptSet is selected; editing changes the **current PromptSet’s `tools`** only.
- **Persistence**: Stored in the promptset JSON as the `tools` map. Save (and git commit) when the user saves the promptset or when tool toggles are applied, as we do elsewhere.
- **Usage**: When building the Chat for a Test run or for Prompt Creator chat, we filter `Manager.tools` using `PromptSet.tools`: only add tools that are enabled in the promptset’s `tools` (with `Config2.tools` merged for tool-specific config such as codebase_search embed/analysis). Same pattern as `Agent.Factory.configure_tools` and `Config2.tools` elsewhere.

## Storage and Git

- **Directory**: `~/.local/share/ollmchat/promptsets/`  
  - In code: use `data_dir` from `ApplicationInterface` when available, e.g.  
    `GLib.Path.build_filename(app.data_dir, "promptsets")`
  - (The app uses `ollmchat` in XDG paths; `data_dir` is typically `~/.local/share/ollmchat`.)

- **Files**: `promptsets/<name>.json`  
  - One JSON file per PromptSet
  - Sanitize `name` for filenames (alphanumeric, `-`, `_`)

- **Git**  
  - The `promptsets` directory is a **git repository**
  - On first use: if the directory exists and is not a git repo, run `git init`
  - Enables: history, diff, and simple “project for files” semantics
  - Implementation: use **libgit2** (libgit2-glib, already a project dependency) for `git init`, `git add`, and `git commit` when saving

## Hidden Sessions for Test Runs

- **Requirement**: Test runs must not clutter the session history list.

- **Approach**: introduce an `is_hidden` (or similar) on `SessionBase` (or on the session row in the DB).

  - Test runs create a session with `is_hidden = true`
  - `Manager.load_sessions()` and any UI that builds the session list (e.g. `HistoryBrowser`’s model) must **exclude** `is_hidden` sessions

- **Lifecycle**:  
  - Hidden sessions can be stored like normal sessions (for possible “recent tests” or debugging) or discarded after the test is shown; the plan assumes they are stored but never shown in the main list.

## Test Flow

1. User edits system prompt, user prompt, and test script.
2. User clicks **Test**.
3. Backend:
   - Resolve `user_prompt` with the test script as the “user message” (replace `{{USER_MESSAGE}}` or similar in the template; if no placeholder, append or replace as per a small, documented convention).
   - Build messages: `[{ role: "system", content: system_prompt }, { role: "user", content: resolved_user }]`.
   - Create a **hidden session** and a `Client` (or reuse a dedicated test client) with the PromptSet’s `model`.
   - Send chat request; stream or collect the full response.
4. UI: show the model’s reply in the **standard test/chat output view** (same as normal assistant messages: markdown, code blocks, etc.).
5. The PromptSet and editor content are unchanged unless the user applies changes from a “prompt creator” chat (see below).

## Prompt Creator Chat (Wrapper)

When the user **chats** in this agent (as opposed to running Test), the assistant is configured to act as a **prompt creator** that edits the two prompts.

### Wrapper System Message

The effective system message for this chat is along the lines of:

```
You are a prompt creator. You are given two prompts:

---CURRENT SYSTEM PROMPT---
<contents of system prompt editor>
---CURRENT USER PROMPT---
<contents of user prompt editor>
---END---

When the user asks you to change them, you must output the new prompts in exactly this format:

---SYSTEM PROMPT--
<new system prompt>
---USER PROMPT---
<new user prompt>
---END---
```

- Delimiters: `---SYSTEM PROMPT--`, `---USER PROMPT---`, `---END---` (as specified).
- The wrapper is built from the current buffers each time we build the context for the chat.

### Parsing and Applying

- On each assistant **content** (or full) response, scan for:
  - `---SYSTEM PROMPT--` … `---USER PROMPT---` … `---END---`
- If both blocks are found:
  - Replace system prompt buffer with the extracted system block.
  - Replace user prompt buffer with the extracted user block.
  - Optionally: mark PromptSet dirty and suggest saving.
- If the format is not found, treat the reply as a normal conversational message (no edits).

### Chat vs Test

- **Test**: uses system + user (with test script) and a hidden session; no wrapper; no parsing of `---SYSTEM PROMPT--` etc.
- **Chat**: uses the prompt-creator wrapper and the user’s free-form instructions; we parse the model output and apply edits to the two SourceViews when the format is present.

## LLM Output Format (Prompt Creator)

The model is instructed to use:

```
---SYSTEM PROMPT--
<new system prompt>
---USER PROMPT---
<new user prompt>
---END---
```

- **---SYSTEM PROMPT--** (two hyphens at the end)  
- **---USER PROMPT---** (three hyphens)  
- **---END---**  
- Content between delimiters: exact text to put in the buffers (trimmed of leading/trailing newlines as needed).

## Implementation Outline

### 1. Data and Storage

- **`PromptSet`** class: JSON load/save; properties include `name`, `system_prompt`, `user_prompt`, `model`, `updated_at`, `tools`.
- **`PromptSetList`**: implements **`GLib.ListModel`** (wrapper over `Gee.ArrayList<PromptSet>`, like `SessionList` / `ProjectList`). Responsibilities: `append`, `remove`, `get_item`, `get_n_items`, `get_item_type`; also `load_from_directory()` (scan `promptsets/*.json`), `save_prompt_set()`, `delete_prompt_set()`, `ensure_repo()` (create `promptsets` dir and `git init` via libgit2 when needed). The ListView binds to `PromptSetList` directly.
- Exclude sessions where `agent_name.has_prefix("--hidden")` from `Manager.load_sessions()` and from the history list. Test runs use `agent_name = "--hidden-agent-sandbox"`.

### 2. Agent and Widget

- **PromptSandbox** agent (e.g. in `liboccoder` or next to `CodeAssistant`):
  - Implements `get_widget()` and returns the right-pane widget.
  - Registers in `Agent.Factory` / agent registry so it can be chosen in the agent dropdown.

- **PromptSandboxWidget** (or equivalent):
  - ListView bound to **`PromptSetList`** (the ListModel) directly.
  - Two `GtkSource.View` buffers for system and user prompts; one text area for the test script.
  - **Tool configuration UI** (like occoder/ToolsPage): list of tools with enabled toggle and optional tool-specific options, bound to the current **PromptSet’s `tools`**; changes are saved with the promptset.
  - Header/toolbar: Test button, Save (and optionally New, Delete, Duplicate for PromptSets).
  - On PromptSet selection: load into buffers, set `model`, and refresh the tool config UI from `PromptSet.tools`.

### 3. Test Run

- Resolve user template with test script.
- Build Chat: add only tools enabled in **`PromptSet.tools`** (merged with `Config2.tools` for tool-specific config), same pattern as elsewhere.
- Create hidden session and client; run chat with `[system, user]`.
- Display response in the same view used for normal assistant messages.

### 4. Prompt Creator Chat

- When sending a user message in Prompt Sandbox chat, prepend the “You are a prompt creator…” system message (with current system and user prompts) to the conversation. When building the Chat, add only tools enabled in **`PromptSet.tools`** (same as Test).
- On assistant output: parse `---SYSTEM PROMPT--` / `---USER PROMPT---` / `---END---` and, when present, update the two SourceViews and optionally mark dirty.

### 5. Git and Optional “Project” Behavior

- On first save (or first use of `promptsets`): `git init` if not already a repo.
- On save of a PromptSet: `git add` and `git commit` with a simple message (e.g. “Update <name>” or “Create <name>”).
- Optional: “Project for files” UI (e.g. a simple diff or history of the repo) in a later phase.

## Files to Create or Modify

### New

- `liboccoder/PromptSandbox/PromptSet.vala` – data class (including `tools`) and JSON (de)serialization.
- `liboccoder/PromptSandbox/PromptSetList.vala` – **`GLib.ListModel`** wrapper (like `SessionList`); `load_from_directory()`, `save_prompt_set()`, `delete_prompt_set()`, `ensure_repo()`; `promptsets` dir and `git init` via libgit2.
- `liboccoder/PromptSandbox/PromptSandboxWidget.vala` – ListView bound to `PromptSetList`; two SourceViews; test script box; **tool config UI** (ToolsPage-style, bound to `PromptSet.tools`); Test button, Save, etc.
- `liboccoder/PromptSandbox/PromptSandbox.vala` – agent that overrides `get_widget()` and wires `PromptSetList` and `PromptSandboxWidget`; implements prompt-creator system message and response parsing; when building Chat, filters tools by `PromptSet.tools`.
- `resources/ollmchat-agents/prompt-sandbox.bjs` (or equivalent) – agent definition for the Prompt Sandbox.

### Modify

- `libollmchat/History/Manager.vala` – `load_sessions()` (and any `SessionList` filling) to exclude sessions where `agent_name.has_prefix("--hidden")`.
- `libollmchatgtk/HistoryBrowser.vala` – ensure the list model excludes `--hidden*` sessions (if not already done by `Manager`).
- Agent registration – register `PromptSandbox` in the factory used by the agent dropdown.
- `liboccoder/AgentFactory.vala` (or wherever `CodeAssistant` is registered) – add Prompt Sandbox.

## User Prompt Placeholder

- Document a single placeholder for the user message in the user prompt, e.g. `{{USER_MESSAGE}}` or `{{INPUT}}`.
- When running Test: replace it with the test script; if the placeholder is missing, one option is to append the test script as a new paragraph or to treat the whole user template as a prefix. The plan assumes `{{USER_MESSAGE}}` and “replace” semantics; if missing, append after the template.

## Phase Summary

| Phase | Description |
|-------|-------------|
| 1 | `PromptSet` (with `tools`), `PromptSetList` (ListModel), `promptsets` dir, `git init` on first use |
| 2 | Filter sessions with `agent_name.has_prefix("--hidden")` from history; Test runs use `agent_name = "--hidden-agent-sandbox"` |
| 3 | `PromptSandbox` agent and `PromptSandboxWidget`: ListView (on `PromptSetList`), system/user SourceViews, test script, **tool config UI** (per PromptSet), Test and Save |
| 4 | Test run: resolve user template, call LLM, show in standard output view |
| 5 | Prompt Creator: wrapper system message and parsing of `---SYSTEM PROMPT--` / `---USER PROMPT---` / `---END---` to update buffers |
| 6 | Git commit on save; optional diff/history UI later |

## Dependencies

- `GtkSource` for the two prompt editors and optionally the test script.
- Existing `Client`, `Session`, `Manager`, and chat UI for Test and for Prompt Creator chat.
- `ApplicationInterface.data_dir` for `promptsets` path.
- **libgit2** (libgit2-glib) for `git init`, `git add`, and `git commit` in the promptsets repo (already a project dependency).

## Open Points

- Exact placeholder name (`{{USER_MESSAGE}}` vs `{input}`) and behavior when it is missing.
- Whether to keep or prune `--hidden-*` sessions (e.g. after N or after some TTL).
- Whether to support more than one placeholder in the user prompt (e.g. `{{MODEL}}`, `{{DATE}}`).
- Optional: dedicated “project” UI for the promptsets git repo (log, diff, branch).
