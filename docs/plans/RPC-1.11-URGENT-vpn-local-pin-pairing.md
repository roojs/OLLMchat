# RPC-1.11 — URGENT — VPN/local timed PIN pairing

> **Do not update `docs/plans/RPC-1.0-summary.md` for this plan.**

**Status:** **URGENT** — Phases 1 and 2 agent-done. Phases 3–5 not started. Browse name is `_rpc._tcp.local`.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala follows `docs/coding-standards.md`.

**Prefix:** `RPC` (`libocrpc` consumers: `ollmfilesd`, `ollmapp`) · see [`RPC-1.0-summary.md`](RPC-1.0-summary.md)

**Parent:** [`RPC-8.2-full-rpc-system.md`](RPC-8.2-full-rpc-system.md) — Phase 7

**Replaces the open registration path in:** [`RPC-8.2.7-client-cert-registration.md`](RPC-8.2.7-client-cert-registration.md)

---

## Purpose

- **🔷** Urgent next step for RPC registration.
- **🔷** Remove every public WAN registration endpoint.
- **🔷** New devices pair only on VPN or LAN, inside a timed window, with a temporary 6-digit PIN.
- **🔷** Listen scope is **one** chosen interface **or all** interfaces. A picked list of specific interfaces is later.
- **🔷** While the window is open the server advertises the addresses it is actually listening on (that one interface, or every up non-loopback address when the choice is all) and returns the same set to the client.
- **🔷** The primary client is Android. It discovers the server, the user types the PIN, and the phone picks the fastest working route. The other addresses stay as runtime fallbacks.
- **🔷** Pairing and steady-state RPC use the TLS bin socket (`filesd.socket`, `SslListen`). That open connection is what carries notifications.
- **🔷** The registration authority is the server. Its CA private key is generated on the server and stored on the filesystem. The distribution does not ship that public or private key.
- **🔷** Registration does not need a valid client certificate, and it does not need the CA installed on the phone. That install is the gateway problem this avoids.
- **🔷** HTTPS is not a downgrade path and not the out-of-LAN fallback in this plan.
- **ℹ️** Phases 1 and 2 are in this file. Phases 3 and 4 are [`RPC-1.11.1`](RPC-1.11.1-pin-registration-and-android.md). Phase 5 stays here and is later.
- **ℹ️** Landed registration is always-on `RPC-ClientCert.request_registration` plus desktop Accept / Reject / Ban. This plan is the replacement for that open path.
- **ℹ️** Prior write-up [`RPC-8.2.7`](RPC-8.2.7-client-cert-registration.md) and parent Phase 7 described admin approval with no PIN and no CSR. This plan is the newer requirement.

---

## Current behaviour

- **ℹ️** Unknown client certs may call `RPC-ClientCert.request_registration` on HTTPS (`ollmfilesd/Https.vala`) and on the TLS bin socket (`ollmfilesd/SslConnection.vala`). See `ollmfilesd/ClientCert.vala`.
- **ℹ️** The LAN listener this plan uses is `ollmfilesd/SslListen.vala`: TLS bin on `filesd.socket`. HTTPS is a separate listener.
- **ℹ️** The phone presents a valid client certificate (`client.pem` from `Transport.Cert.ensure`) before it is registered. `SslConnection.allow_request` allows `request_registration` for that unregistered certificate and refuses every other method until the fingerprint is stored with status approved.
- **ℹ️** Desktop shows the newest pending row on `ollmapp/SettingsDialog/RegistrationBanner.vala` (Accept / Reject / Ban).
- **ℹ️** The client mints its own cert and posts `request_registration` from `ollmapp/SettingsDialog/FileConnectionAdd.vala`. The user types a server URL.
- **ℹ️** Approved rows live in SQLite `client_cert` (fingerprint, status, ip, requester).
- **ℹ️** [`docs/filesd-behind-nginx-proxy.md`](../filesd-behind-nginx-proxy.md) documents an internet-facing nginx stream in front of that listener.
- **ℹ️** No Avahi / mDNS usage anywhere in the tree.
- **ℹ️** The product CA is built into the application. `libocrpc/data/ollmrpc.gresource.xml` lists `ollmrpc-ca.pem` and `ollmrpc-ca-key.pem`. `ollmfilesd/Https.vala` copies those resources into `{data_dir}/tls/` when the files are missing. The phone trusts the same public cert via `product_ca_resource`.
- **ℹ️** Desktop server listen is one IPv4. `ollmapp/SettingsDialog/FileServerRow.vala` fills a Host dropdown from up interfaces (`getifaddrs`, skips `0.0.0.0` and `127.0.0.1`). HTTPS (`filesd.https`) and local network SSL (`filesd.socket`) each store that single `host:port`.

---

## Proposed behaviour

