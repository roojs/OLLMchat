# 8.2.3.2 — HTTP binary RPC + session id

**Status:** **PROPOSED** — Phases 0–3 **✔️** agent (`Session` lifecycle + bin HTTP + smoke); implement idle TTL still **💩** 1800s default; user verify → ✅

> **Do not update `docs/plans/RPC-1.0-summary.md` for this plan.**

**Parent:** [`RPC-8.2.3-http-server-rpc.md`](RPC-8.2.3-http-server-rpc.md)

**Depends on:** [`RPC-8.2.3.3-http-path-type-registration.md`](RPC-8.2.3.3-http-path-type-registration.md) route/type shape ✅; [`RPC-8.2.3.1-http-json-streaming.md`](RPC-8.2.3.1-http-json-streaming.md) preferred stable first

**Related:** Parent **8.2** Phase 6 session resumption; [`docs/bin-rpc-protocol.md`](../bin-rpc-protocol.md)

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Purpose

- **🔷** Accept **bin** RPC request bodies over HTTP (same `Request` / `Response` / `Notification` objects as the socket).
- **🔷** Because HTTP is sessionless, carry a **session id** so the server can restore **bin JIT name tables** across POSTs (not leases — those stay per POST on `HttpReply`).
- **🔷** Carry a **sequence number** on the session — each request advances it by one (no rolling checksum).
- **🔷** Keep a **`Session`** type for lifecycle (create / touch / idle expiry / client reset) — not flatten into bare id→bin / id→sequence maps alone.
- **🔷** Idle **expiry** so sessions do not live forever.
- **🔷** Client may send sequence **`-1`** to **reset** that session (fresh bin tables, sequence restarts).
- **🔷** Keep main-loop-only concurrency (no threading MPM).

---

## Design principle — composition, not bind

- **ℹ️** Today `Connection` holds both transport and **live-handle / lease** state (`leases`, `next_handle`, callbacks, …).
- **ℹ️** For TCP, one socket = one `Connection` for the channel lifetime. `HttpReply : Connection` reuses the type so `Request.dispatch()` keeps calling `connection.write()` / `connection.export()` on the active reply.
- **ℹ️** For HTTP, **only bin JIT wire-name tables** must survive across POSTs. Leases and callbacks are scoped to **one POST** (one `HttpReply` instance).
- **🔷** **`Session`** holds shared **`Bin.Stream` name tables**, opaque **`id`**, per-session **`sequence`**, **last-used** time, and HTTP **`take()`** lookup — not leases.
- **🔷** **`Connection`** keeps leases, `next_handle`, callbacks, socket `bin`, transport — **no delegating getters**, **no `Connection.session` field**.
- **🔷** **`HttpReply` takes a `Session`** and sets `this.bin = session.bin` in `construct` so encode/decode shares JIT tables; **`session.bin.connection = this`** so live refs resolve against **this POST’s** lease maps.
- **🔷** Socket listeners keep `new Connection(stream)` unchanged — private `bin` from `start()` as today.
- **🚫** `Session.bind`, `Session.sync`, freestanding `OLLMrpc.Checksum` class, rolling / MD5 registry checksum.
- **🚫** Dropping `Session` for bare `id → bin` / `id → sequence` maps only (lifecycle needs the object).

### Roles after refactor

- **`Session`** — `id`, shared `Bin.Stream`, `sequence`, `last_used`, HTTP `take()` table + idle purge
- **`Connection`** — leases, `next_handle`, callbacks, `signal_subs`, per-channel `bin` (socket), transport (`stream`, channel, `write`, read loop), `live_handles`
- **`HttpReply`** — `session`, `soup`, `msg`, POST flags (`streaming`, `finished`, `paused`, `bin_body`); inherits `Connection` — **fresh lease maps per POST**, **shared `session.bin`**

### Content types

- **🔷** Request bin body: `Content-Type: application/octet-stream` → bin decode path in `HttpServer.on_rpc`.
- **🔷** JSON path stays `application/json` (Phase 1 / **8.2.3.1**).
- **🔷** Response: mirror request (octet-stream for bin; JSON for JSON).
- **🔷** Unary bin reply: encode straight into Soup chunked `response_body` (same append/`complete` shape as NDJSON) — not `MemoryOutputStream` + `set_response`.
- **ℹ️** `Bin.Stream.in_stream` / `out_stream` are settable (not construct-only) so one session `bin` can rewire I/O per POST.
- **🚫** Custom `application/x-ollmrpc-bin`.

