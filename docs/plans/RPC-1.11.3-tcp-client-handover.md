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
- **🔷** `✔️` `ollmapp` talks to `ollmfilesd` with `OLLMrpc.Client` on `tcp://`. It does not call `Transport.HttpClient.call` for that daemon.
- **🔷** `⏳` A remote `tcp://` handshake uses the certificate kept for that server. `ollmapp` does not construct `Transport.HttpClient` for `ollmfilesd`. Localhost `ClientBoot` on `127.0.0.1` stays cleartext.
- **🚫** Do not add `tls`, `tls_certificate`, or `tls_database` on `OLLMrpc.Client`.
- **🔷** `✔️` After the address probe, `ProjectManager` keeps that client.
- **🔷** Same-machine Linux stays the Unix socket.
- **ℹ️** Removing `ollmfilesd/Https.vala` and the `filesd.https` settings is [`RPC-1.11.4`](RPC-1.11.4-ollmfilesd-stop-http.md).
- **ℹ️** Reconnect after the socket drops is [`RPC-1.11.5`](RPC-1.11.5-phone-reconnect.md).
- **🔷** `✔️` `ollmfilesd`'s `SslListen.broadcast` carries notifications.
- **🔷** `⏳` The phone keeps one certificate per server. Connecting to a server uses the certificate that server supplied.
- **🚫** Do not edit `poll_drain_readable`, `on_read`, `call_poll`, `poll_close`, or `read_channel`. That polling is GNOME shell.

---

## Current behaviour

- **ℹ️** `SslListen` accepts TLS on `filesd.socket`. `probe_addresses` in `ollmapp/android/OllmchatWindow.vala` runs at startup only. It tries each stored address once. None answering sets `UNREACHABLE`, shows `The desktop environment is unavailable.`, and opens Chatter. Nothing retries after a later drop.
- **ℹ️** `OLLMrpc.Client` `tcp://` is plaintext. On Android `connect` then drops the socket: the read watch is `IOChannel.unix_new`.
- **ℹ️** `ollmapp` `Window.initialize_client` and `FileConnectionRow` still build `OLLMrpc.Transport.HttpClient` to reach `ollmfilesd`. The type itself lives in `libocrpc` and is also used by the RPC HTTP tests.
- **ℹ️** `Application.broadcast` writes only `this.listen` (Unix or plaintext `--tcp`). `SslListen` keeps its connections and has no broadcast, so a phone on that socket hears nothing.
- **ℹ️** `Connection.start` on the daemon already reads and writes the TLS `io` when set. The Linux read watch there is fine.
- **💩** This plan does not retarget that daemon read watch.
- **ℹ️** Pairing stores the server's reply in one place. `FileConnectionAdd` writes the signed client PEM and the CA PEM to `{user_data}/ollmchat/client.pem` and `ollmrpc-ca.pem`. The phone's key stays `client-key.pem`. `probe_addresses`, `Window.initialize_client`, and `FileConnectionRow` all load those same names. A second server overwrites them. `FilesdClient` is one row. The reply does not include the server's `client_cert` row id.

---

## Proposed behaviour

- **🔷** `ollmfilesd` no longer serves HTTP. The file-daemon client uses TCP. `libocrpc`'s `Transport.HttpClient` stays.
- **🔷** Localhost cleartext stays, with no TLS. Windows especially.
- **🔷** A remote `tcp://` handshake uses the certificate kept for that server. The existing `IOChannel` watch is left alone.
- **🔷** `TcpListen` on `127.0.0.1` is not given a handshake. Windows `ClientBoot` does not set `http`.
- **🔷** After the address probe, `ProjectManager` keeps a `Client` on that `tcp://` URL.
- **🔷** `Application.broadcast` also writes each `SslListen` connection.
- **🔷** The phone keeps one certificate per server. Pairing with a second server leaves the first server's certificate in place.
- **🔷** Connecting to a server uses the certificate that server supplied.
- **🔷** A dropped phone connection tries the stored addresses a few times, including the VPN address when the local one is gone, and the local address when the VPN is gone.
- **🔷** After those tries fail, if the user is using the file daemon, the phone follows the startup failure path already in `OllmchatWindow.initialize_client`: `UNREACHABLE`, that banner, Chatter instead of Agent Pi.

---

## Phase 1 — `Client` holds a TLS TCP socket

### Goal

- **🔷** `✔️` The client via TCP works. Localhost stays cleartext, with no TLS. Windows especially.
- **🔷** `✔️` `connect` to a remote `tcp://` handshakes with the certificate kept for that server, sends hello, and returns true while the socket stays open.
- **🔷** `✔️` `connect` to `tcp://127.0.0.1` is still cleartext. This phase does not put TLS on `TcpListen`.
- **🚫** Do not edit `poll_drain_readable`, `on_read`, `call_poll`, `poll_close`, or `read_channel` in `libocrpc/Client.vala`. That is the GNOME shell poll path.
- **💩** `⏳` `call` on the existing read watch receives the reply. A notification written by the daemon arrives on `Client.notification`. The watch itself stays `IOChannel`.

### 1. `libocrpc/Client.vala` — `connect`: TLS on a remote `tcp://` socket

