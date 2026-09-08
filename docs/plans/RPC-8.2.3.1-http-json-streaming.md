# 8.2.3.1 — HTTP JSON streaming (inference)

**Status:** **PROPOSED** — Phase streaming `✔️` agent (NDJSON)

> **Do not update `docs/plans/RPC-1.0-summary.md` for this plan.**

**Parent:** [`RPC-8.2.3-http-server-rpc.md`](RPC-8.2.3-http-server-rpc.md) — Phase 1 unary HTTP JSON `✔️`

**Follows:** Phase 1 `HttpServer` / `HttpReply` in tree

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

**Review notes applied:** `write(...)` signature on one line; no `open` getter — public `streaming` / `finished` / `paused`.

---

## Purpose

- **🔷** Stream **multiple JSON objects** on one HTTP POST response (inference token / chunk deltas).
- **🔷** Keep the same `Request.dispatch` / `connection.write` / `request.reply` path as socket RPC.
- **🔷** Main-loop only — no thread pool (see parent concurrency rules).
- **ℹ️** OpenAI `/v1/chat/completions` SSE shape stays in parent Phase 5 / **8.2.5** — this plan is the RPC NDJSON transport.

---

## Current behaviour (Phase 1)

- **ℹ️** `HttpReply.write` always `set_response` once (whole body) + status `200`.
- **ℹ️** `HttpServer.on_rpc` runs `dispatch()` inline and returns; Soup finishes the message when the callback returns.
- **ℹ️** Socket RPC already fans progress with `connection.write(new Notification())` then a final `Response`.

---

## Design

### Framing

- **💩** Primary: **NDJSON** — `Content-Type: application/x-ndjson`, one auto-JSON object per line (`\n`), chunked transfer.
- **🚫** OpenAI `text/event-stream` adapter — later (8.2.5), not this plan.
- **🔷** Each line is `Bin.Json` AUTO encode of a `Bin.Serializable` (`Notification` chunks, final `Response`).

### Unary vs stream (no new API flag)

- **🔷** First outbound object is a **`Response`** → keep Phase 1 unary (`set_response` once).
- **🔷** First outbound object is a **`Notification`** (or any non-`Response`) → open NDJSON stream; each `write` appends one JSON line + `\n`.
- **🔷** Final **`Response`** on an open stream → append last line, then finish the HTTP message (unpause if paused).
- **🔷** Transport/encode failures on a stream → plain-text body only if headers not yet sent; otherwise log + finish (client already has status `200` for an open stream). Prefer ending with a JSON `Response` that has `error` when possible.

### Pause (async handlers)

- **🔷** After `dispatch()` returns, if a stream is **open** and **not finished**, `HttpServer` calls `soup.pause_message(msg)` so Soup does not complete the response.
- **🔷** Final `Response` write unpauses (`soup.unpause_message(msg)`).
- **🔷** Sync smoke (all chunks + final reply inside `dispatch`) never pauses.

### HttpReply needs Soup.Server

- **🔷** Construct `HttpReply(soup, msg)` so stream finish can unpause.
- **💩** Field name `soup` on `HttpReply` (not a second “server”).

---

## Wire example

Request (same as Phase 1):

```json
{"id":1,"method":"RPC-Hello.stream","args":[]}
```

Response body (`application/x-ndjson`):

```text
{"method":"token","message":"Hel"}
{"method":"token","message":"lo"}
{"id":1,"msg":"done"}
```

(Exact `Notification` fields depend on encode; smoke checks predictable substrings.)

---

## Code proposals

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `libocrpc/Transport/HttpReply.vala` — stream-aware `write`

**Why:** Unary stays `set_response`; streaming appends NDJSON lines and can finish/unpause.

**Where:** class fields + constructor + `write`.

**Depends on:** none.

##### Part 1 — fields + ctor take `Soup.Server`

#### Remove

