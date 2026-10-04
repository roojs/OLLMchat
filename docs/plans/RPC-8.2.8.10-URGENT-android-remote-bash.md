# 5)]

[New Thread 0x7fffa0ff96c0 (LWP 112966)]

[New Thread 0x7fff8ffff6c0 (LWP 112967)]

[New Thread 0x7fff8f7fe6c0 (LWP 112970)]

[New Thread 0x7fff8effd6c0 (LWP 112971)]

Thread 1 "ollmchat" received signal SIGSEGV, Segmentation fault.

__strlen_avx2 () at ../sysdeps/x86_64/multiarch/strlen-avx2.S:76

warning: 76	../sysdeps/x86_64/multiarch/strlen-avx2.S: No such file or directory

(gdb) bt

#0  __strlen_avx2 () at ../sysdeps/x86_64/multiarch/strlen-avx2.S:76

#1  0x00007ffff6d3825d in g_strdup () at /lib/x86_64-linux-gnu/[libglib-2.0.so](http://libglib-2.0.so).0

#2  0x00007ffff7279f82 in gtk_string_object_new () at /lib/x86_64-linux-gnu/[libgtk-4.so](http://libgtk-4.so).1

#3  0x00007ffff727f20a in gtk_string_list_splice () at /lib/x86_64-linux-gnu/[libgtk-4.so](http://libgtk-4.so).1

#4  0x00007ffff7e8d963 in ??? () at /lib/x86_64-linux-gnu/[libgobject-2.0.so](http://libgobject-2.0.so).0

#5  0x00007ffff7e903db in g_object_new_valist () at /lib/x86_64-linux-gnu/[libgobject-2.0.so](http://libgobject-2.0.so).0

#6  0x00007ffff7e907cf in g_object_new () at /lib/x86_64-linux-gnu/[libgobject-2.0.so](http://libgobject-2.0.so).0

#7  0x00005555555f1108 in oll_mapp_settings_dialog_file_server_row_load_config (self=0x555555bc0000) at ../ollmapp/SettingsDialog/FileServerRow.vala:452

#8  0x00005555555b0d08 in oll_mapp_settings_dialog_connections_page_load_config (self=0x555555806200) at ../ollmapp/SettingsDialog/ConnectionsPage.vala:597

#9  0x00005555555d5bb6 in oll_mapp_settings_dialog_main_dialog_show_dialog_co (_data_=0x5555584830c0) at ../ollmapp/SettingsDialog/MainDialog.vala:230

#10 0x00005555555d599b in oll_mapp_settings_dialog_main_dialog_show_dialog_ready

    (source_object=0x555555931c70, *res*=0x555556cce900, *user*data_=0x5555584830c0) at ../ollmapp/SettingsDialog/MainDialog.vala:223

#11 0x00007ffff6ed783a in ??? () at /lib/x86_64-linux-gnu/[libgio-2.0.so](http://libgio-2.0.so).0

#12 0x00005555555d693e in oll_mapp_settings_dialog_main_dialog_check_all_connections_co (_data_=0x555557c624e0)

    at ../ollmapp/SettingsDialog/MainDialog.vala:285

#13 0x00005555555d614f in oll_mapp_settings_dialog_main_dialog_check_all_connections_ready

    (source_object=0x5555585d8550, *res*=0x5555585dec80, *user*data_=0x555557c624e0) at ../ollmapp/SettingsDialog/MainDialog.vala:297

#14 0x00007ffff6ed783a in ??? () at /lib/x86_64-linux-gnu/[libgio-2.0.so](http://libgio-2.0.so).0

#15 0x00007ffff7d5eacc in oll_mchat_call_models_exec_models_co (_data_=0x555558603610) at ../libollmchat/Call/Models.vala:48

#16 0x00007ffff7d5e702 in oll_mchat_call_models_exec_models_ready (source_object=0x5555585d8550, *res*=0x555557b83b70, *user*data_=0x555558603610)

    at ../libollmchat/Call/Models.vala:42

#17 0x00007ffff6ed783a in ??? () at /lib/x86_64-linux-gnu/[libgio-2.0.so](http://libgio-2.0.so).0

