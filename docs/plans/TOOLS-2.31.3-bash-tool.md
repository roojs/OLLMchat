# 2.31.3 — Phase C — `bash` on the daemon wire

**Status:** ⏳ **proposed** — review before apply. Phase B is on the wire in [`TOOLS-2.31.2`](TOOLS-2.31.2-daemon-rpc-verbs.md).

> **Do not update** `docs/plans/TOOLS-1.0-summary.md` **for this sub-plan.**

**Parent:** [`TOOLS-2.31`](TOOLS-2.31-URGENT-bash-process-tool.md) — `bash` as a process tool, Phase C

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala follows `docs/coding-standards.md`.

---

## Purpose

- **🔷** `bash` runs the command on `ollmfilesd` through `Sandbox-Bubble`, then manages it with `pid`.
- **🔷** `run_command` stays the local tool. No `pid`, no verbs, no `timeout < 0`.
- **🔷** One tool. `pid` set means `command` is `kill` / `tail` / `wait` / `send`. No second tool.
- **🔷** A negative timeout waits 15 seconds, then returns the pid and leaves the command running. Any other timeout still kills.
- **🔷** The pid return lists `send`, `wait`, `tail`, and `kill`. A dead job does not get that list.
- **🔷** Truncation tells the agent to `grep` / `head` / `tail` the spill file.
- **🔷** A job the daemon started is the only pid these verbs will touch. Another session's pid is refused.
- **ℹ️** Phase D is the Stop button that outlives the call. Do not treat `-1` as shipped until that lands.
- **ℹ️** Phase E is Android registration. Not this plan.

---

## Decisions to confirm

The parent left these open. Each recommendation is **💩** until you promote it.

- **💩** `bash` keeps subclassing `OLLMtools.RunCommand.Tool`. It does not get a second `Request` type. `Request.execute` already holds permission, the spill file, and `stop`. A new request would copy that.
- **💩** The RPC path runs only when `this.tool.name == "bash"`. `run_command` never enters it, even if a caller stuffed `pid` into its JSON.
- **💩** `LIVE` and `SOCKET` use the same calls. Both already have `project_manager.rpc` connected to `ollmfilesd`. In-process `Bubble.exec` remains the path when that client is not connected, when `can_wrap` is `0`, and when `run_as_root` is set.
- **💩** Desktop keeps both tools registered. This plan does not edit `Registry.fill_tools`.
- **💩** The per-session list is a static map on `Request`, each row remembering the session id. `libollmchat` does not gain a bash type. `manage` refuses a pid whose session id is not the caller's.
- **💩** The 15-minute silence kill lives on the daemon bubble, reset by output lines. A phone in a lift cannot run that timer. The 60-second "model was told and did nothing" kill stays on the client, and only after a **waiting for input** return.

---

## Wire the tool speaks

- **🔷** `ProjectManager.rpc.call`, same as `Codebase.search`. No new client.
- **ℹ️** `output` and `finished` are string signals. They arrive on `rpc.notification` with `method` `output` or `finished` and `id` the lease. `Client.live_handles` stays false.
- **🔷** Order for a new command: `can_wrap`, then `rpc_create`, then subscribe `output` and `finished`, then `rpc_run`.
- **🔷** `keep_stdin` is true only when `timeout < 0`.
- **🔷** After `rpc_run`, every later call uses the pid.
- **💩** `wait` seconds are the tool timeout for a positive timeout, and **15** for a negative one. Never send `0` — the daemon treats that as 60.
- **💩** `wait` retval `0` is the finished command. Retval `1` or `2` with a negative timeout is the pid return. Retval `2` with a positive timeout is killed, then the result is whatever `finished` already delivered.

### Calls

