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

- **🔷** Connections tab: **File Server** expander — **always shown** on desktop (empty `https` = server off).
  - Same expandable-block pattern as an LLM `Connection` row.
  - Edit listen values: host/port (→ `filesd.https`), **proxy**, related `filesd` fields (`systemd`).
  - Saving updates `Config2.filesd` and persists; daemon pick-up = restart / existing install path.
- **🔷** Enabling HTTPS must **not** require the operator to hand-copy TLS material.
  - Today CA PEM is extracted from GResource; CA **key** still errors with “copy `libocrpc/data/…`”.
  - Extract / install the CA key the same way on first listen; update [`docs/filesd-behind-nginx-proxy.md`](../filesd-behind-nginx-proxy.md) so it no longer tells operators to copy certs by hand.
- **⏳** Land the expander, GResource key, `Https.listen` extract, and nginx-doc rewrite (fences below).

---

## Current behaviour

- **ℹ️** `Config2.filesd` — `https`, `proxy`, `systemd` (and reserved `unix` / `socket`); class `libollmchat/Settings/Filesd.vala`.
- **ℹ️** `ollmfilesd` starts `OLLMfilesd.Https` when `filesd.https` is non-empty (`ollmfilesd/Https.vala` `listen()`).
- **ℹ️** `Https.listen` extracts CA PEM from GResource (`/ollmrpc/ollmrpc-ca.pem`) into `{data_dir}/tls/ollmrpc-ca.pem`; CA **key** hard-errors with `GLib.error("missing CA key %s (copy libocrpc/data/ollmrpc-ca-key.pem)")`.
- **ℹ️** GResource ships the PEM only (`libocrpc/data/ollmrpc.gresource.xml`); the CA key file `libocrpc/data/ollmrpc-ca-key.pem` is repo-only, not bundled.
- **ℹ️** Desktop Connections tab has LLM `ConnectionRow`s, outbound `FileConnectionRow`, and approved-client rows — no File Server expander yet.
- **ℹ️** `MainDialog.on_closed` already calls `connections_page.apply_config()` then `config.save()`.
- **ℹ️** `docs/filesd-behind-nginx-proxy.md` still tells operators to copy the CA private key by hand.

---

## Design decisions

- **🔷** Always present on desktop Connections. Android does not host `ollmfilesd`, so the expander is `#if !ANDROID` and `FileServerRow.vala` is desktop `ollmchat_sources` only.
- **🔷** Host + Port entries compose `filesd.https` as `host + ":" + port`. Empty host **or** empty port → `https = ""` (server off). Split on load with `last_index_of(":")` (same as `Https.listen`).
- **🔷** Proxy and systemd are switches on `filesd.proxy` / `filesd.systemd`.
- **🔷** Persist on dialog close: `ConnectionsPage.apply_config()` writes the widgets into `config.filesd`; `MainDialog.on_closed` already saves. No live HTTPS rebind.
- **💩** File Server is the **first** row in `boxed_list` (this machine, then LLM connections, then outbound file connection, then approved clients).
- **ℹ️** `Filesd.install()` still runs on daemon start, not from this UI. Turning systemd on only persists the flag.
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

## File Server expander

### 4. `ollmapp/SettingsDialog/FileServerRow.vala` — new expander row

**Why:** File Server is an editable expander like `ConnectionRow`, bound to `Config2.filesd` (not an LLM `Settings.Connection`).
**Where:** new file under `ollmapp/SettingsDialog/` (desktop meson + valadoc lists in §6).
**Depends on:** none.

Sanctioned new type: `FileServerRow`. Constructor only — no `apply_config` helper; the page writes the widgets in existing `ConnectionsPage.apply_config()`.

#### Add — new file `ollmapp/SettingsDialog/FileServerRow.vala`

