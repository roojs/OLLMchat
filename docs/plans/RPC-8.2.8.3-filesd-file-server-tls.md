# 8.2.8.3 — Desktop File Server expander + TLS CA key auto-install

**Status:** **PROPOSED** — code proposals ready for review

> **Do not update `docs/plans/RPC-1.0-summary.md` for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](RPC-8.2.8-filesd-connections-ui.md)

**Depends on:**

- Phase 1 of parent (**✔️** agent-done) — `Config2.filesd` + `OLLMfilesd.Https.listen` CA PEM extraction
- [`RPC-8.2.8.1-DONE-filesd-desktop-connections-ui.md`](done/RPC-8.2.8.1-DONE-filesd-desktop-connections-ui.md) — Connections tab / `ConnectionRow` expander pattern

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Purpose

- **🔷** Connections tab: **File Server** expander — **Linux desktop** (empty `https` = server off). Not Android, not Windows.
  - Same expandable-block pattern as an LLM `Connection` row.
  - Host is a dropdown of this machine’s listen IPs (not free text). Port, proxy, systemd.
  - Saving updates `Config2.filesd` and persists.
  - If those listen fields changed, stop the local `ollmfilesd` from this process and start it again so HTTPS / proxy pick up. No reboot RPC.
- **🔷** Enabling HTTPS must **not** require the operator to hand-copy TLS material.
  - Today CA PEM is extracted from GResource; CA **key** still errors with “copy `libocrpc/data/…`”.
  - Extract / install the CA key the same way on first listen; update [`docs/filesd-behind-nginx-proxy.md`](../filesd-behind-nginx-proxy.md) so it no longer tells operators to copy certs by hand.
- **⏳** Land the expander, GResource key, `Https.listen` extract, nginx-doc rewrite, and `FileServerRow.reboot` (fences below).

---

## Current behaviour

- **ℹ️** `Config2.filesd` — `https`, `proxy`, `systemd` (and reserved `unix` / `socket`); class `libollmchat/Settings/Filesd.vala`.
- **ℹ️** `ollmfilesd` starts `OLLMfilesd.Https` when `filesd.https` is non-empty (`ollmfilesd/Https.vala` `listen()`).
- **ℹ️** `Https.listen` extracts CA PEM from GResource (`/ollmrpc/ollmrpc-ca.pem`) into `{data_dir}/tls/ollmrpc-ca.pem`; CA **key** hard-errors with `GLib.error("missing CA key %s (copy libocrpc/data/ollmrpc-ca-key.pem)")`.
- **ℹ️** GResource ships the PEM only (`libocrpc/data/ollmrpc.gresource.xml`); the CA key file `libocrpc/data/ollmrpc-ca-key.pem` is repo-only, not bundled.
- **ℹ️** Desktop Connections tab has LLM `ConnectionRow`s, outbound `FileConnectionRow`, and approved-client rows — no File Server expander yet.
- **ℹ️** Windows already runs local `ollmfilesd` over TCP `127.0.0.1:4141` (`windows/ClientBoot.vala`, `opt_tcp` forced). No Unix socket, no systemd, no `ClientBoot.kill`. This expander is the Linux HTTPS listen UI, not that loopback daemon.
- **ℹ️** `Filesd.install()` runs on daemon start (`ollmfilesd/Application.vala`). `systemd` true → write user unit + `enable --now`. `systemd` false → `disable --now` (**✔️** §3b).
- **ℹ️** `docs/filesd-behind-nginx-proxy.md` still tells operators to copy the CA private key by hand.

---

## Design decisions