- `Sandbox-Bubble.can_wrap` `""` — `msg` `1` / `0`
- `Sandbox-Bubble.rpc_create` `sssbSb` — `project_path`, `command`, `working_dir`, `network`, `allow_write`, `keep_stdin` — `retval` lease (`t`)
- `RPC-Live-Subscribe.rpc_signal` lease + `output`, then the same for `finished`
- `Sandbox-Bubble.rpc_run` lease — `retval` pid (`i`)
- `Sandbox-Bubble.wait` pid, seconds — `retval` `0` / `1` / `2`, `msg` last lines
- `Sandbox-Bubble.kill` / `tail` / `send` as in Phase B

---

## Phase C code

Edits are **Remove** / **Replace with** / **Add** against the tree. Verify surrounding context before applying.

### 1. `liboctools/RunCommand/Request.vala` — truncation advice

**Why:** The agent is told where the rest of the output is, and not to `cat` it. The cap stays 50.

**Where:** the bwrap footer, the subprocess footer, and the subprocess return line.

**Depends on:** none.

- **🔷** Drop the leading `//`. Bold the count line. Name the file and the way to read it.
- **ℹ️** The count in the sentence is `output_lines`, not a new constant.

#### Remove

```vala
				if (this.output_lines > 50) {
					footer += "// LLM received last 50 of " + this.output_lines.to_string() + " lines.\n";
					if (this.spill_path != "") {
						footer += "Full output: " + this.spill_path + "\n";
					}
				}
```

#### Replace with

```vala
				if (this.output_lines > 50) {
					footer += "**Below are the last 50 of " + this.output_lines.to_string() + " lines.**\n";
					if (this.spill_path != "") {
						footer += "Full output: " + this.spill_path + "\n";
						footer += "Do not read this file whole — it is "
							+ this.output_lines.to_string()
							+ " lines. Use grep, head, or tail on it with this tool to find the part you need.\n";
					}
				}
```

- **ℹ️** That block appears twice (bwrap footer near the `Exit code:` slice, subprocess footer under `#if !G_OS_WIN32`). Both get the same replacement.

#### Remove

```vala
			return "// ... (output truncated: showing last 50 of " + this.output_lines.to_string() + " lines) ...\n" + output;
```

#### Replace with

```vala
			return "**Below are the last 50 of " + this.output_lines.to_string() + " lines.**\n" + output;
```

### 2. `liboctools/RunCommand/Request.vala` — `bash` enters the daemon

**Why:** Management must return before permission and the spill file. A new `bash` command still walks the existing permission code, but the sandbox question has to follow the daemon, not the phone.

**Where:** the `pid` property beside `timeout`, the top of `execute`, `build_perm_question`, and the spawn branch inside `execute_tool_async`.

**Depends on:** [`TOOLS-2.31.2`](TOOLS-2.31.2-daemon-rpc-verbs.md).

- **💩** This plan names `bash_remote` and `manage`. They are the two paths `execute` cannot inline without copying the permission body.
- **💩** `remote_wrap` is set only after `can_wrap` returns `1` on a connected client, and only for `bash`. `build_perm_question` treats that as a sandbox, so the phone does not show "sandbox unavailable".
- **🔷** `pid != 0` returns before `normalize_working_dir`, permission, `client.run_tool.start`, and the spill file.
- **💩** `timeout < 0` on a local fallback (no daemon, or `can_wrap` is `0`) is still a kill at 15 seconds. Detach exists only on the daemon path. `GLib.Timeout.add_seconds` must not see a negative value.

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
			if (this.tool.name == "bash" && this.pid != 0) {
				return yield this.manage();
			}
			if (this.command.strip() == "") {
				return "ERROR: Invalid parameters";
			}
			if (this.tool.name == "bash" && !this.run_as_root) {
				var bash_tool = this.tool as Tool;
				if (bash_tool != null && bash_tool.project_manager != null
					&& bash_tool.project_manager.rpc.connected) {
					var wrap = yield bash_tool.project_manager.rpc.call(new OLLMrpc.Request() {
						method = "Sandbox-Bubble.can_wrap"
					});
					this.remote_wrap = wrap.msg == "1";
				}
			}
			if (this.tool.name == "bash" && this.timeout < 0 && !this.remote_wrap) {
				this.timeout = 15;
			}
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
			if (this.remote_wrap) {
				return yield this.bash_remote();
			}
			if (!OLLMbwrap.Bubble.can_wrap()) {
				return yield this.execute_with_subprocess();
			}
