# run_command unbounded output (`ls -RL ~`)

**Status:** ✔️ Applied as stopgap (kill at 100/50) — **superseded** by [`docs/plans/done/TOOLS-2.6.4-DONE-run-command-stop-and-tail.md`](../plans/done/TOOLS-2.6.4-DONE-run-command-stop-and-tail.md) (Stop + last-slice tail landed). Remaining live/spill/timeout: [`TOOLS-2.6.5-run-command-timeout-live-spill.md`](../plans/TOOLS-2.6.5-run-command-timeout-live-spill.md). Do not extend kill-for-length further.

**Started:** 2026-08-17

**Process:** `docs/bug-fix-process.md` — edits are **Remove** / **Replace with** / **Add** from `docs/guide-to-writing-plans.md`.

---

## Problem

🔷 LLM ran `ls -RL` on the home directory. Output was massive.

🔷 Do **not** whitelist / blacklist commands.

🔷 Monitor output while the command runs. If it exceeds the **existing** line cap, **kill** the command. Return whatever output was captured. The notice must tell the LLM how to recover: avoid outputting large files to stdout; write to a file or limit the output.

🔷 Do **not** change the existing caps: **100** lines on the sandbox (`bwrap`) path, **50** on the unsandboxed fallback (and Windows post-hoc truncate). The 200 figure was a misunderstanding of a new cap.

🔷 Advise the agent in the `run_command` / `bash` tool description against unbounded listings (e.g. `ls -RL` on home).

ℹ️ **Supersession:** Product direction is no longer kill-for-length. Prefer let-finish + **tail** to the LLM + **spill file** for retrieval + user **Stop** / timeout ([2.6.4](../plans/done/TOOLS-2.6.4-DONE-run-command-stop-and-tail.md) done; [2.6.5](../plans/TOOLS-2.6.5-run-command-timeout-live-spill.md) timeout / live / spill).

---

## Evidence

ℹ️ `libocbwrap/Bubble.vala` `read_subprocess_output` / `read_from_channel` accumulate **every** stdout/stderr line into `ret_str` / `fail_str`, then `wait_async` until the process **exits**.

ℹ️ `liboctools/RunCommand/Request.vala` `execute_tool_async` only calls `truncate_output(output, 100)` **after** `yield bubble.exec(...)`. The non-bwrap path does the same with `truncate_output(..., 50)` after both streams are fully read.

✔️ Truncation is post-hoc. `ls -RL ~` still runs to completion, fills memory, and blocks the tool until the listing finishes. The LLM then sees 50–100 lines as if the run were small.

ℹ️ Related historical note: `docs/bugs/done/2026-04-28-FIXED-run-command-bwrap-hang-no-output.md` already flagged unbounded stdio as a follow-up (pipe fill / long output), separate from the spawn deadlock that was fixed.

---

## Root cause

✔️ The cap is applied to the **string returned to the LLM**, not to the **running process**. There is no line counter and no kill during read.

---

## Proposed fix

🔷 Count stdout + stderr lines as they arrive (combined). At the existing cap (100 in `Bubble`, 50 in `execute_with_subprocess`), stop appending, kill the command, return captured output plus (N is that cap):

`Command killed: output exceeded N lines. Avoid outputting large files to stdout; consider writing to a file or limiting what you are outputting.`

🔷 No command allow/deny lists.

🔷 Tool description: warn against recursive/unbounded listings and say over-limit output is killed (no new number — 50 vs 100 already differ by path). `bash` inherits `Tool.description` — one edit covers both.

💩 `Posix.setpgid(0, 0)` in the existing `child_setup` so `Posix.kill(-pid, SIGKILL)` reaches `ls` under `/bin/sh -c` and under `bwrap`. `force_exit()` alone only kills the direct child (`bwrap` or `sh`); the listing would keep running. `get_identifier()` is a pid string, or `null` if the child has already exited — not `""`.

💩 Keep the first N lines of the existing cap; kill when the next line would be appended.

💩 Skip the usual non-zero-exit / network hint when the kill was for excessive output.

💩 Unix non-bwrap path (`execute_with_subprocess` + `read_stream_async`): kill at the existing **50**. Windows `communicate_utf8_async` cannot stream-kill; keep the existing post-hoc `truncate_output(..., 50)` there.