### Session id

- **🔷** Wire header: `X-rpc-session: <id>` on request; echo on response.
- **🔷** Id is a **UUID** from `GLib.Uuid.string_random()` (not a counter).
- **🚫** `X-OLLMrpc-Session` / OLLM-prefixed header names.
- **🔷** Assign at first call when the header is omitted (`Session.take("")`).
- **🔷** Server table: session id → `Session` instance.
- **🔷** Unknown or **expired** session → HTTP `409` + plain text.
- **🚫** Sequential / `next_id` session ids.
- **🚫** Session-count LRU / hard OOM cap (v1) — idle expiry only.

### Session idle expiry

- **🔷** Each `Session` stores `last_used` (`GLib.get_monotonic_time()`).
- **🔷** `Session.take` purges idle rows before lookup/create, then touches `last_used` on the returned session.
- **ℹ️** Purge is a full-map scan — fine for v1; comment in code flags it as inefficient under high session load.
- **💩** Idle TTL **1800** seconds (30 minutes) — confirm or change before implement.
- **ℹ️** Expired id is gone from the table → same `409` as unknown; client omits `X-rpc-session` for a new UUID (or keeps id only if still alive).

### Request sequence

- **🔷** Header: `X-rpc-sequence: <decimal>` on request; echo advanced value on response.
- **🔷** Per-session counter on `Session.sequence` (starts at `0`).
- **🔷** First request: omit header or send `0`; must match current `session.sequence`.
- **🔷** On accept (normal path): `session.sequence++`, then echo the new value.
- **🔷** **`X-rpc-sequence: -1`** on an **existing** session → **reset**: replace `session.bin` with a fresh server `Bin.Stream`, set `sequence = 0`, then same accept bump (`sequence++` → echo `1`). Same session **UUID**.
- **🔷** `-1` with empty/omitted session id → create new session (already empty bin); then bump as first request.
- **🔷** Mismatch (not `-1` and not current) → HTTP `409` + plain text.
- **🚫** Rolling MD5 checksum, pending registration keys, `note_checksum` / `roll_checksum`.
- **🚫** Process-wide registry language hash; hooks in `Bin.register` / `Http.add` / `Request.add_class`.

### Named APIs (this plan)

- **🔷** `OLLMrpc.Transport.Session` — HTTP bin-table owner; `take(string id)`; instance `sequence` / `last_used` / `bin`.
- **🔷** `Connection` — unchanged lease/export API for Gi and Live handlers.
- **🔷** `HttpReply(Soup.Server, Soup.ServerMessage, Session)` — wires shared `session.bin` onto the per-POST reply.
- **🔷** `BodyStream` — private `GLib.OutputStream` over `Soup.MessageBody.append` so `Bin.Stream` can write the HTTP body directly.

---

## Suggested implement order

1. **Phase 0** — `Session` (UUID id + bin + sequence + idle expiry in `take`) + `HttpReply(session)` wiring (`Connection.vala` unchanged).
2. **Phase 1** — `Session.take` + `X-rpc-session` / `X-rpc-sequence` (incl. `-1` reset) on `/rpc`; `HttpReply(session)`.
3. **Phase 2** — bin POST (`application/octet-stream`) on `/rpc`.
4. **Phase 3** — smoke: two POSTs + sequence; `-1` resets bin; expired → `409`.
5. Streaming resume (with **8.2.3.1**) — later fill.

---

## Phase 0 — `Session` (HTTP bin tables only)

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `libocrpc/Transport/Session.vala` — new file: HTTP JIT + id + expiry

**Why:** Cross-POST **bin name tables**, **`X-rpc-session`** lookup, idle purge, and sequence lifecycle. Leases stay on {@link Connection}.

**Where:** new file under `libocrpc/Transport/`.

**Depends on:** none.

#### Add

