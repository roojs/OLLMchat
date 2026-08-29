# 2.6.5 Timeout, live output, spill

> **Do not update `docs/plans/TOOLS-1.0-summary.md` for this plan.**

> Split from `TOOLS-2.6.4-URGENT-run-command-stop-live-tail-spill.md`. Done cut: [`done/TOOLS-2.6.4-DONE-run-command-stop-and-tail.md`](done/TOOLS-2.6.4-DONE-run-command-stop-and-tail.md). VTE is **not** here: [`TOOLS-2.6.6-FUTURE-run-command-vte.md`](TOOLS-2.6.6-FUTURE-run-command-vte.md). Libsecret + hold: [`TOOLS-2.6.7-run-command-libsecret-hold.md`](TOOLS-2.6.7-run-command-libsecret-hold.md).

**Status:** **ACTIVE**

- **✔️** Phase **4a** — live `ToolOutput` stream frame + restore display (agent)
- **✔️** Phase **4b** — spill file (agent)
- **✔️** Phase **3c** — `timeout` (agent)

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

**Parent:** [`done/2.6-DONE-run-terminal-command-tool.md`](done/2.6-DONE-run-terminal-command-tool.md) · related: [`done/2.6.3-DONE-run-command-root-elevation.md`](done/2.6.3-DONE-run-command-root-elevation.md), [`TOOLS-2.6.2-bwrap-ux-fixes.md`](TOOLS-2.6.2-bwrap-ux-fixes.md)

---

## Purpose

- **🔷** ✔️ Stuck runs hit a **default wall-clock timeout**. The model can raise it per call (`timeout`). Display durations as `60s`.
- **🔷** ✔️ **Live:** a **new** `ToolOutput` frame per run, added to the chat stream like any other frame. Collapse that instance when the run ends. Do **not** also show the standard tool-result frame while live.
- **🔷** ✔️ **Restore:** no `ToolOutput` (that buffer is not in the session). Show the **abbreviated** result that went to the LLM (`Message.tool_reply` / role `tool`) as the **standard** collapsed frame.
- **🔷** ✔️ Spill: always write the run to a file under the session’s sibling directory (`task_dir()` = session path without `.json`). If the run stays small (LLM already has the full text), delete the file; rmdir the folder if it is then empty.
- **🔷** ✔️ Live pane holds about **2000** lines (user can scroll back). That pane is **not** persisted. The LLM tail **is** persisted (`tool_reply` in `session.messages`).
- **🔷** ✔️ Emit in **500 ms** chunks (not per line). Flush leftover on `client.run_tool.end`.
- **🔷** ✔️ **Linux GTK** gets live UI first. **Windows** keeps subprocess + text frames with timeout/tail/spill where possible. **Android:** tool stays unregistered.
- **ℹ️** Libsecret + hold two seconds is [`TOOLS-2.6.7-run-command-libsecret-hold.md`](TOOLS-2.6.7-run-command-libsecret-hold.md).
- **ℹ️** Stop, last-50 tail, and `ChatWidget` `tool_frame` already landed in **2.6.4**. Reuse `Request.stop()` / `Bubble.stop()`. RPC methods are `client.run_tool.start` / `client.run_tool.output` / `client.run_tool.end`.

**Suggested order**

- **✔️** Phase **4a** GTK `ToolOutput` + live/restore display.
- **✔️** Phase **4b** spill.
- **✔️** Phase **3c** (`timeout`, display as `Ns`).

---

## Current behaviour

- **ℹ️** **2.6.4** constructor `ChatWidget.tool_frame` is gone. 4a GTK uses a new `ToolOutput` per run, left in the stream.
- **ℹ️** `execute_tools` already `add_message`s `Message.tool_reply` (role `tool`, last-50 tail). That is **session + LLM**. `is_ui_visible` is false live; restore paints `run_command` tool replies as collapsed `Execution results`.
- **ℹ️** Live `client.run_tool.output` chunks are consumed by `ChatWidget.current_output`.
- **ℹ️** Root runs: type password every time → `sudo -S true` check → pipe into `sudo -S /bin/sh -c …`. Copy says the password is not saved. See `ChatPermission.vala`, `Request.execute_with_subprocess()`.
- **ℹ️** **Windows:** `run_command` is registered. No bwrap, no sudo, no libsecret.
- **ℹ️** **Android:** tool is **not** registered.

---

## Platforms

- **🔷** **Linux GTK:** live bounded UI ✔️, spill file ✔️. Timeout ✔️. Libsecret: [`TOOLS-2.6.7-run-command-libsecret-hold.md`](TOOLS-2.6.7-run-command-libsecret-hold.md).
- **🔷** **Windows:** subprocess + text frames. Last-slice ✔️, spill ✔️. Timeout ✔️. No libsecret, no `run_as_root`.
- **🔷** ✔️ **Android:** leave the tool disabled. Do not register `run_command`. Do not add `libsecret` to the Android meson cut.
- **ℹ️** **Linux CLI** (`ollmchat-cli`): no `tool_frame`. Subprocess, last-slice ✔️, spill ✔️. Timeout ✔️. Notifications are no-ops for UI. No hold-password UI.

---

## Phase 3c — Timeout ✔️

Reuses `stop()` from **2.6.4**. JSON `timeout` binds via existing `Json.gobject_deserialize` on the public property. **Inline** — no `arm_timeout()` helper. Landed in `liboctools/RunCommand/Request.vala` and `Tool.vala`. Display the duration as `Ns` (e.g. `60s`), not the word `seconds`.