🔷 A new `Bubble` is constructed per `run_command`. Do **not** reset `ret_str` / `fail_str` / `output_lines` / `output_killed` at read time — `default =` on the properties is enough. Drop the existing `ret_str` / `fail_str` clear in `read_subprocess_output`. Same for `Request`: one deserialize per tool call, so field defaults, no reset at the start of `execute_with_subprocess`.

🚫 Command whitelist / blacklist.

🚫 Named `const` for the line limit — use the existing literals `100` / `50` at the use site.

🚫 Changing the cap from 100/50 to 200.

🚫 New helper methods (`ensure_*`, extract “kill if excessive”, etc.). Inline in the methods that already read stdio.

🚫 Byte cap for newline-less floods (e.g. `cat /dev/zero`) — not requested.

🚫 MCP stdio servers — out of scope.

---

### 1. `libocbwrap/RunSeccomp.vala` — `wire_launcher`: process group for kill

**Why:** Killing only `bwrap` leaves `sh` / `ls` running unless they share a process group.

**Where:** `wire_launcher` — socketpair-failure return, and the existing `set_child_setup` lambda.

**Depends on:** none.

#### Remove
```vala
			if (Posix.socketpair(Posix.AF_UNIX, Posix.SOCK_STREAM, 0, sv) != 0) {
				this.skipped = "seccomp: socketpair failed";
				return;
			}
```

#### Replace with
```vala
			if (Posix.socketpair(Posix.AF_UNIX, Posix.SOCK_STREAM, 0, sv) != 0) {
				this.skipped = "seccomp: socketpair failed";
				launcher.set_child_setup(() => {
					Posix.setpgid(0, 0);
				});
				return;
			}
```

#### Remove
```vala
			launcher.set_child_setup(() => {
				this.child_seccomp_handshake();
			});
```

#### Replace with
```vala
			launcher.set_child_setup(() => {
				Posix.setpgid(0, 0);
				this.child_seccomp_handshake();
			});
```

---

### 2. `libocbwrap/Bubble.vala` — fields for line count / killed

**Why:** Request and `read_subprocess_output` need to know the run was killed for output, not a normal non-zero exit.

**Where:** class body, immediately after `fail_str`.

**Depends on:** none.

#### Add — after `fail_str` property: line counter + killed flag
```vala
		/**
		 * Combined stdout+stderr lines read during {@link exec}.
		 */
		private int output_lines = 0;

		/**
		 * True when the subprocess was killed because output exceeded 100 lines.
		 */
		public bool output_killed { get; private set; default = false; }
```

---

### 3. `libocbwrap/Bubble.vala` — `read_subprocess_output`: kill, return notice

**Why:** Live cap must live where IOChannel watches already read lines. Accumulators start empty from property defaults; this method must not re-clear them.

**Where:** `read_subprocess_output` — drop the leftover accumulator clear; both `add_watch` IN branches; return value before the `exit_status == 0` split.

**Depends on:** §1, §2.

##### Part 1 — drop leftover `ret_str` / `fail_str` clear

`ret_str` and `fail_str` already have `default = ""`. A new Bubble is used once (`Request` constructs it, MCP stdio uses `build_bubble_args` only). Clearing at read time is leftover.

#### Remove
```vala
		// Reset accumulators for this execution
		this.ret_str = "";
		this.fail_str = "";
		
```

##### Part 2 — stdout watch: kill process group after the 100-line cap

#### Remove
```vala
			(channel, condition) => {
				if ((condition & GLib.IOCondition.IN) != 0) {
					this.read_from_channel(channel, true);
				}
				if ((condition & (GLib.IOCondition.HUP | GLib.IOCondition.ERR)) != 0) {
					stdout_open = false;
					return false; // Remove watch
				}
				return stdout_open; // Keep watching if still open
			}
```

#### Replace with
```vala
			(channel, condition) => {
				if ((condition & GLib.IOCondition.IN) != 0) {
					this.read_from_channel(channel, true);
					if (this.output_killed) {
						var id = subprocess.get_identifier();
						if (id != null) {
							Posix.kill(-(int.parse(id)), Posix.Signal.KILL);
						}
						subprocess.force_exit();
					}
				}
				if ((condition & (GLib.IOCondition.HUP | GLib.IOCondition.ERR)) != 0) {
					stdout_open = false;
					return false; // Remove watch
				}
				return stdout_open; // Keep watching if still open
			}
```

