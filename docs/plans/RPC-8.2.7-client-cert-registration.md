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
- **🔷** Rate limiting protects the pending store from filling up:
  - Max **3 pending requests per IP** — further requests from that IP are rejected.
  - Re-registering the **same certificate** is ignored — retries never consume slots.
  - Pending requests older than **24 hours** are pruned.
- **🔷** Pending + registered stores live in the daemon's **SQLite** database — not the filesystem.
- **🔷** Admin on the server (`ollmfilesd` command line): **list** pending requests, **accept** one ("accept #2") → cert becomes **registered**.
- **🔷** Later connections with that cert are accepted; cert identity feeds session reattach (parent Phase 6).
- **🔷** **Admin approval is the auth** — no server-issued certs, no CSR, no passwords / pairing codes (supersedes the earlier "server issues client cert" flow from parent Phase 7 / 8.2.3 Phases 5–6).

---

## Current behaviour

- **ℹ️** HTTPS server + client done (product CA): `Transport.Cert`, `HttpServer.tls_certificate`, `HttpClient.tls_database`.
- **ℹ️** `TlsAuthenticationMode` default — server does not request a client cert today.
- **ℹ️** Session id over HTTP exists ([`done/RPC-8.2.3.2-DONE-http-bin-session.md`](done/RPC-8.2.3.2-DONE-http-bin-session.md)); no client identity bound to it.

---

## Flow (conceptual)

1. Client generates / loads its own client cert (on device).
2. Client → TLS → server, presents the client cert.
3. Server looks up the cert fingerprint in the **registered** store:
   - Found → normal RPC dispatch.
   - Not found → dispatch **`request_registration`** only; reject everything else.
4. `request_registration` → append `(ip, cert fingerprint, time)` to the **pending** store:
   - Fingerprint already pending or registered → ignored (no new row).
   - IP already has 3 pending rows → rejected.
   - Pending rows older than 24 h are pruned.
5. Admin lists pending requests (`ollmfilesd` CLI) → approves one → fingerprint becomes **registered**.
6. Client reconnects with the same cert → accepted.

---

## Suggested order

1. Phase 1 — Registration gate + `request_registration`
2. Phase 2 — Admin approval surface
3. Phase 3 — Cert → session identity

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

### Notes

- **💩** `⏳` `TlsAuthenticationMode.REQUEST` on `Soup.Server` — handshake accepts any client cert; gating at RPC dispatch (handshake-level rejection would make registration impossible).
- **💩** `⏳` Store key = SHA-256 fingerprint of the client cert.
- **🔷** `⏳` Stores live in the daemon's SQLite database (`files.sqlite`):
  - **ℹ️** Opened in `ollmfilesd/Application.vala` `initialize()` via `libocsqlite` (`SQ.Database`); tables created with `db.db.exec(...)` like existing daemon tables.
  - **💩** `⏳` One table keyed by fingerprint with a `status` (`pending` / `registered`) column — simpler than two stores.
- **💩** `⏳` Prune lazily: delete pending rows older than 24 h at daemon startup and on each `request_registration` — no timer needed.
- **💩** `⏳` IP in the pending record is informational for the admin (NAT etc.) — the fingerprint is the identity.
- **💩** `⏳` Client cert may be self-signed — server pins the fingerprint; CA signing adds nothing (product CA key is in-repo).
- **⏳** Code proposals — later.

---

## Phase 2 — Admin approval surface

### Goal

- **🔷** `⏳` `ollmfilesd` command line: list pending registration requests (ip, fingerprint, time).
- **🔷** `⏳` `ollmfilesd` command line: accept one by number → fingerprint becomes **registered**.

### Notes

- **🔷** `⏳` Admin surface = **`ollmfilesd` CLI** — new options on the existing `command_line` handler:
  - **ℹ️** `ollmfilesd/Application.vala` — `command_line()` + `app_options`.
- **💩** `⏳` Revocation = remove fingerprint from the registered store (client must re-register) — v2 if needed.
- **⏳** Code proposals — later.

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
- **🚫** Public CA / Let's Encrypt — server identity stays on the product CA (**8.2.3.5**).
- **🚫** Server-issued client certs / CSR flow — superseded by the approval model.
- **🚫** File-based pending / registered stores (e.g. under `~/.local/share/ollmchat/`) — user vetoed; SQLite only, files are messy to clean up.
- **💩** `⏳` TLS wrapper on `TcpListen` / socket `Client` (bin socket track) — only if socket RPC goes remote; HTTP track first.
