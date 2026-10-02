# RPC-1.11 — URGENT — VPN/local timed PIN pairing

> **Do not update `docs/plans/RPC-1.0-summary.md` for this plan.**

**Status:** **URGENT** — proposed. Design only. Code fences after the Avahi service type is confirmed.

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
- **⏳** `🔷` Phases 1–4 below. No code in this file yet.
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

1. Phase 1 — `PairingDialog` on the GTK server
2. Phase 2 — Listen on one interface or all, then mDNS advertise
3. Phase 3 — PIN check, CSR, signed cert, address list in the registration response
4. Phase 4 — Android discovery, PIN prompt, route probe, fallbacks
5. Phase 5 — **Register a friend** (later, not urgent)

---

## Phase 1 — `PairingDialog` (server)

### Goal

- **🔷** `✔️` New class `OLLMapp.SettingsDialog.PairingDialog` in `ollmapp/SettingsDialog/PairingDialog.vala`. The pairing dialog and most of the pairing logic live in that class.
- **🔷** `✔️` That class owns the session: generate the PIN, show it, run the 60-second countdown line, fire the timeout, and toast **number rejected**.
- **🔷** `⏳` Opening and closing pair mode still has to start and stop mDNS (Phase 2). `pairing` is the flag.
- **🔷** `✔️` **Allow New Device** on the connections action bar opens `PairingDialog`.
- **🔷** `✔️` Pair mode on shows the 6-digit PIN in that dialog. The PIN is the main focus: large, spaced digits from the `.pairing-pin` class in `resources/style.css`.
- **🔷** `✔️` That dialog draws a sliding line that counts the 60 seconds down so the remaining time is visible.
- **🔷** `✔️` Pair mode on starts a 60-second `GLib.Timeout`.
- **🔷** `✔️` `rejected()` toasts **number rejected** and leaves the dialog and PIN up. Nothing calls it until a wrong PIN arrives from the server.
- **🔷** `✔️` The dialog closes when the timeout fires, and `pairing` turns off. Closing when a device finishes pairing waits on the registration response (Phase 3).
- **🔷** `⏳` Pair mode off stops the mDNS broadcast and rejects a non-registered connection outright. Registration does not start.
- **🔷** The user named this RPC `register_client`.
- **ℹ️** The live method is `RPC-ClientCert.request_registration`. Gate that method. A second method name needs a separate decision (see **LLM notes**).
- **🔷** `✔️` Generate the six digits with `GLib.Random`. A 60-second PIN on the local network does not need a cryptographic generator.

### Notes

- **ℹ️** Today’s approval UI is `RegistrationBanner` on the settings action bar (Accept / Reject / Ban). `PairingDialog` replaces that for this flow. Connections already toasts from `ConnectionsPage.toast_overlay`.
- **ℹ️** The listener still rejects a non-registered connection when pair mode is off. That check stays in `ollmfilesd`. `PairingDialog.pairing` is the flag Phase 2 and that listener follow. mDNS itself is Phase 2.
- **🔷** `✔️` **Allow New Device** is a third button on the connections action bar, beside **LLM Connection** and **Remote Desktop Connection**.
- **🔷** `⏳` **Allow New Device** is hidden when this app cannot set the file server up, and while that server is not active. That is the visibility catch. There is no OS `#if` on the button. Windows and Android have no server setup, so the same check hides it there. Wire the show and hide after the listen rejig in Phase 2.

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify surrounding context before applying.

### 1. `ollmapp/SettingsDialog/PairingDialog.vala` — new pairing dialog

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

### 2. `resources/style.css` — large PIN digits

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

### 3. `ollmapp/meson.build` — compile `PairingDialog` on every app build

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

### 4. `ollmapp/SettingsDialog/ConnectionsPage.vala` — **Allow New Device** on the bottom bar

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

## Phase 2 — Listen on one interface or all (server)

### Goal

- **🔷** `⏳` One-or-all applies to the TLS bin socket (`filesd.socket` / `SslListen`) only.
  - **One:** bind that address only, same as today’s `filesd.socket` host.
  - **All:** listen on every interface. The phone’s address list is every up non-loopback IPv4 from the same enumeration `FileServerRow.ifaces` already uses.
- **🔷** `⏳` A list of specific interfaces (more than one, short of all) is later. This plan does not build that multi-select.
- **🔷** `⏳` Leave the HTTPS listener and its Host dropdown unchanged. HTTPS is not the pairing transport and not a fallback when the socket is unreachable.
- **🔷** `⏳` After this listen change, show **Allow New Device** only when this app can set the file server up and that server is active.
  - Do not hide the button with `#if ANDROID` or `#if G_OS_WIN32`. Those builds have no server setup, so this check covers them.
  - **ℹ️** `FileServerRow` already calls the daemon running when `OLLMrpc.ClientBoot.connectable()` is true. Use that same check. Do not add a second probe.
- **🔷** `⏳` Component the user named `NetworkUtils` enumerates those interfaces with `Posix.getifaddrs`.
  - VPN adapters (examples `wg0`, `tun0`)
  - local adapters (examples `eth0`, `wlan0`)