##### Part 3 — stderr watch: same kill

#### Remove
```vala
			(channel, condition) => {
				if ((condition & GLib.IOCondition.IN) != 0) {
					this.read_from_channel(channel, false);
				}
				if ((condition & (GLib.IOCondition.HUP | GLib.IOCondition.ERR)) != 0) {
					stderr_open = false;
					return false; // Remove watch
				}
				return stderr_open; // Keep watching if still open
			}
```

#### Replace with
```vala
			(channel, condition) => {
				if ((condition & GLib.IOCondition.IN) != 0) {
					this.read_from_channel(channel, false);
					if (this.output_killed) {
						var id = subprocess.get_identifier();
						if (id != null) {
							Posix.kill(-(int.parse(id)), Posix.Signal.KILL);
						}
						subprocess.force_exit();
					}
				}
				if ((condition & (GLib.IOCondition.HUP | GLib.IOCondition.ERR)) != 0) {
					stderr_open = false;
					return false; // Remove watch
				}
				return stderr_open; // Keep watching if still open
			}
```

##### Part 4 — return captured output + killed notice (skip generic exit-code failure)

#### Add — immediately before `if (exit_status == 0)`
```vala
		if (this.output_killed) {
			GLib.debug("command killed: output exceeded 100 lines");
			return this.ret_str + "\n" + this.fail_str
				+ "\nCommand killed: output exceeded 100 lines. Avoid outputting large files to stdout; consider writing to a file or limiting what you are outputting.";
		}
```

---

### 4. `libocbwrap/Bubble.vala` — `read_from_channel`: stop at 100 lines

**Why:** A single `IN` burst can deliver far more than 100 lines; the cap must be inside the read loop, not after it.

**Where:** `read_from_channel` — start of `while`, and after a successful `NORMAL` read before accumulate.

**Depends on:** §2.

##### Part 1 — already killed: stop

#### Add — first lines inside `while (true)`, before `read_line`
```vala
			if (this.output_killed) {
				return;
			}
```

##### Part 2 — cap before accumulate

#### Remove
```vala
			// Status is NORMAL - accumulate output
			if (is_stdout) {
				this.ret_str += buffer;
				continue; // Read more
			}
```

#### Replace with
```vala
			// Status is NORMAL - accumulate output
			if (this.output_lines >= 100) {
				this.output_killed = true;
				return;
			}
			this.output_lines++;
			if (is_stdout) {
				this.ret_str += buffer;
				continue; // Read more
			}
```

---

### 5. `liboctools/RunCommand/Request.vala` — bwrap path: drop post-hoc truncate; danger frame if killed

**Why:** After a live kill at 100, post-hoc `truncate_output(..., 100)` is the same cap applied too late. Drop it. A killed run is not a success frame.

**Where:** `execute_tool_async` — after `yield bubble.exec`, the `truncate_output` call and the UI message.

**Depends on:** §2, §3, §4.

#### Remove
```vala
				var output = yield bubble.exec(
					this.command,
					normalized_working_dir
				);
				
				// Truncate output if needed
				// FIXME - not sure this is a great idea - we will be bumping the context up soon
				// with ollama create tricks
				output = this.truncate_output(output, 100);
				if (output.strip() == "") {
					output = "No output received from command";
				}
				
				// Send output as second message via message_created
				this.agent.add_message(new OLLMchat.Message("ui",
					 OLLMchat.Message.fenced("text.oc-frame-success.collapsed Execution results", output)));
```

#### Replace with
```vala
				var output = yield bubble.exec(
					this.command,
					normalized_working_dir
				);
				if (output.strip() == "") {
					output = "No output received from command";
				}

				var frame_header = bubble.output_killed
					? "text.oc-frame-danger.collapsed Execution results (output too excessive)"
					: "text.oc-frame-success.collapsed Execution results";
				this.agent.add_message(new OLLMchat.Message("ui",
					 OLLMchat.Message.fenced(frame_header, output)));
```