**Why:** `tcp://` connect is plaintext. `SslListen` is TLS. The handshake uses the certificate kept for that server.

**Where:** `connect`, after `this.socket` is assigned (both the `boot` path and the direct path), immediately before `this.input = new GLib.DataInputStream(...)`.

**Depends on:** none.

#### Add — before the `DataInputStream` line. A remote `tcp://` handshakes. `tcp://127.0.0.1` stays cleartext. No new properties. `certificate` and `database` are filled in later from the certificate kept for that server.

`GLib.TlsClientConnection` is an interface. `TlsClientConnection.new` is a static factory, not a Vala creation method, so a `{ certificate = …, database = … }` initializer on that call does not compile. The factory's two arguments are the construct properties `base_io_stream` and `server_identity`. `TlsConnection.certificate` and `TlsConnection.database` are ordinary `{ get; set; }` properties, so they are assigned after `@new` returns, the same way `FileConnectionAdd` sets them on the second handshake.

```vala
			var bin_in = this.socket.get_input_stream();
			var bin_out = this.socket.get_output_stream();
			if (this.protocol == Protocol.TCP
				&& !this.socket_path.has_prefix("tcp://127.0.0.1")) {
				try {
					var tls_link = GLib.TlsClientConnection.@new(this.socket, null);
					// certificate and database are filled in later
					// from the certificate kept for this server.
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

#### Remove — the two lines that build `input` and `output` from `this.socket`.

```vala
			this.input = new GLib.DataInputStream(this.socket.get_input_stream());
			this.output = new GLib.DataOutputStream(this.socket.get_output_stream());
```

#### Replace with — those two lines read `bin_in` / `bin_out`.

```vala
			this.input = new GLib.DataInputStream(bin_in);
			this.output = new GLib.DataOutputStream(bin_out);
```

The `#if ANDROID` bail, the `IOChannel` watch, `on_read`, and `poll_drain_readable` stay as they are.

### 3. `ollmfilesd/SslListen.vala` — `broadcast` to accepted connections

**Why:** `Application.broadcast` never reaches a phone on `filesd.socket`. Notifications are the reason the socket stays open.

**Where:** next to `stop()`. `Application.broadcast` calls it after `this.listen.broadcast`.

**Depends on:** none. The client in §4 has to be connected before a notification can be observed.

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

- **🔷** `✔️` The `ollmapp` file-daemon client works over TCP, on Android and on the desktop, and does not use `OLLMrpc.Transport.HttpClient` for `ollmfilesd`.
- **🔷** `✔️` Android startup, after an address answers, sets `ProjectManager` to a TLS `Client` on that `tcp://` URL and leaves it connected.
- **🔷** `✔️` Desktop remote connect does the same.
- **ℹ️** `Cert.ensure` loads the CA file already on disk. It does not copy a CA out of the app.

### 4. `ollmapp/android/OllmchatWindow.vala` — `probe_addresses` then `replace_rpc`

**Why:** 💩 The probe currently proves an address and closes. The chat then runs with no remote RPC.

**Where:** `initialize_client`, after `probe_addresses`. `is_desktop_connected` is true when this startup tries the file daemon: stored addresses exist and the saved state is `ENABLED`, `LIVE`, `UNREACHABLE`, or `SOCKET`. `REQUESTED` and `DISABLED` leave both flags false and skip the file daemon. `is_desktop_available` is the probe's return: one stored `host:port` finished TLS and `RPC-Daemon.hello` replied `ok`. On that reply the probe writes `filesd_client.url` as `tcp://host:port` and sets state `SOCKET`. Later, both flags true opens Agent Pi and sets `LIVE`. Connected and not available sets `UNREACHABLE`, the banner, and Chatter. The one-shot hello inside the probe stays the reachability test. The held connection is the `Client` below.

**Depends on:** Phase 1.

#### Add — when `is_desktop_available` is true, before `register_default_agents`. Build the client from the url the probe stored. The certificate directory and file names are not set here.

```vala
			if (is_desktop_available) {
				// Certificate for this server is filled in later on the handshake.
				var rpc = new OLLMrpc.Client("", "", config.filesd_client.url);
				this.project_manager.replace_rpc(rpc);
				var hello = new OLLMrpc.Request() {
					method = "RPC-Daemon.hello",
					args = OLLMrpc.args("is", 1, "ollmchat")
				};
				is_desktop_available = yield rpc.connect(hello);
			}
```

### 5. `ollmapp/Window.vala` — `initialize_client` remote branch

**Why:** 💩 Desktop `ollmapp` still constructs `OLLMrpc.Transport.HttpClient` to reach `ollmfilesd`. The class in `libocrpc` stays.

**Where:** `initialize_client`, the `if (config.filesd_client.url != "")` branch, and the `rpc.connect` call that follows it.

**Depends on:** Phase 1.

#### Remove

```vala
				var tls = new OLLMrpc.Transport.Cert() {
					dir = GLib.Path.build_filename(GLib.Environment.get_user_data_dir(), 
							"ollmchat"),
					cert_pem = "client.pem",
					key_pem = "client-key.pem",
					cn = "ollmchat-device",
				};
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

#### Replace with — the socket path is `tcp://`. This branch does not construct `Transport.HttpClient`. The certificate for this server is filled in later on the handshake.

