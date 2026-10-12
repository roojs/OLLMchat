# 2.31.3 — Phase C — `bash` on the daemon wire

**Status:** ⏳ **proposed** — review before apply. Phase B is on the wire in [`TOOLS-2.31.2`](TOOLS-2.31.2-daemon-rpc-verbs.md).

> **Do not update** `docs/plans/TOOLS-1.0-summary.md` **for this sub-plan.**

**Parent:** [`TOOLS-2.31`](TOOLS-2.31-URGENT-bash-process-tool.md) — `bash` as a process tool, Phase C

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala follows `docs/coding-standards.md`.

---

## Purpose

- **🔷** `bash` is a new class. Copy `RunCommand` `Tool` and `Request` into it, then change the copy. It does not subclass `OLLMtools.RunCommand.Tool`.
- **🔷** `run_command` is deprecated. Desktop stops registering it. The copy does not stay compatible with it, and pieces of the copy can be deleted.
- **🔷** `bash` runs the command on `ollmfilesd` through `Sandbox-Bubble`, then manages it with `pid`.
- **🔷** One tool. `pid` set means `command` is `kill` / `tail` / `wait` / `send`. No second tool.
- **🔷** A negative timeout waits 15 seconds, then returns the pid and leaves the command running. Any other timeout still kills.
- **🔷** The pid return lists `send`, `wait`, `tail`, and `kill`. A dead job does not get that list.
- **🔷** Truncation tells the agent to `grep` / `head` / `tail` the spill file.
- **🔷** A job the daemon started is the only pid these verbs will touch. Another session's pid is refused.
- **ℹ️** Phase D is the Stop button that outlives the call. Do not treat `-1` as shipped until that lands.
- **ℹ️** Phase E is Android registration. Not this plan. The class there is `OLLMtools.Bash.Tool`.

---

## Decided

- **🔷** New files `liboctools/Bash/Tool.vala` and `liboctools/Bash/Request.vala`, namespace `OLLMtools.Bash`. `RunCommand/Bash.vala` goes away. It was only the alias subclass.
- **🔷** `Registry` registers `Bash.Tool` and does not register `RunCommand.Tool` or `RunCommand.Bash`. Config `init_config`, `register_config`, and `setup_config_defaults` name `Bash.Tool`.
- **🔷** `LIVE` and `SOCKET` both use the daemon calls. There is no in-process spawn on this class.
- **🔷** `grep.tool`, `glob.tool`, and `ls.tool` wrap `bash`. They wrap `run_command` today, and that name will not be registered.
- **🔷** `RunCommand/Tool.vala` and `RunCommand/Request.vala` stay until the new `bash` has been tested. They are not registered. Delete them after that testing, not before.
- **🔷** A chat can only `kill`, `tail`, `wait`, or `send` a process that same chat started. A pid from another chat is refused.
- **🔷** The tool passes the chat's session id to `ollmfilesd` when it starts the command. The daemon stores that id on the job. Later calls pass the same id, and the daemon refuses the call when it does not match. The tool does not keep its own list of which chat owns which pid.
- **🔷** A background command that prints nothing for 15 minutes is killed. Any new line of output starts that 15 minutes again. The clock runs on the desktop daemon, next to the process. The phone may be offline, so the phone cannot be the thing watching.
- **💩** A second, shorter clock: if the tool has already told the model "this command is waiting for you to type", and the model sends nothing for 60 seconds, the app kills it. A command that is still working does not get that one-minute kill.
- **🚫** Subclassing `RunCommand.Tool`, or a second code path inside `RunCommand.Request` gated on `tool.name == "bash"`.
- **🚫** Keeping `run_command` registered beside `bash`.
- **🚫** In-process `Bubble.exec`, `GLib.Subprocess`, or `run_as_root` on the new class. `run_as_root` set on a call is an error.
- **🚫** Editing `liboctools/RunCommand/` so that `bash` and `run_command` stay in step.
- **🚫** A client-side table of pid to session id. The daemon is the check.

---

## Wire the tool speaks