```vala
		public Soup.ServerMessage msg { get; construct; }

		private Bin.Json json = new Bin.Json(Bin.Mode.AUTO);

		public HttpReply(Soup.ServerMessage msg)
		{
			GLib.Object(msg: msg);
		}
```

#### Replace with

```vala
		public Soup.Server soup { get; construct; }
		public Soup.ServerMessage msg { get; construct; }

		private Bin.Json json = new Bin.Json(Bin.Mode.AUTO);
		private bool streaming = false;
		private bool finished = false;

		public HttpReply(Soup.Server soup, Soup.ServerMessage msg)
		{
			GLib.Object(soup: soup, msg: msg);
		}
```

##### Part 2 — `write`: unary vs NDJSON stream

#### Remove

```vala
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
```

#### Replace with

```vala
		public override void write(
			GLib.Object gobject,
			Live.Buffer? buffer = null
		)
		{
			if (this.finished) {
				GLib.warning("http write after finish");
				return;
			}
			var serializable = gobject as Bin.Serializable;
			if (serializable == null) {
				GLib.warning("http write: not bin Serializable");
				if (!this.streaming) {
					this.msg.set_response("text/plain; charset=utf-8", Soup.MemoryUse.COPY,
						"http write: not bin Serializable".data);
					this.msg.set_status(500, null);
					this.finished = true;
				}
				return;
			}
			try {
				var json_text = global::Json.to_string(this.json.from_gobject(serializable), false);
				if (!this.streaming && serializable is Response) {
					this.msg.set_response("application/json; charset=utf-8", Soup.MemoryUse.COPY,
						json_text.data);
					this.msg.set_status(200, null);
					this.finished = true;
					return;
				}
				if (!this.streaming) {
					this.streaming = true;
					this.msg.set_status(200, null);
					this.msg.get_response_headers().set_content_type("application/x-ndjson", null);
					this.msg.get_response_headers().set_encoding(Soup.Encoding.CHUNKED);
				}
				this.msg.get_response_body().append(Soup.MemoryUse.COPY, (json_text + "\n").data);
				if (serializable is Response) {
					this.finished = true;
					this.soup.unpause_message(this.msg);
				}
			} catch (GLib.Error e) {
				GLib.warning("http write error: %s", e.message);
				if (!this.streaming) {
					this.msg.set_response("text/plain; charset=utf-8", Soup.MemoryUse.COPY,
						("encode failed: " + e.message).data);
					this.msg.set_status(500, null);
					this.finished = true;
				}
			}
		}

		/**
		 * True when NDJSON stream started and final {@link Response} not yet written.
		 */
		public bool open {
			get {
				return this.streaming && !this.finished;
			}
		}
```

- **ℹ️** Unary path encodes once via `set_response` (no trailing `\n`). Stream path appends the same JSON plus `\n`.
- **🔷** Property `open` named here for `HttpServer` pause check.

---

### 2. `libocrpc/Transport/HttpServer.vala` — construct `HttpReply(soup, msg)` + pause

**Why:** Pass `soup` into `HttpReply`; pause when dispatch returns with stream still open.

**Where:** `on_rpc` — `new HttpReply` and end of method after `dispatch`.

**Depends on:** §1.

##### Part 1 — ctor call

#### Remove

```vala
			var reply = new HttpReply(msg) {
				live_handles = this.live_handles
			};
```

#### Replace with

```vala
			var reply = new HttpReply(this.soup, msg) {
				live_handles = this.live_handles
			};
```

##### Part 2 — after successful dispatch, pause if stream open

#### Add — immediately after the `if (!request.dispatch()) { … }` block (still inside `on_rpc`)

After dispatch succeeds (no `return` from method-not-found), if the handler started NDJSON and has not finished:

```vala
			if (reply.open) {
				this.soup.pause_message(msg);
			}
```

Full anchor — **Replace** the end of `on_rpc` from `request.connection = reply` through the closing brace of the method:

#### Remove

