# RPC-1.11.4 — `ollmfilesd` stops serving HTTP

> **Do not update `docs/plans/RPC-1.0-summary.md` for this sub-plan** until it is done and archived.

**Status:** proposed

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala follows `docs/coding-standards.md`.

**Parent:** [`RPC-1.11.3`](RPC-1.11.3-tcp-client-handover.md) — phases 1 and 2. The file-daemon client already uses `OLLMrpc.Client` on `tcp://`.

**Depends on:** [`RPC-1.11.3`](RPC-1.11.3-tcp-client-handover.md)

---

## Purpose

- **🔷** `⏳` Remove `ollmfilesd/Https.vala` and the `filesd.https` settings that start it. That is the file daemon's HTTP server, not `libocrpc`.
- **🚫** Do not delete `libocrpc/Transport/HttpClient.vala`, `libocrpc/Transport/HttpServer.vala`, `Client.http`, or the `libocrpc` HTTP tests (`http-client-test.vala`, `http-server-test.vala`, `http-https-test.vala`, `http-routes-test.vala`, `http-bin-session-test.vala`).
- **🔷** `⏳` The Desktop server row drops the HTTPS expander. Unix, systemd, and the local network SSL row stay.
- **🔷** `⏳` `filesd.https`, `https_enabled`, and `proxy` go. `systemd` stays.

---

## Current behaviour

- **ℹ️** `ollmfilesd/Application.vala` constructs `OLLMfilesd.Https` and stores `https_listen` when `listen()` returns true. `cleanup` stops it.
- **ℹ️** `ollmfilesd/meson.build` lists `Https.vala`.
- **ℹ️** `FileServerRow` builds the HTTPS expander (host, port, proxy) and writes `filesd.https`, `https_enabled`, and `proxy`.
- **ℹ️** `tests/rpc/filesd-http-client-test.vala` is a manual executable. It talks to a live `ollmfilesd` over HTTPS. It is not a `meson test()`.
- **ℹ️** `docs/filesd-behind-nginx-proxy.md` tells an operator to set `filesd.https` and `proxy`.
- **ℹ️** `FileServerRow.reboot` treats `project_manager.rpc.http != null` as a remote file connection. After RPC-1.11.3 that client does not set `http`.

---

## Phase 1 — stop the listener

### 1. `ollmfilesd/meson.build` — drop `Https.vala`

**Why:** The file is the HTTP server.

**Where:** the daemon source list.

**Depends on:** none.

#### Remove

```meson
  'Https.vala',
```

Delete `ollmfilesd/Https.vala`.

### 2. `ollmfilesd/Application.vala` — do not start or stop HTTPS

**Why:** Nothing constructs `Https` after the file is gone.

**Where:** the `https_listen` property, the start block after the Unix or `--tcp` listener, and `cleanup`.

**Depends on:** §1.

#### Remove — the property.

```vala
		public OLLMfilesd.Https? https_listen { get; private set; default = null; }
```

#### Remove — the start block.

```vala
			var https = new OLLMfilesd.Https(this);
			if (https.listen()) {
				this.https_listen = https;
			}
```

#### Remove — the `cleanup` stop.

```vala
			if (this.https_listen != null) {
				this.https_listen.stop();
				this.https_listen = null;
			}
```

### 3. `ollmfilesd/SslListen.vala` and `SslConnection.vala` — drop `{@link Https}`

**Why:** Those doc comments name the class this phase deletes.

**Where:** the class docs, and `SslConnection.allow_request`.

**Depends on:** §1.

#### Remove — `SslListen` class doc, the HTTPS sentence.

```vala
	 * Otherwise {@link listen} returns false and the daemon stays
	 * up on Unix and HTTPS. Same product CA and {@link ClientCert}
	 * rows as {@link Https}.
```

#### Replace with

```vala
	 * Otherwise {@link listen} returns false and the daemon stays
	 * up on the Unix socket. Same product CA and {@link ClientCert}
	 * rows.
```

#### Remove — `SslConnection` class doc.

```vala
	 * {@link allow_request} matches {@link Https.allow_rpc}.
	 * {@link SslListen} constructs one after the TLS handshake.
```

#### Replace with

```vala
	 * {@link SslListen} constructs one after the TLS handshake.
```

#### Remove — `allow_request` doc, the first sentence.

```vala
		 * Same gate as {@link Https.allow_rpc} for bin RPC.
		 *
```

---

## Phase 2 — settings and the Desktop server row

### 4. `libollmchat/Settings/Filesd.vala` — drop HTTPS fields

**Why:** Those fields only start the HTTP server.

