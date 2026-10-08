# 2.31 — URGENT — `bash` as a process tool

**Status:** ⏳ **design** — phased, built back-to-front from the daemon. No phase is ready to apply; Phase A's open questions gate the rest.

> **Do not update** `docs/plans/TOOLS-1.0-summary.md` **for this sub-plan.**

**Was:** `RPC-8.2.8.10-URGENT-android-remote-bash.md`. Moved to `TOOLS` because this is a tool problem, not an RPC one.

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](RPC-8.2.8-filesd-connections-ui.md) Phase 12

**Sub-plans:** phases A–E below become `TOOLS-2.31.1` … `TOOLS-2.31.5` as each one's open questions close.

- [`TOOLS-2.31.1`](TOOLS-2.31.1-daemon-job-model.md) — **Phase A**, the daemon job model. Code proposals written and measured.
- [`TOOLS-2.31.6`](TOOLS-2.31.6-PARKED-daemon-sandbox-bubble-rpc.md) — earlier daemon `Sandbox-Bubble` RPC draft. **Parked, do not apply.**

**Depends on:**

- [`RPC-8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md) — Agent Pi on `LIVE` / `SOCKET`. Registers `write` / `read` only. Does not register `Bash`.
- [`BWRAP-2.10.4.15`](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md) — daemon sandbox RPC design. Not on the wire yet.

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

Proposed Vala follows `docs/coding-standards.md`.

---



## Purpose

- **🔷** A separate ticket. Not stuffed into [`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md).
- **🔷** Turn `bash` into a tool the phone can use **remotely**.
  - The command runs on the desktop `ollmfilesd`.
  - Not on the phone.
- **🔷** `bash` becomes its **own tool**, taking over the name it already owns as an alias. `run_command` is left alone.
- **🔷** `⏳` `timeout = -1` returns after 15 s and hands the agent a **running process** to manage. Every other timeout still kills.
- **🔷** `⏳` The UI must **show** that a background process is running, and the **user** must be able to kill it, not just the agent.
- **🔷** `⏳` The agent manages running processes through the **same tool**, with the pid as an argument and `kill` / `tail` / `wait` / `send` as the command. No second tool.
- **🔷** `⏳` Build it back-to-front: the daemon job model first, the tool last.
- **ℹ️** The current tool API is written out below, as the thing being replaced.
- **ℹ️** An earlier daemon implementation is parked in [`TOOLS-2.31.6`](TOOLS-2.31.6-PARKED-daemon-sandbox-bubble-rpc.md), kept to be mined, not applied.

---



## Current tool API



### Registration and advertisement

- **ℹ️** A tool is an `OLLMchat.Tool.BaseTool` subclass, registered with `History.Manager.register_tool(tool)`, which is only `this.tools.set(tool.name, tool)`.
- **ℹ️** What the model sees comes from four overrides on the tool: `name`, `description`, `parameter_description`, `example_call`.
- **ℹ️** `deserialize(Json.Node)` turns the model's arguments into an `OLLMchat.Tool.RequestBase`.



### `run_command` and `bash`

- **ℹ️** `OLLMtools.RunCommand.Tool` is `run_command`. `OLLMtools.RunCommand.Bash` is `bash`.
- **ℹ️** `Bash` overrides `name`, `title`, and `example_call` only. Same `Request`, same execution path.
- **ℹ️** Parameters, from `Tool.parameter_description` and matching `Request` properties:
  - `command` — required shell string. `#` comments are rejected.
  - `working_dir` — absolute path. Defaults to project root, else home.
  - `network` — default false. Without it bwrap uses `--unshare-net`.
  - `run_as_root` — default false. Runs outside the sandbox.
  - `timeout` — wall-clock seconds, **default 60**.
  - `allow_write` — `project` (default) / `no` / PATH-style absolute roots.



### One call, one string

- **ℹ️** `Request.execute()` is the whole tool call. It returns **one string**, which becomes the tool result the agent reads.
- **ℹ️** Order inside `execute()`:
  - Reject empty `command`, normalize `working_dir`, build the permission question, await permission.
  - Open a spill file at `task_dir()/run_command-<request_id>.log`.
  - Arm `timeout_src = GLib.Timeout.add_seconds(this.timeout, …)`.
  - `yield execute_tool_async()` — bwrap via `OLLMbwrap.Bubble.exec`, or `GLib.Subprocess` when bwrap is unavailable, Flatpak, or `run_as_root`.
- **ℹ️** The timeout callback sets `timed_out = true` and calls `this.stop()`. **The process is killed.** There is no path where the call returns with the command still running.
- **ℹ️** `Request.stop()` kills the bubble (`bubble.stop()`) or the subprocess group (`Posix.kill(-pid, KILL)` then `force_exit()`).



### Streaming today

