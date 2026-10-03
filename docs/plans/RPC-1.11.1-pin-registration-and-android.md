# RPC-1.11.1 — PIN registration and Android discovery

> **Do not update `docs/plans/RPC-1.0-summary.md` for this sub-plan** until it is done and archived.

**Status:** proposed

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala follows `docs/coding-standards.md`.

**Parent:** [`RPC-1.11-URGENT-vpn-local-pin-pairing.md`](RPC-1.11-URGENT-vpn-local-pin-pairing.md) — Phases 3 and 4

**Depends on:** Phase 1 and Phase 2 of the parent (PIN dialog, listen choice, mDNS publish)

---

## Purpose

- **🔷** `⏳` During the pairing window the phone submits a CSR and the 6-digit PIN on the TLS bin socket.
- **🔷** `⏳` A valid PIN signs that CSR with the server CA and returns the signed cert, the CA public certificate, and the listen-choice address list.
- **🔷** `⏳` Android **Add connection** finds that server over mDNS, then asks for the PIN. No typed IP.
- **🔷** `⏳` The phone stores every returned address and, on later starts, connects to one that answers.
- **ℹ️** The PIN dialog, the 60-second window, **All** as `0.0.0.0`, and the `_rpc._tcp.local` publish are Phase 1 and Phase 2 of the parent.

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

- **ℹ️** The PIN is on `PairingDialog` in the GTK process. The TLS listener is `ollmfilesd`. The dialog sends the PIN to the daemon on the existing Unix RPC. An empty PIN is pair mode off.
- **💩** That local call is `ClientCert.pair`. It is not a second registration method. `request_registration` stays the phone’s method.
- **💩** A wrong PIN and a finished pairing notify the desktop as `event.pair` (`rejected` / `done`). `event.client_cert` stays the pending-row signal, and this phase does not emit it.
- **ℹ️** Landed clients already hold a self-signed device cert and wait for Accept. This phase returns a server-signed cert and stores it approved. The phone does not get the CA private key.
- **ℹ️** Already-approved `client_cert` rows stay the steady-state allow list. This plan does not describe wiping them.
- **ℹ️** Signing uses the CA already on disk, `{data_dir}/tls/ollmrpc-ca.pem` and `ollmrpc-ca-key.pem`. Removing the bundled CA stays in the parent Certificates section.
- **💩** If the dialog cannot hand the PIN to the daemon, the toast is **Could not start pairing**.
- **💩** Names in the fences that this write-up chose: `pair`, `event.pair`, `set_crq`, `arm`, `finish`, `pair_notice`.

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify surrounding context before applying.

### 1. `ollmfilesd/SslListen.vala` — `pin`

**Why:** Pair mode is this string. Empty means the window is closed. The registration method reads it.

**Where:** field, on the line after `public OllmfilesdApplication app`.

**Depends on:** none.

#### Add — field after `app`. The dialog sets it through `ClientCert.pair`.

```vala
		/**
		 * Six-digit PIN while the pairing window is open.
		 *
		 * Empty when the window is closed. {@link OLLMfilesd.ClientCert.request_registration}
		 * accepts a phone only when this matches.
		 */
		public string pin { get; set; default = ""; }
```

### 2. `ollmfilesd/ClientCert.vala` — `pair` and the registration reply

**Why:** The phone’s existing method takes the PIN and the CSR. A match signs the CSR with the on-disk CA, stores the new cert approved, and returns that cert, the CA certificate, and the listen-choice addresses. A mismatch toasts and writes no row. HTTPS can no longer register.

**Where:** `rpc_register` signature list, then `request_registration`. `pair` is a new method after `request_registration`.

**Depends on:** §1.

#### Remove — `request_registration` takes one string.

```vala
				"request_registration", "s",
```

#### Replace with — PIN, CSR PEM, and the device string.

```vala
				"request_registration", "sss",
				"pair", "s",
```

#### Remove — `request_registration` as it stands. It records a pending HTTPS row.

