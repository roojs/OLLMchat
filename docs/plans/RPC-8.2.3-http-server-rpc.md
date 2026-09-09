# 8.2.3 — HTTP server RPC (JSON → stream → bin → TLS / certs)

**Status:** **PROPOSED** — Phase 1 `✔️` agent; Phases 2–6 stubs

> **Do not update `docs/plans/RPC-1.0-summary.md` for this plan.**

**Parent:** [`RPC-8.2-full-rpc-system.md`](RPC-8.2-full-rpc-system.md) — Phase 3 HTTP server hook + Phase 6/7 session/TLS track for HTTP

**Builds on:** [`RPC-8.2.1-libocrpc-auto-json-and-http-client.md`](RPC-8.2.1-libocrpc-auto-json-and-http-client.md) (`Bin.Json` AUTO + HTTP **client**), [`done/8.2.2-DONE-proper-bin-json-streaming.md`](done/8.2.2-DONE-proper-bin-json-streaming.md)

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Purpose

- **🔷** HTTP **server** in `libocrpc` that speaks the same `Request` / `Response` pipeline as socket RPC.
- **🔷** Phase 1 — plain HTTP + **auto JSON** body; dummy **Hello World** RPC round-trip.
- **🔷** Streaming JSON / bin+session — **split out**:
  - [`RPC-8.2.3.1-http-json-streaming.md`](RPC-8.2.3.1-http-json-streaming.md)
  - [`RPC-8.2.3.2-http-bin-session.md`](RPC-8.2.3.2-http-bin-session.md)
- **🔷** Later — HTTPS; application auth; **client certificate** registration.
- **ℹ️** Parent Phase 3 client HTTP (Hub GET) is already largely done in **8.2.1**; this plan is the **server** side (and later bin/TLS on that path).
- **ℹ️** Parent Phase 5 called out SSE/chunked vs bin notifications for chat — this plan owns the HTTP JSON streaming half.

---

## Suggested order

1. Phase 1 — HTTP JSON server + Hello World (unary) — `✔️` agent
2. [`RPC-8.2.3.1-http-json-streaming.md`](RPC-8.2.3.1-http-json-streaming.md) — streaming JSON
3. [`RPC-8.2.3.3-http-path-type-registration.md`](RPC-8.2.3.3-http-path-type-registration.md) — path ↔ request/response types — `✔️`
4. [`RPC-8.2.3.2-http-bin-session.md`](RPC-8.2.3.2-http-bin-session.md) — bin over HTTP + session id
5. Phase 4 — HTTPS
6. Phase 5 — Application authentication
7. Phase 6 — Issued client certificate after auth

---

## Current behaviour

- **ℹ️** Daemon listen is `Transport.SocketListen` / `TcpListen` → persistent `Connection` + bin byte stream.
- **ℹ️** `Request.dispatch()` requires `request.connection`; `reply()` → `Connection.write()`.
- **ℹ️** `OLLMrpc.Client` HTTP mode is **outbound** Hub-style GET + JSON decode — not a server, not POST RPC.
- **ℹ️** No `Soup.Server` usage in-tree today.
- **ℹ️** Process detach / double-fork lives in **`ollmfilesd`** (`Application.daemonize`), **not** in `libocrpc` listen/server types.

### Concurrency / process model (library vs app)

- **🔷** `libocrpc` owns **bind + accept + per-request decode/dispatch/encode** on the **GLib main loop** — same pattern as `SocketListen` / `TcpListen` today (`SocketService` / Soup sources).
- **🔷** **Fork / daemonize / systemd / supervisor** is the **application’s** job (`ollmfilesd` already double-forks; an HTTP daemon would do the same or run foreground under a service manager).
- **🔷** Phase 1 handlers run **inline on the Soup callback** (sync), one request at a time on the main loop. Same constraint as socket `Connection.on_input_ready` today.
- **🔷** Streaming (Phase 2) still **main-loop only** — chunk writes from idle / async completions on that loop; no worker threads for tokens.
- **🔷** **No threading / worker-MPM model** in this plan (Apache-style prefork/worker/event left out). Threaded request handling would force every RPC handler and shared daemon state to be concurrent-safe — far too much confusion for the gain.
- **🚫** Library does **not** fork per request, spawn a thread per connection, or offer a pluggable “connection MPM”.
- **🚫** Do not add a thread pool, `GLib.Thread` workers, or “async reply on another thread” behind HTTP in this plan.