- **🔷** Linux desktop Connections only. Android does not host `ollmfilesd`. Windows hosts local TCP `ollmfilesd` for the app, not this HTTPS listen UI. Expander is `#if !ANDROID && !G_OS_WIN32`; `FileServerRow.vala` is Linux `ollmchat_sources` only.
- **🔷** Host is a `Gtk.DropDown` of this machine’s IPv4 addresses (`Linux.Network.getifaddrs`, UP, skip `0.0.0.0`, de-dupe). Not a free-text entry. Fill the list in `load_config`, not the constructor. No UP IPv4 addresses → hide Host and Port rows only (do not fill them; do not wipe `filesd.https` on close). systemd and proxy still load.
- **🔷** Port stays a `Gtk.Entry`. `filesd.https` is selected IP `+ ":" +` port when **Enabled** is on. **Enabled** off (or no IP / empty port) → `https = ""` (server off). Split on load with `last_index_of(":")` (same as `Https.listen`). If the saved IP is not on the machine right now, still list it so the row does not silently change.
- **🔷** Proxy is a switch on `filesd.proxy`. systemd is a switch on `filesd.systemd` (this file is Linux-only, so the row is always built).
- **🔷** `FileServerRow` constructor only builds empty widgets (empty IP list, blank port, switches off). `load_config` reads `filesd` and enumerates IPs when the settings dialog is shown (`MainDialog.show_dialog` → `ConnectionsPage.load_config`). **Enabled** is a suffix switch on the expander (`https != ""`).
- **🔷** Persist on dialog close: `ConnectionsPage.apply_config()` calls `file_server_row.apply_config()` (one call; `#if` is that line). `MainDialog.on_closed` already saves.
- **🔷** `FileServerRow.apply_config` writes widgets into `this.filesd`. If host/port rows are hidden, leave `https` alone. If listen fields changed, `config.save()` then `reboot.begin()` so the new daemon reads disk.
- **🔷** Bounce lives on `FileServerRow.reboot()` (not `MainDialog`). `new ClientBoot` → `yield boot.kill()` → `yield boot.ensure_daemon()`. Pid/socket stop lives on `ClientBoot`, not the row.
- **🔷** `ClientBoot.kill()` — SIGTERM the pid, wait `grace`, unlink socket and pid file. Then `ensure_daemon` will spawn (it no-ops if the socket is still up).
- **🔷** `FileServerRow(filesd, win)` — window at construct so `reboot` can reconnect `ProjectManager` when it is still on Unix. Remote takeover: bounce local daemon only.
- **💩** File Server is the **first** row in `boxed_list` (this machine, then LLM connections, then outbound file connection, then approved clients).
- **🔷** systemd on: existing `Filesd.install()` (`enable --now`) after bounce, when the new daemon starts. systemd off: same `install()` runs `systemctl --user disable --now ollmfilesd.service` (no new method, not from the UI).
- **ℹ️** [`RPC-8.2.3.5`](done/RPC-8.2.3.5-DONE-https-server.md) kept the CA **key** out of the libocrpc GResource so Android would not ship it. This plan still lists the key in `libocrpc/data/ollmrpc.gresource.xml` so `Https.listen` can mirror the PEM lookup path (`/ollmrpc/ollmrpc-ca-key.pem`). ollmfilesd already links libocrpc. Confirm or veto (alternative: ollmfilesd-only GResource).

---

## TLS CA key auto-install

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `libocrpc/data/ollmrpc.gresource.xml` — ship the CA key next to the PEM

**Why:** `Https.listen` already extracts `/ollmrpc/ollmrpc-ca.pem` from this GResource. The key file exists in `libocrpc/data/`; listing it is the install source.
**Where:** the `<gresource prefix="/ollmrpc">` file list.
**Depends on:** none.

#### Remove

```xml
    <file>ollmrpc-ca.pem</file>
```

#### Replace with

```xml
    <file>ollmrpc-ca.pem</file>
    <file>ollmrpc-ca-key.pem</file>
```

---

### 2. `ollmfilesd/Https.vala` — `listen()`: extract CA key like CA PEM

**Why:** first HTTPS listen installs `{data_dir}/tls/ollmrpc-ca-key.pem` from GResource instead of aborting with a copy instruction.
**Where:** `listen()`, the `if (!GLib.FileUtils.test(ca_key, …))` block immediately after the CA PEM extract.
**Depends on:** §1.

#### Remove

