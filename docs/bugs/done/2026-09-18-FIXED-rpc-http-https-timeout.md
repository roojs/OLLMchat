# test-rpc-http-https times out (REQUESTED client cert)

**Status:** ✅ user closed 2026-09-19 — `HttpServer` TLS wrap + smoke device leaf; `test-rpc-http-https` green  
**Hit:** 2026-09-18 — `meson test -C build --suite rpc`  
**Component:** `libocrpc/Transport/HttpServer.vala` (`accept_iostream`) + smoke `HttpClient.tls_certificate`  
**Gate:** `meson test -C build test-rpc-http-https`

---

## Problem

🔷 `meson test --suite rpc` must be green.

🔷 `test-rpc-http-https` **TIMEOUT** 30s (SIGTERM). Same-process HTTPS
`HttpServer` + `HttpClient` never returns from `call.begin` / `MainLoop`.
Expected: `RPC-Hello.world` → `{ msg: "Hello World" }`, session header set.
Actual: TCP connects, no HTTP `/rpc`.

Plain HTTP sibling `test-rpc-http-client` is OK (same MainLoop pattern,
`http://127.0.0.1`).

Reproduce:

```bash
unset G_MESSAGES_DEBUG
OLLM_RPC_CA_PEM=/home/alan/gitlive/OLLMchat/libocrpc/data/ollmrpc-ca.pem \
OLLM_RPC_CA_KEY=/home/alan/gitlive/OLLMchat/libocrpc/data/ollmrpc-ca-key.pem \
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
- ℹ️ `HttpServer.start` sets `TlsAuthenticationMode.REQUESTED` on
  `Soup.Server` whenever `tls_certificate` is set. Incoming sockets go
  through `GLib.SocketService` + `accept_iostream`, not
  `Soup.Server.listen` (`opts` HTTPS is unused).
- ✔️ 2026-09-19 `--debug`: `leaf ready`, `client cert set`,
  `accept type=GTcpConnection`, `accept done`, then GSocketClient
  `Connection successful!`. No `request-certificate`, no `on_rpc`.
- ℹ️ libsoup 3.6.5 `soup_server_connection_accepted`: if the iostream is
  already set (`accept_iostream` / `new_for_connection`), it **skips**
  wrapping `GTlsServerConnection` and starts HTTP on the raw TCP stream.
  `Soup.Server:tls-certificate` / `tls-auth-mode` never apply on this path.
- ✔️ Server `REQUESTED` → `NONE` → smoke **exits 0** (2026-09-18). That
  result is in tension with the wrap skip; do not treat it as the remaining
  fix.
- 🚫 `message.request_certificate` returning `true` only — TIMEOUT 30s.
- 🚫 Same handler plus `set_tls_client_certificate(this.tls_certificate)`
  (null on the smoke) — TIMEOUT 30s. Reverted.
- 🚫 Always `set_tls_client_certificate(this.tls_certificate)` before send
  (null included, no `if`) — TIMEOUT 30s. Reverted.
- 🚫 `GLib.Idle.add` around `accept_iostream` — TIMEOUT 30s. Reverted.
  Accept already returned; idle does not answer the cert ask.
- 🚫 Smoke device leaf only (`client.pem`, `HttpClient.tls_certificate`) —
  still TIMEOUT 8s. Cert is set; Soup never asks because the server never
  speaks TLS on `accept_iostream`.
- ℹ️ Soup `soup_connection_complete_tls_certificate_request`: a **non-null**
  cert → `g_tls_connection_set_certificate` + `G_TLS_INTERACTION_HANDLED`.
  A **null** cert → `G_TLS_INTERACTION_FAILED`.

---

## Root cause

✔️ `HttpServer` hands a plain `GTcpConnection` to
`Soup.Server.accept_iostream`. Soup 3.6.5 does not wrap TLS on that API.
The client starts TLS; the server reads HTTP on TCP. `/rpc` never runs.

The smoke also omitted `HttpClient.tls_certificate`. Live clients mint a
device `Cert` (`FileConnectionAdd`, `Cert.vala` example). That leaf is now
in the smoke; it does not unstick the hang by itself.

🔷 User: wrap should be test-only if main HTTPS already works.

✔️ Same `HttpServer.start()`: `ollmfilesd/Https.listen()` sets
`tls_certificate` and calls `this.start()`. Default filesd is Unix
socket (`filesd.sock`); HTTPS only binds when `filesd.https` is set.
No second listen path. Original 8.2.3.5 used `Soup.Server.listen_local`
with HTTPS opts (Soup wraps TLS). 8.2.7 switched to `SocketService` +
`accept_iostream` for PROXY and did not wrap TLS on that stream.

---

## Proposed fix

🔷 Smoke keeps the throwaway device leaf (emulate ollmapp).

✔️ `HttpServer` incoming: when `tls_certificate` is set, wrap the TCP
stream in `GLib.TlsServerConnection`, `REQUESTED`, accept any peer cert
(self-signed device leaves), `handshake_async`, then `accept_iostream`
with the TLS stream. See tree: `libocrpc/Transport/HttpServer.vala`
`start()`, `tests/rpc/http-https-test.vala`.

🚫 Server `TlsAuthenticationMode.NONE` (breaks filesd mTLS).
🚫 Disable TLS verify / raise meson timeout.
🚫 `GLib.Idle.add` around `accept_iostream`.
🚫 `Message.request_certificate` + `set_tls_client_certificate(null)`.
🚫 Session `TlsInteraction` solely so a cert-less client can finish
  REQUESTED — live clients always present a leaf.
🚫 Installing packages / working around missing TLS packages.

### `tests/rpc/http-https-test.vala` — mint client leaf (in tree)

#### Remove
```vala
			var client = new OLLMrpc.Transport.HttpClient(base_url) {
				tls_database = cert.trust
			};
