# 8.2.3.2 — HTTP binary RPC + session id

**Status:** **PROPOSED** — design revised (HTTP `Session` = bin JIT + id only; leases stay on `Connection`); implement after user approval

> **Do not update `docs/plans/RPC-1.0-summary.md` for this plan.**

**Parent:** [`RPC-8.2.3-http-server-rpc.md`](RPC-8.2.3-http-server-rpc.md)

**Depends on:** [`RPC-8.2.3.3-http-path-type-registration.md`](RPC-8.2.3.3-http-path-type-registration.md) route/type shape ✅; [`RPC-8.2.3.1-http-json-streaming.md`](RPC-8.2.3.1-http-json-streaming.md) preferred stable first

**Related:** Parent **8.2** Phase 6 session resumption; [`docs/bin-rpc-protocol.md`](../bin-rpc-protocol.md)

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Purpose

- **🔷** Accept **bin** RPC request bodies over HTTP (same `Request` / `Response` / `Notification` objects as the socket).
- **🔷** Because HTTP is sessionless, carry a **session id** so the server can restore **bin JIT name tables** across POSTs (not leases — those stay per POST on `HttpReply`).
- **🔷** Carry a **registry checksum** with the session so both ends know they share the same registration “language”.
- **🔷** Keep main-loop-only concurrency (no threading MPM).

---

## Design principle — composition, not bind

- **ℹ️** Today `Connection` holds both transport and **live-handle / lease** state (`leases`, `next_handle`, callbacks, …).
- **ℹ️** For TCP, one socket = one `Connection` for the channel lifetime. `HttpReply : Connection` reuses the type so `Request.dispatch()` keeps calling `connection.write()` / `connection.export()` on the active reply.
- **ℹ️** For HTTP, **only bin JIT wire-name tables** must survive across POSTs. Leases and callbacks are scoped to **one POST** (one `HttpReply` instance).
- **🔷** **`Session`** holds shared **`Bin.Stream` name tables**, opaque **`id`**, and HTTP **`take()`** lookup — not leases.
- **🔷** **`Connection`** keeps leases, `next_handle`, callbacks, socket `bin`, transport — **no delegating getters**, **no `Connection.session` field**.
- **🔷** **`HttpReply` takes a `Session`** and sets `this.bin = session.bin` in `construct` so encode/decode shares JIT tables; **`session.bin.connection = this`** so live refs resolve against **this POST’s** lease maps.
- **🔷** Socket listeners keep `new Connection(stream)` unchanged — private `bin` from `start()` as today.
- **🚫** `Session.bind`, `Session.sync`, freestanding `OLLMrpc.Checksum` class.

### Roles after refactor

| Type | Owns |
|------|------|
| **`Session`** | `id`, shared `Bin.Stream` (JIT name tables only; I/O streams wired per POST), static registry checksum (`note` / `roll`), HTTP `take()` table |
| **`Connection`** | Leases, `next_handle`, callbacks, `signal_subs`, per-channel `bin` (socket), transport (`stream`, channel, `write`, read loop), `live_handles` |
| **`HttpReply`** | `session`, `soup`, `msg`, POST flags (`streaming`, `finished`, `paused`, `bin_body`); inherits `Connection` — **fresh lease maps per POST**, **shared `session.bin`** |

### Content types

- **🔷** Request bin body: `Content-Type: application/octet-stream` → bin decode path in `HttpServer.on_rpc`.
- **🔷** JSON path stays `application/json` (Phase 1 / **8.2.3.1**).
- **🔷** Response: mirror request (octet-stream for bin; JSON for JSON).
- **🚫** Custom `application/x-ollmrpc-bin`.

### Session id

- **🔷** Wire header: `X-rpc-session: <id>` on request; echo on response.
- **🚫** `X-OLLMrpc-Session` / OLLM-prefixed header names.
- **🔷** Assign at first call when the header is omitted (`Session.take("")`).
- **🔷** Server table: session id → `Session` instance.
- **🔷** Unknown session → HTTP `409` + plain text.
- **🚫** Session-table OOM / LRU (v1 skip).

