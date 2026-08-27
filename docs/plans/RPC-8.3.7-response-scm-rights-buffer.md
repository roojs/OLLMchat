# 8.3.7 — `Response` + `SCM_RIGHTS` buffer

> **`docs/plans/RPC-1.0-summary.md` is not updated** for this sub-plan until it is done and archived.

**Status:** **PROPOSED** — agent implemented **✔️** (user has not confirmed)

**Parent:** [`RPC-8.3-libocrpc-live-handles-and-signals.md`](done/RPC-8.3-libocrpc-live-handles-and-signals.md)

**Depends on:** [`8.3.4`](done/RPC-8.3.4-DONE-scm-rights-fds.md) (`Live.Buffer` / `BufferStream` / `Connection.write(…, buffer)`)

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

**Consumer:** gnome-shell-rpc Priority **D** `WindowActor.paint_to_content` (fd paint reply on a sync call). Plan lives in that repo under `docs/plans/0.5.5-remaining-meta-stub-gaps.md` / `0.5.3-partial-clutter.md`.

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

---

## Purpose

- **🔷** `✔️` Pair an fd with a successful **`Response`**, same fd-first then bin order as **`Notification`** today.
- **🔷** `✔️` Server: `Request.reply` / `Connection.reply` can pass an optional `Live.Buffer` into `Connection.write`.
- **🔷** `✔️` Client: on `Response` dispatch, `take_pending()` into `Response.buffer` (receive-side only; not on the wire).
- **ℹ️** [`8.3.4`](done/RPC-8.3.4-DONE-scm-rights-fds.md) already built the `.fd` channel and `Notification.buffer`. This cut only opens the same path for **call replies**.
- **ℹ️** Why now: gnome-shell-rpc needs `paint_to_content` to return pixels/dmabuf on the **matching** sync `Client.call` result. A side `Notification` with an fd forces correlating ids and races the promise completion.

---

## Why not stay on Notification-only

- **🔷** Sync Meta/Clutter overrides use `Client.call` → `Response`. The caller already waits on that id.
- **💩** Workarounds (notify-then-reply, stash by request id) work but duplicate the correlation `Response.id` already gives.
- **🔷** `Connection.write(obj, buffer)` already accepts any `Bin.Serializable`. `reply()` just never forwards a buffer today.

---

## Today

- **ℹ️** `Connection.write(gobject, Live.Buffer? buffer = null)` — fd then bin when `buffer_stream` is set.
- **ℹ️** `Connection.reply(request, response)` calls `write(response)` with **no** buffer.
- **ℹ️** `Request.reply(response)` has no buffer argument.
- **ℹ️** `Client.dispatch_message`: `BufferStream.attach(notif)` only on `Notification`.
- **ℹ️** `Response` has no `buffer` property.
- **ℹ️** 8.3.4 smoke is `tests/rpc/scm-notification-test.vala` — socketpair + `Connection.write(Notification, Buffer)` + `parse` + `attach`. It does not use `Request.reply` or `Client.call`.

---

## Phase 1 — receive-side `Response.buffer`

- **🔷** `✔️` Same shape as `Notification.buffer`: filled by the client; omitted on encode/decode.

### 1. `libocrpc/Response.vala` — property + skip on wire

**Why.** Client reads `response.buffer.fd` after `call` returns.

**Where.** After `msg_encode`; start of `bin_write_prop` / `bin_read_prop` switches.

**Depends on.** none.

##### Part 1 — property

#### Add — after `public int msg_encode { get; set; default = 0; }`

Receive-side fd handle. Same shape as `Notification.buffer`.

```vala
		/** Filled by client {@link Live.BufferStream.take_pending}; null on send. */
		public Live.Buffer? buffer { get; internal set; default = null; }
```

##### Part 2 — `bin_write_prop` skip

#### Remove

```vala
			switch (prop.name) {
				case "result":
```

#### Replace with — insert `"buffer"` before `"result"`

Skip encode. `buffer` is client-only.

```vala
			switch (prop.name) {
				case "buffer":
					return;
				case "result":
```

##### Part 3 — `bin_read_prop` skip

#### Remove

```vala
			switch (prop.name) {
				case "result":
```

#### Replace with — insert `"buffer"` before `"result"`

Skip decode. Same as write.

```vala
			switch (prop.name) {
				case "buffer":
					return;
				case "result":
```

---

## Phase 2 — server reply forwards buffer

- **🔷** `✔️` Optional buffer on existing `reply` methods (default `null`). No new Helpers.

