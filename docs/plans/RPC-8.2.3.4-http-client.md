# 8.2.3.4 — HTTP RPC client (JSON + bin, session + sequence)

**Status:** **PROPOSED** — Phases 0–1 **✔️** agent (`HttpClient` + full `call`); Phase 2 confirm next; Phase 3 smoke not started; user verify → ✅

> **Do not update `docs/plans/RPC-1.0-summary.md` for this plan.**

**Parent:** [`RPC-8.2.3-http-server-rpc.md`](RPC-8.2.3-http-server-rpc.md)

**Depends on:** [`RPC-8.2.3.2-http-bin-session.md`](RPC-8.2.3.2-http-bin-session.md) server bin + `Session` + headers **✔️** agent; HTTP JSON `/rpc` from parent Phase 1

**Related:** [`RPC-8.2.1-libocrpc-auto-json-and-http-client.md`](RPC-8.2.1-libocrpc-auto-json-and-http-client.md) Hub GET on `OLLMrpc.Client` (different role); [`docs/bin-rpc-protocol.md`](../bin-rpc-protocol.md)

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

**Renamed from:** `RPC-8.2.3.4-http-bin-client.md` (same number; client is not bin-only).

---

## Purpose

- **🔷** Library client that POSTs `Request` bodies to our HTTP `/rpc` server.
- **🔷** Support **both** wire forms the server already accepts:
  - JSON (`application/json`)
  - bin (`application/octet-stream`)
- **🔷** Carry **`X-rpc-session`** / **`X-rpc-sequence`** across calls (same wire contract as **8.2.3.2**; applies to JSON and bin on `/rpc`).
- **🔷** Keep a **separate type** — do **not** extend or overload `OLLMrpc.Client`.
- **🔷** Support client-driven **session reset** (send sequence `-1`, fresh local JIT tables when using bin).
- **🔷** Keep main-loop-friendly Soup I/O (async `call`; no thread pool).

---

## Why not `OLLMrpc.Client`

- **ℹ️** `OLLMrpc.Client` HTTP mode is Hub-style **GET** + JSON decode (**8.2.1**).
- **ℹ️** Socket/TCP mode is a persistent channel with pending-id queues and live proxies.
- **🔷** POST to our `/rpc` + session headers is a different lifetime — own type next to `HttpServer`.
- **🚫** Branching more protocols into `OLLMrpc.Client` for this path.
- **🚫** Reusing server `Transport.Session.take` on the client (server table only).

---

## Design

### Type

- **🔷** `OLLMrpc.Transport.HttpClient` — peer to `HttpServer` / `HttpReply`.
- **🔷** Owns:
  - `Soup.Session` soup
  - base URL + `rpc_path` (default `/rpc`)
  - `bin_body` — `false` = JSON, `true` = octet-stream (mirrors server `HttpReply.bin_body`)
  - `session_id` (empty until first response)
  - `sequence` (last value echoed by server; send on next request)
  - client `Bin.Stream` (`is_server = false`) for JIT when `bin_body`
  - `Bin.Json` for JSON encode/decode when `!bin_body`
  - `next_id` for `Request.id`
- **🔷** One logical HTTP RPC session per `HttpClient` instance.
- **🔷** Same `call` / session / reset API for both body modes — only Content-Type and codec change.

### Wire

- **🔷** `POST` `{base}{rpc_path}`.
- **🔷** `bin_body == false` → `Content-Type: application/json`; body = auto-JSON `Request`; expect JSON `Response`.
- **🔷** `bin_body == true` → `Content-Type: application/octet-stream`; body = bin `Request`; expect bin `Response` (match **8.2.3.2**).
- **🔷** Request body to Soup via **`set_request_body(content_type, InputStream, -1)`** — stream the encode, do **not** `MemoryOutputStream` + `set_request_body_from_bytes` for bin.
- **🔷** Bin encode: `Posix.pipe` → write with `DataOutputStream(UnixOutputStream)`; Soup reads `UnixInputStream` (same bridge idea as **8.2.2** `from_gobject` pipe).
- **🔷** JSON encode: `Json.to_string` already yields a full string → `MemoryInputStream.from_data` into `set_request_body` (no extra memory encode stream).
- **🔷** Request headers (both modes): `X-rpc-session` when `session_id != ""`; `X-rpc-sequence` = current `sequence` (or `-1` after `reset`).
- **🔷** First call: omit session header (or empty); sequence `0`.
- **🔷** On `2xx`: read echoed session + sequence; update local state; decode `Response` with the matching codec.
- **🔷** On `409` / other non-2xx: throw `GLib.IOError` with status + body text.
- **🚫** Bin request via `MemoryOutputStream` + `set_request_body_from_bytes`.

