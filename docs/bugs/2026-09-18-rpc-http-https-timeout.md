# test-rpc-http-https times out (REQUESTED client cert)

**Status:** ⏳ previous client hunks ruled out; no apply-ready fix yet  
**Hit:** 2026-09-18 — `meson test -C build --suite rpc`  
**Component:** `libocrpc/Transport/HttpClient.vala` + `HttpServer.vala` TLS  
**Gate:** `meson test -C build test-rpc-http-https`

---

## Problem

🔷 `meson test --suite rpc` must be green.

🔷 `test-rpc-http-https` **TIMEOUT** 30s (SIGTERM). Same-process HTTPS
`HttpServer` + `HttpClient` never returns from `call.begin` / `MainLoop`.
Expected: `RPC-Hello.world` → `{ msg: "Hello World" }`, session header set.
Actual: TCP connects, TLS handshake never finishes, no HTTP `/rpc`.

Plain HTTP sibling `test-rpc-http-client` is OK (same MainLoop pattern,
`http://127.0.0.1`).

Reproduce:

```bash
unset G_MESSAGES_DEBUG
OLLM_RPC_CA_PEM=libocrpc/data/ollmrpc-ca.pem \
OLLM_RPC_CA_KEY=libocrpc/data/ollmrpc-ca-key.pem \
timeout 8 ./build/tests/test-rpc-http-https --debug
```

---

## Evidence

- ℹ️ `localhost` on this host is `127.0.0.1` only — not an IPv6 mismatch.
- ✔️ `G_TLS_DEBUG=all`: first TCP `Connection refused`, retry `TCP connection
  successful`, `Starting application layer connection`, `Connection
  successful!`, then silence until kill. `HttpServer.on_rpc` never runs.
- ✔️ Temporary `GLib.debug` on `accept_iostream`: both `start` and `done`
  fire. Handshake is not stuck inside `accept_iostream`.
- ℹ️ `HttpServer.start` sets `TlsAuthenticationMode.REQUESTED` whenever
  `tls_certificate` is set (8.2.7, so ollmfilesd can read the device cert).
  `tests/rpc/http-https-test.vala` does not set
  `HttpClient.tls_certificate`. Production clients do (`Cert.vala` example,
  `Client.vala` HTTPS snippet).
- ✔️ Server `REQUESTED` → `NONE` → smoke **exits 0**. Hang is the
  REQUESTED client-cert ask, not CA trust.
- 🚫 `message.request_certificate` returning `true` only — TIMEOUT 30s.
- 🚫 Same handler plus `set_tls_client_certificate(this.tls_certificate)`
  (null on the smoke) — TIMEOUT 30s. Reverted.
- 🚫 Always `set_tls_client_certificate(this.tls_certificate)` before send
  (null included, no `if`) — TIMEOUT 30s. Reverted.
- 🚫 `GLib.Idle.add` around `accept_iostream` — TIMEOUT 30s. Reverted.
  Accept already returned; idle does not answer the cert ask.
- ℹ️ Soup `soup_connection_complete_tls_certificate_request`: a **non-null**
  cert → `g_tls_connection_set_certificate` + `G_TLS_INTERACTION_HANDLED`.
  A **null** cert → `G_TLS_INTERACTION_FAILED`. The Message docs’ “null
  continues without a client cert” is not what the connection complete
  path does. That is why the client hunks above did not unstick REQUESTED.

---

## Root cause

✔️ Server `REQUESTED` a client certificate. The smoke client has none.
glib-tls waits on Soup’s `TlsInteraction`. Message-level
`set_tls_client_certificate(null)` / `request_certificate` do not complete
that interaction as HANDLED (null → FAILED). Not CA verify, not
`accept_iostream` deadlock.

---

## Proposed fix

💩 Open — no hunk to apply yet. The §1 Message handler is **ruled out**.

Remaining directions (pick one, do not stack):

- 💩 Session/connection `TlsInteraction` that returns **SUCCESS** with no
  certificate when `HttpClient.tls_certificate` is null (REQUESTED allows
  none). Small class or Soup session interaction — not idle, not `NONE`.
- 💩 Smoke presents a leaf (`tls_certificate = cert.certificate` or a
  device Cert), matching production `HttpClient`. That would make the
  gate mTLS; it would not teach the library to finish REQUESTED with no
  cert.

🚫 Server `TlsAuthenticationMode.NONE` (breaks filesd mTLS).
🚫 Disable TLS verify / raise meson timeout.
🚫 `GLib.Idle.add` around `accept_iostream`.
🚫 `Message.request_certificate` + `set_tls_client_certificate(null)` —
  measured TIMEOUT; Soup complete treats null as FAILED.

---

## Attempts / changelog

- ✔️ 2026-09-18 — meson TIMEOUT 30s; TLS debug hangs after TCP
  “Connection successful!”.
- ✔️ `accept_iostream` start+done logged — not blocked in accept.
- ✔️ Server `REQUESTED` → `NONE` → smoke PASS. Reverted (`NONE` is not the
  product behaviour).
- 🚫 Handler that only `return true` — still TIMEOUT.
- 🚫 `request_certificate` + `set_tls_client_certificate(this.tls_certificate)`
  — still TIMEOUT 30s. Reverted.
- 🚫 Always `set_tls_client_certificate` before send (null included) —
  still TIMEOUT 30s. Reverted.
- 🚫 `GLib.Idle.add` around `accept_iostream` — still TIMEOUT. Reverted.

## Next

- ⏳ 💩 Choose a remaining direction above; write a verbatim fence only
  once that direction is picked. Gate: `meson test -C build test-rpc-http-https`.