- **🔷** For the urgent work, pair mode starts when the GTK user turns on **Allow New Device**.
- **🔷** `⏳` Later, not urgent: a connected client can start that same window with **Register a friend** (Phase 5). The PIN shows on the phone that is already connected.
- **🔷** That opens a dialog showing the 6-digit PIN.
- **🔷** The dialog shows the minute running out: a sliding line counts the 60 seconds down so the timeout is visible.
- **🔷** Pair mode lasts **60 seconds** (one minute), then the dialog closes and pair mode turns off. Start it again if the minute runs out.
- **🔷** Turning pair mode on generates a 6-digit PIN and starts the mDNS broadcast.
- **🔷** Pair mode also turns off as soon as one device finishes pairing.
- **🔷** With pair mode off, the server rejects the connection outright. Registration does not start. A registered certificate still connects.
- **🔷** A wrong PIN keeps the dialog open on the same PIN. A toast says **number rejected**. The minute keeps running.
- **🔷** The Linux server publishes the pairing service with mDNS (Avahi). The Android client browses that same DNS-SD type. It does not use `Avahi.ServiceBrowser`.
- **🔷** On the phone, **Add connection** shows **Listening for connection** until mDNS finds the server. The six-digit prompt appears only after that.
- **🔷** The phone then connects on the TLS bin socket and sends a CSR plus the PIN.
- **🔷** The socket listener binds one selected interface, or all interfaces. The HTTPS host dropdown stays as it is.
- **🔷** On a valid PIN the server registers the client cert and returns:
  - the signed client certificate
  - the listen addresses for that choice (one IP, or every up non-loopback IP such as VPN `10.8.0.1` and LAN `192.168.1.5`) with the listen port
- **🔷** The phone stores every address from that response, local and VPN.
- **🔷** Each time the app starts it connects to a stored address that answers.
  - In the house or the office that is the local address.
  - Outside, the local network is absent, so it uses the stored VPN address.

### Workflow

1. GTK server: pair mode off.
2. User clicks **Allow New Device**. A dialog shows the 6-digit PIN (example shape `849204`). A line counts the 60 seconds down. mDNS broadcast starts.
3. Phone: **Add connection**, then **Listening for connection**.
4. mDNS finds the server. The phone then asks for the six digits.
5. Phone opens the TLS bin socket and submits CSR + PIN.
6. Wrong PIN: desktop dialog stays open, same PIN. A toast says **number rejected**. Phone can try again until the minute ends.
7. Right PIN: server signs the client cert and returns that cert plus the addresses for the listen choice (one interface, or all). The phone stores the whole list.
8. The phone connects to an address that answers. At home or in the office that is the local IP. Pair mode turns off and the dialog closes.
9. Next launch away from that network uses the stored VPN address, because the local network is not there. Steady-state RPC stays on that TLS bin socket so notifications keep flowing.

### Threat and operations

- **🔷** Registration stays off until the operator opens the window. Listen scope is one interface or all interfaces, not an always-on public endpoint.
- **🔷** A wrong number is a toast, **number rejected**. The same PIN and the rest of the minute stay available.
- **🔷** After the window, a connection that is not registered is rejected outright. The registration process does not run. A registered certificate keeps working.
- **🔷** The registration window is one minute. The urgent opener is the desktop. **Register a friend** is a later opener (Phase 5).
- **🔷** Discovery and route choice are automatic. The user supplies the PIN, not an IP.

### Certificates

- **🔷** Stop building the CA into the application. Remove `ollmrpc-ca.pem` and `ollmrpc-ca-key.pem` from `libocrpc/data/ollmrpc.gresource.xml`. The phone stops loading that public cert through `product_ca_resource`.
- **🔷** If `{data_dir}/tls/ollmrpc-ca.pem` is still that bundled certificate, delete it and `ollmrpc-ca-key.pem`, then generate a new CA unique to this server and store it in those same paths. A CA that is already unique to the server stays.
- **🔷** The server leaf is issued by that new CA. The old leaf, signed by the bundled CA, is replaced in the same step.
- **🔷** A valid certificate and a registered certificate stay different. Steady-state RPC needs a registered one.
- **🔷** The open handshake exists only while pair mode is on. Then the phone needs no valid client certificate: `TlsAuthenticationMode.REQUESTED`, `accept_certificate` returns true, and registration may run with an empty fingerprint.
- **🔷** The phone side is still closed. `HttpClient` accepts the server certificate only when the errors are `BAD_IDENTITY` or none, and that trust comes from the bundled product CA. Registration has to accept the server certificate without that CA on the phone. The PIN is the authorization for that connection.
- **🔷** The phone sends a CSR and the PIN on that open handshake. It does not present `client.pem`.
- **🔷** A right PIN: the server signs the CSR with the on-disk CA key and returns that client certificate, plus the CA public certificate. The phone stores both. Later connections present the signed certificate and check the server against that CA. The certificate is registered.
- **🔷** With pair mode off, the server rejects that connection before registration starts. A registered certificate is the connection that still gets through.

---

## Suggested order

1. ✔️ Phase 1 — `PairingDialog` on the GTK server
2. ✔️ Phase 2 — Listen on one interface or all, then mDNS advertise
3. Phase 3 — PIN check, CSR, signed cert, address list — [`RPC-1.11.1`](RPC-1.11.1-pin-registration-and-android.md)
4. Phase 4 — Android discovery, PIN prompt, route probe — [`RPC-1.11.1`](RPC-1.11.1-pin-registration-and-android.md)
5. Phase 5 — **Register a friend** (later, not urgent)

---

## Phase 1 — `PairingDialog` (server) (`✔️`)

### Goal