### Reset

- **🔷** `reset()` clears local `bin` to a fresh client `Bin.Stream` and arms the next call to send `X-rpc-sequence: -1` (same `session_id`).
- **🔷** After that call succeeds, store echoed sequence (normally `1`) and clear the arm flag.
- **ℹ️** Reset matters most for bin JIT; JSON still sends `-1` so the server session sequence/bin reset stays consistent.
- **ℹ️** If server expired the session (`409`), caller starts a new `HttpClient` or clears `session_id` and calls again without `-1`.

### Named APIs (this plan)

- **🔷** `OLLMrpc.Transport.HttpClient` — construct with base URL string.
- **🔷** `bin_body` — choose JSON vs bin (default JSON).
- **🔷** `call(Request request)` — async; assigns `request.id`; returns `Response`.
- **🔷** `reset()` — next `call` sends sequence `-1` and uses a fresh local bin.
- **💩** `call_sync` — optional later; not in v1.

### Out of scope

- **🚫** NDJSON / streaming responses (**8.2.3.1**).
- **🚫** Live handles / SCM over HTTP.
- **🚫** TLS / client certs (**8.2.3** Phases 4–6).
- **🚫** Extending `OLLMrpc.Client`.
- **🚫** Hub GET / query-string HTTP (stays on `OLLMrpc.Client`).

---

## Suggested implement order

1. **Phase 0** — `HttpClient` type: fields (incl. `bin_body`), ctor, meson + valadoc.
2. **Phase 1** — `call`: shared headers + branch JSON vs bin encode/decode; update session/sequence.
3. **Phase 2** — `reset` + `-1` path (already wired in Phase 0–1).
4. **Phase 3** — smoke: JSON unary; bin two-call JIT + reset; `409`.

---

## Phase 0 — `HttpClient` shell — **✔️** agent

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `libocrpc/Transport/HttpClient.vala` — new file

**Why:** Separate outbound client for HTTP `/rpc` (JSON or bin) + session headers.

**Where:** new file under `libocrpc/Transport/`.

**Depends on:** none (uses Soup + `Bin.Stream` / `Bin.Json` + wire types).

#### Add