```vala
				this.project_manager.replace_rpc(
					new OLLMrpc.Client("", "", config.filesd_client.url)
				);
```

#### Remove — the `connect` that always passes `ClientBoot`.

```vala
			if (!yield this.project_manager.rpc.connect(hello, new OLLMrpc.ClientBoot())) {
				if (this.busy_dialog != null) {
					this.busy_dialog.close();
				}
				var msg = this.project_manager.rpc.connect_error;
				if (msg == "") {
					msg = "could not start or reach the filesystem daemon (ollmfilesd)";
				}
				GLib.warning("ollmchat: %s", msg);
				this.tool_error_banner.title = "Filesystem daemon: " + msg;
				this.tool_error_banner.revealed = true;
				return;
			}
```

#### Replace with — one `connect`. An empty url passes `ClientBoot`. A stored remote url passes null.

```vala
			if (!yield this.project_manager.rpc.connect(hello,
				config.filesd_client.url == ""
					? new OLLMrpc.ClientBoot() : null)) {
				if (this.busy_dialog != null) {
					this.busy_dialog.close();
				}
				var msg = this.project_manager.rpc.connect_error;
				if (msg == "") {
					msg = "could not start or reach the filesystem daemon (ollmfilesd)";
				}
				GLib.warning("ollmchat: %s", msg);
				this.tool_error_banner.title = "Filesystem daemon: " + msg;
				this.tool_error_banner.revealed = true;
				return;
			}
```

### 6. `ollmapp/SettingsDialog/FileConnectionRow.vala` — `check` and `reconnect`

**Why:** 💩 Both still call `OLLMrpc.Transport.HttpClient` against `ollmfilesd`. The class in `libocrpc` stays.

**Where:** `check` builds an `HttpClient` and `yield http.call`. `reconnect` builds one when `remote` is true.

**Depends on:** Phase 1.

#### Remove — `check`, the `Cert`, the `HttpClient`, and its `call`.

```vala
			var tls = new OLLMrpc.Transport.Cert() {
				dir = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(), "ollmchat"),
				cert_pem = "client.pem",
				key_pem = "client-key.pem",
				cn = "ollmchat-device",
			};
			tls.ensure();
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

#### Replace with — hello goes through `Client.connect`. This call does not construct `Transport.HttpClient`. The certificate for this server is filled in later on the handshake. The old `catch` body is inlined on `connect_error`.

```vala
			var rpc = new OLLMrpc.Client("", "", this.client.url);
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

#### Remove — `reconnect`, remote `Cert` and `HttpClient`.

```vala
				var tls = new OLLMrpc.Transport.Cert() {
					dir = data_dir,
					cert_pem = "client.pem",
					key_pem = "client-key.pem",
					cn = "ollmchat-device",
				};
				tls.ensure();
				var http = new OLLMrpc.Transport.HttpClient(this.client.url) {
					bin_body = true,
					tls_certificate = tls.certificate,
					tls_database = tls.trust
				};
				rpc = new OLLMrpc.Client("", "", this.client.url) { http = http };
```

#### Replace with — this call does not construct `Transport.HttpClient`. The certificate for this server is filled in later on the handshake.

```vala
				rpc = new OLLMrpc.Client("", "", this.client.url);
```

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

#### Remove — the group description and the URL row subtitle.

```vala
			this.group = new Adw.PreferencesGroup() {
				description = "Connect to a desktop environment over HTTPS. "
					+ "The desktop must Accept the registration request."
			};
```

```vala
			url_row.subtitle = "Host:port or HTTPS URL of the desktop";
```

#### Replace with

```vala
			this.group = new Adw.PreferencesGroup() {
				description = "Connect to a desktop environment. "
					+ "The desktop must Accept the registration request."
			};
```

```vala
			url_row.subtitle = "Host:port of the desktop";
```

Pairing stays **Allow New Device** and the phone dialog. This method does not grow a second pair flow.

---

## Suggested order

1. ✔️ Phase 1 — `Client` TLS connect and `SslListen.broadcast`
2. ✔️ Phase 2 — Android and desktop use that client
3. `ollmfilesd` stops its HTTP server — [`RPC-1.11.4`](RPC-1.11.4-ollmfilesd-stop-http.md)
4. The phone reconnects — [`RPC-1.11.5`](RPC-1.11.5-phone-reconnect.md)

---

## LLM notes

- **🚫** Do not delete `OLLMrpc.Transport.HttpClient` or `OLLMrpc.Transport.HttpServer` from `libocrpc`. The file daemon stops using them. The RPC library keeps them.
- **💩** Leave the same-machine Unix socket. The request was to replace `ollmfilesd`'s HTTP server with TCP, and to keep localhost cleartext on Windows.
- **🚫** Do not edit `poll_drain_readable`, `on_read`, `call_poll`, `poll_close`, or `read_channel`. That polling belongs to GNOME shell.
- **💩** No second client class. The wrap is inside `OLLMrpc.Client.connect`.