- **🔷** `✔️` New class `OLLMapp.SettingsDialog.PairingDialog` in `ollmapp/SettingsDialog/PairingDialog.vala`. The pairing dialog and most of the pairing logic live in that class.
- **🔷** `✔️` That class owns the session: generate the PIN, show it, run the 60-second countdown line, fire the timeout, and toast **number rejected**.
- **🔷** `✔️` Opening and closing pair mode starts and stops mDNS. `pairing` is the flag.
- **🔷** `✔️` **Allow New Device** on the connections action bar opens `PairingDialog`.
- **🔷** `✔️` Pair mode on shows the 6-digit PIN in that dialog. The PIN is the main focus: large, spaced digits from the `.pairing-pin` class in `resources/style.css`.
- **🔷** `✔️` That dialog draws a sliding line that counts the 60 seconds down so the remaining time is visible.
- **🔷** `✔️` Pair mode on starts a 60-second `GLib.Timeout`.
- **🔷** `✔️` `rejected()` toasts **number rejected** and leaves the dialog and PIN up. Nothing calls it until a wrong PIN arrives from the server.
- **🔷** `✔️` The dialog closes when the timeout fires, and `pairing` turns off. Closing when a device finishes pairing waits on the registration response (Phase 3).
- **🔷** `⏳` Pair mode off stops the mDNS broadcast and rejects a non-registered connection outright. Registration does not start.
- **💩** The pasted draft said `register_client`. That is not a request to add a method.
- **ℹ️** The live method is `RPC-ClientCert.request_registration`. Gate that method. A second method name needs a separate decision (see **LLM notes**).
- **🔷** `✔️` Generate the six digits with `GLib.Random`. A 60-second PIN on the local network does not need a cryptographic generator.

### Notes

- **ℹ️** Today’s approval UI is `RegistrationBanner` on the settings action bar (Accept / Reject / Ban). `PairingDialog` replaces that for this flow. Connections already toasts from `ConnectionsPage.toast_overlay`.
- **ℹ️** The listener still rejects a non-registered connection when pair mode is off. That check stays in `ollmfilesd`. `PairingDialog.pairing` is the flag Phase 2 and that listener follow. mDNS itself is Phase 2.
- **🔷** `✔️` **Allow New Device** is a third button on the connections action bar, beside **LLM Connection** and **Remote Desktop Connection**.
- **🔷** `✔️` **Allow New Device** is hidden when this app cannot set the file server up, and while that server is not active. That is the visibility catch. There is no OS `#if` on the button. Windows and Android have no server setup, so the same check hides it there.

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify surrounding context before applying.

### ✔️ 1. `ollmapp/SettingsDialog/PairingDialog.vala` — new pairing dialog

**Why:** The PIN, the countdown, and the **number rejected** toast live in one class.

**Where:** new file. Compiled with the app on Linux, Windows, and the Android settings sources. The button is not hidden by OS.

**Depends on:** none.

#### Add — new file. Session UI: PIN, 60-second line, toast.

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
	 * One-minute window that shows a PIN while a device pairs.
	 *
	 * {@link open} draws a new six-digit PIN and a line that counts
	 * down from sixty seconds. {@link rejected} toasts
	 * ''number rejected'' and leaves that PIN up. {@link pairing}
	 * is true only while the dialog is open.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var pair = new OLLMapp.SettingsDialog.PairingDialog(overlay);
	 * pair.open(window);
	 * pair.rejected();
	 * }}}
	 */
	public class PairingDialog : Adw.Dialog
	{
		/**
		 * Overlay that shows ''number rejected''.
		 */
		public Adw.ToastOverlay toast_overlay { get; construct; }

		/**
		 * Six digits the phone must type. Empty until {@link open}.
		 */
		public string pin { get; private set; default = ""; }

		/**
		 * True while this dialog is counting down.
		 */
		public bool pairing { get; private set; default = false; }

		private Gtk.Label pin_label;
		private Gtk.ProgressBar line;
		private uint tick_id = 0;
		private int remaining = 60;

		/**
		 * @param toast_overlay Connections-tab overlay for the toast
		 */
		public PairingDialog(Adw.ToastOverlay toast_overlay)
		{
			Object(toast_overlay: toast_overlay, title: "Allow New Device");
			var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12) {
				margin_top = 24,
				margin_bottom = 24,
				margin_start = 24,
				margin_end = 24
			};
			this.pin_label = new Gtk.Label("") {
				halign = Gtk.Align.CENTER,
				css_classes = { "pairing-pin" }
			};
			box.append(this.pin_label);
			this.line = new Gtk.ProgressBar() {
				fraction = 1,
				hexpand = true
			};
			box.append(this.line);
			this.set_child(box);
			this.set_content_width(560);
			this.closed.connect(() => {
				if (this.tick_id == 0) {
					return;
				}
				GLib.Source.remove(this.tick_id);
				this.tick_id = 0;
				this.pairing = false;
			});
		}

		/**
		 * Show a new PIN and start the sixty-second line.
		 *
		 * @param parent Widget the dialog is attached to
		 */
		public void open(Gtk.Widget parent)
		{
			if (this.tick_id != 0) {
				GLib.Source.remove(this.tick_id);
				this.tick_id = 0;
			}
			var n = GLib.Random.int_range(0, 1000000);
			this.pin = "%06d".printf(n);
			this.pin_label.label = this.pin;
			this.remaining = 60;
			this.line.fraction = 1;
			this.pairing = true;
			this.present(parent);
			this.tick_id = GLib.Timeout.add_seconds(1, () => {
				this.remaining -= 1;
				this.line.fraction = this.remaining / 60.0;
				if (this.remaining > 0) {
					return true;
				}
				this.tick_id = 0;
				this.pairing = false;
				this.close();
				return false;
			});
		}

		/**
		 * Toast ''number rejected''. The PIN and the dialog stay.
		 */
		public void rejected()
		{
			this.toast_overlay.add_toast(new Adw.Toast("number rejected"));
		}
	}
}
```

### ✔️ 2. `resources/style.css` — large PIN digits

**Why:** Adwaita `title-1` is a heading. The six digits are the dialog.

**Where:** end of `resources/style.css`. The file is already on the display via `ChatView` (`/ollmchat/style.css`).

**Depends on:** §1.

#### Add — class `pairing-pin` at the end of the file.

```css
/* Pairing dialog: the six-digit PIN is the whole point of the window. */
.pairing-pin {
	font-size: 64px;
	font-weight: 800;
	letter-spacing: 0.35em;
	font-family: monospace;
}
```

### ✔️ 3. `ollmapp/meson.build` — compile `PairingDialog` on every app build

**Why:** The dialog itself is portable. Hiding the button is the platform split, so Android and Windows still compile the class.

**Where:** `ollmchat_sources`, after `ConnectionsPage.vala`. The same line in `android_poc_settings_sources`. `FileServerRow.vala` stays in the Linux-only list.

**Depends on:** §1.

#### Add — `ollmchat_sources`, on the line after `SettingsDialog/ConnectionsPage.vala`.

```meson
  'SettingsDialog/PairingDialog.vala',