New file `libocrpc/Transport/HttpClient.vala` (Phase 0 shell — `call` filled in Phase 1):

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
	 * HTTP RPC client — POST JSON or bin + session headers.
	 *
	 * Peer to {@link HttpServer}. Not {@link OLLMrpc.Client} (that type owns
	 * socket/TCP and Hub GET). One instance keeps ''X-rpc-session'' /
	 * ''X-rpc-sequence'' across {@link call}s. Set {@link bin_body} for
	 * octet-stream (JIT name tables on {@link bin}); leave false for JSON.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var http = new OLLMrpc.Transport.HttpClient("http://127.0.0.1:8080");
	 * var resp = yield http.call(new OLLMrpc.Request() {
	 *     method = "RPC-Hello.world"
	 * });
	 * http.bin_body = true;
	 * var bin_resp = yield http.call(new OLLMrpc.Request() {
	 *     method = "RPC-Hello.world"
	 * });
	 * }}}
	 */
	public class HttpClient : GLib.Object
	{
		/** Base origin (no path), e.g. ''http://127.0.0.1:8080''. */
		public string base_url { get; construct; }

		/** RPC path under {@link base_url}. Default ''/rpc''. */
		public string rpc_path { get; set; default = "/rpc"; }

		/**
		 * True → ''application/octet-stream'' (bin). False → JSON
		 * (default), matching server {@link HttpReply.bin_body}.
		 */
		public bool bin_body { get; set; default = false; }

		/** Last echoed ''X-rpc-session''; empty before first success. */
		public string session_id { get; set; default = ""; }

		/**
		 * Last echoed ''X-rpc-sequence''. Sent on the next {@link call}
		 * unless {@link reset} armed ''-1''.
		 */
		public uint sequence { get; set; default = 0; }

		/**
		 * Client JIT codec (even wire tokens). Used when {@link bin_body}.
		 * I/O streams attached per {@link call}.
		 */
		public Bin.Stream bin {
			get; set; default = new Bin.Stream(null, null, false);
		}

		private Soup.Session soup = new Soup.Session();
		private Bin.Json json = new Bin.Json(Bin.Mode.AUTO);
		private int next_id = 1;
		private bool send_reset = false;

		public HttpClient(string base_url)
		{
			GLib.Object(base_url: base_url);
		}

		/**
		 * Arm sequence ''-1'' on the next {@link call} and replace
		 * {@link bin} with a fresh client stream.
		 */
		public void reset()
		{
			this.bin = new Bin.Stream(null, null, false);
			this.send_reset = true;
		}

		/**
		 * POST one {@link OLLMrpc.Request} (JSON or bin per {@link bin_body}).
		 *
		 * @param request wire request; {@link OLLMrpc.Request.id} set here
		 * @return decoded {@link OLLMrpc.Response}
		 * @throws GLib.Error HTTP non-2xx or encode/parse failure
		 */
		public async Response call(Request request) throws GLib.Error
		{
			request.id = this.next_id++;
			/* Phase 1 fill */
			throw new GLib.IOError.FAILED("HttpClient.call not implemented");
		}
	}
}
```

### 2. `libocrpc/meson.build` + `docs/meson.build` — source lists

**Why:** Compile + valadoc.

#### Add — `ocrpc_core_src` (after `HttpServer.vala`)

```meson
  'Transport/HttpClient.vala',
```

#### Add — `docs/meson.build` valadoc inputs (near other Transport files)

```meson
    '../libocrpc/Transport/HttpClient.vala',
```

---

## Phase 1 — `call` (JSON + bin + session headers) — **✔️** agent

### 3. `libocrpc/Transport/HttpClient.vala` — replace `call` stub

**Why:** One entry point; Content-Type and codec follow `bin_body`.

**Where:** Phase 0 stub method `public async Response call(...)` through its closing brace.

**Depends on:** Phase 0.

#### Remove

```vala
		/**
		 * POST one {@link OLLMrpc.Request} (JSON or bin per {@link bin_body}).
		 *
		 * @param request wire request; {@link OLLMrpc.Request.id} set here
		 * @return decoded {@link OLLMrpc.Response}
		 * @throws GLib.Error HTTP non-2xx or encode/parse failure
		 */
		public async Response call(Request request) throws GLib.Error
		{
			request.id = this.next_id++;
			/* Phase 1 fill */
			throw new GLib.IOError.FAILED("HttpClient.call not implemented");
		}
