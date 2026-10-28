# Agent Pi bash and read calls failed

**Status:** ✅ issues 2 and 3 are done. ✔️ issues 4, 5, and 6 applied — rebuild the chat app before checking them

Agent Pi was asked to fold `FileConnectionAdd` into the source-diff test. It tried to list that folder and read the file. The commands and the path were fine. Two things in the harness stopped it.

## Issue 1 — Shell commands never run

- 🔷 The shell tool does not run `ls` or `pwd` itself. It asks the file daemon to start a sandbox, then to listen for what the command prints. The daemon can start the sandbox. Listening was never switched on when the daemon started, so the command never runs.
- 🔷 The model only sees `ERROR:` and tries another command. All five `bash` calls died this way: `ls`, `ls` again, `find`, `pwd && ls`, and `pwd`. The reply is an error code with an empty message, which is what `RpcErrorCode.to_error` sends. `Bash.Request` prints `e.message` and drops the code.

### Based on

- ✔️ Each call got a sandbox created, then died on the follow-up "listen for output" step. The command itself was never started. Five sandboxes were left behind.
- ✔️ The daemon log says `no handler for 'RPC-Live-Subscribe'`. That sentence stays in the log. The wire reply is `METHOD_NOT_FOUND` with an empty message.
- ℹ️ The daemon already allows live listeners. Startup calls `OLLMrpc.rpc_register()` without the flag that installs that handler.

### `ollmfilesd/Application.vala` — `startup`: register the live handlers

**Why:** The sandbox is created. The next call is "listen for output", and that handler is installed only when `rpc_register` is passed `true`.

**Where:** `startup`, the `OLLMrpc.rpc_register()` call before `Daemon.rpc_register()`.

**Depends on:** none.

#### Remove

```vala
			OLLMrpc.rpc_register();
```

#### Replace with

Same call, with live handlers enabled.

```vala
			OLLMrpc.rpc_register(true);
```

### `liboctools/Bash/Request.vala` — `execute`: say which code came back

**Why:** The wire message is empty on purpose. This catch is what the model reads, and it prints that empty field.

**Where:** `execute`, the `catch` around `bash_remote()`.

**Depends on:** none.

#### Remove

```vala
			} catch (Error e) {
				return "ERROR: " + e.message;
			} finally {
```

#### Replace with

Keep a real message when the call sent one. When the message is empty, use the domain and the code.

```vala
			} catch (Error e) {
				if (e.message != "") {
					return "ERROR: " + e.message;
				}
				return "ERROR: " + e.domain.to_string() + " " + e.code.to_string();
			} finally {
```

## ✅ Issue 2 — Reading a file with no line range is refused

**Status:** ✅ Done. The check is in `liboctools/ReadFile/Request.vala`. The 17:03 read returned the file (7294 characters). Do not revisit.

- 🔷 The model asked to read `examples/oc-test-source-diff/FileConnectionAdd.vala` and did not give a line range. That path is a symlink to `ollmapp/android/FileConnectionAdd.vala`.
- 🔷 The tool says a line range is optional. The code treats "no line range" as a bad line number and answers `start_line must be >= 1`. The file had already been loaded.

### Based on

- ✔️ The call sent only `file_path`. The schema says that is the only required argument.
- ✔️ With no line numbers, `start_line` stays at its default `-1`. The check `start_line < 1` then fires.
- ✔️ `File.fetch`, `File.exists`, and `File.read` had already succeeded. The code under the check returns that text when neither end was set.

### `liboctools/ReadFile/Request.vala` — `execute_request`: skip the range check when no lines were sent

**Why:** The model sent only `file_path`. Both line properties stay at `-1`, and `start_line < 1` throws after the file is already loaded.

**Where:** `execute_request`, the `if (this.start_line < 1)` inside the block that runs when the read is not a full-file, summarize, or find-words request.

**Depends on:** none.

#### Remove

```vala
				if (this.start_line < 1) {
```

#### Replace with

Throw only when a line number was sent. Both defaults (`-1`) fall through and return the buffer already read.

