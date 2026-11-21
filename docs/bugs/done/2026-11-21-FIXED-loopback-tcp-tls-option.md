# Localhost TCP should allow TLS (client cert identity)

**Status:** ✅ 2026-11-21. User closed. `OLLMrpc.Client.force_localhost_tls` (default false); `connect` handshakes TLS on `tcp://127.0.0.1` when the consumer sets the flag.

**Started:** 2026-11-21

**Pointer:** `docs/bug-fix-process.md`

**Consumers:** Argus controller local login (`--give-me-a-certificate` + TLS `RPC-Daemon.hello`), Windows `TcpListen` tray peers, any TLS-only management port reached via `127.0.0.1`.

## Problem

- 🔷 Management RPC that requires a **registered client certificate** must stay on TLS even when the dial target is **localhost** (`127.0.0.1` / `tcp://127.0.0.1:*`).
- 🔷 Plain localhost TCP cannot identify the peer: there is no client cert, so the server cannot treat the session as a registered user.
- 🔷 **Actual:** `OLLMrpc.Client.connect` **never** ran a TLS handshake when `socket_path` is prefixed with `tcp://127.0.0.1`, even when the caller connected `configure_tls` and presents client PEMs (Argus controller after local certificate issue).
- 🔷 **Symptom:** TLS listener on the management port sees plain bin RPC; hello fails (`Client: disconnected` / handshake mismatch). Connecting with an issued certificate to `localhost` cannot work until the consumer may opt into TLS on that dial.

## Evidence

- ℹ️ Argus argusrm tracking: [`argusrm/docs/bugs/2026-11-20-ollmrpc-loopback-plain-tcp.md`](https://github.com/alanknowles/argusrm/blob/main/docs/bugs/2026-11-20-ollmrpc-loopback-plain-tcp.md) (same root cause, Argus policy notes).
- ✔️ `libocrpc/Client.vala` (TLS gate): TLS branch was guarded by `!this.socket_path.has_prefix("tcp://127.0.0.1")` only.
- ✔️ `libocrpc/Transport/TcpListen.vala`: localhost `TcpListen` accepts **plaintext** `Connection` only — by design for Windows tray / local daemon without Unix sockets (`docs/bugs/done/2026-09-20-FIXED-filesd-windows-socket-port.md` ruled out TLS on that socket in 2026-09).
- ℹ️ `OLLMrpc.Transport.TlsClient` already handshakes TLS to any host/port (including `127.0.0.1`); persistent `OLLMrpc.Client` sessions used the localhost cleartext exception instead.

## Root cause

- ✔️ Historical assumption: **all** `tcp://127.0.0.1` peers are trusted local plaintext (e.g. `ollmfilesd` Windows localhost). That collides with products whose **localhost or LAN IP** management port is **TLS + client certificate** (Argus `SslListen`).

## Fix applied — `libocrpc/Client.vala`

### Client — `force_localhost_tls` (default off) ✅

- 🔷 GObject property `force_localhost_tls` on `OLLMrpc.Client` (default **false**).
- 🔷 Consumers set it in the object initializer (with `configure_tls`) when dialing a TLS-only localhost management port.
- 🔷 When `force_localhost_tls` is **true**, `tcp://127.0.0.1` dials **must** handshake TLS (no cleartext bin RPC).
- 🔷 Cleartext only when the flag is **false** and `socket_path.has_prefix("tcp://127.0.0.1")` (Windows `TcpListen`). Prefix check only — no host/port parsing.
- 🔷 `tcp://localhost` and other non-`127.0.0.1` `tcp://` paths behave as before.

TLS gate:

```vala
			if (this.protocol == Protocol.TCP
				&& !(this.socket_path.has_prefix("tcp://127.0.0.1")
					&& !this.force_localhost_tls)) {
```

### Consumer example (downstream, not libocrpc)

```vala
var rpc = new OLLMrpc.Client(
	data_dir,
	pid,
	"tcp://127.0.0.1:8443"
) {
	force_localhost_tls = true,
};
rpc.configure_tls.connect((link) => {
	link.certificate = client_leaf;
	link.database = client_trust;
});
```

## Out of scope (unchanged)

- 💩 Encrypted localhost **listener** in libocrpc (`TcpListen` TLS mode) — product-specific listeners (e.g. Argus `SslListen`) unless a later plan opens it.
- 💩 `libocrpc` regression test on `127.0.0.1` with client cert — optional follow-up.

## Argus interim policy (downstream)

- ℹ️ Prefer saved **interface** addresses from `Registration.certificate` for probes, not fabricated `127.0.0.1` — still valid when local login need not hit loopback.

## Attempts / changelog

- ✔️ **2026-11-21** — `libocrpc/Client.vala`: `force_localhost_tls` + TLS gate per above.