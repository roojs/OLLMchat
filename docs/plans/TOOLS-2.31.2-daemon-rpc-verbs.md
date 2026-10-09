# 2.31.2 — Phase B — daemon RPC verbs

**Status:** ⏳ **proposed** — apply after [`TOOLS-2.31.1`](TOOLS-2.31.1-daemon-job-model.md). FileVerification and the meson link are taken from the parked draft; the handler is new.

> **Do not update** `docs/plans/TOOLS-1.0-summary.md` **for this sub-plan.**

**Parent:** [`TOOLS-2.31`](TOOLS-2.31-URGENT-bash-process-tool.md) — `bash` as a process tool, Phase B

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala follows `docs/coding-standards.md`.

---

## Purpose

- **🔷** Put sandboxed jobs on the daemon wire: create, run, then `kill` / `tail` / `wait` / `send` by **pid**.
- **🔷** A job outlives the connection that started it. Verbs look up [`TOOLS-2.31.1`](TOOLS-2.31.1-daemon-job-model.md) `Bubble.jobs`, not a connection lease.
- **🔷** Live output still uses a lease, so the current client can subscribe to `output` and `finished` before `rpc_run` starts the child.
- **ℹ️** Overlay apply is [`TOOLS-2.31.6`](TOOLS-2.31.6-PARKED-daemon-sandbox-bubble-rpc.md) §2. Apply that file as written. Do not apply the rest of that plan.
- **ℹ️** The tool, the pid-return text, and the session list are Phase C.

---

## Wire

- **🔷** Prefix is `Sandbox-Bubble`.
- **🔷** Create and run stay two calls so the client can subscribe before any `output` is emitted.
- **🔷** After `rpc_run`, the handle for every later call is the **bwrap pid**, not the lease.
- **🔷** `wait` with seconds `< 1` means **60**. It returns early if the job ends or is waiting on stdin.
- **🔷** `send` to a pid that is gone is **not** an RPC error. Reply `msg` = `command has ended`.
- **💩** `kill` / `tail` / `wait` use the same gone-pid reply. Same sentence, not an error code.
- **💩** `rpc_create` takes `keep_stdin` as the last argument. The tool turns it on for a detached job. The daemon does not guess.
- **💩** `rpc_run` replies with the pid once spawn has set it, not with `"ok"`. A command that dies before it has a pid is the error path.
- **ℹ️** `finished` is emitted inside `exec`. The handler must not emit it a second time.

### Calls

- `can_wrap` `""` — `msg` `1` / `0`
- `rpc_create` `sssbSb` — `project_path`, `command`, `working_dir`, `network`, `allow_write`, `keep_stdin` — `retval` lease (`t`)
- `rpc_run` `t` — lease — `retval` pid (`i`)
- `kill` `i` — pid — `msg` `ok` or `command has ended`
- `tail` `i` — pid — `retval` line count (`i`), `msg` last 50 lines
- `wait` `ii` — pid, seconds — `retval` `0` ended / `1` waiting / `2` still running, `msg` last 50 lines
- `send` `is` — pid, text — `msg` `ok` or `command has ended`

### Streaming

- **🔷** Between `rpc_create` and `rpc_run` the client subscribes with `RPC-Live-Subscribe.rpc_signal` on the lease: `output`, `finished`.
- **🔷** `live_handles = true` on the listeners that accept real clients.
- **ℹ️** The phone is **not** `TcpListen`. It is `SslConnection`. The parked plan never turned leases on there, so subscribe would `GLib.error` on the only path Android uses.
- **💩** Set `live_handles = true` on each new `SslConnection`, and on `TcpListen` / `SocketListen` for the desktop and the T3 harness.

---

## Phase B code

Edits are **Remove** / **Replace with** / **Add** against the tree. Verify surrounding context before applying. `ollmfilesd` is not in the `docs/meson.build` valadoc inputs, so new daemon files need no valadoc entry. `libocbwrap/Bubble.vala` already is.