```vala
				if ((this.start_line != -1 || this.end_line != -1) && this.start_line < 1) {
```

## ✅ Issue 3 — bash crashes once live subscribe works

**Status:** ✅ Done. `arm_bash_listener` creates `bash_lease` on first use. Bash runs. Do not revisit.

- 🔷 After the daemon accepts `RPC-Live-Subscribe.rpc_signal`, the next bash call aborts.
- 🔷 The abort is `gee_abstract_map_set: assertion 'self != NULL' failed` in `arm_bash_listener`.

### Based on

- ✔️ 16:13:06 chat log: `Sandbox-Bubble.rpc_create` and both `RPC-Live-Subscribe.rpc_signal` calls reply, then the process dies. The file daemon log has no `no handler` line for those two calls.
- ✔️ The stack is `oll_mtools_bash_request_arm_bash_listener` at `Request.bash_lease.set`.
- ✔️ `bash_lease` was created only inside `Request()`. `liboctools/Bash/Tool.vala` builds the request with `Json.gobject_deserialize`. That path uses `g_object_new` and does not run the creation method, so the map stays null. `RequestBase` already says requests are created that way.

### `liboctools/Bash/Request.vala` — create the lease map on first use

**Why:** `arm_bash_listener` runs on a deserialized request. The creation method never ran, so `bash_lease` is null. A field initializer does not work for this map. Create it the first time a lease is stored.

**Where:** `arm_bash_listener`, before `bash_lease.set`. The field stays uninitialized.

**Depends on:** none.

#### Remove

```vala
			Request.bash_lease.set((int) lease, this);
```

#### Replace with

```vala
			if (Request.bash_lease == null) {
				Request.bash_lease = new Gee.HashMap<int, Request>();
			}
			Request.bash_lease.set((int) lease, this);
```

## ✔️ Issue 4 — code search returns `ERROR:` and nothing else

- 🔷 `codebase_search` failed with no explanation. The chat showed `ERROR:`.
- 🔷 The next outbound frame was titled `Sending message` and its body was that same `ERROR:`.

### Based on

- ✔️ 17:03:46 chat log. Query `Test source diff build configuration`. `Codebase.search` id=41 replies with an empty error. The tool result is `ERROR: ` (7 characters).
- ✔️ Daemon log: `RPC dispatch: no handler for 'Codebase' (Codebase.search)`.
- ✔️ The client calls `Codebase.search` (`liboctools/CodebaseSearch/Request.vala`). The daemon registers `rpc_search` (`ollmfilesd/Codebase.vala`). `Ffi.dispatch` returns false when that method name is missing, then the log names the class.
- ✔️ `RequestBase.execute` returns `"ERROR: " + e.message`. The wire message is empty, so the model and the UI get `ERROR:` with nothing after it.
- ✔️ `ChatCompletions.send` uses the last outbound message as the `Sending message` body once the list is longer than two messages. That last message was the tool result `ERROR: `.

### `liboctools/CodebaseSearch/Request.vala` — call `Codebase.rpc_search`

**Why:** The daemon registers `rpc_search`. The client calls `search`, so dispatch finds no handler and the wire message is empty.

**Where:** `execute_request`, the `method` on the `Codebase` request. The class docblock names the same method.

**Depends on:** none.

#### Remove

```vala
	 * parameters, calls ''Codebase.search'' on ''ollmfilesd'', and
```

```vala
			// Step 2: Codebase.search on ollmfilesd (filter, FAISS, snippets — daemon-side)
			var response = yield this.project_manager.rpc.call(new OLLMrpc.Request() {
				method = "Codebase.search",
```

#### Replace with

```vala
	 * parameters, calls ''Codebase.rpc_search'' on ''ollmfilesd'', and
```

```vala
			// Step 2: Codebase.rpc_search on ollmfilesd (filter, FAISS, snippets — daemon-side)
			var response = yield this.project_manager.rpc.call(new OLLMrpc.Request() {
				method = "Codebase.rpc_search",
```

### `libollmchat/Tool/RequestBase.vala` — `execute`: keep the code when the message is empty