**Where:** the class doc and the three properties. `unix`, `socket`, `ssl_enabled`, and `systemd` stay. `install()` stays.

**Depends on:** §2.

#### Remove — class doc sentences and example keys.

```vala
	 * SSL server from ''socket''. ''https_enabled'' binds HTTPS from
	 * ''https''. Do not read the old ''enabled'' key.
```

```vala
	 *   "https": "127.0.0.1:8443",
	 *   "https_enabled": true,
	 *   "proxy": true,
```

#### Replace with

```vala
	 * SSL server from ''socket''. Do not read the old ''enabled'' key.
```

#### Remove — the three properties.

```vala
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

		/**
		 * Expect PROXY Protocol v1 on the HTTPS TCP listener.
		 */
		public bool proxy { get; set; default = false; }
```

### 5. `ollmapp/SettingsDialog/FileServerRow.vala` — drop the HTTPS expander

**Why:** The row writes the fields §4 removes. Unix, systemd, and local network SSL stay.

**Where:** properties, the constructor, `load_config`, `apply_config`, and `reboot`.

**Depends on:** §4.

#### Remove — constructor doc, the HTTPS parameters.

```vala
		 * @param filesd Config listen settings (https, socket, proxy, systemd)
```

#### Replace with

```vala
		 * @param filesd Config listen settings (socket, systemd)
```

#### Remove — class doc, the HTTPS lines.

```vala
	 * No control on the right. Rows are Unix socket, systemd,
	 * HTTPS server, then Local network SSL server.
	 * {@link https_switch} writes
	 * {@link OLLMchat.Settings.Filesd.https_enabled}.
	 * {@link ssl_switch} writes
```

#### Replace with

```vala
	 * No control on the right. Rows are Unix socket, systemd,
	 * then Local network SSL server.
	 * {@link ssl_switch} writes
```

#### Remove — HTTPS and proxy properties. `systemd_switch` stays.

```vala
		/**
		 * HTTPS server on/off. Writes
		 * {@link OLLMchat.Settings.Filesd.https_enabled}.
		 * Off keeps the saved host and port.
		 */
		public Gtk.Switch https_switch { get; private set; }

		/**
		 * HTTPS server expander. Host, Port, and Proxy are its rows.
		 */
		public Adw.ExpanderRow https_expander { get; private set; }

		/**
		 * HTTPS listen IP from this machine (left of ''host:port'' in
		 * {@link OLLMchat.Settings.Filesd.https}).
		 */
		public Gtk.DropDown host_dropdown { get; private set; }
		/**
		 * HTTPS listen IP row. Hidden when this machine has no
		 * IPv4 addresses.
		 */
		public Adw.ActionRow host_row { get; private set; }

		/**
		 * HTTPS listen port (right of ''host:port'' in
		 * {@link OLLMchat.Settings.Filesd.https}). Suffix
		 * {@link Gtk.Entry} with
		 * {@link Adw.ActionRow.set_activatable_widget} like Tools
		 * Engine ID. ''width_chars = 5'' fits 65535. Valid range
		 * 1024–65535; empty is off. Too low or too high sets this
		 * row's subtitle to ''Invalid'' and is not written.
		 */
		public Gtk.Entry port_entry { get; private set; }
		/**
		 * HTTPS port row. Hidden when this machine has no IPv4
		 * addresses.
		 */
		public Adw.ActionRow port_row { get; private set; }

		/**
		 * PROXY Protocol switch bound to
		 * {@link OLLMchat.Settings.Filesd.proxy}.
		 */
		public Gtk.Switch proxy_switch { get; private set; }
```

```vala
		/**
		 * Proxy action row inside the HTTPS server expander.
		 */
		private Adw.ActionRow proxy_row;
```

#### Remove — constructor, from `host_dropdown` through `expander.add_row(this.https_expander)`.

