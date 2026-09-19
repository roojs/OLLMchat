# 8.2.7 — TLS client certificate registration (pairing approval)

**Status:** **PROPOSED** — flow agreed in chat; no code proposals yet

> **Do not update `docs/plans/RPC-1.0-summary.md` for this plan.**

**Parent:** [`RPC-8.2-full-rpc-system.md`](RPC-8.2-full-rpc-system.md) — Phase 7

**Builds on:** [`done/RPC-8.2.3.5-DONE-https-server.md`](done/RPC-8.2.3.5-DONE-https-server.md) + [`done/RPC-8.2.3.6-DONE-https-client.md`](done/RPC-8.2.3.6-DONE-https-client.md) — HTTPS product-CA transport (no client certs yet)

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Purpose

- **🔷** Primary target: remote **file server** access from **Android** (not the OpenAI-compatible server).
- **🔷** Client presents **its own certificate** on connect (generated on device, kept on device).
- **🔷** Server gates RPC on the certificate:
  - **Registered** cert → full access.
  - **Unknown** cert → exactly **one** call allowed: **`request_registration`**; all other methods rejected.
- **🔷** **`request_registration`** registers the client's **IP against its certificate** as a pending request.
  - IP keys the **maximum** pending registrations (anti-spam on the pending store).
  - **Dropped on approval** — registered store is fingerprint-only (phones move between Wi-Fi / mobile networks, so the IP is never stable).
- **🔷** Rate limiting protects the pending store from filling up:
  - Max **3 pending requests per IP** — further requests from that IP are rejected.
  - Re-registering the **same certificate** is ignored — retries never consume slots.
  - Pending requests older than **24 hours** are pruned.
- **🔷** Pending + registered stores live in the daemon's **SQLite** database — not the filesystem.
- **🔷** Admin on the server (`ollmfilesd` command line): **list** pending requests, **accept** one ("accept #2") → cert becomes **registered**.
- **🔷** Later connections with that cert are accepted; cert identity feeds session reattach (parent Phase 6).
- **🔷** **Admin approval is the auth** — no server-issued certs, no CSR, no passwords / pairing codes (supersedes the earlier "server issues client cert" flow from parent Phase 7 / 8.2.3 Phases 5–6).
- **🔷** Production path sits **behind a reverse proxy** (nginx stream / PROXY Protocol).
  - Real client IP for pending registration comes from the PROXY header, not the proxy's loopback address.
- **🔷** File-daemon **listen** settings live on a nested **`filesd`** object in the existing config (`Config2` / `~/.config/ollmchat/config.2.json`) — hyphen keys in JSON, not a pile of CLI flags.
  - Nested type name: **`OLLMchat.Settings.Filesd`** (no `Config` suffix).
  - `unix` — **bool** (default on); config key reserved, **no listen behaviour change in this plan**.
  - `socket` / `https` — **`host:port` strings** (empty = off); `socket` is config-only for future; **this plan implements `https`**.
  - `proxy: true` — PROXY Protocol on the HTTPS listener (nginx relay).
  - `systemd: true` — install/enable the user unit from shipped resources on startup.
- **🔷** Daemon runs as a **user session** service (systemd user unit shipped in resources; opt-in via `filesd.systemd`).
- **🔷** Operator doc: [`docs/filesd-behind-nginx-proxy.md`](../filesd-behind-nginx-proxy.md) — how to run `ollmfilesd` behind nginx with PROXY Protocol.

---

## Current behaviour

- **ℹ️** HTTPS server + client done (product CA): `Transport.Cert`, `HttpServer.tls_certificate`, `HttpClient.tls_database`.
- **ℹ️** `TlsAuthenticationMode` default — server does not request a client cert today.
- **ℹ️** Session id over HTTP exists ([`done/RPC-8.2.3.2-DONE-http-bin-session.md`](done/RPC-8.2.3.2-DONE-http-bin-session.md)); no client identity bound to it.
- **ℹ️** `ollmfilesd` today listens Unix socket (default) **or** TCP bin (`--tcp`) — mutually exclusive via CLI; **`HttpServer` is not wired into the daemon yet** (HTTPS only in `tests/rpc/http-https-test.vala`).
- **ℹ️** Without PROXY Protocol, every connection behind nginx looks like `127.0.0.1` — pending IP rate limits would collapse to one bucket.