**Why:** This catch is what `codebase_search` returns. An empty wire message becomes `ERROR:` and that string is the next `Sending message` body.

**Where:** `execute`, the `catch` around `execute_request()`.

**Depends on:** none.

#### Remove

```vala
			} catch (Error e) {
				GLib.debug("RequestBase.execute: Tool '%s' threw error: %s", this.tool.name, e.message);
				return "ERROR: " + e.message;
			}
```

#### Replace with

```vala
			} catch (Error e) {
				GLib.debug("RequestBase.execute: Tool '%s' threw error: %s", this.tool.name, e.message);
				if (e.message != "") {
					return "ERROR: " + e.message;
				}
				return "ERROR: " + e.domain.to_string() + " " + e.code.to_string();
			}
```

🚫 Do not replace the code with a generic "search failed" string.

## ✔️ Issue 5 — bash output frame

- 🔷 Bash runs. The live frame is still wrong.
- 🔷 It is white, with a grey up arrow. Markdown boxes use `.oc-frame` plus a theme class, so they pick up the blue (or theme) fill and a matching arrow. This frame does not, so `frame.css` never paints it.
- 🔷 The command is the title and a long command is cut with an ellipsis. The ellipsis can stay. Under the title it says `Running command in sandbox`.
- 🔷 The output area stays black with white text. That shell is required.
- 🚫 Do not replace the black output with the frame fill.
- 🔷 The output should show the full command.
- 🔷 About 4 pixels of margin around the output.
- 🔷 The expanded output is far too short.

### Based on

- ✔️ `ToolOutput` adds `tool-frame` only. `RenderSourceView` adds `oc-frame` and the theme class (`oc-frame-info` and the others). `frame.css` colours `.oc-frame`, its text, and its buttons from `--frame-bg` and `--frame-text-emphasis`.
- ✔️ The arrow is `go-up-symbolic` on a plain `Gtk.Button`. Without `.oc-frame`, that button keeps the default grey.
- ✔️ `.tool-output` in `resources/style.css` forces background `#000000` and text `#ffffff`, which covers the frame fill even after the class is added.
- ✔️ The command is only the header label (`ellipsize` end). The text buffer starts empty. Open height is `min_content_height` 80, cap 280.

### `libollmchatgtk/ToolOutput.vala` — paint it as a markdown frame

**Why:** The classes are what `frame.css` matches. `oc-frame-info` is the same theme as the other tool frames.

**Where:** `ToolOutput` constructor.

**Depends on:** none.

#### Remove

```vala
			this.add_css_class("tool-frame");
```

#### Replace with

```vala
			this.add_css_class("tool-frame");
			this.add_css_class("oc-frame");
			this.add_css_class("oc-frame-info");
```

#### Remove

```vala
			var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
```

#### Replace with

```vala
			var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
			row.add_css_class("oc-frame-header");
```

#### Remove

```vala
			this.view.add_css_class("tool-output");
```

#### Replace with

The title stays the cut-off command. The body starts with the full command.

```vala
			this.view.add_css_class("tool-output");
			this.view.buffer.text = command + "\n";
```

#### Remove

```vala
			this.scroll = new Gtk.ScrolledWindow() {
				min_content_height = 80,
				max_content_height = 280,
				propagate_natural_height = true,
				hexpand = true,
				vexpand = false
			};
```

#### Replace with

Open height 200 instead of 80. Cap 480 instead of 280. Four pixels around the output.

```vala
			this.scroll = new Gtk.ScrolledWindow() {
				min_content_height = 200,
				max_content_height = 480,
				propagate_natural_height = true,
				hexpand = true,
				vexpand = false,
				margin_top = 4,
				margin_bottom = 4,
				margin_start = 4,
				margin_end = 4
			};
```

### `resources/style.css` — keep the black shell

**Why:** The output is a shell. Black background and white text stay. Those two colours win over `.oc-frame text`, so the body stays a black box inside the frame.

**Where:** `.tool-frame .tool-output`.

**Depends on:** none.

🚫 The 2026-10-27 removal of `#000000` / `#ffffff` is rejected. Put them back.