```vala
			this.host_dropdown = new Gtk.DropDown(new Gtk.StringList({}), null) {
				selected = Gtk.INVALID_LIST_POSITION,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.host_row = new Adw.ActionRow() {
				title = "Host",
				visible = false
			};
			this.host_row.add_suffix(this.host_dropdown);
			this.host_row.set_activatable_widget(this.host_dropdown);

			this.port_entry = new Gtk.Entry() {
				width_chars = 5,
				valign = Gtk.Align.CENTER,
				max_length = 5,
				placeholder_text = "8443"
			};
			this.port_entry.insert_text.connect((new_text, new_text_length, ref position) => {
				if (GLib.Regex.match_simple("^[0-9]*$", new_text)) {
					return;
				}
				GLib.Signal.stop_emission_by_name(this.port_entry, "insert-text");
			});
			this.port_row = new Adw.ActionRow() {
				title = "Port",
				visible = false
			};
			this.port_row.add_suffix(this.port_entry);
			this.port_row.set_activatable_widget(this.port_entry);
			var port_focus = new Gtk.EventControllerFocus();
			port_focus.leave.connect(() => {
				if (this.loading) {
					return;
				}
				this.apply_config();
			});
			this.port_entry.add_controller(port_focus);

			this.proxy_switch = new Gtk.Switch() {
				active = false,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.proxy_row = new Adw.ActionRow() {
				title = "Proxy"
			};
			this.proxy_row.add_suffix(this.proxy_switch);

			this.https_switch = new Gtk.Switch() {
				active = false,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.https_expander = new Adw.ExpanderRow() {
				title = "HTTPS server"
			};
			this.https_expander.add_suffix(this.https_switch);
			this.https_expander.add_row(this.host_row);
			this.https_expander.add_row(this.port_row);
			this.https_expander.add_row(this.proxy_row);
			this.expander.add_row(this.https_expander);
```

#### Remove — constructor signal handlers for the HTTPS widgets.

```vala
			this.https_switch.notify["active"].connect(() => {
				if (this.loading) {
					return;
				}
				this.apply_config();
			});
```

```vala
			this.host_dropdown.notify["selected"].connect(() => {
				if (this.loading) {
					return;
				}
				this.apply_config();
			});
```

```vala
			this.proxy_switch.notify["active"].connect(() => {
				if (this.loading) {
					return;
				}
				this.apply_config();
			});
```

#### Remove — `load_config`, the HTTPS address parse, proxy switch, HTTPS port widgets, HTTPS switch, and the "and HTTPS" subtitle.

```vala
			var host = "";
			var port = "";
			var colon = this.filesd.https.last_index_of(":");
			if (colon > 0) {
				host = this.filesd.https.substring(0, colon);
				port = this.filesd.https.substring(colon + 1);
			}
```

```vala
			this.proxy_switch.active = this.filesd.proxy;
```

```vala
			var port_n = 0;
			int.try_parse(port, out port_n);
			this.port_entry.text = port;
			this.port_row.subtitle = "";
			this.port_entry.remove_css_class("error");
			if (port != "" && (port_n < 1024 || port_n > 65535)) {
				this.port_row.subtitle = "Invalid";
				this.port_entry.add_css_class("error");
			}
			if (ips.length > 0) {
				var selected = Gtk.INVALID_LIST_POSITION;
				for (var i = 0; i < ips.length; i++) {
					if (ips[i] != host) {
						continue;
					}
					selected = i;
					break;
				}
				if (host != "" && selected == Gtk.INVALID_LIST_POSITION) {
					ips += host;
					selected = ips.length - 1;
				}
				this.host_dropdown.model = new Gtk.StringList(ips);
				this.host_dropdown.selected = selected;
			}
```

```vala
			this.https_switch.active = this.filesd.https_enabled;
```

```vala
			var https_ok = this.filesd.https_enabled && port_n >= 1024 && port_n <= 65535;
```

```vala
			if (up && https_ok) {
				how = how + " and HTTPS";
			}
```

```vala
			this.host_row.visible = ips.length > 0;
			this.port_row.visible = ips.length > 0;
```

`load_config` still builds `ssl_ips` from `OLLMrpc.Transport.TcpListen.ifaces()`.

#### Remove — `apply_config`, HTTPS and proxy writes, and those fields in the change check.

```vala
			var prev_https = this.filesd.https;
```

```vala
			var prev_proxy = this.filesd.proxy;
```

```vala
			var prev_enabled = this.filesd.https_enabled;
```

```vala
			this.filesd.https_enabled = this.https_switch.active;
			if (this.host_row.visible) {
				var host = "";
				var item = this.host_dropdown.selected_item as Gtk.StringObject;
				if (item != null) {
					host = item.string;
				}
				var n = 0;
				var port = this.port_entry.text.strip();
				int.try_parse(port, out n);
				this.port_row.subtitle = "";
				this.port_entry.remove_css_class("error");
				if (port != "" && (n < 1024 || n > 65535)) {
					this.port_row.subtitle = "Invalid";
					this.port_entry.add_css_class("error");
				}
				if (host != "" && n >= 1024 && n <= 65535) {
					this.filesd.https = host + ":" + n.to_string();
				}
			}
```

```vala
			this.filesd.proxy = this.proxy_switch.active;
```

```vala
			if (this.filesd.https_enabled != prev_enabled
				|| this.filesd.ssl_enabled != prev_ssl
				|| this.filesd.https != prev_https
				|| this.filesd.socket != prev_socket
				|| this.filesd.proxy != prev_proxy
				|| this.filesd.systemd != prev_systemd) {
```