- **ℹ️** `bubble.output` lines land in `pending_output` and flush on a 500 ms timer as an `OLLMrpc.Notification`:
  - `method = "client.run_tool.output"`, `id = this.request_id`.
- **ℹ️** A final `client.run_tool.end` notification carries the command text.
- **ℹ️** This is **display only**. The agent's result is still just the returned string.



### What the agent gets back

- **ℹ️** Last **50** lines only, with `// ... (output truncated: showing last 50 of N lines) ...` prepended.
- **ℹ️** Full output stays in the spill file; the path is appended when truncated, as `// LLM received last 50 of N lines.` followed by `Full output: <path>`.
- **ℹ️** Footer carries `Exit code: N`, any seccomp evidence, `Command stopped by user.`, and the timeout note.
- **ℹ️** The tool `description` has an `Output:` section, but it is advice about writing a **narrower command** ("Prefer a specific directory, non-recursive `ls`, `find -maxdepth`, `git ls-files`, or pipe through `head` / `grep`"). It says nothing about what to do with the spill file once one exists.

---



## Proposed behaviour — `timeout = -1` detaches, everything else kills

- **🔷** `timeout` stays a **hard** timeout. A positive value kills the command when it expires, exactly as today.
- **🔷** A **negative** timeout is the only way to get a background process. It waits **15 seconds**, then returns with the pid and leaves the command running. `-1` is what the tool advertises, but the test is `timeout < 0`, so any negative value behaves the same way.
- **🔷** So there are three outcomes:
  - **Finished inside a positive timeout** — return the output (or its tail) and the result, as today.
  - **Still running at a positive timeout** — killed, as today.
  - **`timeout = -1`** — after 15 s, return the output so far **and the pid**. Nothing is killed.
- **ℹ️** Backgrounding being opt-in is what keeps this safe. An agent that never asks for `-1` cannot leave processes behind, so nothing about existing behaviour drifts.
- **🔷** Any return that hands back a pid also **lists the commands that can be run on it**. The agent is told what to do next at the point it needs to know.
- **🔷** Process management stays on the **same tool**. No second tool, no `action` parameter, no extra RPC call for kill / status / wait.
- **🔷** The pid is a **tool argument**, not part of the command line. `command` carries only the verb.
- **ℹ️** Streaming to the application is unchanged in shape — `client.run_tool.output` already carries lines by `request_id`.

### `pid` as a parameter

- **🔷** One new parameter, `pid`. When it is set, `command` is a management verb rather than a shell line.
  - `command = "kill"`, `pid = 1234` — stop that job.
  - `command = "tail"`, `pid = 1234` — return its output so far and whether it is still alive.
  - `command = "wait"`, `pid = 1234`, `timeout = 60` — wait that many seconds, then return as the first call did.
  - `command = "send yes"`, `pid = 1234` — write `yes` to that job's stdin.
- **🔷** `send` is the verb, the rest of the string is the payload. That is the whole of it.
- **🔷** **No newline is added.** The payload is written exactly as given.
  - **🔷** If the model wants an Enter, it puts a real newline in the payload. It is capable of that; this is not an escape sequence to parse.
  - **🚫** Do not append a trailing newline, and do not translate a literal `\n` into one.
- **🔷** Instead, **hint after the fact**. When a `send` produces little or no new output, the reply notes that ending the payload with a newline may help if the command is waiting on a prompt.
  - **ℹ️** "Produced no effect" does not need a guessed threshold. Phase A can see from `/proc` whether the command is *still* blocked on the job's stdin after the write, which is the actual condition.
- **🔷** When `pid` is unset the tool behaves exactly as it does today. Nothing about normal commands changes.
- **🔷** Dispatch is `if (this.pid != 0)`, then the first word of `command` selects the verb, and for `send` the remainder is the payload.
- **🚫** The `pid` argument is the **only** trigger. Never sniff the command text to decide whether a call is management — splitting verb from payload happens only once `pid` is already set.

#### Why the verb runs in the tool, not in a shell

- **ℹ️** The shell *could* do some of this. The sandbox **shares the host PID namespace** — `build_args` adds `--unshare-user` and optionally `--unshare-net`, but no `--unshare-pid` and no `--proc`, and `--ro-bind / /` gives the sandbox the **host** `/proc`. A pid from one `exec` is visible and signallable from the next.
- **ℹ️** Handling it in the tool is still better on four counts:
  - `Request.stop()` kills the process **group** (`Posix.kill(-pid, KILL)` then `force_exit()`). A shell `kill 1234` does not, so a command that spawned children leaves orphans.
  - Stopping through the job runs the overlay copy-back and cleanup that `exec` does on the way out. A raw signal from a second sandbox bypasses all of it.
  - The UI can be told the job is gone. A raw `kill` leaves the frame and its Stop button believing the process is live.
  - On Android it works unchanged. The verb is handled in `Request`, which already routes to the daemon, so the phone never needs host `/proc`.
