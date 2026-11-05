# Tool output and code blocks are two incomplete widgets

**Status:** ⏳ design only. No product code. No patch.

## Problem

- 🔷 Reopen a session that ran `ls`.
  - 🔷 The listing is a collapsed frame.
  - 🔷 The title is Execution results.
- 🔷 While the command was running, that listing was the black tool pane.
  - 🔷 The command is in the header.
  - 🔷 Long lines scroll sideways.
- 🔷 Those are two widgets for one job.
  - 🔷 Each is missing what the other has.
  - 🔷 Neither can be both the live view and the restored view.
- 🔷 Building the live pane again at restore time is not a design.
  - 🔷 That leaves the split in place.

## The two widgets

- ℹ️ `OLLMchatGtk.ToolOutput` is the live shell pane.
  - ℹ️ `ChatWidget` creates it from `client.run_tool.start`.
  - ℹ️ It appends `client.run_tool.output`.
  - ℹ️ `close()` runs on `client.run_tool.end`.
- ℹ️ The pane has:
  - ℹ️ A command header.
  - ℹ️ A status line.
  - ℹ️ Stop.
  - ℹ️ Collapse.
  - ℹ️ A 2000-line cap.
  - ℹ️ Stick-to-bottom.
- ℹ️ The body is:
  - ℹ️ Black.
  - ℹ️ A fixed face.
  - ℹ️ No wrap.
  - ℹ️ Sideways scroll.
- ℹ️ The pane is not a markdown row.
  - ℹ️ No copy button.
  - ℹ️ No syntax language.
  - ℹ️ No place in the transcript row map.
- ℹ️ It is built only from those three notifications.
  - ℹ️ A saved session does not replay them.
  - ℹ️ The pane cannot build itself from a stored `tool` message.
- ℹ️ `MarkdownGtk.RenderSourceView` is the fenced block.
  - ℹ️ Assistant markdown uses it.
  - ℹ️ User quotes use it.
  - ℹ️ The restore path uses it.
- ℹ️ A fence can take text while it is parsed (`add_code_text`).
  - ℹ️ That includes an assistant message that is still streaming.
- ℹ️ The block has:
  - ℹ️ A language.
  - ℹ️ A frame theme.
  - ℹ️ Copy.
  - ℹ️ Height expand.
  - ℹ️ A row id.
- ℹ️ Wrap depends on the type.
  - ℹ️ Markdown wraps.
  - ℹ️ `raw` wraps.
  - ℹ️ Vala stays one line and scrolls sideways.
  - ℹ️ Python stays one line and scrolls sideways.
  - ℹ️ Other code does the same.
- ℹ️ The fence has no shell chrome.
  - ℹ️ No command header.
  - ℹ️ No Stop.
  - ℹ️ No status line.
  - ℹ️ No line cap.
  - ℹ️ No black shell face.
- ℹ️ Restore does not feed the fence the live notifications.
  - ℹ️ `ChatWidget.on_message_created` wraps the saved tail.
  - ℹ️ The fence header is `text.oc-frame-success.collapsed Execution results`.

## Why restore looks wrong

- ℹ️ The saved row is still a `tool` message.
  - ℹ️ `name` is `bash` or `run_command`.
  - ℹ️ `content` is the tail.
  - ℹ️ `tool_call_id` points at the assistant call.
  - ℹ️ The command is `arguments.command` on that call.
  - ℹ️ `is_ui_visible` is false.
- ℹ️ The restore branch exists because the live pane cannot be rebuilt.
  - ℹ️ The fence was the widget that can show a finished block.
  - ℹ️ That choice is [`TOOLS-2.6.5`](../plans/done/TOOLS-2.6.5-DONE-run-command-timeout-live-spill.md) §4a and §5.
- ✔️ The listing changes widget when the session is reopened.
  - ✔️ The fence was never the shell pane.
  - ✔️ The shell pane was never a restorable block.

## What one widget has to cover

- 🔷 The same listing in both cases.
  - 🔷 Chunks still arriving.
  - 🔷 The session opened again.
- 🔷 Shell output stays one line and scrolls sideways.
  - 🔷 The command stays in the header.
- 🔷 Markdown and raw text keep wrapping.
- 🔷 Vala and Python fences keep scrolling sideways.
  - 🔷 Those fences are not this widget.
- ⏳ 🔷 How a finished run is shown is part of the design.
  - ⏳ 🔷 Open or collapsed.
  - ⏳ 🔷 What the status line says.
  - ⏳ 🔷 Not settled here.
- 🚫 A restore-only constructor call on `ToolOutput`.
  - 🚫 That is not the fix.
- 🚫 Keep painting Execution results.
  - 🚫 And treat the live pane as a separate special case.

## Attempts / changelog

- ✔️ 2026-11-05 — first note proposed a `ChatWidget` branch.
  - ✔️ It built `ToolOutput` from the saved `tool` row.
  - ✔️ Withdrawn.
- ✔️ 2026-11-05 — product code still unchanged.

## Next

- ⏳ 🔷 Decide what the one widget is.
  - ⏳ 🔷 Which of today's two objects it grows from.
  - ⏳ 🔷 Before any code.