---

### 6. `liboctools/RunCommand/Request.vala` — non-bwrap Unix: same live kill

**Why:** Flatpak / missing bwrap still uses `execute_with_subprocess`. Sequential stream reads must stop and kill at the existing **50**.

**Where:** class fields; `execute_with_subprocess` launcher + stream reads + result assembly; `read_stream_async`.

**Depends on:** none (parallel to Bubble).

##### Part 1 — fields (after `is_complex_command`)

#### Add — after `private bool is_complex_command = false;`
```vala
		private int output_lines = 0;
		private bool output_killed = false;
```

##### Part 2 — process group + pass subprocess into readers

`output_lines` / `output_killed` use field defaults. `Request` is deserialized once per tool call — do not re-zero at the start of `execute_with_subprocess`.

#### Remove
```vala
				var launcher = new GLib.SubprocessLauncher (flags);
				if (!this.run_as_root) {
					launcher.set_cwd (work_dir);
				}
				subprocess = launcher.spawnv (argv);
```

#### Replace with
```vala
				var launcher = new GLib.SubprocessLauncher (flags);
				if (!this.run_as_root) {
					launcher.set_cwd (work_dir);
				}
				launcher.set_child_setup(() => {
					Posix.setpgid(0, 0);
				});
				subprocess = launcher.spawnv (argv);
```

#### Remove
```vala
			stdout_output = yield this.read_stream_async (stdout_stream);
			stderr_output = yield this.read_stream_async (stderr_stream);
```

#### Replace with
```vala
			stdout_output = yield this.read_stream_async (stdout_stream, subprocess);
			stderr_output = yield this.read_stream_async (stderr_stream, subprocess);
```

##### Part 3 — Unix result: no post-hoc 50-line chop; killed notice

#### Remove
```vala
			// Truncate outputs if they exceed max lines (50)
			stdout_output = this.truncate_output(stdout_output, 50);
			//stderr_output = this.truncate_output(stderr_output, 50);
			
			// Escape code blocks in stdout output
 			
			// Build output message (txt code block)
			
			var	output_content  = stdout_output;
			 
			// Add stderr output (if any)
			if (stderr_output != "") {
				if (stdout_output != "") {
					output_content += "\n";
				}
				output_content += stderr_output;
			}
			 
			// Add exit code only if non-zero (success doesn't need to be shown)
			if (exit_status != 0) {
				if (stdout_output != "" || stderr_output != "") {
					output_content += "\n";
				}
				output_content += "Exit code: " + exit_status.to_string();
				if (!this.network) {
					output_content += " - Note: Networking is disabled by default. Pass \"network\": true in the "
						+ this.tool.name + " arguments to enable it.";
				}
				output_content += "\n";
			}
```

#### Replace with
```vala
			var	output_content  = stdout_output;
			if (stderr_output != "") {
				if (stdout_output != "") {
					output_content += "\n";
				}
				output_content += stderr_output;
			}
			if (this.output_killed) {
				output_content += "\nCommand killed: output exceeded 50 lines. Avoid outputting large files to stdout; consider writing to a file or limiting what you are outputting.";
			}
			if (!this.output_killed && exit_status != 0) {
				if (stdout_output != "" || stderr_output != "") {
					output_content += "\n";
				}
				output_content += "Exit code: " + exit_status.to_string();
				if (!this.network) {
					output_content += " - Note: Networking is disabled by default. Pass \"network\": true in the "
						+ this.tool.name + " arguments to enable it.";
				}
				output_content += "\n";
			}
```

##### Part 4 — UI frame when killed

#### Remove
```vala
			var frame_header = exit_status != 0
				? "text.oc-frame-danger.collapsed Execution results (Command Failed)"
				: "text.oc-frame-success.collapsed Execution results";
```

#### Replace with
```vala
			var frame_header = "text.oc-frame-success.collapsed Execution results";
			if (this.output_killed) {
				frame_header = "text.oc-frame-danger.collapsed Execution results (output too excessive)";
			}
			if (!this.output_killed && exit_status != 0) {
				frame_header = "text.oc-frame-danger.collapsed Execution results (Command Failed)";
			}
```

##### Part 5 — `read_stream_async`: count, kill, stop; try only around `read_line_async`