---

## Phase 1 — HTTP JSON server + Hello World

### Goal

- **🔷** `✔️` `Soup.Server` wrapper under `OLLMrpc.Transport`.
- **🔷** `✔️` One POST accepts a JSON `Request` body (auto JSON, no `*type`).
- **🔷** `✔️` Decode → `Request.dispatch()` → `Response` → auto JSON HTTP body.
- **🔷** `✔️` Dummy method (Hello World) registered via existing `Request.register` / `add_class`.
- **🔷** `✔️` Smoke test: POST JSON in, JSON out with greeting.

### Design

- **🔷** Roles (so names do not confuse):
  - **`HttpServer`** — binds port, accepts POSTs.
  - **`HttpReply`** — **server-side** write target for **one** inbound POST. Subclasses `Connection` only so `Request.reply()` → `connection.write()` still works. **Not** the RPC `Response` object (that is the JSON body); **not** the HTTP client.
  - **`Request` / `Response`** — RPC wire envelopes.
  - **`Soup.ServerMessage`** — Soup’s HTTP message; `HttpReply.write` fills its response body.
  - **`OLLMrpc.Client`** — real HTTP client (elsewhere).
- **🔷** New `HttpServer` : `Listen` — owns `Soup.Server`, `start()` / `stop()`.
- **🔷** New `HttpReply` : `Connection` — one per HTTP request (Phase 1 sessionless).
  - Overrides `write()` to encode with `Bin.Json` AUTO into the Soup response body.
  - No socket `IOChannel` read loop.
- **🔷** Method string lives in the JSON body (`"method":"RPC-Hello.world"`), same as socket RPC — not derived from the URL path in Phase 1.
- **🔷** HTTP transport failures (`400`/`405`/`500`) use a helpful **plain-text** body; the client keys off the **HTTP status**. RPC-level faults after a successful decode still use a JSON `Response` with `error.message`.
- **💩** `⏳` POST path **`/rpc`** only (reject other paths / non-POST with HTTP 404 / 405).
- **💩** `⏳` Default bind **`127.0.0.1`** via `Soup.Server.listen_local(port, …)`.
- **💩** `⏳` Default port **`8080`** (construct props; override in tests).
- **💩** `⏳` HTTP status mapping: `405` wrong method, `400` bad JSON / not a Request, `500` encode failure; RPC `METHOD_NOT_FOUND` still goes out as JSON `Response.error` (HTTP `200` or `404` — pick one when implementing; body must carry the message either way).
- **🚫** Streaming JSON — **[`8.2.3.1`](RPC-8.2.3.1-http-json-streaming.md)** (not in Phase 1 unary Hello World).
- **🚫** Extending `OLLMrpc.Client` for POST-to-our-server — Phase 1 smoke uses `Soup.Session` (or curl) in the test; dedicated client POST mode can follow.
- **🚫** Sessions, bin Content-Type — **[`8.2.3.2`](RPC-8.2.3.2-http-bin-session.md)**; TLS, auth — Phases 4–6.

### Wire (Phase 1)

Request body (auto JSON):

```json
{"id":1,"method":"RPC-Hello.world","args":[]}
```

Response body (auto JSON) — success carries greeting on `msg`:

```json
{"id":1,"msg":"Hello World"}
```

### Pipeline (per POST)

1. Read `Soup.ServerMessage` request body → `Json.Parser` → object root.
2. `Bin.Json(Mode.AUTO).json_to_bin(obj, mem_bin, typeof(Request))` → `parse()` → `Request`.
3. `var reply = new HttpReply(msg);` · `request.connection = reply;`
4. `request.dispatch()` (or `reply.write(Response{error…})` on miss) — handler calls `request.reply(Response)`.
5. `HttpReply.write` → `from_gobject` → `msg.set_response("application/json", …)` · status `200` (or overwrite to `400`/`405`/`500` after write on transport failures).
6. Transport failures always `write` a `Response` with a concrete `error.message` before setting the non-200 status.

### Code proposals

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `libocrpc/Transport/HttpReply.vala` — new file