#18 0x00007ffff7d28a8e in oll_mchat_call_base_get_models_co (_data_=0x5555585e3bb0) at ../libollmchat/Call/Base.vala:442

#19 0x00007ffff7d2849e in oll_mchat_call_base_get_models_ready (source_object=0x5555585d8550, *res*=0x555557b82260, *user*data_=0x5555585e3bb0)

    at ../libollmchat/Call/Base.vala:430

#20 0x00007ffff6ed783a in ??? () at /lib/x86_64-linux-gnu/[libgio-2.0.so](http://libgio-2.0.so).0

#21 0x00007ffff7d21d00 in oll_mchat_call_base_send_request_co (_data_=0x555557d877d0) at ../libollmchat/Call/Base.vala:116

#22 0x00007ffff7d21478 in oll_mchat_call_base_send_request_ready (source_object=0x5555557295a0, *res*=0x555555ebfc10, *user*data_=0x555557d877d0)

    at ../libollmchat/Call/Base.vala:106

#23 0x00007ffff6ed783a in ??? () at /lib/x86_64-linux-gnu/[libgio-2.0.so](http://libgio-2.0.so).0

--Type <RET> for more, q to quit, c to continue without paging--

8.2.8.10 — URGENT — `bash` as a remote tool Android can use

**Status:** ⏳ **design** — tool contract is being reworked before any implementation lands. Daemon implementation is parked in `[8.2.8.10.1](RPC-8.2.8.10.1-daemon-sandbox-bubble-rpc.md)`.

> **Do not update** `docs/plans/RPC-1.0-summary.md` **for this sub-plan.**

**Parent:** `[RPC-8.2.8-filesd-connections-ui.md](RPC-8.2.8-filesd-connections-ui.md)` Phase 12

**Sub-plans:**

- `[RPC-8.2.8.10.1](RPC-8.2.8.10.1-daemon-sandbox-bubble-rpc.md)` — daemon `Sandbox-Bubble` RPC implementation. **Parked, do not apply.**

**Depends on:**

- `[RPC-8.2.8.9](done/RPC-8.2.8.9-DONE-android-agent-pi.md)` — Agent Pi on `LIVE` / `SOCKET`. Registers `write` / `read` only. Does not register `Bash`.
- `[BWRAP-2.10.4.15](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md)` — daemon sandbox RPC design. Not on the wire yet.

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

Proposed Vala follows `docs/coding-standards.md`.

---



## Purpose

- **🔷** A separate ticket. Not stuffed into `[8.2.8.9](done/RPC-8.2.8.9-DONE-android-agent-pi.md)`.
- **🔷** Turn `bash` into a tool the phone can use **remotely**.
  - The command runs on the desktop `ollmfilesd`.
  - Not on the phone.
- **🔷** `⏳` Settle the **tool** contract first, then work down to the daemon.
  - A long command must not hold the tool call open.
  - `timeout = -1` returns after 15 s and hands the agent a **running process** to manage.
- **🔷** `⏳` The **user** must be able to kill a background process, not just the agent.
- **🔷** `⏳` The agent manages running processes through the **same tool**, with the pid as an argument and `kill` / `tail` / `wait` / `send` as the command. No second tool.
- **🔷** `⏳` Describe the current tool API before designing the new one.
- **ℹ️** The daemon implementation already drafted is parked in `[8.2.8.10.1](RPC-8.2.8.10.1-daemon-sandbox-bubble-rpc.md)`, not deleted.

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
- **🔷** `timeout = -1` is the **only** way to get a background process. It waits **15 seconds**, then returns with the pid and leaves the command running.
- **🔷** So there are three outcomes:
  - **Finished inside a positive timeout** — return the output (or its tail) and the result, as today.
  - **Still running at a positive timeout** — killed, as today.
  - **`timeout = -1`** — after 15 s, return the output so far **and the pid**. Nothing is killed.
- **💩** Backgrounding being opt-in is what keeps this safe. An agent that never asks for `-1` cannot leave processes behind, so nothing about existing behaviour drifts.
- **🔷** Any return that hands back a pid also **lists the commands that can be run on it**. The agent is told what to do next at the point it needs to know.
- **🔷** Process management stays on the **same tool**. No second tool, no `action` parameter, no extra RPC call for kill / status / wait.
- **🔷** The pid is a **tool argument**, not part of the command line. `command` carries only the verb.
- **ℹ️** Streaming to the application is unchanged in shape — `client.run_tool.output` already carries lines by `request_id`.