```vala
		/**
		 * Record this connection's client cert as pending registration.
		 *
		 * @param request inbound RPC (connection must be
		 * {@link OLLMrpc.Transport.HttpReply})
		 * @param requester best-effort device string sent by the client
		 */
		public void request_registration(OLLMrpc.Request request, string requester)
		{
			var reply = request.connection as OLLMrpc.Transport.HttpReply;
			if (reply == null) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "HTTPS registration only")
				});
				return;
			}
			if (reply.cert_fingerprint == "") {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "client certificate required")
				});
				return;
			}
			var db = this.app.project_manager.db;
			var q = ClientCert.query(db);
			var int_binds = new Gee.HashMap<string, int>();
			var text_binds = new Gee.HashMap<string, string>();
			int_binds["status"] = 0;
			int_binds["before"] = (int) (new GLib.DateTime.now_utc().to_unix() - (24 * 60 * 60));
			q.deleteWhere("WHERE status = $status AND created < $before", int_binds, null);
			var banned_ip = new Gee.ArrayList<ClientCert>();
			int_binds["status"] = -1;
			text_binds["ip"] = reply.client_ip;
			q.selectWhere("WHERE status = $status AND ip = $ip", int_binds, text_binds, banned_ip);
			if (banned_ip.size > 0) {
				var ban_cutoff = new GLib.DateTime.now_utc().to_unix() - (30 * 24 * 60 * 60);
				if (banned_ip.get(0).created < ban_cutoff) {
					q.deleteId(banned_ip.get(0).id);
				} else {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error(
							(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "IP banned")
					});
					return;
				}
			}
			var existing = new Gee.ArrayList<ClientCert>();
			int_binds.clear();
			text_binds.clear();
			text_binds["fingerprint"] = reply.cert_fingerprint;
			q.selectWhere("WHERE fingerprint = $fingerprint", int_binds, text_binds, existing);
			if (existing.size > 0) {
				var row = existing.get(0);
				if (row.status != 0) {
					request.reply(new OLLMrpc.Response() {
						msg = "ok"
					});
					return;
				}
				row.created = new GLib.DateTime.now_utc().to_unix();
				row.requester = requester;
				q.updateById(row);
				this.app.broadcast(new OLLMrpc.Notification() {
					method = "event.client_cert",
					object_type = "ClientCert",
					action = "request"
				});
				request.reply(new OLLMrpc.Response() {
					msg = "ok"
				});
				return;
			}
			var by_ip = new Gee.ArrayList<ClientCert>();
			int_binds["status"] = 0;
			text_binds["ip"] = reply.client_ip;
			q.selectWhere("WHERE status = $status AND ip = $ip", int_binds, text_binds, by_ip);
			if (by_ip.size >= 3) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
						"too many pending registrations for this IP")
				});
				return;
			}
			var row = new ClientCert() {
				fingerprint = reply.cert_fingerprint,
				status = 0,
				ip = reply.client_ip,
				created = new GLib.DateTime.now_utc().to_unix(),
				requester = requester
			};
			q.insert(row);
			this.app.broadcast(new OLLMrpc.Notification() {
				method = "event.client_cert",
				object_type = "ClientCert",
				action = "request"
			});
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
		}
```

#### Replace with — check the PIN, sign the CSR, store the cert approved, return the PEMs and the listen addresses. No pending row.

