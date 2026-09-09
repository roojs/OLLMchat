# 8.2.3.2 — HTTP binary RPC + session id

**Status:** **PROPOSED** — code proposals filled; implement after user approval

> **Do not update `docs/plans/RPC-1.0-summary.md` for this plan.**

**Parent:** [`RPC-8.2.3-http-server-rpc.md`](RPC-8.2.3-http-server-rpc.md)

**Depends on:** [`RPC-8.2.3.3-http-path-type-registration.md`](RPC-8.2.3.3-http-path-type-registration.md) route/type shape ✅; [`RPC-8.2.3.1-http-json-streaming.md`](RPC-8.2.3.1-http-json-streaming.md) preferred stable first

**Related:** Parent **8.2** Phase 6 session resumption; [`docs/bin-rpc-protocol.md`](../bin-rpc-protocol.md)

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Purpose

- **🔷** Accept **bin** RPC request bodies over HTTP (same `Request` / `Response` / `Notification` objects as the socket).
- **🔷** Because HTTP is sessionless, carry a **session id** so the server can restore JIT type maps / lease tables across POSTs.
- **🔷** Carry a **registry checksum** with the session so both ends know they share the same registration “language”.
- **🔷** Keep main-loop-only concurrency (no threading MPM).

---

## Why sessions

- **ℹ️** Socket `Connection` holds `Bin.Stream` name tables, leases, and live handles for the peer lifetime.
- **🔷** Each HTTP POST is a new `HttpReply` today — maps would reset every call without a session.
- **🔷** JSON auto mode needs fewer JIT maps; **bin** needs them — session is required before bin is useful.

---

## Design (outline)

### Content types

- **🔷** Request bin body: `Content-Type: application/octet-stream` → bin decode path in `HttpServer.on_rpc`.
- **🔷** JSON path stays `application/json` (Phase 1 / **8.2.3.1**).
- **🔷** Response: mirror request (octet-stream for bin; JSON for JSON).
- **🚫** Custom `application/x-ollmrpc-bin`.

### Session id

- **🔷** Wire header: `X-rpc-session: <id>` on request; echo on response.
- **🚫** `X-OLLMrpc-Session` / OLLM-prefixed header names.
- **🔷** Assign at first call when the header is omitted.
- **🔷** Server table: session id → in-memory state (stream name maps, leases).
- **🔷** Unknown session → HTTP `409` + plain text.
- **🚫** Session-table OOM / LRU (v1 skip).

### Registry checksum

- **🔷** Header: `X-rpc-checksum: <32-char lowercase hex MD5>`.
- **🔷** Mismatch → HTTP `409` + plain text.
- **🔷** **New key** = newly inserted registration-map entry only.
- **🔷** Pending buffer of key strings; **≤1 MD5 per request** via `Checksum.roll()`.
- **🔷** `checksum = md5(old_hex + pending)`; no pending → unchanged.
- **🔷** Pending keys joined with `'\n'`.
- **🔷** Feeds: `Bin.register` / `register_alias`, `Http.add`, new `Request.add_class` method rows.
- **🔷** Idempotent / thrown duplicate → no pending append.
- **🚫** Rehash whole maps; hash HTTP bodies for this header.

### Named APIs (this plan)

- **🔷** `OLLMrpc.Checksum` — `note(string key)`, `roll()` → hex string.
- **🔷** `OLLMrpc.Transport.Session` — `id`, long-lived `bin` + lease maps; static `by_id`.

---

## Suggested implement order

1. `Checksum` + hooks in `Bin` / `Http` / `Request.add_class`.
2. `Session` + `X-rpc-session` / `X-rpc-checksum` on `/rpc` (JSON first).
3. Bin POST (`application/octet-stream`) on `/rpc`.
4. Smoke: two POSTs, shared session, JIT name survives; checksum match.
5. Streaming resume (with **8.2.3.1**) — later fill.

---

## Phase 1 — Rolling MD5 registry checksum

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `libocrpc/Checksum.vala` — new file: pending keys + `roll`

**Why:** One place for registry fingerprint; ≤1 MD5 when `roll()` runs.

**Where:** new file under `libocrpc/`.

**Depends on:** none.

#### Add

New file `libocrpc/Checksum.vala` (entire contents):

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

namespace OLLMrpc
{
	/**
	 * Rolling MD5 of process-wide registration map inserts.
	 *
	 * Call {@link note} after each successful new map entry.
	 * Call {@link roll} at most once per HTTP request (or when
	 * reading ''X-rpc-checksum'') — hashes only pending keys.
	 *
	 * == Example ==
	 *
	 * {{{
	 * OLLMrpc.Checksum.note("bin:Alarm:RpcDummyAlarmAlarm");
	 * var hex = OLLMrpc.Checksum.roll();
	 * }}}
	 */
	public class Checksum : GLib.Object
	{
		/** Current hex digest (empty before first {@link roll} with pending). */
		public static string value { get; private set; default = ""; }

		private static string pending = "";

