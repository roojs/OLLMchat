#  8.2.8.7 — URGENT — File-daemon TCP socket on the LAN (TLS + registration)

**Status:** **URGENT** — Phase 1 **✔️**. Phase 2 **✔️** (`SslListen` and `SslConnection`, one class per file). Desktop server rows are [`8.2.8.13`](RPC-8.2.8.13-filesd-desktop-server-rows.md). Windows is [`8.2.8.14`](RPC-8.2.8.14-LATER-filesd-windows-desktop-server.md), later.

> **Do not update** `docs/plans/RPC-1.0-summary.md` **for this sub-plan.**

**Parent:** `[RPC-8.2.8-filesd-connections-ui.md](RPC-8.2.8-filesd-connections-ui.md)`

**Depends on:**

- `[RPC-8.2.7-client-cert-registration.md](RPC-8.2.7-client-cert-registration.md)` — `filesd.socket` reserved; HTTPS registration already in tree
- `[RPC-8.2.8.3-DONE-filesd-file-server-tls.md](done/RPC-8.2.8.3-DONE-filesd-file-server-tls.md)` — File Server expander is HTTPS host/port/proxy/systemd
- **Windows loopback port** is a **bug**, not this plan: `[docs/bugs/2026-09-20-filesd-windows-socket-port.md](../bugs/2026-09-20-filesd-windows-socket-port.md)`

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Purpose

- 🔷 Bind a TLS bin listener from `filesd.socket` (`host:port`) when that listener is explicitly enabled. This is the local network SSL server. It is not the Windows plaintext socket.
- 🔷 Off is that enabled flag. Host and port stay. An empty port or port 0 is not the off switch.
- 🔷 The Unix socket on Linux stays the local app path. `filesd.unix` stays true.
- 🔷 LAN only. This path is **not** for the public internet: no nginx PROXY, no WAN registration, no reverse-proxy IP rewrite.
- 🔷 The phone uses this socket on the home LAN and the office LAN. HTTPS is only for when the phone is outside those networks.
- ℹ️ HTTPS remains the internet / proxy path (`[docs/filesd-behind-nginx-proxy.md](../filesd-behind-nginx-proxy.md)`).
- ℹ️ Desktop server rows and the LAN client are [`8.2.8.13`](RPC-8.2.8.13-filesd-desktop-server-rows.md). Windows service and the Windows host list are [`8.2.8.14`](RPC-8.2.8.14-LATER-filesd-windows-desktop-server.md), later.

---

## Current behaviour

- ℹ️ `filesd.socket` is `host:port`. `SslListen` binds it when `ssl_enabled` is on and the address is a non-loopback `host:port` in 1024–65535. `TcpListen` is not used for that address.
- ℹ️ Linux daemon: Unix `SocketListen` unless CLI `--tcp` / `--tcp-host` / `--tcp-port`. HTTPS is a **second** listener from `filesd.https`.
- ℹ️ `TcpListen` is **plaintext** bin RPC. Docblock already says a public bind needs an authenticated transport first (`libocrpc/Transport/TcpListen.vala`).
- ℹ️ HTTPS registration: product-CA TLS + `OLLMfilesd.Https.allow_rpc` + `ClientCert` (`request_registration` / accept / reject / ban).
- ℹ️ File Server UI edits `https` / `proxy` / `systemd` only. No socket host/port rows.
- ℹ️ Windows loopback TCP is hardcoded **4141** — `[2026-09-20-filesd-windows-socket-port.md](../bugs/2026-09-20-filesd-windows-socket-port.md)`.

---

## Design decisions

🔷 Decided.