```vala
		[CCode (cname = "gnutls_x509_crt_set_crq", cheader_filename = "gnutls/x509.h")]
		private static extern int set_crq(GnuTLS.X509.Certificate crt,
			GnuTLS.X509.CertificateRequest crq);

		/**
		 * Sign ''csr'' when ''pin'' matches {@link OLLMfilesd.SslListen.pin}.
		 *
		 * The reply ''retval'' is a string array. Index 0 is the new
		 * client certificate PEM. Index 1 is the CA certificate PEM.
		 * Each later entry is a ''host:port'' for the listen choice.
		 * A wrong PIN leaves the window up and writes no row.
		 *
		 * @param request inbound RPC on the TLS bin socket
		 * @param pin six digits from the desktop dialog
		 * @param csr PEM certificate request
		 * @param requester best-effort device string
		 */
		public void request_registration(
			OLLMrpc.Request request,
			string pin,
			string csr,
			string requester
		) {
			var rpc = request.connection as SslConnection;
			if (rpc == null) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "socket registration only")
				});
				return;
			}
			var window = "";
			if (this.app.ssl_listen != null) {
				window = this.app.ssl_listen.pin;
			}
			if (window == "" || pin != window) {
				if (window != "") {
					this.app.broadcast(new OLLMrpc.Notification() {
						method = "event.pair",
						action = "rejected"
					});
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error(
							(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "number rejected")
					});
					return;
				}
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "pairing is off")
				});
				rpc.stop();
				return;
			}
			var init_ret = GnuTLS.global_init();
			if (init_ret < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR, "could not sign")
				});
				return;
			}
			var csr_datum = GnuTLS.Datum() {
				data = csr,
				size = csr.length
			};
			var crq = GnuTLS.X509.CertificateRequest.create();
			if (crq.import(ref csr_datum, GnuTLS.X509.CertificateFormat.PEM) < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "bad csr")
				});
				return;
			}
			var crt = GnuTLS.X509.Certificate.create();
			if (set_crq(crt, crq) < 0 || crt.set_version(3) < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "bad csr")
				});
				return;
			}
			var serial = new uint8[16];
			for (var i = 0; i < serial.length; i++) {
				serial[i] = (uint8) GLib.Random.int_range(0, 256);
			}
			var now = (time_t) (GLib.get_real_time() / 1000000);
			if (crt.set_serial(serial, serial.length) < 0
				|| crt.set_activation_time(now) < 0
				|| crt.set_expiration_time(now + (time_t) (3650 * 24 * 60 * 60)) < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR, "could not sign")
				});
				return;
			}
			var tls_dir = GLib.Path.build_filename(this.app.data_dir, "tls");
			var ca_pem = "";
			var ca_key_pem = "";
			try {
				GLib.FileUtils.get_contents(
					GLib.Path.build_filename(tls_dir, "ollmrpc-ca.pem"), out ca_pem);
				GLib.FileUtils.get_contents(
					GLib.Path.build_filename(tls_dir, "ollmrpc-ca-key.pem"), out ca_key_pem);
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR, "could not sign")
				});
				return;
			}
			var ca_datum = GnuTLS.Datum() {
				data = ca_pem,
				size = ca_pem.length
			};
			var key_datum = GnuTLS.Datum() {
				data = ca_key_pem,
				size = ca_key_pem.length
			};
			var ca_crt = GnuTLS.X509.Certificate.create();
			var ca_key = GnuTLS.X509.PrivateKey.create();
			if (ca_crt.import(ref ca_datum, GnuTLS.X509.CertificateFormat.PEM) < 0
				|| ca_key.import(ref key_datum, GnuTLS.X509.CertificateFormat.PEM) < 0
				|| crt.sign2(ca_crt, ca_key, GnuTLS.DigestAlgorithm.SHA256, 0) < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR, "could not sign")
				});
				return;
			}
			var crt_len = (size_t) 0;
			crt.export(GnuTLS.X509.CertificateFormat.PEM, null, ref crt_len);
			var crt_buf = new uint8[crt_len];
			if (crt.export(GnuTLS.X509.CertificateFormat.PEM, crt_buf, ref crt_len) < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR, "could not sign")
				});
				return;
			}
			var crt_pem = (string) crt_buf;
			GLib.TlsCertificate issued;
			try {
				issued = new GLib.TlsCertificate.from_pem(crt_pem);
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR, "could not sign")
				});
				return;
			}
			var fingerprint = GLib.Checksum.compute_for_data(
				GLib.ChecksumType.SHA256, issued.certificate.data);
			var q = ClientCert.query(this.app.project_manager.db);
			q.insert(new ClientCert() {
				fingerprint = fingerprint,
				status = 1,
				created = new GLib.DateTime.now_utc().to_unix(),
				requester = requester
			});
			this.app.ssl_listen.pin = "";
			var socket = this.app.config.filesd.socket;
			var colon = socket.last_index_of(":");
			var host = "";
			var port_text = "";
			if (colon > 0) {
				host = socket.substring(0, colon);
				port_text = socket.substring(colon + 1);
			}
			string[] packed = {};
			packed += crt_pem;
			packed += ca_pem;
			if (host == "0.0.0.0") {
				foreach (var ip in OLLMrpc.Transport.TcpListen.ifaces()) {
					packed += ip + ":" + port_text;
				}
			}
			if (host != "" && host != "0.0.0.0") {
				packed += host + ":" + port_text;
			}
			this.app.broadcast(new OLLMrpc.Notification() {
				method = "event.pair",
				action = "done"
			});
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("as", packed),
				msg = "ok"
			});
		}

		/**
		 * Set {@link OLLMfilesd.SslListen.pin} from the desktop dialog.
		 *
		 * Empty ''pin'' closes the window. Unix socket only.
		 *
		 * @param request inbound RPC from the GTK app
		 * @param pin six digits, or empty to close the window
		 */
		public void pair(OLLMrpc.Request request, string pin)
		{
			if (this.app.ssl_listen == null) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "SSL listener is off")
				});
				return;
			}
			this.app.ssl_listen.pin = pin;
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
		}
```

