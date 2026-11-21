# Localhost TCP should allow TLS (client cert identity)

**Status:** ⏳ OPEN — client fix ✔️ applied in libocrpc; regression test ⏳

**Started:** 2026-11-21

**Pointer:** `docs/bug-fix-process.md`, `docs/guide-to-writing-plans.md` (edit fences)

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

## Proposed fix

### Client — explicit `force_localhost_tls` (default off)

- 🔷 Add GObject property `force_localhost_tls` on `OLLMrpc.Client` (default **false**).
- 🔷 Consumers set it in the object initializer (with `configure_tls`) when dialing a TLS-only localhost management port.
- 🔷 When `force_localhost_tls` is **true**, `tcp://127.0.0.1` dials **must** handshake TLS (no cleartext bin RPC).
- 🔷 Cleartext is allowed only when the flag is **false** and `socket_path.has_prefix("tcp://127.0.0.1")` (Windows `TcpListen`). No host/port parsing — fixed `tcp://` URL shapes only.
- 🔷 `tcp://localhost` and other non-`127.0.0.1` `tcp://` paths behave as today (TLS unless that prefix rule applies).
- 🚫 Do **not** infer TLS from `configure_tls.has_handler()` alone — easy to wire by accident; breaks plaintext Windows `TcpListen` peers.
- 🚫 Do **not** enable TLS on all `tcp://127.0.0.1` dials unconditionally (default remains cleartext until the consumer sets the flag).

#### Add — `libocrpc/Client.vala`, after `pass_data_dir`

```vala
		/**
		 * When true, ''tcp://127.0.0.1'' dials handshake TLS (no cleartext).
		 * When false, only that prefix stays cleartext (Windows
		 * {@link Transport.TcpListen}). Wire {@link configure_tls} before
		 * {@link connect} when this flag is on.
		 */
		public bool force_localhost_tls { get; set; default = false; }
```

#### Remove — `libocrpc/Client.vala`, `connect`, TLS gate (before bin streams)

```vala
			var bin_in = this.socket.get_input_stream();
			var bin_out = this.socket.get_output_stream();
			if (this.protocol == Protocol.TCP
				&& !this.socket_path.has_prefix("tcp://127.0.0.1")) {
				try {
					var tls_link = GLib.TlsClientConnection.@new(this.socket, null);
					this.configure_tls(tls_link);
					tls_link.accept_certificate.connect((peer_cert, errors) => {
						return peer_cert != null
							&& (errors & ~GLib.TlsCertificateFlags.BAD_IDENTITY) == 0;
					});
					yield tls_link.handshake_async();
					this.tls_connection = tls_link;
					bin_in = tls_link.get_input_stream();
					bin_out = tls_link.get_output_stream();
				} catch (GLib.Error e) {
					this.connect_error = e.message;
					GLib.critical("connect %s: %s", this.socket_path, this.connect_error);
					return false;
				}
			}
```

#### Replace with — `libocrpc/Client.vala`, `connect`, TLS gate (before bin streams)

```vala
			var bin_in = this.socket.get_input_stream();
			var bin_out = this.socket.get_output_stream();
			if (this.protocol == Protocol.TCP
				&& !(this.socket_path.has_prefix("tcp://127.0.0.1")
					&& !this.force_localhost_tls)) {
				try {
					var tls_link = GLib.TlsClientConnection.@new(this.socket, null);
					this.configure_tls(tls_link);
					tls_link.accept_certificate.connect((peer_cert, errors) => {
						return peer_cert != null
							&& (errors & ~GLib.TlsCertificateFlags.BAD_IDENTITY) == 0;
					});
					yield tls_link.handshake_async();
					this.tls_connection = tls_link;
					bin_in = tls_link.get_input_stream();
					bin_out = tls_link.get_output_stream();
				} catch (GLib.Error e) {
					this.connect_error = e.message;
					GLib.critical("connect %s: %s", this.socket_path, this.connect_error);
					return false;
				}
			}
```

#### Keep — `libocrpc/Client.vala`, `connect`, immediately after TLS gate (unchanged)

```vala
			this.input = new GLib.DataInputStream(bin_in);
			this.output = new GLib.DataOutputStream(bin_out);
			this.bin = new Bin.Stream(this.input, this.output) {
```

### Consumer example (downstream, not libocrpc)

#### Add — Argus-style dial (illustrative; file is product repo)

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

### Server (optional, later) — encrypted localhost listener

- 💩 If a daemon must accept **only** registered certificates on localhost (no Unix socket), add an explicit **TLS mode** on `TcpListen` (or a sibling `TlsListen` transport) rather than upgrading every default `127.0.0.1:4141` bind. Argus Linux uses Unix `argus.sock` for plaintext registration RPC and a separate TLS app listener; Windows-style products would flip the flag on the localhost row.

## Argus interim policy (downstream)

- ℹ️ Prefer saved **interface** addresses from `Registration.certificate` for probes, not fabricated `127.0.0.1` — avoids the bug but does not replace upstream fix when local login must hit localhost.

## Attempts / changelog

- ✔️ **2026-11-21** — `libocrpc/Client.vala`: `force_localhost_tls` + localhost-only TLS enforcement per fences above (agent; not user-verified).

## Next

- 🔷 ⏳ Regression test: TLS echo server on `127.0.0.1`, `Client` with `force_localhost_tls = true`, `configure_tls` + client cert, successful `RPC-Daemon.hello`.
- 💩 ⏳ Decide whether localhost TLS listener belongs in libocrpc or stays product-specific (`Argus.Server.Net.SslListen`).