**Why:** `Request.reply` needs a `Connection`. Socket `Connection.write` goes to a peer stream; HTTP must JSON-encode into this POST’s Soup message. `HttpReply` is that write target — not the `Response` envelope.

**Where:** new file under `libocrpc/Transport/`.

**Depends on:** none.

#### Add — new file `libocrpc/Transport/HttpReply.vala`

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMrpc.Transport
{
	/**
	 * Server-side write target for one HTTP POST.
	 *
	 * Subclasses {@link Connection} so {@link OLLMrpc.Request.reply}
	 * can call {@link write}. The RPC payload is still an
	 * {@link OLLMrpc.Response} (or {@link Notification}); this type only
	 * holds the {@link Soup.ServerMessage} and encodes JSON into it.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var reply = new OLLMrpc.Transport.HttpReply(msg);
	 * request.connection = reply;
	 * request.dispatch();
	 * }}}
	 */
	public class HttpReply : Connection
	{
		public Soup.ServerMessage msg { get; construct; }

		private Bin.Json json = new Bin.Json(Bin.Mode.AUTO);

		public HttpReply(Soup.ServerMessage msg)
		{
			GLib.Object(msg: msg);
		}

		public override void start()
		{
		}

		public override void write(
			GLib.Object gobject,
			Live.Buffer? buffer = null
		)
		{
			var serializable = gobject as Bin.Serializable;
			if (serializable == null) {
				GLib.warning("http write: not bin Serializable");
				this.msg.set_response("text/plain; charset=utf-8", Soup.MemoryUse.COPY,
					"http write: not bin Serializable".data);
				this.msg.set_status(500, null);
				return;
			}
			try {
				this.msg.set_response("application/json; charset=utf-8", Soup.MemoryUse.COPY,
					global::Json.to_string(this.json.from_gobject(serializable), false).data);
				this.msg.set_status(200, null);
			} catch (GLib.Error e) {
				GLib.warning("http write error: %s", e.message);
				this.msg.set_response("text/plain; charset=utf-8", Soup.MemoryUse.COPY,
					("encode failed: " + e.message).data);
				this.msg.set_status(500, null);
			}
		}
	}
}
```

---

### 2. `libocrpc/Transport/HttpServer.vala` — new file

**Why:** HTTP RPC entry that owns `Soup.Server`; POST `/rpc`, decode JSON `Request`, dispatch on `HttpReply`.

**Where:** new file under `libocrpc/Transport/`.

**Depends on:** §1.

#### Add — new file `libocrpc/Transport/HttpServer.vala`

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMrpc.Transport
{
	/**
	 * HTTP JSON RPC server ({@link Soup.Server}).
	 *
	 * Phase 1: POST ''/rpc'' with auto-JSON {@link OLLMrpc.Request} body;
	 * reply is auto-JSON {@link OLLMrpc.Response}. Same
	 * {@link OLLMrpc.Request.dispatch} path as socket RPC. Runs on the
	 * process main loop — no fork or thread pool inside the library.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var http = new OLLMrpc.Transport.HttpServer(8080);
	 * http.start();
	 * }}}
	 */
	public class HttpServer : Listen
	{
		public uint port { get; construct; default = 8080; }

		private Soup.Server soup = new Soup.Server("server-header", null);
		private bool listening = false;
		private Bin.Json json = new Bin.Json(Bin.Mode.AUTO);

		public HttpServer(uint port = 8080)
		{
			GLib.Object(port: port);
		}

		public override bool start()
		{
			if (this.listening) {
				return true;
			}
			this.soup.add_handler("/rpc", this.on_rpc);
			try {
				this.soup.listen_local(this.port, 0);
			} catch (GLib.Error e) {
				GLib.warning(
					"failed to start HTTP server on port %u: %s",
					this.port,
					e.message
				);
				return false;
			}
			this.listening = true;
			return true;
		}

		public override void stop()
		{
			if (!this.listening) {
				return;
			}
			this.listening = false;
			this.soup.disconnect();
			this.soup = new Soup.Server("server-header", null);
		}

		private void on_rpc(
			Soup.Server server,
			Soup.ServerMessage msg,
			string path,
			GLib.HashTable<string, string>? query
		)
		{
			var reply = new HttpReply(msg) {
				live_handles = this.live_handles
			};
			if (msg.get_method() != "POST") {
				reply.write(new Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
						"POST required, got %s".printf(msg.get_method())
					)
				});
				msg.set_status(405, null);
				return;
			}
			var bytes = msg.get_request_body().flatten();
			var parser = new Json.Parser();
			try {
				parser.load_from_data((string) bytes.get_data(), (ssize_t) bytes.get_size());
			} catch (GLib.Error e) {
				reply.write(new Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.PARSE_ERROR,
						"invalid JSON: %s".printf(e.message)
					)
				});
				msg.set_status(400, null);
				return;
			}
			var root = parser.get_root();
			if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
				reply.write(new Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
						"JSON root must be an object"
					)
				});
				msg.set_status(400, null);
				return;
			}
			var mem = new GLib.MemoryOutputStream.resizable();
			var encode_ctx = new Bin.Stream(null, new GLib.DataOutputStream(mem));
			try {
				this.json.json_to_bin(root.get_object(), encode_ctx, typeof(Request));
				encode_ctx.out_stream.close();
			} catch (GLib.Error e) {
				reply.write(new Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
						"request decode failed: %s".printf(e.message)
					)
				});
				msg.set_status(400, null);
				return;
			}
			var read_ctx = new Bin.Stream(
				new GLib.DataInputStream(
					new GLib.MemoryInputStream.from_bytes(mem.steal_as_bytes())
				),
				null
			);
			read_ctx.mode = this.json.mode;
			OLLMrpc.Request? request = null;
			try {
				request = read_ctx.parse() as OLLMrpc.Request;
			} catch (GLib.Error e) {
				reply.write(new Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
						"request parse failed: %s".printf(e.message)
					)
				});
				msg.set_status(400, null);
				return;
			}
			if (request == null) {
				reply.write(new Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
						"body did not decode to a Request"
					)
				});
				msg.set_status(400, null);
				return;
			}
			request.connection = reply;
			if (!request.dispatch()) {
				var err = OLLMrpc.RpcErrorCode.to_error(
					(int) OLLMrpc.RpcErrorCode.METHOD_NOT_FOUND
				);
				err.message = "no handler for '%s'".printf(request.method);
				reply.write(new Response() {
					id = request.id,
					error = err
				});
			}
		}
	}
}
```