- **ℹ️** `wait` could not be a shell command anyway. The builtin only waits on children of the same shell, and each call is a fresh shell.
- **ℹ️** `tail` already has somewhere to read from. `Request` writes every line to `task_dir()/run_command-<request_id>.log`.
- **ℹ️** `send` could not be a shell command at all. Nothing in a second sandbox can reach another process's stdin.

#### `send` needs a pipe that does not exist yet

- **ℹ️** `Bubble.exec` builds its subprocess with `GLib.SubprocessFlags.STDIN_INHERIT`, so the child's stdin **is the daemon's own stdin**. There is no pipe to write to, and `/proc/PID/fd/0` points at the daemon's stdin as well.
- **🔷** `⏳` So `send` needs `GLib.SubprocessFlags.STDIN_PIPE` and the resulting stream kept on the bubble for the life of the job.
- **ℹ️** Phase A has the tested answer for how to do that without hanging ordinary commands.
- **ℹ️** `kill` / `tail` / `wait` need none of it. `send` can land after them if the pipe turns out to be awkward.

### How a detached job is watched

- **🔷** Start the command with `timeout = -1`, then **poll it about every 5 seconds**.
- **🔷** The poll is looking for the job becoming stuck. Two things end the watch:
  - the command **ended**
  - the command is **waiting on stdin**
- **🔷** Either one is the trigger to report back to the model. The return is driven by what the job is doing, not only by a flat timer.
- **🔷** The report tells the model its four options:
  - **`send`** text to it
  - **`kill`** it
  - **`wait`** a number of seconds
  - **do nothing** — in which case it is killed within about the next **60 seconds**
- **🔷** `wait` **defaults to 60 seconds**. A bare `command = "wait"`, `pid = 1234` is a complete call and needs nothing else.
  - **🔷** The job carries on as if it were still on its negative timeout. `wait` only parks the agent for 60 seconds.
  - **🔷** At the end of the wait, if the job is still alive, the **same pid block is returned again**. The agent can `wait` as many times as it likes.
  - **🔷** A duration can still be given, and it rides on the existing `timeout` parameter rather than a new one. `command = "wait"`, `pid = 1234`, `timeout = 90`.
- **🔷** The loop only ends when the agent kills the job, stops waiting, or the job finishes on its own.
- **ℹ️** Detecting "waiting on stdin" is the `/proc` check in Phase A, not a guess from output going quiet.
- **ℹ️** The 60 second reap and the 15–20 minute idle rule are separate triggers, not rival settings for one timer:
  - **60 s** — the job was reported stuck, the model was handed its four options, and it did nothing about them.
  - **15–20 min** — no client activity at all. The phone is gone. This reaps a job that is still working perfectly well, just unattended.
- **ℹ️** A job that is running and being watched hits neither.

### `timeout = -1` — start it and come back

- **🔷** `-1` is the agent saying "this will not finish quickly". The tool waits **15 seconds** and then returns with the pid.
- **ℹ️** The 15 seconds is not wasted. It is long enough to catch the common failure where the command dies immediately — a typo, a missing binary, a port already bound. Those come back as an ordinary failed command, not as a pid the agent then has to poll.
- **ℹ️** `timeout` is already `public int timeout { get; set; default = 60; }`, so `-1` needs no type change.
- **ℹ️** It must be mapped to 15 before it reaches the timer. `GLib.Timeout.add_seconds` takes a `uint`, so an unmapped `-1` wraps to 4294967295 seconds and the timeout never fires at all.
- **ℹ️** `to_summary()` prints the timeout whenever it is not 60, so it would show `Timeout: -1s` in the permission prompt.
- **ℹ️** `-1` is not interchangeable with `timeout = 15`. The latter still kills at 15 s. Only `-1` detaches.
- **🚫** The permission prompt does **not** need extra wording about the command being left running. `to_summary()` showing the timeout is enough. The user sees the running job in the UI instead — see Phase D.
- **🔷** **Any** negative timeout detaches. The test is `timeout < 0`, not `timeout == -1`. No error on `-2`, no special case, no validation.

### What a pid return says

- **🔷** When the tool returns a pid, it lists the commands available for it. The model does not have to remember the management verbs from the tool description.
- **🔷** Shape of the returned text, as the agent would read it:

```
Waiting for input. pid 1234.

Call this tool again with pid=1234 and command set to one of:
  send <text>  write to its stdin
  wait         wait 60 more seconds for it
  tail         show the last 50 lines of its output
  kill         stop it
Left alone, it is killed in about 60 seconds.
```

- **🔷** The same block is returned by `wait` whenever it comes back with the job still alive, so the agent never has to scroll back for the verbs.
- **🔷** Nothing repeats it once the job is gone. A `wait` that outlives the job, a `tail` on a dead job, and `kill` all end with an ordinary result — output and exit status, no verb list.
- **ℹ️** A positive timeout never produces this block. It kills and reports as it does today.
- **🚫** Do not shorten or suppress the block to save tokens. It is cheap enough to repeat on every background return.