- **🔷** ✔️ Every `run_command` has a wall-clock timeout. When it fires, kill the process group (**same `stop()` as Stop**) and return the tail plus a clear timed-out line so the model can retry with a larger `timeout`.
- **🔷** ✔️ Tool argument **`timeout`** (seconds, integer). Document in `Tool.description` and `Tool.parameter_description`.
- **🔷** ✔️ Default **60s** when omitted.
- **🔷** `timeout <= 0` (no timer / wait until Stop) is **not** in this phase. That would need a second permission (we may not support stacking prompts). Decide later — no `ERROR:` reject and no infinite hang here.
- **🔷** ✔️ User **Stop** still works before the timer.
- **ℹ️** One `GLib.Timeout.add_seconds` in `execute()` immediately before `yield execute_tool_async`. Covers bwrap, Linux subprocess, and Windows. Setup before spawn is milliseconds, not idle-time.
- **ℹ️** `stop()` still sets `stopped`. Use `timed_out` so the LLM / live footer do **not** say `Command stopped by user.`

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `liboctools/RunCommand/Request.vala` — `timeout` property + kill on expiry ✔️

**Why:** Hung interactive prompts must not block the agent forever.

**Where:** property next to `allow_write`; fields next to `stopped`; arm in `execute()`; footer / LLM string after the run.

**Depends on:** **2.6.4** `stop()`.

- **🔷** ✔️ `GLib.Timeout.add_seconds(this.timeout, …)` sets `timed_out`, calls `this.stop()`, then lets wait/read finish.
- **🔷** ✔️ On exit: `GLib.Source.remove` the timeout id (`0` = none) in the existing `execute()` `finally`.
- **🔷** ✔️ When the timer fired: `Command timed out after Ns. Raise timeout in run_command if this was expected to run longer.`
- **🔷** ✔️ `to_summary()`: add `Timeout: Ns` when not 60.

##### Part 1 — property next to `allow_write`

**Where:** after `public string allow_write { get; set; default = "project"; }`.

#### Add — public `timeout` (JSON deserialize already maps this name)

```vala
		/**
		 * Wall-clock seconds before the child is killed.
		 * Omitted JSON uses 60.
		 */
		public int timeout { get; set; default = 60; }
```

##### Part 2 — fields next to `stopped`

**Where:** after `private bool stopped = false;`.

#### Add — `timed_out` + `timeout_src` (`0` = no source)

```vala
		private bool timed_out = false;
		private uint timeout_src = 0;
```

##### Part 3 — `to_summary()`: show non-default timeout

**Where:** after the `run_as_root` line, before `return string.joinv`.

#### Remove

```vala
			if (this.run_as_root) {
				lines += "Run as root: yes";
			}
			return string.joinv ("\n", lines);
```

#### Replace with

```vala
			if (this.run_as_root) {
				lines += "Run as root: yes";
			}
			if (this.timeout != 60) {
				lines += "Timeout: " + this.timeout.to_string() + "s";
			}
			return string.joinv ("\n", lines);
```

##### Part 4 — arm in `execute()`; remove in `finally`

**Where:** immediately before `try { return yield this.execute_tool_async(); }`; first lines of the existing `finally`.

#### Remove

```vala
			try {
				return yield this.execute_tool_async();
			} catch (Error e) {
				return "ERROR: " + e.message;
			} finally {
				if (this.pending_output_src != 0) {
					GLib.Source.remove(this.pending_output_src);
					this.pending_output_src = 0;
				}
```

#### Replace with

Arm once for bwrap + subprocess + Windows. Callback sets `timeout_src = 0` so `finally` does not double-remove.

```vala
			this.timeout_src = GLib.Timeout.add_seconds(this.timeout, () => {
				this.timed_out = true;
				this.stop();
				this.timeout_src = 0;
				return false;
			});
			try {
				return yield this.execute_tool_async();
			} catch (Error e) {
				return "ERROR: " + e.message;
			} finally {
				if (this.timeout_src != 0) {
					GLib.Source.remove(this.timeout_src);
					this.timeout_src = 0;
				}
				if (this.pending_output_src != 0) {
					GLib.Source.remove(this.pending_output_src);
					this.pending_output_src = 0;
				}
```

##### Part 5 — bwrap: LLM string + live footer

**Where:** `execute_tool_async` after the empty-output fallback, before `var footer`. `Bubble.exec` still appends `Command stopped by user.` when `stop()` ran — strip that and append the timeout line. Footer uses `timed_out` instead of `stopped`.

#### Remove

```vala
				if (output.strip() == "") {
					output = "No output received from command";
				}

				var footer = "";
				if (this.output_lines > 50) {
					footer += "// LLM received last 50 of " + this.output_lines.to_string() + " lines.\n";
					if (this.spill_path != "") {
						footer += "Full output: " + this.spill_path + "\n";
					}
				}
				if (this.stopped) {
					footer += "Command stopped by user.\n";
				}
```

#### Replace with

```vala
				if (output.strip() == "") {
					output = "No output received from command";
				}
				if (this.timed_out) {
					output = output.replace("\nCommand stopped by user.", "");
					output += "\nCommand timed out after " + this.timeout.to_string()
						+ "s. Raise timeout in run_command if this was expected to run longer.";
				}

				var footer = "";
				if (this.output_lines > 50) {
					footer += "// LLM received last 50 of " + this.output_lines.to_string() + " lines.\n";
					if (this.spill_path != "") {
						footer += "Full output: " + this.spill_path + "\n";
					}
				}
				if (this.timed_out) {
					footer += "Command timed out after " + this.timeout.to_string()
						+ "s. Raise timeout in run_command if this was expected to run longer.\n";
				}
				if (this.stopped && !this.timed_out) {
					footer += "Command stopped by user.\n";
				}
```