```

#### Add — `android_poc_settings_sources`, on the line after `SettingsDialog/ConnectionsPage.vala`.

```meson
    'SettingsDialog/PairingDialog.vala',
```

### ✔️ 4. `ollmapp/SettingsDialog/ConnectionsPage.vala` — **Allow New Device** on the bottom bar

**Why:** That bar already holds **LLM Connection** and **Remote Desktop Connection**, fixed under the page.

**Where:** field on the line before the `#if !ANDROID && !G_OS_WIN32` that still holds `FileServerRow`. Button appended to `action_widget` after `this.append(this.toast_overlay)`. No OS guard on the button. Hiding it when the server cannot be set up waits on Phase 2.

**Depends on:** §1.

#### Add — field, on the line before `#if !ANDROID && !G_OS_WIN32`.

```vala
		private PairingDialog pairing_dialog;
```

#### Add — after `this.append(this.toast_overlay)`. The button is built on every platform. Visibility is not an OS `#if`.

```vala
			this.pairing_dialog = new PairingDialog(this.toast_overlay);
			var allow_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
			allow_box.append(new Gtk.Image.from_icon_name("list-add-symbolic"));
			var allow_label = new Gtk.Label("Allow New Device") {
				ellipsize = Pango.EllipsizeMode.END,
				hexpand = true
			};
			allow_box.append(allow_label);
			var allow = new Gtk.Button() {
				child = allow_box,
				hexpand = true
			};
			allow.clicked.connect(() => {
				this.pairing_dialog.open(this.dialog);
			});
			this.action_widget.append(allow);
```

---

## Phase 2 — Listen on one interface or all (server) (`✔️`)

### Goal

- **🔷** `✔️` One-or-all applies to the TLS bin socket (`filesd.socket` / `SslListen`) only.
  - **One:** bind that address only, same as today’s `filesd.socket` host.
  - **All:** one bind to `0.0.0.0`. The listener does not walk interfaces. `SslListen` already binds the single host in `filesd.socket` and does not reject `0.0.0.0`.
- **🔷** `⏳` A list of specific interfaces (more than one, short of all) is later. This plan does not build that multi-select.
- **🔷** `✔️` Leave the HTTPS listener and its Host dropdown unchanged. HTTPS is not the pairing transport and not a fallback when the socket is unreachable.
- **🔷** `✔️` After this listen change, show **Allow New Device** only when this app can set the file server up and that server is active.
  - Do not hide the button with `#if ANDROID` or `#if G_OS_WIN32`. Those builds have no server setup, so this check covers them.
  - **ℹ️** `FileServerRow` already calls the daemon running when `OLLMrpc.ClientBoot.connectable()` is true. Use that same check. Do not add a second probe.
- **🚫** Do not add a `NetworkUtils` class, and do not call `Posix.getifaddrs`. That name is not in the tree.
- **🔷** `✔️` The broadcast needs the real interface list. `0.0.0.0` is not an address to advertise.
- **🔷** `⏳` The registration response carries that same list. That response is [`RPC-1.11.1`](RPC-1.11.1-pin-registration-and-android.md).
- **🔷** `✔️` That list is `OLLMrpc.Transport.TcpListen.ifaces`. It does not stay as the private `FileServerRow.ifaces` method, and it is not a new class.
- **🔷** `✔️` The Host dropdown uses that RPC list. Do not keep a second walk on the row.
- **ℹ️** Today the walk is private on `FileServerRow` and uses `Linux.Network.getifaddrs` (up IPv4, skip `0.0.0.0` and `127.0.0.1`). That already includes VPN adapters (`wg0`, `tun0`) and local adapters (`eth0`, `wlan0`). `0.0.0.0` is IPv4 only.
- **🔷** `✔️` Publish the pairing service over mDNS while pair mode is on. Advertise only the addresses for the listen choice.
- **🔷** The browse label is `rpc`. The full name is `_rpc._tcp.local`.
- **ℹ️** The browse name is always `_<label>._tcp.local`. The two underscores, `_tcp`, and `.local` stay. `rpc` is a legal label: letters only, under 15 characters.
- **ℹ️** The broadcast is mDNS to `224.0.0.251` port `5353`. With label `rpc`, listen port `8422`, instance name `ollmchat`, and addresses `192.168.1.5` and `10.8.0.1`, the records are:

