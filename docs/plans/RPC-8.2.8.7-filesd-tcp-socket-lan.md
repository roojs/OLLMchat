# 8.2.8.7 — File-daemon TCP socket on the LAN (TLS + registration)

**Status:** **PROPOSED** — design only; code proposals not yet written

> **Do not update** `docs/plans/RPC-1.0-summary.md` **for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](RPC-8.2.8-filesd-connections-ui.md)

**Depends on:**

- [`RPC-8.2.7-client-cert-registration.md`](RPC-8.2.7-client-cert-registration.md) — `filesd.socket` reserved; HTTPS registration already in tree
- [`done/RPC-8.2.8.3-DONE-filesd-file-server-tls.md`](done/RPC-8.2.8.3-DONE-filesd-file-server-tls.md) — File Server expander is HTTPS host/port/proxy/systemd
- **Windows loopback port** is a **bug**, not this plan: [`docs/bugs/2026-09-20-filesd-windows-socket-port.md`](../bugs/2026-09-20-filesd-windows-socket-port.md)

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Purpose

- 🔷 Bind the **bin TCP** listener from `filesd.socket` (`host:port`), the same way HTTPS is bound from `filesd.https`.
- 🔷 Linux: `filesd.socket` empty or port **0** → **do not** bind TCP; the **Unix** socket stays the local app path (`filesd.unix`).
- 🔷 Opening that TCP socket on a **LAN interface** (not only loopback) needs **TLS + client-certificate registration**, the same idea as the HTTPS file server.
- 🔷 LAN only. This path is **not** for the public internet: no nginx PROXY, no WAN registration, no reverse-proxy IP rewrite.
- ℹ️ HTTPS remains the internet / proxy path ([`docs/filesd-behind-nginx-proxy.md`](../filesd-behind-nginx-proxy.md)).
- ⏳ Design in this file. Code fences after the TLS-on-bin-TCP shape is agreed.

---

## Current behaviour

- ℹ️ `Config2.filesd.unix` (bool, default on) and `filesd.socket` (`host:port`, default empty) are **config-only**. `ollmfilesd` never starts `TcpListen` from `filesd.socket`.
- ℹ️ Linux daemon: Unix `SocketListen` unless CLI `--tcp` / `--tcp-host` / `--tcp-port`. HTTPS is a **second** listener from `filesd.https`.
- ℹ️ `TcpListen` is **plaintext** bin RPC. Docblock already says a public bind needs an authenticated transport first (`libocrpc/Transport/TcpListen.vala`).
- ℹ️ HTTPS registration: product-CA TLS + `OLLMfilesd.Https.allow_rpc` + `ClientCert` (`request_registration` / accept / reject / ban).
- ℹ️ File Server UI edits `https` / `proxy` / `systemd` only. No socket host/port rows.
- ℹ️ Windows loopback TCP is hardcoded **4141** — [`2026-09-20-filesd-windows-socket-port.md`](../bugs/2026-09-20-filesd-windows-socket-port.md).

---

## Design decisions

- 🔷 `filesd.socket` stays `host:port` (empty = TCP off). Same split as `filesd.https` (`last_index_of(":")`).
- 🔷 Linux port **0** or missing port → treat as **off** (Unix only). Not an ephemeral TCP bind.
- 🔷 Unix (`filesd.unix`) and TCP socket are independent. Local `ollmchat` keeps the Unix socket when `unix` is true.
- 🔷 LAN bind (an address that is not loopback) uses **TLS** and the **same registration gate** as HTTPS (client cert, pending / accept / ban).
- 🔷 No PROXY Protocol on this listener. Client IP is the TCP peer.
- 🔷 Do not publish this socket past the local network. WAN clients use HTTPS + nginx as today.

- 💩 Reuse the existing `ClientCert` SQLite rows (same fingerprints) so Accept once covers HTTPS and LAN TCP.
- 💩 File Server expander: second Host/Port pair for `filesd.socket` (same IP dropdown as HTTPS), not a free-text field.
- 💩 Loopback `127.0.0.1` TCP may stay plaintext (Windows pattern). TLS required only when the host is a LAN address.
- 💩 Bin framing on the TLS stream (not HTTP/JSON). First-byte JSON line mode stays out of this plan.

---

## Phase 1 — Honor `filesd.socket` on Linux (`⏳`)

- 🔷 `⏳` `ollmfilesd` starts `TcpListen` when `filesd.socket` is a valid `host:port` and port is in **1024–65535**.
- 🔷 `⏳` Empty / port 0 → no `TcpListen`. Unix listen unchanged when `filesd.unix` is true.
- 🔷 `⏳` CLI `--tcp*` remains for tests; config is the desktop path (no new listen flags).
- ⏳ Code proposals — after Phase 2 TLS shape, or a first plaintext-loopback-only slice if that is approved.

---

## Phase 2 — TLS on the LAN TCP socket (`⏳`)

- 🔷 `⏳` Non-loopback `filesd.socket` wraps the accepted stream in TLS (product CA leaf, same `Transport.Cert` install as `Https.listen`).
- 🔷 `⏳` Request a **client certificate**. Unknown cert: only `request_registration`. Approved cert: full bin RPC.
- 🔷 `⏳` Ban list: drop by peer IP before TLS, same as HTTPS (`HttpServer.banned_ips`).
- 💩 `⏳` Implement as TLS on `TcpListen` / `Connection`, not a second Soup HTTP server on that port.
- ⏳ Code proposals — after this wrap is chosen.

---

## Phase 3 — Client + Connections UI (`⏳`)

- 🔷 `⏳` A LAN client connects with device cert + trust (same `Cert.ensure` as HTTPS file connection), to the socket `host:port`, not an `https://` URL.
- 🔷 `⏳` File Server expander can set socket host/port. Apply/reboot when those fields change (same bounce as HTTPS).
- ℹ️ Outbound “Add file connection” today is HTTPS URL only ([`8.2.8.2`](done/RPC-8.2.8.2-DONE-filesd-android-file-connection.md)). A `tcp://` / TLS-socket client row is this phase if we want phone-on-LAN without HTTPS.
- ⏳ Code proposals — after Phase 2 compiles.

---

## Suggested order

1. ⏳ Phase 1 — daemon binds `filesd.socket` (Linux; port 0 / empty = Unix only)
2. ⏳ Phase 2 — TLS + registration on non-loopback
3. ⏳ Phase 3 — client + File Server socket fields
4. ℹ️ Windows loopback port UI — the bug log, not these phases

---

## LLM notes

- ℹ️ Parent 8.2.8 HTTPS UI and Android takeover stay on their sub-plans.
- 🚫 nginx stream / PROXY Protocol on `filesd.socket`.
- 🚫 Advertising this socket on the public internet.
- 🚫 Replacing HTTPS with TCP for WAN / Android-over-internet.
- 🚫 Turning off the Unix socket just because TCP is on (unless `filesd.unix` is false).
- 🚫 New CLI flags for listen host/port (config object already exists).
- 🚫 Helper methods “for TLS accept” — inline on the existing listen/accept path unless a later fence names one.