### Truncation — tell the agent how to read the spill file

- **ℹ️** Half of this is already in. When output exceeds the cap the agent gets `// LLM received last 50 of N lines.` and `Full output: <path>`.
- **🔷** What is missing is the **advice**. The path is named but nothing tells the agent not to read it whole, so the obvious next move is `cat <path>` — which puts the entire output back into context and defeats the truncation.
- **🔷** The truncation note should say to `grep` / `head` / `tail` the file rather than read it.
- **💩** Wording, appended where the path is given:

```
**Below are the last 50 of 4120 lines.**
Full output: /path/to/run_command-7.log
Do not read this file whole — it is 4120 lines. Use grep, head, or tail
on it with this tool to find the part you need.
```

- **🔷** Drop the leading `//`. It reads as a code comment and means nothing here.
- **🔷** Mark the line in **bold** (`**…**`) so it stands out from the command output above it.
- **🔷** Say **"below are the last 50 of 4120 lines"**. The existing `"// LLM received last 50 of 4120 lines."` does not say *where* those lines are.
- **ℹ️** Three sites carry this wording in `RunCommand/Request.vala` — two `"// LLM received last 50 of "` at lines 468 and 696, and `"// ... (output truncated: showing last 50 of "` at line 808.

- **🔷** The cap stays **50**. That is the consistent number everywhere — it is not being raised to 100.
- **🔷** `tail <pid>` uses the same 50, so background reads match one-shot commands.
- **ℹ️** 50 is already the value at all eleven sites in `RunCommand/Request.vala`, so nothing has to change for the cap itself. Only the advice text above is new.
- **🚫** Do not extract 50 into a `const`. `docs/coding-standards-router.md` requires user or plan approval for a new named constant and prefers the literal at the use site.
- **ℹ️** Two of the eleven are inside message strings (`"// LLM received last 50 of "` and `"showing last 50 of "`). If the cap is ever revisited, those two must move with the tests — a mismatch would not fail the build, it would just misreport the count to the agent.

### Where the dispatch goes

- **🔷** `pid` is declared beside `timeout` on `Request`, and documented in `Tool.parameter_description` next to it.
- **💩** The dispatch sits at the top of `Request.execute()` in `liboctools/RunCommand/Request.vala`, between the empty-`command` guard and the `normalize_working_dir()` call.
- **ℹ️** That position matters. A management call has no working directory to validate, must not raise a permission prompt, and must not open a spill file or emit `client.run_tool.start`. Every one of those begins below that line.
- **⏳** **🔷** This is not reviewable as prose. Phase C writes the actual hunk — the `pid != 0` branch, the verb switch, and what each verb returns — and it gets confirmed against real code, not against this description.

#### Only our own pids

- **🔷** The tool acts **only on pids it created**. A pid belonging to any other process on the machine is refused.
- **🔷** So the pids of our own jobs are stored, in a map or equivalent, and an incoming `pid` is looked up there before anything is done with it. No lookup hit, no action.
- **ℹ️** This is not optional hardening. The sandbox shares the host PID namespace, so an unchecked `kill` would reach any process the user can signal — including the app itself.
- **ℹ️** The map is the same registry Phase A has to build for the daemon. Who owns it is still open there.

### Open — **🔷** confirm

- **ℹ️** Switching to `STDIN_PIPE` is safe as long as the pipe is closed right after spawn for jobs that do not want `send`. Measured; see Phase A.
- **🔷** `send` to a job that has already exited is **not an error**. It returns a note that the command has ended.
  - **🔷** The RPC layer may still answer with an error code. The tool turns that into the plain "command has ended" line the model reads.
  - **ℹ️** Nothing is written anywhere in that case.
- **🔷** The pid is the bwrap pid from `child.get_identifier()`. Phase A explains why that one and not an opaque id.
- **🔷** The registry is the pid-to-`Bubble` map in Phase A. The daemon returns the pid on the first exec, the model quotes it back through the `pid` argument, and the registry resolves it.
- **🔷** A management call raises **no permission prompt**. It never reaches `build_perm_question` and that is intended.
- **🔷** `tail` always shows the **last 50 lines of the log**, like `tail` does. Not a delta, not "since last read".
  - **🔷** It ends with the helpful block — the log file path and the pid being looked at.
- **🔷** A detached job survives client disconnect and dies on a 15–20 minute idle timer. Phase A.
- **ℹ️** The four `"Command timed out after Ns. Raise timeout in run_command if this was expected to run longer."` messages stay correct, since a positive timeout still kills, and behaviour there is unchanged. The `-1` path needs its own wording, which is a free choice as long as it is sensible.