```
PTR  _rpc._tcp.local.
     → ollmchat._rpc._tcp.local.

SRV  ollmchat._rpc._tcp.local.
     0 0 8422 ollmchat.local.

A    ollmchat.local. → 192.168.1.5
A    ollmchat.local. → 10.8.0.1
```

- **ℹ️** The phone browses `_rpc._tcp.local`. The SRV carries the port. The PIN is not in this packet.
- **🔷** `✔️` The listen-choice addresses are A records on `ollmchat.local`, one record per address, in the same packet. The example above is that list.
- **ℹ️** An A record holds the address only. `eth0` or `wg0` cannot be written on that line. The phone tells the addresses apart by which one answers.
- **🚫** Do not put the address list in a TXT record.
- **ℹ️** Any other device advertising `_rpc._tcp` on the same network shows up in that browse.
- **🔷** `⏳` The registration response carries that same address set and the listen port.
- **ℹ️** Avahi is not a dependency in this repo yet. This phase adds it.
- **🔷** `✔️` Store **All** as host `0.0.0.0` in the existing `filesd.socket` string. No new config key. The SSL host dropdown shows **All** for that value. The HTTPS host dropdown stays a single address.

### Notes

- **ℹ️** Listen port stays `filesd.socket` (local network SSL, default 8422 in [`RPC-8.2.8.7`](RPC-8.2.8.7-URGENT-filesd-tcp-socket-lan.md)). This phase does not add a listener.
- **ℹ️** `SslListen` already binds the host in `filesd.socket` and does not reject `0.0.0.0`. This phase does not edit that bind.
- **ℹ️** **All** advertises every address from `OLLMrpc.Transport.TcpListen.ifaces`. A public address on the machine is included. The PIN window is still required.

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify surrounding context before applying.

### ✔️ 1. `libocrpc/Transport/TcpListen.vala` — `ifaces`

**Why:** The broadcast and the host dropdown share one walk. It sits on the TCP listener. No new class.

**Where:** static method at the end of `TcpListen`, after `stop`. `Linux.Network.getifaddrs` is compiled only on desktop Linux. Android and Windows return an empty list.

**Depends on:** none.

#### Add — after `stop`, before the class closing brace. Up non-loopback IPv4 addresses.

```vala
		/**
		 * Up non-loopback IPv4 addresses on this machine.
		 *
		 * Skips ''0.0.0.0'', ''127.0.0.1'', and duplicates.
		 * The SSL **All** choice is not an entry. The dropdown
		 * adds that label itself.
		 *
		 * @return One string per address. Empty when this
		 * platform has no ''getifaddrs'' or the call fails.
		 */
		public static string[] ifaces()
		{
#if ANDROID || G_OS_WIN32
			string[] none = {};
			return none;
#else
			Linux.Network.IfAddrs addrs;
			if (Linux.Network.getifaddrs(out addrs) != 0) {
				string[] none = {};
				return none;
			}
			string[] found = {};
			for (unowned var iface = addrs; iface != null; iface = iface.ifa_next) {
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
				if (ip == null || ip == "" || ip == "0.0.0.0" || ip == "127.0.0.1") {
					continue;
				}
				var seen = false;
				foreach (var existing in found) {
					if (existing != ip) {
						continue;
					}
					seen = true;
					break;
				}
				if (seen) {
					continue;
				}
				found += ip;
			}
			return found;
#endif
		}
```

### ✔️ 2. `libocrpc/Transport/PairPublish.vala` — mDNS A records

**Why:** Pair mode broadcasts `_rpc._tcp` with one A record per listen-choice address. The PIN is not in the packet. No TXT address list.

**Where:** new file in `OLLMrpc.Transport`, same folder as `TcpListen`. Desktop Linux source list only. Android and Windows do not compile it, so the file has no platform `#if`.

**Depends on:** §1.

#### Add — new file. Publish the service and one A record per address. Each Avahi call that throws has its own try.

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

namespace OLLMrpc.Transport
{
	/**
	 * mDNS publish for the pairing window.
	 *
	 * {@link start} sends PTR, SRV, and one A record per address
	 * for ''_rpc._tcp'' in ''.local''. {@link stop} withdraws them.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var pub = new OLLMrpc.Transport.PairPublish();
	 * pub.start(OLLMrpc.Transport.TcpListen.ifaces(), 8422);
	 * pub.stop();
	 * }}}
	 */
	public class PairPublish : GLib.Object
	{
		private string[] addresses = {};
		private uint16 port = 0;
		private bool up = false;
		private Avahi.Client? client = null;
		private Avahi.EntryGroup? group = null;

		/**
		 * Avahi failed after {@link start} had already returned.
		 *
		 * The dialog toasts. {@link start} itself returns false
		 * for a failure that happens before it returns.
		 */
		public signal void failed();

