# `call_poll` / `Request` cannot send `Live.Buffer` (client→server)

**Status:** ✔️ FIXED — §1–5 applied; `test-rpc-scm-request-call-poll` passes; full `--suite rpc` 21/21 green 2026-09-17  
**Hit:** 2026-09-17 — gnome-shell-rpc D2.2 `St.ImageContent.set_data`  
**Component:** `libocrpc` / `OLLMrpc.Client` write path + `Request` + server `Connection.on_input_ready`  
**Consumer gate:** `gnome-shell-rpc/tests/call-sync-repro/request-buffer-gate` — **FAIL** 2026-09-17  
**Related (other direction, done):** [`done/2026-09-14-FIXED-call-poll-live-buffer-fd-lost.md`](done/2026-09-14-FIXED-call-poll-live-buffer-fd-lost.md)  
**Landed sibling:** [`RPC-8.3.7-DONE-response-scm-rights-buffer.md`](../plans/done/RPC-8.3.7-DONE-response-scm-rights-buffer.md) — **Response** only

**Process:** Follow **`docs/bug-fix-process.md`** — propose → approve → apply. Do not land from the gnome-shell-rpc tree.

---

## Problem

🔷 `Live.Buffer` + `SCM_RIGHTS` on the **`.fd`** channel already works **server → client** on a **`Response`**: `request.reply(response, new Live.Buffer(fd))` → client `response.buffer`.

🔷 There is **no** matching path for **client → server** on a **`Request`**. `Request` has no `buffer` field. Every client write of a Request is bin-only:

```vala
this.bin.write(entry.request);
```

(`Client.call_poll` ~969, `send_head` ~596, `call_sync` pending flush ~829.)

🔷 Server `Connection.on_input_ready` parses a Request and `dispatch()`s. It never `take_pending()` / attach an inbound fd.

🔷 Consumer cannot upload pixmap bytes (`St.ImageContent.set_data`) without stuffing `"ay"` on the bin envelope (rejected: size, copies, Variant ownership). Need memfd + `Live.Buffer` **on the call**, same fd-first order as reply.

**Expected:** client attaches a memfd to the Request; server handler sees `request.buffer` (or equivalent) before dispatch.

**Actual:** no API. Gate handler always sees `saw_buffer=false`.

---

## Evidence

### Consumer (gnome-shell-rpc) — 2026-09-17

```bash
meson compile -C build request-buffer-gate
timeout 5 ./build/tests/call-sync-repro/request-buffer-gate
```

```
server: listening /tmp/gsr-request-buffer-gate-186174438.sock
server eat_fd nbytes=5 saw_buffer=false
request-buffer-gate eat_fd ok=false
FAIL request-buffer-gate: call_poll cannot send Live.Buffer with Request (ImageContent.set_data). OPC: outbound Request buffer + server attach before dispatch.
```

`live_handles` is on; `client.buffer_stream != null`. The call still cannot attach an fd. The gate does not invent a `Request.buffer` setter — that type is in libocrpc.

### Library code

`Response.buffer` is receive-side only (`internal set`, filled by `take_pending` on the **client**). `Request.reply(..., buffer)` is the **server send** path via `Connection.write` → `BufferStream.write_with`.

Client send of Request never calls `write_with`. Server recv of Request never attaches.

`tests/rpc/scm-response-call-poll-test.vala` covers **reply** fd. Nothing covers **request** fd.

---

## Root cause

✔️ RPC-8.3.7 scoped SCM on **Response** (and Notification). Outbound **Request** was never added.

This is not the 2026-09-14 `call_poll` drain bug. That fix made the **client** drain `.fd` when a **Response** arrives during `call_poll`. Here the client never **sends** an fd, and the server never **reads** one on Request.

---

## Proposed fix (library)

💩 Same contract as reply: fd on `.fd` **first**, then bin object. Reuse `BufferStream.write_with` / `take_pending`. No `"ay"` pixmap on bin. No MainContext pump.

**🚫** HTTP/JSON body as the fd.  
**🚫** Consumer packing pixels as Variant / `ay`.  
**🚫** Iterating default MainContext from `call_poll` to “make it work.”

### 1. `libocrpc/Request.vala` — `Request.buffer` property + bin skip