#### Spill file on the `-1` path

- **ℹ️** The spill file is the log `tail` reads. It is `task_dir()/run_command-<request_id>.log` and `Request` appends every output line to it while the command runs.
- **ℹ️** Two things happen to it in the `finally` of `execute()`, both tied to the **tool call** ending rather than the **command** ending:
  - the write stream is closed
  - the file is deleted if the command produced 50 lines or fewer
- **ℹ️** On a positive timeout those are both right, because the command is dead by then. That path is unchanged.
- **ℹ️** On `-1` the call returns at 15 s while the command runs on. If the `finally` still fires, the log stops growing and may be deleted, so a later `tail` shows a stale file or none at all.
- **💩** So for a detached job only, closing and deleting move to where the process actually ends.



---

## The user must be able to kill a background process

- **🔷** If a process can outlive the tool call, the **user** needs a way to kill it. Not only the agent.
- **🔷** The UI must **show that something is running in the background**. A detached job is invisible today once the tool frame closes, and the user has no way to know it is there.
- **🔷** From that indication the user must be able to **kill the job**. Seeing it is not enough on its own.
- **ℹ️** There are two kill paths today, and both do the same unconditional thing:
  - `libollmchatgtk/ToolOutput.vala` — the **Stop** button on the tool frame.
  - `libollmchat/History/Session.vala` `cancel_current_request()` — the chat-level stop.
  - Both are `foreach (var req in this.agent.active_tools.values) { req.stop(); }`.

### What the new model breaks

- **ℹ️** `client.run_tool.end` is emitted from the `finally` in `Request.execute()`. On the `-1` path that `finally` runs **at the 15 s return**, while the process is still alive.
- **ℹ️** `ChatWidget` answers `client.run_tool.end` with `this.current_output.close()` and `this.current_output = null`. The frame closes and **the Stop button is destroyed while the process is still running**.
- **ℹ️** `ChatWidget` holds exactly one `current_output`. A second `client.run_tool.start` overwrites it and orphans the first frame, so two live processes have nowhere to both render.
- **ℹ️** `client.run_tool.output` calls `this.current_output.output(...)` with **no null guard**. Output arriving after `end` is a null dereference.
- **ℹ️** Stop is all-or-nothing. Killing one command kills every other entry in `active_tools` with it.
- **ℹ️** `run_tool.output` carries `id = this.request_id`, but `run_tool.start` and `run_tool.end` do **not**, and `ChatWidget` ignores the id entirely. Nothing can route a notification to the right frame.
- **ℹ️** `RunCommand.Request` never calls `unregister_tool` itself. Whether a detached request stays in `active_tools` is incidental today, not a decision.

### Open — **🔷** decide with the tool contract

- **⏳** **🔷** Which surface carries the indication and the kill? The requirement is settled, the surface is not.
  - **💩** Keep the tool frame open with Stop live, and emit `run_tool.end` when the **process** ends rather than when the call returns. Closest to what exists, but dies with the message and the session.
  - **💩** A persistent background-job indicator, since a process can outlive the frame, the message, and the session. Survives everything, but is new UI.
  - **ℹ️** The frame alone cannot satisfy the requirement on its own, because a job can still be running after the conversation has moved on.
- **⏳** **🔷** Does the chat-level stop kill background processes, or only the in-flight turn?
- **⏳** **💩** `run_tool.start` / `end` need to carry `id`, and `ChatWidget` needs a map keyed by it, if more than one process can be live at once.
- **⏳** **💩** `stop()` has to become per-process instead of "everything in `active_tools`".
- **⏳** **💩** What kills a background process on session close or app quit? Nothing does today.
- **ℹ️** On Android the process runs on the desktop. Killing it from the phone is the same daemon stop call, but the UI has to find the handle after the tool call has already returned.

---



## Current behaviour (remote path)

