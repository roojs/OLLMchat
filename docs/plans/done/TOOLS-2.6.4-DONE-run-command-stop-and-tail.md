# 2.6.4 Stop, tail, and live tool frame

> Split from the old `TOOLS-2.6.4-URGENT-run-command-stop-live-tail-spill.md`. Done timeout / live / spill: [`TOOLS-2.6.5-DONE-run-command-timeout-live-spill.md`](TOOLS-2.6.5-DONE-run-command-timeout-live-spill.md). VTE: [`TOOLS-2.6.6-FUTURE-run-command-vte.md`](../TOOLS-2.6.6-FUTURE-run-command-vte.md).

**Status:** **✔️** **DONE** — Stop, last-slice tail, permission bold command, live `tool_frame`. User asked to archive this cut.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

**Parent:** [`2.6-DONE-run-terminal-command-tool.md`](2.6-DONE-run-terminal-command-tool.md) · related: [`2.6.3-DONE-run-command-root-elevation.md`](2.6.3-DONE-run-command-root-elevation.md)

**Supersedes:** [`docs/bugs/done/2026-08-17-FIXED-run-command-unbounded-output.md`](../../bugs/done/2026-08-17-FIXED-run-command-unbounded-output.md) — kill-at-N was a stopgap; this cut keeps the process alive and returns a tail.

---

## Purpose

- **🔷** `✔️` **Stop** a running command from the UI (kill process group). Same path as a later wall-clock timeout.
- **🔷** `✔️` Do **not** kill because output is long. Let the command finish (or Stop / later timeout).
- **🔷** `✔️` The LLM gets a **tail** (last slice), not the head, and not a killed-for-length process.
- **🔷** `✔️` Permission row: the command is its own label, **bold**, larger than the warning text.
- **🔷** `✔️` Live run frame: bold command header + sandbox/root status + Stop. Not a persisted markdown “Running …” fence.
- **🔷** `✔️` Short-term: tool prompt forbids `#` comments in the command string.
- **🔷** `✔️` Frame RPC is generic so other tools can reuse it: `client.run_tool.start` / `client.run_tool.end` (not `run_command`).
- **ℹ️** Timeout / live stream / spill: **2.6.5** (done). Libsecret: **2.6.7** (done). Optional VTE: **2.6.6**.

---

## What landed

- **✔️** `OLLMchat.Tool.RequestBase.stop()` — virtual no-op.
- **✔️** `OLLMtools.RunCommand.Request.stop()` — set `stopped`; kill process group.
- **✔️** `OLLMbwrap.Bubble.stop()` — same for the sandbox child. Windows stub is empty.
- **✔️** `Agent.Base.active_tools` is public. ChatBar Stop and the frame Stop iterate it.
- **✔️** `Session.cancel_current_request` calls `stop()` on active tools, then HTTP cancel.
- **✔️** Rolling last **50** lines (`string[] tail`). Prefix: `// ... (output truncated: showing last 50 of N lines) ...`.
- **✔️** Results fence title stays **Execution results** / **Execution results (Command Failed)**. Stopped is a body line (`Command stopped by user.`).
- **✔️** `ChatWidget` `tool_frame` / `tool_header` / `tool_status`. CSS `.tool-frame` / `.command-preview`.
- **✔️** Show/hide via `this.agent.notification` methods `client.run_tool.start` / `client.run_tool.end`. `ActivityBanner` has no case; they stay off the status bar.
- **✔️** Frame Stop calls `Request.stop()` only — does **not** `cancel_current_request()`.
- **✔️** Permission `command_label` + `RequestBase.permission_command`. Warning copy no longer repeats `Command: …`.

**Files**

- **ℹ️** `libollmchat/Tool/RequestBase.vala`
- **ℹ️** `libollmchat/Agent/Base.vala`
- **ℹ️** `libollmchat/History/Session.vala`
- **ℹ️** `liboctools/RunCommand/Request.vala`
- **ℹ️** `liboctools/RunCommand/Tool.vala`
- **ℹ️** `libocbwrap/Bubble.vala`
- **ℹ️** `libocbwrap/windows/Bubble.vala`
- **ℹ️** `libollmchatgtk/ChatWidget.vala`
- **ℹ️** `libollmchatgtk/ChatPermission.vala`
- **ℹ️** `libollmchatgtk/Tools/Permission.vala`
- **ℹ️** `resources/style.css`

---

## LLM notes

- **🚫** Do not reintroduce kill-for-length (`output_killed`).
- **🚫** Do not put live stdout into `tool_frame` here — that is **2.6.5** Phase 4.
- **🚫** Do not add `CommandFrame.vala` — reserved for **2.6.6** VTE.