- **🔷** `ProjectManager.rpc.call`, same as `Codebase.search`. No new client.
- **ℹ️** `output` and `finished` are string signals. They arrive on `rpc.notification` with `method` `output` or `finished` and `id` the lease. `Client.live_handles` stays false.
- **🔷** Order for a new command: `can_wrap`, then `rpc_create`, then subscribe `output` and `finished`, then `rpc_run`.
- **🔷** `keep_stdin` is true only when `timeout < 0`.
- **🔷** After `rpc_run`, every later call uses the pid.
- **🔷** `wait` seconds are the tool timeout when that timeout is positive, and **15** when it is negative. A wait of **0** means **60** seconds.
- **🔷** When the command has finished, `wait`'s retval is that command's exit code. `0` means the command exited 0. It does not mean a special "ended" state.
- **🔷** A pid handed back to the model is negative, so it cannot be read as an exit code. The real process id is the positive number. The daemon is called with that positive id.
- **🔷** "Waiting for input" and "still working" are not the same answer, and neither is an exit code.
- **💩** Still working: retval is minus the pid (`-4321` for pid 4321). Waiting for input: retval is that same minus-pid, and the tool text says it is waiting. Those two live answers share one number, so the words are what separate them. Say if the number itself has to differ.
- **ℹ️** `ollmfilesd` `wait` today replies `0` ended, `1` waiting, `2` still running. `1` and `2` are real exit codes, so that reply has to change before this tool trusts it. The exit code is not kept once the pid leaves `Bubble.jobs`.

### Calls

- `Sandbox-Bubble.can_wrap` `""` — `msg` `1` / `0`
- `Sandbox-Bubble.rpc_create` `sssbSbx` — `project_path`, `command`, `working_dir`, `network`, `allow_write`, `keep_stdin`, `session_id` — `retval` lease (`t`)
- `RPC-Live-Subscribe.rpc_signal` lease + `output`, then the same for `finished`
- `Sandbox-Bubble.rpc_run` lease — `retval` pid (`i`), the positive process id
- `Sandbox-Bubble.wait` `iix` — pid, seconds, session id. `retval` the exit code when it has finished, or minus the pid when it has not. `msg` last lines. A `seconds` of `0` waits 60.
- `Sandbox-Bubble.kill` / `tail` `ix` — pid, session id
- `Sandbox-Bubble.send` `isx` — pid, text, session id

---

## Phase C code

Edits are **Remove** / **Replace with** / **Add** against the tree. Verify surrounding context before applying.

The `Request` hunks below apply to the copy, `liboctools/Bash/Request.vala`. Do not apply them to `liboctools/RunCommand/`.

### 1. `liboctools/Bash/` — new class, old tool deprecated

**Why:** `bash` owns its code. `run_command` is no longer registered, so nothing in this plan has to keep the old class working.

**Where:** copy, meson, registry, the three wrapped tools, and delete `RunCommand/Bash.vala`.

**Depends on:** none.

- **🔷** Copy `RunCommand/Tool.vala` to `Bash/Tool.vala` and `RunCommand/Request.vala` to `Bash/Request.vala`. Namespace on both copies is `OLLMtools.Bash`.
- **🔷** The copied tool's `name` is `bash`. `clone` returns `new Tool`.
- **🚫** Do not leave `RunCommand.Bash` in the build. Do not register `RunCommand.Tool`.

#### Remove — copied `Bash/Tool.vala`

```vala
namespace OLLMtools.RunCommand
```

#### Replace with

```vala
namespace OLLMtools.Bash
```

#### Remove

```vala
		public override string name { get { return "run_command"; } }
```

#### Replace with

```vala
		public override string name { get { return "bash"; } }
```

#### Remove

```vala
		public override string title { get { return "Run Shell Commands Tool"; } }
		public override string example_call {
			get { return "{\"name\": \"run_command\", \"arguments\": {\"command\": \"ls -la\"}}"; }
		}
```

#### Replace with

```vala
		public override string title { get { return "Bash"; } }
		public override string example_call {
			get { return "{\"name\": \"bash\", \"arguments\": {\"command\": \"ls -la\"}}"; }
		}
```

- **ℹ️** The same namespace replacement applies to the copied `Bash/Request.vala`. One line, `namespace OLLMtools.RunCommand` to `namespace OLLMtools.Bash`.

#### Remove — `liboctools/meson.build`

```vala
  'RunCommand/Bash.vala',
```

#### Add — beside the RunCommand sources