---

## Flow (conceptual)

1. Client generates / loads its own client cert (on device).
2. Client → TLS → (optional nginx stream with `proxy_protocol on`) → `ollmfilesd` HTTPS listen.
3. If proxy mode is on, daemon strips the PROXY v1 header and uses the advertised source IP as the client IP for registration.
4. Server looks up the cert fingerprint in the **registered** store:
   - Found → normal RPC dispatch.
   - Not found → dispatch **`request_registration`** only; reject everything else.
5. `request_registration` → append `(ip, cert fingerprint, time)` to the **pending** store:
   - Fingerprint already pending or registered → ignored (no new row).
   - IP already has 3 pending rows → rejected.
   - Pending rows older than 24 h are pruned.
6. Admin lists pending requests (`ollmfilesd` CLI) → approves one → fingerprint becomes **registered** (IP dropped).
7. Client reconnects with the same cert → accepted.

---

## Suggested order

1. Phase 0 — File-daemon listen config (Unix + HTTPS / PROXY) + user-session startup + nginx doc
2. Phase 1 — Registration gate + `request_registration`
3. Phase 2 — Admin approval surface → [`RPC-8.2.8`](RPC-8.2.8-filesd-connections-ui.md) / desktop UI [`8.2.8.1`](done/RPC-8.2.8.1-DONE-filesd-desktop-connections-ui.md)
4. Phase 3 — Cert → session identity

---

## Phase 0 — File-daemon listen config + PROXY relay + user-session startup

### Goal

- **🔷** `⏳` Wire **`HttpServer`** (HTTPS, product CA leaf) into **`ollmfilesd`** so remote Android can reach the file daemon.
- **🔷** `⏳` Listen configuration lives on a nested **`filesd`** / **`OLLMchat.Settings.Filesd`** object in **`Config2`**.
  - Defaults: `unix` `true`; `socket` / `https` `""`; `proxy` `false`; `systemd` `false`.
  - **This plan implements:** non-empty `https` → start HTTPS listen; `proxy: true` → PROXY Protocol strip; `systemd: true` → install/enable user unit from resources.
  - **Config-only for later (no listen changes here):** `unix`, `socket`.
  - JSON keys use **hyphens** where needed → Vala underscores.
  - **🚫** Do not add a long list of new CLI flags for this.
  - **🚫** No `https-unix` / HTTPS-on-Unix-path key.
  - **🚫** No `FilesdConfig` name — class is **`Filesd`**.
- **🔷** `⏳` When `filesd.proxy` is true: accept **PROXY Protocol v1** on the raw TCP socket **before** the TLS handshake bytes reach `Soup.Server`.
  - Parse `PROXY TCP4|TCP6 <src_ip> <dst_ip> <src_port> <dst_port>\r\n`.
  - Use `<src_ip>` as the real client IP for pending registration / rate limits.
  - Hand the remaining stream (ClientHello onward) to libsoup via `Soup.Server.accept_iostream`.
  - **Inline** into existing server accept path — **no** new `ProxyInputStream` / `ProxyIOStream` classes.
- **🔷** `⏳` `filesd.systemd: true` → ship a **systemd user unit** in **resources**, install it under the user systemd dir, and enable/start it (set up on boot of the daemon when that flag is on).
- **🔷** `⏳` Daemon runs under the **user session** (not system-wide root).
- **🔷** `⏳` Doc [`docs/filesd-behind-nginx-proxy.md`](../filesd-behind-nginx-proxy.md):
  - nginx `stream { … proxy_protocol on; }` example → local `filesd.https` address.
  - matching `config.2.json` `"filesd"` object.
  - `systemd: true` install behaviour.

### Notes