- **ℹ️** `Request.execute_tool_async` calls in-process `OLLMbwrap.Bubble.exec`. The command never leaves the app process.
- **ℹ️** Overlay apply after a local exec is File.* RPC ([`done/2.10.4.19`](done/2.10.4.19-DONE-runcommand-overlay-index.md)).
- **ℹ️** `write` / `read` already go through `ProjectManager` RPC when the client is remote.
- **ℹ️** Android `initialize_client` registers `write` / `read` only ([`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md) Phase 2).
- **ℹ️** `AgentPi.Factory.register_config` `GLib.error`s without `write` / `read` / `bash`. Android therefore does not call `register_config` yet.
- **ℹ️** Daemon `Bubble.*` is still **DEFERRED** ([`FILES-2.10.4.1`](FILES-2.10.4.1-ollmfilesd-rpc-api.md) · [`2.10.4.15`](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md)).

---



## Design decisions

- **🔷** Phone `bash` is an RPC tool. Exec is on the desktop daemon.
- **🔷** Do not register in-process `Bash` on Android.
- **🔷** `Bubble.exec` on `ollmfilesd` is the one exec path.
  - Linux desktop does not keep a separate in-process `OLLMbwrap.Bubble.exec` as the future path.
  - Callers go through that RPC.
  - That RPC is also how this is tested.
- **🔷** Keep the `Bash` class for now. The name is the Agent Pi tool (`bash`). It stays a wrapper on `RunCommand.Tool`.
- **🔷** After the exec wire exists, Android registers `Bash`, then `AgentPi.Factory.register_config`.
  - Same order as `write` / `read` today.
- **🔷** HTTPS is being retired. The phone reaches the daemon over the TLS TCP socket (`filesd.socket`, `SslListen`).
  - **ℹ️** Handover is [`RPC-1.11.3`](RPC-1.11.3-tcp-client-handover.md). `TcpListen` stays the plaintext Windows listener.
- **ℹ️** `Bash` today only sets `name`, `title`, and `example_call`. `Request.execute_tool_async` is what spawns. Whether that method is the only edit is not decided.
- **🔷** Whether this needs another V2 cutover is open.
  - [`2.10.4.15`](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md) still says the daemon RPC caller lands at the V2 flip.
  - This ticket does not decide that.

---



## Parked implementation

- **ℹ️** [`TOOLS-2.31.6`](TOOLS-2.31.6-PARKED-daemon-sandbox-bubble-rpc.md) holds a complete set of daemon code proposals written before this design. **Do not apply it.**
- **ℹ️** What still stands in it: the `OLLMbwrap.Bubble` changes, the `FileVerification` work, the live-handle streaming design, `live_handles = true` on the listeners, and the Vala test approach modelled on `tests/rpc/subscribe-test.vala`.
- **ℹ️** What Phases A and B supersede: its `rpc_create` / `rpc_run` / `stop` wire covers `kill` only, it has no `STDIN_PIPE`, no job registry, and a lease lifetime that assumes the client unrefs when the command finishes.
- **💩** Mine it during Phase B rather than rewriting from scratch.

---



## `bash` becomes its own tool

- **🔷** This does not get bolted onto `run_command`. `pid`, four verbs, `-1`, and a job registry are too much to clutter it with.
- **🔷** `bash` is the tool that takes it over. It is already the Pi-facing name, and today it is only an alias.
- **ℹ️** `RunCommand.Bash` currently overrides `name`, `title`, `example_call`, and `clone` — nothing else. Same `Request`, same `execute`, same everything.
- **🔷** `run_command` stays as it is. In-process, one call one string, hard timeout, no pid.
- **ℹ️** So the split is: `run_command` is the simple local tool, `bash` is the RPC tool that can detach and be managed.

### What that costs — **ℹ️** facts to design against

- **ℹ️** `liboctools/Registry.vala` `fill_tools` registers **both** on desktop, back to back. So desktop agents would see two shell tools with different capabilities.
- **ℹ️** `bash` has **no config registration today**. `init_config`, `setup_config_defaults`, and `register_config` all name `RunCommand.Tool` only. A first-class `bash` needs adding to all three, or it has no settings row and cannot be disabled.
- **ℹ️** `libollmchatgtk/ChatWidget.vala` special-cases `m.name == "run_command"` when restoring a session, to re-render tool output as a collapsed `Execution results` frame. `bash` has never matched it, so restored `bash` output already renders differently.
- **ℹ️** `AgentPi.Factory.register_config` `GLib.error`s on a missing `bash`, so whatever `bash` becomes has to keep that name.
- **ℹ️** `RunCommand/Bash.vala` is unconditional in `liboctools/meson.build`, so it is already in the Android build.

### Open — **🔷** decide

- **⏳** **🔷** Does `bash` stop subclassing `RunCommand.Tool`, or keep inheriting and override the parts that differ? It needs its own `Request`, which is the bulk of the class.
- **⏳** **🔷** Where does it live? Staying in `liboctools/RunCommand/` is odd once it is not a `RunCommand` variant.
- **⏳** **🔷** Do desktop agents get both tools, or does `bash` replace `run_command` there too? Two shell tools in one tool list invites the model to pick the wrong one.
- **⏳** **💩** Does `run_command` keep its own `Request`, or does it become the degenerate case of the new one? Two copies of the bwrap and subprocess paths is the thing most likely to rot.

---

## Phase A — daemon job model (`⏳`)

**ℹ️** Split out to [`TOOLS-2.31.1`](TOOLS-2.31.1-daemon-job-model.md), which carries the measurements and the code proposals. Summary only below.

- **🔷** `⏳` A job must survive the call that created it. Today nothing does.
- **🔷** `⏳` A map of pid to `Bubble` is the registry, and it is the one genuinely new piece of state. It is also the **authorisation check** — a pid that is not in it was not started by us, and nothing is done to it.
- **🔷** The pid is the **bwrap** pid, which is also the process group leader, so one number is the handle, the key, and the kill target.
- **🔷** `⏳` `OLLMbwrap.Bubble` gains `command` / `working_dir` properties and a `finished` signal, because `exec` has no completion signal and `stopped` is set only by `stop()`.
- **🔷** `⏳` A job can be written to and can be asked whether it is stuck on stdin. Neither is declared up front by the agent.
- **🔷** A detached job is **not** killed when the client disconnects. A phone going into a lift must not kill the build.
- **🔷** `⏳` Instead it dies after **15–20 minutes with no client activity**. Idle timer, not a disconnect hook.
- **⏳** **🔷** Still open there: who owns the registry, and which calls count as "activity".

---

## Phase B — daemon RPC verbs (`⏳`)

- **🔷** `⏳` `Sandbox-Bubble` gains a call per verb — kill, tail, wait, send — on top of create and run.
- **ℹ️** The parked [`TOOLS-2.31.6`](TOOLS-2.31.6-PARKED-daemon-sandbox-bubble-rpc.md) has `rpc_create` / `rpc_run` / `stop` only, so it covers `kill` and nothing else. Phase B **supersedes its wire shape**; the `Bubble` and `FileVerification` work in it still stands.
- **🔷** `⏳` Output streaming stays the live-handle design already worked out in the sub-plan — `connection.export`, `RPC-Live-Subscribe.rpc_signal` on `output`, and `live_handles = true` on the daemon's listeners.
- **ℹ️** HTTPS cannot carry this. `HttpServer` does not override `Listen.broadcast` and enforces `X-rpc-sequence` with a 409 on mismatch. The TLS TCP listener is the transport, which is why HTTPS is being retired.
- **🔷** `⏳` Code proposals — after Phase A settles the registry and lifetime.

---

## Phase C — the `bash` tool (`⏳`)

- **🔷** `⏳` Build the tool contract designed above: `pid` parameter, the four verbs, `timeout = -1`, the pid-return block, and the truncation advice.
- **🔷** `⏳` When the file client is `LIVE`, `bash` runs the command on the daemon. Not `OLLMbwrap` in the Android process.
- **ℹ️** `SOCKET` is the desktop local Unix hello ([`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md)). `ollmfilesd` is already up on this machine. Empty `url`. Not a remote row.
- **🔷** What `SOCKET` does for exec is not decided. Not enough here to choose in-process bwrap versus the same RPC.
- **ℹ️** Overlay / index update after daemon exec is the daemon's job in `2.10.4.15` (`Scan` + `FileVerification` on `ollmfilesd`).
- **🔷** `⏳` Code proposals — after Phase B is on the wire.