```

#### Replace with — stream request body; shared session/decode tail

```vala
		/**
		 * POST one {@link OLLMrpc.Request} (JSON or bin per {@link bin_body}).
		 *
		 * @param request wire request; {@link OLLMrpc.Request.id} set here
		 * @return decoded {@link OLLMrpc.Response}
		 * @throws GLib.Error HTTP non-2xx or encode/parse failure
		 */
		public async Response call(Request request) throws GLib.Error
		{
			request.id = this.next_id++;
			var url = this.base_url + this.rpc_path;
			var message = new Soup.Message("POST", url);
			var req_headers = message.get_request_headers();
			if (this.session_id != "") {
				req_headers.replace("X-rpc-session", this.session_id);
			}
			if (this.send_reset) {
				req_headers.replace("X-rpc-sequence", "-1");
			} else {
				req_headers.replace("X-rpc-sequence",
					"%u".printf(this.sequence));
			}
			GLib.Bytes bytes;
			if (this.bin_body) {
				int[] fds = new int[2];
				if (Posix.pipe(fds) != 0) {
					throw new GLib.IOError.FAILED(
						"HttpClient.call: pipe failed");
				}
				var unix_in = new GLib.UnixInputStream(fds[0], true);
				var unix_out = new GLib.UnixOutputStream(fds[1], true);
				message.set_request_body(
					"application/octet-stream", unix_in, -1);
				/* Start Soup before filling the pipe — avoid deadlock. */
				var send = this.soup.send_and_read_async.begin(
					message, GLib.Priority.DEFAULT, null);
				this.bin.out_stream = new GLib.DataOutputStream(unix_out);
				this.bin.out_stream.set_byte_order(
					GLib.DataStreamByteOrder.BIG_ENDIAN);
				this.bin.mode = Bin.Mode.EXPLICIT;
				try {
					this.bin.write(request);
					this.bin.out_stream.close();
				} finally {
					this.bin.out_stream = null;
				}
				bytes = yield this.soup.send_and_read_async.end(send);
			} else {
				var json_text = global::Json.to_string(
					this.json.from_gobject(request), false
				);
				message.set_request_body(
					"application/json; charset=utf-8",
					new GLib.MemoryInputStream.from_data(
						json_text.data, null),
					json_text.data.length
				);
				bytes = yield this.soup.send_and_read_async(
					message, GLib.Priority.DEFAULT, null);
			}
			if (message.status_code < 200 || message.status_code >= 300) {
				var body_text = "";
				if (bytes != null) {
					body_text = ((string) bytes.get_data()).strip();
				}
				throw new GLib.IOError.FAILED("HTTP %u for %s: %s",
					message.status_code, url, body_text);
			}
			var res_headers = message.get_response_headers();
			var sid = res_headers.get_one("X-rpc-session");
			if (sid != null && sid != "") {
				this.session_id = sid;
			}
			var seq_hdr = res_headers.get_one("X-rpc-sequence");
			if (seq_hdr != null && seq_hdr != "") {
				uint64 parsed_seq = 0;
				if (uint64.try_parse(seq_hdr, out parsed_seq)
					&& parsed_seq <= uint.MAX) {
					this.sequence = (uint) parsed_seq;
				}
			}
			this.send_reset = false;
			Response response;
			if (this.bin_body) {
				this.bin.in_stream = new GLib.DataInputStream(
					new GLib.MemoryInputStream.from_bytes(bytes)
				);
				this.bin.in_stream.set_byte_order(
					GLib.DataStreamByteOrder.BIG_ENDIAN);
				Bin.Serializable parsed;
				try {
					parsed = this.bin.parse();
				} finally {
					this.bin.in_stream = null;
				}
				response = parsed as Response;
				if (response == null) {
					throw new Bin.StreamError.PROTOCOL(
						"HTTP bin body did not decode to a Response");
				}
			} else {
				var parser = new Json.Parser();
				parser.load_from_data(
					(string) bytes.get_data(), (ssize_t) bytes.get_size());
				var root = parser.get_root();
				if (root == null
					|| root.get_node_type() != Json.NodeType.OBJECT) {
					throw new Bin.StreamError.PROTOCOL(
						"HTTP JSON root must be an object");
				}
				var mem = new GLib.MemoryOutputStream.resizable();
				var encode_ctx = new Bin.Stream(
					null, new GLib.DataOutputStream(mem));
				this.json.json_to_bin(
					root.get_object(), encode_ctx, typeof(Response));
				encode_ctx.out_stream.close();
				var read_ctx = new Bin.Stream(
					new GLib.DataInputStream(
						new GLib.MemoryInputStream.from_bytes(
							mem.steal_as_bytes())
					),
					null
				);
				read_ctx.mode = this.json.mode;
				var parsed = read_ctx.parse();
				response = parsed as Response;
				if (response == null) {
					throw new Bin.StreamError.PROTOCOL(
						"HTTP JSON body did not decode to a Response");
				}
			}
			if (response.error != null) {
				GLib.warning("%s id=%d: %s",
					request.method, request.id, response.error.message);
				var quark = GLib.Quark.from_string(response.error.domain);
				var code = response.error.gerror_code;
				if (response.error.domain == "") {
					quark = new RpcErrorCode.INTERNAL_ERROR("").domain;
					code = response.error.code;
				}
				throw new GLib.Error.literal(
					quark, code, response.error.message);
			}
			return response;
		}
