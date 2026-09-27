# 8.2.8.13 — Desktop server rows and LAN client

**Status:** **⏳** — Desktop server rows **✔️**. LAN client not started. Windows build is [`8.2.8.14`](RPC-8.2.8.14-LATER-filesd-windows-desktop-server.md).

> **Do not update** `docs/plans/RPC-1.0-summary.md` **for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](RPC-8.2.8-filesd-connections-ui.md)

**Depends on:** [`RPC-8.2.8.7-URGENT-filesd-tcp-socket-lan.md`](RPC-8.2.8.7-URGENT-filesd-tcp-socket-lan.md) — `ssl_enabled`, `https_enabled`, and `SslListen` are in the tree

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Purpose

- 🔷 Desktop server is one expander on the Connections tab. Nothing sits on the right of that row. The subtitle says what is running.
- 🔷 Linux order: Unix socket, systemd, HTTPS server, Local network SSL server.
- 🔷 The LAN client connects to `filesd.socket` `host:port`, not an `https://` URL.
- ℹ️ The TLS listener is already [`8.2.8.7`](RPC-8.2.8.7-URGENT-filesd-tcp-socket-lan.md). This plan is the rows and the client.
- ℹ️ Windows row layout is drawn below. Building it is [`8.2.8.14`](RPC-8.2.8.14-LATER-filesd-windows-desktop-server.md), later.
- ⏳ Row fences are under Desktop server rows. The LAN client still has no fences.

---

## Desktop server rows

🔷 Desktop server is one expander. Nothing sits on the right of that row. The subtitle says what is running, for example Running on socket, or Running via systemd.

```
Linux — expanded

┌ Desktop server                                          ┐
│  subtitle: Running on socket                            │
│    Unix socket                               Running    │
│    systemd                                   [  ○   ]   │
│  ▸ HTTPS server                              [  ○   ]   │
│  ▸ Local network SSL server                  [  ○   ]   │
└─────────────────────────────────────────────────────────┘
```

🔷 Unix socket is the first row on Linux. It is not an expander and it has no toggle. The row says Running.

🔷 systemd is the next row, above HTTPS server. The toggle is on that row.

🔷 HTTPS server has an on/off toggle. It expands to Host, Port, and Proxy. Port placeholder is 8443. The listener is `filesd.https`.

```
│  ▾ HTTPS server                              [  ○   ]   │
│      Host                        [ ▾ ip, no 127.0.0.1 ] │
│      Port                                     [ 8443 ]  │
│      Proxy                                    [  ○   ]   │
```

🔷 Local network SSL server has an on/off toggle. It expands to Host and Port. Port placeholder is 8422. Subtitle: Recommended for local networks only. HTTPS and this row use the same host list. That list leaves out `127.0.0.1`.

```
│  ▾ Local network SSL server                  [  ○   ]   │
│      Recommended for local networks only                │
│      Host                        [ ▾ ip, no 127.0.0.1 ] │
│      Port                                     [ 8422 ]  │
```

🔷 The Local network SSL server toggle shows after a host and port are saved. Before that, the row expands to Host and Port with no toggle. The toggle writes `ssl_enabled`. The HTTPS server toggle writes `https_enabled`.

🔷 Windows has no Unix socket row and no systemd row. Localhost TCP is the first row: listed Running, no toggle.

```
Windows — expanded

┌ Desktop server                                          ┐
│  subtitle: Running on localhost TCP                     │
│    Localhost TCP                             Running    │
│  ▸ HTTPS server                              [  ○   ]   │
│  ▸ Local network SSL server                  [  ○   ]   │
└─────────────────────────────────────────────────────────┘
```

- 🔷 `✔️` Replace the File Server Enabled suffix with this layout in `FileServerRow`. Linux host list only. Fences are below.
- 🔷 `✔️` HTTPS server and Local network SSL server each have an on/off toggle. Off keeps the saved host and port and does not listen.
- 🔷 `✔️` Desktop server Local network SSL server edits `filesd.socket` host and port. Apply/reboot when those fields change (same bounce as HTTPS).
- 💩 `⏳` Those toggles are `Gtk.Switch`, same as today's File Server Enabled switch.
- 💩 `⏳` “Set up” means `filesd.socket` has a host and a port in 1024–65535.
- 💩 `⏳` Localhost TCP subtitle can show the live listen address. The row stays status-only.
- ℹ️ Windows loopback port is still [`docs/bugs/2026-09-20-filesd-windows-socket-port.md`](../bugs/2026-09-20-filesd-windows-socket-port.md). This row does not add a port editor for it.
- ℹ️ Windows does not build `FileServerRow` today (`ConnectionsPage.vala`, `#if !ANDROID && !G_OS_WIN32`). The Windows host list and per-user service are [`8.2.8.14`](RPC-8.2.8.14-LATER-filesd-windows-desktop-server.md).

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify surrounding context before applying. Linux only. Do not build the Windows host list here.

