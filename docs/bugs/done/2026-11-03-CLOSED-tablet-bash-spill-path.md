# Tablet bash tells the model to read a file bash cannot open

**Status:** 🚫 CLOSED 2026-11-05. Server spill path is in the tree (§1–§5 applied 2026-11-04). The `bash-spill` directory, the date folders, and boot cleanup are a separate bug: [`2026-11-05-CLOSED-bash-tools-spill.md`](2026-11-05-CLOSED-bash-tools-spill.md).

Agent Pi on the tablet ran a long string of `bash` calls. Every one exited 0. When the output was longer than 50 lines, the tool returned the tail and told the model to `grep`, `head`, or `tail` a log file. That log is on the tablet. Bash runs on the desktop, so the follow-up cannot work. The model then treated the tail as the file.

## Problem

- 🔷 A long command still returns the last 50 lines. That cap stays.
- 🔷 The follow-up path in the tool result must be a path the next `bash` call can open.
- 🔷 The full-output spill file and its path stay in the result.
- 🔷 The spill file must live on the server, where the command runs. The app
  must fetch server file content through the file daemon, not read a local
  tablet copy.
- 🔷 On the tablet the result names `/storage/emulated/0/Android/data/.../run_command-N.log` and says to open it with this tool.
- 🔷 `head`, `sed -n '1,Np'`, and `cat` whose stdout exceeds 50 lines come back as the tail. The model read that tail as the start of the file.

## Evidence

- ℹ️ Tablet emulator `emulator-5556`, package `org.roojs.ollmchat.androidpoc`, pid 20434. Session `history/2026/11/03/01-44-12` (09:44–09:50). Agent Pi, `ornith-1.5:35b`, project `/home/alan/gitlive/OLLMchat`.
- ℹ️ User text: merge `FileConnectionAdd` into `examples/oc-test-source-diff.vala`.
- ✔️ Spill logs still on the device, mode `600`, under that session directory: `run_command-3.log`, `4`, `5`, `6`, `15`, `20`.
- ✔️ Commands and what the model was given. All of these ended `Exit code: 0`.
  - `cat` `examples/oc-test-source-diff.vala` — last 50 of 1242 lines (the end of the file).
  - `wc -l` then `head -60` on that file — last 50 of 62 lines. The line count and the start of `head` were dropped. The text opened in the license.
  - `cat -A … | head -5` then a full `cat` of `FileConnectionAdd.vala` — last 50 of 257 lines. The `head -5` never appeared.
  - `cat` of that file — last 50 of 251 lines.
  - `sed -n '1,120p'` of that file — last 50 of 120 lines, so lines 71–120.
  - `head -25` of that file — full output. It stayed under the cap.
- ✔️ The model's own notes after those tails: the file was a fragment, it started partway through, and `can_close` was used without being declared. The declaration is above the window it was shown.
- ✔️ It then called `read` on the same paths. `read` returned the file, including the top.
- ℹ️ A 20th `bash` (a diff, result 2042 characters, spill kept) finished at 09:50:03. The next completion started. At 09:50:04 the session logged `Stopping running` (`cancel_current_request`). That diff is not in the session json. The save at 09:50:03 flushed the previous turn. That stop is separate from the spill path.
- ℹ️ Desktop spill paths are on the host. The sandbox is started with `--ro-bind / /` (`libocbwrap/Bubble.vala`), so a desktop `bash` can open `~/.local/share/ollmchat/history/.../run_command-N.log`. The same sentence is true there.

## Root cause

- ✔️ `ollmapp/android/tools/Bash/Request.vala` `bash_finished_text` appends the footer when `output_lines > 50`. The path is `this.spill_path`, built from `session.task_dir()` on the tablet.
- ✔️ The command itself runs on the desktop daemon (`Sandbox-Bubble.rpc_create` / `rpc_run` / `wait`). `ollmfilesd/Sandbox/Bubble.vala` `wait_run` replies with `string.joinv` of `tail` (the rolling last 50 lines) plus `Exit code:`. The daemon does not keep the earlier lines (`libocbwrap/Bubble.vala` `read_from_channel` drops past 50).
- ✔️ The only full copy is the spill file the tablet writes while `output` notifications arrive. The footer tells the model to open that copy with `bash`.
- ✔️ The existing thin-client file path already fetches content from the
  daemon: `libocfiles/File.vala` `read()` calls `File.read`, and
  `ollmfilesd/File.vala` reads the path on the server.