### `pid` as a parameter

- **🔷** One new parameter, `pid`. When it is set, `command` is a management verb rather than a shell line.
  - `command = "kill"`, `pid = 1234` — stop that job.
  - `command = "tail"`, `pid = 1234` — return its output so far and whether it is still alive.
  - `command = "wait"`, `pid = 1234` — block up to the timeout, then return as the first call did.
  - `command = "send yes"`, `pid = 1234` — write `yes` to that job's stdin.
- **🔷** `send` is the one verb that takes an argument. Everything after `send ` is the text to write.
  - **🔷** A trailing line break is **inferred**. The agent does not have to supply one.
  - **💩** Append `\n` only when the text does not already end in one, so `send yes` and `send yes\n` behave the same.
  - **💩** Interpret a literal `\n` in the text as a line break, so multi-line input is possible in one call.
- **🔷** When `pid` is unset the tool behaves exactly as it does today. Nothing about normal commands changes.
- **💩** Dispatch is therefore `if (this.pid != 0)`, then the first word of `command` selects the verb, and for `send` the remainder is the payload.
- **🚫** The `pid` argument is the **only** trigger. Never sniff the command text to decide whether a call is management — splitting verb from payload happens only once `pid` is already set.

#### Why the verb runs in the tool, not in a shell

- **ℹ️** The shell *could* do some of this. The sandbox **shares the host PID namespace** — `build_args` adds `--unshare-user` and optionally `--unshare-net`, but no `--unshare-pid` and no `--proc`, and `--ro-bind / /` gives the sandbox the **host** `/proc`. A pid from one `exec` is visible and signallable from the next.
- **💩** Handling it in the tool is still better on four counts:
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
- **💩** That is a change to `OLLMbwrap.Bubble`, not just to the tool, and it affects every command — including ones that today inherit a terminal.
- **💩** `kill` / `tail` / `wait` need none of it. `send` can land after them if the pipe turns out to be awkward.

### `timeout = -1` — start it and come back

- **🔷** `-1` is the agent saying "this will not finish quickly". The tool waits **15 seconds** and then returns with the pid.
- **💩** The 15 seconds is not wasted. It is long enough to catch the common failure where the command dies immediately — a typo, a missing binary, a port already bound. Those come back as an ordinary failed command, not as a pid the agent then has to poll.
- **ℹ️** `timeout` is already `public int timeout { get; set; default = 60; }`, so `-1` needs no type change.
- **💩** It must be mapped to 15 before it reaches the timer. `GLib.Timeout.add_seconds` takes a `uint`, so an unmapped `-1` wraps to 4294967295 seconds and the timeout never fires at all.
- **💩** `to_summary()` prints the timeout whenever it is not 60, so it would show `Timeout: -1s` in the permission prompt. It should say what `-1` means instead.
- **💩** `-1` is not interchangeable with `timeout = 15`. The latter still kills at 15 s. Only `-1` detaches.
- **⏳** **💩** Does the permission prompt say the command will be left running? A user approving `npm run dev` with `-1` is approving something that outlives the turn, which the current wording does not convey.
- **⏳** **💩** Are other negative values an error, or do they all mean `-1`? An error is safer than silently detaching on a typo.

### What a pid return says

- **🔷** When the tool returns a pid, it lists the commands available for it. The model does not have to remember the management verbs from the tool description.
- **💩** Shape of the returned text, as the agent would read it:

```
Left running in the background. pid 1234.

To manage it, call this tool again with pid=1234 and command set to:
  tail         output since you last read it
  wait         wait up to timeout seconds for it to finish
  send <text>  write a line to its stdin
  kill         stop it
```

- **💩** The same block is appended by `wait` when it returns with the job still alive, so the agent never has to scroll back for the verbs.
- **💩** Nothing repeats it once the job is gone. A finished `wait`, a `tail` on a dead job, and `kill` all end with an ordinary result.
- **ℹ️** A positive timeout never produces this block. It kills and reports as it does today.
- **⏳** **💩** This text is a per-call token cost on every background return. If it proves expensive, shorten it to one line once the model has seen it in a session.

