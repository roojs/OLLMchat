# RPC-1.11.1 — PIN registration

> **Do not update `docs/plans/RPC-1.0-summary.md` for this sub-plan** until it is done and archived.

**Status:** Phase 3 agent-done.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala follows `docs/coding-standards.md`.

**Parent:** [`RPC-1.11-URGENT-vpn-local-pin-pairing.md`](RPC-1.11-URGENT-vpn-local-pin-pairing.md) — Phase 3

**Depends on:** Phase 1 and Phase 2 of the parent (PIN dialog, listen choice, mDNS publish)

---

## Purpose

- **🔷** `✔️` During the pairing window the phone submits a CSR and the 6-digit PIN on the TLS bin socket.
- **🔷** `✔️` A valid PIN signs that CSR with the server CA and returns the signed cert, the CA public certificate, and the listen-choice address list.
- **ℹ️** Android discovery, the address probe, and the command-line pairing check are [`RPC-1.11.2`](RPC-1.11.2-android-discovery-and-pair-cli.md).
- **ℹ️** The PIN dialog, the 60-second window, **All** as `0.0.0.0`, and the `_rpc._tcp.local` publish are Phase 1 and Phase 2 of the parent.

---

## Phase 3 — Registration response (`✔️`)

### Goal

- **🔷** `✔️` During the pairing window the phone submits a CSR and the 6-digit PIN on the TLS bin socket.
- **🔷** `✔️` Server checks the PIN against the value from Phase 1.
- **🔷** `✔️` Valid PIN: sign the CSR with the server CA key from disk, return that client certificate and the CA public certificate, and return the listen-choice address list from Phase 2 (one IP, or all).
- **🔷** `✔️` Wrong PIN: refuse that attempt, leave pair mode on, leave the PIN unchanged, and toast **number rejected**. No pending row.
- **🔷** `✔️` Expired window or pair mode off: reject the connection outright. Do not run registration. No pending row.
- **🔷** `✔️` One successful pairing ends the window (Phase 1).

### Notes

- **ℹ️** The PIN is on `PairingDialog` in the GTK process. The TLS listener is `ollmfilesd`. The dialog sends the PIN to the daemon on the existing Unix RPC. An empty PIN is pair mode off.
- **💩** That local call is `ClientCert.pair`. It is not a second registration method. `request_registration` stays the phone’s method.
- **💩** A wrong PIN and a finished pairing notify the desktop as `event.pair` (`rejected` / `done`).
- **🔷** `✔️` Delete the pending-registration calls. `pending_cert`, `client_cert` actions `accept` / `reject` / `ban`, and `event.client_cert` go away, and so does `RegistrationBanner`. A match inserts the row approved. `approved_certs` and `client_cert` action `remove` stay.
- **ℹ️** This phase returns a server-signed cert and stores it approved. The phone does not get the CA private key.
- **ℹ️** Already-approved `client_cert` rows stay the steady-state allow list. This plan does not describe wiping them.
- **ℹ️** Signing uses the CA already on disk, `{data_dir}/tls/ollmrpc-ca.pem` and `ollmrpc-ca-key.pem`. Removing the bundled CA stays in the parent Certificates section.
- **💩** If the dialog cannot hand the PIN to the daemon, the toast is **Could not start pairing**.
- **💩** Names in the fences that this write-up chose: `pair`, `event.pair`, `arm`, `finish`.

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify surrounding context before applying.

### ✔️ 1. `ollmfilesd/SslListen.vala` — `pin`

**Why:** Pair mode is this string. Empty means the window is closed. While it is set, TLS accepts a client with no certificate. While it is empty, the handshake requires a client certificate and does not read the cert table.

**Where:** field, on the line after `public OllmfilesdApplication app`. The handshake mode is the `authentication_mode` assignment in `listen`.

**Depends on:** none.

#### Add — field after `app`. The dialog sets it through `ClientCert.pair`.

```vala
		/**
		 * Six-digit PIN while the pairing window is open.
		 *
		 * Empty when the window is closed. The handshake then
		 * requires a client certificate. While this is set, a
		 * phone with no certificate can connect and send the PIN.
		 */
		public string pin { get; set; default = ""; }
```

#### Remove — every handshake accepts any client certificate, including none.

```vala
				tls.authentication_mode = GLib.TlsAuthenticationMode.REQUESTED;
				tls.accept_certificate.connect((peer_cert, errors) => {
					return true;
				});
```

#### Replace with — a set PIN accepts anyone. An empty PIN requires a client certificate and rejects an unknown CA. No cert-table read.