**ℹ️** `if (!this.stopped && exit_at >= 0)` stays. Timeout calls `stop()`, so the killed child’s exit code is not appended.

##### Part 6 — subprocess: LLM string + live footer

**Where:** `execute_with_subprocess` after building `output_content` from stdout/stderr; Linux footer after the chopped-spill lines. Windows already emits `output_content` as the body, so the LLM string change covers it.

#### Remove

```vala
			if (this.stopped) {
				output_content += "\nCommand stopped by user.";
			}
			if (!this.stopped && exit_status != 0) {
```

#### Replace with

```vala
			if (this.timed_out) {
				output_content += "\nCommand timed out after " + this.timeout.to_string()
					+ "s. Raise timeout in run_command if this was expected to run longer.";
			}
			if (this.stopped && !this.timed_out) {
				output_content += "\nCommand stopped by user.";
			}
			if (!this.stopped && exit_status != 0) {
```

#### Remove

```vala
			if (this.stopped) {
				footer += "Command stopped by user.\n";
			}
			if (!this.stopped && exit_status != 0) {
```

#### Replace with

```vala
			if (this.timed_out) {
				footer += "Command timed out after " + this.timeout.to_string()
					+ "s. Raise timeout in run_command if this was expected to run longer.\n";
			}
			if (this.stopped && !this.timed_out) {
				footer += "Command stopped by user.\n";
			}
			if (!this.stopped && exit_status != 0) {
```

### 2. `liboctools/RunCommand/Tool.vala` — describe timeout ✔️

**Where:** `description` after the Output bullets; `parameter_description` after `run_as_root`.

**Depends on:** §1 property name `timeout`.

##### Part 1 — `description` Timeout bullets

**Where:** after the last Output bullet, before `If the command fails`.

#### Remove

```
- If output is long, you see the **last** lines only (not the first). Prefer a narrow listing, or write to a file and read a slice.

If the command fails, you should handle the error gracefully and provide a helpful error message to the user.
```

#### Replace with

```
- If output is long, you see the **last** lines only (not the first). Prefer a narrow listing, or write to a file and read a slice.

Timeout:
- Default is 60s. Commands that block (SSH password, missing TTY) are killed at that cap.
- Set `timeout` (seconds) higher for installs, compiles, or other long jobs.

If the command fails, you should handle the error gracefully and provide a helpful error message to the user.
```

##### Part 2 — `parameter_description`

**Where:** after the `run_as_root` `@param` line, before `""" + allow_write_line`.

#### Remove

```
@param run_as_root {boolean} [optional] Run the command as root via sudo. Linux only. Defaults to false. Do not use sudo in the command string.
""" + allow_write_line;
```

#### Replace with

```
@param run_as_root {boolean} [optional] Run the command as root via sudo. Linux only. Defaults to false. Do not use sudo in the command string.
@param timeout {integer} [optional] Wall-clock seconds before the command is killed. Defaults to 60s. Increase for long jobs.
""" + allow_write_line;
```

---

## Phase 4 — Live output (bounded UI) + spill to file ✔️

**Why:** See progress and Stop on the existing pipe path. Avoid filling chat `TextBuffer` / markdown frames with megabytes.

### 4a. Live streaming — `ToolOutput` in the stream; restore uses `tool_reply` ✔️