### 3. `ollmfilesd/SslConnection.vala` — drop the connection when the window is closed

**Why:** Pair mode off must not run registration. A registered certificate still connects. `pair` is local admin, same as the pending-row calls.

**Where:** `allow_request`, the `request_registration` allow, and the local-admin switch.

**Depends on:** §1, §2.

#### Remove — registration is always allowed. `pair` is not in the local-admin switch.

```vala
			switch (request.method) {
				case "ClientCert.pending_cert":
				case "ClientCert.client_cert":
					this.reply(request, new OLLMrpc.Response() {
						error = new OLLMrpc.Error(
							(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "local admin only")
					});
					return false;
			}
			if (request.method == "ClientCert.request_registration") {
				return true;
			}
```

#### Replace with — `pair` stays on the Unix socket. Registration runs only while a PIN is set. Otherwise the connection stops.

```vala
			switch (request.method) {
				case "ClientCert.pending_cert":
				case "ClientCert.client_cert":
				case "ClientCert.pair":
					this.reply(request, new OLLMrpc.Response() {
						error = new OLLMrpc.Error(
							(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "local admin only")
					});
					return false;
			}
			if (request.method == "ClientCert.request_registration") {
				if (this.app.ssl_listen != null && this.app.ssl_listen.pin != "") {
					return true;
				}
				this.reply(request, new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "pairing is off")
				});
				this.stop();
				return false;
			}
```

### 4. `ollmfilesd/Https.vala` — HTTPS does not register

**Why:** Pairing is the TLS bin socket. The open HTTPS registration path closes in the same change.

**Where:** `allow_rpc`, the same local-admin switch and the `request_registration` allow.

**Depends on:** §2.

#### Remove

```vala
			switch (request.method) {
				case "ClientCert.pending_cert":
				case "ClientCert.client_cert":
					reply.write(new OLLMrpc.Response() {
						id = request.id,
						error = new OLLMrpc.Error(
							(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "local admin only")
					});
					return false;
			}
			if (request.method == "ClientCert.request_registration") {
				return true;
			}
```

#### Replace with — `pair` stays a local-admin call. HTTPS refuses registration.

```vala
			switch (request.method) {
				case "ClientCert.pending_cert":
				case "ClientCert.client_cert":
				case "ClientCert.pair":
					reply.write(new OLLMrpc.Response() {
						id = request.id,
						error = new OLLMrpc.Error(
							(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "local admin only")
					});
					return false;
			}
			if (request.method == "ClientCert.request_registration") {
				reply.write(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "socket registration only")
				});
				return false;
			}
```

### 5. `ollmapp/SettingsDialog/PairingDialog.vala` — hand the PIN to the daemon

**Why:** Opening the dialog arms the listener. Closing it, the minute ending, or one success clears the PIN and withdraws mDNS.

**Where:** `open`, the `closed` handler, the timeout lambda. `finish` is new.

**Depends on:** §2.

#### Add — in `open`, on the line after `this.pairing = true;`. Sends the new PIN before mDNS starts.