		/**
		 * Publish ''addresses'' on ''_rpc._tcp'' at ''port''.
		 *
		 * Returns false when the list is empty, the port is
		 * outside 1024–65535, or Avahi rejects the records now.
		 * A later failure emits {@link failed}.
		 *
		 * @param addresses Listen-choice IPv4 addresses
		 * @param port TLS bin listen port
		 * @return false when the publish did not succeed
		 */
		public bool start(string[] addresses, uint16 port)
		{
			this.stop();
			if (addresses.length == 0 || port < 1024) {
				this.failed();
				return false;
			}
			this.addresses = addresses;
			this.port = port;
			var fresh = this.client == null;
			if (fresh) {
				var client = new Avahi.Client(Avahi.ClientFlags.NO_FAIL);
				var group = new Avahi.EntryGroup();
				client.state_changed.connect((state) => {
					if (state == Avahi.ClientState.FAILURE) {
						this.failed();
						return;
					}
					if (state != Avahi.ClientState.S_RUNNING) {
						return;
					}
					if (this.commit()) {
						return;
					}
					this.failed();
				});
				try {
					group.attach(client);
				} catch (Avahi.Error e) {
					this.failed();
					return false;
				}
				try {
					client.start();
				} catch (Avahi.Error e) {
					this.failed();
					return false;
				}
				this.client = client;
				this.group = group;
			}
			if (this.client.state == Avahi.ClientState.FAILURE) {
				return false;
			}
			if (fresh || this.client.state != Avahi.ClientState.S_RUNNING) {
				return true;
			}
			if (this.commit()) {
				return true;
			}
			this.failed();
			return false;
		}

		/**
		 * Withdraw the pairing service.
		 */
		public void stop()
		{
			if (!this.up || this.group == null) {
				return;
			}
			this.up = false;
			try {
				this.group.reset();
			} catch (Avahi.Error e) {
				return;
			}
		}

		/**
		 * Commit PTR, SRV, and one A record per address.
		 *
		 * DNS class and type are both 1 (IN, A). The A record
		 * holds the address only.
		 *
		 * @return false when Avahi rejects the records
		 */
		private bool commit()
		{
			if (this.addresses.length == 0 || this.group == null) {
				return false;
			}
			var name = GLib.Environment.get_host_name();
			var dot = name.index_of(".");
			if (dot > 0) {
				name = name.substring(0, dot);
			}
			var host = name + ".local";
			if (this.up) {
				try {
					this.group.reset();
				} catch (Avahi.Error e) {
					return false;
				}
				this.up = false;
			}
			try {
				this.group.add_service_full(Avahi.Interface.UNSPEC,
					Avahi.Protocol.INET, Avahi.PublishFlags.NO_COOKIE,
					name, "_rpc._tcp", "local", host, this.port);
			} catch (Avahi.Error e) {
				return false;
			}
			foreach (var ip in this.addresses) {
				var packed = new char[4];
				if (Posix.inet_pton(Posix.AF_INET, ip, packed) != 1) {
					continue;
				}
				try {
					this.group.add_record_full(Avahi.Interface.UNSPEC,
						Avahi.Protocol.INET, (Avahi.PublishFlags) 0,
						host, 1, 1, 120, packed);
				} catch (Avahi.Error e) {
					return false;
				}
			}
			try {
				this.group.commit();
			} catch (Avahi.Error e) {
				return false;
			}
			this.up = true;
			return true;
		}
	}
}
```

### ✔️ 3. `libocrpc/meson.build` — compile the list and the publish

**Why:** Desktop Linux links Avahi and the `linux` vapi. `PairPublish.vala` is only in that source list.

**Where:** inside `if use_unix_sockets`, with the existing gio-unix deps. The file joins `transport_socket_src`.

**Depends on:** §1, §2.

#### Add — inside `if use_unix_sockets`, after the `gobject-introspection-1.0` dependency lines. Avahi and `linux` for the desktop walk and publish.

```meson
  ocrpc_deps += dependency('avahi-gobject')
  ocrpc_vapi_pkgs += '--pkg=avahi-gobject'
  ocrpc_vapi_pkgs += '--pkg=linux'
  ocrpc_vapi_gen_pkgs += ['--pkg', 'avahi-gobject']
  ocrpc_vapi_gen_pkgs += ['--pkg', 'linux']
```

#### Remove — the desktop Linux socket source list.

```meson
  transport_socket_src = files(['Transport/SocketListen.vala'])
```

#### Replace with — same list, plus the publish.

```meson
  transport_socket_src = files([
    'Transport/SocketListen.vala',
    'Transport/PairPublish.vala',
  ])
```

### ✔️ 4. `docs/meson.build` — valadoc inputs

**Why:** New `libocrpc` sources are listed by path for valadoc.

**Where:** after `'../libocrpc/ClientBoot.vala'`.

**Depends on:** §1, §2.

#### Add — after `'../libocrpc/ClientBoot.vala'`.

```meson
    '../libocrpc/Transport/PairPublish.vala',
```

### ✔️ 5. `ollmapp/SettingsDialog/FileServerRow.vala` — **All** stores `0.0.0.0`

**Why:** The SSL host dropdown uses the RPC list and adds **All**. Choosing it writes `0.0.0.0` into `filesd.socket`. HTTPS is unchanged. `running` is the daemon check this row already makes, so the pairing button can read it.

**Where:** drop `addresses` and `ifaces`. `load_config` fills the dropdowns. `apply_config` maps **All**.

**Depends on:** §1.

#### Remove — field `addresses` and its docblock.

```vala
		/**
		 * IPv4 addresses on interfaces that are up.
		 *
		 * Filled by {@link ifaces}. Skips ''0.0.0.0'' and
		 * ''127.0.0.1''.
		 */
		private string[] addresses = {};