```vala
  'Bash/Tool.vala',
  'Bash/Request.vala',
```

- **🔷** Delete `liboctools/RunCommand/Bash.vala`.

#### Remove — `liboctools/Registry.vala` `init_config`, and the same swap in `register_config` and `setup_config_defaults`

```vala
			typeof(RunCommand.Tool).ensure();
```

#### Replace with

```vala
			typeof(Bash.Tool).ensure();
```

#### Remove

```vala
			OLLMchat.Tool.BaseTool.register_config(typeof(RunCommand.Tool));
```

#### Replace with

```vala
			OLLMchat.Tool.BaseTool.register_config(typeof(Bash.Tool));
```

#### Remove

```vala
			(new RunCommand.Tool(null)).setup_tool_config_default(config);
```

#### Replace with

```vala
			(new Bash.Tool(null)).setup_tool_config_default(config);
```

#### Remove — `fill_tools`

```vala
			manager.register_tool(new RunCommand.Tool(project_manager));
			manager.register_tool(new RunCommand.Bash(project_manager));
```

#### Replace with

```vala
			manager.register_tool(new Bash.Tool(project_manager));
```

#### Remove — `resources/wrapped-tools/grep.tool`, `glob.tool`, and `ls.tool`

```
@wrapped run_command
```

#### Replace with

```
@wrapped bash
```

### 2. Truncation wording

**Why:** The agent is told where the rest of the output is, and not to `cat` it. The cap stays 50.

**Where:** `bash_finished_text` in §5. The old footer sites are inside the local spawn §3 deletes.

**Depends on:** none.

- **🔷** Drop the leading `//`. Bold the count line. Name the file and the way to read it.
- **ℹ️** The count in the sentence is `output_lines`, not a new constant.
- **🚫** Do not patch the copied bwrap footer or the subprocess footer. Those methods are deleted.

```vala
"**Below are the last 50 of " + this.output_lines.to_string() + " lines.**\n"
+ "Full output: " + this.spill_path + "\n"
+ "Do not read this file whole — it is "
+ this.output_lines.to_string()
+ " lines. Use grep, head, or tail on it with this tool to find the part you need.\n"
```

### 3. `liboctools/Bash/Request.vala` — the copy talks to the daemon

**Why:** Management returns before permission and the spill file. A new command still walks the copied permission code. The sandbox question follows the daemon.

**Where:** the `pid` property beside `timeout`, the top of `execute`, `build_perm_question`, and the spawn branch inside `execute_tool_async`.

**Depends on:** [`TOOLS-2.31.2`](TOOLS-2.31.2-daemon-rpc-verbs.md). §1.

- **💩** This plan names `bash_remote` and `manage`.
- **🔷** `pid != 0` returns before `normalize_working_dir`, permission, `client.run_tool.start`, and the spill file.
- **🔷** No daemon, `can_wrap` not `1`, or `run_as_root` set: return an error. Do not spawn on the phone.
- **🔷** Delete the copied `GLib.Timeout.add_seconds` arm. The daemon `wait` is the clock.
- **💩** `remote_wrap` is set after `can_wrap` returns `1`. `build_perm_question` treats that as a sandbox, so the phone does not show "sandbox unavailable".

#### Add — beside `timeout`

```vala
		/**
		 * Bwrap pid from a previous ''bash'' call.
		 * ''0'' means this call is a new command.
		 */
		public int pid { get; set; default = 0; }

		/**
		 * True when this ''bash'' call will spawn on the daemon.
		 * Set before permission so the sandbox question matches the host that runs the command.
		 */
		private bool remote_wrap = false;
```

#### Remove

```vala
		public override async string execute()
		{
			// Parameters are already deserialized in constructor
			if (this.command.strip() == "") {
				return "ERROR: Invalid parameters";
			}
```

#### Replace with

```vala
		public override async string execute()
		{
			if (this.pid != 0) {
				return yield this.manage();
			}
			if (this.command.strip() == "") {
				return "ERROR: Invalid parameters";
			}
			if (this.run_as_root) {
				return "ERROR: run_as_root is not available";
			}
			var bash_tool = (Tool) this.tool;
			if (bash_tool.project_manager == null || !bash_tool.project_manager.rpc.connected) {
				return "ERROR: bash needs the file daemon";
			}
			var wrap = yield bash_tool.project_manager.rpc.call(new OLLMrpc.Request() {
				method = "Sandbox-Bubble.can_wrap"
			});
			if (wrap.msg != "1") {
				return "ERROR: sandbox unavailable";
			}
			this.remote_wrap = true;
```