- **ℹ️** `ollmfilesd` already calls `this.load_config()` → `base_load_config()` → `Config2.load()` from `~/.config/ollmchat/config.2.json`.
- **ℹ️** Approach agreed in chat: custom `GSocketService` / `ThreadedSocketService` in front of `Soup.Server`; strip PROXY line on first read; then `accept_iostream` with the cleaned stream + real remote address.
- **ℹ️** nginx side is Layer-4 stream (not HTTP `proxy_pass`) — TLS stays end-to-end to `ollmfilesd` so client certs still reach the daemon.
- **ℹ️** Existing product CA leaf (`Transport.Cert`) stays the server identity — same as **8.2.3.5**.
- **🔷** Nested `Filesd` on `Config2` — JSON example:
  ```json
  "filesd": {
    "unix": true,
    "socket": "",
    "https": "127.0.0.1:8443",
    "proxy": true,
    "systemd": true
  }
  ```
  - Vala: `OLLMchat.Settings.Filesd` with `unix`, `socket`, `https`, `proxy`, `systemd`.
  - Defaults: `unix` `true`; `socket` / `https` `""`; `proxy` `false`; `systemd` `false`.
  - `https` — HTTPS listen as `host:port` (empty = off); implement in this plan.
  - `proxy: true` — PROXY Protocol v1 on that HTTPS listener.
  - `systemd: true` — install/enable user unit from resources.
  - `unix` / `socket` — present in config for future; **do not change** current Unix / `--tcp` listen behaviour in this plan.
- **🔷** PROXY strip / accept — **inline** in existing code; **no** new stream-wrapper classes.
- **🚫** `https-unix` / HTTPS Unix-path listen.
- **🚫** `FilesdConfig` naming.
- **🚫** Configurable leaf SAN / public hostname work in this plan — phone path is nginx → proxy → daemon on the VPN listen address; product CA leaf from **8.2.3.5** stays as-is.
- **⏳** Code proposals — later.

### Nginx sketch (for the doc)

```nginx
stream {
    server {
        listen 443;
        proxy_pass 127.0.0.1:8443;
        proxy_protocol on;
    }
}
```

---

## Phase 1 — Registration gate + `request_registration`

### Goal

- **🔷** `⏳` Client generates / loads **its own** client cert on device; presents it on every HTTPS connect.
- **🔷** `⏳` Server gates RPC dispatch on the peer cert fingerprint:
  - **Registered** → normal dispatch.
  - **Unknown** (or no cert) → only **`request_registration`** dispatches; all other methods rejected.
- **🔷** `⏳` `request_registration` appends `(ip, cert fingerprint, time)` to a **pending** store:
  - **🔷** `⏳` Duplicate fingerprint (already pending or registered) → ignored, no new row.
  - **🔷** `⏳` Max **3 pending rows per IP** — further requests rejected until one is approved or pruned.
  - **🔷** `⏳` Pending rows older than **24 hours** are deleted.
  - **🔷** `⏳` IP is the **PROXY-sourced** client address when `filesd.proxy` is true; otherwise the TCP peer address.

### Notes

- **🔷** `⏳` `TlsAuthenticationMode.REQUEST` on `Soup.Server` — handshake accepts any client cert; gating at RPC dispatch (handshake-level rejection would make registration impossible).
- **🔷** `⏳` Store key = SHA-256 fingerprint of the client cert (DER bytes from `GLib.TlsCertificate.certificate`).
- **🔷** `⏳` Stores live in the daemon's SQLite database (`files.sqlite`):
  - **ℹ️** Opened in `ollmfilesd/Application.vala` `initialize()` via `libocsqlite` (`SQ.Database`); tables created with `db.db.exec(...)` like existing daemon tables.
  - **🔷** `⏳` One table `client_cert` (`id` PK + **unique** `fingerprint`, int `status`, `ip`, `created`) — simpler than two stores.
  - **ℹ️** Status values locked in **8.2.8**: `0` pending, `1` approved, `-1` IP ban (flood control, not cert revoke).
  - **🔷** `⏳` Row type **`OLLMfilesd.ClientCert`** (same pattern as `FileDiffPart`) + **`ClientCert.init_db`**.