- 🚫 Raising the 50-line cap. The cap is the finished design in `docs/plans/done/TOOLS-2.6.5-DONE-run-command-timeout-live-spill.md` and `docs/plans/done/TOOLS-2.31.3-DONE-bash-tool.md`.
- 🚫 Applying an Android-only result-formatting fix. Server-owned spill
  output is shared infrastructure, so both Bash clients must use the daemon
  contract consistently.
- 🚫 Removing the spill path or replacing recovery with first-and-last output.
- 🚫 Making the app dereference the spill path with `GLib.File`; on a thin
  client that resolves against the tablet filesystem.

## Proposed fix

- 🔷 The daemon writes every output line to a spill file on the host that runs the command, and still keeps only the rolling 50-line tail in memory.
- 🔷 `Sandbox-Bubble.wait` returns that server path with the finished result. The tool result keeps the existing `Full output:` footer and the grep / head / tail line.
- 🔷 A follow-up `bash` runs on the daemon and opens that path. `read` loads it with the existing `File.read` RPC. Both Bash clients use that daemon path.
- 💩 Spill directory on the daemon host: `{user_data_dir}/ollmchat/bash-spill/`. File name: `run_command-{session_id}-{realtime}.log`, mode `600`. This is the same data root `ollmfilesd` uses when `--data-dir` is unset. A later bash sees it through `--ro-bind / /`. The sandbox puts a tmpfs on `/tmp` and on `XDG_RUNTIME_DIR`, so a file there would be hidden. The project tree is a scan root, so the log stays in the user data dir.
- 💩 Open the file in `run()` before `exec`. Append on the `output` signal. On `finished`, close it. When `output_lines` is 50 or fewer, delete the file and clear the path. When it is more than 50, keep the file. Leave the `bash-spill` directory in place.
- 💩 Every successful `wait` reply sets `args[0]` to that path (empty unless more than 50 lines) and `args[1]` to the daemon line count. `msg` stays the tail text, plus `Exit code:` when the job has ended. Both Bash clients build the footer from those two args and stop writing their own log.
- 🚫 Writing the spill inside `libocbwrap/Bubble.vala` `read_from_channel`. `RunCommand` and MCP also call `exec`. Only `ollmfilesd/Sandbox/Bubble.vala` `run()` opens this file.
- 🚫 Deleting `bash-spill` or the user data directory when a short run ends.
- 🚫 A first-50 / last-50 footer, a higher line cap, or an Android-only path rewrite.
- 🚫 A change to `File.read`. An unindexed spill comes back with `msg_encode` 1, and `libocfiles/File.vala` `read()` already base64-decodes that.
- ℹ️ A timeout `kill` returns before `finished` closes the file. The path in that wait reply is the path `finished` keeps when the line count is already over 50. The model's next tool call is after this result, so the close has run.

Edits below are **Remove** / **Replace with** / **Add** from the tree. `ollmapp/android/tools/Bash/Request.vala` and `liboctools/Bash/Request.vala` are the same text; apply each client hunk to both.

### 1. `libocbwrap/Bubble.vala` — spill fields on the job

**Why:** `wait` reads the path after `exec` has moved the job to `ended`. The path has to live on the bubble, next to `tail` and `output_lines`.

**Where:** instance fields, immediately after the `tail` property and before `private GLib.Subprocess child`.

**Depends on:** none.

#### Remove

```vala
		public string[] tail { get; private set; default = {}; }
		private GLib.Subprocess child;
```

#### Replace with

```vala
		public string[] tail { get; private set; default = {}; }

		/**
		 * Absolute server path of this run's spill file.
		 *
		 * Empty until the daemon opens the file. Empty again when
		 * the run wrote 50 lines or fewer and the file was removed.
		 * A later bash or read uses this path on the daemon host.
		 */
		public string spill_path = "";

		/**
		 * Open spill stream. The daemon appends one line each time
		 * {@link output} fires, while {@link spill_open} is true.
		 */
		public GLib.FileOutputStream spill_stream;

		/**
		 * True after the spill file is opened, false after it is
		 * closed.
		 */
		public bool spill_open = false;

		private GLib.Subprocess child;
```

