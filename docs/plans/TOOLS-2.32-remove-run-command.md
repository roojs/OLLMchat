# 2.32 — Remove `run_command`

**Status:** ⏳ **proposed**

> **Do not update** `docs/plans/TOOLS-1.0-summary.md` **for this sub-plan.**

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala follows `docs/coding-standards.md`.

**Was:** [`TOOLS-2.31`](done/TOOLS-2.31-DONE-bash-process-tool.md). `bash` is the shell tool. This plan deletes the old one.

---

## Purpose

- **🔷** Delete `run_command`. `bash` is the shell tool.
- **🔷** `⏳` Find every live mention in docs, help, and instructions, and retarget the ones a person or a model still follows.
- **ℹ️** Archived plans and closed bugs keep the old name. They are history.
- **ℹ️** Survey date: 2026-10-15. Wrapped `grep` / `glob` / `ls` already say `@wrapped bash`. `resources/skills/research_find_files.md` already says `bash`.

---

## Live instructions

These still tell someone to use `run_command`.

- **🔷** `⏳` `resources/tools/huggingface-help.md` — two lines name `bash` and `run_command`. Drop `run_command`.
- **🔷** `⏳` `resources/pi-prompts/NOTICE` — says `bash` is RunCommand-based, not `run_command`, and lists `run_command` as forbidden.
- **🔷** `⏳` `docs/BUILD.md` — bubblewrap line says sandboxed `run_command`.
- **🔷** `⏳` `docs/mcp-settings.md` — built-in tools example lists `run_command`.
- **🔷** `⏳` `libocbwrap/RunSeccomp.vala` — the network note says pass `"network": true` in `run_command`. `libocmcp/Client/Stdio.vala` replaces that substring. Both have to say `bash`, or the model is told to call a tool that is gone.

---

## Open plans that still name it

Not history. They are still in `docs/plans/`.

- **ℹ️** `docs/plans/TOOLS-2.6.6-FUTURE-run-command-vte.md` — the whole plan is a VTE for `run_command`. It stays parked. Do not implement it against a deleted tool.
- **ℹ️** `docs/plans/TOOLS-2.30-pretooler-tool-filtering.md` — example tool list has `run_command`.
- **ℹ️** `docs/plans/BWRAP-2.6.2-open-first-changed-file.md` — after `edit_file` or bwrap `run_command`.
- **ℹ️** `docs/plans/WEBKIT-5.0.11-browser-dump-spill-file.md` — compares its spill file to `run_command`.
- **ℹ️** `docs/plans/MCP-2.10.4.20-BACKLOG-mcp-stdio-overlay-report-back.md` — overlay pipeline compared to `run_command`.
- **ℹ️** `docs/plans/EDIT-1.0-summary.md` — category blurb lists `run_command` as a generic tool.
- **💩** `⏳` Retarget those instructional phrases to `bash` when this plan is applied. Do not rewrite their design.

---

## Leave alone

- **ℹ️** `docs/plans/done/` and `docs/bugs/done/` — dozens of hits. Closed.
- **ℹ️** `CHANGELOG.md` — release notes.
- **ℹ️** `docs/plans/CHAT-1.0-summary.md` — points at a rejected plan whose title mentions `run_command`.
- **ℹ️** `tests/markdown/repro-phone-web-fetch-frame.md` — a captured page, not an instruction.
- **ℹ️** `examples/oc-test-bubble.vala` — comments on the old allow-write grammar.

---

## Delete the tool

`liboctools/RunCommand/` goes away: `Tool.vala`, `Request.vala`, and `Bash.vala` (the alias file is not in `meson.build`).

### `liboctools/Registry.vala`

#### Remove

```vala
			typeof(RunCommand.Tool).ensure();
```

```vala
			OLLMchat.Tool.BaseTool.register_config(typeof(RunCommand.Tool));
```

```vala
			(new RunCommand.Tool(null)).setup_tool_config_default(config);
```

```vala
			manager.register_tool(new RunCommand.Tool(project_manager));
```

Drop `RunCommand` from the class docblock list.

### `liboctools/meson.build` and `docs/meson.build`

#### Remove

```vala
  'RunCommand/Tool.vala',
  'RunCommand/Request.vala',
```

```vala
    '../liboctools/RunCommand/Tool.vala',
    '../liboctools/RunCommand/Request.vala',
```

`docs/meson.build` has `FileVerification.vala` between those two lines. Leave that line.

### Comments that name the old class

- **🔷** `⏳` `liboctools/FileVerification.vala` docblock, `liboctools/EditMode/Tool.vala` comment, `liboctools/Child/Factory.vala` comment, `libollmchatgtk/ToolOutput.vala` docblock, `libollmchat/Tool/RequestBase.vala` comment.
- **💩** `libollmchatgtk/ChatWidget.vala` restores `bash` or `run_command` as the collapsed execution-results frame. Keep the `run_command` name so old sessions still paint.
- **💩** `liboctools/Bash/Request.vala` still writes `run_command-<request_id>.log`. Leave the spill prefix. Existing logs use it.
- **💩** `liboccoder/AgentPi/Factory.vala` forbid seed still lists `run_command`. Drop that name from the seed. The other forbidden names stay.

---

## LLM notes

- **🚫** Do not set `enabled = false` on `run_command` instead of deleting it. Enabling tools is the user's setting. This plan removes the tool.
- **🚫** Do not edit `docs/plans/done/` or `docs/bugs/done/` to rename history.
- **🚫** Phase D Stop button and Phase E Android `bash` registration. Not this plan.
- **🚫** Rewriting `RunCommand/Request.vala` so it shares a path with `bash`.
