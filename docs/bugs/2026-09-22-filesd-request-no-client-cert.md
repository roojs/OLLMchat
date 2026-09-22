# File connection Request: client certificate required

**Status:** ⏳ root cause confirmed; client + server fix in tree —
  needs filesd bounce + APK for device ✅

**Pointer:** `docs/bug-fix-process.md`

## Problem

- 🔷 Phone Add file connection → Request against desktop
  `192.168.88.132:8443` (no proxy). Nothing visible on the phone;
  desktop chat never shows an access request.
- 🔷 Expected: desktop Connections banner Accept / Reject / Ban
  (settings dialog, [`RPC-8.2.8.1`](../plans/done/RPC-8.2.8.1-DONE-filesd-desktop-connections-ui.md)).
- 🔷 URL row subtitle on the phone is too long beside the entry —
  put the hint under the field (same as Android bootstrap Host).

## Evidence

- ℹ️ Desktop `ollmfilesd` LISTEN `192.168.88.132:8443` (systemd,
  binary 2026-09-22 16:31).
- ✔️ Phone logcat: TCP + TLS succeed, then
  `RPC-ClientCert.request_registration id=0: client certificate required`.
  `error_occurred` is not connected, so the dialog looks idle.
- ✔️ Same RPC error from desktop
  `test-rpc-filesd-http-client --url=https://192.168.88.132:8443`.
- ✔️ `openssl s_client -msg`: server sends TLS 1.3
  `CertificateRequest`; openssl without `-cert` replies empty.
- ✔️ After `CertAsk`: client log `tls interaction type=…CertAsk`,
  then `client cert interaction sync`. Same second, filesd
  `HttpServer.vala:229: tls handshake peer cert present`
  (`~/.cache/ollmchat/ollmfilesd.debug.log` 16:58:34) — then still
  `client certificate required`.
- ℹ️ Soup `ServerMessage.get_socket()` is **NULL** after
  `accept_iostream` (libsoup 3.6.5 docs). Peer qdata on the TCP
  socket is unreachable. `get_tls_peer_certificate()` is a cache
  filled only when Soup does its own handshake, not for a
  pre-handshaked `GTlsServerConnection`.

## Root cause

- ✔️ Two layers:
  1. Soup TLS 1.3 needs `Session:tls-interaction` to present the
     device leaf (`CertAsk`). Message
     `set_tls_client_certificate` is ignored when that property
     is set, and is too late on its own.
  2. Non-proxy `HttpServer` wraps TLS itself then
     `accept_iostream`. Handshake **has** `tls.peer_certificate`,
     but `on_rpc` never saw it (`get_socket()` NULL, message TLS
     cache empty) → `ClientCert.request_registration` empty
     fingerprint.
- ✔️ Failures are silent in `FileConnectionAdd` (`error_occurred`
  unused).

## Proposed fix

- 🔷 `HttpClient`: `CertAsk` + `this.soup.tls_interaction`.
- 🔷 `HttpServer` handshake: also
  `remote.set_data("ollmrpc-peer-cert", …)` on the
  `GSocketAddress` passed into `accept_iostream` (Soup keeps that
  object). `on_rpc` / `on_route` read it via
  `msg.get_remote_address()`.
- 🔷 AlertDialog on Request failure; Android URL hint under the
  entry.

## Attempts / changelog

- ✔️ 2026-09-22 — logcat + live client + openssl `-msg`.
- ✔️ 2026-09-22 — `CertAsk` invoked; server handshake **present**;
  RPC fingerprint still empty.
- ✔️ 2026-09-22 — qdata on remote address (Soup
  `accept_iostream` path).

## Next

- 🔷 ⏳ Bounce `ollmfilesd` so the fingerprint lookup is live
  (do not restart until asked).
- 🔷 ⏳ `test-rpc-filesd-http-client --url=https://192.168.88.132:8443`
  → `request_registration ok`.
- 🔷 ⏳ Rebuild/install APK; Request; desktop Settings →
  Connections for Accept.