### 2. `libocbwrap/windows/Bubble.vala` — the same three fields

**Why:** `ollmfilesd/Sandbox/Bubble.vala` assigns these fields. The Windows bubble stub has to compile the same assignments.

**Where:** instance fields, immediately after the `tail` property and before `public Bubble`.

**Depends on:** none.

#### Remove

```vala
		public string[] tail { get; private set; default = {}; }

		public Bubble (FileVerification verification)
```

#### Replace with

```vala
		public string[] tail { get; private set; default = {}; }

		/**
		 * Absolute server path of this run's spill file.
		 *
		 * Empty until the daemon opens the file. Empty again when
		 * the run wrote 50 lines or fewer and the file was removed.
		 * A later bash or read uses this path on the daemon host.
		 */
		public string spill_path = "";

		/**
		 * Open spill stream. The daemon appends one line each time
		 * {@link output} fires, while {@link spill_open} is true.
		 */
		public GLib.FileOutputStream spill_stream;

		/**
		 * True after the spill file is opened, false after it is
		 * closed.
		 */
		public bool spill_open = false;

		public Bubble (FileVerification verification)
```

### 3. `ollmfilesd/Sandbox/Bubble.vala` — `run()`: create the spill and append every line

**Why:** This is the only place a Bash command starts. The file has to exist before the first `output` line, and it has to close when `exec` emits `finished`.

**Where:** `run()`, after the unknown-handle return, through the existing `finished` connection. `exec.begin` stays where it is.

**Depends on:** §1 and §2.

#### Remove

```vala
		/**
		 * Start {@link OLLMbwrap.Bubble.exec} and reply with the pid.
		 *
		 * @param request inbound RPC
		 */
		private async void run(OLLMrpc.Request request)
		{
			var bubble = request.connection.leases.get(
				(int) request.args.get(0).get_uint64()) as OLLMbwrap.Bubble;
			if (bubble == null) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INVALID_PARAMS,
						"unknown sandbox handle"
					)
				});
				return;
			}
			var ended = "";
			bubble.finished.connect((output) => {
				ended = output;
			});
			bubble.exec.begin(bubble.command, bubble.working_dir, (obj, res) => {
				try {
					bubble.exec.end(res);
				} catch (GLib.Error e) {
					if (ended == "") {
						ended = "ERROR: " + e.message;
					}
				}
			});
			while (bubble.pid == 0 && ended == "") {
				GLib.Timeout.add(50, () => {
					this.run.callback();
					return false;
				});
				yield;
			}
			if (bubble.pid == 0) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						ended
					)
				});
				return;
			}
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				retval = OLLMrpc.val("i", bubble.pid)
			});
		}
```

#### Replace with