```css
.tool-frame .tool-output,
.tool-frame .tool-output text {
  font-family: monospace;
  font-size: 0.9em;
  background-color: #000000;
  color: #ffffff;
}
```

## ✔️ Issue 6 — sending frame on a tool reply

- 🔷 A tool result already appears in the transcript. The next outbound frame was still titled `Sending message` and its body was that tool result.
- 🔷 Show that frame only for the send that ends on the user message.

### Based on

- ✔️ `ChatCompletions.send` paints `Sending message` whenever `this.agent` is set and the body is non-empty. A list longer than two messages uses the last message as that body.
- ✔️ `toolsReply` appends the assistant turn and the tool results, then calls `send` again. The last message on that list has role `tool`.
- ✔️ The user send ends with role `user` (`PendingMessage.run`, `Agent.Base.send_async`).

### `libollmchat/Call/ChatCompletions.vala` — `send`: frame only for a user send

**Why:** The tool result is already on screen. The frame is for the outbound text of the user send.

**Where:** `send`, the `if (this.agent != null)` that builds the frame.

**Depends on:** none.

#### Remove

```vala
			if (this.agent != null) {
```

#### Replace with

```vala
			/* Tool replies are already in the transcript. Frame is the user send. */
			if (this.agent != null &&
					this.messages.get(this.messages.size - 1).role == "user") {
```

## Attempts / changelog

- ✔️ 2026-10-27 — applied the three hunks in `ollmfilesd/Application.vala`, `liboctools/Bash/Request.vala`, and `liboctools/ReadFile/Request.vala`.
- 🚫 2026-10-27 — field initializer `bash_lease = new Gee.HashMap<int, Request>()` does not work. The `Request()` creation method is still gone.
- ✔️ 2026-10-27 — `arm_bash_listener` creates `bash_lease` on first use, then `set`.
- ✔️ 2026-10-27 — issue 4: client calls `Codebase.rpc_search`. `RequestBase.execute` adds the domain and code when the wire message is empty.
- ✔️ 2026-10-27 — issue 5: `ToolOutput` uses `oc-frame` and `oc-frame-info`. The body starts with the full command, the output margin is 4 pixels, and the open height is 200.
- 🚫 2026-10-27 — removing the black shell was wrong. The user requires white text on a black output.
- ✔️ 2026-10-28 — `.tool-output` is `#000000` with `#ffffff` text again.
- ✔️ 2026-10-28 — issue 6: `Sending message` is emitted only when the last outbound message has role `user`.

## Next

- ✅ Issues 2 and 3. Do not revisit.
- 🔷 ⏳ Rebuild the chat app and run one `codebase_search` plus one `bash` command. The file daemon already registers `rpc_search`, so it does not need a restart for issue 4.
- ℹ️ Restarting the file daemon while this chat stays open is a separate failure: `docs/bugs/2026-10-27-filesd-restart-drops-client.md`.
- ℹ️ The same prompt at 08:43 and 08:58 died in the UI as `Unexpected error: Exception has been thrown` before any tool call. The debug log has no matching line. That is a separate failure.

## Logs

- ℹ️ Session `~/.local/share/ollmchat/history/2026/10/27/09-07-18.json`.
- ℹ️ `~/.cache/ollmchat/ollmchat.debug.log` and `~/.cache/ollmchat/ollmfilesd.debug.log`, 09:08:07–09:08:40.
- ℹ️ One `File.changed.check` line in the daemon log asserts `mtime_on_disk: self != NULL`. That is the same second and is not one of these tool failures.

### App log