### 1. `ollmfilesd/meson.build` — link `ocbwrap`

**Why:** The daemon does not link `libocbwrap` today. Same hunk as the parked §1, written against the current file.

**Where:** `ollmfilesd_deps`, `ollmfilesd_src`, `build_rpath`, `include_directories`, and `vala_args`.

**Depends on:** none.

#### Remove

```meson
  ocvector2_vapi_dep,
]
```

#### Replace with

```meson
  ocvector2_vapi_dep,
  ocbwrap_vapi_dep,
]
```

#### Remove

```meson
  'SQT/VectorMetadata.vala',
  'Daemon.vala',
```

#### Replace with

```meson
  'SQT/VectorMetadata.vala',
  'FileVerification.vala',
  'Sandbox/Bubble.vala',
  'Daemon.vala',
```

#### Remove

```meson
  meson.current_build_dir() / '..' / 'libocvector2',
])
```

#### Replace with

```meson
  meson.current_build_dir() / '..' / 'libocvector2',
  meson.current_build_dir() / '..' / 'libocbwrap',
])
```

#### Remove

```meson
    include_directories('../libocvector2'),
  ],
```

#### Replace with

```meson
    include_directories('../libocvector2'),
    include_directories('../libocbwrap'),
  ],
```

#### Remove

```meson
    '--pkg=ocvector2',
    '--pkg=libsoup-3.0',
```

#### Replace with

```meson
    '--pkg=ocvector2',
    '--pkg=ocbwrap',
    '--pkg=libsoup-3.0',
```

#### Remove

```meson
    '--vapidir', meson.current_build_dir() / '..' / 'libocvector2',
```

#### Replace with

```meson
    '--vapidir', meson.current_build_dir() / '..' / 'libocvector2',
    '--vapidir', meson.current_build_dir() / '..' / 'libocbwrap',
```

### 2. `ollmfilesd/FileVerification.vala` — apply overlay writes

**Why:** `OLLMbwrap.Scan` needs a real apply hook on the daemon. `NoOpFileVerification` discards writes.

**Where:** New file.

**Depends on:** §1.

- **ℹ️** Apply [`TOOLS-2.31.6`](TOOLS-2.31.6-PARKED-daemon-sandbox-bubble-rpc.md) §2 **as written**. That fence is the file. Do not apply §3–§5 of that plan.

### 3. `libocbwrap/Bubble.vala` — `output_lines` and `last_lines` for `tail`

**Why:** `tail` has to read the ring buffer. Both are private today.

**Where:** the `output_lines` field, and a property beside `finished`.

**Depends on:** [`TOOLS-2.31.1`](TOOLS-2.31.1-daemon-job-model.md).

- **💩** `output_lines` becomes a public property so the count can travel on the wire. The increment in `read_from_channel` stays as it is.
- **💩** `last_lines` is a public read of `tail`. No new method.

#### Remove

```vala
		private int output_lines = 0;
```

#### Replace with

```vala
		public int output_lines { get; private set; default = 0; }
```

#### Add — immediately after the `finished` signal

```vala
		/**
		 * Last 50 output lines. What ''tail'' returns.
		 */
		public string[] last_lines {
			owned get {
				return this.tail;
			}
		}
```

- **ℹ️** The Windows stub needs the same two members, returning `0` and `{}`.

### 4. `ollmfilesd/Sandbox/Bubble.vala` — `Sandbox-Bubble` handlers

**Why:** The parked handler keyed verbs on a connection lease. A phone that drops would lose the job. Phase A already has the pid map; the verbs use that.

**Where:** New file, new `ollmfilesd/Sandbox/` directory.

**Depends on:** §1, §2, §3, and [`TOOLS-2.31.1`](TOOLS-2.31.1-daemon-job-model.md).