```vala
		/**
		 * Start {@link OLLMbwrap.Bubble.exec} and reply with the pid.
		 *
		 * @param request inbound RPC
		 */
		private async void run(OLLMrpc.Request request)
		{
			var bubble = request.connection.leases.get(
				(int) request.args.get(0).get_uint64()) as OLLMbwrap.Bubble;
			if (bubble == null) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INVALID_PARAMS,
						"unknown sandbox handle"
					)
				});
				return;
			}
			var spill_dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(),
				"ollmchat", "bash-spill");
			try {
				GLib.File.new_for_path(spill_dir).make_directory_with_parents(null);
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						e.message
					)
				});
				return;
			}
			var spill_file = GLib.Path.build_filename(spill_dir,
				"run_command-" + bubble.session_id.to_string() + "-" +
				GLib.get_real_time().to_string() + ".log");
			try {
				bubble.spill_stream = GLib.File.new_for_path(spill_file).replace(
					null, false, GLib.FileCreateFlags.PRIVATE, null);
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						e.message
					)
				});
				return;
			}
			bubble.spill_path = spill_file;
			bubble.spill_open = true;
			bubble.output.connect((line) => {
				if (!bubble.spill_open) {
					return;
				}
				try {
					bubble.spill_stream.write_all((line + "\n").data, null);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					bubble.spill_open = false;
					try {
						bubble.spill_stream.close(null);
					} catch (GLib.Error close_error) {
						GLib.warning("%s", close_error.message);
					}
					try {
						GLib.File.new_for_path(bubble.spill_path).delete(null);
					} catch (GLib.Error delete_error) {
						GLib.warning("%s", delete_error.message);
					}
					bubble.spill_path = "";
				}
			});
			var ended = "";
			bubble.finished.connect((output) => {
				ended = output;
				if (!bubble.spill_open) {
					return;
				}
				try {
					bubble.spill_stream.close(null);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					bubble.spill_open = false;
					bubble.spill_path = "";
					return;
				}
				bubble.spill_open = false;
				if (bubble.output_lines > 50) {
					return;
				}
				try {
					GLib.File.new_for_path(bubble.spill_path).delete(null);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return;
				}
				bubble.spill_path = "";
			});
			bubble.exec.begin(bubble.command, bubble.working_dir, (obj, res) => {
				try {
					bubble.exec.end(res);
				} catch (GLib.Error e) {
					if (ended == "") {
						ended = "ERROR: " + e.message;
					}
				}
			});
			while (bubble.pid == 0 && ended == "") {
				GLib.Timeout.add(50, () => {
					this.run.callback();
					return false;
				});
				yield;
			}
			if (bubble.pid == 0) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						ended
					)
				});
				return;
			}
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				retval = OLLMrpc.val("i", bubble.pid)
			});
		}
```

### 4. `ollmfilesd/Sandbox/Bubble.vala` — `wait()` / `wait_run()`: return the path

**Why:** The footer needs the server path and the daemon line count. `msg` stays the tail text. `args` carries the path and the line count.

**Where:** the `wait` docblock, the `wait_run` docblock, and `wait_run` as a whole. The loop sleeps while the job is still ours and is not waiting on stdin. After the loop, each outcome returns once.

**Depends on:** §1 and §3. For an ended job, `finished` has already closed the file before `wait_run` reads `ended`.

#### Remove

The `wait` docblock.

```vala
		/**
		 * ''Sandbox-Bubble.wait'' — wait on a job we started.
		 *
		 * Seconds below 1 means 60. Retval is the exit code once the
		 * job has ended, or the negative pid while it is still running.
		 *
		 * @param request inbound RPC
		 * @param pid bwrap pid from {@link rpc_run}
		 * @param seconds how long to wait
		 * @param session_id chat that started this command
		 */
```

#### Replace with

```vala
		/**
		 * ''Sandbox-Bubble.wait'' — wait on a job we started.
		 *
		 * Seconds below 1 means 60. Retval is the exit code once the
		 * job has ended, or the negative pid while it is still running.
		 * args[0] is the spill path, empty unless the run has more
		 * than 50 lines. args[1] is the line count.
		 *
		 * @param request inbound RPC
		 * @param pid bwrap pid from {@link rpc_run}
		 * @param seconds how long to wait
		 * @param session_id chat that started this command
		 */
```

#### Remove

The `wait_run` docblock.

```vala
		/**
		 * Poll the job every 5 seconds until it ends or the wait expires.
		 *
		 * A finished job replies with its exit code. A live job replies
		 * with the negative pid, including when it is waiting on stdin.
		 *
		 * @param request inbound RPC
		 */
```

#### Replace with

```vala
		/**
		 * Poll the job every 5 seconds until it ends or the wait expires.
		 *
		 * A finished job replies with its exit code. A live job replies
		 * with the negative pid, including when it is waiting on stdin.
		 * Every success reply puts the spill path in args[0] (empty
		 * unless the run has more than 50 lines) and the line count
		 * in args[1].
		 *
		 * @param request inbound RPC
		 */
```

#### Remove

`wait_run`.