- **🔷** `⏳` Prune lazily: delete pending rows older than 24 h at daemon startup and on each `request_registration` — no timer needed.
- **🔷** `⏳` Client cert is **self-signed by construction** — generated on device; the product CA key never ships to clients and there is no CSR step. Server pins the fingerprint, so chain trust is irrelevant.
- **🔷** `⏳` Gate via **`protected virtual` `HttpServer.allow_rpc`** — default allows all (existing smokes unchanged). **`OLLMfilesd.Https`** subclasses and overrides with the SQLite registration check (no delegates / Func callbacks).
- **🔷** `⏳` Wire method: **`RPC-Daemon.request_registration`** (no args) on `ollmfilesd/Daemon.vala`.
- **ℹ️** Depends on Phase 0 for HTTPS listen + `filesd.proxy` real client IP on `HttpReply.client_ip`. Phase 1 still owns fingerprint fill + gate + store.
- **🚫** Delegate / `Func` / callback-property gate on `HttpServer` — not an acceptable pattern here.

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `libocrpc/Transport/HttpReply.vala` — client IP + cert fingerprint

**Why:** Gate and `request_registration` need the peer identity on the reply object.

**Where:** class body after `bin_body` property.

**Depends on:** none.

#### Add — properties for registration gate

```vala
		/**
		 * Client address for pending registration (PROXY-sourced when
		 * ''filesd.proxy'', else TCP peer). Empty when unknown.
		 */
		public string client_ip { get; set; default = ""; }

		/**
		 * SHA-256 hex of the TLS peer cert DER. Empty when no client cert.
		 */
		public string cert_fingerprint { get; set; default = ""; }
```

### 2. `libocrpc/Transport/HttpServer.vala` — REQUEST + fill identity + `allow_rpc`

**Why:** Request client certs; expose peer fingerprint / IP; let `ollmfilesd` override the gate without delegates.

**Where:** class members + `start()` + `on_rpc` / `on_route` before `request.dispatch()`.

**Depends on:** §1.

#### Add — virtual gate (after `tls_certificate`)

```vala
		/**
		 * Registration / auth gate before {@link OLLMrpc.Request.dispatch}.
		 *
		 * Return ''false'' when the request was already answered (rejected).
		 * Default allows all. Override in a subclass (e.g. {@link OLLMfilesd.Https}).
		 *
		 * @param reply HTTP reply for this POST (fingerprint / IP filled)
		 * @param request parsed request about to dispatch
		 * @return true to dispatch, false if already rejected
		 */
		protected virtual bool allow_rpc(HttpReply reply, OLLMrpc.Request request)
		{
			return true;
		}
```

#### Remove — `start()` listen block (TLS only)

```vala
			try {
				var opts = (Soup.ServerListenOptions) 0;
				if (this.tls_certificate != null) {
					this.soup.set_tls_certificate(this.tls_certificate);
					opts = Soup.ServerListenOptions.HTTPS;
				}
				this.soup.listen_local(this.port, opts);
			} catch (GLib.Error e) {
				GLib.warning("failed to start HTTP server on port %u: %s",
					this.port, e.message);
				return false;
			}
```

#### Replace with — REQUEST client certs when HTTPS

```vala
			try {
				var opts = (Soup.ServerListenOptions) 0;
				if (this.tls_certificate != null) {
					this.soup.set_tls_certificate(this.tls_certificate);
					this.soup.set_tls_auth_mode(GLib.TlsAuthenticationMode.REQUEST);
					opts = Soup.ServerListenOptions.HTTPS;
				}
				this.soup.listen_local(this.port, opts);
			} catch (GLib.Error e) {
				GLib.warning("failed to start HTTP server on port %u: %s",
					this.port, e.message);
				return false;
			}
```

#### Add — in `on_rpc`, after session header replaces, before POST check: fill fingerprint + IP

Placement: immediately after the `res_headers.replace("X-rpc-sequence", …)` lines and before `if (msg.get_method() != "POST")`.

```vala
			var peer = msg.get_tls_peer_certificate();
			if (peer != null) {
				var der = peer.certificate;
				reply.cert_fingerprint = GLib.Checksum.compute_for_data(
					GLib.ChecksumType.SHA256, der.data);
			}
			if (reply.client_ip == "") {
				var remote = msg.get_remote_address() as GLib.InetSocketAddress;
				if (remote != null) {
					reply.client_ip = remote.get_address().to_string();
				}
			}
```

#### Add — in `on_rpc`, immediately before `if (!request.dispatch())`

```vala
			if (!this.allow_rpc(reply, request)) {
				return;
			}
```

#### Add — same fill + `allow_rpc` in `on_route` before `if (!request.dispatch())`

