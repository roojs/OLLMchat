# 2.31.1 — Phase A — daemon job model

**Status:** ⏳ **proposed** — every hunk below was compiled and run outside the tree before being written down. Two open questions remain and neither blocks these hunks.

> **Do not update** `docs/plans/TOOLS-1.0-summary.md` **for this sub-plan.**

**Parent:** [`TOOLS-2.31`](TOOLS-2.31-URGENT-bash-process-tool.md) — `bash` as a process tool, Phase A

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala follows `docs/coding-standards.md`.

---

## Purpose

- **🔷** Make a sandboxed command into a **job** that outlives the call which started it. Nothing in the tree does that today.
- **🔷** Give that job a stable handle, a way to write to its stdin, and a way to tell that it is stuck waiting for input.
- **🔷** Make the job table the **authorisation check** — we act only on processes we started.
- **ℹ️** Everything here is `libocbwrap/Bubble.vala`. No daemon file changes, no wire changes. Those are [`TOOLS-2.31`](TOOLS-2.31-URGENT-bash-process-tool.md) Phase B.
- **ℹ️** Mined from the parked [`TOOLS-2.31.6`](TOOLS-2.31.6-PARKED-daemon-sandbox-bubble-rpc.md) §3, which already drafted `command` / `working_dir` / `finished`.
- **⏳** **🔷** The idle reaper — a detached job dies after 15–20 minutes with no client activity — has no code here. See **Still open**.

---

## What a job needs

- **🔷** **Survive its call.** The registry holds the reference, so nothing drops the last one when `exec`'s caller stops waiting.
- **🔷** **One handle.** The bwrap pid is the key, the kill target, and the process group.
  - **ℹ️** `RunSeccomp.wire_launcher` calls `Posix.setpgid(0, 0)` in child setup on both branches, so the bwrap pid leads the group and `stop()`'s `Posix.kill(-pid, KILL)` already reaches the whole tree.
- **🔷** **Only our own pids.** A pid that is not in the registry is not ours and nothing is done to it.
  - **ℹ️** This is not optional. `build_bubble_args` adds no `--unshare-pid`, so the sandbox shares the host pid namespace and an unchecked signal would reach anything the user can signal.
- **🔷** **A writable stdin, but only when asked for.** Holding a pipe open on a job nobody can write to just hangs it.
- **🔷** **Detection instead of declaration.** The job works out for itself that it is sitting on stdin. The agent never has to say so up front.

### Two things that already work

- **ℹ️** `stop()` is correct as it stands. `Posix.kill(-(int.parse(id)), Posix.Signal.KILL)` targets a process group, and the bwrap child leads one.
  - **ℹ️** The Windows `RunSeccomp.wire_launcher` is empty and has no `setpgid`. Not a problem: bwrap is Linux-only, and `can_wrap()` returns false under Flatpak and when `bwrap` is off PATH.
- **ℹ️** Overlay copy-back already survives a kill. `exec` runs `read_subprocess_output`, then `overlay.scan.run()`, then `detach_sources()` and `overlay.cleanup()`, and none of it is guarded on `stopped`.
  - **ℹ️** A killed process closes its pipes, so `read_subprocess_output` returns normally and the scan and cleanup still run. That holds whether the kill came from `stop()` or from a signal sent outside the process.

### stdin: `/dev/null` by default, a pipe on request

- **ℹ️** Measured with a throwaway `GLib.Subprocess` probe:
  - `STDIN_PIPE` left **open** — `cat` and `grep -c .` hang indefinitely.
  - `STDIN_PIPE` **closed immediately**, or written then closed — about 1 ms.
  - A command that ignores stdin (`echo hello`) — unaffected either way.
- **ℹ️** Today's `STDIN_INHERIT` is worse than it looks. The same probe shows `cat` hanging when the parent has a terminal on stdin and returning instantly when it does not, so current behaviour depends on how the app was launched.
- **💩** So the default becomes **neither flag**, which GLib redirects from `/dev/null`. Reads EOF at once, every time, however the app was started.
  - **ℹ️** Measured with the §2 launcher expression as written: `/bin/cat` spawned with no stdin flag had already exited two seconds later.