```vala
		private async void wait_run(OLLMrpc.Request request)
		{
			var pid = (int) request.args.get(0).get_int();
			var seconds = (int) request.args.get(1).get_int();
			var session_id = request.args.get(2).get_int64();
			var left = seconds < 1 ? 60 : seconds;
			while (left > 0) {
				if (OLLMbwrap.Bubble.jobs == null || !OLLMbwrap.Bubble.jobs.has_key(pid)) {
					if (OLLMbwrap.Bubble.ended.has_key(pid)
						&& OLLMbwrap.Bubble.ended.get(pid).session_id == session_id) {
						var done = OLLMbwrap.Bubble.ended.get(pid);
						var msg = string.joinv("\n", done.tail);
						if (msg != "") {
							msg += "\n";
						}
						msg += "Exit code: " + done.exit_status.to_string();
						OLLMbwrap.Bubble.ended.unset(pid);
						request.reply(new OLLMrpc.Response() {
							id = request.id,
							retval = OLLMrpc.val("i", done.exit_status),
							msg = msg
						});
						return;
					}
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						retval = OLLMrpc.val("i", 0),
						msg = "command has ended"
					});
					return;
				}
				var bubble = OLLMbwrap.Bubble.jobs.get(pid);
				if (bubble.session_id != session_id) {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						retval = OLLMrpc.val("i", 0),
						msg = "command has ended"
					});
					return;
				}
				if (bubble.waiting_stdin()) {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						retval = OLLMrpc.val("i", -pid),
						msg = string.joinv("\n", bubble.tail)
					});
					return;
				}
				var step = left < 5 ? left : 5;
				GLib.Timeout.add_seconds(step, () => {
					this.wait_run.callback();
					return false;
				});
				yield;
				left -= step;
			}
			if (OLLMbwrap.Bubble.jobs == null || !OLLMbwrap.Bubble.jobs.has_key(pid)) {
				if (OLLMbwrap.Bubble.ended.has_key(pid)
					&& OLLMbwrap.Bubble.ended.get(pid).session_id == session_id) {
					var done = OLLMbwrap.Bubble.ended.get(pid);
					var msg = string.joinv("\n", done.tail);
					if (msg != "") {
						msg += "\n";
					}
					msg += "Exit code: " + done.exit_status.to_string();
					OLLMbwrap.Bubble.ended.unset(pid);
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						retval = OLLMrpc.val("i", done.exit_status),
						msg = msg
					});
					return;
				}
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					retval = OLLMrpc.val("i", 0),
					msg = "command has ended"
				});
				return;
			}
			var still = OLLMbwrap.Bubble.jobs.get(pid);
			if (still.session_id != session_id) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					retval = OLLMrpc.val("i", 0),
					msg = "command has ended"
				});
				return;
			}
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				retval = OLLMrpc.val("i", -pid),
				msg = string.joinv("\n", still.tail)
			});
		}
```

#### Replace with

The loop only sleeps. A missing job, the wrong session, or stdin leaves the loop. The replies sit once underneath it, each as its own return. The finished-job reply is the last block, at the method's own indent.

```vala
		private async void wait_run(OLLMrpc.Request request)
		{
			var pid = (int) request.args.get(0).get_int();
			var seconds = (int) request.args.get(1).get_int();
			var session_id = request.args.get(2).get_int64();
			var left = seconds < 1 ? 60 : seconds;
			while (left > 0) {
				if (OLLMbwrap.Bubble.jobs == null || !OLLMbwrap.Bubble.jobs.has_key(pid)) {
					break;
				}
				var bubble = OLLMbwrap.Bubble.jobs.get(pid);
				if (bubble.session_id != session_id) {
					break;
				}
				if (bubble.waiting_stdin()) {
					break;
				}
				var step = left < 5 ? left : 5;
				GLib.Timeout.add_seconds(step, () => {
					this.wait_run.callback();
					return false;
				});
				yield;
				left -= step;
			}
			if (OLLMbwrap.Bubble.jobs != null && OLLMbwrap.Bubble.jobs.has_key(pid)) {
				var bubble = OLLMbwrap.Bubble.jobs.get(pid);
				if (bubble.session_id != session_id) {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						retval = OLLMrpc.val("i", 0),
						msg = "command has ended",
						args = OLLMrpc.args("si", "", 0)
					});
					return;
				}
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					retval = OLLMrpc.val("i", -pid),
					msg = string.joinv("\n", bubble.tail),
					args = OLLMrpc.args(
						"si",
						bubble.output_lines > 50 ? bubble.spill_path : "",
						bubble.output_lines
					)
				});
				return;
			}
			if (!OLLMbwrap.Bubble.ended.has_key(pid)) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					retval = OLLMrpc.val("i", 0),
					msg = "command has ended",
					args = OLLMrpc.args("si", "", 0)
				});
				return;
			}
			var done = OLLMbwrap.Bubble.ended.get(pid);
			if (done.session_id != session_id) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					retval = OLLMrpc.val("i", 0),
					msg = "command has ended",
					args = OLLMrpc.args("si", "", 0)
				});
				return;
			}
			var msg = string.joinv("\n", done.tail);
			if (msg != "") {
				msg += "\n";
			}
			msg += "Exit code: " + done.exit_status.to_string();
			OLLMbwrap.Bubble.ended.unset(pid);
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				retval = OLLMrpc.val("i", done.exit_status),
				msg = msg,
				args = OLLMrpc.args(
					"si",
					done.output_lines > 50 ? done.spill_path : "",
					done.output_lines
				)
			});
		}
```