		/**
		 * Queue one new registration key for the next {@link roll}.
		 *
		 * Keys are joined with ''\\n''. Does not MD5.
		 *
		 * @param key canonical insert string (e.g. bin:Alias:TypeName)
		 */
		public static void note(string key)
		{
			if (pending == "") {
				pending = key;
				return;
			}
			pending = pending + "\n" + key;
		}

		/**
		 * Apply at most one MD5: ''md5(value + pending)'' when pending
		 * is non-empty; otherwise return {@link value} unchanged.
		 *
		 * @return lowercase hex MD5 string
		 */
		public static string roll()
		{
			if (pending == "") {
				return value;
			}
			var sum = new GLib.Checksum(GLib.ChecksumType.MD5);
			sum.update(value.data);
			sum.update(pending.data);
			value = sum.get_string();
			pending = "";
			return value;
		}
	}
}
```

### 2. `libocrpc/meson.build` — compile `Checksum.vala`

**Why:** Wire new source into `ocrpc`.

**Where:** `ocrpc_core_src` list, after `'RpcErrorCode.vala',`.

**Depends on:** §1.

#### Add — after `'RpcErrorCode.vala',` in `ocrpc_core_src`

```meson
  'Checksum.vala',
```

### 3. `docs/meson.build` — valadoc input

**Why:** Valadoc lists every public `.vala`.

**Where:** near other `libocrpc` inputs (after `Http/Route.vala`).

**Depends on:** §1.

#### Add

```meson
    '../libocrpc/Checksum.vala',
```

### 4. `libocrpc/Bin/Stream.vala` — `register` / `register_alias` note

**Why:** New bin aliases feed the checksum.

**Where:** end of `register` after `gtype_to_alias.set`; end of `register_alias` after `gtype_to_alias.set`.

**Depends on:** §1.

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
		OLLMrpc.Checksum.note("bin:" + alias + ":" + gtype.name());
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
		OLLMrpc.Checksum.note("bin-alias:" + alias + ":" + gtype.name());
	}
```

### 5. `libocrpc/Http/Route.vala` — `add` notes after insert

**Why:** New HTTP routes feed the checksum.

**Where:** end of `Http.add`, after `by_verb.get(verb).set(...)`.

**Depends on:** §1.

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
			OLLMrpc.Checksum.note(
				"http:" + verb + ":" + key + ":" + method_name + ":"
				+ (variable ? "1" : "0") + ":"
				+ request_type.name() + ":" + response_type.name()
			);
		}
```

### 6. `libocrpc/Request.vala` — `add_class` notes new methods only

**Why:** New FFI method rows feed the checksum; overwrites of the same method do not.

**Where:** `add_class` loop body.

**Depends on:** §1.

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
				OLLMrpc.Checksum.note(
					"ffi:" + name + ":" + method + ":" + sig
				);
			}
		}
```

---

## Phase 2 — Session table + headers (JSON `/rpc`)

### 7. `libocrpc/Transport/Session.vala` — new file

**Why:** Long-lived JIT name tables + leases across POSTs.

**Where:** new file under `libocrpc/Transport/`.

**Depends on:** none (Phase 1 optional for smoke).

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
	 * HTTP RPC session — restores bin name tables and leases across POSTs.
	 *
	 * Look up by ''X-rpc-session''. Missing id creates a new session.
	 * Bind onto each {@link HttpReply} before {@link OLLMrpc.Request.dispatch}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var session = OLLMrpc.Transport.Session.take("");
	 * session.bind(reply);
	 * }}}
	 */
	public class Session : GLib.Object
	{
		/** Opaque session id (echoed on ''X-rpc-session''). */
		public string id { get; set; default = ""; }

		/**
		 * Long-lived bin codec (name tables). I/O streams set per POST.
		 */
		public Bin.Stream bin {
			get; set; default = new Bin.Stream(null, null) {
				is_server = true
			};
		}

		public Gee.HashMap<int, GLib.Object> leases {
			get; set; default = new Gee.HashMap<int, GLib.Object>();
		}

		public Gee.HashMap<int, uint> floors {
			get; set; default = new Gee.HashMap<int, uint>();
		}

		public Gee.HashMap<int, uint> extras {
			get; set; default = new Gee.HashMap<int, uint>();
		}

		public Gee.HashMap<int, Gee.HashMap<int, int>> lease_ids {
			get; set; default = new Gee.HashMap<int, Gee.HashMap<int, int>>();
		}

		public Gee.HashMap<int, Gee.HashMap<string, OLLMrpc.Live.Subscription>> signal_subs {
			get; set; default = new Gee.HashMap<int, Gee.HashMap<string, OLLMrpc.Live.Subscription>>();
		}

		public Gee.HashMap<int, OLLMrpc.Live.Hook> callbacks {
			get; set; default = new Gee.HashMap<int, OLLMrpc.Live.Hook>();
		}

		public int next_handle { get; set; default = 1; }

		internal static Gee.HashMap<string, Session> by_id;

		private static uint next_id = 1;

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

		/**
		 * Attach this session’s maps and bin stream to one HTTP reply.
		 *
		 * @param reply per-POST write target
		 */
		public void bind(HttpReply reply)
		{
			reply.bin = this.bin;
			reply.leases = this.leases;
			reply.floors = this.floors;
			reply.extras = this.extras;
			reply.lease_ids = this.lease_ids;
			reply.signal_subs = this.signal_subs;
			reply.callbacks = this.callbacks;
			reply.next_handle = this.next_handle;
			this.bin.connection = reply;
		}

		/**
		 * Copy handle counter back after dispatch.
		 *
		 * @param reply finished or paused reply
		 */
		public void sync(HttpReply reply)
		{
			this.next_handle = reply.next_handle;
		}
	}
}
```

### 8. `libocrpc/meson.build` + `docs/meson.build` — Session source

**Why:** Compile + valadoc.

**Where:** `ocrpc_core_src` after `HttpServer.vala`; docs list after `HttpServer.vala`.

**Depends on:** §7.

#### Add — meson `ocrpc_core_src`

```meson
  'Transport/Session.vala',