#### Remove

```vala
			bool can = OLLMbwrap.Bubble.can_wrap ();
```

#### Replace with

```vala
			var can = this.remote_wrap || OLLMbwrap.Bubble.can_wrap();
```

#### Remove

```vala
			if (!OLLMbwrap.Bubble.can_wrap()) {
				return yield this.execute_with_subprocess();
			}
```

#### Replace with

```vala
			return yield this.bash_remote();
```

- **🔷** Also delete the copied `if (this.run_as_root) return yield this.execute_with_subprocess()` just above that branch.
- **🔷** `execute_with_subprocess` and the in-process `Bubble.exec` body below the return are unused. Delete them from the copy.

- **💩** In the `finally` of `execute`, a detached job must not close the spill, delete it, or emit `client.run_tool.end`. Those wait for `finished`. One-shot jobs keep the current `finally`.

#### Add — field beside `remote_wrap`

```vala
		/**
		 * True once a negative timeout has handed the pid back
		 * and the command is still running.
		 */
		private bool detached = false;
```

#### Remove

```vala
				if (this.spill_active) {
					try {
						this.spill_stream.close(null);
					} catch (GLib.Error e) {
					}
					this.spill_active = false;
```

#### Replace with

```vala
				if (this.spill_active && !this.detached) {
					try {
						this.spill_stream.close(null);
					} catch (GLib.Error e) {
					}
					this.spill_active = false;
```

#### Remove

```vala
				this.agent.notification(new OLLMrpc.Notification() {
					method = "client.run_tool.end",
					message = this.command.strip(),
				});
```

#### Replace with

```vala
				if (!this.detached) {
					this.agent.notification(new OLLMrpc.Notification() {
						method = "client.run_tool.end",
						message = this.command.strip(),
					});
				}
```

#### Remove

```vala
			this.timeout_src = GLib.Timeout.add_seconds(this.timeout, () => {
				this.timed_out = true;
				this.stop();
				this.timeout_src = 0;
				return false;
			});
```

- **ℹ️** The `finally` that clears `timeout_src` can stay. Nothing arms it.

### 4. `ollmfilesd` — store the session id and check it

**Why:** The daemon is the place that knows which chat started a process. A later call from another chat is refused there.

**Where:** `OLLMbwrap.Bubble` gains `session_id`. `ollmfilesd/Sandbox/Bubble.vala` `rpc_register`, `rpc_create`, and `kill` / `tail` / `wait` / `send`.

**Depends on:** [`TOOLS-2.31.2`](TOOLS-2.31.2-daemon-rpc-verbs.md).

- **🔷** `session_id` is the chat session's `id` (`int64`). The tool sends it on create, and again on `kill`, `tail`, `wait`, and `send`.
- **🔷** It is stored on the bubble. The job table stays keyed by the positive pid.
- **🔷** Unknown pid, or a pid stored for a different session: reply `command has ended`. Same sentence as a job that is already gone.

#### Add — field on `libocbwrap/Bubble.vala`, beside `pid`

```vala
		public int64 session_id { get; set; default = -1; }
```

#### Remove — `rpc_register`

```vala
				"rpc_create", "sssbSb",
				"rpc_run", "t",
				"kill", "i",
				"tail", "i",
				"wait", "ii",
				"send", "is"
```

#### Replace with

```vala
				"rpc_create", "sssbSbx",
				"rpc_run", "t",
				"kill", "ix",
				"tail", "ix",
				"wait", "iix",
				"send", "isx"
```

- **🔷** `rpc_create` takes `int64 session_id` after `keep_stdin` and sets `bubble.session_id` before the lease is returned.
- **🔷** `kill`, `tail`, `wait`, and `send` take `int64 session_id` after their current arguments. Look the pid up. If the bubble's `session_id` is not the one passed, reply `command has ended` and do nothing else.

### 5. `liboctools/Bash/Request.vala` — `bash_remote` and `manage`