---

### 3. `libocrpc/meson.build` — compile `HttpServer` / `HttpReply`

**Why:** ship the new transport sources with `libocrpc`.

**Where:** `ocrpc_core_src` list after `Transport/TcpListen.vala`.

**Depends on:** §1–§2.

#### Add — after `'Transport/TcpListen.vala',`:

```meson
  'Transport/HttpReply.vala',
  'Transport/HttpServer.vala',
```

---

### 4. `tests/rpc/http-server-test.vala` — Hello World smoke

**Why:** prove POST JSON → dispatch → JSON reply without a daemon socket.

**Where:** new test beside other `tests/rpc/*-test.vala`; wire into the existing rpc test meson target the same way as `values-test` / `proxies-test` (implementer matches current `tests/rpc` meson pattern).

**Depends on:** §1–§3.

#### Add — new file `tests/rpc/http-server-test.vala` (dummy + test)

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * HTTP JSON RPC smoke — types here are NOT shipped in libocrpc.
 */

namespace RpcDummy
{
	public class Hello : GLib.Object
	{
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"RPC-Hello", typeof(Hello),
				"world", ""
			);
		}

		public void world(OLLMrpc.Request request)
		{
			request.reply(new OLLMrpc.Response() {
				msg = "Hello World"
			});
		}
	}
}

namespace OLLMrpcTests
{
	class TestRpcHttpServer : RpcTestAppBase
	{
		public TestRpcHttpServer()
		{
			base("com.roojs.ollmchat.test-rpc-http-server");
		}

		protected override string get_app_name()
		{
			return "test-rpc-http-server";
		}