```vala
			this.arm(this.pin);
```

#### Add — inside the `closed` handler, on the line after `this.pairing = false;`. An empty PIN closes the window on the daemon.

```vala
				this.arm("");
```

#### Add — in the timeout lambda, on the line after `this.pairing = false;`.

```vala
				this.arm("");
```

#### Add — methods, on the line after `rejected`. `finish` is the one successful pairing. `arm` is the Unix call.

```vala
		/**
		 * End the window after one device pairs.
		 *
		 * Clears the daemon PIN, withdraws mDNS, and closes.
		 */
		public void finish()
		{
			this.arm("");
			this.publish.stop();
			this.pairing = false;
			if (this.tick_id != 0) {
				GLib.Source.remove(this.tick_id);
				this.tick_id = 0;
			}
			this.close();
		}

		/**
		 * Send ''pin'' to {@link OLLMfilesd.ClientCert.pair}.
		 *
		 * Empty clears the window. A failed arm while a PIN is
		 * showing toasts ''Could not start pairing''.
		 *
		 * @param pin six digits, or empty
		 */
		private void arm(string pin)
		{
			var win = this.page.dialog.parent;
			if (win == null || win.project_manager == null) {
				if (pin == "") {
					return;
				}
				this.page.toast_overlay.add_toast(new Adw.Toast("Could not start pairing"));
				return;
			}
			win.project_manager.rpc.call.begin(new OLLMrpc.Request() {
				method = "ClientCert.pair",
				args = OLLMrpc.args("s", pin)
			}, (obj, res) => {
				try {
					win.project_manager.rpc.call.end(res);
				} catch (GLib.Error e) {
					if (pin == "") {
						return;
					}
					this.page.toast_overlay.add_toast(
						new Adw.Toast("Could not start pairing"));
				}
			});
		}
```

### 6. `ollmapp/SettingsDialog/ConnectionsPage.vala` — toast or close

**Why:** `event.pair` is how the daemon tells this page the PIN was wrong or a device finished.

**Where:** new method after `load_config`.

**Depends on:** §5.

#### Add — method after `load_config`. `rejected` leaves the dialog up. `done` closes it.

```vala
		/**
		 * Handle one pairing notification from the daemon.
		 *
		 * ''rejected'' toasts. ''done'' ends the window.
		 *
		 * @param action ''rejected'' or ''done''
		 */
		public void pair_notice(string action)
		{
			if (action == "rejected") {
				this.pairing_dialog.rejected();
				return;
			}
			if (action != "done") {
				return;
			}
			this.pairing_dialog.finish();
		}
```

### 7. `ollmapp/SettingsDialog/MainDialog.vala` — wire `event.pair`

**Why:** The page already hears `event.client_cert` on this connection. Pairing uses the same socket.

**Where:** the `notification.connect` lambda in `show_dialog`, inside the `registration_wired` block, on the line after the `event.client_cert` check.

**Depends on:** §6.

#### Add — inside that lambda, after the `event.client_cert` refresh. Does not refresh the pending banner.

```vala
					if (notif.method == "event.pair") {
						this.connections_page.pair_notice(notif.action);
						return;
					}
```

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
- **ℹ️** `⏳` Code proposals after Phase 3 response fields are confirmed.

---

## LLM notes

- **ℹ️** The pasted draft said `register_client`. Tree name is `ClientCert.request_registration`. Gate the existing method. Do not add a parallel RPC until a rename is explicitly requested.
- **ℹ️** Nginx WAN registration in `docs/filesd-behind-nginx-proxy.md` is the exposure this plan removes. Update that doc in the same change as the listener gate, not as a drive-by.
- **ℹ️** Avahi stays on the Linux server as the mDNS publisher. The Android browser is `NsdManager` via JNI. Do not link `Avahi.ServiceBrowser` into the phone build.
- **ℹ️** Do not add an HTTPS registration or steady-state fallback. [`RPC-8.2.8.7`](RPC-8.2.8.7-URGENT-filesd-tcp-socket-lan.md) still describes HTTPS outside the LAN. The parent wins for pairing and for notifications.