- **ℹ️** `run` and `wait_run` are the FFI splits. The entry points cannot `yield`. Both names are part of this plan.
- **ℹ️** `rpc_create` does no `yield`, so it stays a plain handler.
- **💩** `rpc_run` starts `exec` with `.begin` and replies once `pid != 0`. It does not wait for the command to finish.
- **💩** `wait_run` polls every 5 seconds, the interval the parent already chose for watching a detached job.

#### Add

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMfilesd.Sandbox
{
	/**
	 * Server ''Sandbox-Bubble.*'' handlers.
	 *
	 * {@link OLLMbwrap.Bubble} owns the spawn, overlay, and job table.
	 * This class is RPC glue: it builds a bubble, leases it so the
	 * caller can subscribe, then looks later calls up by pid.
	 *
	 * == Example ==
	 *
	 * {{{
	 * OLLMfilesd.Sandbox.Bubble.rpc_register();
	 * OLLMrpc.Request.register("Sandbox-Bubble",
	 *     new OLLMfilesd.Sandbox.Bubble(project_manager));
	 * //   Sandbox-Bubble.rpc_create -> lease
	 * //   RPC-Live-Subscribe.rpc_signal lease "output"
	 * //   RPC-Live-Subscribe.rpc_signal lease "finished"
	 * //   Sandbox-Bubble.rpc_run lease -> pid
	 * //   Sandbox-Bubble.wait pid 60
	 * //   Sandbox-Bubble.send pid "yes\n"
	 * //   Sandbox-Bubble.kill pid
	 * }}}
	 */
	public class Bubble : GLib.Object
	{
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"Sandbox-Bubble", typeof(Bubble),
				"can_wrap", "",
				"rpc_create", "sssbSb",
				"rpc_run", "t",
				"kill", "i",
				"tail", "i",
				"wait", "ii",
				"send", "is"
			);
		}

		public ProjectManager manager { get; construct; }

		public Bubble(ProjectManager manager)
		{
			GLib.Object(manager: manager);
		}

		/**
		 * ''Sandbox-Bubble.can_wrap'' — whether bubblewrap is usable
		 * on this host.
		 *
		 * @param request inbound RPC
		 */
		public void can_wrap(OLLMrpc.Request request)
		{
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				msg = OLLMbwrap.Bubble.can_wrap() ? "1" : "0"
			});
		}

		/**
		 * ''Sandbox-Bubble.rpc_create'' — lease a sandbox. Does not
		 * start it.
		 *
		 * @param request inbound RPC
		 * @param project_path project root, or empty for no-project
		 * @param command ''sh -c'' shell string
		 * @param working_dir absolute path, or empty
		 * @param network true leaves the network namespace shared
		 * @param allow_write ''no'' / ''project'' / absolute roots
		 * @param keep_stdin true holds a stdin pipe for {@link send}
		 */
		public void rpc_create(
			OLLMrpc.Request request,
			string project_path, string command, string working_dir,
			bool network, string[] allow_write, bool keep_stdin
		) {
			if (command == "") {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INVALID_PARAMS,
						"Command cannot be empty"
					)
				});
				return;
			}
			if (!OLLMbwrap.Bubble.can_wrap()) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						"sandbox unavailable"
					)
				});
				return;
			}
			var project = this.manager.project_root(project_path);
			if (project_path != "" && project == null) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					msg = "project not found"
				});
				return;
			}
			var bubble = new OLLMbwrap.Bubble(
				new FileVerification(project, this.manager)) {
				project_path = project_path,
				allow_network = network,
				write_tokens = allow_write,
				command = command,
				working_dir = working_dir,
				keep_stdin = keep_stdin
			};
			if (project != null) {
				bubble.write_roots.set(project.path, project.path);
			}
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				retval = OLLMrpc.val("t", request.connection.export(bubble))
			});
		}

		/**
		 * ''Sandbox-Bubble.rpc_run'' — start the leased command.
		 *
		 * Replies with the bwrap pid once spawn has set it.
		 *
		 * @param request inbound RPC
		 * @param handle lease from {@link rpc_create}
		 */
		public void rpc_run(OLLMrpc.Request request, uint64 handle)
		{
			this.run.begin(request, (obj, res) => {
				this.run.end(res);
			});
		}

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

		/**
		 * ''Sandbox-Bubble.kill'' — stop a job we started.
		 *
		 * @param request inbound RPC
		 * @param pid bwrap pid from {@link rpc_run}
		 */
		public void kill(OLLMrpc.Request request, int pid)
		{
			if (OLLMbwrap.Bubble.jobs == null || !OLLMbwrap.Bubble.jobs.has_key(pid)) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					msg = "command has ended"
				});
				return;
			}
			OLLMbwrap.Bubble.jobs.get(pid).stop();
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				msg = "ok"
			});
		}

		/**
		 * ''Sandbox-Bubble.tail'' — last 50 lines of a job we started.
		 *
		 * @param request inbound RPC
		 * @param pid bwrap pid from {@link rpc_run}
		 */
		public void tail(OLLMrpc.Request request, int pid)
		{
			if (OLLMbwrap.Bubble.jobs == null || !OLLMbwrap.Bubble.jobs.has_key(pid)) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					msg = "command has ended"
				});
				return;
			}
			var bubble = OLLMbwrap.Bubble.jobs.get(pid);
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				retval = OLLMrpc.val("i", bubble.output_lines),
				msg = string.joinv("\n", bubble.last_lines)
			});
		}

		/**
		 * ''Sandbox-Bubble.wait'' — wait on a job we started.
		 *
		 * Seconds below 1 means 60. Returns early when the job ends
		 * or is waiting on stdin.
		 *
		 * @param request inbound RPC
		 * @param pid bwrap pid from {@link rpc_run}
		 * @param seconds how long to wait
		 */
		public void wait(OLLMrpc.Request request, int pid, int seconds)
		{
			this.wait_run.begin(request, (obj, res) => {
				this.wait_run.end(res);
			});
		}

		/**
		 * Poll the job every 5 seconds until it ends, waits on stdin,
		 * or the wait expires.
		 *
		 * @param request inbound RPC
		 */
		private async void wait_run(OLLMrpc.Request request)
		{
			var pid = (int) request.args.get(0).get_int();
			var seconds = (int) request.args.get(1).get_int();
			var left = seconds < 1 ? 60 : seconds;
			while (left > 0) {
				if (OLLMbwrap.Bubble.jobs == null || !OLLMbwrap.Bubble.jobs.has_key(pid)) {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						retval = OLLMrpc.val("i", 0),
						msg = "command has ended"
					});
					return;
				}
				var bubble = OLLMbwrap.Bubble.jobs.get(pid);
				if (bubble.waiting_stdin()) {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						retval = OLLMrpc.val("i", 1),
						msg = string.joinv("\n", bubble.last_lines)
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
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					retval = OLLMrpc.val("i", 0),
					msg = "command has ended"
				});
				return;
			}
			var still = OLLMbwrap.Bubble.jobs.get(pid);
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				retval = OLLMrpc.val("i", 2),
				msg = string.joinv("\n", still.last_lines)
			});
		}

		/**
		 * ''Sandbox-Bubble.send'' — write to a job we started.
		 *
		 * Nothing is appended. The caller sends its own newline.
		 *
		 * @param request inbound RPC
		 * @param pid bwrap pid from {@link rpc_run}
		 * @param text bytes to write, verbatim
		 */
		public void send(OLLMrpc.Request request, int pid, string text)
		{
			if (OLLMbwrap.Bubble.jobs == null || !OLLMbwrap.Bubble.jobs.has_key(pid)) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					msg = "command has ended"
				});
				return;
			}
			try {
				OLLMbwrap.Bubble.jobs.get(pid).send(text);
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					msg = "command has ended"
				});
				return;
			}
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				msg = "ok"
			});
		}
	}
}
```

### 5. `ollmfilesd/Application.vala` — register `Sandbox-Bubble`, enable `live_handles`

**Why:** `add_class` fills the method table; `register` binds the handler. `live_handles` is what makes the lease usable.

**Where:** The `rpc_register()` run, the `OLLMrpc.Request.register(...)` block, and both listener constructions.

**Depends on:** §4.

#### Remove

```vala
			SQT.VectorMetadata.rpc_register();
			Codebase.rpc_register();