Fill `reply.cert_fingerprint` / `reply.client_ip` the same way after `var reply = new HttpReply(...)` is created; call `this.allow_rpc` immediately before `request.dispatch()`.

**ℹ️** Phase 0 PROXY accept path must set `reply.client_ip` (or an equivalent on the iostream hand-off) **before** Soup builds the message when `filesd.proxy` is true — otherwise the TCP-peer fallback above sees `127.0.0.1`.

### 3. `libocrpc/Transport/HttpClient.vala` — present client cert

**Why:** Device/client must send its cert on every HTTPS connect.

**Where:** property next to `tls_database`; apply in `call()` when building the `Soup.Message`.

**Depends on:** none (server REQUEST from §2).

#### Add — property

```vala
		/**
		 * Client certificate to present (mTLS). Null → none.
		 */
		public GLib.TlsCertificate? tls_certificate { get; set; default = null; }
```

#### Add — in `call()`, after `var message = new Soup.Message(...)`, before headers

```vala
			if (this.tls_certificate != null) {
				message.set_tls_client_certificate(this.tls_certificate);
			}
```

**💩** `⏳` On-device cert mint/load (Android) — generate self-signed once, persist, assign to `HttpClient.tls_certificate`. Exact Android file path / API left for a follow-up proposal once the client entry point is chosen.

### 4. `ollmfilesd/ClientCert.vala` — new row type + table

**Why:** One SQLite table for pending + registered fingerprints.

**Where:** new file under `ollmfilesd/`.

**Depends on:** none.

#### Add — full file

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

namespace OLLMfilesd
{
	/**
	 * Client TLS certificate registration row (pending or registered).
	 *
	 * Keyed by SHA-256 fingerprint. ''ip'' is stored only while
	 * ''status'' is ''pending'' (rate-limit bucket); cleared on approve
	 * in Phase 2.
	 *
	 * == Example ==
	 *
	 * {{{
 * ClientCert.init_db(db);
 * var rows = new Gee.ArrayList<ClientCert>();
 * ClientCert.query(db).select("WHERE status = 'pending'", rows);
 * }}}
 */
	public class ClientCert : GLib.Object
	{
		public int64 id { get; set; default = 0; }
		public string fingerprint { get; set; default = ""; }
		public string status { get; set; default = ""; }
		public string ip { get; set; default = ""; }
		public int64 created { get; set; default = 0; }

		public static SQ.Query<ClientCert> query(SQ.Database db)
		{
			return new SQ.Query<ClientCert>(db, "client_cert");
		}

		/**
		 * Create ''client_cert'' and prune pending rows older than 24 h.
		 *
		 * @param db daemon ''files.sqlite''
		 */
		public static void init_db(SQ.Database db)
		{
			var errmsg = "";
			var create = "CREATE TABLE IF NOT EXISTS client_cert (" +
				"id INTEGER PRIMARY KEY, " +
				"fingerprint TEXT NOT NULL UNIQUE, " +
				"status TEXT NOT NULL DEFAULT '', " +
				"ip TEXT NOT NULL DEFAULT '', " +
				"created INT64 NOT NULL DEFAULT 0" +
				");";
			if (Sqlite.OK != db.db.exec(create, null, out errmsg)) {
				GLib.warning("Failed to create client_cert table: %s", db.db.errmsg());
			}
			var cutoff = new GLib.DateTime.now_utc().to_unix() - (24 * 60 * 60);
			if (Sqlite.OK != db.db.exec(
				"DELETE FROM client_cert WHERE status = 'pending' AND created < %lld".printf(cutoff),
				null, out errmsg)) {
				GLib.warning("Failed to prune client_cert: %s", db.db.errmsg());
			}
		}
	}
}
```

**ℹ️** `id` is for `SQ.Query.insert` (same as other daemon tables); uniqueness is on `fingerprint`.
### 5. `ollmfilesd/meson.build` — source

**Where:** `ollmfilesd_src` next to `'Daemon.vala',`.

#### Add

```meson
  'ClientCert.vala',