- **ℹ️** The choice has to be made at spawn, because a closed pipe cannot be reopened. A probe closed the write end, the child got EOF, and writing again failed with `Stream is already closed`.
- **ℹ️** A FIFO was tried as the way round that. Writers opening one at a time EOF the child on every close. A FIFO with a permanent keepalive writer does work, but it buys nothing over holding the pipe open, and `--tmpfs /tmp` would hide a host FIFO from inside the bubble anyway.

### Detecting a job blocked on stdin

- **ℹ️** Measured by compiling §1 to §4 as written and running them against the cases that could confuse it. Every result below is from that run, not from the earlier exploratory probe:
  - `cat` waiting on stdin — detected.
  - `sh -c 'read x; echo got $x'` — detected, and the blocked process is the **shell itself** with no child, which is why the whole descendant tree is walked. `send("zebra\n")` unblocked it and it ran to completion.
  - `tail -f /dev/null | cat` — **not** detected, correctly. The `cat` is genuinely blocked on fd 0, but that fd is the pipeline's pipe, and the `pipe:[inode]` comparison keeps it out.
  - `sleep 30` — not detected.
- **ℹ️** From the earlier exploratory probe, not re-run here: `grep foo` on stdin is detected; a busy loop and `cat /dev/zero` read `syscall=running` and are not; in `cat | cat` the first is flagged and the second is not, in the same tree.
- **💩** `wchan` is read in the probe but **not** in the proposal. `syscall` field 0 says the process is inside `read`, field 1 says the fd is 0, and the inode match says the fd is ours. `wchan` adding `pipe_read` on top of that is a redundant check.

---

## Still open

- **⏳** **🔷** Who owns the registry. §1 proposes a static on `Bubble`, which makes it daemon-wide and automatic. The alternative is a field on a daemon-side owner, which then has to be reachable from every verb.
- **⏳** **🔷** What counts as "activity" for the 15–20 minute idle reaper — any call on that job, or any call on the connection. No timer code until that is settled, because the answer decides where the timestamp lives.
- **⏳** **💩** Whether `STDIN_PIPE` behaves the same **under bwrap**. The probes ran bare `GLib.Subprocess`; bwrap adds a layer between the pipe and `/bin/sh`.

---

## Phase A code

Edits are **Remove** / **Replace with** / **Add** against the tree. Verify surrounding context before applying. `libocbwrap/Bubble.vala` is already in the `docs/meson.build` valadoc inputs and no files are added, so that list needs no change.

### 1. `libocbwrap/Bubble.vala` — class body: `jobs`, `pid`, `keep_stdin`, `command`, `working_dir`, `finished`

**Why:** Every other change in this plan needs one of these. `jobs` is the registry, the lifetime anchor, and the authorisation check. `pid` is the handle. `keep_stdin` picks the stdin shape at spawn, which is the only point it can be picked. `command` / `working_dir` / `finished` are carried from [`TOOLS-2.31.6`](TOOLS-2.31.6-PARKED-daemon-sandbox-bubble-rpc.md) §3 for an owner that leases the object and cannot see the `exec` return value.

**Where:** class body, the five-line block that starts at `public bool stopped` and ends at `private bool child_active`.

**Depends on:** none.

- **💩** `jobs` is **static**. One table per process covers the daemon, and membership answers "is this ours" with no second structure to keep in step.
  - **ℹ️** The initializer runs in `class_init`, which fires on the first `new Bubble(...)`. Inside any instance method it is therefore set. A cold static read before any bubble was ever built sees `null`, and `null` means the same thing as a missing key — not our job.
- **💩** `keep_stdin` is the name for "this job may be written to". It is set by the tool for a detached job, not by the agent.
- **🔷** `finished` carries the string `exec` returns, which already embeds the exit code and any seccomp evidence.
- **ℹ️** All of it is additive for in-process callers. `RunCommand.Request` keeps passing `exec` its arguments and reading the return value, and never connects `finished`.