### Truncation — tell the agent how to read the spill file

- **ℹ️** Half of this is already in. When output exceeds the cap the agent gets `// LLM received last 50 of N lines.` and `Full output: <path>`.
- **🔷** What is missing is the **advice**. The path is named but nothing tells the agent not to read it whole, so the obvious next move is `cat <path>` — which puts the entire output back into context and defeats the truncation.
- **🔷** The truncation note should say to `grep` / `head` / `tail` the file rather than read it.
- **💩** Wording, appended where the path is given:

```
// LLM received last 50 of 4120 lines.
Full output: /path/to/run_command-7.log
Do not read this file whole — it is 4120 lines. Use grep, head, or tail
on it with this tool to find the part you need.
```

- **🔷** `⏳` The cap itself is probably too aggressive. **100** or so is likely better than 50.
- **⏳** **🔷** Confirm the new number. 50 → 100 doubles the worst-case tokens from a single noisy command, which matters more on a phone.
- **💩** The same cap governs `tail <pid>`, so whatever is chosen applies to background reads too.

#### The cap is a magic number in eleven places

- **ℹ️** `50` is written out literally throughout `RunCommand/Request.vala` — the spill-delete test, both `output_lines > 50` footer tests in the bwrap and subprocess paths, the two `"last 50 of"` message strings, the `truncate_output` default parameter, its call site, the `tail` ring-buffer bound, and the two tests in the bwrap tail reader.
- **💩** Changing the number means editing all of them consistently, and two of them are inside message text where a mismatch would not fail the build — it would just lie to the agent.
- **💩** Worth a single constant before the value changes, not after.
- **⏳** **💩** Should the cap be configurable per call, given `tail` on a long-running job may want more than a one-shot command does?

### Where the dispatch goes

- **💩** At the top of `Request.execute()`, straight after the empty-`command` guard and before `normalize_working_dir()`.
- **ℹ️** That position matters: a management call has no working directory to validate, must not raise a permission prompt, and must not open a spill file or emit `client.run_tool.start`. All of that begins below this point.
- **💩** `pid` is declared beside `timeout` on `Request`, and documented in `Tool.parameter_description` next to it.

### Open — **🔷** confirm

- **⏳** **💩** Does switching to `STDIN_PIPE` change behaviour for ordinary commands? Anything that reads stdin today sees the daemon's; with a pipe nobody writes to, it would see a pipe that never closes. A command like `cat` would hang where it used to end.
- **⏳** **💩** Should `send` on a job that already exited be an error, or a no-op with a note?
- **⏳** **💩** Nothing maps a pid back to a job today. `active_tools` is keyed by `request_id` and is cleared when the call ends, so a live-job registry is the one genuinely new piece of state this needs.
- **⏳** **💩** Which pid is handed out? `Bubble.stop()` signals `this.child.get_identifier()`, the **bwrap** pid, not the inner `/bin/sh`. It only has to be a key the registry understands, so an opaque id would work equally well now that the agent never types it into a shell.
- **⏳** **💩** Permission: a management call never reaches `build_perm_question`, so killing a job prompts for nothing. Confirm that is wanted.
- **⏳** **🔷** What does `tail` show on the second and later calls — everything since the last read, or the whole tail again?
- **⏳** **💩** What kills a job still running when the session ends or the phone disconnects? Nothing does today.
- **⏳** **💩** The spill stream is **closed** in the `finally` of `execute()`, and deleted outright when the command produced 50 lines or fewer. On the `-1` path that would stop the file growing at 15 s and might delete it, so `tail` would find nothing. Both have to move to process end — but only for detached jobs; a positive timeout should keep today's cleanup.
- **ℹ️** The four `"Command timed out after Ns. Raise timeout in run_command if this was expected to run longer."` messages stay correct, since a positive timeout still kills. The `-1` path needs its own text and must not reuse them.



---

## The user must be able to kill a background process

- **🔷** If a process can outlive the tool call, the **user** needs a way to kill it. Not only the agent.
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