- 🔷 `filesd.socket` stays `host:port`. Same split as `filesd.https` (`last_index_of(":")`).
- 🔷 `ssl_enabled` is the local network SSL server switch. Off keeps the saved host and port and does not listen.
- 🔷 Rename `filesd.enabled` to `https_enabled`. That switch is the HTTPS server. No migration from the old `enabled` key. It has barely been used.
- 🔷 Anyone can make a certificate and request to join. Approval still gates them. That is why the subtitle is Recommended for local networks only.
- 🔷 Unix on Linux, and localhost TCP on Windows, stay up. Those rows have no switch. `filesd.unix` stays true. The Unix row does not write it false.
- 🔷 The local network SSL server is TLS on the bin stream. It does not expose the Windows plaintext socket.
- 🔷 No TLS on Windows localhost TCP (`127.0.0.1`).
- 🔷 No PROXY Protocol on the local network SSL server. It cannot be used there. Client IP is the TCP peer.
- 🔷 Already decided: do not publish this listener past the local network. Outside the LAN the phone uses HTTPS.
- 🔷 Local network SSL server default port is 8422. HTTPS default port is 8443.
- 🔷 Local network SSL server host list excludes localhost (`127.0.0.1`).
- 🔷 Reuse the existing `ClientCert` SQLite rows. The same fingerprint accept covers HTTPS and this TLS socket. Accept on the LAN accepts HTTPS. Accept on HTTPS accepts the LAN socket.
- 🔷 First-byte JSON line mode stays out of this plan. This is not a second HTTP server.

- 💩 `ssl_enabled` defaults to false, so the new listener stays off until the toggle is on. `https_enabled` keeps today's default true.
- ℹ️ systemd here is the Linux user unit (`systemctl --user` in `Filesd.install`). The Windows per-user service and the Windows host list are [`8.2.8.14`](RPC-8.2.8.14-LATER-filesd-windows-desktop-server.md), later.

---

## Phase 1 — Flags (`✔️`)

- 🔷 `✔️` Rename `enabled` to `https_enabled` on `Filesd`. Do not read the old key. `ssl_enabled` defaults false. `socket` stays `host:port`.
- 🔷 `✔️` Unix listen stays. `filesd.unix` stays true.
- 🔷 `✔️` Windows localhost TCP stays up, plaintext, no switch. This phase does not replace it.
- 🔷 `✔️` CLI `--tcp*` remains for tests. No new listen flags.
- 🚫 A `GLib.warning` in `initialize()` with no listener. Phase 2 skips the SSL socket when `socket` is not a LAN `host:port`. Unix and HTTPS keep running.

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify surrounding context before applying.

### 1. `libollmchat/Settings/Filesd.vala` — class doc: `https_enabled` and `ssl_enabled`

**Why:** The JSON example still shows `enabled`, and the overview still says `socket` is reserved.

**Where:** Class docblock on `Filesd`, including the example object.

**Depends on:** none

#### Remove

```vala
	 * JSON key ''filesd''. ''unix'' / ''socket'' are reserved for later;
	 * this plan uses ''enabled'', ''https'', ''proxy'', and
	 * ''systemd''. {@link install} sets up the user systemd unit from
	 * {@link systemd}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * "filesd": {
	 *   "unix": true,
	 *   "socket": "",
	 *   "enabled": true,
	 *   "https": "127.0.0.1:8443",
	 *   "proxy": true,
	 *   "systemd": true
	 * }
	 * }}}
```

#### Replace with

`ssl_enabled` and `https_enabled` replace the reserved-socket note and the `enabled` key. No read of the old key.

```vala
	 * JSON key ''filesd''. ''ssl_enabled'' binds the local network
	 * SSL server from ''socket''. ''https_enabled'' binds HTTPS from
	 * ''https''. Do not read the old ''enabled'' key.
	 * {@link install} sets up the user systemd unit from
	 * {@link systemd}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * "filesd": {
	 *   "unix": true,
	 *   "socket": "",
	 *   "ssl_enabled": false,
	 *   "https": "127.0.0.1:8443",
	 *   "https_enabled": true,
	 *   "proxy": true,
	 *   "systemd": true
	 * }
	 * }}}
```

### 2. `libollmchat/Settings/Filesd.vala` — `socket`, `ssl_enabled`, `https_enabled`

**Why:** Off is `ssl_enabled`, not an empty port. `enabled` is the HTTPS switch and gets the new name.

**Where:** Properties `socket`, `https`, and `enabled`.

**Depends on:** ### 1

#### Remove

