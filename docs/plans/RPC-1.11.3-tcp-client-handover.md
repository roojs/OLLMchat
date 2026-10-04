# RPC-1.11.3 — TCP client handover

> **Do not update `docs/plans/RPC-1.0-summary.md` for this sub-plan** until it is done and archived.

**Status:** proposed

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala follows `docs/coding-standards.md`.

**Parent:** [`RPC-1.11-URGENT-vpn-local-pin-pairing.md`](RPC-1.11-URGENT-vpn-local-pin-pairing.md)

**Depends on:** [`RPC-1.11.2`](RPC-1.11.2-android-discovery-and-pair-cli.md) — the phone already stores addresses and probes them. This plan is the connection that stays open after that probe.

---

## Purpose

- **🔷** Final handover for the OLLMchat file daemon (`ollmfilesd`).
- **🔷** Remove that daemon's HTTP file server. Replace it with the TCP socket.
- **🔷** The file-daemon client via TCP works.
- **🔷** `OLLMrpc.Transport.HttpClient` is not used to talk to `ollmfilesd`. It is not deleted from the RPC library (`libocrpc`).
- **🔷** Localhost still accepts cleartext. It does not need TLS. Windows especially.
- **🔷** `⏳` The `ollmapp` file-daemon connection (`Window`, `FileConnectionRow`, Android `OllmchatWindow`) stops constructing `OLLMrpc.Transport.HttpClient` and uses `OLLMrpc.Client` on `tcp://` instead.
- **🔷** `⏳` Remote `tcp://` sets a `tls` flag and wraps `TlsClientConnection`. Localhost and Windows `ClientBoot` leave `tls` false, so `ollmfilesd`'s `TcpListen` on `127.0.0.1` stays cleartext.
- **🔷** `⏳` After the address probe, `ProjectManager` keeps that client.
- **🔷** `⏳` Remove `ollmfilesd/Https.vala` and the `filesd.https` settings that start it. That is the file daemon's HTTP server, not `libocrpc`.
- **🔷** Same-machine Linux stays the Unix socket.
- **🔷** `⏳` When that connection drops, try to reconnect.
- **🔷** `⏳` On the phone, walking off the local network onto the VPN uses the stored VPN address. VPN up or VPN down drops the current socket and tries the stored addresses a few times.
- **🔷** `⏳` If those tries fail, and the user is actually using the file daemon, tell them it can no longer connect. Follow the existing disabling of `ollmfilesd`: state `UNREACHABLE`, the banner `The desktop environment is unavailable.`, leave Agent Pi, and use Chatter. `AgentDropdown` already hides Agent Pi unless the state is `LIVE` or `SOCKET`.
- **💩** `⏳` `ollmfilesd`'s `SslListen.broadcast` carries notifications.
- **🚫** Do not edit `poll_drain_readable`, `on_read`, `call_poll`, `poll_close`, or `read_channel`. That polling is GNOME shell.

---

## Current behaviour

- **ℹ️** `SslListen` accepts TLS on `filesd.socket`. `probe_addresses` in `ollmapp/android/OllmchatWindow.vala` handshakes, sends hello, then closes. It stores `tcp://host:port` and never calls `replace_rpc`.
- **ℹ️** `OLLMrpc.Client` `tcp://` is plaintext. On Android `connect` then drops the socket: the read watch is `IOChannel.unix_new`.
- **ℹ️** `ollmapp` `Window.initialize_client` and `FileConnectionRow` still build `OLLMrpc.Transport.HttpClient` to reach `ollmfilesd`. The type itself lives in `libocrpc` and is also used by the RPC HTTP tests.
- **ℹ️** `Application.broadcast` writes only `this.listen` (Unix or plaintext `--tcp`). `SslListen` keeps its connections and has no broadcast, so a phone on that socket hears nothing.
- **ℹ️** `Connection.start` on the daemon already reads and writes the TLS `io` when set. The Linux read watch there is fine.
- **💩** This plan does not retarget that daemon read watch.

---

## Proposed behaviour

- **🔷** `ollmfilesd` no longer serves HTTP. The file-daemon client uses TCP. `libocrpc`'s `Transport.HttpClient` stays.
- **🔷** Localhost cleartext stays, with no TLS. Windows especially.
- **💩** Remote file connections set `tls` and present the device certificate. `connect` wraps TLS only then. The existing `IOChannel` watch is left alone.
- **💩** `TcpListen` on `127.0.0.1` is not given a handshake. Windows `ClientBoot` does not set `tls`.
- **💩** After the address probe, `ProjectManager` keeps a `Client` on that `tcp://` URL.
- **💩** `Application.broadcast` also writes each `SslListen` connection.
- **💩** Trust for that remote client is the on-disk CA (`product_ca_resource = false`).
- **🔷** A dropped phone connection tries the stored addresses a few times, including the VPN address when the local one is gone, and the local address when the VPN is gone.
- **🔷** After those tries fail, if the user is using the file daemon, the phone follows the startup failure path already in `OllmchatWindow.initialize_client`: `UNREACHABLE`, that banner, Chatter instead of Agent Pi.