- **🔷** ✔️ While the command runs, the user can **see output updating**.
- **🔷** ✔️ **`ToolOutput`** is a `Gtk.Frame` class. Construct it on `client.run_tool.start` and `add_widget_frame` it. Same place as other chat frames. **Not** a ChatWidget constructor singleton. **Not** cleared or reused.
- **🔷** ✔️ ChatWidget holds **only the live** `ToolOutput` so it can forward `client.run_tool.output`. That object owns scrolling and the 2000-line cap.
- **ℹ️** Finished frames stay alive because `ChatView.add_widget_frame` already `widgets.add(frame)` (`Gee.ArrayList<Gtk.Widget>`). `ChatView.clear()` (session switch / clear chat) `widgets.clear()` and removes the box children. Do **not** keep a second array on `ChatWidget`. Nullifying `current_output` is only the live routing pointer.
- **🔷** ✔️ On `client.run_tool.end`: `close()` that instance (hide Stop, collapse the body). The widget **stays in the stream**. Then **nullify** the live pointer. Next `start` constructs a **new** `ToolOutput`.
- **🔷** ✔️ **Live:** do **not** paint the standard tool-result frame (`Execution results` `ui` fence, or `tool_reply` in the chat). `ToolOutput` is the live view.
- **🔷** ✔️ **Session:** keep `Message.tool_reply` (already added in `execute_tools`). That is what the LLM got (last 50 + spill path when chopped). Do **not** persist the 2000-line `ToolOutput` buffer.
- **🔷** ✔️ **Restore:** `restoring_session` is true. No `ToolOutput`. For `role == "tool"` and `name == "run_command"`, render `m.content` as the **standard** collapsed fence (`text.oc-frame-success.collapsed Execution results`). Other tools unchanged (`tool` stays non-UI live).
- **🔷** ✔️ Do **not** `add_message(Message.fenced(… Execution results))` from `Request`. That would double on restore (fence + `tool_reply`) and double live if also shown.
- **🔷** ✔️ Do **not** append unbounded stdout into `RenderSourceView` / the chat markdown buffer.
- **🔷** ✔️ Do **not** pass a `Gtk.Widget` through `Message` or `Request`. `liboctools` stays GTK-free.
- **🔷** ✔️ About **2000** lines in that live instance; older lines drop. User can scroll back.
- **🔷** ✔️ Coalesce pipe reads into **500 ms** chunks. Flush leftover in `execute()` `finally` **before** `client.run_tool.end`.
- **🔷** ✔️ `client.run_tool.output` — `message` = chunk, `id` = `Request.request_id`. CLI / no GTK: emit is a no-op for UI.
- **🔷** ✔️ Stay pinned to the bottom while the user is at the bottom. If they scroll up, do **not** jump.
- **🔷** ✔️ Footer on the **live** `ToolOutput` **only** when chopped, **stopped**, or **failed** (via `client.run_tool.output` from `Request`). Clean success: **no** footer.
- **🔷** ✔️ Live output is **white on black**, monospace. CSS on `.tool-output` / `text`.
- **🔷** ✔️ Root run: frame chrome red (same idea as `.permission-widget.high-risk`). Terminal body stays black. `action == "Running command as root (sudo)"` → CSS class `root` on that `ToolOutput`.
- **ℹ️** Sandboxed Linux: `Bubble.read_from_channel`. Windows `communicate_utf8_async` has no line loop — still construct `ToolOutput` on start; body may fill from the one-shot `output` emit (4a Part 6).
- **ℹ️** Pending chunk is `string[]` + `string.joinv` like `tail`. No `StringBuilder`.
- **💩** ✔️ Viewport `max_content_height` **280**. Change if the pane feels short.
- **💩** `⏳` Restore fence uses `oc-frame-danger` when `m.content` has a non-zero `Exit code:` line. Confirm. Still always `oc-frame-success`.

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `liboctools/RunCommand/Request.vala` — pending chunk + 500 ms emit ✔️

**Why:** GTK-free Request pushes text. One pending buffer for subprocess and bwrap.

**Where:** fields next to `tail`; `execute()` `finally` before end; `read_stream_async` after each line; `execute_tool_async` after `this.bubble_active = true`.

**Depends on:** §2 `Bubble.output`.

**Inline** — no `flush_output()` / `queue_output()` helper. The Timeout lambda and the `finally` flush are duplicated on purpose (two read sites, one flush site).

##### Part 1 — fields next to `tail`

#### Add — after `private string[] tail = {};`

Pending lines since the last 500 ms flush. Same `string[]` + `joinv` as `tail`; empty the array on flush (do not prune this one).

```vala
		private string[] pending_output = {};
		private uint pending_output_src = 0;
```

##### Part 2 — `execute()` `finally`: flush then end

#### Remove

```vala
			} finally {
				this.agent.notification(new OLLMrpc.Notification() {
					method = "client.run_tool.end",
					message = this.command.strip(),
				});
			}
```

#### Replace with

Cancel a pending timeout so the last chunk is not delayed 500 ms after the process exits. Emit leftover, then end (`ToolOutput.close()`; ChatWidget nullifies the live pointer; the frame stays in the stream).

```vala
			} finally {
				if (this.pending_output_src != 0) {
					GLib.Source.remove(this.pending_output_src);
					this.pending_output_src = 0;
				}
				if (this.pending_output.length > 0) {
					this.agent.notification(new OLLMrpc.Notification() {
						method = "client.run_tool.output",
						message = string.joinv("\n", this.pending_output) + "\n",
						id = this.request_id,
					});
					this.pending_output = {};
				}
				this.agent.notification(new OLLMrpc.Notification() {
					method = "client.run_tool.end",
					message = this.command.strip(),
				});
			}
```

##### Part 3 — `read_stream_async` (Linux subprocess / root / no-bwrap)

#### Add — after `this.output_lines++;` inside the `while` (before the loop closes)

Same arm-timeout body as Part 4. `continue` when a timeout is already queued.

```vala
				this.pending_output += line;
				if (this.pending_output_src != 0) {
					continue;
				}
				this.pending_output_src = GLib.Timeout.add(500, () => {
					this.agent.notification(new OLLMrpc.Notification() {
						method = "client.run_tool.output",
						message = string.joinv("\n", this.pending_output) + "\n",
						id = this.request_id,
					});
					this.pending_output = {};
					this.pending_output_src = 0;
					return false;
				});
```

##### Part 4 — `execute_tool_async` connect `Bubble.output`

#### Add — after `this.bubble_active = true;` before `yield bubble.exec`

```vala
				bubble.output.connect((line) => {
					this.pending_output += line;
					this.output_lines++;
					if (this.pending_output_src != 0) {
						return;
					}
					this.pending_output_src = GLib.Timeout.add(500, () => {
						this.agent.notification(new OLLMrpc.Notification() {
							method = "client.run_tool.output",
							message = string.joinv("\n", this.pending_output) + "\n",
							id = this.request_id,
						});
						this.pending_output = {};
						this.pending_output_src = 0;
						return false;
					});
				});
```

##### Part 5 — `execute_tool_async`: no results fence; footer to the live frame

**Where:** after `bubble.exec` returns, replace the `add_message` fence. LLM still `return output`.

#### Remove