```vala
				tls.authentication_mode = GLib.TlsAuthenticationMode.REQUIRED;
				if (this.pin != "") {
					tls.authentication_mode = GLib.TlsAuthenticationMode.REQUESTED;
				}
				tls.accept_certificate.connect((peer_cert, errors) => {
					if (this.pin != "") {
						return true;
					}
					if (peer_cert == null) {
						return false;
					}
					return (errors & ~GLib.TlsCertificateFlags.BAD_IDENTITY) == 0;
				});
```

### ✔️ 2. `ollmfilesd/ClientCert.vala` — `pair` and the registration reply

**Why:** The phone’s existing method takes the PIN and the CSR. It runs only after §3 has let the call through, which is while a PIN is set. A match signs the CSR with the on-disk CA, stores the new cert approved, and returns that cert, the CA certificate, and the listen-choice addresses. A mismatch toasts and writes no row. HTTPS can no longer register.

**Where:** `rpc_register` signature list, then `request_registration`. `pair` is a new method after `request_registration`.

**Depends on:** §1.

#### Remove — the one-string registration call, and `pending_cert`.

```vala
				"request_registration", "s",
				"pending_cert", "",
```

#### Replace with — PIN, CSR PEM, and the device string. No `pending_cert`.

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
		private static extern int gnutls_x509_crt_set_crq(
			GnuTLS.X509.Certificate crt,
			GnuTLS.X509.CertificateRequest request
		);

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
			if (pin != this.app.ssl_listen.pin) {
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
			if (gnutls_x509_crt_set_crq(crt, crq) < 0 || crt.set_version(3) < 0) {
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
		 * Empty ''pin'' means the handshake requires a client
		 * certificate. Unix socket only.
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

#### Remove — `pending_cert`. Nothing lists a pending row.

```vala
		/**
		 * Newest pending client cert for the preferences banner.
		 *
		 * @param request inbound RPC (local Unix / bin)
		 */
		public void pending_cert(OLLMrpc.Request request)
		{
			var q = ClientCert.query(this.app.project_manager.db);
			var rows = new Gee.ArrayList<ClientCert>();
			var int_binds = new Gee.HashMap<string, int>();
			int_binds["status"] = 0;
			q.selectWhere("WHERE status = $status ORDER BY created DESC LIMIT 1", int_binds, null, rows);
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows.size > 0 ? rows.get(0) : new ClientCert()),
				msg = "ok"
			});
		}
```

#### Remove — `client_cert` documents accept, reject, and ban.

```vala
		 * ''action'': ''accept'' / ''reject'' / ''ban'' / ''remove''.
		 * Retval ''true'' on success, ''false'' if not found / unknown action.
```

#### Replace with — `remove` is the only action. It deletes an approved row.

```vala
		 * ''action'' is ''remove''. Retval ''true'' when that approved
		 * row was deleted, ''false'' otherwise.
```

#### Remove — the `accept`, `reject`, and `ban` arms. `remove` and `default` stay.

```vala
				case "accept":
					var accept_rows = new Gee.ArrayList<ClientCert>();
					int_binds["id"] = (int) id;
					int_binds["status"] = 0;
					q.selectWhere("WHERE id = $id AND status = $status", int_binds, null, accept_rows);
					if (accept_rows.size == 0) {
						request.reply(new OLLMrpc.Response() {
							retval = OLLMrpc.val("b", false),
							msg = "ok"
						});
						return;
					}
					accept_rows.get(0).status = 1;
					accept_rows.get(0).ip = "";
					q.updateById(accept_rows.get(0));
					request.reply(new OLLMrpc.Response() {
						retval = OLLMrpc.val("b", true),
						msg = "ok"
					});
					return;

				case "reject":
					var reject_rows = new Gee.ArrayList<ClientCert>();
					int_binds["id"] = (int) id;
					int_binds["status"] = 0;
					q.selectWhere("WHERE id = $id AND status = $status", int_binds, null, reject_rows);
					if (reject_rows.size == 0) {
						request.reply(new OLLMrpc.Response() {
							retval = OLLMrpc.val("b", false),
							msg = "ok"
						});
						return;
					}
					var rejected = reject_rows.get(0);
					var reject_now = new GLib.DateTime.now_utc().to_unix();
					rejected.status = -2;
					rejected.created = reject_now;
					q.updateById(rejected);
					var recent_rejects = new Gee.ArrayList<ClientCert>();
					text_binds["ip"] = rejected.ip;
					int_binds["since"] = (int) (reject_now - (30 * 24 * 60 * 60));
					q.selectWhere("WHERE status = -2 AND ip = $ip AND created > $since",
						int_binds, text_binds, recent_rejects);
					if (recent_rejects.size < 3 || rejected.ip == "") {
						request.reply(new OLLMrpc.Response() {
							retval = OLLMrpc.val("b", true),
							msg = "ok"
						});
						return;
					}
					var auto_ban = new Gee.ArrayList<ClientCert>();
					int_binds["status"] = -1;
					q.selectWhere("WHERE status = $status AND ip = $ip", int_binds, text_binds, auto_ban);
					if (auto_ban.size == 0) {
						q.insert(new ClientCert() {
							fingerprint = "ip:" + rejected.ip,
							status = -1,
							ip = rejected.ip,
							created = reject_now
						});
					} else {
						auto_ban.get(0).created = reject_now;
						auto_ban.get(0).fingerprint = "ip:" + rejected.ip;
						q.updateById(auto_ban.get(0));
					}
					if (this.app.https_listen != null
						&& !this.app.https_listen.banned_ips.contains(rejected.ip)) {
						this.app.https_listen.banned_ips.add(rejected.ip);
					}
					if (this.app.ssl_listen != null
						&& !this.app.ssl_listen.banned_ips.contains(rejected.ip)) {
						this.app.ssl_listen.banned_ips.add(rejected.ip);
					}
					GLib.debug("auto-banned IP %s after %d rejects in 30 days",
						rejected.ip, recent_rejects.size);
					request.reply(new OLLMrpc.Response() {
						retval = OLLMrpc.val("b", true),
						msg = "ok"
					});
					return;

				case "ban":
					var ban_rows = new Gee.ArrayList<ClientCert>();
					int_binds["id"] = (int) id;
					int_binds["status"] = 0;
					q.selectWhere("WHERE id = $id AND status = $status", int_binds, null, ban_rows);
					if (ban_rows.size == 0) {
						request.reply(new OLLMrpc.Response() {
							retval = OLLMrpc.val("b", false),
							msg = "ok"
						});
						return;
					}
					ban_rows.get(0).status = -1;
					ban_rows.get(0).fingerprint = "ip:" + ban_rows.get(0).ip;
					ban_rows.get(0).created = new GLib.DateTime.now_utc().to_unix();
					q.updateById(ban_rows.get(0));
					if (this.app.https_listen != null && ban_rows.get(0).ip != ""
						&& !this.app.https_listen.banned_ips.contains(ban_rows.get(0).ip)) {
						this.app.https_listen.banned_ips.add(ban_rows.get(0).ip);
					}
					if (this.app.ssl_listen != null && ban_rows.get(0).ip != ""
						&& !this.app.ssl_listen.banned_ips.contains(ban_rows.get(0).ip)) {
						this.app.ssl_listen.banned_ips.add(ban_rows.get(0).ip);
					}
					request.reply(new OLLMrpc.Response() {
						retval = OLLMrpc.val("b", true),
						msg = "ok"
					});
					return;
```

### ✔️ 3. `ollmfilesd/SslConnection.vala` — `pair` is local admin

**Why:** An unknown client never reaches this method when the PIN is empty. §1 fails that handshake inside TLS. `request_registration` stays allowed on a connection that was accepted while the window was open. `pair` is local admin, same as `client_cert`. `pending_cert` is gone.

**Where:** `allow_request`, the local-admin switch. The `request_registration` allow stays a plain `return true`.

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

#### Replace with — `pair` stays on the Unix socket. `pending_cert` is not a method. `request_registration` is unchanged: the handshake already refused strangers.

```vala
			switch (request.method) {
				case "ClientCert.client_cert":
				case "ClientCert.pair":
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

### ✔️ 4. `ollmfilesd/Https.vala` — HTTPS does not register

**Why:** Pairing is the TLS bin socket. HTTPS does not register, and it does not keep `pending_cert`.

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

#### Replace with — `pair` and registration stay off HTTPS. `pending_cert` is not a method.

```vala
			switch (request.method) {
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

### ✔️ 5. `ollmapp/SettingsDialog/PairingDialog.vala` — hand the PIN to the daemon

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

### ✔️ 6. `ollmapp/SettingsDialog/MainDialog.vala` — `event.pair`, no pending banner

**Why:** `event.client_cert` and `RegistrationBanner` exist for the pending calls. Those calls are deleted. This socket hears `event.pair` instead.

**Where:** `ConnectionsPage.pairing_dialog` is public. Then the banner field and its construct, then the `registration_wired` block in `show_dialog`.

**Depends on:** §5. The listener calls `PairingDialog` directly, so `ConnectionsPage.pairing_dialog` is not private.

#### Remove — `ConnectionsPage`, the private dialog field.

```vala
		private PairingDialog pairing_dialog;
```

#### Replace with — the settings dialog can toast or close it.

```vala
		public PairingDialog pairing_dialog;
```

#### Remove — the banner field.

```vala
		private RegistrationBanner registration_banner;
```

#### Remove — construct, the two lines that create the banner and prepend it.

```vala
			this.registration_banner = new RegistrationBanner(this);
			this.action_bar_area.prepend(this.registration_banner);
```

#### Remove — `show_dialog` refreshes the pending banner.

```vala
			if (this.parent.project_manager != null && !this.registration_wired) {
				this.registration_wired = true;
				this.parent.project_manager.notification.connect((notif) => {
					if (notif.method == "event.client_cert") {
						this.registration_banner.refresh.begin();
					}
				});
			}
			this.registration_banner.refresh.begin();
```

#### Replace with — one `event.pair` listener. `registration_wired` stays so `show_dialog` does not connect twice.

```vala
			if (this.parent.project_manager != null && !this.registration_wired) {
				this.registration_wired = true;
				this.parent.project_manager.notification.connect((notif) => {
					if (notif.method != "event.pair") {
						return;
					}
					if (notif.action == "rejected") {
						this.connections_page.pairing_dialog.rejected();
						return;
					}
					if (notif.action == "done") {
						this.connections_page.pairing_dialog.finish();
					}
				});
			}
```

### ✔️ 7. Pending banner and the old phone call

**Why:** `RegistrationBanner` only calls `pending_cert` and `client_cert` accept / reject / ban. `Window` shows a banner for `event.client_cert`. `FileConnectionAdd` posts the one-string HTTPS `request_registration`. None of those calls remain.

**Where:** delete `ollmapp/SettingsDialog/RegistrationBanner.vala`. Drop its source line in `ollmapp/meson.build` and `docs/meson.build`. `Window.notification` and `FileConnectionAdd`.

**Depends on:** §2, §6.

#### Remove — `ollmapp/meson.build`

```vala
  'SettingsDialog/RegistrationBanner.vala',
```

#### Remove — `docs/meson.build`

```vala
    '../ollmapp/SettingsDialog/RegistrationBanner.vala',
```

#### Remove — `ollmapp/Window.vala`, the pending-device banner.

```vala
				if (notif.method == "event.client_cert") {
					this.banner_queue.add("Pending device registration — open Settings → Connections");
					if (this.tool_error_banner.revealed) {
						return;
					}
					this.tool_error_banner.title = this.banner_queue.get(0);
					this.tool_error_banner.revealed = true;
					return;
				}
```

#### Remove — `FileConnectionAdd.request`, from the spinner through `force_close`. That body only exists to post the old call. Phase 4 replaces this handler. After the URL check, the method returns.

```vala
			this.request_button.sensitive = false;
			this.spinner.spinning = true;
			this.spinner.visible = true;
			this.can_close = false;

			var tls = new OLLMrpc.Transport.Cert() {
				dir = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(), "ollmchat"),
				cert_pem = "client.pem",
				key_pem = "client-key.pem",
				cn = "ollmchat-device",
				product_ca_resource = true,
			};
			tls.ensure();
			var http = new OLLMrpc.Transport.HttpClient(url) {
				bin_body = true,
				tls_certificate = tls.certificate,
				tls_database = tls.trust
			};
			var os = GLib.Environment.get_os_info("PRETTY_NAME");
			var requester = (os != null && os != "") ? os : "unknown OS";
			GLib.debug("file connection request url=%s", url);
			var finished = false;
			var timeout_id = GLib.Timeout.add_seconds(15, () => {
				if (finished) {
					return false;
				}
				finished = true;
				this.request_button.sensitive = true;
				this.spinner.spinning = false;
				this.spinner.visible = false;
				GLib.debug("file connection request timed out");
				this.error_occurred("Could not connect: timed out");
				return false;
			});
			try {
				yield http.call(new OLLMrpc.Request() {
					method = "ClientCert.request_registration",
					args = OLLMrpc.args("s", requester)
				});
			} catch (GLib.Error e) {
				if (finished) {
					return;
				}
				finished = true;
				if (timeout_id != 0) {
					GLib.Source.remove(timeout_id);
				}
				this.request_button.sensitive = true;
				this.spinner.spinning = false;
				this.spinner.visible = false;
				GLib.debug("file connection request failed: %s", e.message);
				this.error_occurred("Could not connect: " + e.message);
				return;
			}
			if (finished) {
				return;
			}
			finished = true;
			if (timeout_id != 0) {
				GLib.Source.remove(timeout_id);
			}
			this.can_close = true;
			GLib.debug("file connection request ok");
			this.registered_url = url;
			this.request_button.sensitive = true;
			this.spinner.spinning = false;
			this.spinner.visible = false;
			this.force_close();
```

---

## LLM notes

- **ℹ️** The pasted draft said `register_client`. The phone method stays `ClientCert.request_registration`, with the new arguments. `pending_cert`, accept / reject / ban, and `event.client_cert` are deleted, not left as a second path.
- **ℹ️** Nginx WAN registration in `docs/filesd-behind-nginx-proxy.md` is the exposure this plan removes. Update that doc in the same change as the listener gate, not as a drive-by.