### 1. `ollmapp/SettingsDialog/FileServerRow.vala` — Desktop server chrome

**Why:** The outer row is Desktop server. Nothing sits on its right. Unix socket, systemd, HTTPS server, and Local network SSL server are the rows under it.

**Where:** Class doc and the new row properties. The constructor is ### 2.

**Depends on:** none.

#### Remove

```vala
	 * Widget group for the desktop File Server expander.
	 *
	 * Binds {@link OLLMchat.Settings.Filesd} listen fields (https
	 * host/port, proxy, systemd). Off {@link enabled_switch} hides
	 * Host / Port / Proxy and sets
	 * {@link OLLMchat.Settings.Filesd.https_enabled} false without
	 * clearing their values. {@link systemd_row} stays visible.
```

#### Replace with

Outer row has no switch. HTTPS and local network SSL each have their own.

```vala
	 * Widget group for the Desktop server expander.
	 *
	 * No control on the right. Rows are Unix socket, systemd,
	 * HTTPS server, then Local network SSL server.
	 * {@link https_switch} writes
	 * {@link OLLMchat.Settings.Filesd.https_enabled}.
	 * {@link ssl_switch} writes
	 * {@link OLLMchat.Settings.Filesd.ssl_enabled} after a
	 * host and port are saved.
```

#### Remove

```vala
		/**
		 * File Server HTTPS on/off. Off hides Host / Port / Proxy
		 * and sets {@link OLLMchat.Settings.Filesd.https_enabled} false;
		 * those fields keep their last values. systemd stays shown.
		 */
		public Gtk.Switch enabled_switch { get; private set; }
```

#### Replace with

The HTTPS switch sits on the HTTPS server row, not on Desktop server.

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
```

#### Add

After `systemd_row`. Unix socket has a Running label, not a switch. The SSL switch stays hidden until `filesd.socket` is a saved non-loopback `host:port`.

```vala
		/**
		 * Unix socket row. Suffix says Running. No toggle.
		 */
		private Adw.ActionRow unix_row;

		/**
		 * ''Running'' on the Unix socket row.
		 */
		private Gtk.Label unix_label;

		/**
		 * Local network SSL server expander.
		 *
		 * Subtitle is Recommended for local networks only.
		 * Host and Port are its rows. The host list leaves out
		 * ''127.0.0.1''.
		 */
		public Adw.ExpanderRow ssl_expander { get; private set; }

		/**
		 * Local network SSL on/off. Hidden until {@link filesd.socket}
		 * has a host and a port in 1024–65535. Writes
		 * {@link OLLMchat.Settings.Filesd.ssl_enabled}.
		 */
		public Gtk.Switch ssl_switch { get; private set; }

		/**
		 * SSL listen IP. Same machine list as HTTPS, without
		 * ''127.0.0.1''.
		 */
		public Gtk.DropDown ssl_host_dropdown { get; private set; }

		/**
		 * SSL host row inside {@link ssl_expander}.
		 */
		public Adw.ActionRow ssl_host_row { get; private set; }

		/**
		 * SSL listen port. Placeholder is 8422.
		 */
		public Gtk.Entry ssl_port_entry { get; private set; }

		/**
		 * SSL port row. Invalid ports set the subtitle to ''Invalid''.
		 */
		public Adw.ActionRow ssl_port_row { get; private set; }
```

#### Remove

```vala
		 * @param filesd Config listen settings (enabled, https, proxy, systemd)
```

#### Replace with

```vala
		 * @param filesd Config listen settings (https, socket, proxy, systemd)