```vala
				var frame_header = "text.oc-frame-success.collapsed Execution results";
				this.agent.add_message(new OLLMchat.Message("ui",
					 OLLMchat.Message.fenced(frame_header, output)));
				
				// Return output to LLM
				return output;
```

#### Replace with

Footer **only** if chopped, stopped, or failed. Clean success: skip. Then `return output` to the LLM.

```vala
				var footer = "";
				if (this.output_lines > 50) {
					footer += "// LLM received last 50 of " + this.output_lines.to_string() + " lines.\n";
				}
				if (this.stopped) {
					footer += "Command stopped by user.\n";
				}
				var exit_at = output.index_of("Exit code:");
				if (!this.stopped && exit_at >= 0) {
					footer += output.substring(exit_at);
				}
				if (footer != "") {
					this.agent.notification(new OLLMrpc.Notification() {
						method = "client.run_tool.output",
						message = footer,
						id = this.request_id,
					});
				}
				return output;
```

##### Part 6 — `execute_with_subprocess`: same, drop the fence

#### Remove

```vala
		// Send output as second message (danger when command failed, success when exit 0)
			var frame_header = "text.oc-frame-success.collapsed Execution results";
			if (exit_status != 0) {
				frame_header = "text.oc-frame-danger.collapsed Execution results (Command Failed)";
			}
			this.agent.add_message(new OLLMchat.Message("ui", 
				OLLMchat.Message.fenced(frame_header, output_content)));
```

#### Replace with

Linux: footer only if chopped / stopped / failed. Windows never streamed — emit `output_content` as the body (that is the view, not a “success footer”).

```vala
#if G_OS_WIN32
			this.agent.notification(new OLLMrpc.Notification() {
				method = "client.run_tool.output",
				message = output_content + "\n",
				id = this.request_id,
			});
#else
			var footer = "";
			if (this.output_lines > 50) {
				footer += "// LLM received last 50 of " + this.output_lines.to_string() + " lines.\n";
			}
			if (this.stopped) {
				footer += "Command stopped by user.\n";
			}
			if (!this.stopped && exit_status != 0) {
				footer += "Exit code: " + exit_status.to_string();
				if (!this.network) {
					footer += " - Note: Networking is disabled by default. Pass \"network\": true in the "
						+ this.tool.name + " arguments to enable it.";
				}
				footer += "\n";
			}
			if (footer != "") {
				this.agent.notification(new OLLMrpc.Notification() {
					method = "client.run_tool.output",
					message = footer,
					id = this.request_id,
				});
			}
#endif
```

### 2. `libocbwrap/Bubble.vala` — `output` signal from `read_from_channel` ✔️

**Why:** Default Linux GTK path is bwrap. `Bubble.exec` collects the 50-line tail internally; Request never sees lines unless Bubble emits.

**Where:** class body near `stopped`; `read_from_channel` after the tail update.

**Depends on:** none.

**ℹ️** Windows stub `libocbwrap/windows/Bubble.vala` does not need the signal (`can_wrap` is false).

##### Part 1 — signal

#### Add — after `public bool stopped { get; private set; default = false; }`

```vala
		public signal void output(string line);
```

##### Part 2 — emit each line

#### Remove

```vala
			if (this.tail.length >= 50) {
				this.tail = this.tail[1:this.tail.length];
			}
			this.tail += buffer.chomp();
			this.output_lines++;
```

#### Replace with

```vala
			var line = buffer.chomp();
			if (this.tail.length >= 50) {
				this.tail = this.tail[1:this.tail.length];
			}
			this.tail += line;
			this.output_lines++;
			this.output(line);
```

### 3. `libollmchatgtk/ToolOutput.vala` — new stream frame (one per run) ✔️

**Why:** Live output is a normal chat frame, not a ChatWidget singleton buffer.

**Where:** new file. `Gtk.Frame` subclass. Methods `output` and `close` (user: send chunks to the object; object owns scroll; end does not remove it from the stream).

**Depends on:** §1 `client.run_tool.output`.

**🔷** User asked for this class.

#### Add — new file `libollmchatgtk/ToolOutput.vala`