### 2. `libocrpc/Transport/Connection.vala` — `reply`

**Why.** Helpers that already hold a dmabuf/memfd must pass it with the `Response`.

**Where.** `reply` (the method immediately above `reply_error`).

**Depends on.** Phase 1.

#### Remove

```vala
		public void reply(OLLMrpc.Request request, OLLMrpc.Response response)
		{
			response.id = request.id;
			this.write(response);
		}
```

#### Replace with — forward optional buffer into `write`

```vala
		public void reply(OLLMrpc.Request request, OLLMrpc.Response response, Live.Buffer? buffer = null)
		{
			response.id = request.id;
			this.write(response, buffer);
		}
```

### 3. `libocrpc/Request.vala` — `reply`

**Why.** Helpers call `request.reply(...)`, not `connection.reply` directly.

**Where.** `reply` at end of class.

**Depends on.** §2.

#### Remove

```vala
		/**
		 * Relay a {@link Response} to {@link connection} (sets wire id).
		 */
		public void reply(Response response)
		{
			this.connection.reply(this, response);
		}
```

#### Replace with — optional buffer, pass through to `Connection.reply`

```vala
		/**
		 * Relay a {@link Response} to {@link connection} (sets wire id).
		 *
		 * Optional {@link Live.Buffer} uses the ''.fd'' channel first
		 * (same order as {@link Transport.Connection.write}).
		 *
		 * @param response envelope to send
		 * @param buffer fd payload, or null for bin only
		 */
		public void reply(Response response, Live.Buffer? buffer = null)
		{
			this.connection.reply(this, response, buffer);
		}
```

---

## Phase 3 — client attach on `Response`

- **🔷** `✔️` FIFO `take_pending` when a `Response` completes a pending call.
- **ℹ️** Inline at the dispatch site (same body as `BufferStream.attach` for notifications).

### 4. `libocrpc/Client.vala` — `dispatch_message` Response branch

**Why.** Fd may already be queued before the bin `Response` arrives; pop it with the matching reply.

**Where.** Inside `if (response != null)`, after the `if (!found) { GLib.error(...); }` block, before `if (response.error != null)`.

**Depends on.** Phase 1; `buffer_stream` from 8.3.4.

#### Add — after the `if (!found) { GLib.error(...); }` block

Pop the next queued fd onto this reply. Same `buffer_stream != null` guard as the `Notification` branch.

```vala
				if (this.buffer_stream != null) {
					response.buffer = this.buffer_stream.take_pending();
				}
```

---

## Phase 4 — Windows / Android stub

- **🔷** `✔️` Stub `BufferStream` must expose `take_pending` because `Client.vala` calls it on every platform.

### 5. `libocrpc/Live/namespace.vala` — stub `take_pending`

**Why.** Client dispatch calls `take_pending` on every platform that compiles `Client.vala`.

**Where.** `#if G_OS_WIN32 || ANDROID` `BufferStream` class, after `public void attach(Notification notif) {}`.

**Depends on.** none (needed before Phase 3 on Win32/Android; Unix `BufferStream.vala` already has `take_pending`).

#### Add — after `public void attach(Notification notif) {}`

Return null. Unix implementation lives in `Live/BufferStream.vala`.

```vala
		public Buffer? take_pending() { return null; }
```

---

## Phase 5 — smoke

- **🔷** `✔️` New `tests/rpc/scm-response-test.vala`: registered sync method calls `request.reply(response, buffer)`; `Client.call` with `live_handles` sees `response.buffer.fd >= 0` and can read the pipe byte.
- **ℹ️** Not an edit of `scm-notification-test.vala`. That file stays Notification-only.
- **ℹ️** `SocketListen` / `Client` only open the `.fd` channel when `live_handles` is true (`gi-test.vala` pattern). Without that flag Phase 3 never runs.
- **ℹ️** 8.3.4 smoke calls `receive_one()` itself after parse. This smoke uses real watches + `dispatch_message`. `write_with` sends fd then bin; if this test flakes, the fd watch lost the race with bin parse — stop and ask, do not add a drain in dispatch unless review says so.

### 6. `tests/rpc/scm-response-test.vala` — create file

**Why.** Prove `Request.reply(..., buffer)` + `Client.call` + `Response.buffer` together.

**Where.** New file next to `tests/rpc/scm-notification-test.vala`.

**Depends on.** Phases 1–3.

#### Add — create `tests/rpc/scm-response-test.vala`

Dummy `RPC-Daemon.hello` / `RPC-Daemon.paint`. `paint` replies with a pipe fd. Listen + client set `live_handles = true`.

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * SCM_RIGHTS Response smoke — types here are NOT shipped in libocrpc.
 */