```vala
		/**
		 * Bin TCP listen as ''host:port'' (empty = off). Config-only for now.
		 */
		public string socket { get; set; default = ""; }

		/**
		 * HTTPS listen as ''host:port''. Kept when {@link enabled} is
		 * false; empty means no address stored yet.
		 */
		public string https { get; set; default = ""; }

		/**
		 * When false, ollmfilesd does not bind HTTPS. Host, port,
		 * {@link proxy}, and {@link systemd} keep their last values.
		 */
		public bool enabled { get; set; default = true; }
```

#### Replace with

`socket` stays `host:port`. `ssl_enabled` defaults false. `https_enabled` keeps the old default true.

```vala
		/**
		 * Local network SSL listen as ''host:port''. Kept when
		 * {@link ssl_enabled} is false. Empty means no address
		 * stored yet, not the off switch.
		 */
		public string socket { get; set; default = ""; }

		/**
		 * When false, ollmfilesd does not bind the local network
		 * SSL server. {@link socket} keeps its host and port.
		 */
		public bool ssl_enabled { get; set; default = false; }

		/**
		 * HTTPS listen as ''host:port''. Kept when
		 * {@link https_enabled} is false. Empty means no address
		 * stored yet.
		 */
		public string https { get; set; default = ""; }

		/**
		 * When false, ollmfilesd does not bind HTTPS. Host, port,
		 * {@link proxy}, and {@link systemd} keep their last values.
		 */
		public bool https_enabled { get; set; default = true; }
```

### 3. `ollmfilesd/Https.vala` — `listen()`: `https_enabled`

**Why:** HTTPS must follow the renamed flag. `ssl_enabled` does not turn HTTPS off.

**Where:** `listen()`, the docblock sentence and the first guard.

**Depends on:** ### 2

#### Remove

```vala
		 * No-op (returns ''false'') when ''filesd.enabled'' is false,
```

#### Replace with

Docblock names `https_enabled`.

```vala
		 * No-op (returns ''false'') when ''filesd.https_enabled'' is false,
```

#### Remove

```vala
			if (!filesd.enabled) {
```

#### Replace with

Guard uses `https_enabled`.

```vala
			if (!filesd.https_enabled) {
```

### 4. `ollmapp/SettingsDialog/FileServerRow.vala` — HTTPS switch writes `https_enabled`

**Why:** The existing File Server switch is the HTTPS on/off. Phase 3 moves the rows. This phase only renames the property it writes.

**Where:** Class doc, `enabled_switch` doc, `load_config`, `apply_config`, and the subtitle check after reboot.

**Depends on:** ### 2

#### Remove

```vala
	 * {@link OLLMchat.Settings.Filesd.enabled} false without
```

#### Replace with

Class doc names `https_enabled`.

```vala
	 * {@link OLLMchat.Settings.Filesd.https_enabled} false without
```

#### Remove

```vala
		 * and sets {@link OLLMchat.Settings.Filesd.enabled} false;
```

#### Replace with

Switch doc names `https_enabled`.

```vala
		 * and sets {@link OLLMchat.Settings.Filesd.https_enabled} false;
```

#### Remove

```vala
			this.enabled_switch.active = this.filesd.enabled;
```

#### Replace with

`load_config` reads `https_enabled`.

```vala
			this.enabled_switch.active = this.filesd.https_enabled;
```

#### Remove

```vala
			var https_ok = this.filesd.enabled && n >= 1024 && n <= 65535;
```

#### Replace with

HTTPS subtitle uses `https_enabled`.

```vala
			var https_ok = this.filesd.https_enabled && n >= 1024 && n <= 65535;
```

#### Remove

```vala
		 * {@link OLLMchat.Settings.Filesd.enabled} false and leaves
```

#### Replace with

`apply_config` doc names `https_enabled`.

```vala
		 * {@link OLLMchat.Settings.Filesd.https_enabled} false and leaves
```

#### Remove

```vala
			var prev_enabled = this.filesd.enabled;
			this.was_systemd = prev_systemd;
			this.filesd.enabled = this.enabled_switch.active;
			if (this.filesd.enabled && this.host_row.visible) {
```