The existing method blankets the whole `while` in `try`. Wrap only `read_line_async` (`try-catch-scope`).

#### Remove
```vala
		private async string read_stream_async (InputStream? stream)
		{
			if (stream == null) {
				return "";
			}

			var data_input = new GLib.DataInputStream (stream);
			string output = "";

			try {
				while (true) {
					string? line = yield data_input.read_line_async (GLib.Priority.DEFAULT, null);

					if (line == null) {
						break;
					}

					if (output != "") {
						output += "\n";
					}
					output += line;
				}
			} catch (GLib.Error e) {
				return output;
			}

			return output;
		}
```

#### Replace with
```vala
		private async string read_stream_async (InputStream? stream, GLib.Subprocess subprocess)
		{
			if (stream == null) {
				return "";
			}

			var data_input = new GLib.DataInputStream (stream);
			var output = "";

			while (true) {
				if (this.output_killed) {
					break;
				}
				string? line = null;
				try {
					line = yield data_input.read_line_async (GLib.Priority.DEFAULT, null);
				} catch (GLib.Error e) {
					return output;
				}

				if (line == null) {
					break;
				}

				if (this.output_lines >= 50) {
					this.output_killed = true;
					GLib.debug("command killed: output exceeded 50 lines");
					var id = subprocess.get_identifier();
					if (id != null) {
						Posix.kill(-(int.parse(id)), Posix.Signal.KILL);
					}
					subprocess.force_exit();
					break;
				}
				this.output_lines++;

				if (output != "") {
					output += "\n";
				}
				output += line;
			}

			return output;
		}
```

##### Part 6 — Windows: keep existing post-hoc truncate at 50 (no live kill)

Part 3 removes the shared `truncate_output(..., 50)` after `#endif`. Windows still needs that chop. Put the **same** call in the Win32 block only — do not change 50.

**Where:** `#if G_OS_WIN32` block after `communicate_utf8_async` assigns `stdout_output` / `stderr_output`.

#### Add — after `stderr_output = stderr_buf ?? "";` in the Win32 block
```vala
			stdout_output = this.truncate_output(stdout_output, 50);
```

---

### 7. `liboctools/RunCommand/Tool.vala` — `description`: advise against unbounded listings

**Why:** The kill is a backstop. The model should not start `ls -RL ~` in the first place.

**Where:** `description` getter — the trailing `"""` block, immediately before `If the command fails`.

**Depends on:** none. `Bash` does not override `description`.

#### Remove
```vala
Root Access (Linux GTK app only):
- Set `run_as_root` to `true` when the command requires root (e.g. package install, system configuration).
- Do NOT prefix the command with `sudo`, `pkexec`, or `su` — the tool handles elevation when this flag is set.
- The user must approve in the app and enter their password in the permission prompt (not saved).
- Root runs execute outside the sandbox with full host access; `network` and `allow_write` do not restrict them.

If the command fails, you should handle the error gracefully and provide a helpful error message to the user.
```

#### Replace with
```vala
Root Access (Linux GTK app only):
- Set `run_as_root` to `true` when the command requires root (e.g. package install, system configuration).
- Do NOT prefix the command with `sudo`, `pkexec`, or `su` — the tool handles elevation when this flag is set.
- The user must approve in the app and enter their password in the permission prompt (not saved).
- Root runs execute outside the sandbox with full host access; `network` and `allow_write` do not restrict them.

Output:
- Keep listings and searches narrow. Do not recursively list large trees (for example `ls -R` / `ls -RL` on home, or `find` from `/` or `$HOME` without `-maxdepth` or a name filter).
- Prefer a specific directory, non-recursive `ls`, `find -maxdepth`, `git ls-files`, or pipe through `head` / `grep`.
- If output is too long, the command is killed and only the lines already captured are returned. Avoid outputting large files to stdout; write to a file or limit what you output.

If the command fails, you should handle the error gracefully and provide a helpful error message to the user.
```

---

## Next

✔️ Fences applied (sandbox kill at 100, fallback kill at 50, tool description, process group).

💩 ⏳ After apply: `seq 1 300` via sandboxed `run_command` should return 100 lines, the killed notice, and not wait for the rest of `seq`.