namespace RpcDummy
{
	public class Paint : GLib.Object
	{
		public int send_fd = -1;

		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"RPC-Daemon", typeof(Paint),
				"hello", "",
				"paint", ""
			);
		}

		public void hello(OLLMrpc.Request request)
		{
			request.reply(new OLLMrpc.Response());
		}

		public void paint(OLLMrpc.Request request)
		{
			request.reply(
				new OLLMrpc.Response(),
				new OLLMrpc.Live.Buffer(this.send_fd)
			);
		}
	}
}

namespace OLLMrpcTests
{
	class TestRpcScmResponse : RpcTestAppBase
	{
		public TestRpcScmResponse()
		{
			base("com.roojs.ollmchat.test-rpc-scm-response");
		}

		protected override string get_app_name()
		{
			return "test-rpc-scm-response";
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

			var dummy = new RpcDummy.Paint();
			dummy.send_fd = pipe_fds[0];
			RpcDummy.Paint.rpc_register();
			OLLMrpc.Request.register("RPC-Daemon", dummy);

			var dir = GLib.DirUtils.make_tmp("ocrpc-scm-response-XXXXXX");
			var sock = GLib.Path.build_filename(dir, "rpc.sock");
			var listen = new OLLMrpc.Transport.SocketListen(sock) {
				live_handles = true
			};
			this.check(command_line, listen.start(), "listen start failed");
			var rpc = new OLLMrpc.Client("", "", sock) {
				live_handles = true
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
			var call_loop = new GLib.MainLoop();
			rpc.call.begin(new OLLMrpc.Request() {
				method = "RPC-Daemon.paint"
			}, (obj, res) => {
				try {
					response = rpc.call.end(res);
				} catch (GLib.Error e) {
					this.check(command_line, false, e.message);
				}
				call_loop.quit();
			});
			call_loop.run();
			this.check(command_line, response.error == null, "paint returned error");
			this.check(
				command_line,
				response.buffer != null && response.buffer.fd >= 0,
				"missing buffer fd"
			);
			uint8 read_byte = 0;
			if (Posix.read(response.buffer.fd, &read_byte, 1) != 1) {
				this.fail(command_line, "read fd failed");
			}
			this.check(command_line, read_byte == payload, "fd payload mismatch");
			rpc.disconnect();
			listen.stop();
		}
	}
}

int main(string[] args)
{
	return new OLLMrpcTests.TestRpcScmResponse().run(args);
}
```

### 7. `tests/meson.build` — `test-rpc-scm-response`

**Why.** Build and run the new smoke next to the 8.3.4 Notification test.

**Where.** Immediately after the `test('test-rpc-scm-notification', …)` block (before `test('test-rpc-t1', …)`).

**Depends on.** §6.

#### Add — after `test('test-rpc-scm-notification', …)`

Same deps as `test-rpc-scm-notification` (posix + gio-unix). `values-test` / `gi-test` also need `export_dynamic` for `Request.add_class` dispatch.

```meson
test_rpc_scm_response = executable('test-rpc-scm-response',
  'rpc/scm-response-test.vala',
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
test('test-rpc-scm-response',
  test_rpc_scm_response,
  suite: 'rpc',
  timeout: 10,
)
```

---

## Suggested order

1. **🔷** `✔️` Phase 1 — `Response.buffer`
2. **🔷** `✔️` Phase 2 — `Connection.reply` / `Request.reply`
3. **🔷** `✔️` Phase 4 — stub `take_pending` (before Client compiles on Win32/Android)
4. **🔷** `✔️` Phase 3 — `Client` attach
5. **🔷** `✔️` Phase 5 — `scm-response-test.vala` + meson
6. **ℹ️** gnome-shell-rpc then wires `Helper` paint → `request.reply(resp, buffer)` (out of this repo)

---

## LLM notes

- **🚫** Do not change Notification fd behaviour.
- **🚫** Do not put fd numbers or pixel blobs in bin `args` / `msg`.
- **🚫** Do not edit gnome-shell-rpc from this plan; only libocrpc (+ its test).
- **🚫** Do not add `BufferStream.attach_response` — `take_pending` at the `Response` dispatch site.
- **🚫** Do not edit `tests/rpc/scm-notification-test.vala`.
- **🚫** Do not add a `receive_one` drain in `dispatch_message` unless the smoke flakes and review asks.
- **🔷** Default `buffer = null` keeps every existing `reply` call site valid.