#### Remove

```vala
		public bool stopped { get; private set; default = false; }
		public signal void output(string line);
		private string[] tail = {};
		private GLib.Subprocess child;
		private bool child_active = false;
```

#### Replace with

```vala
		public bool stopped { get; private set; default = false; }
		public signal void output(string line);

		/**
		 * Live jobs keyed by {@link pid}, added on spawn and dropped
		 * when the command ends. Holds the only reference to a
		 * detached job, and membership is what authorises ''kill'',
		 * ''tail'' and {@link send}.
		 */
		public static Gee.HashMap<int, Bubble> jobs =
			new Gee.HashMap<int, Bubble>();

		/**
		 * Bwrap child pid, or ''0'' before {@link exec} spawns it.
		 * Also the process group id, so it is the kill target too.
		 */
		public int pid { get; private set; default = 0; }

		/**
		 * When true {@link exec} holds a stdin pipe open for
		 * {@link send}; when false the command reads ''/dev/null''.
		 */
		public bool keep_stdin { get; set; default = false; }

		/**
		 * Shell string for a deferred run, when the owner leases this
		 * object and starts it later. Not read by {@link exec}.
		 */
		public string command { get; set; default = ""; }

		/**
		 * Working directory for a deferred run. Same contract as
		 * {@link command}.
		 */
		public string working_dir { get; set; default = ""; }

		/**
		 * Emitted once the command has ended, for owners that never
		 * see the {@link exec} return value.
		 *
		 * @param output what {@link exec} returned, or its error
		 *   message when it threw
		 */
		public signal void finished(string output);

		private string[] tail = {};
		private GLib.Subprocess child;
		private bool child_active = false;
```

### 2. `libocbwrap/Bubble.vala` — `exec()`: stdin shape, register the job, emit `finished` — ordered chunks

**Why:** Spawn is the only place the stdin shape can be chosen, and the only place the pid exists. The registry entry has to appear there and disappear when the command ends, or a detached job is either unreachable or leaked.

**Where:** `exec()`, three places — the launcher construction near the top, the `if (subprocess != null)` block after `spawnv`, and the tail after `overlay.cleanup()`.

**Depends on:** §1.

- **💩** `finished` is emitted from `exec` itself. [`TOOLS-2.31.6`](TOOLS-2.31.6-PARKED-daemon-sandbox-bubble-rpc.md) §3 left `exec` untouched and had the daemon emit it after the `yield` returned. That was written when the only owner was the RPC handler. A detached job has a watcher that is not the caller, so the signal belongs where the command actually ends.
- **ℹ️** `exec` has exactly one `return` and one `throw`, both at the tail, so emitting there covers every exit.

**Keep**

```vala
			this.overlay.create();
			var run_seccomp = new RunSeccomp(this);
```

**Remove**

```vala
			var launcher = new GLib.SubprocessLauncher(
				GLib.SubprocessFlags.STDOUT_PIPE |
				GLib.SubprocessFlags.STDERR_PIPE |
				GLib.SubprocessFlags.STDIN_INHERIT);
```

**Replace with** — stdin is a pipe only when the owner asked for one; otherwise GLib gives the child `/dev/null`.

```vala
			var launcher = new GLib.SubprocessLauncher(
				GLib.SubprocessFlags.STDOUT_PIPE |
				GLib.SubprocessFlags.STDERR_PIPE |
				(this.keep_stdin
					? GLib.SubprocessFlags.STDIN_PIPE
					: GLib.SubprocessFlags.NONE));
```

**Keep**

```vala
			run_seccomp.wire_launcher(launcher);
```

**Remove**

```vala
			if (subprocess != null) {
				this.child = subprocess;
				this.child_active = true;
			}
```

**Replace with** — record the pid and publish the job while it is alive.