### 5. `ollmapp/android/tools/Bash/Request.vala` and `liboctools/Bash/Request.vala` — drop the local spill

**Why:** The daemon now owns the only full copy. The client keeps live `client.run_tool.output` notifications. The footer uses the path and the count from `wait`.

**Where:** the same hunks in both files. Field list, the spill open in `execute`, the spill close in `execute`'s `finally`, both `bash_finished_text` calls in `bash_remote`, the `bash_finished_text` call in `manage`, the spill close on `finished` inside `arm_bash_listener`, the per-line spill write, and `bash_finished_text` itself.

**Depends on:** §4.

**Fields**

**Where:** Instance fields at the top of `Request`. Remove `output_lines`, `spill_stream`, `spill_active`, and `spill_path`. `stopped` and `timed_out` stay.

#### Remove

```vala
		private int output_lines = 0;
		private bool stopped = false;
		private bool timed_out = false;
		private uint timeout_src = 0;
		private string[] pending_output = {};
		private uint pending_output_src = 0;
		private GLib.FileOutputStream spill_stream;
		private bool spill_active = false;
		private string spill_path = "";
```

#### Replace with

```vala
		private bool stopped = false;
		private bool timed_out = false;
		private uint timeout_src = 0;
		private string[] pending_output = {};
		private uint pending_output_src = 0;
```

**`execute` spill open**

**Where:** In `execute`, the block that assigns `this.spill_path` immediately before the `bash_remote` call.

#### Remove

```vala
			this.spill_path = GLib.Path.build_filename(
				this.agent.chat().agent.session.task_dir(),
				"run_command-" + this.request_id.to_string() + ".log");
			try {
				this.spill_stream = GLib.File.new_for_path(this.spill_path).replace(
					null, false, GLib.FileCreateFlags.PRIVATE, null);
				this.spill_active = true;
			} catch (GLib.Error e) {
				this.spill_active = false;
			}
```

**`execute` `finally`**

**Where:** In `execute`'s `finally`, the `spill_active` close and delete. The pending-output flush and `client.run_tool.end` stay.

#### Remove

```vala
				if (this.spill_active && !this.detached) {
					try {
						this.spill_stream.close(null);
					} catch (GLib.Error e) {
					}
					this.spill_active = false;
					if (this.output_lines <= 50) {
						try {
							GLib.File.new_for_path(this.spill_path).delete(null);
						} catch (GLib.Error e) {
						}
						try {
							GLib.File.new_for_path(GLib.Path.get_dirname(this.spill_path)).delete(null);
						} catch (GLib.Error e) {
						}
					}
				}
```

**`bash_remote` finished and timeout results**

**Where:** Both `return this.bash_finished_text(waited.msg)` calls in `bash_remote`. One is the finished wait. One is the timeout path after `kill`.

#### Remove

```vala
				return this.bash_finished_text(waited.msg);
```

#### Replace with

```vala
				return this.bash_finished_text(
					waited.msg,
					waited.args.get(0).get_string(),
					(int) waited.args.get(1).get_int());
```

**`manage` `wait`**

**Where:** The `return this.bash_finished_text(waited.msg)` call in `manage`, inside `case "wait"`.

#### Remove