#### Replace with

Same writes, property name `https_enabled`.

```vala
			var prev_enabled = this.filesd.https_enabled;
			this.was_systemd = prev_systemd;
			this.filesd.https_enabled = this.enabled_switch.active;
			if (this.filesd.https_enabled && this.host_row.visible) {
```

#### Remove

```vala
			if (this.filesd.enabled) {
				this.filesd.proxy = this.proxy_switch.active;
			}
			if (this.filesd.enabled != prev_enabled
```

#### Replace with

Proxy write and the change check use `https_enabled`.

```vala
			if (this.filesd.https_enabled) {
				this.filesd.proxy = this.proxy_switch.active;
			}
			if (this.filesd.https_enabled != prev_enabled
```

#### Remove

```vala
			if (this.filesd.enabled && colon > 0) {
```

#### Replace with

Reboot subtitle uses `https_enabled`.

```vala
			if (this.filesd.https_enabled && colon > 0) {
```

### 5. `ollmfilesd/Application.vala` — no warning gate

🚫 Not applied. `initialize()` stays `https.listen()` then `filesd.install()`. Phase 2 does not start the SSL socket when `socket` is not a LAN `host:port`. The daemon stays up on Unix and HTTPS. The UI subtitle already says which of those are running.


---

## Phase 2 — TLS and the same certificates (`✔️`)

- 🔷 `✔️` When `ssl_enabled` is on and `filesd.socket` is empty, not a LAN `host:port`, localhost, or outside **1024–65535**, do not start the SSL socket. Unix and HTTPS stay up. The Desktop server subtitle reports those. Do not stop `ollmfilesd`.
- 🔷 `✔️` The local network SSL server wraps the accepted bin stream in TLS (product CA leaf, same `Transport.Cert` install as `Https.listen`).
- 🔷 `✔️` Not a second HTTP server. First-byte JSON line mode stays out.
- 🔷 `✔️` Request a client certificate. Unknown cert: only `request_registration`. Approved cert: full bin RPC.
- 🔷 `✔️` Same `ClientCert` rows as HTTPS. Accept on either listener accepts both.
- 🔷 `✔️` No TLS on Windows `127.0.0.1`.
- 🔷 `✔️` No PROXY Protocol on this listener.
- 🔷 `✔️` Ban list: drop by peer IP before TLS, same as HTTPS (`HttpServer.banned_ips`).
- 🚫 Do not wrap `TcpListen`. That class stays the Windows localhost and CLI `--tcp` plaintext path.
- ℹ️ `listen.broadcast` still reaches only the Unix or CLI TCP listener. SSL clients are not on that list in this phase.
- ℹ️ The fd watch stays on the raw socket. Bin parse reads the TLS streams. A second request already sitting in the TLS buffer waits until the next ciphertext wake.

### 1. `libocrpc/Transport/Connection.vala` — TLS streams and the cert gate

**Why:** `start()` watches `stream.get_socket().get_fd()` and reads `stream.get_input_stream()`. A `GLib.TlsServerConnection` is an `IOStream`, not a `SocketConnection`, so the fd watch stays on the socket and bin reads `io` after the handshake. `ClientCert` lives in `ollmfilesd`, so the gate is a virtual method that defaults to allow. Unix and Windows plaintext stay open.

**Where:** Properties next to `stream`. `start()` builds the bin streams. `on_input_ready` calls `allow_request` before `dispatch`. The default method sits after `reply_error`.

**Depends on:** none.

#### Add

After `stream`, before `bin`.

```vala
		/**
		 * Plaintext bin streams after a TLS handshake.
		 *
		 * Null on Unix and plaintext TCP. The fd watch stays
		 * on {@link stream}.
		 */
		public GLib.IOStream? io { get; set; default = null; }

		/**
		 * SHA256 of the peer certificate DER, or empty.
		 */
		public string cert_fingerprint { get; set; default = ""; }
```

#### Remove

```vala
				var in_stream = new GLib.DataInputStream(
					this.stream.get_input_stream()
				);
				var out_stream = new GLib.DataOutputStream(
					this.stream.get_output_stream()
				);
```