```vala
namespace OLLMchatGtk
{
	/**
	 * Live ''run_command'' pane. One instance per run, added to the chat
	 * stream like any other frame. Stays after the command ends.
	 *
	 * @since 1.0
	 */
	public class ToolOutput : Gtk.Frame
	{
		private Gtk.Button stop;
		private Gtk.Button collapse;
		private Gtk.Revealer body;
		private Gtk.ScrolledWindow scroll;
		private Gtk.TextView view;
		private OLLMchat.History.Manager manager;

		/**
		 * @param manager History manager (Stop uses session.agent.active_tools).
		 * @param command Command line from ''client.run_tool.start'' message.
		 * @param action Status line from ''client.run_tool.start'' action.
		 */
		public ToolOutput(OLLMchat.History.Manager manager, string command, string action)
		{
			this.manager = manager;
			this.add_css_class("tool-frame");
			if (action == "Running command as root (sudo)") {
				this.add_css_class("root");
			}
			var header = new Gtk.Label("") {
				halign = Gtk.Align.START,
				ellipsize = Pango.EllipsizeMode.END,
				use_markup = true,
				hexpand = true
			};
			header.add_css_class("command-preview");
			header.tooltip_text = command;
			header.label = "<b>" + GLib.Markup.escape_text(command) + "</b>";
			var status = new Gtk.Label(action) {
				halign = Gtk.Align.START,
				wrap = true
			};
			this.body = new Gtk.Revealer() {
				reveal_child = true,
				hexpand = true
			};
			this.collapse = new Gtk.Button() {
				icon_name = "go-up-symbolic",
				tooltip_text = "Collapse",
				valign = Gtk.Align.CENTER
			};
			this.collapse.clicked.connect(() => {
				this.body.reveal_child = !this.body.reveal_child;
				this.collapse.icon_name = this.body.reveal_child
					? "go-up-symbolic" : "go-next-symbolic";
				this.collapse.tooltip_text = this.body.reveal_child
					? "Collapse" : "Expand";
			});
			this.stop = new Gtk.Button.with_label("Stop") {
				valign = Gtk.Align.CENTER
			};
			this.stop.add_css_class("destructive-action");
			this.stop.clicked.connect(() => {
				foreach (var req in this.manager.session.agent.active_tools.values) {
					req.stop();
				}
			});
			var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
			row.append(this.collapse);
			row.append(header);
			row.append(this.stop);
			this.view = new Gtk.TextView() {
				editable = false,
				cursor_visible = false,
				wrap_mode = Gtk.WrapMode.CHAR,
				monospace = true
			};
			this.view.add_css_class("tool-output");
			this.scroll = new Gtk.ScrolledWindow() {
				min_content_height = 80,
				max_content_height = 280,
				propagate_natural_height = true,
				hexpand = true,
				vexpand = false
			};
			this.scroll.add_css_class("tool-output");
			this.scroll.set_child(this.view);
			this.body.set_child(this.scroll);
			var col = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
			col.append(row);
			col.append(status);
			col.append(this.body);
			this.set_child(col);
		}

		/**
		 * Append a chunk. Cap at 2000 lines. Stick to bottom only if already there.
		 *
		 * @param chunk Text from ''client.run_tool.output'' message.
		 */
		public void output(string chunk)
		{
			var adj = this.scroll.get_vadjustment();
			var stick = adj.value >= adj.upper - adj.page_size - 8.0;
			Gtk.TextIter end;
			this.view.buffer.get_end_iter(out end);
			this.view.buffer.insert(ref end, chunk, -1);
			var extra = this.view.buffer.get_line_count() - 2000;
			if (extra > 0) {
				Gtk.TextIter start;
				Gtk.TextIter cut;
				this.view.buffer.get_start_iter(out start);
				this.view.buffer.get_iter_at_line(out cut, extra);
				this.view.buffer.delete(ref start, ref cut);
			}
			if (stick) {
				adj.value = adj.upper - adj.page_size;
			}
		}

		/**
		 * Run finished. Hide Stop and collapse. Leave this frame in the stream.
		 */
		public void close()
		{
			this.stop.visible = false;
			this.body.reveal_child = false;
			this.collapse.icon_name = "go-next-symbolic";
			this.collapse.tooltip_text = "Expand";
		}
	}
}
```

### 4. `libollmchatgtk/ChatWidget.vala` — live pointer; drop constructor `tool_frame` ✔️

**Why:** ChatWidget only routes start/output/end. The frame lives in the stream.

**Where:** drop `tool_frame` / `tool_header` / `tool_status` and the constructor widget block; replace `notification.connect`.

**Depends on:** §3 `ToolOutput`.

##### Part 1 — fields

#### Remove

```vala
		private Gtk.Frame tool_frame;
		private Gtk.Label tool_header;
		private Gtk.Label tool_status;
```

#### Replace with

Live pointer only. Null after `close()`. Finished frames stay parented in `ChatView`.

```vala
		private ToolOutput? current_output;
```

##### Part 2 — constructor: drop singleton frame; route notifications

#### Remove

```vala
			this.tool_header = new Gtk.Label("") {
				halign = Gtk.Align.START,
				ellipsize = Pango.EllipsizeMode.END,
				use_markup = true,
				hexpand = true
			};
			this.tool_header.add_css_class("command-preview");
			this.tool_status = new Gtk.Label("") {
				halign = Gtk.Align.START,
				wrap = true
			};
			var stop_btn = new Gtk.Button.with_label("Stop") {
				valign = Gtk.Align.CENTER
			};
			stop_btn.add_css_class("destructive-action");
			stop_btn.clicked.connect(() => {
				foreach (var req in this.manager.session.agent.active_tools.values) {
					req.stop();
				}
			});
			var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
			row.append(this.tool_header);
			row.append(stop_btn);
			var col = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
			col.append(row);
			col.append(this.tool_status);
			this.tool_frame = new Gtk.Frame(null);
			this.tool_frame.add_css_class("tool-frame");
			this.tool_frame.set_child(col);
			this.manager.notification.connect((notif) => {
				if (notif.method == "client.run_tool.start") {
					this.tool_header.tooltip_text = notif.message;
					this.tool_header.label = "<b>"
						+ GLib.Markup.escape_text(notif.message) + "</b>";
					this.tool_status.label = notif.action;
					this.chat_view.add_widget_frame(this.tool_frame);
					return;
				}
				if (notif.method != "client.run_tool.end") {
					return;
				}
				if (this.tool_frame.get_parent() != null) {
					this.tool_frame.unparent();
				}
			});
```

#### Replace with

On start: new `ToolOutput`, `add_widget_frame`. On output: `current_output.output`. On end: `close()`, then nullify. Do not unparent. Do not clear a shared buffer.