```vala
						return this.bash_finished_text(waited.msg);
```

#### Replace with

```vala
						return this.bash_finished_text(
							waited.msg,
							waited.args.get(0).get_string(),
							(int) waited.args.get(1).get_int());
```

**`arm_bash_listener` `finished`**

**Where:** Inside the `finished` notification branch, the `req.spill_active` close and delete. The pending-output flush and `client.run_tool.end` stay.

#### Remove

```vala
					if (req.spill_active) {
						try {
							req.spill_stream.close(null);
						} catch (GLib.Error e) {
						}
						req.spill_active = false;
						if (req.output_lines <= 50) {
							try {
								GLib.File.new_for_path(req.spill_path).delete(null);
							} catch (GLib.Error e) {
							}
							try {
								GLib.File.new_for_path(GLib.Path.get_dirname(req.spill_path)).delete(null);
							} catch (GLib.Error e) {
							}
						}
					}
```

**`arm_bash_listener` `output`**

**Where:** The `output` notification branch, from `var line` through the `spill_active` write. The live `pending_output` append stays.

#### Remove

```vala
				var line = notif.args.get(0).get_string();
				req.pending_output += line;
				req.output_lines++;
				if (req.spill_active) {
					try {
						req.spill_stream.write_all((line + "\n").data, null);
					} catch (GLib.Error e) {
						req.spill_active = false;
					}
				}
```

#### Replace with

```vala
				var line = notif.args.get(0).get_string();
				req.pending_output += line;
```

**`bash_finished_text`**

**Where:** The whole `bash_finished_text` method. Footer wording stays. The path and the count come from the wait reply. An empty path means the daemon deleted the file.

#### Remove

```vala
		/**
		 * Command result, plus the spill footer when more than 50 lines arrived.
		 *
		 * @param msg last lines, or ''command has ended''
		 * @return text the agent reads
		 */
		private string bash_finished_text(string msg)
		{
			if (this.output_lines <= 50) {
				return msg;
			}
			return msg + @"

**Below are the last 50 of $(this.output_lines) lines.**
Full output: $(this.spill_path)
Do not read this file whole — it is $(this.output_lines) lines. Use grep, head, or tail on it with this tool to find the part you need.
";
		}
```

#### Replace with

```vala
		/**
		 * Command result, plus the spill footer when the daemon kept
		 * the spill file.
		 *
		 * @param msg last lines, or ''command has ended''
		 * @param path server spill path, empty when the file was not kept
		 * @param lines daemon line count
		 * @return text the agent reads
		 */
		private string bash_finished_text(string msg, string path, int lines)
		{
			if (path == "") {
				return msg;
			}
			return msg + @"

**Below are the last 50 of $(lines) lines.**
Full output: $(path)
Do not read this file whole — it is $(lines) lines. Use grep, head, or tail on it with this tool to find the part you need.
";
		}
```

## Close

- 🚫 CLOSED 2026-11-05. §1–§5, the server spill path, are in the tree. This log stops there.
- ℹ️ `bash-spill`, `tools/bash/YYYY/MM/DD`, and boot cleanup are [`2026-11-05-CLOSED-bash-tools-spill.md`](2026-11-05-CLOSED-bash-tools-spill.md).

## Attempts / changelog

- ✔️ 2026-11-03 — read the tablet session json and logcat for pid 20434. No product change.
- 🔷 2026-11-03 — corrected direction: retain the spill path, store the file on the server, and fetch it through the file daemon rather than tablet disk.
- 💩 2026-11-04 — replacement proposal: spill file under the daemon host data dir, `wait` args carry the path and the line count, both Bash clients stop writing a local log. No product change.
- 💩 2026-11-04 — `wait_run` in that proposal sleeps in the loop and replies once after it. The finished-job reply is one block at the method's own indent.
- ✔️ 2026-11-04 — applied §1–§5. `ninja -C build` built `libocbwrap.so`, `ollmfilesd`, and `liboctools.so`. This build does not compile `ollmapp/android/tools/Bash/Request.vala`; that file matches `liboctools/Bash/Request.vala`.
- 🚫 2026-11-05 — closed. Later `bash-spill` mkdir work is the new bug, not this one.