```vala
			if (subprocess != null) {
				this.child = subprocess;
				this.child_active = true;
				var id = subprocess.get_identifier();
				this.pid = id != null ? int.parse(id) : 0;
				Bubble.jobs.set(this.pid, this);
			}
```

**Keep**

```vala
			var result = "";
			 
			if (err == null) {
```

**Remove**

```vala
			run_seccomp.detach_sources();
			this.child_active = false;
			this.overlay.cleanup();
			if (err != null) {
				throw err;
			}
			return result;
```

**Replace with** — retire the registry entry, then tell any watcher how it ended.

```vala
			run_seccomp.detach_sources();
			this.child_active = false;
			this.overlay.cleanup();
			Bubble.jobs.unset(this.pid);
			if (err != null) {
				this.finished("ERROR: " + err.message);
				throw err;
			}
			this.finished(result);
			return result;
```

### 3. `libocbwrap/Bubble.vala` — `send()`: write to the running command's stdin

**Why:** The `send` verb has nowhere to land. `exec` holds the only reference to the subprocess, so the write has to happen here.

**Where:** New method, directly after `stop()` and before the `exec()` docblock.

**Depends on:** §1 and §2 (`keep_stdin` must have produced a pipe).

- **🔷** Nothing is appended to the text. The caller sends its own newline if the command needs a completed line.
- **💩** The method name is `send`, matching the agent-facing verb.
- **ℹ️** Throwing on an ended job is right at this level. The tool turns that into the plain "command has ended" line the model reads, rather than an error.

#### Add — new public method on `Bubble`, immediately below `stop()`

```vala
		/**
		 * Write to the running command's stdin. Needs
		 * {@link keep_stdin} set before {@link exec}; otherwise the
		 * command is reading ''/dev/null'' and there is no pipe.
		 *
		 * Nothing is appended — a caller that wants a completed line
		 * sends the newline itself.
		 *
		 * @param text bytes to write, verbatim
		 * @throws GLib.Error if the command has ended, has no stdin
		 *   pipe, or the write fails
		 */
		public void send(string text) throws GLib.Error
		{
			if (!this.child_active) {
				throw new GLib.IOError.CLOSED("Command has already ended");
			}
			var stdin_pipe = this.child.get_stdin_pipe();
			if (stdin_pipe == null) {
				throw new GLib.IOError.NOT_SUPPORTED("Command has no stdin pipe");
			}
			stdin_pipe.write(text.data);
			stdin_pipe.flush();
		}
```

### 4. `libocbwrap/Bubble.vala` — `waiting_stdin()`: is the job blocked on the stdin we gave it

**Why:** A detached job that has gone quiet is either working or stuck. Guessing from output going silent cannot tell those apart; `/proc` can. This is what turns "it hung" into "it is waiting for input, use send".

**Where:** New method, directly after `send()` from §3.

**Depends on:** §1, §2 and §3.

- **💩** The method name is `waiting_stdin`. It is a question, not a getter, and it does three file reads per process in the tree, so it is a method rather than a property.
- **ℹ️** The descendant walk is not optional. `read x` as a shell builtin blocks in the shell with no child process to find.
- **ℹ️** The `pipe:[inode]` comparison is not optional either. Without it `tail -f /dev/null | cat` reports as waiting for input when it is reading the pipeline.
- **ℹ️** Linux only, which matches bwrap. The non-bwrap `GLib.Subprocess` fallback does not get this and keeps today's behaviour.

#### Add — new public method on `Bubble`, immediately below `send()`