**Why:** `Response.buffer` is the receive slot on the client. Request needs a slot the **client sets** on send and the **server fills** on recv. Public get/set (unlike Response `internal set`) so stubs can assign before `call_poll`.

**Where:** class body — after the `connection` property (the `/** Set by the server before {@link dispatch}. */` block).

**Depends on:** none.

#### Add — after the `connection` property declaration
```vala
	/**
	 * Live fd payload, or null for bin only.
	 *
	 * Client sets before {@link Client.call} / {@link Client.call_poll};
	 * server fills via {@link Live.BufferStream.take_pending} before
	 * {@link dispatch}. Never serialized on the bin socket — the fd
	 * travels the ''.fd'' channel first, same order as
	 * {@link Response.buffer}.
	 */
	public Live.Buffer? buffer { get; set; default = null; }
```

### 1a. `libocrpc/Request.vala` — `bin_write_prop`: skip `buffer` on encode

**Why:** `Live.Buffer` is a GObject; the default `bin_default_write_prop` would serialize it as a nested object. `Response` already skips `buffer` — mirror that.

**Where:** `bin_write_prop` — the `switch (prop.name)` opening cases.

**Depends on:** §1 (property exists before its writer is touched).

#### Remove
```vala
		public override void bin_write_prop(
			Bin.Stream ctx,
			GLib.ParamSpec prop
		) throws GLib.Error
		{
			switch (prop.name) {
				case "connection":
				case "result-type":
					return;
```

#### Replace with
```vala
		public override void bin_write_prop(
			Bin.Stream ctx,
			GLib.ParamSpec prop
		) throws GLib.Error
		{
			switch (prop.name) {
				case "buffer":
				case "connection":
				case "result-type":
					return;
```

### 1b. `libocrpc/Request.vala` — `bin_read_prop`: skip `buffer` on decode

**Why:** same as §1a — the reader must not try to decode a `buffer` tag (none is sent on the bin socket).

**Where:** `bin_read_prop` — the `switch (prop.name)` opening cases.

**Depends on:** §1.

#### Remove
```vala
		public override void bin_read_prop(
			Bin.Stream ctx,
			GLib.ParamSpec prop,
			uint8 type_byte
		) throws GLib.Error
		{
			switch (prop.name) {
				case "connection":
				case "result-type":
					return;
```

#### Replace with
```vala
		public override void bin_read_prop(
			Bin.Stream ctx,
			GLib.ParamSpec prop,
			uint8 type_byte
		) throws GLib.Error
		{
			switch (prop.name) {
				case "buffer":
				case "connection":
				case "result-type":
					return;
```

### 2. `libocrpc/Client.vala` — client Request write paths: `write_with`

**Why:** all three client Request sends are `this.bin.write(request)` only. When `buffer_stream != null`, send the fd on the `.fd` channel first via `BufferStream.write_with` (same contract as the reply path), else keep the bin-only write + flush.

**Where:** three methods — `send_head`, `call_sync` pending-flush loop, `call_poll` send block.

**Depends on:** §1 (`Request.buffer` exists before any send reads it).

### 2a. `libocrpc/Client.vala` — `send_head`: fd-first send

**Where:** `send_head`, the `try {` block after the HTTP early-return (~596).

**Depends on:** §1.

#### Remove
```vala
			GLib.debug("id=%d method=%s", head.request.id, head.request.method);
			this.bin.write(head.request);
			yield this.output.flush_async(GLib.Priority.DEFAULT, null);
			head.sent = true;
```

#### Replace with
```vala
			GLib.debug("id=%d method=%s", head.request.id, head.request.method);
			if (this.buffer_stream != null) {
				this.buffer_stream.write_with(head.request.buffer,
					head.request, this.bin);
			} else {
				this.bin.write(head.request);
				yield this.output.flush_async(GLib.Priority.DEFAULT, null);
			}
			head.sent = true;
```

### 2b. `libocrpc/Client.vala` — `call_sync` pending flush: fd-first send

**Where:** `call_sync`, the `while (entry.done_response == null)` flush loop (~829).

**Depends on:** §1.

#### Remove
```vala
						this.sending = true;
						GLib.debug("id=%d method=%s", p.request.id, p.request.method);
						this.bin.write(p.request);
						this.output.flush(null);
						p.sent = true;
						this.sending = false;
```