```vala
			request.connection = reply;
			if (!request.dispatch()) {
				var err = OLLMrpc.RpcErrorCode.to_error(
					(int) OLLMrpc.RpcErrorCode.METHOD_NOT_FOUND
				);
				err.message = "no handler for '" + request.method + "'";
				reply.write(new Response() {
					id = request.id,
					error = err
				});
			}
		}
	}
}
```

#### Replace with

```vala
			request.connection = reply;
			if (!request.dispatch()) {
				var err = OLLMrpc.RpcErrorCode.to_error(
					(int) OLLMrpc.RpcErrorCode.METHOD_NOT_FOUND
				);
				err.message = "no handler for '" + request.method + "'";
				reply.write(new Response() {
					id = request.id,
					error = err
				});
				return;
			}
			if (reply.open) {
				this.soup.pause_message(msg);
			}
		}
	}
}
```

---

### 3. `tests/rpc/http-server-test.vala` — stream smoke (+ keep unary)

**Why:** Prove NDJSON multi-chunk + final `Response`; keep Hello World unary.

**Where:** extend existing test file / meson target `test-rpc-http-server`.

**Depends on:** §1–§2.

#### Add — dummy stream handler + second check in `run_rpc_test` (after unary Hello World)

```vala
	public class StreamHello : GLib.Object
	{
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"RPC-Hello", typeof(StreamHello),
				"stream", ""
			);
		}

		public void stream(OLLMrpc.Request request)
		{
			request.connection.write(new OLLMrpc.Notification() {
				method = "token",
				message = "Hel"
			});
			request.connection.write(new OLLMrpc.Notification() {
				method = "token",
				message = "lo"
			});
			request.reply(new OLLMrpc.Response() {
				msg = "done"
			});
		}
	}
```

Register `Notification.rpc_register()`, `StreamHello.rpc_register()`, and `Request.register("RPC-Hello", …)` carefully — Phase 1 already registers `Hello` on `RPC-Hello`. **💩** Use one object that implements both `world` and `stream`, or register `StreamHello` as the only `RPC-Hello` target with both methods listed in `add_class`. Prefer **one class** with both methods:

```vala
	public class Hello : GLib.Object
	{
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"RPC-Hello", typeof(Hello),
				"world", "",
				"stream", ""
			);
		}

		public void world(OLLMrpc.Request request)
		{
			request.reply(new OLLMrpc.Response() {
				msg = "Hello World"
			});
		}

		public void stream(OLLMrpc.Request request)
		{
			request.connection.write(new OLLMrpc.Notification() {
				method = "token",
				message = "Hel"
			});
			request.connection.write(new OLLMrpc.Notification() {
				method = "token",
				message = "lo"
			});
			request.reply(new OLLMrpc.Response() {
				msg = "done"
			});
		}
	}
```

Second POST `RPC-Hello.stream`; assert body contains `Hel`, `lo`, and `done` (and likely two `\n` separators). Same async `MainLoop` pattern as unary.

---

## Backlog

- **🔷** `✔️` §1–§3 land; `meson test test-rpc-http-server` covers unary + stream.
- **💩** `⏳` Async stream smoke (idle callbacks + pause) — optional follow-up if sync smoke is enough for v1.
- **🚫** SSE / OpenAI event format.
- **🚫** Bin body streaming — [`RPC-8.2.3.2-http-bin-session.md`](RPC-8.2.3.2-http-bin-session.md).

**Implementation notes (agent):**

- **✔️** Public `streaming` / `finished` / `paused` (no `open` property).
- **✔️** `write(GLib.Object gobject, Live.Buffer? buffer = null)` on one line.
- **✔️** Stream finish calls `get_response_body().complete()`; unpause only if `paused`.
- **✔️** NDJSON + chunked; smoke `RPC-Hello.stream` → Hel / lo / done.

---

## LLM notes

- **ℹ️** `pause_message` / `unpause_message` deprecated since Soup 3.2 — still used; replace later if Soup offers a non-deprecated pause API.
- **🚫** No thread pool / MPM.