Desktop File Server expander: Host / Port / Proxy / systemd bound to `filesd`.

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
	 * Connections page writes the widgets back in
	 * {@link ConnectionsPage.apply_config}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var row = new FileServerRow(config.filesd);
	 * boxed_list.append(row.expander);
	 * }}}
	 */
	public class FileServerRow : Object
	{
		/**
		 * The expander row containing File Server fields.
		 */
		public Adw.ExpanderRow expander { get; private set; }

		/**
		 * HTTPS listen host (left of ''host:port'' in
		 * {@link OLLMchat.Settings.Filesd.https}).
		 */
		public Gtk.Entry host_entry { get; private set; }

		/**
		 * HTTPS listen port (right of ''host:port'' in
		 * {@link OLLMchat.Settings.Filesd.https}).
		 */
		public Gtk.Entry port_entry { get; private set; }

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
		 * File Server expander for one {@link OLLMchat.Settings.Filesd}.
		 *
		 * @param filesd Config listen settings (https, proxy, systemd)
		 */
		public FileServerRow(OLLMchat.Settings.Filesd filesd)
		{
			this.filesd = filesd;
			var host = "";
			var port = "";
			var colon = this.filesd.https.last_index_of(":");
			if (colon > 0) {
				host = this.filesd.https.substring(0, colon);
				port = this.filesd.https.substring(colon + 1);
			}
			this.expander = new Adw.ExpanderRow() {
				title = "File Server",
				subtitle = this.filesd.https == "" ? "Off" : this.filesd.https,
				can_focus = false,
				focus_on_click = false
			};

			this.host_entry = new Gtk.Entry() {
				text = host,
				placeholder_text = "127.0.0.1",
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			var host_row = new Adw.ActionRow() {
				title = "Host"
			};
			host_row.add_suffix(this.host_entry);
			this.expander.add_row(host_row);

			this.port_entry = new Gtk.Entry() {
				text = port,
				placeholder_text = "8443",
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			var port_row = new Adw.ActionRow() {
				title = "Port"
			};
			port_row.add_suffix(this.port_entry);
			this.expander.add_row(port_row);

			this.proxy_switch = new Gtk.Switch() {
				active = this.filesd.proxy,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			var proxy_row = new Adw.ActionRow() {
				title = "Proxy"
			};
			proxy_row.add_suffix(this.proxy_switch);
			this.expander.add_row(proxy_row);

			this.systemd_switch = new Gtk.Switch() {
				active = this.filesd.systemd,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			var systemd_row = new Adw.ActionRow() {
				title = "systemd"
			};
			systemd_row.add_suffix(this.systemd_switch);
			this.expander.add_row(systemd_row);
		}
	}
}
```

---

### 5. `ollmapp/SettingsDialog/ConnectionsPage.vala` — show File Server; persist on apply

**Why:** always-on desktop expander; write `Config2.filesd` from the widgets when the dialog closes.
**Where:** field next to `file_connection_row`; constructor before `render_connections()`; `apply_config()`.
**Depends on:** §4.

##### Part 1 — field

#### Add — after `private FileConnectionRow? file_connection_row;`

Desktop-only File Server expander handle.

```vala
#if !ANDROID
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
#if !ANDROID
			this.file_server_row = new FileServerRow(this.dialog.app.config.filesd);
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
#if !ANDROID
			var filesd = this.dialog.app.config.filesd;
			var host = this.file_server_row.host_entry.text.strip();
			var port = this.file_server_row.port_entry.text.strip();
			filesd.https = "";
			if (host != "" && port != "") {
				filesd.https = host + ":" + port;
			}
			filesd.proxy = this.file_server_row.proxy_switch.active;
			filesd.systemd = this.file_server_row.systemd_switch.active;
			this.file_server_row.expander.subtitle =
				filesd.https == "" ? "Off" : filesd.https;
#endif
		}
```

---

### 6. Meson + valadoc — desktop sources only

**Why:** new Vala file; Android `android_poc_settings_sources` must not list it (`#if !ANDROID` in the page is not enough if the class file is compiled in).
**Where:** `ollmchat_sources` next to `FileConnectionRow.vala`; `docs/meson.build` valadoc inputs next to the same file.
**Depends on:** §4.

#### Add — `ollmapp/meson.build` `ollmchat_sources`, immediately after `'SettingsDialog/FileConnectionRow.vala',`

Desktop compile list only (not `android_poc_settings_sources`).

```meson
    'SettingsDialog/FileServerRow.vala',
```

#### Add — `docs/meson.build` valadoc inputs, immediately after `'../ollmapp/SettingsDialog/FileConnectionRow.vala',`

```meson
    '../ollmapp/SettingsDialog/FileServerRow.vala',
```

---

## Suggested order

1. **⏳** §1–§2 — GResource + `Https.listen` extract (HTTPS enable works without UI)
2. **⏳** §3 — nginx doc matches automatic install
3. **⏳** §4–§6 — File Server expander on desktop Connections

---

## LLM notes

- **ℹ️** Parent Phase 1 owns `Config2.filesd` + CA PEM extraction — this sub-plan adds the key extract and the expander.
- **ℹ️** Sanctioned new type: `FileServerRow` (`expander`, `host_entry`, `port_entry`, `proxy_switch`, `systemd_switch`, `filesd`). No `apply_config` on the row.
- **🚫** Live HTTPS rebind without daemon restart when `filesd.https` changes from the UI.
- **🚫** Putting file-server listen settings into `Settings.Connection` LLM map.
- **🚫** Operator hand-copy of CA key as the supported enable path.
- **🚫** `unix` / `socket` fields on the expander (reserved).
- **🚫** Enabled switch (empty host or port is off).
- **🚫** `FileServerRow` in `android_poc_settings_sources`.
- **🚫** Calling `Filesd.install()` from the UI.
- **💩** Save on every keystroke / switch instead of dialog close.
- **💩** Restart-hint ActionRow (“restart ollmfilesd to apply”).
- **💩** ollmfilesd-only GResource for the CA key (if you veto shipping it via libocrpc to Android).