```vala
		/**
		 * Whether the job is blocked reading the stdin we gave it.
		 *
		 * The whole descendant tree is walked because a builtin such
		 * as ''read x'' blocks in the shell with no child to find. A
		 * process counts only when it is inside ''read'' on fd 0
		 * //and// that fd is our pipe — comparing the pipe is what
		 * keeps a blocked pipeline from reading as a stdin wait.
		 *
		 * Linux only, and needs the host pid namespace that
		 * {@link build_bubble_args} leaves shared.
		 *
		 * @return true when something in the job is waiting for
		 *   {@link send}
		 */
		public bool waiting_stdin()
		{
			if (!this.child_active || !this.keep_stdin) {
				return false;
			}
			var stdin_pipe = this.child.get_stdin_pipe() as GLib.UnixOutputStream;
			if (stdin_pipe == null) {
				return false;
			}
			var ours = "";
			try {
				ours = GLib.FileUtils.read_link(
					"/proc/self/fd/" + stdin_pipe.get_fd().to_string());
			} catch (GLib.FileError e) {
				return false;
			}
			string[] pids = { this.pid.to_string() };
			for (var i = 0; i < pids.length; i++) {
				var proc = "/proc/" + pids[i];
				var children = "";
				try {
					GLib.FileUtils.get_contents(
						proc + "/task/" + pids[i] + "/children", out children);
				} catch (GLib.FileError e) {
					continue;
				}
				foreach (var kid in children.strip().split(" ")) {
					if (kid == "") {
						continue;
					}
					pids += kid;
				}
				var syscall = "";
				try {
					GLib.FileUtils.get_contents(proc + "/syscall", out syscall);
				} catch (GLib.FileError e) {
					continue;
				}
				var fields = syscall.strip().split(" ");
				if (fields.length < 2 || fields[0] != "0" || fields[1] != "0x0") {
					continue;
				}
				try {
					if (GLib.FileUtils.read_link(proc + "/fd/0") == ours) {
						return true;
					}
				} catch (GLib.FileError e) {
					continue;
				}
			}
			return false;
		}
```

---

## Testing Phase A

- **🔷** `⏳` Everything here is reachable from the existing in-process path, so it is testable before any RPC work. Drive it from a `Bubble` directly.
- **ℹ️** The stdin and detection behaviour is already measured outside the tree, as noted above. What is **not** yet covered is any of it running through bwrap, the overlay, or seccomp.
- **💩** `⏳` Sequence to assert, all with `keep_stdin = false`:
  - `echo hello` — `pid` is non-zero during the run, `Bubble.jobs` has that key, and the key is gone once `exec` returns.
  - `cat` — exits at once on EOF rather than hanging. This is the case that behaves differently today depending on how the app was launched.
  - `finished` fires with the same string `exec` returned.
- **💩** `⏳` Then with `keep_stdin = true`:
  - `cat` — `waiting_stdin()` is true within a second or so, `send("hi\n")` is echoed on `output`, and `waiting_stdin()` is true again afterwards.
  - `sh -c 'read x; echo got $x'` — detected even though the blocked process is the shell, not a child.
  - `tail -f /dev/null | cat` — `waiting_stdin()` stays **false**. This is the false positive the inode comparison exists to kill.
  - `sleep 30` and a busy loop — both stay false.
  - `send` after the command exits throws, and does not write anywhere.
- **💩** `⏳` `stop()` on a `keep_stdin` job still kills the whole group, and `finished` still fires with `Command stopped by user.` in the string.
- **🔷** `⏳` Re-run the `STDIN_PIPE` probe **through bwrap** rather than bare `GLib.Subprocess`, which is the open question above.

---

## LLM notes

- **🚫** Touching `stop()`, or adding overlay handling for the kill path. Both already work — see **Two things that already work**.
- **🚫** A FIFO for stdin, or any scheme that reopens a closed pipe. Neither is possible or needed.
- **🚫** Adding `--unshare-pid` or `--proc` to `build_bubble_args`. The `/proc` detection in §4 depends on the shared pid namespace.
- **🚫** A timer inside `exec`. `exec` owns the overlay and must keep it mounted for as long as the command runs, so it cannot return early. The 15 second detach belongs **above** `exec`: the caller stops waiting and reports the pid, while the `Bubble` keeps running and eventually fires `finished`. The `jobs` entry is what stops the last reference being dropped in the meantime.
- **🚫** An agent-facing "this job will want send" parameter. §4 exists so nothing has to declare it.
- **🚫** Helper methods beyond the two named in §3 and §4.