#### Replace with
```vala
						this.sending = true;
						GLib.debug("id=%d method=%s", p.request.id, p.request.method);
						if (this.buffer_stream != null) {
							this.buffer_stream.write_with(p.request.buffer,
								p.request, this.bin);
						} else {
							this.bin.write(p.request);
							this.output.flush(null);
						}
						p.sent = true;
						this.sending = false;
```

### 2c. `libocrpc/Client.vala` — `call_poll` send: fd-first send

**Where:** `call_poll`, the `try {` send block after `this.poll_depth++` (~969).

**Depends on:** §1.

#### Remove
```vala
			this.sending = true;
			GLib.debug("id=%d method=%s", entry.request.id, entry.request.method);
			this.bin.write(entry.request);
			this.output.flush(null);
			entry.sent = true;
			this.sending = false;
```

#### Replace with
```vala
			this.sending = true;
			GLib.debug("id=%d method=%s", entry.request.id, entry.request.method);
			if (this.buffer_stream != null) {
				this.buffer_stream.write_with(entry.request.buffer,
					entry.request, this.bin);
			} else {
				this.bin.write(entry.request);
				this.output.flush(null);
			}
			entry.sent = true;
			this.sending = false;
```

`BufferStream.write_with` already flushes `bin.out_stream`, so the explicit `flush`/`flush_async` is skipped on the `write_with` branch (the socket is the same stream; a second flush would be a no-op).

### 3. `libocrpc/Live/BufferStream.vala` — `read_fd()`: non-blocking fd receive helper

**Why:** the inbound-fd receive loop (poll(0) + `receive_one` until empty) is needed in server `on_input_ready` and already exists inline in client `dispatch_message`. `BufferStream` owns the socket and `receive_one`, so it is the natural home; extracting it as `read_fd` gives one shared implementation so the two copies do not drift. User asked for this extraction and the `read_fd` name.

**Where:** `BufferStream` class body — new public method, placed after `receive_one` (before `start_watch`).

**Depends on:** none.

#### Add — after `receive_one()`
```vala
	/**
	 * Read currently-readable fds on the ''.fd'' channel into pending.
	 *
	 * Non-blocking: poll(0) + {@link receive_one} until the socket has
	 * no more data. Call before {@link take_pending} on the receive side
	 * (server on_input_ready, client dispatch_message).
	 */
	public void read_fd()
	{
		while (this.socket != null) {
			var buffer_poll = GLib.PollFD();
			buffer_poll.fd = this.socket.get_fd();
			buffer_poll.events = GLib.IOCondition.IN;
			var buffer_fds = new GLib.PollFD[] { buffer_poll };
			if (GLib.poll(buffer_fds, 0) <= 0
				|| (buffer_fds[0].revents & GLib.IOCondition.IN) == 0) {
				break;
			}
			try {
				this.receive_one();
			} catch (GLib.IOError e) {
				if (e.code == GLib.IOError.WOULD_BLOCK) {
					break;
				}
				GLib.warning("buffer stream receive: %s", e.message);
				break;
			} catch (GLib.Error e) {
				GLib.warning("buffer stream receive: %s", e.message);
				break;
			}
		}
	}
```

💩 Follow-up (not this change): client `Client.dispatch_message` has the same inline receive loop (~1082) and could call `this.buffer_stream.read_fd()` instead. Left alone here to avoid a surprise refactor of existing code; file a separate task if you want it consolidated.

### 4. `libocrpc/Transport/Connection.vala` — `on_input_ready`: attach inbound fd before dispatch

**Why:** fd-first means when the Request is readable on the main socket, the `.fd` byte is already in the kernel (same as the reply drain on the client). The server must drain `.fd` and set `request.buffer` before `dispatch()` so the handler sees it.

**Where:** `on_input_ready`, the `do { … } while` parse+dispatch loop — between `request.connection = this;` and `if (!request.dispatch())`.

**Depends on:** §1, §3.

#### Remove
```vala
			request.connection = this;
			if (!request.dispatch()) {
				this.reply_error(
					request,
					(int) OLLMrpc.RpcErrorCode.METHOD_NOT_FOUND
				);
			}
```

#### Replace with
```vala
			request.connection = this;
			if (this.buffer_stream != null) {
				this.buffer_stream.read_fd();
				request.buffer = this.buffer_stream.take_pending();
			}
			if (!request.dispatch()) {
				this.reply_error(request, (int) OLLMrpc.RpcErrorCode.METHOD_NOT_FOUND);
			}
```