---

## Phase D — user-facing kill (`⏳`)

- **🔷** `⏳` Deliver the UI side already analysed above — a Stop that survives the tool call returning, per-job rather than all-or-nothing, and `run_tool.start` / `end` carrying `id` so more than one job can render.
- **🔷** `⏳` Show the user that a background job exists, and let them kill it from there. This is the half that does not exist in any form today: the current Stop button is attached to an in-flight call, so it has nothing to attach to once the call has returned.
- **🚫** Do not ship Phase C's `-1` without this. A detached process the user cannot see or stop is worse than no backgrounding at all.

---

## Phase E — Android registers `bash` (`⏳`)

- **🔷** `⏳` `ollmapp/android/OllmchatWindow.vala` `initialize_client` registers the `bash` tool next to `write` / `read`, then `AgentPi.Factory.register_config`.
- **🔷** `⏳` Still no in-process exec on the phone. Registration is only valid once Phase C routes through RPC.
- **🚫** Do not apply this before Phase C. `bash` in `history_manager.tools` is a tool Agent Pi can call, and until it routes through RPC that call runs `OLLMbwrap` / `GLib.Subprocess` **on the phone**.
- **ℹ️** The class name in the hunk below is `OLLMtools.RunCommand.Bash`, which is only correct if Phase C leaves it in that namespace. Re-check before applying.



### Key facts

- **ℹ️** `register_config` on `liboccoder/AgentPi/Factory.vala` `GLib.error`s on a missing `write`, `read`, or `bash` in the tool map. `bash` is the only one still absent on Android, which is why [`8.2.8.11`](done/RPC-8.2.8.11-DONE-android-startup-history-bars.md) §4 says not to call it yet.
- **ℹ️** `History.Manager.register_tool` is only `this.tools.set(tool.name, tool)`. No config type registration, which is why `write` / `read` work today without being in `AndroidToolsRegistration.init_config`. `bash` needs nothing extra either.
- **ℹ️** `RunCommand/Bash.vala` is unconditional in `liboctools/meson.build`, so the class is already in the Android build.
- **ℹ️** Calling `register_config` is not just an assert. It also seeds `config.agents["agent-pi"]` with the `forbid` list and the skills array. Android has never seeded that, so Agent Pi has been running with no forbid list and no skills.
- **ℹ️** No explicit `save()` after `register_config`, matching desktop `ollmapp/Window.vala`. The seeded agent row persists on the next save, which on the `LIVE` path is the `this.app.config.save()` already in `initialize_client`.