- **🔷** `⏳` Publish the pairing service over mDNS while pair mode is on. Advertise only the addresses for the listen choice.
- **🔷** Service type the user wrote: `_myapp_pair._tcp`.
- **🔷** `⏳` The registration response carries that same address set and the listen port.
- **ℹ️** Avahi is not a dependency in this repo yet. This phase adds it.
- **💩** `⏳` Store **All** as host `0.0.0.0` in the existing `host:port` string. No new config key. Confirm before implement.
- **💩** `⏳` `_myapp_pair._tcp` reads as a placeholder. Confirm a product type (for example `_ollmfilesd-pair._tcp`) before implement.

### Notes

- **ℹ️** Listen port stays `filesd.socket` (local network SSL, default 8422 in [`RPC-8.2.8.7`](RPC-8.2.8.7-URGENT-filesd-tcp-socket-lan.md)). This phase does not add a listener.
- **ℹ️** **All** includes every address the Host dropdown can already show. A public address on the machine is included when the operator picks All. The PIN window is still required.
- **⏳** Code proposals after the service type string is confirmed.

---

## Phase 3 — Registration response

### Goal

- **🔷** `⏳` During the pairing window the phone submits a CSR and the 6-digit PIN on the TLS bin socket.
- **🔷** `⏳` Server checks the PIN against the value from Phase 1.
- **🔷** `⏳` Valid PIN: sign the CSR with the server CA key from disk, return that client certificate and the CA public certificate, and return the listen-choice address list from Phase 2 (one IP, or all).
- **🔷** `⏳` Wrong PIN: refuse that attempt, leave pair mode on, leave the PIN unchanged, and toast **number rejected**. No pending row.
- **🔷** `⏳` Expired window or pair mode off: reject the connection outright. Do not run registration. No pending row.
- **🔷** `⏳` One successful pairing ends the window (Phase 1).

### Notes

- **ℹ️** Landed clients already hold a self-signed device cert and wait for Accept. This phase returns a server-signed cert instead. The phone does not get the CA private key.
- **ℹ️** Already-approved `client_cert` rows stay the steady-state allow list. This plan does not describe wiping them.
- **⏳** Code proposals after Phase 1’s gate shape is confirmed.

---

## Phase 4 — Android discovery and route selection

### Goal

- **🔷** `⏳` **Add connection** on the phone shows **Listening for connection** and browses for the pairing service. No manual IP entry. The six-digit prompt waits until mDNS finds the server.
- **💩** `⏳` Browse with Android `NsdManager` (`android.net.nsd`) through JNI, same pattern as `ollmapp/android/android-partial-wake-lock.c`. The service type is the one the Linux Avahi publisher registered. `Avahi.ServiceBrowser` does not run on the phone.
- **🔷** `⏳` After discovery, prompt for the six digits.
- **🔷** `⏳` Connect the TLS bin socket, send CSR + PIN, read the signed cert and the address list.
- **🔷** `⏳` Store every returned address with the connection, including the VPN address and the local address.
- **🔷** `⏳` On each app start, probe the stored addresses and connect to one that answers.
  - 2-second timeout per address
  - In the house or the office the local address answers
  - Outside, the local network is absent, so the stored VPN address is the one that answers
- **🔷** `⏳` Later RPC stays on that bin socket so server notifications have a live connection.

### Notes

- **ℹ️** `FileConnectionAdd` today asks for a URL and calls `request_registration` over HTTPS. This phase is the socket pairing path on Android (`FilesdClient.State.SOCKET`).
- **ℹ️** `OLLMchat.Settings.FilesdClient` stores one `url` today. This phase stores the full address list beside that connection.
- **ℹ️** [`RPC-8.2.8.7`](RPC-8.2.8.7-URGENT-filesd-tcp-socket-lan.md) sent the phone to HTTPS when it left the LAN. This plan does not add that downgrade. Notifications need the socket.
- **⏳** Code proposals after Phases 1–3 response fields are confirmed.

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
- **ℹ️** User RPC name is `register_client`. Tree name is `RPC-ClientCert.request_registration`. Gate the existing method. Do not add a parallel RPC until that rename is explicitly requested.
- **ℹ️** Parent Phase 7 and **8.2.7** still say “no CSR, no pairing codes, admin approval, internet-facing daemon”. This file wins for new pairing work.
- **ℹ️** Nginx WAN registration in `docs/filesd-behind-nginx-proxy.md` is the exposure this plan removes. Update that doc in the same change as the listener gate, not as a drive-by.
- **ℹ️** One completed pairing closes the window. Until Phase 5, another device needs **Allow New Device** on the desktop again. **Register a friend** is Phase 5 only.
- **ℹ️** A wrong PIN does not regenerate the PIN and does not close the dialog. The user considered both and kept the same PIN for the rest of the minute. **number rejected** is an `Adw.Toast`, not dialog text and not an action-bar banner.
- **ℹ️** Multi-select of specific interfaces is later. Implement one address or all interfaces only, on `filesd.socket`.
- **ℹ️** Avahi stays on the Linux server as the mDNS publisher. The Android browser is `NsdManager` via JNI. Do not link `Avahi.ServiceBrowser` into the phone build.
- **ℹ️** Do not add an HTTPS registration or steady-state fallback in this plan. [`RPC-8.2.8.7`](RPC-8.2.8.7-URGENT-filesd-tcp-socket-lan.md) still describes HTTPS outside the LAN. This file wins for pairing and for notifications.