		protected override void run_rpc_test(ApplicationCommandLine command_line) throws Error
		{
			OLLMrpc.Request.rpc_register();
			OLLMrpc.Response.rpc_register();
			RpcDummy.Hello.rpc_register();
			OLLMrpc.Request.register("RPC-Hello", new RpcDummy.Hello());

			var http = new OLLMrpc.Transport.HttpServer(0);
			this.check(command_line, http.start(), "http server start");

			var session = new Soup.Session();
			var message = new Soup.Message(
				"POST",
				"http://127.0.0.1:%u/rpc".printf(http.port)
			);
			var body = "{\"id\":1,\"method\":\"RPC-Hello.world\",\"args\":[]}";
			message.set_request_body_from_bytes(
				"application/json",
				new GLib.Bytes(body.data)
			);
			var bytes = session.send_and_read(message);
			this.check(
				command_line,
				message.status_code == 200,
				"http status %u".printf(message.status_code)
			);
			var text = (string) bytes.get_data();
			this.check(
				command_line,
				text.contains("Hello World"),
				"body missing Hello World: %s".printf(text)
			);
			http.stop();
		}
	}
}
```

- **💩** `⏳` Port `0` — confirm `Soup.Server.listen_local(0, …)` yields an ephemeral port readable from `http.port` (or from `soup.get_uris()`). If not, bind a fixed high port in the test and document it.
- **💩** `⏳` Meson: add executable + `test()` entry next to the other `tests/rpc` targets (same deps as `proxies-test`).

---

### Phase 1 backlog

- **🔷** `✔️` §1–§4 land and `meson test` for the HTTP smoke passes.
- **💩** `✔️` Docblob / Transport namespace overview mentions HTTP server.
- **💩** `⏳` Optional curl one-liner in LLM notes only (not a shipped script).

**Implementation notes (agent):**

- **✔️** `Bin.Mode.AUTO` (not `Bin.Json.Mode`).
- **✔️** Ephemeral port `0` → `HttpServer.port` updated from `soup.get_uris()` after `listen_local`.
- **✔️** Smoke test uses `send_and_read_async` + `MainLoop` (sync client blocks Soup on the same thread).
- **✔️** Files: `libocrpc/Transport/HttpReply.vala`, `HttpServer.vala`, `tests/rpc/http-server-test.vala`.

---

## Phase 2 — Streaming JSON → [`RPC-8.2.3.1`](RPC-8.2.3.1-http-json-streaming.md)

- **ℹ️** Split out — NDJSON proposals live in that plan (not duplicated here).

---

## Phase 3 — Bin + session → [`RPC-8.2.3.2`](RPC-8.2.3.2-http-bin-session.md)

- **ℹ️** Split out — session table + bin Content-Type live in that plan.

---

## Phase 4 — HTTPS

### Goal

- **🔷** `⏳` TLS on `Soup.Server` (server certificate).
- **🔷** `⏳` Client talks `https://` to the same RPC paths.

### Notes

- **💩** `⏳` Auto-generated vs configured server cert — fill with Phase 6 cert story.
- **⏳** Code proposals — later.

---

## Phase 5 — Application authentication

### Goal

- **🔷** `⏳` First-time (or unknown-cert) clients must pass an RPC auth step before privileged methods.
- **🔷** `⏳` Auth method surface (`Auth.*` or `Daemon.register_client`) — exact API in a later fill-in.

### Notes

- **ℹ️** Parent Phase 7: mTLS alone is **not** first-time trust.
- **⏳** Code proposals — later.

---

## Phase 6 — Client certificate registration

### Goal

- **🔷** `⏳` After successful auth, server **issues / registers a client certificate** and returns it to the client.
- **🔷** `⏳` Later connections present that cert; server maps cert → session identity (with or without repeating full auth).

### Flow (from parent Phase 7)

1. Client → TLS (server cert only).
2. Client → RPC auth.
3. Server → issue client cert.
4. Client reconnects with client cert → recognized.

### Notes

- **⏳** Code proposals — later.
- **💩** `⏳` Cert storage under `~/.local/share/ollmchat/` (or configurable) — confirm when filling.

---

## LLM notes

- **ℹ️** Numbered **8.2.3** — next open slot after **8.2.2**; parent sub-plan list updated to match.
- **ℹ️** Phase 1 deliberately does **not** change Hub-oriented `Client.send_http` (GET + query).
- **🚫** Do not implement Phases 2–6 until Phase 1 is user-confirmed and those sections have code proposals (Phase 2 needs a framing pick: NDJSON vs SSE).
- **🚫** Do not add helper methods beyond the named types/methods in Phase 1 fences.
- **🚫** No Apache-style MPM / thread pool — handlers stay main-loop serial; see **Concurrency / process model**.