```

### 6. `ollmfilesd/ProjectManager.vala` — create table on open

**Why:** Same place as other `init_db` calls.

**Where:** `ProjectManager` constructor, after `FileDiffPart.init_db(this.db);`.

**Depends on:** §4.

#### Add

```vala
				ClientCert.init_db(this.db);
```

### 7. `ollmfilesd/Daemon.vala` — `request_registration`

**Why:** Only allowed RPC for unknown certs; writes pending row with IP rate limit.

**Where:** `rpc_register` method list + new method on `Daemon`.

**Depends on:** §1, §4.

#### Remove — `rpc_register` add_class list

```vala
			OLLMrpc.Request.add_class(
				"RPC-Daemon", typeof(Daemon),
				"hello", "is",
				"shutdown", ""
			);
```

#### Replace with — register `request_registration`

```vala
			OLLMrpc.Request.add_class(
				"RPC-Daemon", typeof(Daemon),
				"hello", "is",
				"shutdown", "",
				"request_registration", ""
			);
```

#### Add — method (after `shutdown`)

```vala
		/**
		 * Record this connection's client cert as pending registration.
		 *
		 * Duplicate fingerprint (pending or registered) is ignored.
		 * Max three pending rows per IP; older-than-24h pending rows pruned first.
		 *
		 * @param request inbound RPC (connection must be {@link OLLMrpc.Transport.HttpReply})
		 */
		public void request_registration(OLLMrpc.Request request)
		{
			var reply = request.connection as OLLMrpc.Transport.HttpReply;
			if (reply == null) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
						"HTTPS registration only"
					)
				});
				return;
			}
			if (reply.cert_fingerprint == "") {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
						"client certificate required"
					)
				});
				return;
			}
			var db = this.app.project_manager.db;
			var cutoff = new GLib.DateTime.now_utc().to_unix() - (24 * 60 * 60);
			var errmsg = "";
			db.db.exec(
				"DELETE FROM client_cert WHERE status = 'pending' AND created < %lld".printf(cutoff),
				null, out errmsg);
			var existing = new Gee.ArrayList<ClientCert>();
			ClientCert.query(db).select(
				"WHERE fingerprint = '%s'".printf(
					reply.cert_fingerprint.replace("'", "''")),
				existing);
			if (existing.size > 0) {
				request.reply(new OLLMrpc.Response() {
					msg = "ok"
				});
				return;
			}
			var by_ip = new Gee.ArrayList<ClientCert>();
			ClientCert.query(db).select(
				"WHERE status = 'pending' AND ip = '%s'".printf(
					reply.client_ip.replace("'", "''")),
				by_ip);
			if (by_ip.size >= 3) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
						"too many pending registrations for this IP"
					)
				});
				return;
			}
			var row = new ClientCert() {
				fingerprint = reply.cert_fingerprint,
				status = "pending",
				ip = reply.client_ip,
				created = new GLib.DateTime.now_utc().to_unix()
			};
			ClientCert.query(db).insert(row);
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
		}
```

### 8. `ollmfilesd/Https.vala` — override `allow_rpc`

**Why:** Registration check lives in the daemon (SQLite), not a callback into libocrpc.

**Where:** new file; Phase 0 constructs **`new OLLMfilesd.Https(...)`** instead of bare `HttpServer`.

**Depends on:** §2; §4; Phase 0 HTTPS listen.

#### Add — full file

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

namespace OLLMfilesd
{
	/**
	 * HTTPS RPC server with client-cert registration gate.
	 *
	 * Extends {@link OLLMrpc.Transport.HttpServer}. Unknown certs may only
	 * call {@link Daemon.request_registration}; registered certs pass through.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var http = new OLLMfilesd.Https(8443, app);
	 * http.tls_certificate = cert.certificate;
	 * http.start();
	 * }}}
	 */
	public class Https : OLLMrpc.Transport.HttpServer
	{
		public OllmfilesdApplication app { get; private set; }

		public Https(uint port, OllmfilesdApplication app)
		{
			base(port);
			this.app = app;
		}

		protected override bool allow_rpc(
			OLLMrpc.Transport.HttpReply reply,
			OLLMrpc.Request request
		) {
			if (request.method == "RPC-Daemon.request_registration") {
				return true;
			}
			if (reply.cert_fingerprint == "") {
				reply.write(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
						"client certificate required"
					)
				});
				return false;
			}
			var rows = new Gee.ArrayList<ClientCert>();
			ClientCert.query(this.app.project_manager.db).select(
				"WHERE fingerprint = '%s' AND status = 'registered'".printf(
					reply.cert_fingerprint.replace("'", "''")),
				rows);
			if (rows.size > 0) {
				return true;
			}
			reply.write(new OLLMrpc.Response() {
				id = request.id,
				error = new OLLMrpc.Error(
					(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
					"certificate not registered"
				)
			});
			return false;
		}
	}
}
```