```

#### Add — `docs/meson.build` valadoc inputs

```meson
    '../libocrpc/Transport/Session.vala',
```

### 9. `libocrpc/Transport/HttpServer.vala` — session + checksum on `on_rpc`

**Why:** Create/lookup session, roll checksum, set response headers; reject mismatch / unknown session.

**Where:** start of `on_rpc`, after creating `reply`, before method/body handling.

**Depends on:** §1, §7.

#### Add — immediately after `var reply = new HttpReply(...) { ... };` in `on_rpc`

Purpose: bind session, verify checksum, echo headers. Before POST check.

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
			session.bind(reply);
			var client_sum = req_headers.get_one("X-rpc-checksum");
			var server_sum = OLLMrpc.Checksum.roll();
			if (client_sum != null && client_sum != "" && client_sum != server_sum) {
				msg.set_status(409, null);
				msg.set_response("text/plain", Soup.MemoryUse.COPY,
					"checksum mismatch".data);
				return;
			}
			var res_headers = msg.get_response_headers();
			res_headers.replace("X-rpc-session", session.id);
			res_headers.replace("X-rpc-checksum", server_sum);
```

#### Add — before each successful return path that finishes dispatch (and after pause setup)

Purpose: sync `next_handle` back to session. After `request.dispatch()` block / pause block at end of `on_rpc`:

```vala
			session.sync(reply);
```

**ℹ️** Implementer: keep `session` in scope for the whole `on_rpc` (declare before early returns that still need it only when bind succeeded).

---

## Phase 3 — Bin POST (`application/octet-stream`)

### 10. `libocrpc/Transport/HttpReply.vala` — bin encode in `write`

**Why:** Mirror request Content-Type for responses.

**Where:** `HttpReply` — add `bin_body` flag; branch in `write`.

**Depends on:** §7.

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

**Why:** `Content-Type: application/octet-stream` → parse with session `bin`.

**Where:** `on_rpc` after session bind / POST check — branch before JSON parser.

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
				session.bin.in_stream = new GLib.DataInputStream(
					new GLib.MemoryInputStream.from_bytes(bytes)
				);
				session.bin.mode = Bin.Mode.EXPLICIT;
				Bin.Serializable parsed;
				try {
					parsed = session.bin.parse();
				} catch (GLib.Error e) {
					reply.write(new Response() {
						error = new OLLMrpc.Error(
							(int) OLLMrpc.RpcErrorCode.PARSE_ERROR,
							"invalid bin: " + e.message
						)
					});
					msg.set_status(400, null);
					session.sync(reply);
					return;
				}
				session.bin.in_stream = null;
				request = parsed as OLLMrpc.Request;
				if (request == null) {
					reply.write(new Response() {
						error = new OLLMrpc.Error(
							(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
							"body did not decode to a Request"
						)
					});
					msg.set_status(400, null);
					session.sync(reply);
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

**Depends on:** Phases 1–3.

#### Add

New executable smoke (outline — fill literals when implementing):

- Register Hello + types; note both client and server use same `rpc_register` order.
- `Checksum.roll()` once after register (or rely on first request).
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

- **🔷** `⏳` Implement Phases 1–4 after approval.
- **🔷** `⏳` Streaming resume + session (**8.2.3.1**) — fill fences later.
- **🚫** TLS / client certs — **8.2.3** / **8.2.7**.
- **🚫** Threaded workers; session LRU/OOM.
- **🚫** Rehash entire maps / body MD5 for `X-rpc-checksum`.

---

## LLM notes

- **🚫** Do not start implementation until user approves these proposals.
- **ℹ️** `Checksum.note` / `Checksum.roll` and `Session.take` / `bind` / `sync` are **named in this plan** (allowed methods).
- **ℹ️** Parent **8.2.6** should reuse `Session` concepts long-term.
- **ℹ️** Checksum is registration language, not body integrity.