```vala
			if (!GLib.FileUtils.test(ca_key, GLib.FileTest.EXISTS)) {
				GLib.error("missing CA key %s (copy libocrpc/data/ollmrpc-ca-key.pem)",
					ca_key);
			}
```

#### Replace with

```vala
			if (!GLib.FileUtils.test(ca_key, GLib.FileTest.EXISTS)) {
				try {
					GLib.FileUtils.set_contents(ca_key,
						(string) GLib.resources_lookup_data("/ollmrpc/ollmrpc-ca-key.pem",
							GLib.ResourceLookupFlags.NONE).get_data());
				} catch (GLib.Error e) {
					GLib.error("extract CA key: %s", e.message);
				}
			}
```

---

### 3. `docs/filesd-behind-nginx-proxy.md` — drop the operator copy step

**Why:** 🔷 rewrite of “Place the product CA private key once…”.
**Where:** the paragraph under `config.2.json` that tells operators to copy `ollmrpc-ca-key.pem`.
**Depends on:** §2.

#### Remove

```markdown
Place the product CA **private** key once at:

`~/.local/share/ollmchat/tls/ollmrpc-ca-key.pem`

(copy from `libocrpc/data/ollmrpc-ca-key.pem`). The public CA PEM is extracted
from GResource into the same `tls/` directory on first HTTPS start. Leaf
`server.pem` / `server-key.pem` are minted there via `Transport.Cert`.
```

#### Replace with

```markdown
On first HTTPS listen, `ollmfilesd` extracts the product CA PEM and private key
from GResource into `~/.local/share/ollmchat/tls/` (`ollmrpc-ca.pem` and
`ollmrpc-ca-key.pem`). Operators do not copy TLS files by hand. Leaf
`server.pem` / `server-key.pem` are minted there via `Transport.Cert`.
```

---

### 3a. `libocrpc/ClientBoot.vala` — public `kill()`

**Why:** Stop/unlink belongs on `ClientBoot`, not `FileServerRow`. `ensure_daemon` no-ops when the socket is already up, so a bounce is `kill` then `ensure_daemon`.
**Where:** after `ensure_daemon()`, before `connectable()`.
**Depends on:** none.

Sanctioned method: `kill`. Reuse private `read_pid` / `pid_running` / `terminate_daemon` / `unlink_socket` / `pause`. No extra helpers.

#### Add — after `ensure_daemon()`

```vala
		/**
		 * Stop a running ollmfilesd (SIGTERM), then drop socket and pid files.
		 *
		 * After this, {@link ensure_daemon} will spawn. No-op if nothing
		 * is running besides leftover files.
		 */
		public async void kill()
		{
			var daemon_pid = this.read_pid();
			if (this.pid_running(daemon_pid)) {
				this.terminate_daemon(daemon_pid);
				yield this.pause(this.grace);
			}
			this.unlink_socket();
			if (GLib.FileUtils.test(this.pid, GLib.FileTest.EXISTS)) {
				GLib.FileUtils.unlink(this.pid);
			}
		}
```

---

### 3b. `libollmchat/Settings/Filesd.vala` — `install()`: disable when the flag is off ✔️

**Why:** Install already `enable --now`s. The false branch is a no-op, so turning the File Server systemd switch off only writes JSON.
**Where:** `install()`, the `if (!this.systemd)` early return.
**Depends on:** none.

#### Remove

```vala
			if (!this.systemd) {
				return;
			}
```

#### Replace with

```vala
			if (!this.systemd) {
				try {
					GLib.Process.spawn_command_line_async(
						"systemctl --user disable --now ollmfilesd.service"
					);
				} catch (GLib.Error e) {
					GLib.warning("systemd disable failed: %s", e.message);
				}
				return;
			}
```

Also extend the `install()` docblock: when {@link systemd} is false, `disable --now`.

---

## File Server expander

### 4. `ollmapp/SettingsDialog/FileServerRow.vala` — new expander row

**Why:** File Server is an editable expander like `ConnectionRow`, bound to `Config2.filesd` (not an LLM `Settings.Connection`).
**Where:** new file under `ollmapp/SettingsDialog/` (desktop meson + valadoc lists in §6).
**Depends on:** §3a `ClientBoot.kill`.