```

#### Replace with
```vala
			var leaf = new OLLMrpc.Transport.Cert() {
				dir = tls_dir,
				cert_pem = "client.pem",
				key_pem = "client-key.pem",
				cn = "ollmchat-device",
			};
			leaf.ensure();
			var client = new OLLMrpc.Transport.HttpClient(base_url) {
				tls_database = cert.trust,
				tls_certificate = leaf.certificate
			};
```

### `libocrpc/Transport/HttpServer.vala` — wrap TLS before `accept_iostream`

#### Remove
```vala
				try {
					GLib.debug("accept type=%s", connection.get_type().name());
					this.soup.accept_iostream(connection, local, remote);
					GLib.debug("accept done");
				} catch (GLib.Error e) {
					GLib.warning("proxy accept failed: %s", e.message);
				}
```

#### Replace with
```vala
				if (this.tls_certificate != null) {
					GLib.TlsServerConnection tls;
					try {
						tls = GLib.TlsServerConnection.@new(
							connection, this.tls_certificate);
					} catch (GLib.Error e) {
						GLib.warning("proxy accept failed: %s", e.message);
						return true;
					}
					tls.set_authentication_mode(
						GLib.TlsAuthenticationMode.REQUESTED);
					tls.accept_certificate.connect((peer_cert, errors) => {
						return true;
					});
					tls.handshake_async.begin(
						GLib.Priority.DEFAULT, null, (obj, res) => {
						try {
							tls.handshake_async.end(res);
						} catch (GLib.Error e) {
							GLib.warning("tls handshake failed: %s", e.message);
							return;
						}
						try {
							this.soup.accept_iostream(tls, local, remote);
						} catch (GLib.Error e) {
							GLib.warning("proxy accept failed: %s", e.message);
						}
					});
					return true;
				}
				try {
					this.soup.accept_iostream(connection, local, remote);
				} catch (GLib.Error e) {
					GLib.warning("proxy accept failed: %s", e.message);
				}
```

Temporary `GLib.debug` removed after the gate went green.

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
- ✔️ 2026-09-19 — user: smoke should emulate live code (temporary client
  cert). Second `Cert` (`client.pem`) + `HttpClient.tls_certificate`.
  Still TIMEOUT; `accept type=GTcpConnection`.
- 🔷 2026-09-19 — user: do not install packages or work around missing ones;
  ask if more packages are needed.
- 🔷 2026-09-19 — user: live HTTPS may never have been tested; same hang
  likely. Wrap applied in `HttpServer.start` (not test-only).
- ✔️ `meson test -C build test-rpc-http-https` OK 0.21s. Handshake log:
  `accept type=GTlsServerConnectionGnutls`, `on_rpc path=/rpc`.
- ✅ 2026-09-19 — user closed the bug.

## After the fix

✅ Smoke hello round-trip on HTTPS with a throwaway device leaf. `HttpServer`
wraps TLS on the `SocketService` / `accept_iostream` path (same as
`ollmfilesd.Https.listen()`). Log: `docs/bugs/done/2026-09-18-FIXED-rpc-http-https-timeout.md`.