---

## Phase 1 — `Client` holds a TLS TCP socket

### Goal

- **🔷** `⏳` The client via TCP works. Localhost stays cleartext, with no TLS. Windows especially.
- **💩** `⏳` `connect` to `tcp://` with `tls` set handshakes, sends hello, and returns true while the socket stays open.
- **💩** `⏳` `connect` to `tcp://127.0.0.1` with `tls` left false is still cleartext. This phase does not put TLS on `TcpListen`.
- **🚫** Do not edit `poll_drain_readable`, `on_read`, `call_poll`, `poll_close`, or `read_channel` in `libocrpc/Client.vala`. That is the GNOME shell poll path.
- **💩** `⏳` `call` on the existing read watch receives the reply. A notification written by the daemon arrives on `Client.notification`. The watch itself stays `IOChannel`.

### 1. `libocrpc/Client.vala` — TLS fields on `Client`

**Why:** 💩 The file client has to present its certificate. `HttpClient` is the type going away, so the fields move here. `tls` false keeps plaintext `tcp://`.

**Where:** property block, after `call_timeout_seconds`.

**Depends on:** none.

#### Add — after `call_timeout_seconds`. `tls` selects the TLS wrap; the certificate and trust are set by the caller before `connect`.

```vala
		/**
		 * Wrap a ''tcp://'' connect in TLS before the bin streams.
		 *
		 * False leaves that connect plaintext (Windows local daemon).
		 */
		public bool tls { get; set; default = false; }

		/**
		 * Client certificate presented when {@link tls} is true.
		 */
		public GLib.TlsCertificate tls_certificate { get; set; }

		/**
		 * CA trust for the server certificate when {@link tls} is true.
		 */
		public GLib.TlsDatabase tls_database { get; set; }
```

### 2. `libocrpc/Client.vala` — `connect`: TLS wrap, then a socket read source

**Why:** 💩 The bin streams have to sit on the TLS connection, and the read watch cannot be a Unix `IOChannel` or Android drops the socket.

**Where:** `connect`, after `this.socket` is assigned (both the `boot` path and the direct path), and the `#if ANDROID` bail that follows `this.connected = true`.

**Depends on:** §1.

#### Add — immediately before `this.input = new GLib.DataInputStream(...)`. When `tls` is set, handshake on a `TlsClientConnection` and point the bin streams at it. The watch stays on `this.socket`.

```vala
			var bin_in = this.socket.get_input_stream();
			var bin_out = this.socket.get_output_stream();
			if (this.protocol == Protocol.TCP && this.tls) {
				try {
					var tls_link = GLib.TlsClientConnection.@new(this.socket, null);
					tls_link.certificate = this.tls_certificate;
					tls_link.database = this.tls_database;
					tls_link.accept_certificate.connect((peer_cert, errors) => {
						return peer_cert != null
							&& (errors & ~GLib.TlsCertificateFlags.BAD_IDENTITY) == 0;
					});
					yield tls_link.handshake_async();
					bin_in = tls_link.get_input_stream();
					bin_out = tls_link.get_output_stream();
				} catch (GLib.Error e) {
					this.connect_error = e.message;
					GLib.critical("connect %s: %s", this.socket_path, this.connect_error);
					return false;
				}
			}
```

#### Replace with — the two lines that build `input` and `output` read `bin_in` / `bin_out`.

```vala
			this.input = new GLib.DataInputStream(bin_in);
			this.output = new GLib.DataOutputStream(bin_out);
```

The `#if ANDROID` bail, the `IOChannel` watch, `on_read`, and `poll_drain_readable` stay as they are.

### 3. `ollmfilesd/SslListen.vala` — `broadcast` to accepted connections

**Why:** 💩 `Application.broadcast` never reaches a phone on `filesd.socket`. Notifications are the reason the socket stays open.

**Where:** next to `stop()`. `Application.broadcast` calls it after `this.listen.broadcast`.

**Depends on:** none. The client in §2 has to be connected before a notification can be observed.

#### Add — same loop as `OLLMrpc.Transport.TcpListen.broadcast`.