#### Replace with — the change check.

```vala
			if (this.filesd.ssl_enabled != prev_ssl
				|| this.filesd.socket != prev_socket
				|| this.filesd.systemd != prev_systemd) {
```

#### Remove — the debug line that prints `https`.

```vala
				GLib.debug("file server apply systemd=%s was=%s https=%s socket=%s",
					this.filesd.systemd ? "on" : "off",
					this.was_systemd ? "on" : "off",
					this.filesd.https, this.filesd.socket);
```

#### Replace with

```vala
				GLib.debug("file server apply systemd=%s was=%s socket=%s",
					this.filesd.systemd ? "on" : "off",
					this.was_systemd ? "on" : "off",
					this.filesd.socket);
```

#### Remove — `reboot`, the HTTPS subtitle.

```vala
			var https_ok = false;
			var colon = this.filesd.https.last_index_of(":");
			if (this.filesd.https_enabled && colon > 0) {
				var n = 0;
				if (int.try_parse(this.filesd.https.substring(colon + 1), out n)
					&& n >= 1024 && n <= 65535) {
					https_ok = true;
				}
			}
```

```vala
			if (https_ok) {
				how = how + " and HTTPS";
			}
```

#### Remove — `reboot` treats `rpc.http` as the remote file connection.

```vala
			if (this.win.project_manager.rpc.http != null) {
```

#### Replace with — a stored remote url means the window is not on the local daemon.

```vala
			if (this.win.app.config.filesd_client.url != "") {
```

#### Remove — `reboot` doc, the HTTPS phrase.

```vala
		 * (socket only vs socket and HTTPS). If this window is still
```

#### Replace with

```vala
		 * (socket only vs socket and local network SSL). If this window is still
```

#### Remove — `apply_config` doc, the HTTPS phrase.

```vala
		 * Off keeps the saved HTTPS and socket addresses. A saved
```

#### Replace with

```vala
		 * Off keeps the saved socket address. A saved
```

#### Remove — `load_config` doc, the HTTPS sentences.

```vala
		 * HTTPS uses {@link OLLMrpc.Transport.TcpListen.ifaces}.
		 * SSL adds ''All'' first. That list never includes
		 * ''127.0.0.1''. No addresses: hide
		 * {@link host_row} and {@link port_row}. Call when the
```

#### Replace with

```vala
		 * SSL uses {@link OLLMrpc.Transport.TcpListen.ifaces} and
		 * adds ''All'' first. That list never includes
		 * ''127.0.0.1''. Call when the
```

---

## Phase 3 — the manual HTTPS client and the operator doc

### 6. `tests/meson.build` — drop `test-rpc-filesd-http-client`

**Why:** 💩 That executable calls `ollmfilesd` over HTTPS. With that server gone it has nothing to call. It is not one of the `libocrpc` HTTP tests.

**Where:** the executable block. There is no `test()` registration.

**Depends on:** §1.

#### Remove

```meson
# Manual: talks to a live systemd ollmfilesd. Not a meson test().
test_rpc_filesd_http_client = executable('test-rpc-filesd-http-client',
  'rpc/filesd-http-client-test.vala',
  dependencies: rpc_test_deps + [
    rpc_test_app_dep,
    dependency('libsoup-3.0'),
  ],
  link_with: rpc_test_link_with,
  build_rpath: rpc_test_build_rpath,
  export_dynamic: true,
  vala_args: rpc_test_vala_args + [
    '--pkg=libsoup-3.0',
  ],
)
```

Delete `tests/rpc/filesd-http-client-test.vala`.

### 7. `docs/filesd-behind-nginx-proxy.md` — stop telling operators to set `filesd.https`

**Why:** That listener is gone. The phone uses the TLS socket.

**Where:** the whole file.

**Depends on:** §4.

#### Replace with

````markdown
# ollmfilesd

`ollmfilesd` does not serve HTTP. The phone connects to the TLS socket
on `filesd.socket`.

`systemd` still installs the user unit. With `"systemd": true`,
`Filesd.install()` writes `~/.config/systemd/user/ollmfilesd.service`
only when the contents differ, reloads when it wrote, and runs
`enable --now` only if the unit is not already active.

Enable lingering if the daemon should survive logout:

```bash
loginctl enable-linger "$USER"
```
````

---

## Suggested order

1. Phase 1 — delete `Https.vala` and stop starting it
2. Phase 2 — drop `filesd.https`, `https_enabled`, `proxy`, and the HTTPS expander
3. Phase 3 — drop the manual HTTPS client and the nginx operator page