`emit_wait_poll` / any parse+dispatch copy in consumers (gnome-shell-rpc `Rpc.Connection.drain_readable`) must do the same after this lands — **consumer follow-up**, not a substitute for the library path.

### 5. `tests/rpc/scm-request-call-poll-test.vala` + `tests/meson.build` — in-tree repro

**Why:** until §1–4 land, no test covers outbound Request fd. Mirror `scm-response-call-poll-test.vala` with the arrow reversed: client sends a pipe fd via `call_poll` with `buffer` set; server `eat_fd` reads `request.buffer.fd` and replies `ok`. Fails to compile before §1–4.

**Where:** new file `tests/rpc/scm-request-call-poll-test.vala` (copy server/connect boilerplate from `scm-response-call-poll-test.vala`); new `test()` block in `tests/meson.build` after the `test-rpc-scm-response-call-poll` entry (~376).

**Depends on:** §1, §2, §3, §4.

#### Add — `tests/rpc/scm-request-call-poll-test.vala`
```vala
/*
 * SCM_RIGHTS Request via Client.call_poll — arrow reversed from
 * scm-response-call-poll-test.vala. Client sends the fd; server
 * handler reads request.buffer.fd. Types here are NOT shipped in libocrpc.
 */

namespace RpcDummy
{
	public class EatPoll : GLib.Object
	{
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"RPC-Daemon", typeof(EatPoll),
				"hello", "",
				"eat_fd", ""
			);
		}

		public void hello(OLLMrpc.Request request)
		{
			request.reply(new OLLMrpc.Response());
		}

		public void eat_fd(OLLMrpc.Request request)
		{
			var got = request.buffer != null ? request.buffer.fd : -1;
			uint8 b = 0;
			var ok = got >= 0 && Posix.read(got, &b, 1) == 1 && b == 0xAB;
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				args = OLLMrpc.args("b", ok),
			});
		}
	}
}

namespace OLLMrpcTests
{
	class TestRpcScmRequestCallPoll : RpcTestAppBase
	{
		public TestRpcScmRequestCallPoll()
		{
			base("com.roojs.ollmchat.test-rpc-scm-request-call-poll");
		}

		protected override string get_app_name()
		{
			return "test-rpc-scm-request-call-poll";
		}

		protected override void run_rpc_test(ApplicationCommandLine command_line) throws Error
		{
			int[] pipe_fds = new int[2];
			if (Posix.pipe(pipe_fds) != 0) {
				this.fail(command_line, "pipe failed");
			}
			uint8 payload = 0xAB;
			if (Posix.write(pipe_fds[1], &payload, 1) != 1) {
				this.fail(command_line, "pipe write failed");
			}

			var dir = GLib.DirUtils.make_tmp("ocrpc-scm-request-call-poll-XXXXXX");
			var sock = GLib.Path.build_filename(dir, "rpc.sock");
			var ready_path = GLib.Path.build_filename(dir, "ready");

			var self_bin = GLib.FileUtils.read_link("/proc/self/exe");
			string[] spawn_args = {
				self_bin,
				"server",
				sock,
				ready_path
			};
			string[] spawn_env = GLib.Environ.get();
			Pid child_pid = 0;
			try {
				GLib.Process.spawn_async(
					null,
					spawn_args,
					spawn_env,
					GLib.SpawnFlags.DO_NOT_REAP_CHILD,
					null,
					out child_pid
				);
			} catch (GLib.Error e) {
				this.fail(command_line, "spawn server: %s".printf(e.message));
			}

			var waited = 0;
			while (!GLib.FileUtils.test(ready_path, GLib.FileTest.EXISTS)) {
				if (waited > 50) {
					Posix.kill(child_pid, Posix.Signal.TERM);
					Posix.waitpid(child_pid, null, 0);
					this.fail(command_line, "server ready timeout");
				}
				GLib.Thread.usleep(100000);
				waited++;
			}

			OLLMrpc.Client? rpc = null;
			try {
				rpc = new OLLMrpc.Client("", "", sock) {
					live_handles = true,
					call_timeout_seconds = 5
				};
				var connected = false;
				var loop = new GLib.MainLoop();
				rpc.connect.begin(new OLLMrpc.Request() {
					method = "RPC-Daemon.hello"
				}, null, (obj, res) => {
					connected = rpc.connect.end(res);
					loop.quit();
				});
				loop.run();
				this.check(command_line, connected, "client connect failed");

				OLLMrpc.Response? response = null;
				try {
					response = rpc.call_poll(new OLLMrpc.Request() {
						method = "RPC-Daemon.eat_fd",
						buffer = new OLLMrpc.Live.Buffer(pipe_fds[0])
					});
				} catch (GLib.Error e) {
					this.fail(command_line, "call_poll eat_fd: %s".printf(e.message));
				}
				this.check(command_line, response.error == null, "eat_fd returned error");
				this.check(command_line, response.args.size > 0, "eat_fd no args");
				this.check(command_line, response.args.get(0).get_boolean(), "fd payload mismatch");
			} finally {
				if (rpc != null) {
					rpc.disconnect();
				}
				Posix.close(pipe_fds[0]);
				Posix.close(pipe_fds[1]);
				Posix.kill(child_pid, Posix.Signal.TERM);
				Posix.waitpid(child_pid, null, 0);
			}
		}
	}
}

int main(string[] args)
{
	if (args.length >= 4 && args[1] == "server") {
		var sock = args[2];
		var ready_path = args[3];
		OLLMrpc.rpc_register(true);
		RpcDummy.EatPoll.rpc_register();
		OLLMrpc.Request.register("RPC-Daemon", new RpcDummy.EatPoll());
		var listen = new OLLMrpc.Transport.SocketListen(sock) {
			live_handles = true
		};
		if (!listen.start()) {
			return 2;
		}
		try {
			GLib.FileUtils.set_contents(ready_path, "1");
		} catch (GLib.Error e) {
			return 3;
		}
		new GLib.MainLoop().run();
		return 0;
	}
	return new OLLMrpcTests.TestRpcScmRequestCallPoll().run(args);
}
```