```vala
		/**
		 * Write one object on every accepted TLS connection.
		 *
		 * @param gobject bin serializable, usually a notification
		 */
		public void broadcast(GLib.Object gobject)
		{
			foreach (var connection in this.connections) {
				connection.write(gobject);
			}
		}
```

#### Add — in `ollmfilesd/Application.vala` `broadcast`, after the `this.listen` write.

```vala
			if (this.ssl_listen != null) {
				this.ssl_listen.broadcast(notification);
			}
```

---

## Phase 2 — the app uses that client

### Goal

- **🔷** `⏳` The `ollmapp` file-daemon client works over TCP, on Android and on the desktop, and does not use `OLLMrpc.Transport.HttpClient` for `ollmfilesd`.
- **💩** `⏳` Android startup, after an address answers, sets `ProjectManager` to a TLS `Client` on that `tcp://` URL and leaves it connected.
- **💩** `⏳` Desktop remote connect does the same.
- **💩** `⏳` Trust is the paired CA on disk (`product_ca_resource = false`).

### 4. `ollmapp/android/OllmchatWindow.vala` — `probe_addresses` then `replace_rpc`

**Why:** 💩 The probe currently proves an address and closes. The chat then runs with no remote RPC.

**Where:** `initialize_client`, the block that sets `desktop_reached`. `probe_addresses` still picks the address and writes `filesd_client.url`. The one-shot hello inside the probe can stay as the reachability test. The held connection is the `Client` below.

**Depends on:** Phase 1.

#### Add — when `desktop_reached` is true, before `register_default_agents`. Build the client from the url the probe stored.

```vala
			if (desktop_reached) {
				var tls = new OLLMrpc.Transport.Cert() {
					dir = GLib.Path.build_filename(
						GLib.Environment.get_user_data_dir(), "ollmchat"),
					cert_pem = "client.pem",
					key_pem = "client-key.pem",
					cn = "ollmchat-device",
					product_ca_resource = false
				};
				tls.ensure();
				var rpc = new OLLMrpc.Client("", "", config.filesd_client.url) {
					tls = true,
					tls_certificate = tls.certificate,
					tls_database = tls.trust
				};
				this.project_manager.replace_rpc(rpc);
				var hello = new OLLMrpc.Request() {
					method = "RPC-Daemon.hello",
					args = OLLMrpc.args("is", 1, "ollmchat")
				};
				desktop_reached = yield rpc.connect(hello);
			}
```

### 5. `ollmapp/Window.vala` — `initialize_client` remote branch

**Why:** 💩 Desktop `ollmapp` still constructs `OLLMrpc.Transport.HttpClient` to reach `ollmfilesd`. The class in `libocrpc` stays.

**Where:** `initialize_client`, the `if (config.filesd_client.url != "")` branch.

**Depends on:** Phase 1.

#### Remove

```vala
				tls.ensure();
				var http = new OLLMrpc.Transport.HttpClient(config.filesd_client.url) {
					bin_body = true,
					tls_certificate = tls.certificate,
					tls_database = tls.trust
				};
				this.project_manager.replace_rpc(
					new OLLMrpc.Client("", "", config.filesd_client.url) {
						http = http
					}
				);
```

#### Replace with — same `Cert` block above this, with `product_ca_resource = false`.

```vala
				tls.ensure();
				this.project_manager.replace_rpc(
					new OLLMrpc.Client("", "", config.filesd_client.url) {
						tls = true,
						tls_certificate = tls.certificate,
						tls_database = tls.trust
					}
				);
```

### 6. `ollmapp/SettingsDialog/FileConnectionRow.vala` — `check` and `reconnect`

**Why:** 💩 Both still call `OLLMrpc.Transport.HttpClient` against `ollmfilesd`. The class in `libocrpc` stays.

**Where:** `check` builds an `HttpClient` and `yield http.call`. `reconnect` builds one when `remote` is true.

**Depends on:** Phase 1.

#### Remove — `check`, the `HttpClient` and its `call`.

```vala
			var http = new OLLMrpc.Transport.HttpClient(this.client.url) {
				bin_body = true,
				tls_certificate = tls.certificate,
				tls_database = tls.trust
			};
			this.check_button.sensitive = false;
			try {
				yield http.call(new OLLMrpc.Request() {
					method = "RPC-Daemon.hello",
					args = OLLMrpc.args("is", 1, "ollmchat")
				});
			} catch (GLib.Error e) {
				GLib.debug("file connection check: %s", e.message);
				this.check_button.sensitive = true;
				this.expander.subtitle = "Requested: " + e.message;
				return;
			}
```

#### Replace with — `product_ca_resource = false` on the `Cert` above. Hello goes through `Client.connect`. The old `catch` body is inlined on `connect_error`.

