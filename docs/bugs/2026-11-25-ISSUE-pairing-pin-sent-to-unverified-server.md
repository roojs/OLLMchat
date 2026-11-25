# Phone pairing sends the PIN and CSR to any TLS server at the discovered address

**Status:** ✔️

### User decisions required

None.

### User reported

- 🔷 Pairing interception through disabled TLS checks in device enrollment: anyone on the network who advertises or intercepts the pairing service receives the PIN, registers their own certificate with the real desktop, or hands the phone a fake CA for later file-server RPC.

### Success scenario

- A TLS server that is not the desktop never receives the pairing PIN or CSR, even when the phone has the full code from the desktop dialog.
- The desktop never approves a certificate that the attacker enrolled with a stolen PIN.
- The phone never stores a CA that did not come from the desktop it verified.
- Pairing with the real desktop still works, with and without stored credentials.
- `meson test -C build test-rpc-filesd-pair-intercept` (PR 49) and `test-rpc-filesd-pair-flow` pass.

### Current behavior

- Tool calls
  - `meson test -C build test-rpc-filesd-pair-intercept --print-errorlogs` on `248bf5ca`
- Observable outcome
  - Exit status 1 with the stderr below.

```text
untrusted server received the pairing PIN; attacker certificate was approved; approved attacker read a file; approved attacker wrote a file; approved attacker passed the command gate; phone stored the attacker CA; phone url points at the attacker; stored CA trusted the attacker for later RPC; ClientCert.pair reached the attacker;
```

### Codebase observed behavior

- [`libollmchat/Settings/FilesdClient.vala`](../../libollmchat/Settings/FilesdClient.vala) — registration trusts any server and sends the PIN and CSR on that session.

```vala
var link = new OLLMrpc.Transport.TlsClient(host, port) {
	accept_any = true
};
response = link.call(new OLLMrpc.Request() {
	method = "ClientCert.request_registration",
	args = OLLMrpc.args("sss", pin, csr, requester)
});
```

- [`libollmchat/Settings/FilesdClient.vala`](../../libollmchat/Settings/FilesdClient.vala) — the reply's CA (`packed[1]`) is written to `ollmrpc-ca.pem` and used as trust for every later call.
- [`libocrpc/Transport/TlsClient.vala`](../../libocrpc/Transport/TlsClient.vala) — `accept_any` returns `true` from `accept_certificate` and nothing exposes the peer certificate.
- [`ollmfilesd/SslListen.vala`](../../ollmfilesd/SslListen.vala) — while `pin` is set the desktop accepts any client, so a stolen PIN is enough to enroll.
- [`libocrpc/Transport/PairPublish.vala`](../../libocrpc/Transport/PairPublish.vala) — the mDNS record is unauthenticated, so the address the phone dials is attacker-controllable.

### Debugging

#### Current debug output

None yet.

#### Debug code added (remove when complete)

None.

### ✔️ Proposed fix

- Why
  - The only authenticated channel is the desktop screen, and the six-digit PIN is the only secret on it.
  - Any value derived from the PIN alone that the phone sends to an unverified server can be brute-forced offline in a million tries.
  - So the screen must also carry something that binds the desktop's server certificate, and the phone must check it before it sends anything.
- Design
  - The daemon computes six check digits: HMAC-SHA256 keyed by the PIN over the DER of its SSL server certificate, first 32 bits modulo one million.
  - `ClientCert.pair` (Unix socket) returns them. The dialog shows `PIN check`.
  - The phone types all twelve digits.
  - `try_connection` opens TLS, recomputes the digits over the certificate that handshake received, and sends `request_registration` on that same session only when they match.
  - The stored CA is replaced only after a verified registration. The old pre-check `force_register` delete is gone.
  - An attacker does not know the PIN, so cannot compute or grind a certificate whose check matches. One guess per pairing attempt succeeds with probability one in a million.
- Files
  - [`libocrpc/Transport/TlsClient.vala`](../../libocrpc/Transport/TlsClient.vala) — `peer_certificate` set after the `open` handshake.
  - [`ollmfilesd/SslListen.vala`](../../ollmfilesd/SslListen.vala) — keep the server certificate as `certificate`.
  - [`ollmfilesd/ClientCert.vala`](../../ollmfilesd/ClientCert.vala) — `pair` replies with the check digits.
  - [`libollmchat/Settings/FilesdClient.vala`](../../libollmchat/Settings/FilesdClient.vala) — twelve-digit code, check before sending, PIN-only on the wire.
  - [`ollmapp/SettingsDialog/PairingDialog.vala`](../../ollmapp/SettingsDialog/PairingDialog.vala) — show the PIN and the check digits.
  - [`ollmapp/android/FileConnectionAdd.vala`](../../ollmapp/android/FileConnectionAdd.vala) — accept twelve digits.
  - [`tests/rpc/filesd-pair-flow-test.vala`](../../tests/rpc/filesd-pair-flow-test.vala) — pass the PIN plus the check digits from each `ClientCert.pair` reply.

### LLM

- ℹ️ Failing tests: https://github.com/roojs/OLLMchat/pull/49 (`tests/rpc/filesd-pair-intercept-test.vala`).
- 🚫 PAKE (SRP / SPAKE2 / CPace) — phone links OpenSSL on Android and GnuTLS on desktop, and GLib TLS exposes neither SRP nor raw group operations.
- 🚫 Static server fingerprint in mDNS TXT — the attacker spoofs mDNS.
- 🚫 Static short fingerprint on screen — the server certificate is public and long-lived, so a short fingerprint can be ground in advance.
- ⏳ [`tests/rpc/filesd-pair-test.vala`](../../tests/rpc/filesd-pair-test.vala) is a manual developer CLI that still sends `--pin` over an accept-any handshake. It is not shipped and not a registered test.
- ⏳ The phone trusts any certificate the desktop CA signs as a server, and the same CA signs approved device certificates. A device that is already approved could pose as the desktop to another phone. This needs an already-approved device and is separate from this report.