Sanctioned new type: `FileServerRow`. Sanctioned methods: `load_config` (IPs + `filesd` into widgets), `apply_config` (widgets into `filesd`, save + `reboot` if listen fields changed), `reboot` (`new ClientBoot` → `kill` → `ensure_daemon`). Pass `OllmchatWindow` at construct (`this.win`), same as `FileConnectionRow`. `host_row` / `port_row` so `load_config` can hide them.

#### Add — new file `ollmapp/SettingsDialog/FileServerRow.vala`

Desktop File Server expander: Host dropdown (machine IPv4) / Port / Proxy / systemd bound to `filesd`.

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

namespace OLLMapp.SettingsDialog
{
	/**
	 * Widget group for the desktop File Server expander.
	 *
	 * Binds {@link OLLMchat.Settings.Filesd} listen fields (https
	 * host/port, proxy, systemd). Empty https is server off. The
 * Connections page calls {@link apply_config} on close, which
 * writes {@link filesd} and {@link reboot}s if listen fields
 * changed. {@link load_config} fills the IP dropdown and listen
 * fields when the settings dialog is shown.
 *
 * == Example ==
 *
 * {{{
 * var row = new FileServerRow(config.filesd, win);
 * boxed_list.append(row.expander);
 * row.load_config();
 * }}}
	 */
	public class FileServerRow : Object
	{
		/**
		 * The expander row containing File Server fields.
		 */
		public Adw.ExpanderRow expander { get; private set; }

		/**
		 * HTTPS listen IP from this machine (left of ''host:port'' in
		 * {@link OLLMchat.Settings.Filesd.https}).
		 */
		public Gtk.DropDown host_dropdown { get; private set; }
		/**
		 * Host (interface) action row; hidden when no IPv4 addresses.
		 */
		public Adw.ActionRow host_row { get; private set; }

		/**
		 * HTTPS listen port (right of ''host:port'' in
		 * {@link OLLMchat.Settings.Filesd.https}).
		 */
		public Gtk.Entry port_entry { get; private set; }
		/**
		 * Port action row; hidden when no IPv4 addresses.
		 */
		public Adw.ActionRow port_row { get; private set; }

		/**
		 * PROXY Protocol switch bound to
		 * {@link OLLMchat.Settings.Filesd.proxy}.
		 */
		public Gtk.Switch proxy_switch { get; private set; }

		/**
		 * systemd user-unit switch bound to
		 * {@link OLLMchat.Settings.Filesd.systemd}.
		 */
		public Gtk.Switch systemd_switch { get; private set; }

		/**
		 * Config ''filesd'' object this expander edits.
		 */
		public OLLMchat.Settings.Filesd filesd { get; private set; }
		/**
		 * Host window: {@link OLLMfiles.ProjectManager} after a local bounce.
		 */
		public OllmchatWindow win { get; private set; }