```vala
			var rpc = new OLLMrpc.Client("", "", this.client.url) {
				tls = true,
				tls_certificate = tls.certificate,
				tls_database = tls.trust
			};
			this.check_button.sensitive = false;
			if (!yield rpc.connect(new OLLMrpc.Request() {
				method = "RPC-Daemon.hello",
				args = OLLMrpc.args("is", 1, "ollmchat")
			})) {
				GLib.debug("file connection check: %s", rpc.connect_error);
				this.check_button.sensitive = true;
				this.expander.subtitle = "Requested: " + rpc.connect_error;
				return;
			}
```

#### Remove — `reconnect`, remote `HttpClient`.

```vala
				var http = new OLLMrpc.Transport.HttpClient(this.client.url) {
					bin_body = true,
					tls_certificate = tls.certificate,
					tls_database = tls.trust
				};
				rpc = new OLLMrpc.Client("", "", this.client.url) { http = http };
```

#### Replace with

```vala
				rpc = new OLLMrpc.Client("", "", this.client.url) {
					tls = true,
					tls_certificate = tls.certificate,
					tls_database = tls.trust
				};
```

Set `product_ca_resource = false` on that `Cert` too.

### 7. `ollmapp/SettingsDialog/FileConnectionAdd.vala` — stop rewriting a host into an HTTPS URL

**Why:** 💩 `request()` only prefixes `https://` and returns. That URL is what the old client posted.

**Where:** `request()`.

**Depends on:** none.

#### Remove

```vala
			if (url.has_prefix("http://")) {
				url = "https://" + url.substring("http://".length);
			}
			if (!url.has_prefix("https://")) {
				url = "https://" + url;
			}
```

The dialog description and the URL row subtitle drop the HTTPS wording. Pairing stays **Allow New Device** and the phone dialog. This method does not grow a second pair flow.

---

## Phase 3 — `ollmfilesd` stops serving HTTP

### Goal

- **🔷** `⏳` The HTTP file server on `ollmfilesd` is removed. `ollmapp` does not use `OLLMrpc.Transport.HttpClient` to reach that daemon.
- **🚫** Do not delete `libocrpc/Transport/HttpClient.vala`, `libocrpc/Transport/HttpServer.vala`, `Client.http`, or the `libocrpc` HTTP tests (`http-client-test.vala`, `http-server-test.vala`, `http-https-test.vala`, `http-routes-test.vala`, `http-bin-session-test.vala`).
- **💩** `⏳` Remove `ollmfilesd/Https.vala`, `https_listen`, the `listen()` call, and the `cleanup` stop. Drop that file from `ollmfilesd/meson.build`.
- **💩** `⏳` Delete `filesd.https`, `https_enabled`, and `proxy` from `libollmchat/Settings/Filesd.vala`. `ollmapp` `FileServerRow` drops the HTTPS expander. The local network SSL row stays.
- **💩** `⏳` `tests/rpc/filesd-http-client-test.vala` calls `ollmfilesd` over HTTP. With that server gone it has nothing to call.
- **💩** `⏳` `docs/filesd-behind-nginx-proxy.md` currently tells an operator to set `filesd.https` on `ollmfilesd`.

### 8. `ollmfilesd` — stop the HTTPS listener

**Why:** 💩 `ollmfilesd/Https.vala` is the HTTP file server. `libocrpc`'s `Transport.HttpServer` is the library it subclasses, and that library type stays.

**Where:** `ollmfilesd/Application.vala` constructs `Https` and stores `https_listen`. `ollmfilesd/meson.build` lists `Https.vala`.

**Depends on:** Phase 2, so `ollmapp` is no longer posting to that listener.

---

## Suggested order

1. Phase 1 — `Client` TLS connect and `SslListen.broadcast`
2. Phase 2 — Android and desktop use that client
3. Phase 3 — `ollmfilesd` stops its HTTP server. `libocrpc`'s `Transport.HttpClient` stays.

---

## LLM notes

- **🚫** Do not delete `OLLMrpc.Transport.HttpClient` or `OLLMrpc.Transport.HttpServer` from `libocrpc`. The file daemon stops using them. The RPC library keeps them.
- **💩** Leave the same-machine Unix socket. The request was to replace `ollmfilesd`'s HTTP server with TCP, and to keep localhost cleartext on Windows.
- **🚫** Do not edit `poll_drain_readable`, `on_read`, `call_poll`, `poll_close`, or `read_channel`. That polling belongs to GNOME shell.
- **💩** No second client class. The wrap is inside `OLLMrpc.Client.connect`.
