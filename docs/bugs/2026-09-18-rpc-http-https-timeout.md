# test-rpc-http-https times out (REQUESTED client cert, no handler)

**Status:** ⏳ root cause confirmed; fix proposed — await apply approval  
**Hit:** 2026-09-18 — `meson test -C build --suite rpc`  
**Component:** `libocrpc/Transport/HttpClient.vala` `call`  
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
  `tls_certificate` is set. 8.2.7 did that so ollmfilesd can read the device
  cert. `tests/rpc/http-https-test.vala` does not set
  `HttpClient.tls_certificate`.
- ✔️ Experiment: server `REQUESTED` → `NONE` → the smoke **exits 0**. So the
  hang is “server asked for a client cert” plus “client never completed that
  ask.”
- ✔️ Experiment: `message.request_certificate.connect(() => { return true; })`
  with **no** `set_tls_client_certificate` → still TIMEOUT 30s.
- ℹ️ Soup 3 `Message::request-certificate`: return `TRUE` **and** call
  `soup_message_set_tls_client_certificate`. `certificate == NULL` continues
  the handshake with no client cert. Return `TRUE` without that call means
  “I’ll set it later” — async wait, i.e. the hang we measured.
- ℹ️ Signal is **not** emitted if `set_tls_client_certificate` was already
  called with a non-null cert before the handshake, or if
  `Session:tls-interaction` is set. Today we only call set when
  `tls_certificate != null`, so the null (smoke) path never completes the
  REQUESTED ask.

---

## Root cause

✔️ Server `REQUESTED` a client certificate. `HttpClient.call` never answers
that ask when `tls_certificate` is null, so glib-tls waits forever. Not a
CA-trust failure (NONE without a client cert passes) and not an
`accept_iostream` deadlock (start and done both logged).

---

## Proposed fix

💩 In `HttpClient.call`, connect `request-certificate` and call
`set_tls_client_certificate(this.tls_certificate)` inside the handler
(null is allowed — Soup continues without a client cert). Keep server
`REQUESTED`. Keep the existing pre-handshake set when a cert is already on
the client.

🚫 Do not switch the server to `NONE` (breaks filesd mTLS). 🚫 Do not
disable TLS verify. 🚫 Do not raise the meson timeout. 🚫 Do not make the
smoke present a leaf unless this client complete still hangs. 🚫 Do not
`return true` without `set_tls_client_certificate` — already measured as a
hang.

### 1. `libocrpc/Transport/HttpClient.vala` — `call()`: finish REQUESTED handshake

**Why:** Soup only continues a REQUESTED client-cert ask after
`set_tls_client_certificate` (null = none).
**Where:** `call()`, immediately after the existing
`if (this.tls_certificate != null) { message.set_tls_client_certificate(...) }`
block.

#### Add — `request_certificate` handler that completes the ask

```vala
			message.request_certificate.connect((tls_connection) => {
				message.set_tls_client_certificate(this.tls_certificate);
				return true;
			});
```

---

## Attempts / changelog

- ✔️ 2026-09-18 — meson TIMEOUT 30s; TLS debug hangs after TCP
  “Connection successful!”.
- ✔️ `accept_iostream` start+done logged — not blocked in accept.
- ✔️ Server `REQUESTED` → `NONE` → smoke PASS. Reverted (`NONE` is not the
  product behaviour).
- 🚫 Handler that only `return true` — still TIMEOUT. Soup waits for
  `set_tls_client_certificate`.

## Next

- ⏳ 💩 Approve §1, then apply. Gate: `meson test -C build test-rpc-http-https`
  (and `--suite rpc` after both suite bugs land).
