# Bash execution frame is built and never shown

**Status:** ✔️ installed on the tablet. Waiting for a bash command to confirm the frame is on screen.

**ℹ️** The accepted shell-frame cut is closed: [`done/2026-11-05-CLOSED-restore-bash-tool-output.md`](done/2026-11-05-CLOSED-restore-bash-tool-output.md). This file is only the missing row.

## Problem

- 🔷 A bash command runs. The model receives the output.
- 🔷 The chat does not show the execution frame while it runs.
- 🔷 Reopening the session uses the same frame. That row is missing for the same reason.

## Evidence

- ✔️ 2026-11-08 — tablet `emulator-5556`, `org.roojs.ollmchat.androidpoc` pid 30273, installed 10:01. One call:
  - ✔️ `Executing tool 'bash'`.
  - ✔️ `Sandbox-Bubble.rpc_create`, `rpc_run`, and `wait` reply.
  - ✔️ RPC notifications `output` and `finished` arrive.
  - ✔️ `Tool 'bash' executed successfully, result length: 17, preview: done`. A later call stored 2435 bytes.
  - ✔️ The next chat log line is `waiting for ornith-1.5:35b to reply`.
  - ✔️ No crash on that path.
- ℹ️ The phone emulator does not have the app.
- ℹ️ A live `tool` row is not drawn. `Message` sets `is_ui_visible` false for `role=tool`, and `ChatWidget.on_message_created` returns on that flag unless the session is restoring.
- ℹ️ The listing is `MarkdownGtk.RenderToolOutput`. `ChatWidget` opens it from `client.run_tool.start` by calling `Render.on_code_block`. Restore opens the same class from a `bash` fence.
- ℹ️ `RenderSourceView` puts its frame in the chat with `this.renderer.box.appender(frame)` before setup returns.
- ✔️ `RenderToolOutput.construct` builds the header, status line, and body, then `this.set_child(col)`. It never calls `appender`.

## Root cause

- ✔️ The frame exists only as the `tool_view` pointer. It is not a child of the chat box, so nothing paints it. Command output still returns through `Sandbox-Bubble.wait`.

## Proposed fix

- 🔷 Put the frame in the chat box at the end of construction. Same call `RenderSourceView` uses for its frame.
- 🚫 A second widget, a restore-only path, or a change to the bash tool. The closed cut already builds this frame for both the live notifications and the restored fence.

### `libocmarkdowngtk/RenderToolOutput.vala` — `construct`: add the frame to the chat

**Why:** The shell frame is built and then left unparented. `appender` is what makes a row.

**Where:** end of `construct`, after `this.set_child(col)`.

#### Add

After `this.set_child(col)`, add the frame to the render box.

```vala
			this.renderer.box.appender(this);
```

## Attempts / changelog

- ✔️ 2026-11-08 — tablet logcat above. No product change.
- ✔️ 2026-11-09 — added `this.renderer.box.appender(this)` at the end of `RenderToolOutput.construct`.
- ✔️ 2026-11-09 — rebuilt `app-arm64-v8a-debug.apk` and installed it on `emulator-5556`.

## Next

- ⏳ 🔷 Run a bash command on the tablet. Confirm the frame is on screen while the command runs.