Edits are **Remove** / **Replace with** against the tree. Verify surrounding context before applying.

### 1. `ollmapp/android/OllmchatWindow.vala` — register `bash`, then `register_config`

**Why:** `bash` completes the three tools `AgentPi.Factory.register_config` asserts, so the call can finally run. Registration order is tools first, then the factory — same as desktop.

**Where:** `initialize_client`, the `read` tool block and the `agent-pi` factory block, between `this.register_default_agents()` and `this.agent_dropdown.wire()`.

**Depends on:** Phase C. `bash` must already route through the daemon.

- **ℹ️** The `register_config` line is copied from `ollmapp/Window.vala`, which does `agent_pi.register_config(app.config, this.history_manager.tools)`. Android passes the `config` parameter instead of `app.config`; the bootstrap path assigns `this.app.config = config` before calling `initialize_client`, so they are the same object on both paths.
- **ℹ️** The `has_key` guard shape is kept from the surrounding Android block rather than the unguarded desktop form.



#### Remove

```vala
			if (!this.history_manager.tools.has_key("read")) {
				this.history_manager.register_tool(
					new OLLMtools.ReadFile.Read(this.project_manager));
			}
			if (!this.history_manager.agent_factories.has_key("agent-pi")) {
				var agent_pi = new OLLMcoder.AgentPi.Factory(this.project_manager);
				this.history_manager.agent_factories.set(agent_pi.name, agent_pi);
			}
```



#### Replace with

```vala
			if (!this.history_manager.tools.has_key("read")) {
				this.history_manager.register_tool(
					new OLLMtools.ReadFile.Read(this.project_manager));
			}
			if (!this.history_manager.tools.has_key("bash")) {
				this.history_manager.register_tool(
					new OLLMtools.RunCommand.Bash(this.project_manager));
			}
			if (!this.history_manager.agent_factories.has_key("agent-pi")) {
				var agent_pi = new OLLMcoder.AgentPi.Factory(this.project_manager);
				this.history_manager.agent_factories.set(agent_pi.name, agent_pi);
				agent_pi.register_config(config, this.history_manager.tools);
			}
```



### Testing Phase E

- **🔷** `⏳` On the phone, Agent Pi runs a command and the output comes back from the desktop. Check the command ran on the desktop, not the handset.
- **💩** `⏳` Startup must still reach chat when the desktop is unreachable (`UNREACHABLE` → Chatter). `register_config` runs before the hello result is known, so a missing tool aborts the app rather than falling back.
- **💩** `⏳` Confirm the seeded `agent-pi` config appears in the saved config with the `forbid` list and skills, since Android has not had that row before.

---



## Suggested order

1. **⏳** Answer the two questions left open in [`TOOLS-2.31.1`](TOOLS-2.31.1-daemon-job-model.md) — registry owner, and what counts as activity for the idle timer.
2. **⏳** Decide whether `bash` stops subclassing `RunCommand.Tool`, and whether desktop keeps both tools.
3. **⏳** **Phase A** — apply [`TOOLS-2.31.1`](TOOLS-2.31.1-daemon-job-model.md)
4. **⏳** **Phase B** — `Sandbox-Bubble` calls for kill / tail / wait / send
5. **⏳** **Phase C** — the `bash` tool: `pid`, verbs, `-1`, truncation advice
6. **⏳** **Phase D** — background-job indicator and user-facing kill, before `-1` ships
7. **⏳** **Phase E** — Android registration + `AgentPi.Factory.register_config`

- **💩** Phase B is big enough for its own sub-plan once its open questions close, as Phase A already is. C is likely two — the tool contract and the RPC caller.

---



## LLM notes

- **🚫** Registering in-process `bash` on Android so Agent Pi can start. That runs on the phone.
- **🚫** A long-term in-process `OLLMbwrap.Bubble.exec` on Linux desktop beside the exec RPC. RPC is the exec path.
- **🚫** Applying [`TOOLS-2.31.6`](TOOLS-2.31.6-PARKED-daemon-sandbox-bubble-rpc.md). It predates this design.
- **🚫** Adding `pid`, verbs, or `-1` to `run_command`. That is what `bash` is for.
- **🚫** A second management tool. One tool, `pid` as the argument.
- **🚫** Putting these hunks into [`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md).
- **🚫** `run_as_root` / sudo over RPC ([`2.10.4.15`](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md)).
- **🚫** MCP stdio session RPC (`2.10.4.15` Phase B).
- **🚫** Helper methods unless a fence names one.