```

### 2. `FileServerRow` constructor

**Why:** One replace for the widget tree. Order is Unix socket, systemd, HTTPS server, Local network SSL server. Desktop server has no switch.

**Where:** The whole `FileServerRow` constructor.

**Depends on:** ### 1.

#### Remove

```vala
		public FileServerRow(
			OLLMchat.Settings.Filesd filesd,
			OllmchatWindow win,
			Adw.ToastOverlay toast_overlay)
		{
			this.filesd = filesd;
			this.win = win;
			this.toast_overlay = toast_overlay;
			this.expander = new Adw.ExpanderRow() {
				title = "File Server",
				subtitle = "Not running"
			};
			this.enabled_switch = new Gtk.Switch() {
				active = false,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.expander.add_suffix(this.enabled_switch);

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
			this.expander.add_row(this.host_row);

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
			this.expander.add_row(this.port_row);

			this.proxy_switch = new Gtk.Switch() {
				active = false,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.proxy_row = new Adw.ActionRow() {
				title = "Proxy",
				visible = false
			};
			this.proxy_row.add_suffix(this.proxy_switch);
			this.expander.add_row(this.proxy_row);

			this.systemd_switch = new Gtk.Switch() {
				active = false,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.systemd_row = new Adw.ActionRow() {
				title = "systemd"
			};
			this.systemd_row.add_suffix(this.systemd_switch);
			this.expander.add_row(this.systemd_row);

			this.enabled_switch.notify["active"].connect(() => {
				this.proxy_row.visible = this.enabled_switch.active;
				this.host_row.visible = false;
				this.port_row.visible = false;
				if (this.enabled_switch.active && this.host_dropdown.model.get_n_items() > 0) {
					this.host_row.visible = true;
					this.port_row.visible = true;
				}
				if (this.loading) {
					return;
				}
				this.apply_config();
			});
			this.host_dropdown.notify["selected"].connect(() => {
				if (this.loading) {
					return;
				}
				this.apply_config();
			});
			this.proxy_switch.notify["active"].connect(() => {
				if (this.loading) {
					return;
				}
				this.apply_config();
			});
			this.systemd_switch.notify["active"].connect(() => {
				if (this.loading) {
					return;
				}
				this.apply_config();
			});
		}
```

#### Replace with

```vala
		public FileServerRow(
			OLLMchat.Settings.Filesd filesd,
			OllmchatWindow win,
			Adw.ToastOverlay toast_overlay)
		{
			this.filesd = filesd;
			this.win = win;
			this.toast_overlay = toast_overlay;
			this.expander = new Adw.ExpanderRow() {
				title = "Desktop server",
				subtitle = "Not running"
			};
			this.unix_label = new Gtk.Label("Running") {
				valign = Gtk.Align.CENTER
			};
			this.unix_row = new Adw.ActionRow() {
				title = "Unix socket"
			};
			this.unix_row.add_suffix(this.unix_label);
			this.expander.add_row(this.unix_row);

			this.systemd_switch = new Gtk.Switch() {
				active = false,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.systemd_row = new Adw.ActionRow() {
				title = "systemd"
			};
			this.systemd_row.add_suffix(this.systemd_switch);
			this.expander.add_row(this.systemd_row);

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

			this.ssl_switch = new Gtk.Switch() {
				active = false,
				visible = false,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.ssl_expander = new Adw.ExpanderRow() {
				title = "Local network SSL server",
				subtitle = "Recommended for local networks only",
				expanded = true
			};
			this.ssl_expander.add_suffix(this.ssl_switch);
			this.ssl_host_dropdown = new Gtk.DropDown(new Gtk.StringList({}), null) {
				selected = Gtk.INVALID_LIST_POSITION,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.ssl_host_row = new Adw.ActionRow() {
				title = "Host"
			};
			this.ssl_host_row.add_suffix(this.ssl_host_dropdown);
			this.ssl_host_row.set_activatable_widget(this.ssl_host_dropdown);
			this.ssl_expander.add_row(this.ssl_host_row);
			this.ssl_port_entry = new Gtk.Entry() {
				width_chars = 5,
				valign = Gtk.Align.CENTER,
				max_length = 5,
				placeholder_text = "8422"
			};
			this.ssl_port_entry.insert_text.connect((new_text, new_text_length, ref position) => {
				if (GLib.Regex.match_simple("^[0-9]*$", new_text)) {
					return;
				}
				GLib.Signal.stop_emission_by_name(this.ssl_port_entry, "insert-text");
			});
			this.ssl_port_row = new Adw.ActionRow() {
				title = "Port"
			};
			this.ssl_port_row.add_suffix(this.ssl_port_entry);
			this.ssl_port_row.set_activatable_widget(this.ssl_port_entry);
			var ssl_port_focus = new Gtk.EventControllerFocus();
			ssl_port_focus.leave.connect(() => {
				if (this.loading) {
					return;
				}
				this.apply_config();
			});
			this.ssl_port_entry.add_controller(ssl_port_focus);
			this.ssl_expander.add_row(this.ssl_port_row);
			this.expander.add_row(this.ssl_expander);

			this.https_switch.notify["active"].connect(() => {
				if (this.loading) {
					return;
				}
				this.apply_config();
			});
			this.ssl_switch.notify["active"].connect(() => {
				if (this.loading) {
					return;
				}
				this.apply_config();
			});
			this.host_dropdown.notify["selected"].connect(() => {
				if (this.loading) {
					return;
				}
				this.apply_config();
			});
			this.ssl_host_dropdown.notify["selected"].connect(() => {
				if (this.loading) {
					return;
				}
				this.apply_config();
			});
			this.proxy_switch.notify["active"].connect(() => {
				if (this.loading) {
					return;
				}
				this.apply_config();
			});
			this.systemd_switch.notify["active"].connect(() => {
				if (this.loading) {
					return;
				}
				this.apply_config();
			});
		}
```

### 3. `load_config` — two host lists and the subtitle

**Why:** `ifaces` skips `127.0.0.1`, so neither host list has localhost. The SSL switch appears only after `filesd.socket` is saved in range. The Desktop server subtitle names what is up.

**Where:** `load_config`, in the address loop, after the HTTPS dropdown, and in the subtitle block at the bottom.

**Depends on:** ### 2.

#### Remove

```vala
			string[] ips = {};
```

#### Replace with

```vala
			string[] ips = {};
			string[] ssl_ips = {};
			var socket_host = "";
			var socket_port = "";
			var socket_colon = this.filesd.socket.last_index_of(":");
			if (socket_colon > 0) {
				socket_host = this.filesd.socket.substring(0, socket_colon);
				socket_port = this.filesd.socket.substring(socket_colon + 1);
			}
```

#### Remove

```vala
					ips += ip;
```

#### Replace with

`127.0.0.1` stays on the HTTPS list only.

```vala
					ips += ip;
					if (ip != "127.0.0.1") {
						ssl_ips += ip;
					}
```

#### Add

After the HTTPS `host_dropdown` block (`if (ips.length > 0) { ... }`), before `this.enabled_switch.active`.

```vala
			if (ssl_ips.length > 0) {
				var ssl_selected = Gtk.INVALID_LIST_POSITION;
				for (var i = 0; i < ssl_ips.length; i++) {
					if (ssl_ips[i] != socket_host) {
						continue;
					}
					ssl_selected = i;
					break;
				}
				if (socket_host != "" && ssl_selected == Gtk.INVALID_LIST_POSITION) {
					ssl_ips += socket_host;
					ssl_selected = ssl_ips.length - 1;
				}
				this.ssl_host_dropdown.model = new Gtk.StringList(ssl_ips);
				this.ssl_host_dropdown.selected = ssl_selected;
			}
			var socket_n = 0;
			int.try_parse(socket_port, out socket_n);
			this.ssl_port_entry.text = socket_port;
			this.ssl_port_row.subtitle = "";
			this.ssl_port_entry.remove_css_class("error");
			if (socket_port != "" && (socket_n < 1024 || socket_n > 65535)) {
				this.ssl_port_row.subtitle = "Invalid";
				this.ssl_port_entry.add_css_class("error");
			}
```

#### Remove

```vala
			this.enabled_switch.active = this.filesd.https_enabled;
```

#### Replace with

```vala
			this.https_switch.active = this.filesd.https_enabled;
			this.ssl_switch.active = this.filesd.ssl_enabled;
```

#### Remove

```vala
			var https_ok = this.filesd.https_enabled && n >= 1024 && n <= 65535;
			this.expander.subtitle = "Not running";
			if (up) {
				this.expander.subtitle = "Running on startup (socket only)";
			}
			if (up && via_systemd) {
				this.expander.subtitle = "Running via systemd (socket only)";
			}
			if (up && https_ok) {
				this.expander.subtitle = "Running on startup (socket and HTTPS)";
			}
			if (up && via_systemd && https_ok) {
				this.expander.subtitle = "Running via systemd (socket and HTTPS)";
			}
			this.proxy_row.visible = this.enabled_switch.active;
			this.host_row.visible = false;
			this.port_row.visible = false;
			if (this.enabled_switch.active && ips.length > 0) {
				this.host_row.visible = true;
				this.port_row.visible = true;
			}
```

#### Replace with

HTTPS and local network SSL are appended when those listeners are on. 💩 The combined wording is this sentence, not a new control.

```vala
			var https_ok = this.filesd.https_enabled && n >= 1024 && n <= 65535;
			var ssl_ok = this.filesd.ssl_enabled && socket_host != ""
				&& socket_n >= 1024 && socket_n <= 65535;
			var how = "Not running";
			if (up) {
				how = "Running on socket";
			}
			if (up && via_systemd) {
				how = "Running via systemd";
			}
			if (up && https_ok) {
				how = how + " and HTTPS";
			}
			if (up && ssl_ok) {
				how = how + " and local network SSL";
			}
			this.expander.subtitle = how;
			this.host_row.visible = ips.length > 0;
			this.port_row.visible = ips.length > 0;
			var ssl_ready = socket_host != ""
				&& socket_n >= 1024 && socket_n <= 65535;
			this.ssl_switch.visible = ssl_ready;
			if (!ssl_ready) {
				this.ssl_expander.expanded = true;
			}
```

### 4. `apply_config` — save `filesd.socket` and reboot

**Why:** Host and port edits write `filesd.socket` even while the SSL switch is hidden, so the switch can appear. A change of `socket` or `ssl_enabled` bounces `ollmfilesd` the same way HTTPS does. Off does not clear the saved address.

**Where:** The top of `apply_config`, the HTTPS write, and the change check.

**Depends on:** ### 3.

#### Remove

```vala
			var prev_https = this.filesd.https;
			var prev_proxy = this.filesd.proxy;
			var prev_systemd = this.filesd.systemd;
			var prev_enabled = this.filesd.https_enabled;
			this.was_systemd = prev_systemd;
			this.filesd.https_enabled = this.enabled_switch.active;
			if (this.filesd.https_enabled && this.host_row.visible) {
```

#### Replace with

`https` is written when Host is visible, including while the HTTPS switch is off.

```vala
			var prev_https = this.filesd.https;
			var prev_socket = this.filesd.socket;
			var prev_proxy = this.filesd.proxy;
			var prev_systemd = this.filesd.systemd;
			var prev_enabled = this.filesd.https_enabled;
			var prev_ssl = this.filesd.ssl_enabled;
			this.was_systemd = prev_systemd;
			this.filesd.https_enabled = this.https_switch.active;
			if (this.host_row.visible) {
```

#### Remove

```vala
			this.filesd.systemd = this.systemd_switch.active;
			if (this.filesd.https_enabled) {
				this.filesd.proxy = this.proxy_switch.active;
			}
			if (this.filesd.https_enabled != prev_enabled
				|| this.filesd.https != prev_https
				|| this.filesd.proxy != prev_proxy
				|| this.filesd.systemd != prev_systemd) {
				this.win.app.config.save();
				GLib.debug("file server apply systemd=%s was=%s https=%s",
					this.filesd.systemd ? "on" : "off",
					this.was_systemd ? "on" : "off", this.filesd.https);
```

#### Replace with

The SSL switch is not written while it is hidden, so a first save of host and port does not turn the listener on.

```vala
			this.filesd.systemd = this.systemd_switch.active;
			this.filesd.proxy = this.proxy_switch.active;
			var ssl_host = "";
			var ssl_item = this.ssl_host_dropdown.selected_item as Gtk.StringObject;
			if (ssl_item != null) {
				ssl_host = ssl_item.string;
			}
			var ssl_n = 0;
			var ssl_port = this.ssl_port_entry.text.strip();
			int.try_parse(ssl_port, out ssl_n);
			this.ssl_port_row.subtitle = "";
			this.ssl_port_entry.remove_css_class("error");
			if (ssl_port != "" && (ssl_n < 1024 || ssl_n > 65535)) {
				this.ssl_port_row.subtitle = "Invalid";
				this.ssl_port_entry.add_css_class("error");
			}
			if (ssl_host != "" && ssl_n >= 1024 && ssl_n <= 65535) {
				this.filesd.socket = ssl_host + ":" + ssl_n.to_string();
			}
			var saved_n = 0;
			var saved_colon = this.filesd.socket.last_index_of(":");
			var saved_host = "";
			if (saved_colon > 0) {
				saved_host = this.filesd.socket.substring(0, saved_colon);
				int.try_parse(this.filesd.socket.substring(saved_colon + 1), out saved_n);
			}
			var ssl_ready = saved_host != ""
				&& saved_n >= 1024 && saved_n <= 65535;
			this.ssl_switch.visible = ssl_ready;
			if (!ssl_ready) {
				this.ssl_expander.expanded = true;
			}
			if (this.ssl_switch.visible) {
				this.filesd.ssl_enabled = this.ssl_switch.active;
			}
			if (this.filesd.https_enabled != prev_enabled
				|| this.filesd.ssl_enabled != prev_ssl
				|| this.filesd.https != prev_https
				|| this.filesd.socket != prev_socket
				|| this.filesd.proxy != prev_proxy
				|| this.filesd.systemd != prev_systemd) {
				this.win.app.config.save();
				GLib.debug("file server apply systemd=%s was=%s https=%s socket=%s",
					this.filesd.systemd ? "on" : "off",
					this.was_systemd ? "on" : "off",
					this.filesd.https, this.filesd.socket);
```

### 5. `reboot` subtitle

**Why:** After the bounce, the subtitle has to match `load_config`.

**Where:** The success path that currently sets `Running on startup`.

**Depends on:** ### 3.

#### Remove

```vala
			this.expander.subtitle = "Running on startup (socket only)";
			if (via_systemd) {
				this.expander.subtitle = "Running via systemd (socket only)";
			}
			if (https_ok) {
				this.expander.subtitle = "Running on startup (socket and HTTPS)";
			}
			if (via_systemd && https_ok) {
				this.expander.subtitle = "Running via systemd (socket and HTTPS)";
			}
```

#### Replace with

```vala
			var ssl_ok = false;
			var socket_colon = this.filesd.socket.last_index_of(":");
			if (this.filesd.ssl_enabled && socket_colon > 0) {
				var socket_n = 0;
				if (int.try_parse(this.filesd.socket.substring(socket_colon + 1), out socket_n)
					&& socket_n >= 1024 && socket_n <= 65535) {
					ssl_ok = true;
				}
			}
			var how = "Running on socket";
			if (via_systemd) {
				how = "Running via systemd";
			}
			if (https_ok) {
				how = how + " and HTTPS";
			}
			if (ssl_ok) {
				how = how + " and local network SSL";
			}
			this.expander.subtitle = how;
```

### 6. `ollmapp/SettingsDialog/ConnectionsPage.vala`

**Why:** The dialog comment still says File Server.

**Where:** `load_config` docblock.

**Depends on:** none.

#### Remove

```vala
		 * Fill File Server widgets from {@link OLLMchat.Settings.Config2.filesd}.
```

#### Replace with

```vala
		 * Fill Desktop server widgets from {@link OLLMchat.Settings.Config2.filesd}.
```

## LAN client

- 🔷 `⏳` A LAN client connects with device cert + trust (same `Cert.ensure` as HTTPS file connection), to the socket `host:port`, not an `https://` URL.
- ℹ️ Outbound “Add file connection” today is HTTPS URL only ([`8.2.8.2`](done/RPC-8.2.8.2-DONE-filesd-android-file-connection.md)). A `tcp://` / TLS-socket client row is this plan.
- ⏳ Code proposals — not written.

---

## LLM notes

- ℹ️ The listener, cert gate, and flags stay on [`8.2.8.7`](RPC-8.2.8.7-URGENT-filesd-tcp-socket-lan.md).
- 🚫 A control on the right of the Desktop server row. Subtitle only.
- 🚫 A toggle on Unix socket, or on Windows Localhost TCP.
- 🚫 `127.0.0.1` in the HTTPS or Local network SSL server host list.
- 🚫 systemd on the Desktop server header. It is a row under Unix socket and above HTTPS server.
- 🚫 Titling the TLS row HTTP server. The title is HTTPS server.
- 🚫 A Proxy row on Local network SSL server.
- 🚫 Turning off the Unix socket because Local network SSL server is on.
- 🚫 Building the Windows host list or a Windows per-user service here. That is [`8.2.8.14`](RPC-8.2.8.14-LATER-filesd-windows-desktop-server.md).