#### Replace with

Fd watch is unchanged above this. `io` is set only by `SslConnection` after the handshake.

```vala
				var bin_in = this.stream.get_input_stream();
				var bin_out = this.stream.get_output_stream();
				if (this.io != null) {
					bin_in = this.io.get_input_stream();
					bin_out = this.io.get_output_stream();
				}
				var in_stream = new GLib.DataInputStream(bin_in);
				var out_stream = new GLib.DataOutputStream(bin_out);
```

#### Remove

```vala
				if (!request.dispatch()) {
					this.reply_error(request, (int) OLLMrpc.RpcErrorCode.METHOD_NOT_FOUND);
				}
```

#### Replace with

A false `allow_request` has already replied. Do not dispatch and do not send method-not-found.

```vala
				if (this.allow_request(request) && !request.dispatch()) {
					this.reply_error(request, (int) OLLMrpc.RpcErrorCode.METHOD_NOT_FOUND);
				}
```

#### Add

After `reply_error`, before the `emit_wait_poll` docblock.

```vala
		/**
		 * Return true when this request may run.
		 *
		 * Unix and plaintext TCP stay open.
		 * {@link OLLMfilesd.SslConnection} overrides this.
		 *
		 * @param request inbound RPC
		 * @return true when dispatch may run
		 */
		public virtual bool allow_request(OLLMrpc.Request request)
		{
			return true;
		}
```

### 2. `ollmfilesd/SslListen.vala` — new file

**Why:** The TLS accept path needs `ClientCert` and the product CA. Putting that inside `TcpListen` would TLS the Windows localhost socket. This file is the listener the plan names.

**Where:** New file `ollmfilesd/SslListen.vala`. `SslConnection` is its own file in ### 3.

**Depends on:** ### 1.

#### Add