		/**
		 * File Server expander for one {@link OLLMchat.Settings.Filesd}.
		 *
		 * @param filesd Config listen settings (https, proxy, systemd)
		 * @param win Host window for ProjectManager reconnect
		 */
		public FileServerRow(OLLMchat.Settings.Filesd filesd, OllmchatWindow win)
		{
			this.filesd = filesd;
			this.win = win;
			this.expander = new Adw.ExpanderRow() {
				title = "File Server",
				subtitle = "Off",
				can_focus = false,
				focus_on_click = false
			};

			this.host_dropdown = new Gtk.DropDown(new Gtk.StringList({}), null) {
				selected = Gtk.INVALID_LIST_POSITION,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.host_row = new Adw.ActionRow() {
				title = "Host"
			};
			this.host_row.add_suffix(this.host_dropdown);
			this.expander.add_row(this.host_row);

			this.port_entry = new Gtk.Entry() {
				text = "",
				placeholder_text = "8443",
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.port_row = new Adw.ActionRow() {
				title = "Port"
			};
			this.port_row.add_suffix(this.port_entry);
			this.expander.add_row(this.port_row);

			this.proxy_switch = new Gtk.Switch() {
				active = false,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			var proxy_row = new Adw.ActionRow() {
				title = "Proxy"
			};
			proxy_row.add_suffix(this.proxy_switch);
			this.expander.add_row(proxy_row);

			this.systemd_switch = new Gtk.Switch() {
				active = false,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			var systemd_row = new Adw.ActionRow() {
				title = "systemd"
			};
			systemd_row.add_suffix(this.systemd_switch);
			this.expander.add_row(systemd_row);
		}

		/**
		 * Fill Host / Port / Proxy / systemd from {@link filesd}.
		 *
		 * Enumerates this machine's IPv4 listen addresses into
		 * {@link host_dropdown}. No addresses: hide {@link host_row}
		 * and {@link port_row}; still bind proxy and systemd. Call
		 * when the settings dialog is shown, not from the constructor.
		 */
		public void load_config()
		{
			var host = "";
			var port = "";
			var colon = this.filesd.https.last_index_of(":");
			if (colon > 0) {
				host = this.filesd.https.substring(0, colon);
				port = this.filesd.https.substring(colon + 1);
			}
			string[] ips = {};
			var addrs = (Linux.Network.IfAddrs) null;
			if (Linux.Network.getifaddrs(out addrs) == 0) {
				for (var iface = addrs; iface != null; iface = iface.ifa_next) {
					if (iface.ifa_addr == null) {
						continue;
					}
					if (iface.ifa_addr.sa_family != Posix.AF_INET) {
						continue;
					}
					if ((iface.ifa_flags & Linux.Network.IfFlag.UP) == 0) {
						continue;
					}
					var sin = (Posix.SockAddrIn*) iface.ifa_addr;
					var buf = new uint8[Posix.INET_ADDRSTRLEN];
					var ip = Posix.inet_ntop(Posix.AF_INET, &sin.sin_addr, buf);
					if (ip == null || ip == "" || ip == "0.0.0.0") {
						continue;
					}
					var seen = false;
					foreach (var existing in ips) {
						if (existing != ip) {
							continue;
						}
						seen = true;
						break;
					}
					if (seen) {
						continue;
					}
					ips += ip;
				}
			}
			this.proxy_switch.active = this.filesd.proxy;
			this.systemd_switch.active = this.filesd.systemd;
			this.expander.subtitle =
				this.filesd.https == "" ? "Off" : this.filesd.https;
			if (ips.length == 0) {
				this.host_row.visible = false;
				this.port_row.visible = false;
				return;
			}
			this.host_row.visible = true;
			this.port_row.visible = true;
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
			this.port_entry.text = port;
		}

		/**
		 * Write Host / Port / Proxy / systemd back into {@link filesd}.
		 *
		 * Hidden host/port rows leave ''https'' unchanged. If listen
		 * fields changed, save config and {@link reboot}.
		 */
		public void apply_config()
		{
			var prev_https = this.filesd.https;
			var prev_proxy = this.filesd.proxy;
			var prev_systemd = this.filesd.systemd;
			if (this.host_row.visible) {
				var host = "";
				var item = this.host_dropdown.selected_item as Gtk.StringObject;
				if (item != null) {
					host = item.string;
				}
				var port = this.port_entry.text.strip();
				this.filesd.https = "";
				if (host != "" && port != "") {
					this.filesd.https = host + ":" + port;
				}
			}
			this.filesd.proxy = this.proxy_switch.active;
			this.filesd.systemd = this.systemd_switch.active;
			this.expander.subtitle =
				this.filesd.https == "" ? "Off" : this.filesd.https;
			if (this.filesd.https != prev_https || this.filesd.proxy != prev_proxy
				|| this.filesd.systemd != prev_systemd) {
				this.win.app.config.save();
				this.reboot.begin();
			}
		}

		/**
		 * Stop the local Unix ollmfilesd and start it again.
		 *
		 * {@link OLLMrpc.ClientBoot.kill} then
		 * {@link OLLMrpc.ClientBoot.ensure_daemon}. Spawn failure
		 * raises ''Alert.show'' on the window and returns. If this
		 * window is still on Unix, reconnect
		 * {@link OLLMfiles.ProjectManager} like
		 * {@link FileConnectionRow.reconnect} with ''remote = false''.
		 * If the window is on a remote file connection, only bounce the
		 * local daemon.
		 */
		public async void reboot()
		{
			var data_dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "ollmchat");
			var boot = new OLLMrpc.ClientBoot(data_dir, "ollmfilesd.pid", "ollmfilesd.sock");
			yield boot.kill();
			try {
				yield boot.ensure_daemon();
			} catch (GLib.Error e) {
				GLib.critical("file server restart: %s", e.message);
				this.win.notification(new OLLMrpc.Notification() {
					method = "Alert.show",
					message = "File daemon is not up: " + e.message
				});
				return;
			}
			if (this.win.project_manager.rpc.http != null) {
				return;
			}
			this.win.project_manager.replace_rpc(
				new OLLMrpc.Client(data_dir, "ollmfilesd.pid", "ollmfilesd.sock")
			);
			var hello = new OLLMrpc.Request() {
				method = "RPC-Daemon.hello",
				args = OLLMrpc.args("is", 1, "ollmchat")
			};
			yield this.win.project_manager.rpc.connect(hello, new OLLMrpc.ClientBoot());
		}
	}
}
```

---

### 5. `ollmapp/SettingsDialog/ConnectionsPage.vala` — show File Server; persist on apply

**Why:** always-on desktop expander; empty widgets at construct; `load_config` when the dialog is shown; write `Config2.filesd` from the widgets when the dialog closes; `reboot.begin()` if listen fields changed (after `save()` so the new daemon reads disk).
**Where:** field next to `file_connection_row`; constructor before `render_connections()`; `load_config()`; `apply_config()`; `MainDialog.show_dialog`.
**Depends on:** §4.

##### Part 1 — field

#### Add — after `private FileConnectionRow? file_connection_row;`

Desktop-only File Server expander handle.

```vala
#if !ANDROID && !G_OS_WIN32
		private FileServerRow file_server_row;
#endif
```

##### Part 2 — construct first in `boxed_list`

#### Remove

```vala
			this.render_connections();
			this.render_file_connection();
			this.render_approved.begin();
```

#### Replace with

```vala
#if !ANDROID && !G_OS_WIN32
			this.file_server_row = new FileServerRow(
				this.dialog.app.config.filesd, this.dialog.parent);
			this.boxed_list.append(this.file_server_row.expander);
#endif
			this.render_connections();
			this.render_file_connection();
			this.render_approved.begin();
```

##### Part 3 — `apply_config()` writes `filesd`

#### Remove

```vala
		public void apply_config()
		{
			foreach (var entry in this.rows.entries) {
				entry.value.apply_config(this.dialog.app.config.connections.get(entry.key));
			}
		}
```

#### Replace with

```vala
		public void apply_config()
		{
			foreach (var entry in this.rows.entries) {
				entry.value.apply_config(this.dialog.app.config.connections.get(entry.key));
			}
#if !ANDROID && !G_OS_WIN32
			this.file_server_row.apply_config();
#endif
		}
```

##### Part 4 — `ConnectionsPage.load_config()` fills File Server widgets

#### Add — after `apply_config()`

Same moment as `ToolsPage.load_configs`: when the dialog is shown, not at page construct.

```vala
		public void load_config()
		{
#if !ANDROID && !G_OS_WIN32
			this.file_server_row.load_config();
#endif
		}
```

##### Part 5 — `ollmapp/SettingsDialog/MainDialog.vala` `show_dialog` loads File Server

#### Add — after `this.tools_page.load_configs();`

```vala
			this.connections_page.load_config();
```

---

### 6. Meson + valadoc — desktop sources only

**Why:** new Vala file; Android `android_poc_settings_sources` must not list it (`#if !ANDROID && !G_OS_WIN32` in the page is not enough if the class file is compiled in).
**Where:** `ollmchat_sources` next to `FileConnectionRow.vala`; non-Windows `ollmchat_vala_args` `--pkg=linux`; `docs/meson.build` valadoc inputs next to the same file.
**Depends on:** §4.

#### Add — `ollmapp/meson.build` Linux `ollmchat_sources` only (`host_machine.system() == 'linux'`), next to `'SettingsDialog/FileConnectionRow.vala',`

Not `android_poc_settings_sources`, not the Windows `ollmchat` source list.

```meson
    'SettingsDialog/FileServerRow.vala',
```

#### Add — `ollmapp/meson.build` `ollmchat_vala_args` non-Windows branch (next to `'--pkg=webkitgtk-6.0'`)

`Linux.Network.getifaddrs` in `FileServerRow` (desktop Linux only).

```meson
    '--pkg=linux',
```

#### Add — `docs/meson.build` valadoc inputs, immediately after `'../ollmapp/SettingsDialog/FileConnectionRow.vala',`

```meson
    '../ollmapp/SettingsDialog/FileServerRow.vala',
```

---

## Suggested order

1. **⏳** §1–§2 — GResource + `Https.listen` extract (HTTPS enable works without UI)
2. **⏳** §3 — nginx doc matches automatic install
3. **⏳** §3a — `ClientBoot.kill`
4. **✔️** §3b — `Filesd.install` `disable --now` when systemd is off
5. **⏳** §4–§6 — File Server expander; `FileServerRow.reboot` when listen fields change

---

## LLM notes

- **ℹ️** Parent Phase 1 owns `Config2.filesd` + CA PEM extraction — this sub-plan adds the key extract and the expander.
- **ℹ️** Sanctioned: `ClientBoot.kill`; `FileServerRow` (`expander`, `enabled_switch`, `host_dropdown`, `host_row`, `port_entry`, `port_row`, `proxy_switch`, `systemd_switch`, `filesd`, `win`, `load_config`, `apply_config`, `reboot`). `ConnectionsPage.apply_config` / `load_config` are one call each behind `#if !ANDROID && !G_OS_WIN32`.
- **ℹ️** `ensure_daemon` failure: `this.win.notification` `Alert.show` “File daemon is not up” (same channel as `FileConnectionRow` local connect failure). Not silent `critical` + return.
- **🚫** Pid / SIGTERM / unlink in `FileServerRow` or `MainDialog` — that is `ClientBoot.kill`.
- **🚫** New `RPC-Daemon.reboot` (or any reboot RPC).
- **🚫** `RPC-Daemon.shutdown` for this bounce — stop from this process via pid + SIGTERM.
- **🚫** Live HTTPS rebind inside a running daemon (no listen swap without restart).
- **🚫** Putting file-server listen settings into `Settings.Connection` LLM map.
- **🚫** Operator hand-copy of CA key as the supported enable path.
- **🚫** `unix` / `socket` fields on the expander (reserved).
- **🚫** Filling IPs / `filesd` values in the `FileServerRow` constructor — that is `load_config` on dialog show.
- **🚫** `Gtk.Entry` / typing hostnames for Host — dropdown of this machine’s IPv4 only.
- **🔷** Enabled switch on the File Server expander (suffix). Off writes `https = ""`; on writes selected IP `+ ":" +` port.
- **🚫** File Server expander on Windows or Android — Windows local `ollmfilesd` is TCP loopback for the app; this UI is Linux HTTPS listen.
- **🚫** `FileServerRow.vala` in `android_poc_settings_sources` or the Windows `ollmchat` source list.
- **🚫** Calling `Filesd.install()` from the UI — the bounced daemon already calls it.
- **💩** Save on every keystroke / switch instead of dialog close.
- **🚫** Restart-hint ActionRow (“restart ollmfilesd to apply”) — dialog close bounces the daemon.
- **💩** `0.0.0.0` / all-interfaces as a Host choice.
- **💩** IPv6 Host values until `Https.listen` `host:port` split is IPv6-safe.
- **💩** ollmfilesd-only GResource for the CA key (if you veto shipping it via libocrpc to Android).