```

**ℹ️** Bin **request** streams via `Posix.pipe` + `set_request_body(..., -1)` (start Soup before writing).

**ℹ️** JSON request uses `MemoryInputStream` over `Json.to_string` output (string already materialized).

**ℹ️** Response still `send_and_read_async` (full buffer) for v1 — streaming the response read is backlog (like server `flatten()`).

**ℹ️** `reset()` already in Phase 0; Phase 1 `call` honors `send_reset`.

---

## Phase 2 — `reset` behaviour check

### 4. Confirm `reset` + `-1` (no extra API)

**Why:** Phase 0 already adds `reset()`; Phase 1 `call` sends `-1` when armed.

**Depends on:** Phase 1.

- **🔷** `⏳` **No further library code** — wiring already matches Design → Reset.
- **ℹ️** `reset` does **not** clear `session_id` (same UUID on server).
- **ℹ️** Failed non-2xx leaves `send_reset` armed (flag cleared only after 2xx header update) so a retry still sends `-1`.
- **ℹ️** JSON and bin both send `-1` when armed; server resets session bin + sequence either way.
- **🔷** Phase 3 smoke proves: after two bin calls, `reset()` then next `call` → echoed `sequence == 1` and same `session_id`.
- **🚫** New methods or a separate “reset call” type.
- **🚫** Clearing `session_id` inside `reset()` (that would force a new server UUID).

**Done when:** you agree the checklist above; mark this phase **✔️** (still no code). Smoke stays Phase 3.
---

## Phase 3 — Smoke test

### 5. `tests/rpc/http-client-test.vala` — `HttpClient` ↔ `HttpServer`

**Why:** Prove JSON and bin paths + session/reset via the library client.

**Where:** new test; mirror `test-rpc-http-bin-session` meson block.

**Depends on:** Phases 0–2; server from **8.2.3** / **8.2.3.2**.

#### Add — outline

- Register Hello + start `HttpServer(0)`.
- **JSON:** `HttpClient` default `bin_body = false`; `call` → Hello World; `session_id` set; `sequence == 1`; second `call` → `sequence == 2`.
- **Bin:** new client or same with `bin_body = true` (and cleared session if switching); two calls → JIT reuse; `reset()` → third call `sequence == 1`.
- Bogus `session_id` → expect `409` / thrown `GLib.IOError`.

#### Add — `tests/meson.build`

```meson
test_rpc_http_client = executable('test-rpc-http-client',
  'rpc/http-client-test.vala',
  ...
)
test('test-rpc-http-client', test_rpc_http_client, ...)
```

**ℹ️** Copy deps/link from `test-rpc-http-bin-session` verbatim when implementing.

---

## Backlog

- **🔷** `⏳` Implement Phase 2 confirm (no code) + Phase 3 smoke after approval.
- **💩** `⏳` `call_sync` for non-async callers.
- **🔷** `⏳` Streaming / NDJSON client (**8.2.3.1**) — later.
- **🔷** `⏳` **Future:** stream HTTP **response** read (not only `send_and_read_async`) — not in v1.
- **🚫** Fold into `OLLMrpc.Client`.
- **🚫** Client use of `Session.take` / server session table.
- **🚫** Live handles / SCM over HTTP.
- **🚫** Bin-only or JSON-only restriction on this type.
- **🚫** Bin request via `MemoryOutputStream` + `set_request_body_from_bytes`.

---

## LLM notes

- **🚫** Do not start implementation until user approves these proposals.
- **ℹ️** Named methods: `HttpClient` ctor, `call`, `reset` only; `bin_body` is a property.
- **ℹ️** Parent **8.2.3** deferred “extend Client for POST”; this plan is that dedicated type.
- **ℹ️** Keep `OLLMrpc.Client` Hub GET path untouched.
- **ℹ️** After implement, mark **✔️**; user promotes **✅**.