- **⏳** **🔷** Where does the user kill it from?
  - **💩** Keep the tool frame open with Stop live, and emit `run_tool.end` when the **process** ends rather than when the call returns.
  - **💩** A separate background-process list, since a process can outlive the frame, the message, and the session.
  - Not chosen.
- **⏳** **🔷** Does the chat-level stop kill background processes, or only the in-flight turn?
- **⏳** **💩** `run_tool.start` / `end` need to carry `id`, and `ChatWidget` needs a map keyed by it, if more than one process can be live at once.
- **⏳** **💩** `stop()` has to become per-process instead of "everything in `active_tools`".
- **⏳** **💩** What kills a background process on session close or app quit? Nothing does today.
- **⏳** **💩** On Android the process runs on the desktop. Killing it from the phone is the same daemon stop call, but the UI has to find the handle after the tool call has already returned.

---



## Current behaviour (remote path)

- **ℹ️** `Request.execute_tool_async` calls in-process `OLLMbwrap.Bubble.exec`. The command never leaves the app process.
- **ℹ️** Overlay apply after a local exec is File.* RPC (`[done/2.10.4.19](done/2.10.4.19-DONE-runcommand-overlay-index.md)`).
- **ℹ️** `write` / `read` already go through `ProjectManager` RPC when the client is remote.
- **ℹ️** Android `initialize_client` registers `write` / `read` only (`[8.2.8.9](done/RPC-8.2.8.9-DONE-android-agent-pi.md)` Phase 2).
- **ℹ️** `AgentPi.Factory.register_config` `GLib.error`s without `write` / `read` / `bash`. Android therefore does not call `register_config` yet.
- **ℹ️** Daemon `Bubble.`* is still **DEFERRED** (`[FILES-2.10.4.1](FILES-2.10.4.1-ollmfilesd-rpc-api.md)` · `[2.10.4.15](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md)`).

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
  - `[2.10.4.15](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md)` still says the daemon RPC caller lands at the V2 flip.
  - This ticket does not decide that.

---



## Phase 1 — Daemon exec wire (`⏳`)

- **ℹ️** Moved out to `[8.2.8.10.1](RPC-8.2.8.10.1-daemon-sandbox-bubble-rpc.md)`. Code proposals are complete there.
- **🔷** `⏳` **Parked.** Do not apply until the tool contract above is settled.
- **⏳** **🔷** What the sub-plan does **not** cover yet, because it predates the detached-process model:
  - it has `rpc_create` / `rpc_run` / `stop` only, so three of the four verbs have no wire — nothing for `tail`, `wait`, or `send`
  - `send` additionally needs `STDIN_PIPE` on the bubble, which nothing in the sub-plan touches
  - lease lifetime assumes the client unrefs when the command finishes, which a detached process breaks

---



## Phase 2 — `RunCommand.Request` drives the remote process (`⏳`)

- **🔷** `⏳` When the file client is `LIVE`, `Request` runs the command on the daemon. Not `OLLMbwrap` in the Android process.
- **ℹ️** `SOCKET` is the desktop local Unix hello (`[8.2.8.9](done/RPC-8.2.8.9-DONE-android-agent-pi.md)`). `ollmfilesd` is already up on this machine. Empty `url`. Not a remote row.
- **🔷** What `SOCKET` does for exec is not decided. Not enough here to choose in-process bwrap versus the same RPC.
- **ℹ️** Overlay / index update after daemon exec is the daemon's job in `2.10.4.15` (`Scan` + `FileVerification` on `ollmfilesd`).
- **⏳** Code proposals — after the tool contract and Phase 1 are settled.

---



## Phase 3 — Android registers `bash` (`⏳`)

- **🔷** `⏳` `ollmapp/android/OllmchatWindow.vala` `initialize_client` registers `OLLMtools.RunCommand.Bash` next to `write` / `read`, then `AgentPi.Factory.register_config`.
- **🔷** `⏳` Still no in-process exec on the phone. Registration is only valid once Phase 2 uses RPC.
- **🚫** Do not apply this before Phase 2. `Bash` in `history_manager.tools` is a tool Agent Pi can call, and until `Request` routes through RPC that call runs `OLLMbwrap` / `GLib.Subprocess` **on the phone**.