```vala
			this.manager.notification.connect((notif) => {
				switch (notif.method) {
				case "client.run_tool.start":
					this.current_output = new ToolOutput(
						this.manager, notif.message, notif.action);
					this.chat_view.add_widget_frame(this.current_output);
					return;

				case "client.run_tool.output":
					this.current_output.output(notif.message);
					return;

				case "client.run_tool.end":
					this.current_output.close();
					this.current_output = null;
					return;
				}
			});
```

### 5. `libollmchatgtk/ChatWidget.vala` — restore paints `tool_reply`; live does not ✔️

**Why:** `tool_reply` is already in `session.messages` (LLM tail). Live already has `ToolOutput`. Restore has no live pane, so show the standard abbreviated frame.

**Where:** `on_message_created`, after scroll, **before** the `is_ui_visible` skip. Session check first (restore uses `session`).

**Depends on:** §4. `ChatWidget.restoring_session` already true during history load.

#### Remove

```vala
			if (!this.restoring_session) {
				this.chat_view.scroll_enabled = true;
			}
			
			// Skip messages that shouldn't be displayed in UI
			if (!m.is_ui_visible) {
				return;
			}
			
			// Session is required for rendering messages
			if (session == null) {
				GLib.warning("ChatWidget.on_message_created: session is null, cannot render message");
				return;
			}
```

#### Replace with

Live: `role == "tool"` stays hidden (`is_ui_visible` false). Restore: `run_command` tail as the usual collapsed fence.

```vala
			if (!this.restoring_session) {
				this.chat_view.scroll_enabled = true;
			}
			if (session == null) {
				GLib.warning("ChatWidget.on_message_created: session is null, cannot render message");
				return;
			}
			if (this.restoring_session && m.role == "tool" && m.name == "run_command") {
				var ui_msg = new OLLMchat.Message("assistant",
					OLLMchat.Message.fenced(
						"text.oc-frame-success.collapsed Execution results",
						m.content),
					m.thinking);
				ui_msg.idx_last = this.chat_view.append_complete_assistant_message(ui_msg, session);
				ui_msg.idx_first = this.chat_view.render_box.first_id;
				m.idx_first = ui_msg.idx_first;
				m.idx_last = ui_msg.idx_last;
				return;
			}
			if (!m.is_ui_visible) {
				return;
			}
```

### 6. `libollmchatgtk/meson.build` + `docs/meson.build` — compile `ToolOutput.vala` ✔️

**Where:** `ollmchatgtk_src` after `'ChatWidget.vala'`; valadoc list after `ChatWidget.vala`.

#### Add — in `libollmchatgtk/meson.build` after `'ChatWidget.vala',`

```meson
  'ToolOutput.vala',
```

#### Add — in `docs/meson.build` after `'../libollmchatgtk/ChatWidget.vala',`

```meson
    '../libollmchatgtk/ToolOutput.vala',
```

### 7. `resources/style.css` — monospace live output ✔️

**Why:** Command output should read as a terminal: monospace, white on black.

**Where:** after `.tool-frame .command-preview`.

#### Add — after the `.tool-frame .command-preview` rule

```css
.tool-frame .tool-output,
.tool-frame .tool-output text {
  font-family: monospace;
  font-size: 0.9em;
  background-color: #000000;
  color: #ffffff;
}

.tool-frame.root {
  background-color: #ffe4e1;
  border: 2px solid #c0392b;
}
```

### 4b. Save output + spill (next after 4a) ✔️

**Why:** Full output on disk when the LLM only got a tail. Sidecar next to the session JSON, not `/tmp`.

**Where:** `Request` — open a file at spawn; append each line in the same loops as `pending_output`; after the run, keep or delete.

**Depends on:** 4a live chunks. `History.Session.task_dir()` (already `history_dir / to_path()`, sibling of `to_path() + ".json"`).

- **🔷** ✔️ Default: **create and write** the file as the command runs (every line). Do not wait for a size threshold to start writing.
- **🔷** ✔️ Directory: `session.task_dir()` — same path as the session file **without** `.json` (e.g. `…/history/2026/04/06/11-28-38/` next to `11-28-38.json`). `EmptySession.task_dir()` is `""` — skip the file (CLI / no session).
- **🔷** ✔️ File in that directory: `run_command-` + `request_id` + `.log`. One file, stdout and stderr concatenated (today’s merge).
- **🔷** ✔️ On completion: if the run was **small** (not chopped — `output_lines <= 50`, so the tool return already is the full text), **delete** the log. Then if the directory has nothing left, **delete the directory**.
- **🔷** ✔️ If chopped (or later spill-worthy): **keep** the file. Tool return (and live footer, which already fires when chopped) includes the **absolute path** so the model can `read_file`.
- **ℹ️** `task_dir()` is also occoder’s task-list folder. Only `GLib.File.delete` the log; `delete` the dir only when empty (fails if `task-list.md` is there — leave it).
- **ℹ️** Get the dir from `(OLLMchat.Agent.Base) this.agent` → `session.task_dir()`. Dummy agents without `Base`: skip.
- **💩** `⏳` bwrap `read_file` / sandbox may not see `~/.local/share/ollmchat/history`. Path is still this (user chose session sidecar). Bind/visibility later if the model cannot read it. (Not a 4b code gap — follow-up if the model cannot read the log.)

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 5. `liboctools/RunCommand/Request.vala` — spill file (4b, after 4a) ✔️

**Why:** Always stream to disk; drop the file when it duplicates the tool return.

**Where:** field next to `pending_output`; open after `client.run_tool.start`; append in Part 3 / Part 4 line loops; keep-or-delete after the LLM string is built (same places as the footer).