### Registry checksum

- **🔷** Header: `X-rpc-checksum: <32-char lowercase hex MD5>`.
- **🔷** Mismatch → HTTP `409` + plain text.
- **🔷** **New key** = newly inserted registration-map entry only.
- **🔷** Pending buffer of key strings; **≤1 MD5 per request** via `Session.roll_checksum()`.
- **🔷** `checksum = md5(old_hex + pending)`; no pending → unchanged.
- **🔷** Pending keys joined with `'\n'`.
- **🔷** Feeds: `Bin.register` / `register_alias`, `Http.add`, new `Request.add_class` method rows.
- **🔷** Idempotent / thrown duplicate → no pending append.
- **🚫** Rehash whole maps; hash HTTP bodies for this header.
- **ℹ️** Checksum is process-wide registration language (static on `Session`), not per-session instance state.

### Named APIs (this plan)

- **🔷** `OLLMrpc.Transport.Session` — HTTP bin-table owner; `take(string id)`; static `note_checksum` / `roll_checksum`.
- **🔷** `Connection` — unchanged lease/export API for Gi and Live handlers.
- **🔷** `HttpReply(Soup.Server, Soup.ServerMessage, Session)` — wires shared `session.bin` onto the per-POST reply.

---

## Suggested implement order

1. **Phase 0** — add slim `Session` + `HttpReply(session)` wiring ( **`Connection.vala` unchanged** ).
2. **Phase 1** — registry checksum hooks (`Session.note_checksum`) in `Bin` / `Http` / `Request.add_class`.
3. **Phase 2** — `Session.take` + headers on `/rpc`; `HttpReply(session)`.
4. **Phase 3** — bin POST (`application/octet-stream`) on `/rpc`.
5. **Phase 4** — smoke: two POSTs, shared session, JIT name survives; checksum match.
6. Streaming resume (with **8.2.3.1**) — later fill.

---

## Phase 0 — `Session` (HTTP bin tables only)

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `libocrpc/Transport/Session.vala` — new file: HTTP JIT + id