```

#### Replace with

```vala
			SQT.VectorMetadata.rpc_register();
			Codebase.rpc_register();
			Sandbox.Bubble.rpc_register();
```

#### Remove

```vala
			OLLMrpc.Request.register("Codebase",  new Codebase(this.project_manager, this.config));
```

#### Replace with

```vala
			OLLMrpc.Request.register("Codebase",  new Codebase(this.project_manager, this.config));
			OLLMrpc.Request.register("Sandbox-Bubble",
				new Sandbox.Bubble(this.project_manager));
```

#### Remove

```vala
				this.listen = new OLLMrpc.Transport.TcpListen(
					opt_tcp_host,
					(uint16) opt_tcp_port
				);
```

#### Replace with

```vala
				this.listen = new OLLMrpc.Transport.TcpListen(
					opt_tcp_host,
					(uint16) opt_tcp_port
				) {
					live_handles = true
				};
```

#### Remove

```vala
				this.listen = new OLLMrpc.Transport.SocketListen(
					this.socket_path
				);
```

#### Replace with

```vala
				this.listen = new OLLMrpc.Transport.SocketListen(
					this.socket_path
				) {
					live_handles = true
				};
```

### 6. `ollmfilesd/SslListen.vala` — `live_handles` on the phone path

**Why:** Android reaches the daemon over TLS. `SslConnection` is a `Transport.Connection`. Subscribe dies unless that connection has `live_handles`.

**Where:** the `new SslConnection` initializer inside `listen()`.

**Depends on:** §4.

#### Remove

```vala
					var rpc = new SslConnection(conn, this.app) {
						io = tls,
						cert_fingerprint = fingerprint
					};