New file `libocrpc/Transport/Session.vala` (entire contents):

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
	 * HTTP RPC session — shared bin JIT name tables, sequence, idle expiry.
	 *
	 * Many {@link HttpReply} POSTs share one session's {@link bin} tables.
	 * Leases and {@link Connection.next_handle} live on each {@link HttpReply}
	 * (per POST), not here. HTTP looks up sessions by ''X-rpc-session'' via
	 * {@link take}. Socket {@link Connection} does not use this type.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var session = OLLMrpc.Transport.Session.take("");
	 * var reply = new OLLMrpc.Transport.HttpReply(soup, msg, session);
	 * }}}
	 */
	public class Session : GLib.Object
	{
		/** Opaque session UUID (echoed on ''X-rpc-session''; empty until assigned). */
		public string id { get; set; default = ""; }

		/**
		 * Shared JIT wire-name tables ({@link Bin.Stream.client_names} /
		 * {@link Bin.Stream.server_names}). I/O streams are attached per POST
		 * on {@link HttpReply}; {@link Bin.Stream.connection} points at the
		 * active {@link HttpReply} for that POST's leases.
		 */
		public Bin.Stream bin {
			get; set; default = new Bin.Stream(null, null, true);
		}

		/**
		 * Per-session request counter. Client must send the last echoed
		 * value (or ''0'' / omit on first POST); ''-1'' resets bin + counter.
		 * Server increments on accept.
		 */
		public uint sequence { get; set; default = 0; }

		/**
		 * Monotonic µs of last {@link take} touch (idle expiry).
		 */
		public int64 last_used { get; set; default = 0; }

		internal static Gee.HashMap<string, Session> by_id;

		/** Idle TTL in seconds (default 30 minutes — see plan). */
		internal static uint idle_secs = 1800;

		/**
		 * Look up ''id'', or allocate a new session when ''id'' is empty.
		 * Purges idle sessions first; touches {@link last_used} on success.
		 *
		 * @param id client ''X-rpc-session'' value, or empty to create
		 * @return session, or null when ''id'' is non-empty and unknown/expired
		 */
		public static Session? take(string id)
		{
			if (by_id == null) {
				by_id = new Gee.HashMap<string, Session>();
			}
			var now = GLib.get_monotonic_time();
			var idle_us = (int64) idle_secs * 1000 * 1000;
			/* Horribly inefficient at large session counts (full-map scan
			 * every take). Revisit if we ever see high load. */
			var stale = new Gee.ArrayList<string>();
			foreach (var sid in by_id.keys) {
				if (now - by_id.get(sid).last_used > idle_us) {
					stale.add(sid);
				}
			}
			foreach (var sid in stale) {
				by_id.unset(sid);
			}
			if (id != "") {
				if (!by_id.has_key(id)) {
					return null;
				}
				var existing = by_id.get(id);
				existing.last_used = now;
				return existing;
			}
			var session = new Session();
			session.id = GLib.Uuid.string_random();
			session.last_used = now;
			by_id.set(session.id, session);
			return session;
		}
	}
}
```

### 2. `libocrpc/Transport/Connection.vala` — **Keep** (Phase 0)

**Why:** {@link export}, {@link stop}, Gi, and Live code keep using `connection.leases`, `connection.next_handle`, and socket {@link bin} from {@link start} with no indirection.

**Where:** no edit in Phase 0.

**Depends on:** none.

**ℹ️** HTTP POSTs use {@link HttpReply} — a new {@link Connection} subclass per POST with **empty** lease maps; only {@link HttpReply.session.bin} is shared.

### 3. `libocrpc/Transport/HttpReply.vala` — construct with `Session`

**Why:** Reply shares JIT tables via `session.bin`; leases stay on `this` (the POST-scoped {@link Connection}).

**Where:** class body + constructor.

**Depends on:** §1.

#### Add — property (before `soup` or after class opening)

```vala
		/**
		 * Shared HTTP session (bin name tables + id). Not used for leases.
		 */
		public Session session { get; construct; }
```

#### Remove

```vala
		public HttpReply(Soup.Server soup, Soup.ServerMessage msg)
		{
			GLib.Object(soup: soup, msg: msg);
		}
```

#### Replace with

```vala
		public HttpReply(
			Soup.Server soup,
			Soup.ServerMessage msg,
			Session session
		) {
			GLib.Object(soup: soup, msg: msg, session: session);
		}

		construct {
			this.bin = this.session.bin;
			if (this.bin != null) {
				this.bin.connection = this;
			}
		}