**Why:** Cross-POST **bin name tables** and **`X-rpc-session`** lookup. Leases stay on {@link Connection}.

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
	 * HTTP RPC session — shared bin JIT name tables and session id.
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
		/** Opaque session id (echoed on ''X-rpc-session''; empty until assigned). */
		public string id { get; set; default = ""; }

		/**
		 * Bin codec (name tables). I/O streams wired per transport.
		 */
		/**
		 * Shared JIT wire-name tables ({@link Bin.Stream.client_names} /
		 * {@link Bin.Stream.server_names}). I/O streams are attached per POST
		 * on {@link HttpReply}; {@link Bin.Stream.connection} points at the
		 * active {@link HttpReply} for that POST's leases.
		 */
		public Bin.Stream? bin {
			get; set; default = new Bin.Stream(null, null) {
				is_server = true
			};
		}

		/** Current registry checksum hex (process-wide; see {@link roll_checksum}). */
		public static string checksum { get; private set; default = ""; }

		private static string checksum_pending = "";

		internal static Gee.HashMap<string, Session> by_id;

		private static uint next_id = 1;

		/**
		 * Queue one new registration key for the next {@link roll_checksum}.
		 *
		 * @param key canonical insert string (e.g. bin:Alias:TypeName)
		 */
		public static void note_checksum(string key)
		{
			if (checksum_pending == "") {
				checksum_pending = key;
				return;
			}
			checksum_pending = checksum_pending + "\n" + key;
		}

		/**
		 * Apply at most one MD5: ''md5(checksum + pending)'' when pending
		 * is non-empty; otherwise return {@link checksum} unchanged.
		 *
		 * @return lowercase hex MD5 string
		 */
		public static string roll_checksum()
		{
			if (checksum_pending == "") {
				return checksum;
			}
			var sum = new GLib.Checksum(GLib.ChecksumType.MD5);
			sum.update(checksum.data);
			sum.update(checksum_pending.data);
			checksum = sum.get_string();
			checksum_pending = "";
			return checksum;
		}

		/**
		 * Look up ''id'', or allocate a new session when ''id'' is empty.
		 *
		 * @param id client ''X-rpc-session'' value, or empty to create
		 * @return session, or null when ''id'' is non-empty and unknown
		 */
		public static Session? take(string id)
		{
			if (by_id == null) {
				by_id = new Gee.HashMap<string, Session>();
			}
			if (id != "") {
				if (!by_id.has_key(id)) {
					return null;
				}
				return by_id.get(id);
			}
			var session = new Session();
			session.id = "%u".printf(next_id);
			next_id++;
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

## Phase 1 — Registry checksum hooks

**Depends on:** Phase 0 (checksum statics live on `Session`).

### 6. `libocrpc/Bin/Stream.vala` — `register` / `register_alias` note

**Why:** New bin aliases feed the checksum.

**Where:** end of `register` after `gtype_to_alias.set`; end of `register_alias` after `gtype_to_alias.set`.

#### Remove

```vala
		alias_to_gtype.set(alias, gtype);
		gtype_to_alias.set(gtype, alias);
	}

	/**
	 * Map an extra server GType to an alias already passed to
```

#### Replace with

```vala
		alias_to_gtype.set(alias, gtype);
		gtype_to_alias.set(gtype, alias);
		OLLMrpc.Transport.Session.note_checksum("bin:" + alias + ":" + gtype.name());
	}

	/**
	 * Map an extra server GType to an alias already passed to
```

#### Remove

```vala
		if (gtype_to_alias.has_key(gtype)) {
			throw new StreamError.REGISTRATION("duplicate register of type '%s'", gtype.name());
		}
		gtype_to_alias.set(gtype, alias);
	}
```

#### Replace with

```vala
		if (gtype_to_alias.has_key(gtype)) {
			throw new StreamError.REGISTRATION("duplicate register of type '%s'", gtype.name());
		}
		gtype_to_alias.set(gtype, alias);
		OLLMrpc.Transport.Session.note_checksum("bin-alias:" + alias + ":" + gtype.name());
	}
```

### 7. `libocrpc/Http/Route.vala` — `add` notes after insert

**Why:** New HTTP routes feed the checksum.

**Where:** end of `Http.add`, after `by_verb.get(verb).set(...)`.

#### Remove

```vala
			by_verb.get(verb).set(key, new Route() {
				method = method_name,
				wire_name = wire_name,
				handler = handler,
				request_type = request_type,
				response_type = response_type,
				variable = variable
			});
		}
```

#### Replace with

```vala
			by_verb.get(verb).set(key, new Route() {
				method = method_name,
				wire_name = wire_name,
				handler = handler,
				request_type = request_type,
				response_type = response_type,
				variable = variable
			});
			OLLMrpc.Transport.Session.note_checksum(
				"http:" + verb + ":" + key + ":" + method_name + ":"
				+ (variable ? "1" : "0") + ":"
				+ request_type.name() + ":" + response_type.name()
			);
		}
```

### 8. `libocrpc/Request.vala` — `add_class` notes new methods only

**Why:** New FFI method rows feed the checksum; overwrites of the same method do not.

**Where:** `add_class` loop body.

#### Remove

```vala
			var l = va_list();
			while (true) {
				var method = l.arg<string>();
				if (method == null) {
					break;
				}
				methods.get(name).set(method, l.arg<string>());
			}
		}
```

#### Replace with

```vala
			var l = va_list();
			while (true) {
				var method = l.arg<string>();
				if (method == null) {
					break;
				}
				var sig = l.arg<string>();
				var fresh = !methods.get(name).has_key(method);
				methods.get(name).set(method, sig);
				if (!fresh) {
					continue;
				}
				OLLMrpc.Transport.Session.note_checksum(
					"ffi:" + name + ":" + method + ":" + sig
				);
			}
		}
```

---

## Phase 2 — HTTP session table + headers (JSON `/rpc`)

### 9. `libocrpc/Transport/HttpServer.vala` — session + checksum on `on_rpc`

**Why:** Look up or create session, verify checksum, echo headers. `HttpReply` constructed with session — no bind.

**Where:** `on_rpc` — session lookup before reply construction; headers after reply exists.

**Depends on:** Phase 0, Phase 1.

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
			var client_sum = req_headers.get_one("X-rpc-checksum");
			var server_sum = Session.roll_checksum();
			if (client_sum != null && client_sum != "" && client_sum != server_sum) {
				msg.set_status(409, null);
				msg.set_response("text/plain", Soup.MemoryUse.COPY,
					"checksum mismatch".data);
				return;
			}
			var reply = new HttpReply(this.soup, msg, session) {
				live_handles = this.live_handles
			};
			var res_headers = msg.get_response_headers();
			res_headers.replace("X-rpc-session", session.id);
			res_headers.replace("X-rpc-checksum", server_sum);
			if (msg.get_method() != "POST") {
```

**ℹ️** No `session.sync(reply)` — `next_handle` and leases are on each {@link HttpReply} (per POST); only {@link Session.bin} name tables persist.

---

## Phase 3 — Bin POST (`application/octet-stream`)

### 10. `libocrpc/Transport/HttpReply.vala` — bin encode in `write`

**Why:** Mirror request Content-Type for responses.

**Where:** `HttpReply` — add `bin_body` flag; branch in `write`.

**Depends on:** Phase 0.

#### Add — property after `paused`

```vala
		/**
		 * True when the POST used ''application/octet-stream'' (bin reply).
		 */
		public bool bin_body { get; set; default = false; }
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
					var mem = new GLib.MemoryOutputStream.resizable();
					this.bin.out_stream = new GLib.DataOutputStream(mem);
					this.bin.write(serializable);
					this.bin.out_stream = null;
					this.msg.set_response(
						"application/octet-stream",
						Soup.MemoryUse.COPY,
						mem.steal_as_bytes().get_data()
					);
					this.msg.set_status(200, null);
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

### 11. `libocrpc/Transport/HttpServer.vala` — bin decode branch in `on_rpc`

**Why:** `Content-Type: application/octet-stream` → parse with `reply.session.bin`.

**Where:** `on_rpc` after POST check — branch before JSON parser.

**Depends on:** §9, §10.

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

## Phase 4 — Smoke test

### 12. `tests/rpc/http-bin-session-test.vala` — two POSTs + checksum

**Why:** Prove session name-table restore and checksum header.

**Where:** new test file; wire in `tests/meson.build` like `test-rpc-http-routes`.

**Depends on:** Phases 0–3.

#### Add

New executable smoke (outline — fill literals when implementing):

- Register Hello + types; note both client and server use same `rpc_register` order.
- `Session.roll_checksum()` once after register (or rely on first request).
- POST 1: `Content-Type: application/octet-stream`, no `X-rpc-session`; capture `X-rpc-session` + `X-rpc-checksum` from response.
- POST 2: same session + checksum; bin body that depends on a wire name learned in POST 1 (or second call that only works if JIT tables persist).
- Wrong checksum → expect `409`.
- Unknown session → expect `409`.

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

- **🔷** `⏳` Implement Phases 0–4 after approval.
- **🔷** `⏳` Typed HTTP routes (`on_route`) — optional shared session table later.
- **🔷** `⏳` Streaming resume + session (**8.2.3.1**) — fill fences later.
- **🚫** TLS / client certs — **8.2.3** / **8.2.7**.
- **🚫** Threaded workers; session LRU/OOM.
- **🚫** Rehash entire maps / body MD5 for `X-rpc-checksum`.
- **🚫** `Session.bind` / `Session.sync` / freestanding `Checksum` class.

---

## LLM notes

- **🚫** Do not start implementation until user approves these proposals.
- **ℹ️** `Session.note_checksum` / `Session.roll_checksum` / `Session.take` are **named in this plan** (allowed methods).
- **ℹ️** Parent **8.2.6** should reuse `Session` concepts long-term.
- **ℹ️** Checksum is registration language, not body integrity.
- **ℹ️** Phase 0 adds {@link Session} and {@link HttpReply.session} only — **no** {@link Connection} field moves; socket tests should be unchanged.