**Why:** Create, subscribe, run, then either return the command result or the pid block. Later calls are the four verbs.

**Where:** new methods on `OLLMtools.Bash.Request`. The plan names both.

**Depends on:** §3 and §4.

- **🔷** Subscribe before `rpc_run`.
- **🔷** `send` writes the payload with no added newline. The verb is the first word. The rest is the payload, including a leading space that gets stripped once.
- **🔷** Unknown pid, or a pid from another session: the daemon replies `command has ended`. The tool returns that sentence. Nothing is signalled.
- **🔷** `wait` with no extra timeout argument waits 60 seconds. A duration rides on `timeout` when it is not 60.
- **🔷** Every `rpc_create`, `kill`, `tail`, `wait`, and `send` from this tool includes `this.agent.chat().agent.session.id`.
- **💩** The 60-second kill is not in this hunk: "waiting for input" and "still working" currently come back as the same negative pid, so there is nothing to test.
- **💩** `finished` text is the tool result when the command ends inside the wait. The truncation footer from §1 is applied when `output_lines > 50`.
- **💩** Streaming to the UI stays `client.run_tool.output` on the same `request_id`, fed from the `output` notification.

#### Add

```vala
		private static bool bash_listening = false;

		/**
		 * Spawn on the daemon and wait.
		 *
		 * Caller has already checked ''can_wrap'' and permission.
		 * A negative timeout uses 15 seconds and may detach.
		 *
		 * @return tool result, either the command output or the pid block
		 */
		private async string bash_remote()
		{
			var bash_tool = (Tool) this.tool;
			var project_path = "";
			if (bash_tool.project_manager.active_project != null) {
				project_path = bash_tool.project_manager.active_project.path;
			}
			var keep_stdin = this.timeout < 0;
			var seconds = keep_stdin ? 15 : this.timeout;
			var created = yield bash_tool.project_manager.rpc.call(new OLLMrpc.Request() {
				method = "Sandbox-Bubble.rpc_create",
				args = OLLMrpc.args(
					"sssbSbx",
					project_path,
					this.command,
					this.working_dir,
					this.network,
					this.write_array,
					keep_stdin,
					this.agent.chat().agent.session.id
				)
			});
			if (created.error != null) {
				return "ERROR: " + created.error.message;
			}
			var lease = created.retval.get_uint64();
			yield bash_tool.project_manager.rpc.call(new OLLMrpc.Request() {
				method = "RPC-Live-Subscribe.rpc_signal",
				lease_id = lease,
				args = OLLMrpc.args("s", "output")
			});
			yield bash_tool.project_manager.rpc.call(new OLLMrpc.Request() {
				method = "RPC-Live-Subscribe.rpc_signal",
				lease_id = lease,
				args = OLLMrpc.args("s", "finished")
			});
			this.arm_bash_listener(bash_tool, lease);
			var started = yield bash_tool.project_manager.rpc.call(new OLLMrpc.Request() {
				method = "Sandbox-Bubble.rpc_run",
				args = OLLMrpc.args("t", lease)
			});
			if (started.error != null) {
				return "ERROR: " + started.error.message;
			}
			var pid = (int) started.retval.get_int();
			var waited = yield bash_tool.project_manager.rpc.call(new OLLMrpc.Request() {
				method = "Sandbox-Bubble.wait",
				args = OLLMrpc.args(
					"iix",
					pid,
					seconds,
					this.agent.chat().agent.session.id
				)
			});
			var state = (int) waited.retval.get_int();
			if (state >= 0) {
				return this.bash_finished_text(waited.msg);
			}
			if (!keep_stdin) {
				yield bash_tool.project_manager.rpc.call(new OLLMrpc.Request() {
					method = "Sandbox-Bubble.kill",
					args = OLLMrpc.args(
						"ix",
						pid,
						this.agent.chat().agent.session.id
					)
				});
				this.timed_out = true;
				return this.bash_finished_text(waited.msg);
			}
			this.detached = true;
			return this.pid_block(-pid, false);
		}

		/**
		 * ''kill'' / ''tail'' / ''wait'' / ''send'' for a pid this session started.
		 *
		 * @return the verb result
		 */
		private async string manage()
		{
			if (this.pid >= 0) {
				return "command has ended";
			}
			var os_pid = -this.pid;
			var session_id = this.agent.chat().agent.session.id;
			var bash_tool = this.tool as Tool;
			if (bash_tool == null || bash_tool.project_manager == null
				|| !bash_tool.project_manager.rpc.connected) {
				return "command has ended";
			}
			var verb = this.command.strip();
			var payload = "";
			var space = verb.index_of(" ");
			if (space > 0) {
				payload = verb.substring(space + 1);
				verb = verb.substring(0, space);
			}
			if (verb == "kill") {
				yield bash_tool.project_manager.rpc.call(new OLLMrpc.Request() {
					method = "Sandbox-Bubble.kill",
					args = OLLMrpc.args("ix", os_pid, session_id)
				});
				return "command has ended";
			}
			if (verb == "tail") {
				var tail = yield bash_tool.project_manager.rpc.call(new OLLMrpc.Request() {
					method = "Sandbox-Bubble.tail",
					args = OLLMrpc.args("ix", os_pid, session_id)
				});
				return tail.msg + "\n" + this.pid_block(this.pid, false);
			}
			if (verb == "wait") {
				var seconds = this.timeout == 60 ? 60 : this.timeout;
				if (seconds < 1) {
					seconds = 60;
				}
				var waited = yield bash_tool.project_manager.rpc.call(new OLLMrpc.Request() {
					method = "Sandbox-Bubble.wait",
					args = OLLMrpc.args("iix", os_pid, seconds, session_id)
				});
				if ((int) waited.retval.get_int() >= 0) {
					return this.bash_finished_text(waited.msg);
				}
				return waited.msg + "\n" + this.pid_block(this.pid, false);
			}
			if (verb == "send") {
				var sent = yield bash_tool.project_manager.rpc.call(new OLLMrpc.Request() {
					method = "Sandbox-Bubble.send",
					args = OLLMrpc.args("isx", os_pid, payload, session_id)
				});
				if (sent.msg != "ok") {
					return "command has ended";
				}
				return "ok";
			}
			return "ERROR: Unknown command for pid " + this.pid.to_string();
		}

		/**
		 * Pid return the agent reads. Waiting-for-input includes the 60 second reap line.
		 *
		 * @param pid bwrap pid
		 * @param waiting true when the job is blocked on stdin
		 * @return the block
		 */
		private string pid_block(int pid, bool waiting)
		{
			var head = waiting ? "Waiting for input. pid " : "Still running. pid ";
			var text = head + pid.to_string() + ".\n\n"
				+ "Call this tool again with pid=" + pid.to_string() + " and command set to one of:\n"
				+ "  send <text>  write to its stdin\n"
				+ "  wait         wait 60 more seconds for it\n"
				+ "  tail         show the last 50 lines of its output\n"
				+ "  kill         stop it\n";
			if (waiting) {
				text += "Left alone, it is killed in about 60 seconds.\n";
			}
			return text;
		}
```