#### Add — `ollmfilesd/meson.build` source next to `'Daemon.vala',`

```meson
  'Https.vala',
```

**ℹ️** Phase 0 listen wiring uses `new OLLMfilesd.Https(port, this)` (not `new HttpServer`).

### 9. Smoke (extend HTTPS test) — register gate happy path later

**Why:** Prove REQUEST + fingerprint path; full pending/approve covered when Phase 2 lands.

**Where:** `tests/rpc/http-https-test.vala` (or a new `test-rpc-client-cert` once Phase 0 wires daemon HTTPS).

**💩** `⏳` Minimal smoke: mint a throwaway client cert, set `HttpClient.tls_certificate`, call a method, assert server sees fingerprint (or `request_registration` against a temp DB). Exact harness after Phase 0 HTTPS-on-daemon exists.

---

## Phase 2 — Admin approval surface

### Goal

- **🔷** `⏳` Admin approval moves to the **Connections** UI — see [`RPC-8.2.8`](RPC-8.2.8-filesd-connections-ui.md) → [`8.2.8.1`](done/RPC-8.2.8.1-DONE-filesd-desktop-connections-ui.md).
  - Desktop preferences dialog: **one** pending at a time as a banner (like download progress); Accept / Reject / Ban; clear → next latest.
  - Registered clients as expand/remove rows on Connections.
  - Ban blocks IP from re-registering; no unban.
- **🚫** CLI `list` / `accept` / `reset` as the primary admin surface — superseded by **8.2.8**.
- **🚫** “Reset all registered” as the only revoke path — **8.2.8** adds per-client Remove on the Connections row (confirm in that plan).

### Notes

- **ℹ️** Full UI + Android file-connection work lives in **8.2.8**.
- **⏳** Code proposals — in **8.2.8** after design sign-off.

---

## Phase 3 — Cert → session identity

### Goal

- **🔷** `⏳` Registered fingerprint maps to a stable **client identity** for session reattach (parent Phase 6).
- **🔷** `⏳` Reconnect with the same cert resumes identity — no re-registration, no auth repeat.

### Notes

- **⏳** Code proposals — later.

---

## LLM notes

- **ℹ️** Split out of [`done/RPC-8.2.3-DONE-http-server-rpc.md`](done/RPC-8.2.3-DONE-http-server-rpc.md) Phases 5–6 — HTTP server is complete; this is an add-on feature.
- **ℹ️** Phase 0 added from chat: relay behind nginx + PROXY Protocol + user-session daemon + operator doc.
- **ℹ️** Listen settings → `Config2.filesd` / `OLLMchat.Settings.Filesd`: `unix`, `socket`, `https`, `proxy`, `systemd`. This plan implements `https` + `proxy` + `systemd` install; `unix` / `socket` are future-facing config only.
- **ℹ️** PROXY handling inlined — no `ProxyInputStream` / `ProxyIOStream` classes.
- **🚫** Public CA / Let's Encrypt — server identity stays on the product CA (**8.2.3.5**).
- **🚫** Configurable leaf SAN / “public hostname” work — out of scope; path is phone → nginx → proxy → VPN listen port.
- **🚫** Server-issued client certs / CSR flow — superseded by the approval model.
- **🚫** File-based pending / registered stores (e.g. under `~/.local/share/ollmchat/`) — user vetoed; SQLite only, files are messy to clean up.
- **🚫** Delegate / `Func` / callback-property gate on `HttpServer` — use virtual `allow_rpc` + `OLLMfilesd.Https` override instead.
- **💩** `⏳` TLS wrapper on `TcpListen` / socket `Client` (bin socket track) — only if socket RPC goes remote; HTTP track first.