New file `ollmfilesd/SslListen.vala`.

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMfilesd
{
	/**
	 * TLS bin listener for the local network SSL server.
	 *
	 * Binds ''filesd.socket'' when ''ssl_enabled'' is on and the
	 * address is a non-loopback ''host:port'' in 1024–65535.
	 * Otherwise {@link listen} returns false and the daemon stays
	 * up on Unix and HTTPS. Same product CA and {@link ClientCert}
	 * rows as {@link Https}.
	 */
	public class SslListen : GLib.Object
	{
		public OllmfilesdApplication app { get; private set; }
		public Gee.ArrayList<string> banned_ips {
			get; set; default = new Gee.ArrayList<string>();
		}

		private GLib.SocketService service {
			get; set; default = new GLib.SocketService();
		}
		private bool listening = false;
		private Gee.ArrayList<SslConnection> connections {
			get; set; default = new Gee.ArrayList<SslConnection>();
		}

		public SslListen(OllmfilesdApplication app)
		{
			this.app = app;
		}

		/**
		 * Bind the TLS bin socket from ''filesd.socket''.
		 *
		 * Returns false when SSL is off or the address is empty,
		 * loopback, or outside 1024–65535. Does not stop the
		 * daemon. Bind failure logs a warning and returns false.
		 *
		 * @return true when the SSL listener is up
		 */
		public bool listen()
		{
			if (this.listening) {
				return true;
			}
			var filesd = this.app.config.filesd;
			if (!filesd.ssl_enabled) {
				return false;
			}
			var socket = filesd.socket;
			var colon = socket.last_index_of(":");
			var host = "";
			var port = 0;
			if (colon > 0) {
				host = socket.substring(0, colon);
				int.try_parse(socket.substring(colon + 1), out port);
			}
			if (socket == "" || colon <= 0 || host == ""
				|| host == "127.0.0.1" || host == "localhost" || host == "::1"
				|| port < 1024 || port > 65535) {
				return false;
			}
			var tls_dir = GLib.Path.build_filename(this.app.data_dir, "tls");
			if (!GLib.FileUtils.test(tls_dir, GLib.FileTest.IS_DIR)) {
				GLib.DirUtils.create_with_parents(tls_dir, 0700);
			}
			var ca_pem = GLib.Path.build_filename(tls_dir, "ollmrpc-ca.pem");
			var ca_key = GLib.Path.build_filename(tls_dir, "ollmrpc-ca-key.pem");
			if (!GLib.FileUtils.test(ca_pem, GLib.FileTest.EXISTS)) {
				try {
					GLib.FileUtils.set_contents(ca_pem,
						(string) GLib.resources_lookup_data("/ollmrpc/ollmrpc-ca.pem",
							GLib.ResourceLookupFlags.NONE).get_data());
				} catch (GLib.Error e) {
					GLib.error("extract CA PEM: %s", e.message);
				}
			}
			if (!GLib.FileUtils.test(ca_key, GLib.FileTest.EXISTS)) {
				try {
					GLib.FileUtils.set_contents(ca_key,
						(string) GLib.resources_lookup_data("/ollmrpc/ollmrpc-ca-key.pem",
							GLib.ResourceLookupFlags.NONE).get_data());
				} catch (GLib.Error e) {
					GLib.error("extract CA key: %s", e.message);
				}
			}
			var cert = new OLLMrpc.Transport.Cert() {
				dir = tls_dir,
				ca_pem_path = ca_pem,
				ca_key_path = ca_key,
				server_san = true,
			};
			cert.ensure();
			var server_cert = cert.certificate;
			var parsed = new GLib.InetSocketAddress.from_string(host, (uint16) port);
			if (parsed == null) {
				return false;
			}
			this.service = new GLib.SocketService();
			var effective = (GLib.SocketAddress) parsed;
			try {
				this.service.add_address(
					effective,
					GLib.SocketType.STREAM,
					GLib.SocketProtocol.TCP,
					null,
					out effective
				);
			} catch (GLib.Error e) {
				GLib.warning("failed to bind SSL listener %s:%u: %s",
					host, (uint) port, e.message);
				return false;
			}
			this.service.incoming.connect((conn) => {
				var ip = "";
				try {
					var remote = conn.get_remote_address() as GLib.InetSocketAddress;
					if (remote != null) {
						ip = remote.get_address().to_string();
					}
				} catch (GLib.Error e) {
				}
				if (ip != "" && this.banned_ips.contains(ip)) {
					GLib.debug("dropping banned client IP %s", ip);
					try {
						conn.close();
					} catch (GLib.Error e) {
					}
					return true;
				}
				GLib.TlsServerConnection tls;
				try {
					tls = GLib.TlsServerConnection.@new(conn, server_cert);
				} catch (GLib.Error e) {
					GLib.warning("ssl accept failed: %s", e.message);
					return true;
				}
				tls.authentication_mode = GLib.TlsAuthenticationMode.REQUESTED;
				tls.accept_certificate.connect((peer_cert, errors) => {
					return true;
				});
				tls.handshake_async.begin(GLib.Priority.DEFAULT, null, (obj, res) => {
					try {
						tls.handshake_async.end(res);
					} catch (GLib.Error e) {
						GLib.warning("ssl handshake failed: %s", e.message);
						return;
					}
					var fingerprint = "";
					var peer = tls.get_peer_certificate();
					if (peer != null) {
						fingerprint = GLib.Checksum.compute_for_data(
							GLib.ChecksumType.SHA256, peer.certificate.data);
					}
					var rpc = new SslConnection(conn, this.app) {
						io = tls,
						cert_fingerprint = fingerprint
					};
					rpc.start();
					this.connections.add(rpc);
				});
				return true;
			});
			this.service.start();
			this.listening = true;
			GLib.debug("SSL listening on %s:%u", host, (uint) port);
			var cert_q = ClientCert.query(this.app.project_manager.db);
			var banned = new Gee.ArrayList<ClientCert>();
			cert_q.select("WHERE status = -1 ORDER BY created DESC", banned);
			var ban_cutoff = new GLib.DateTime.now_utc().to_unix() - (30 * 24 * 60 * 60);
			foreach (var row in banned) {
				if (row.created < ban_cutoff) {
					cert_q.deleteId(row.id);
					continue;
				}
				if (row.ip != "" && !this.banned_ips.contains(row.ip)) {
					this.banned_ips.add(row.ip);
				}
			}
			return true;
		}

		/**
		 * Stop the SSL listener and its bin connections.
		 */
		public void stop()
		{
			if (!this.listening) {
				return;
			}
			this.listening = false;
			this.service.stop();
			this.service = new GLib.SocketService();
			foreach (var connection in this.connections) {
				connection.stop();
			}
			this.connections.clear();
		}
	}
}
```

### 3. `ollmfilesd/SslConnection.vala` — new file

**Why:** One class per file. The cert gate stays out of `libocrpc`.

**Where:** New file. `allow_request` is the same gate as `Https.allow_rpc`.

**Depends on:** ### 1.

#### Add

New file `ollmfilesd/SslConnection.vala`.

```vala
namespace OLLMfilesd
{
	/**
	 * Bin connection on the local network SSL server.
	 *
	 * {@link allow_request} matches {@link Https.allow_rpc}.
	 * {@link SslListen} constructs one after the TLS handshake.
	 */
	public class SslConnection : OLLMrpc.Transport.Connection
	{
		public OllmfilesdApplication app { get; construct; }