- **💩** `arm_bash_listener`, `bash_finished_text`, and `reap_stuck` are the three leftovers. `arm_bash_listener` connects `rpc.notification` once and appends `output` lines to the spill and to `client.run_tool.output` while the lease matches. `bash_finished_text` applies the §2 wording when the line count is over 50. `reap_stuck` calls `Sandbox-Bubble.kill` with the session id. Same three names, no further helpers.
- **💩** `tail` on a live job appends `pid_block`. `tail` on a missing pid returns only `command has ended`, from the session check above, so the block is not repeated for a dead job.
- **💩** `send` that gets `ok` and then no new output does not guess a threshold. The next `wait` is what reports stdin. A one-line note on the `ok` return — "end the text with a newline if the command is waiting for a line" — is optional and not in the block above.

### 6. `liboctools/Bash/Tool.vala` — `pid` and `-1` in the description

**Why:** The model reads `parameter_description` on this class. There is no base tool to append to.

**Where:** the copied `parameter_description`, the `timeout` line.

**Depends on:** §1.

- **🔷** `-1` is the advertised detach value. The code tests `timeout < 0`.
- **🔷** Add the `pid` line. Replace the copied timeout line. It still describes a hard kill and nothing else.

#### Remove

```vala
@param timeout {integer} [optional] Wall-clock seconds before the command is killed. Defaults to 60s. Increase for long jobs.
```

