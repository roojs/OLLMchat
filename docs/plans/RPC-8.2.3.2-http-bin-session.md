# 8.2.3.2 — HTTP binary RPC + session id

**Status:** **PROPOSED** — goals + design outline; code proposals after **8.2.3.1**

> **Do not update `docs/plans/RPC-1.0-summary.md` for this plan.**

**Parent:** [`RPC-8.2.3-http-server-rpc.md`](RPC-8.2.3-http-server-rpc.md)

**Depends on:** [`RPC-8.2.3.3-http-path-type-registration.md`](RPC-8.2.3.3-http-path-type-registration.md) route/type shape ✅; [`RPC-8.2.3.1-http-json-streaming.md`](RPC-8.2.3.1-http-json-streaming.md) preferred stable first

**Related:** Parent **8.2** Phase 6 session resumption; [`docs/bin-rpc-protocol.md`](../bin-rpc-protocol.md)

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Purpose

- **🔷** Accept **bin** RPC request bodies over HTTP (same `Request` / `Response` / `Notification` objects as the socket).
- **🔷** Because HTTP is sessionless, carry a **session id** so the server can restore JIT type maps / lease tables across POSTs.
- **🔷** Keep main-loop-only concurrency (no threading MPM).

---

## Why sessions

- **ℹ️** Socket `Connection` holds `Bin.Stream` name tables, leases, and live handles for the peer lifetime.
- **🔷** Each HTTP POST is a new `HttpReply` today — maps would reset every call without a session.
- **🔷** JSON auto mode needs fewer JIT maps; **bin** needs them — session is required before bin is useful.

---

## Design (outline)

### Content types

- **💩** Request: `Content-Type: application/x-ollmrpc-bin` (or `application/octet-stream`) → bin decode path in `HttpServer.on_rpc`.
- **💩** JSON path stays `application/json` (Phase 1 / **8.2.3.1**).
- **💩** Response: mirror request (bin reply for bin request; JSON for JSON), unless negotiated later.

### Session id

- **🔷** Assign at first authenticated/`Daemon.hello`-style call when omitted.
- **💩** Wire: HTTP header `X-OLLMrpc-Session: <id>` on request; echo on response. (Alternative: field on hello — pick one in code proposals.)
- **🔷** Server table: session id → in-memory state (stream name maps, leases, optional pause/stream resume hooks from **8.2.3.1**).
- **🔷** Unknown / expired session → HTTP `401`/`409` + plain-text message (status-driven, same as Phase 1 transport errors).

### HttpReply / session binding

- **🔷** Look up or create session before `dispatch`; attach state to the `HttpReply` / underlying `Connection` maps so `write`/`export` behave like a long-lived socket connection for that session.
- **ℹ️** Align naming with parent Phase 6 (`Session.resume`, TTL, cleanup) when filling proposals.

### Streaming + session

- **ℹ️** Dropped NDJSON streams may resume using the same session id (**8.2.3.1** + this plan). Exact resume handshake — fill when both plans are further along.

---

## Suggested implement order (this plan)

1. Session table + header on JSON unary (prove restore without bin).
2. Bin POST decode/encode on `/rpc`.
3. Smoke: two POSTs sharing session; second uses a JIT type registered on the first.
4. Wire session into streaming finish/resume (with **8.2.3.1**).

---

## Backlog

- **🔷** `⏳` Full **Remove** / **Replace with** / **Add** fences after **8.2.3.1** framing is ✅.
- **🔷** `⏳` Header vs hello-field decision promoted from **💩** → **🔷**.
- **🚫** TLS / client certs — still **8.2.3** later phases / **8.2.7**.
- **🚫** Threaded workers.

---

## LLM notes

- **🚫** Do not start implementation until code proposals are filled and user-approved.
- **ℹ️** Parent sub-plan **8.2.6** (socket session) should share concepts; avoid two divergent session tables long-term.