```

#### Add — property, on the line after `public OLLMchat.Settings.Filesd filesd { get; private set; }`. True after `load_config` when the daemon accepts a connection.

```vala
		/**
		 * True when the files daemon accepts a connection.
		 *
		 * Set at the end of {@link load_config} from
		 * {@link OLLMrpc.ClientBoot.connectable}.
		 */
		public bool running { get; private set; default = false; }
```

#### Remove — docblock sentence that the SSL host list matches HTTPS.

```vala
		 * SSL listen IP. Same list as HTTPS. Neither includes
		 * ''127.0.0.1''.
```

#### Replace with — SSL host list is the RPC walk plus **All**.

```vala
		 * SSL listen IP. {@link OLLMrpc.Transport.TcpListen.ifaces} plus ''All''.
		 * ''All'' stores ''0.0.0.0''.
```

#### Remove — `ifaces`. The walk now lives on `OLLMrpc.Transport.TcpListen`.

```vala
		/**
		 * List this machine's IPv4 addresses into {@link addresses}.
		 *
		 * Returns when {@link addresses} is already filled, and
		 * when ''getifaddrs'' is not zero. Up interfaces only.
		 * Skips ''0.0.0.0'', ''127.0.0.1'', and duplicates.
		 * HTTPS and the local network socket both use this list.
		 */
		private void ifaces()
		{
			if (this.addresses.length > 0) {
				return;
			}
			Linux.Network.IfAddrs addrs;
			if (Linux.Network.getifaddrs(out addrs) != 0) {
				return;
			}
			string[] found = {};
			for (unowned var iface = addrs; iface != null; iface = iface.ifa_next) {
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
				if (ip == null || ip == "" || ip == "0.0.0.0" || ip == "127.0.0.1") {
					continue;
				}
				var seen = false;
				foreach (var existing in found) {
					if (existing != ip) {
						continue;
					}
					seen = true;
					break;
				}
				if (seen) {
					continue;
				}
				found += ip;
			}
			this.addresses = found;
		}
```

#### Remove — `load_config` list fill, from `this.ifaces()` through the SSL dropdown `selected` assignment.

```vala
			this.ifaces();
			var ips = this.addresses[0:this.addresses.length];
			var ssl_ips = this.addresses[0:this.addresses.length];
```

#### Replace with — HTTPS uses the RPC list. SSL puts **All** first. A saved `0.0.0.0` selects **All**.

```vala
			var found = OLLMrpc.Transport.TcpListen.ifaces();
			var ips = found[0:found.length];
			string[] ssl_ips = { "All" };
			foreach (var ip in found) {
				ssl_ips += ip;
			}
```

#### Remove — SSL dropdown selection that appends an unknown host, including `0.0.0.0`.

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
```

#### Replace with — `0.0.0.0` selects **All**. Any other saved host that is not in the list is still appended.

```vala
			if (ssl_ips.length > 0) {
				var ssl_selected = Gtk.INVALID_LIST_POSITION;
				if (socket_host == "0.0.0.0") {
					ssl_selected = 0;
				}
				for (var i = 0; i < ssl_ips.length; i++) {
					if (ssl_ips[i] != socket_host) {
						continue;
					}
					ssl_selected = i;
					break;
				}
				if (socket_host != "" && socket_host != "0.0.0.0"
					&& ssl_selected == Gtk.INVALID_LIST_POSITION) {
					ssl_ips += socket_host;
					ssl_selected = ssl_ips.length - 1;
				}
				this.ssl_host_dropdown.model = new Gtk.StringList(ssl_ips);
				this.ssl_host_dropdown.selected = ssl_selected;
			}
```

#### Add — in `load_config`, on the line after `var up = boot.connectable();`. The pairing button reads this.

```vala
			this.running = up;
```

#### Add — in `apply_config`, on the line after the `ssl_item` null check that sets `ssl_host`. **All** is stored as `0.0.0.0`.

```vala
			if (ssl_host == "All") {
				ssl_host = "0.0.0.0";
			}
```

### ✔️ 6. `ollmapp/SettingsDialog/PairingDialog.vala` — publish while the dialog is open

**Why:** Pair mode is this dialog. Opening it publishes the listen-choice addresses. A false return or {@link OLLMrpc.Transport.PairPublish.failed} toasts. Closing the dialog, or the minute ending, withdraws the broadcast.

**Where:** constructor, `open`, and the `closed` handler.

**Depends on:** §1, §2, §5.

#### Add — field, on the line after `public Adw.ToastOverlay toast_overlay { get; construct; }`. The page owns the dialog. The dialog reads toasts, the listen socket, and the parent window from that page.

```vala
		/**
		 * Connections tab that owns this dialog.
		 *
		 * Toasts, the listen socket, and the parent window
		 * are read from this page.
		 */
		private unowned ConnectionsPage page;

		private OLLMrpc.Transport.PairPublish publish;
```

#### Remove

```vala
		public PairingDialog(Adw.ToastOverlay toast_overlay)
		{
			Object(toast_overlay: toast_overlay, title: "Allow New Device");
```

#### Replace with — the connections page, not the overlay and the listen settings as separate arguments.

```vala
		public PairingDialog(ConnectionsPage page)
		{
			Object(title: "Allow New Device");
			this.page = page;
			this.publish = new OLLMrpc.Transport.PairPublish();
			this.publish.failed.connect(() => {
				this.page.toast_overlay.add_toast(new Adw.Toast(
					"Could not publish the pairing service"));
			});
```

#### Add — inside the existing `closed` handler, on the line after `this.pairing = false;`. Withdraws the broadcast when the dialog closes.