#### Replace with

```vala
@param pid {integer} [optional] Bwrap pid from an earlier call. When set, command is kill, tail, wait, or send <text>.
@param timeout {integer} [optional] Wall-clock seconds before the command is killed. Defaults to 60s. -1 waits 15 seconds, then returns the pid and leaves the command running.
```

- **ℹ️** Phase D still gates shipping `-1` to Android.

### 7. `libocbwrap/Bubble.vala` — silence kill

**Why:** Output is what resets the clock, and the daemon is where the output is read. Fifteen minutes is the short end of the 15–20 minute rule.

**Where:** arm when the pid is stored, remove when the pid leaves `jobs`, reset from `read_from_channel`.

**Depends on:** [`TOOLS-2.31.1`](TOOLS-2.31.1-daemon-job-model.md).

- **💩** 900 seconds, literal, no new constant.
- **💩** The Windows stub arms nothing. `can_wrap` is false there, so no job is stored.
- **🚫** Not a timer inside the `exec` wait. `wait` and the client reap stay above this.

#### Add — field beside `pid`

```vala
		private uint idle_src = 0;
```

#### Remove

```vala
				Bubble.jobs.set(this.pid, this);
```

#### Replace with

```vala
				Bubble.jobs.set(this.pid, this);
				this.arm_idle();
```

#### Remove

```vala
			if (Bubble.jobs != null) {
				Bubble.jobs.unset(this.pid);
			}
```

#### Replace with

```vala
			if (this.idle_src != 0) {
				GLib.Source.remove(this.idle_src);
				this.idle_src = 0;
			}
			if (Bubble.jobs != null) {
				Bubble.jobs.unset(this.pid);
			}
```

#### Add — called from `read_from_channel` after `this.output(line)`, and from the `jobs.set` site via `arm_idle`

```vala
		private void arm_idle()
		{
			if (this.idle_src != 0) {
				GLib.Source.remove(this.idle_src);
			}
			this.idle_src = GLib.Timeout.add_seconds(900, () => {
				this.idle_src = 0;
				this.stop();
				return false;
			});
		}
```

- **ℹ️** `arm_idle` is named here because both the spawn site and every output line call it.

---

## Testing Phase C

- **🔷** `⏳` One-shot over the socket: `bash` with `timeout` 30 runs `echo hi`, the result has the output, and `Bubble.jobs` does not keep the pid.
- **💩** `⏳` `timeout` `-1` on `cat`: the result is the pid block, `wait` returns waiting, `send` of `hi\n` produces output, `kill` ends it.
- **💩** `⏳` A pid from another session, and a pid that was never returned, both come back `command has ended`.
- **🔷** `⏳` Truncation over 50 lines includes the bold count, the spill path, and the grep / head / tail line.
- **🔷** `⏳` `run_command` is not in the tool list. `grep`, `glob`, and `ls` still run, through `bash`.
- **💩** `⏳` A job with no output for 15 minutes is killed on the daemon. Output during that window resets the clock.
- **💩** `⏳` `run_as_root` set, and a call with the file daemon disconnected, both return an error and do not spawn locally.

---

## LLM notes

- **🚫** Subclassing `RunCommand.Tool`, or patching `RunCommand.Request` so `bash` and `run_command` share a path.
- **🚫** Registering `run_command` beside `bash`.
- **🚫** In-process `Bubble.exec` or `GLib.Subprocess` on `OLLMtools.Bash`.
- **🚫** A second management tool.
- **🚫** Registering `bash` on Android in this plan. Phase E.
- **🚫** The Phase D Stop button, stuffed in here so `-1` can ship early.
- **🚫** Applying [`TOOLS-2.31.6`](TOOLS-2.31.6-PARKED-daemon-sandbox-bubble-rpc.md).
- **🚫** `run_as_root` on `Sandbox-Bubble`, and a local root path kept on the copy so that flag still works.
- **🚫** `Client.live_handles = true` on the file client. String signals do not need a proxy.
- **🚫** Helper methods beyond `bash_remote`, `manage`, `pid_block`, `arm_bash_listener`, `bash_finished_text`, `reap_stuck`, and `arm_idle`.
- **🚫** Rewriting skills and docs that still say `run_command`. Trash those when the old tool is deleted.