		public SslConnection(GLib.SocketConnection stream, OllmfilesdApplication app)
		{
			GLib.Object(stream: stream, app: app);
		}

		public override bool allow_request(OLLMrpc.Request request)
		{
			switch (request.method) {
				case "RPC-ClientCert.pending_cert":
				case "RPC-ClientCert.client_cert":
					this.reply(request, new OLLMrpc.Response() {
						error = new OLLMrpc.Error(
							(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "local admin only")
					});
					return false;
			}
			if (request.method == "RPC-ClientCert.request_registration") {
				return true;
			}
			if (this.cert_fingerprint == "") {
				this.reply(request, new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
						"client certificate required")
				});
				return false;
			}
			var rows = new Gee.ArrayList<ClientCert>();
			var cert_q = ClientCert.query(this.app.project_manager.db);
			var int_binds = new Gee.HashMap<string, int>();
			var text_binds = new Gee.HashMap<string, string>();
			text_binds.set("fingerprint", this.cert_fingerprint);
			cert_q.selectWhere(
				"WHERE fingerprint = $fingerprint AND status = 1",
				int_binds, text_binds, rows);
			if (rows.size > 0) {
				return true;
			}
			this.reply(request, new OLLMrpc.Response() {
				error = new OLLMrpc.Error(
					(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
					"certificate not registered")
			});
			return false;
		}
	}
}
```

### 4. `ollmfilesd/Application.vala` — start and stop

**Why:** `initialize` already leaves Unix and HTTPS up. This adds the SSL listener beside HTTPS. A false `listen` does not abort the process.

**Where:** Field next to `https_listen`. Call after `https.listen()`, before `filesd.install()`. `cleanup` stops it with HTTPS.

**Depends on:** ### 2 and ### 3.

#### Add

After the `https_listen` field.

```vala
		public OLLMfilesd.SslListen? ssl_listen { get; private set; default = null; }
```

#### Add

After the `https.listen()` block, before `this.config.filesd.install()`.

```vala
			var ssl = new OLLMfilesd.SslListen(this);
			if (ssl.listen()) {
				this.ssl_listen = ssl;
			}
```

#### Add

Inside `cleanup`, after the `https_listen` stop block.

```vala
			if (this.ssl_listen != null) {
				this.ssl_listen.stop();
				this.ssl_listen = null;
			}
```

### 5. `ollmfilesd/ClientCert.vala` — ban the SSL listener too

**Why:** Reject and ban already append the peer IP to `https_listen.banned_ips`. The SSL listener has its own list. A ban on either admin path has to hit both, or a banned IP still completes the TLS handshake on the socket that was not updated.

**Where:** The auto-ban block and the `ban` case, immediately after each HTTPS `banned_ips.add`.

**Depends on:** ### 4.

#### Remove

```vala
					if (this.app.https_listen != null
						&& !this.app.https_listen.banned_ips.contains(rejected.ip)) {
						this.app.https_listen.banned_ips.add(rejected.ip);
					}