```text
09:08:07.392457 Message.vala:455: tool_calls array elements=2
09:08:07.405597 Base.vala:217: Executing tool 'bash' (id='w0Sfi5emfmQMaI2uMFHh1UZvFDKAt4IZ')
09:08:07.405990 Client.vala:666: id=63 method=Sandbox-Bubble.can_wrap
09:08:07.407829 Client.vala:1235: replied id=63
09:08:07.410930 Client.vala:666: id=64 method=Sandbox-Bubble.rpc_create
09:08:07.412698 Client.vala:1235: replied id=64
09:08:07.412783 Client.vala:666: id=65 method=RPC-Live-Subscribe.rpc_signal
09:08:07.414115 Client.vala:1228: replied id=65 error=
09:08:07.414155 Client.vala:821: RPC-Live-Subscribe.rpc_signal id=65:
09:08:07.417345 Base.vala:247: Tool 'bash' returned error result: ERROR:
09:08:07.418917 Base.vala:217: Executing tool 'read' (id='uFhgtDHFpKjGb7Pvpc6NVjCnqcpVJAdV')
09:08:07.419400 Client.vala:666: id=66 method=File.fetch
09:08:07.421204 Client.vala:1235: replied id=66
09:08:07.430300 Client.vala:666: id=67 method=File.exists
09:08:07.431904 Client.vala:1235: replied id=67
09:08:07.432016 Client.vala:666: id=68 method=File.read
09:08:07.433793 Client.vala:1235: replied id=68
09:08:07.445468 RequestBase.vala:217: Tool 'read' threw error: Invalid line range: start_line must be >= 1
09:08:07.445552 Base.vala:247: Tool 'read' returned error result: ERROR: Invalid line range: start_line must be >= 1

09:08:12.572367 Base.vala:217: Executing tool 'bash' (id='JQ2tm7EFHy09EI5dVxQbsEWZ3nuOaCNy')
09:08:12.572480 Client.vala:666: id=69 method=Sandbox-Bubble.can_wrap
09:08:12.574329 Client.vala:1235: replied id=69
09:08:12.577548 Client.vala:666: id=70 method=Sandbox-Bubble.rpc_create
09:08:12.579161 Client.vala:1235: replied id=70
09:08:12.579427 Client.vala:666: id=71 method=RPC-Live-Subscribe.rpc_signal
09:08:12.580819 Client.vala:1228: replied id=71 error=
09:08:12.580861 Client.vala:821: RPC-Live-Subscribe.rpc_signal id=71:
09:08:12.583261 Base.vala:247: Tool 'bash' returned error result: ERROR:

09:08:24.804759 Base.vala:217: Executing tool 'bash' (id='xbHEHnxFVGvuuIyB1CsIYDjbNPmLs4pD')
09:08:24.804957 Client.vala:666: id=72 method=Sandbox-Bubble.can_wrap
09:08:24.807149 Client.vala:1235: replied id=72
09:08:24.811239 Client.vala:666: id=73 method=Sandbox-Bubble.rpc_create
09:08:24.813057 Client.vala:1235: replied id=73
09:08:24.813170 Client.vala:666: id=74 method=RPC-Live-Subscribe.rpc_signal
09:08:24.814526 Client.vala:1228: replied id=74 error=
09:08:24.814574 Client.vala:821: RPC-Live-Subscribe.rpc_signal id=74:
09:08:24.815871 Base.vala:247: Tool 'bash' returned error result: ERROR:

09:08:31.783350 Base.vala:217: Executing tool 'bash' (id='r8rtiu8mttQXLbuGQNQy2MyLIcCdiQEd')
09:08:31.783503 Client.vala:666: id=75 method=Sandbox-Bubble.can_wrap
09:08:31.785716 Client.vala:1235: replied id=75
09:08:31.789072 Client.vala:666: id=76 method=Sandbox-Bubble.rpc_create
09:08:31.790510 Client.vala:1235: replied id=76
09:08:31.790680 Client.vala:666: id=77 method=RPC-Live-Subscribe.rpc_signal
09:08:31.791578 Client.vala:1228: replied id=77 error=
09:08:31.791640 Client.vala:821: RPC-Live-Subscribe.rpc_signal id=77:
09:08:31.793163 Base.vala:247: Tool 'bash' returned error result: ERROR:

09:08:38.307025 Base.vala:217: Executing tool 'bash' (id='b66vEIUe0pGtNUq6Iq5eHP52IHEJGmsx')
09:08:38.307136 Client.vala:666: id=78 method=Sandbox-Bubble.can_wrap
09:08:38.308856 Client.vala:1235: replied id=78
09:08:38.313522 Client.vala:666: id=79 method=Sandbox-Bubble.rpc_create
09:08:38.315274 Client.vala:1235: replied id=79
09:08:38.315366 Client.vala:666: id=80 method=RPC-Live-Subscribe.rpc_signal
09:08:38.316261 Client.vala:1228: replied id=80 error=
09:08:38.316309 Client.vala:821: RPC-Live-Subscribe.rpc_signal id=80:
09:08:38.317423 Base.vala:247: Tool 'bash' returned error result: ERROR:
09:08:40.853653 Session.vala:569: Stopping running
```