```

### 4. `libocrpc/Transport/HttpServer.vala` — pass ephemeral session on typed routes

**Why:** `HttpReply` now requires a `Session`. Typed routes do not use the HTTP session table in v1 — each POST gets a private session.

**Where:** `on_route` `new HttpReply(...)`.

**Depends on:** §3.

#### Remove

```vala
			var reply = new HttpReply(this.soup, msg) {
				live_handles = this.live_handles
			};
```

#### Replace with

```vala
			var reply = new HttpReply(this.soup, msg, new Session()) {
				live_handles = this.live_handles
			};
```

### 5. `libocrpc/meson.build` + `docs/meson.build` — Session source

**Why:** Compile + valadoc.

**Where:** `ocrpc_core_src` before `Connection.vala`; docs list with other Transport types.

**Depends on:** §1.

#### Add — meson `ocrpc_core_src` (before `'Transport/Connection.vala',`)

```meson
  'Transport/Session.vala',
```

#### Add — `docs/meson.build` valadoc inputs

```meson
    '../libocrpc/Transport/Session.vala',
```

---

## Phase 1 — HTTP session table + headers (JSON `/rpc`)

### 6. `libocrpc/Transport/HttpServer.vala` — session + sequence on `on_rpc`

**Why:** Look up or create session, verify sequence, echo headers. `HttpReply` constructed with session — no bind.

**Where:** `on_rpc` — session lookup before reply construction; headers after reply exists.

**Depends on:** Phase 0.

#### Remove

```vala
			var reply = new HttpReply(this.soup, msg) {
				live_handles = this.live_handles
			};
			if (msg.get_method() != "POST") {
```

#### Replace with

```vala
			var req_headers = msg.get_request_headers();
			var session_hdr = req_headers.get_one("X-rpc-session");
			if (session_hdr == null) {
				session_hdr = "";
			}
			var session = Session.take(session_hdr);
			if (session == null) {
				msg.set_status(409, null);
				msg.set_response("text/plain", Soup.MemoryUse.COPY,
					"unknown session".data);
				return;
			}
			var client_seq_hdr = req_headers.get_one("X-rpc-sequence");
			int64 client_seq = 0;
			if (client_seq_hdr != null && client_seq_hdr != "") {
				if (!int64.try_parse(client_seq_hdr, out client_seq)) {
					msg.set_status(409, null);
					msg.set_response("text/plain", Soup.MemoryUse.COPY,
						"sequence mismatch".data);
					return;
				}
			}
			if (client_seq == -1) {
				session.bin = new Bin.Stream(null, null, true);
				session.sequence = 0;
			} else if (client_seq < 0
				|| client_seq > uint.MAX
				|| (uint) client_seq != session.sequence) {
				msg.set_status(409, null);
				msg.set_response("text/plain", Soup.MemoryUse.COPY,
					"sequence mismatch".data);
				return;
			}
			session.sequence++;
			var reply = new HttpReply(this.soup, msg, session) {
				live_handles = this.live_handles
			};
			var res_headers = msg.get_response_headers();
			res_headers.replace("X-rpc-session", session.id);
			res_headers.replace("X-rpc-sequence",
				"%u".printf(session.sequence));
			if (msg.get_method() != "POST") {
```

**ℹ️** No `session.sync(reply)` — `next_handle` and leases are on each {@link HttpReply} (per POST); only {@link Session.bin} name tables persist.

**ℹ️** Omit / empty `X-rpc-sequence` is treated as `0` (first POST only).

**ℹ️** `-1` resets bin + sequence on the **same** UUID, then bumps to `1` for this POST.

---

## Phase 2 — Bin POST (`application/octet-stream`)

### 7. `libocrpc/Transport/HttpReply.vala` — bin encode in `write`

**Why:** Mirror request Content-Type; write bin bytes into the Soup response body stream (no full-buffer `set_response`).

**Where:** `HttpReply` — add `bin_body` flag; private `BodyStream`; branch in `write`.

**Depends on:** Phase 0.

**ℹ️** Soup has no `GLib.OutputStream` for the response — only `MessageBody.append`. `BodyStream` bridges that so `Bin.Stream` keeps using `DataOutputStream`.

**🚫** `MemoryOutputStream` + `steal_as_bytes` + `set_response` for unary bin.

#### Add — property after `paused`

```vala
		/**
		 * True when the POST used ''application/octet-stream'' (bin reply).
		 */
		public bool bin_body { get; set; default = false; }
```

#### Add — private class before `HttpReply` (same file)

```vala
	/**
	 * ''GLib.OutputStream'' that appends into a Soup response body.
	 *
	 * Lets {@link Bin.Stream} write HTTP chunked octets without buffering
	 * the whole reply in a {@link GLib.MemoryOutputStream}.
	 */
	private class BodyStream : GLib.OutputStream
	{
		public Soup.MessageBody body { get; construct; }

		public BodyStream(Soup.MessageBody body)
		{
			GLib.Object(body: body);
		}

		public override ssize_t write(
			uint8[] buffer,
			GLib.Cancellable? cancellable = null
		) throws GLib.IOError {
			this.body.append(Soup.MemoryUse.COPY, buffer);
			return (ssize_t) buffer.length;
		}

		public override bool close(GLib.Cancellable? cancellable = null)
			throws GLib.IOError
		{
			return true;
		}
	}
```

#### Remove

```vala
			try {
				var json_text = global::Json.to_string(
					this.json.from_gobject(serializable), false
				);
				if (!this.streaming && serializable is Response) {
					this.msg.set_response(
						"application/json; charset=utf-8",
						Soup.MemoryUse.COPY,
						json_text.data
					);
					this.msg.set_status(200, null);
					this.finished = true;
					return;
				}
```

#### Replace with

```vala
			try {
				if (this.bin_body && !this.streaming && serializable is Response) {
					this.msg.set_status(200, null);
					this.msg.get_response_headers().set_content_type(
						"application/octet-stream", null);
					this.msg.get_response_headers().set_encoding(
						Soup.Encoding.CHUNKED);
					this.bin.out_stream = new GLib.DataOutputStream(
						new BodyStream(this.msg.get_response_body())
					);
					this.bin.out_stream.set_byte_order(
						GLib.DataStreamByteOrder.BIG_ENDIAN);
					this.bin.write(serializable);
					this.bin.out_stream.close();
					this.bin.out_stream = null;
					this.msg.get_response_body().complete();
					this.finished = true;
					return;
				}
				var json_text = global::Json.to_string(
					this.json.from_gobject(serializable), false
				);
				if (!this.streaming && serializable is Response) {
					this.msg.set_response(
						"application/json; charset=utf-8",
						Soup.MemoryUse.COPY,
						json_text.data
					);
					this.msg.set_status(200, null);
					this.finished = true;
					return;
				}
```

### 8. `libocrpc/Transport/HttpServer.vala` — bin decode branch in `on_rpc`

**Why:** `Content-Type: application/octet-stream` → parse with `reply.session.bin`.

**Where:** `on_rpc` after POST check — branch before JSON parser.

**Depends on:** §6, §7.

#### Add — after POST check, before JSON `Json.Parser` path

Purpose: detect octet-stream, parse bin `Request`, set `reply.bin_body`, then share dispatch tail with JSON path (extract shared dispatch inline — no new helper).

```vala
			var content_type = msg.get_request_headers().get_one("Content-Type");
			if (content_type == null) {
				content_type = "";
			}
			OLLMrpc.Request request;
			if (content_type.has_prefix("application/octet-stream")) {
				reply.bin_body = true;
				var bytes = msg.get_request_body().flatten();
				reply.session.bin.in_stream = new GLib.DataInputStream(
					new GLib.MemoryInputStream.from_bytes(bytes)
				);
				reply.session.bin.in_stream.set_byte_order(
					GLib.DataStreamByteOrder.BIG_ENDIAN);
				reply.session.bin.mode = Bin.Mode.EXPLICIT;
				Bin.Serializable parsed;
				try {
					parsed = reply.session.bin.parse();
				} catch (GLib.Error e) {
					reply.write(new Response() {
						error = new OLLMrpc.Error(
							(int) OLLMrpc.RpcErrorCode.PARSE_ERROR,
							"invalid bin: " + e.message
						)
					});
					msg.set_status(400, null);
					return;
				}
				reply.session.bin.in_stream = null;
				request = parsed as OLLMrpc.Request;
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
			} else {
```

**ℹ️** Close the `else {` around the existing JSON decode through `request = parsed as Request` null-check; then common `request.connection = reply; dispatch…` stays once after the if/else.

---

## Phase 3 — Smoke test

### 9. `tests/rpc/http-bin-session-test.vala` — two POSTs + sequence

**Why:** Prove session name-table restore and sequence header.

**Where:** new test file; wire in `tests/meson.build` like `test-rpc-http-routes`.

**Depends on:** Phases 0–2.

#### Add

New executable smoke (outline — fill literals when implementing):

- Register Hello + types; note both client and server use same `rpc_register` order.
- POST 1: `Content-Type: application/octet-stream`, no `X-rpc-session` / no `X-rpc-sequence`; capture `X-rpc-session` + `X-rpc-sequence` from response (expect sequence `1`).
- POST 2: same session + sequence from POST 1; bin body that depends on a wire name learned in POST 1 (or second call that only works if JIT tables persist); expect sequence `2`.
- POST 3: same session + `X-rpc-sequence: -1`; expect sequence `1` again; prior JIT wire name must **not** apply (fresh bin).
- Wrong sequence → expect `409`.
- Unknown / expired session → expect `409`.

#### Add — `tests/meson.build` (mirror `test-rpc-http-routes` block)

```meson
test_rpc_http_bin_session = executable('test-rpc-http-bin-session',
  'rpc/http-bin-session-test.vala',
  ...
)
test('test-rpc-http-bin-session', test_rpc_http_bin_session, ...)
```

**ℹ️** Copy deps/link from `test-rpc-http-routes` verbatim when implementing.

---

## Backlog

- **🔷** `✔️` Implement Phases 0–3 after approval.
- **🔷** `⏳` Typed HTTP routes (`on_route`) — optional shared session table later.
- **🔷** `⏳` Streaming resume + session (**8.2.3.1**) — fill fences later.
- **🔷** `⏳` HTTP **client** (JSON + bin) — [`RPC-8.2.3.4-http-client.md`](RPC-8.2.3.4-http-client.md).
- **🔷** `⏳` **Future:** stream HTTP **request** body into `Bin.Stream` (`set_accumulate(false)` / chunk handlers) — not in this plan’s implement phases.
- **💩** `⏳` Confirm idle TTL (plan default **1800** s) before implement.
- **🚫** TLS / client certs — **8.2.3** / **8.2.7**.
- **🚫** Threaded workers; session-count LRU / hard OOM cap (idle expiry covers cleanup).
- **🚫** Rolling MD5 / `X-rpc-checksum` / registration-map feeds.
- **🚫** `Session.bind` / `Session.sync` / freestanding `Checksum` class.
- **🚫** Unary bin via `MemoryOutputStream` + `set_response`.
- **🚫** Request-body streaming in Phases 0–3 — keep `flatten()` + `MemoryInputStream` for now.
- **🚫** Replace `Session` with bare id→bin / id→sequence maps only.

---

## LLM notes

- **🚫** Do not start implementation until user approves these proposals.
- **ℹ️** `Bin.Stream.in_stream` / `out_stream` changed from construct-only to settable so session `bin` rewires I/O per POST (needed for this plan).
- **ℹ️** `Session.take` is **named in this plan** (allowed method). Sequence bump and `-1` bin reset are **inlined** in `on_rpc` (no `Session.reset` helper).
- **ℹ️** `BodyStream` is **named in this plan** (private `OutputStream` over Soup `MessageBody`).
- **ℹ️** Parent **8.2.6** should reuse `Session` concepts long-term.
- **ℹ️** Sequence is per-session request ordering; `-1` is client-driven restart of JIT tables on the same UUID.
- **ℹ️** Phase 0 adds {@link Session} and {@link HttpReply.session} only — **no** {@link Connection} field moves; socket tests should be unchanged.
- **ℹ️** Request decode uses `flatten()` — Soup has already buffered the POST before the handler. True request-body streaming is backlog-only (not Phases 0–3).
- **ℹ️** Idle purge runs inside `take` (no background timer required for v1).