#### Add — `tests/meson.build` (after the `test-rpc-scm-response-call-poll` block, ~376)
```meson
test_rpc_scm_request_call_poll = executable('test-rpc-scm-request-call-poll',
  'rpc/scm-request-call-poll-test.vala',
  dependencies: rpc_test_deps + [
    rpc_test_app_dep,
    dependency('gio-unix-2.0'),
    meson.get_compiler('vala').find_library('posix'),
  ],
  link_with: rpc_test_link_with,
  build_rpath: rpc_test_build_rpath,
  export_dynamic: true,
  vala_args: rpc_test_vala_args + [
    '--pkg=posix',
  ],
)
test('test-rpc-scm-request-call-poll',
  test_rpc_scm_request_call_poll,
  suite: 'rpc',
  timeout: 15,
)
```

PASS when handler reads `0xAB`. FAIL/`Request` has no `buffer` until §1–4.

---

## Attempts / changelog

- ✔️ Confirmed `Connection.write(gobject, buffer)` + `Request.reply` already send fds **out** of the server.
- ✔️ Confirmed all three client Request writes are `bin.write` only.
- ✔️ Consumer `request-buffer-gate` FAIL 2026-09-17 (`saw_buffer=false`).
- 🚫 Do not fix in gnome-shell-rpc (no field to set; no write_with on Client).

## Next

✔️ **Applied 2026-09-17** — §1–5 landed:
1. `libocrpc/Request.vala` — added `buffer` property + bin skip (§1, §1a, §1b).
2. `libocrpc/Client.vala` — `write_with` on the three send paths (§2a–§2c).
3. `libocrpc/Live/BufferStream.vala` — `read_fd()` helper (§3).
4. `libocrpc/Transport/Connection.vala` — `read_fd()` + `take_pending` before dispatch (§4).
5. `tests/rpc/scm-request-call-poll-test.vala` + `tests/meson.build` — in-tree repro (§5).

✔️ `meson test -C build --suite rpc` → **21/21 OK** (incl. `test-rpc-scm-request-call-poll`).

💩 Follow-up: consolidate the client `dispatch_message` inline receive loop onto `BufferStream.read_fd()` (separate task, not this change).

Then consumer undeny `ImageContent.set_data` + Helper memfd; update `drain_readable`; gate should PASS once it sets `Request.buffer`.