Commands, from the session:

```text
bash  ls -la /home/alan/gitlive/OLLMchat/examples/oc-test-source-diff/
read  file_path=/home/alan/gitlive/OLLMchat/examples/oc-test-source-diff/FileConnectionAdd.vala
bash  ls -la /home/alan/gitlive/OLLMchat/examples/oc-test-source-diff/
bash  find /home/alan/gitlive/OLLMchat/examples/oc-test-source-diff/ -type f
bash  pwd && ls -la examples/oc-test-source-diff/
bash  pwd
```

### File daemon log

```text
09:08:07.249336 Connection.vala:351: recv id=62 method=File.changed.check
09:08:07.249528 CRITICAL oll_mfilesd_file_base_mtime_on_disk: assertion 'self != NULL' failed
09:08:07.406310 Connection.vala:351: recv id=63 method=Sandbox-Bubble.can_wrap
09:08:07.411349 Connection.vala:351: recv id=64 method=Sandbox-Bubble.rpc_create
09:08:07.413164 Connection.vala:351: recv id=65 method=RPC-Live-Subscribe.rpc_signal
09:08:07.413275 Request.vala:447: RPC dispatch: no handler for 'RPC-Live-Subscribe' (RPC-Live-Subscribe.rpc_signal)
09:08:07.420072 Connection.vala:351: recv id=66 method=File.fetch
09:08:07.430983 Connection.vala:351: recv id=67 method=File.exists
09:08:07.432631 Connection.vala:351: recv id=68 method=File.read
09:08:12.572823 Connection.vala:351: recv id=69 method=Sandbox-Bubble.can_wrap
09:08:12.578174 Connection.vala:351: recv id=70 method=Sandbox-Bubble.rpc_create
09:08:12.579986 Connection.vala:351: recv id=71 method=RPC-Live-Subscribe.rpc_signal
09:08:12.580069 Request.vala:447: RPC dispatch: no handler for 'RPC-Live-Subscribe' (RPC-Live-Subscribe.rpc_signal)
09:08:24.805558 Connection.vala:351: recv id=72 method=Sandbox-Bubble.can_wrap
09:08:24.812064 Connection.vala:351: recv id=73 method=Sandbox-Bubble.rpc_create
09:08:24.813833 Connection.vala:351: recv id=74 method=RPC-Live-Subscribe.rpc_signal
09:08:24.813941 Request.vala:447: RPC dispatch: no handler for 'RPC-Live-Subscribe' (RPC-Live-Subscribe.rpc_signal)
09:08:31.783989 Connection.vala:351: recv id=75 method=Sandbox-Bubble.can_wrap
09:08:31.789513 Connection.vala:351: recv id=76 method=Sandbox-Bubble.rpc_create
09:08:31.791120 Connection.vala:351: recv id=77 method=RPC-Live-Subscribe.rpc_signal
09:08:31.791214 Request.vala:447: RPC dispatch: no handler for 'RPC-Live-Subscribe' (RPC-Live-Subscribe.rpc_signal)
09:08:38.307442 Connection.vala:351: recv id=78 method=Sandbox-Bubble.can_wrap
09:08:38.314207 Connection.vala:351: recv id=79 method=Sandbox-Bubble.rpc_create
09:08:38.315849 Connection.vala:351: recv id=80 method=RPC-Live-Subscribe.rpc_signal
09:08:38.315931 Request.vala:447: RPC dispatch: no handler for 'RPC-Live-Subscribe' (RPC-Live-Subscribe.rpc_signal)
```