```

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

- **💩** The local `Timeout.add_seconds(this.timeout, …)` must be skipped when `this.remote_wrap` is set. The daemon `wait` is the clock. Arming both would kill a command the daemon is still streaming.

#### Remove

```vala
			this.timeout_src = GLib.Timeout.add_seconds(this.timeout, () => {
				this.timed_out = true;
				this.stop();
				this.timeout_src = 0;
				return false;
			});
```

#### Replace with

```vala
			if (!this.remote_wrap) {
				this.timeout_src = GLib.Timeout.add_seconds((uint) this.timeout, () => {
					this.timed_out = true;
					this.stop();
					this.timeout_src = 0;
					return false;
				});
			}
```

### 3. `liboctools/RunCommand/Request.vala` — `bash_remote` and `manage`

**Why:** Create, subscribe, run, then either return the command result or the pid block. Later calls are the four verbs.

**Where:** new methods on `Request`. The plan names both.

**Depends on:** §2.

- **🔷** Subscribe before `rpc_run`.
- **🔷** `send` writes the payload with no added newline. The verb is the first word. The rest is the payload, including a leading space that gets stripped once.
- **🔷** Unknown pid, or a pid from another session: the result is `command has ended`. Nothing is signalled.
- **🔷** `wait` with no extra timeout argument waits 60 seconds. A duration rides on `timeout` when it is not 60.
- **💩** `bash_jobs` is the session list. The value is the session id. A `0` source id on the side map is "no 60-second reap". The reap is armed only for a waiting-for-input return.
- **💩** `finished` text is the tool result when the command ends inside the wait. The truncation footer from §1 is applied when `output_lines > 50`.
- **💩** Streaming to the UI stays `client.run_tool.output` on the same `request_id`, fed from the `output` notification.

#### Add

```vala
		private static Gee.HashMap<int, int64> bash_jobs;
		private static Gee.HashMap<int, uint> bash_reap;
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
					"sssbSb",
					project_path,
					this.command,
					this.working_dir,
					this.network,
					this.write_array,
					keep_stdin
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
				args = OLLMrpc.args("ii", pid, seconds)
			});
			var state = (int) waited.retval.get_int();
			if (state == 0) {
				return this.bash_finished_text(waited.msg);
			}
			if (!keep_stdin) {
				yield bash_tool.project_manager.rpc.call(new OLLMrpc.Request() {
					method = "Sandbox-Bubble.kill",
					args = OLLMrpc.args("i", pid)
				});
				this.timed_out = true;
				return this.bash_finished_text(waited.msg);
			}
			if (Request.bash_jobs == null) {
				Request.bash_jobs = new Gee.HashMap<int, int64>();
				Request.bash_reap = new Gee.HashMap<int, uint>();
			}
			Request.bash_jobs.set(pid, this.agent.chat().agent.session.id);
			this.detached = true;
			if (state == 1) {
				var src = GLib.Timeout.add_seconds(60, () => {
					this.reap_stuck(pid);
					return false;
				});
				Request.bash_reap.set(pid, src);
			}
			return this.pid_block(pid, state == 1);
		}

		/**
		 * ''kill'' / ''tail'' / ''wait'' / ''send'' for a pid this session started.
		 *
		 * @return the verb result
		 */
		private async string manage()
		{
			if (Request.bash_jobs == null || !Request.bash_jobs.has_key(this.pid)
				|| Request.bash_jobs.get(this.pid) != this.agent.chat().agent.session.id) {
				return "command has ended";
			}
			if (Request.bash_reap != null && Request.bash_reap.has_key(this.pid)) {
				GLib.Source.remove(Request.bash_reap.get(this.pid));
				Request.bash_reap.unset(this.pid);
			}
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
					args = OLLMrpc.args("i", this.pid)
				});
				Request.bash_jobs.unset(this.pid);
				return "command has ended";
			}
			if (verb == "tail") {
				var tail = yield bash_tool.project_manager.rpc.call(new OLLMrpc.Request() {
					method = "Sandbox-Bubble.tail",
					args = OLLMrpc.args("i", this.pid)
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
					args = OLLMrpc.args("ii", this.pid, seconds)
				});
				if ((int) waited.retval.get_int() == 0) {
					Request.bash_jobs.unset(this.pid);
					return this.bash_finished_text(waited.msg);
				}
				if ((int) waited.retval.get_int() == 1) {
					var src = GLib.Timeout.add_seconds(60, () => {
						this.reap_stuck(this.pid);
						return false;
					});
					Request.bash_reap.set(this.pid, src);
				}
				return waited.msg + "\n" + this.pid_block(this.pid, (int) waited.retval.get_int() == 1);
			}
			if (verb == "send") {
				var sent = yield bash_tool.project_manager.rpc.call(new OLLMrpc.Request() {
					method = "Sandbox-Bubble.send",
					args = OLLMrpc.args("is", this.pid, payload)
				});
				if (sent.msg != "ok") {
					Request.bash_jobs.unset(this.pid);
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

- **💩** `arm_bash_listener`, `bash_finished_text`, and `reap_stuck` are the three leftovers. `arm_bash_listener` connects `rpc.notification` once and appends `output` lines to the spill and to `client.run_tool.output` while the lease matches. `bash_finished_text` applies the §1 footer when the line count is over 50. `reap_stuck` calls `Sandbox-Bubble.kill` and drops the pid from `bash_jobs`. Same three names, no further helpers.
- **💩** `tail` on a live job appends `pid_block`. `tail` on a missing pid returns only `command has ended`, from the session check above, so the block is not repeated for a dead job.
- **💩** `send` that gets `ok` and then no new output does not guess a threshold. The next `wait` is what reports stdin. A one-line note on the `ok` return — "end the text with a newline if the command is waiting for a line" — is optional and not in the block above.

### 4. `liboctools/RunCommand/Bash.vala` — tell the model about `pid`

**Why:** `parameter_description` is what the model sees. `run_command` must not gain the `pid` line.

**Where:** override on `Bash`.

**Depends on:** §2.

- **🔷** `-1` is the advertised detach value. The code tests `timeout < 0`.
- **🚫** Do not add this text to `RunCommand.Tool.parameter_description`.

#### Add

```vala
		public override string parameter_description {
			get {
				return base.parameter_description
					+ "\n@param pid {integer} [optional] Bwrap pid from an earlier call. When set, command is kill, tail, wait, or send <text>.\n"
					+ "@param timeout {integer} [optional] Wall-clock seconds before the command is killed. -1 waits 15 seconds, then returns the pid and leaves the command running.\n";
			}
		}
```

- **ℹ️** `base.parameter_description` already documents `timeout` as a hard kill. The extra line is the `-1` meaning. Phase D still gates shipping this to Android.

### 5. `libocbwrap/Bubble.vala` — silence kill

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
- **💩** `⏳` `run_command` with `pid` set still runs the command string. It does not kill anything.
- **💩** `⏳` A job with no output for 15 minutes is killed on the daemon. Output during that window resets the clock.

---

## LLM notes

- **🚫** `pid`, verbs, or `-1` on `run_command`.
- **🚫** A second management tool.
- **🚫** Registering `bash` on Android in this plan. Phase E.
- **🚫** The Phase D Stop button, stuffed in here so `-1` can ship early.
- **🚫** Applying [`TOOLS-2.31.6`](TOOLS-2.31.6-PARKED-daemon-sandbox-bubble-rpc.md).
- **🚫** `run_as_root` on `Sandbox-Bubble`. That call stays on the local path.
- **🚫** `Client.live_handles = true` on the file client. String signals do not need a proxy.
- **🚫** Helper methods beyond `bash_remote`, `manage`, `pid_block`, `arm_bash_listener`, `bash_finished_text`, `reap_stuck`, and `arm_idle`.