```

#### Replace with

Auto-ban updates both listeners.

```vala
					if (this.app.https_listen != null
						&& !this.app.https_listen.banned_ips.contains(rejected.ip)) {
						this.app.https_listen.banned_ips.add(rejected.ip);
					}
					if (this.app.ssl_listen != null
						&& !this.app.ssl_listen.banned_ips.contains(rejected.ip)) {
						this.app.ssl_listen.banned_ips.add(rejected.ip);
					}
```

#### Remove

```vala
					if (this.app.https_listen != null && ban_rows.get(0).ip != ""
						&& !this.app.https_listen.banned_ips.contains(ban_rows.get(0).ip)) {
						this.app.https_listen.banned_ips.add(ban_rows.get(0).ip);
					}
```

#### Replace with

Manual ban updates both listeners.

```vala
					if (this.app.https_listen != null && ban_rows.get(0).ip != ""
						&& !this.app.https_listen.banned_ips.contains(ban_rows.get(0).ip)) {
						this.app.https_listen.banned_ips.add(ban_rows.get(0).ip);
					}
					if (this.app.ssl_listen != null && ban_rows.get(0).ip != ""
						&& !this.app.ssl_listen.banned_ips.contains(ban_rows.get(0).ip)) {
						this.app.ssl_listen.banned_ips.add(ban_rows.get(0).ip);
					}
```

### 6. `ollmfilesd/meson.build`

**Why:** Both new files have to be in the `ollmfilesd` sources or they will not build.

**Where:** Next to `Https.vala`.

**Depends on:** ### 2 and ### 3.

#### Remove

```meson
  'Https.vala',
```

#### Replace with

```meson
  'Https.vala',
  'SslListen.vala',
  'SslConnection.vala',
```

---


## Suggested order

1. ✔️ Phase 1 — rename `enabled` to `https_enabled`. Add `ssl_enabled`. Unix stays up. Windows localhost TCP stays plaintext. No warning-only gate.
2. ✔️ Phase 2 — `OLLMfilesd.SslListen` TLS bin on `filesd.socket`. Skip when the address is not a LAN `host:port`. Same `ClientCert` rows. No TLS on `127.0.0.1`. `TcpListen` stays plaintext. `SslConnection` is its own file.
3. ⏳ Desktop server rows and the LAN client — [`8.2.8.13`](RPC-8.2.8.13-filesd-desktop-server-rows.md).
4. ⏳ Windows per-user service and the Windows host list — [`8.2.8.14`](RPC-8.2.8.14-LATER-filesd-windows-desktop-server.md), later.
5. ℹ️ Windows localhost TCP stays a Running row. Changing its port is the bug log, not these plans.

---

## LLM notes

- ℹ️ Parent 8.2.8 HTTPS UI and Android takeover stay on their sub-plans.
- 🚫 nginx stream / PROXY Protocol on `filesd.socket`.
- 🚫 Advertising this socket on the public internet.
- 🚫 Replacing HTTPS with TCP for WAN / Android-over-internet.
- 🚫 Migrating the old `filesd.enabled` JSON key into `https_enabled`.
- 🚫 Stopping `ollmfilesd` because `ssl_enabled` is on and `socket` is bad. Skip the SSL socket only.
- 🚫 Desktop server rows or the LAN client in this file. That is [`8.2.8.13`](RPC-8.2.8.13-filesd-desktop-server-rows.md).
- 🚫 A Windows per-user service or a Windows host list here. That is [`8.2.8.14`](RPC-8.2.8.14-LATER-filesd-windows-desktop-server.md).
- 🚫 New CLI flags for listen host/port (config object already exists).
- 🚫 Wrapping `TcpListen` for the local network SSL server. That class stays plaintext.
- 🚫 `GLib.error` when `ssl_enabled` is on and `socket` is not a LAN `host:port`.
- 🚫 Further helpers beyond the named `SslListen`, `SslConnection`, and `Connection.allow_request`.