```

#### Replace with

```vala
					var rpc = new SslConnection(conn, this.app) {
						io = tls,
						cert_fingerprint = fingerprint,
						live_handles = true
					};
```

---

## Testing Phase B

- **🔷** `⏳` Drive `Sandbox-Bubble.*` over a real socket before any tool change. Model the test on `tests/rpc/subscribe-test.vala`.
- **💩** `⏳` One-shot: `can_wrap` → `rpc_create` → subscribe `output` / `finished` → `rpc_run` returns a non-zero pid → `finished` arrives → `tail` / `send` / `kill` on that pid reply `command has ended`.
- **💩** `⏳` Detached: `keep_stdin = true`, `cat`, `rpc_run` returns a pid, `wait` returns `1` and is waiting, `send` `"hi\n"` produces `output`, `wait` returns `1` again, `kill` then `finished`.
- **💩** `⏳` `wait` with `0` seconds uses 60. A `sleep 2` with `wait 2` returns `0` ended.
- **💩** `⏳` A pid that was never ours — `kill` / `tail` / `wait` / `send` all reply `command has ended`, and no host process is signalled.
- **💩** `⏳` Drop the client after `rpc_run`. The job is still in `Bubble.jobs`. A new connection can `kill` it by pid.
- **💩** `⏳` Overlay: a command that writes a project file still lands through §2.

---

## LLM notes

- **🚫** Applying the parked handler in [`TOOLS-2.31.6`](TOOLS-2.31.6-PARKED-daemon-sandbox-bubble-rpc.md) §4. Its verbs key on a lease. That dies with the phone.
- **🚫** Emitting `finished` from the handler. `exec` already does.
- **🚫** A timer inside `exec`. Detach and `wait` sit above it.
- **🚫** Helper methods beyond `run` and `wait_run`.
- **🚫** HTTPS. The phone is TLS TCP.