```vala
				this.publish.stop();
```

#### Add — in `open`, on the line after `this.pairing = true;`. One address, or every address when the socket host is `0.0.0.0`. `open` takes no parent; it presents on `this.page.dialog`.

```vala
			var socket = this.page.dialog.app.config.filesd.socket;
			var colon = socket.last_index_of(":");
			if (colon > 0) {
				var host = socket.substring(0, colon);
				var parsed = 0;
				int.try_parse(socket.substring(colon + 1), out parsed);
				if (parsed >= 1024 && parsed <= 65535) {
					string[] addrs = {};
					if (host == "0.0.0.0") {
						addrs = OLLMrpc.Transport.TcpListen.ifaces();
					}
					if (host != "" && host != "0.0.0.0") {
						addrs = { host };
					}
					this.publish.start(addrs, (uint16) parsed);
				}
			}
```

#### Add — in the timeout lambda, on the line after `this.pairing = false;`. The minute ending withdraws the broadcast before `close`.

```vala
				this.publish.stop();
```

### ✔️ 7. `ollmapp/SettingsDialog/ConnectionsPage.vala` — button follows the server

**Why:** **Allow New Device** is hidden until this page can set the file server up and that server is running. The button starts hidden. `load_config` shows it from `FileServerRow.running`. Android and Windows have no server row, so nothing sets it visible.

**Where:** the button field, its constructor, the `PairingDialog` call, and `load_config`.

**Depends on:** §5, §6.

#### Add — field, on the line after `private PairingDialog pairing_dialog;`.

```vala
		private Gtk.Button allow_btn;
```

#### Remove

```vala
			this.pairing_dialog = new PairingDialog(this.toast_overlay);
```

#### Replace with

```vala
			this.pairing_dialog = new PairingDialog(this);
```

#### Remove

```vala
			var allow = new Gtk.Button() {
				child = allow_box,
				hexpand = true
			};
			allow.clicked.connect(() => {
				this.pairing_dialog.open(this.dialog);
			});
			this.action_widget.append(allow);
```

#### Replace with — hidden until `load_config` sees the daemon up.

```vala
			this.allow_btn = new Gtk.Button() {
				child = allow_box,
				hexpand = true,
				visible = false
			};
			this.allow_btn.clicked.connect(() => {
				this.pairing_dialog.open();
			});
			this.action_widget.append(this.allow_btn);
```

#### Add — in `load_config`, inside the existing `#if !ANDROID && !G_OS_WIN32` block, on the line after `this.file_server_row.load_config();`.

```vala
			this.allow_btn.visible = this.file_server_row.running;
```

---

## Phase 3 and Phase 4

- **ℹ️** PIN check, CSR, the registration response, and Android discovery are [`RPC-1.11.1-pin-registration-and-android.md`](RPC-1.11.1-pin-registration-and-android.md).
- **🔷** `⏳` Phase 3 — CSR plus PIN on the TLS bin socket. Valid PIN returns the signed cert, the CA public certificate, and the listen-choice address list.
- **🔷** `⏳` Phase 4 — Android **Add connection** browses for the pairing service, then stores every returned address and probes them on later starts.

---

## Phase 5 — Register a friend (later, not urgent)

### Goal

- **🔷** `⏳` Not part of the urgent pairing work. Do this after Phases 1–4.
- **🔷** `⏳` The client connections list has **Register a friend**.
- **🔷** `⏳` Use it to register another device, for example a tablet, while the phone is already connected.
- **🔷** `⏳` On the tablet, **Register a friend** starts the same 60-second pairing window remotely.
- **🔷** `⏳` The six-digit PIN is shown on the phone that is already connected. The tablet types that PIN to register.
- **ℹ️** The connections list is `ollmapp/SettingsDialog/ConnectionsPage.vala`.
- **ℹ️** The push to the phone uses the open TLS bin socket. That is why this waits until steady-state notifications exist.

### Notes

- **⏳** Code proposals when this phase is picked up. Phases 1–4 do not need it.

---

## LLM notes

- **ℹ️** The PIN comes from `GLib.Random`. Do not replace it with an OS CSPRNG. The window is 60 seconds and the network is local.
- **ℹ️** Parent Phase 7 and **8.2.7** still say “no CSR, no pairing codes, admin approval, internet-facing daemon”. This file wins for new pairing work.
- **ℹ️** The listener gate, the CSR response, and the Android browse are [`RPC-1.11.1`](RPC-1.11.1-pin-registration-and-android.md).
- **ℹ️** One completed pairing closes the window. Until Phase 5, another device needs **Allow New Device** on the desktop again. **Register a friend** is Phase 5 only.
- **ℹ️** A wrong PIN does not regenerate the PIN and does not close the dialog. The user considered both and kept the same PIN for the rest of the minute. **number rejected** is an `Adw.Toast`, not dialog text and not an action-bar banner.
- **ℹ️** Multi-select of specific interfaces is later. Implement one address or all interfaces only, on `filesd.socket`.
- **ℹ️** Avahi on this plan is the Linux publisher only. The phone browse is Phase 4 in [`RPC-1.11.1`](RPC-1.11.1-pin-registration-and-android.md).
- **ℹ️** Do not add an HTTPS registration or steady-state fallback in this plan. [`RPC-8.2.8.7`](RPC-8.2.8.7-URGENT-filesd-tcp-socket-lan.md) still describes HTTPS outside the LAN. This file wins for pairing and for notifications.