**Depends on:** 4a Parts 1–4.

**Inline** — no `open_spill()` / `close_spill()` helpers.

##### Part 1 — fields

#### Add — after `pending_output_src`

```vala
		private GLib.FileOutputStream spill_stream;
		private bool spill_active = false;
		private string spill_path = "";
```

##### Part 2 — open after start notification in `execute()`

#### Add — after the `client.run_tool.start` notification, before `try { return yield this.execute_tool_async(); }`

Cast to `Agent.Base` for `session.task_dir()`. Skip when the dir is empty.

```vala
			var agent_base = this.agent as OLLMchat.Agent.Base;
			if (agent_base != null) {
				var dir = agent_base.session.task_dir();
				if (dir != "") {
					this.spill_path = GLib.Path.build_filename(
						dir, "run_command-" + this.request_id.to_string() + ".log");
					this.spill_stream = GLib.File.new_for_path(this.spill_path).replace(
						null, false, GLib.FileCreateFlags.PRIVATE, null);
					this.spill_active = true;
				}
			}
```

##### Part 3 — append each line (same sites as `pending_output += line`)

#### Add — immediately after `this.pending_output += line;` (read_stream_async and `bubble.output` connect)

```vala
				if (this.spill_active) {
					this.spill_stream.write_all((line + "\n").data, null);
				}
```

##### Part 4 — keep or delete after the run

#### Add — after the footer notification (Parts 5–6), before `return`

Close the stream first. Chopped → keep path in the return string. Else delete log; try-delete the directory (empty only).

```vala
			if (this.spill_active) {
				this.spill_stream.close(null);
				this.spill_active = false;
				if (this.output_lines > 50) {
					output = output + "\nFull output: " + this.spill_path + "\n";
				} else {
					GLib.File.new_for_path(this.spill_path).delete(null);
					try {
						GLib.File.new_for_path(GLib.Path.get_dirname(this.spill_path)).delete(null);
					} catch (GLib.Error e) {
					}
				}
			}
```

**ℹ️** Subprocess path uses `output_content` not `output` — same keep/delete on `output_content`. Windows: write `output_content` to the spill file once after `communicate_utf8_async` if the stream was opened (no line loop).

**ℹ️** Empty `catch` on dir delete: not empty (task files) or not ours — leave the dir.

### 4c. Open design ✔️

- **🔷** ✔️ Stream every line to the spill file as it arrives (4b). RAM stays the 50-line `tail` + 2000-line UI + pending chunk.
- **🔷** ✔️ stderr in the **same** log (concatenated, as today).
- **💩** ✔️ If `replace()` / `write_all` throws, skip spill (do not fail the command). Confirm.

---

## LLM notes

- **🚫** Do not kill the child because the tail is long.
- **🚫** Do not implement libsecret / hold-password here — that is **2.6.7**.
- **🚫** Do not use `GLib.StringBuilder` for the 500 ms pending chunk — `string[]` + `string.joinv` like `tail`.
- **🚫** Do not add `queue_output` / `flush_output` / `append_to_widget` — arm the 500 ms timeout inline at both read sites; flush inline in `execute()` `finally`.
- **🚫** Do not resurrect `OLLMchatGtk.Message` or put a widget `GLib.Object` on `OLLMchat.Message` for live output.
- **🚫** Do not stream live stdout on Windows `communicate_utf8_async` in 4a (no line loop). Start/end frame only.
- **🚫** Do not add a live-frame footer on a clean success (not chopped, not stopped, exit 0).
- **🚫** Do not add a second `ToolOutput[]` / `Gee.ArrayList` on `ChatWidget`. `ChatView.widgets` already strong-refs frames and clears them on `clear()`.
- **🚫** Do not `add_message(Message.fenced(… Execution results))` from `Request` — live is `ToolOutput`; restore paints `tool_reply`.
- **🚫** Do not paint `role == "tool"` / `run_command` in the chat **while live** (`ToolOutput` is already there).
- **🚫** Do not persist the 2000-line `ToolOutput` buffer into `session.messages`. The LLM tail is already `Message.tool_reply`.
- **🚫** Do not skip storing `tool_reply` — restore has nothing else to show.
- **🚫** Do not construct `Gtk.Widget` / `GtkSource.View` in `liboctools`. Do not register `OLLMwebkit.Tool` from `OLLMtools.Registry`.
- **🚫** Do not stream live stdout into `Message.fenced` / `RenderSourceView`. Restore may fence `tool_reply.content`; live uses `ToolOutput`.
- **🚫** Do not implement VTE, add `CommandFrame.vala`, or add `vte-2.91-gtk4` — that is **2.6.6**.
- **🚫** Do not design Phase 4 to require a PTY (pipe + bounded UI + spill must stand alone).
- **🚫** Do not register `run_command` on Android in this plan.
- **🚫** Do not use output-idle as the timeout (elapsed time from spawn only).
- **🚫** Do not add `arm_timeout()` — one `GLib.Timeout.add_seconds` inline in `execute()`.
- **🚫** Do not change `Bubble.exec`'s `Command stopped by user.` line — Request strips it when `timed_out`.
- **🚫** Do not wait forever when `timeout` is omitted.
- **🚫** Do not spill into `/tmp` or a host-only temp — use `session.task_dir()` (sibling of the session JSON).
- **🚫** Do not wait for a size threshold before creating the spill file — write from the first line; delete after if not chopped.