### Key facts

- **ℹ️** `register_config` on `liboccoder/AgentPi/Factory.vala` `GLib.error`s on a missing `write`, `read`, or `bash` in the tool map. `bash` is the only one still absent on Android, which is why `[8.2.8.11](done/RPC-8.2.8.11-DONE-android-startup-history-bars.md)` §4 says not to call it yet.
- **ℹ️** `History.Manager.register_tool` is only `this.tools.set(tool.name, tool)`. No config type registration, which is why `write` / `read` work today without being in `AndroidToolsRegistration.init_config`. `bash` needs nothing extra either.
- **ℹ️** `RunCommand/Bash.vala` is unconditional in `liboctools/meson.build`, so the class is already in the Android build.
- **ℹ️** Calling `register_config` is not just an assert. It also seeds `config.agents["agent-pi"]` with the `forbid` list and the skills array. Android has never seeded that, so Agent Pi has been running with no forbid list and no skills.
- **💩** No explicit `save()` after `register_config`, matching desktop `ollmapp/Window.vala`. The seeded agent row persists on the next save, which on the `LIVE` path is the `this.app.config.save()` already in `initialize_client`.
- **⏳** **💩** If process management becomes a second tool, `register_config` may need it in the asserted set too. Unknown until the tool is named.

Edits are **Remove** / **Replace with** against the tree. Verify surrounding context before applying.

### 1. `ollmapp/android/OllmchatWindow.vala` — register `bash`, then `register_config`

**Why:** `bash` completes the three tools `AgentPi.Factory.register_config` asserts, so the call can finally run. Registration order is tools first, then the factory — same as desktop.

**Where:** `initialize_client`, the `read` tool block and the `agent-pi` factory block, between `this.register_default_agents()` and `this.agent_dropdown.wire()`.

**Depends on:** Phase 2. `Bash` must already route through the daemon.

- **ℹ️** The `register_config` line is copied from `ollmapp/Window.vala`, which does `agent_pi.register_config(app.config, this.history_manager.tools)`. Android passes the `config` parameter instead of `app.config`; the bootstrap path assigns `this.app.config = config` before calling `initialize_client`, so they are the same object on both paths.
- **💩** The `has_key` guard shape is kept from the surrounding Android block rather than the unguarded desktop form.



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



### Testing Phase 3

- **🔷** `⏳` On the phone, Agent Pi runs a command and the output comes back from the desktop. Check the command ran on the desktop, not the handset.
- **💩** `⏳` Startup must still reach chat when the desktop is unreachable (`UNREACHABLE` → Chatter). `register_config` runs before the hello result is known, so a missing tool aborts the app rather than falling back.
- **💩** `⏳` Confirm the seeded `agent-pi` config appears in the saved config with the `forbid` list and skills, since Android has not had that row before.

---



## Suggested order

1. **⏳** Settle the tool contract — timeout return, process id, management tool shape, user kill
2. **⏳** Revisit `[8.2.8.10.1](RPC-8.2.8.10.1-daemon-sandbox-bubble-rpc.md)` against that contract, then apply
3. **⏳** Phase 2 — `RunCommand.Request` daemon caller when `LIVE`
4. **⏳** Phase 3 — Android `Bash` + `AgentPi.Factory.register_config`

---



## LLM notes

- **🚫** Registering in-process `Bash` on Android so Agent Pi can start. That runs on the phone.
- **🚫** A long-term in-process `OLLMbwrap.Bubble.exec` on Linux desktop beside the exec RPC. RPC is the exec path.
- **🚫** Applying `[8.2.8.10.1](RPC-8.2.8.10.1-daemon-sandbox-bubble-rpc.md)` before the tool contract is agreed.
- **🚫** Putting these hunks into `[8.2.8.9](done/RPC-8.2.8.9-DONE-android-agent-pi.md)`.
- **🚫** `run_as_root` / sudo over RPC (`[2.10.4.15](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md)`).
- **🚫** MCP stdio session RPC (`2.10.4.15` Phase B).
- **🚫** Helper methods unless a fence names one.

