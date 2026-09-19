# 8.2.8.2 — Client file connection + unlock Agent Pi

**Status:** **PROPOSED** — Phase 1 code proposals ready for review · Phase 2 split out to [`RPC-8.2.8.4`](RPC-8.2.8.4-filesd-remote-rpc-client.md) + [`RPC-8.2.8.5`](RPC-8.2.8.5-filesd-remote-takeover-connections-tab.md)

> **Do not update** `docs/plans/RPC-1.0-summary.md` **for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](RPC-8.2.8-filesd-connections-ui.md)

**Depends on:**

- Phase 1 of parent (**✔️** agent-done) — `RPC-ClientCert.request_registration` + gateroute
- [`RPC-8.2.8.1-filesd-desktop-connections-ui.md`](RPC-8.2.8.1-filesd-desktop-connections-ui.md) — desktop Accept so the client can leave pending

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

**Scope note:** filename still says *android* for link stability; this plan covers **Android and Linux desktop** (Linux is useful for testing).

---

## Purpose

- **🔷** Connections tab: **Add file connection** — dialog with **HTTPS URL** only (`https://host:port` or public nginx front). Row title = **hostname** parsed from URL.
- **🔷** **Add file connection** button is **hidden** when `filesd_client.url` is already set (one connection only).
- **🔷** Dialog button is **Request** (not Verify): mint/load device client cert, TLS to remote URL, `RPC-ClientCert.request_registration(requester)`, then persist config.
- **🔷** On Request success: park `approved = false` (shows **Requested**), close dialog, persist config, show one **file-connection row**. Dialog fields reset on close.
- **🔷** **One** remote file-server URL at a time (single config object, single row — not a list). Add or Remove only — no edit.
- **🔷** Row is `FileConnectionRow` — expandable, **Remove**, **Check** (Phase 2), **Enabled** switch (`enabled` bool).
- **🔷** Registration state is **`approved` bool** (config JSON — not the server DB). `false` → **Requested**; `true` → **Active** (desktop accepted). Server keeps int `status` in SQLite.
- **🔷** **`enabled` bool** — user has turned the connection on or off (Linux: overrides local Unix when on).
- **🔷** After desktop Accept (`approved`) and `enabled`: use file RPC over HTTPS; **unlock Agent Pi**.
- **🔷** **Linux desktop** as well as Android — when configured, `enabled`, and `approved`, remote **takes over** local Unix `ollmfilesd`. When `enabled` is false, local Unix wins.
- **🔷** Two implementation phases (implement in order):
  1. **Phase 1 — UI + registration request** — config, dialog, row, Connections tab, client-cert mint/load, `request_registration` on Request (Check stub).
  2. **Phase 2 — Live connection + Agent Pi** — split into [`RPC-8.2.8.4`](RPC-8.2.8.4-filesd-remote-rpc-client.md) (libocrpc / libocfiles) and [`RPC-8.2.8.5`](RPC-8.2.8.5-filesd-remote-takeover-connections-tab.md) (takeover, Check, live toggle, Agent Pi).
- **🚫** Code Assistant, Skill Runner, OC Coder agents — out of scope for this plan (Agent Pi only).
- **🚫** Reusing `Settings.Connection` as the file-server URL without a type discriminant.
- **ℹ️** Operator nginx doc: [`docs/filesd-behind-nginx-proxy.md`](../filesd-behind-nginx-proxy.md).
- **ℹ️** Desktop pending banner + approved incoming-client rows live in [`8.2.8.1`](RPC-8.2.8.1-filesd-desktop-connections-ui.md) — this plan is the **outbound client** side.

---

## Current behaviour

- **ℹ️** Connections tab reuses `ConnectionAdd` / `ConnectionRow` for LLM API connections only; no file-server outbound connection.
- **ℹ️** Desktop also shows **approved incoming** client rows (`ApprovedClientRow`) — unrelated to this outbound row.
- **ℹ️** Android `OLLMfiles.ProjectManager` is a stub; desktop boots local Unix `ollmfilesd` and registers Code Assistant / Agent Pi / Skill Runner after `ProjectManager` connects.
- **ℹ️** `OLLMrpc.Client` HTTP path exists; `Transport.HttpClient.tls_certificate` is ready — client-cert mint/load not wired on the outbound client path.
- **ℹ️** `libocfiles.ProjectManager` hard-wires Unix sock under `~/.local/share/ollmchat` — needs construct-time HTTPS socket path + client cert on the HTTP transport for remote mode.
- **ℹ️** Product CA trust on Android already has TLS helpers (`AndroidConnectionTls` / config TLS) for LLM HTTPS — file-server CA trust must use the **product CA** PEM, not the device trust store alone.

---

## Resolved design (was open questions)

1. **🔷** **One** file-server URL only — single `Config2` nested object, single row; **no Add button** when configured.
2. **🔷** **Agent Pi only** unlocks when `approved` and `enabled`. Chatter stays always; other agents unchanged.
3. **🔷** **Linux + Android** — same UI and config; `enabled` controls whether remote overrides local Unix `ollmfilesd`.
4. **🔷** Row title = URL **hostname** (`GLib.Uri.parse`); **requester** on `request_registration` = `PRETTY_NAME`, else `"unknown OS"`.

---

## Phase 1 — UI + registration request

### Goal

- **🔷** `⏳` New `OLLMchat.Settings.FilesdClient` on `Config2` (JSON key `filesd_client`).
- **🔷** `⏳` Refactor `OLLMrpc.Transport.Cert` (libocrpc) — GObject construct properties (`dir`, PEM basenames, `cn`, CA paths, …) + `ensure()` / `ensure_trust()` (no static TLS API).
- **🔷** `⏳` `FileConnectionAdd` — construct with `Config2`; **Request** = cert + HTTPS `request_registration(requester)` + write `config.filesd_client` + `config.save()`; no `show_add`; URL field resets on `closed`.
- **🔷** `⏳` `FileConnectionRow` — hostname title, exposed **Check** button (wired from `render_file_connection`, not a signal), **Enabled** switch, Remove.
- **🔷** `⏳` `ConnectionsPage` — inline `present()` on Add button; Check handler inline in `render_file_connection` (`GLib.critical` stub until Phase 2).

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `libollmchat/Settings/FilesdClient.vala` — new config object

**Why:** dedicated outbound file-server settings — not mixed into `Settings.Connection`.
**Where:** new file; add to `libollmchat/meson.build` before `Config2.vala`.
**Depends on:** none.

#### Add

```vala
namespace OLLMchat.Settings
{
	/**
	 * Outbound remote file-server connection (client side).
	 *
	 * JSON key ''filesd_client'' on {@link Config2}. At most one row in the
	 * Connections tab; empty ''url'' means not configured.
	 */
	public class FilesdClient : Object, Json.Serializable
	{
		/**
		 * Remote ''ollmfilesd'' HTTPS base URL (e.g. ''https://host:8443'').
		 */
		public string url { get; set; default = ""; }

		/**
		 * Desktop has accepted registration (Check sets true in Phase 2).
		 * UI: false → ''Requested'', true → ''Active''.
		 */
		public bool approved { get; set; default = false; }

		/**
		 * When false, Phase 2 must not connect / must not override local Unix.
		 */
		public bool enabled { get; set; default = true; }

		public FilesdClient()
		{
		}

		public unowned ParamSpec? find_property(string name)
		{
			return this.get_class().find_property(name);
		}

		public new void Json.Serializable.set_property(ParamSpec pspec, Value value)
		{
			base.set_property(pspec.get_name(), value);
		}

		public new Value Json.Serializable.get_property(ParamSpec pspec)
		{
			var val = Value(pspec.value_type);
			base.get_property(pspec.get_name(), ref val);
			return val;
		}

		public override Json.Node serialize_property(
			string property_name, Value value, ParamSpec pspec)
		{
			return default_serialize_property(property_name, value, pspec);
		}

		public override bool deserialize_property(
			string property_name, out Value value, ParamSpec pspec,
			Json.Node property_node)
		{
			return default_deserialize_property(
				property_name, out value, pspec, property_node);
		}
	}
}
```

### 2. `libollmchat/Settings/Config2.vala` — `filesd_client` property

**Why:** persist the single outbound file connection.
**Where:** after the `filesd` property.
**Depends on:** §1.

#### Add — after `public Filesd filesd { get; set; default = new Filesd(); }`

```vala
		/**
		 * Outbound remote file-server connection (client side).
		 */
		public FilesdClient filesd_client {
			get; set; default = new FilesdClient();
		}
```

### 3. `libollmchat/meson.build` — source list

**Why:** compile `FilesdClient` before `Config2`.
**Where:** `ollmchat_ollama_src` list, before `Settings/Config2.vala`.
**Depends on:** §1.

#### Add — immediately before `'Settings/Config2.vala',`

```python
  'Settings/FilesdClient.vala',  # Before Config2 (Config2.filesd_client)
```

### 4. `libocrpc/Transport/Cert.vala` — construct properties + `ensure()` / `ensure_trust()`

**Why:** one instance-oriented TLS class — configure paths / names / CN via GObject construct properties, then call `ensure()` to load or mint the leaf. Server (CA-signed) and device client (self-signed per **8.2.7**) are the same type with different property values. No static `load_*` / `product_ca_*` API.
**Where:** refactor existing `libocrpc/Transport/Cert.vala`; meson in §9 (build on all platforms).
**Depends on:** `HttpClient.tls_certificate` / `tls_database`, GResource `/ollmrpc/ollmrpc-ca.pem`.

ℹ️ **Remove** the three-argument throwing constructor (`Cert(dir, ca_pem, ca_key)`). Call sites construct with object initializers and call `ensure()`.

#### Replace — class body (from docblock through closing `}` of class)

```vala
	/**
	 * TLS leaf identity and product-CA trust for HTTPS RPC.
	 *
	 * Configure with construct properties, then {@link ensure} (leaf) and/or
	 * {@link ensure_trust} (client trust store). Signing: when
	 * {@link ca_pem_path} and {@link ca_key_path} are set, the leaf is
	 * CA-signed; otherwise self-signed.
	 *
	 * == Example ==
	 *
	 * {{{
	 * // server (ollmfilesd)
	 * var server = new OLLMrpc.Transport.Cert() {
	 *     dir = tls_dir,
	 *     ca_pem_path = ca_pem,
	 *     ca_key_path = ca_key,
	 *     server_san = true,
	 * };
	 * server.ensure();
	 * http.tls_certificate = server.certificate;
	 *
	 * // device client (ollmapp)
	 * var data_dir = GLib.Path.build_filename(
	 *     GLib.Environment.get_user_data_dir(), "ollmchat");
	 * var leaf = new OLLMrpc.Transport.Cert() {
	 *     dir = data_dir,
	 *     cert_pem = "client.pem",
	 *     key_pem = "client-key.pem",
	 *     cn = "ollmchat-device",
	 * };
	 * leaf.ensure();
	 * var http = new OLLMrpc.Transport.HttpClient(url) {
	 *     bin_body = true,
	 *     tls_certificate = leaf.certificate,
	 *     tls_database = leaf.ensure_trust()
	 * };
	 * }}}
	 */
	public class Cert : GLib.Object
	{
		/** Directory for leaf PEMs and optional trust PEM. */
		public string dir { get; construct; }

		/** Leaf certificate PEM basename under {@link dir}. */
		public string cert_pem { get; construct default = "server.pem"; }

		/** Leaf private key PEM basename under {@link dir}. */
		public string key_pem { get; construct default = "server-key.pem"; }

		/** X.509 common name (DN 2.5.4.3). */
		public string cn { get; construct default = "ollmrpc"; }

		/** Add localhost DNS + 127.0.0.1 SAN (server leaf). */
		public bool server_san { get; construct default = false; }

		/**
		 * Product CA certificate PEM path for CA-signed leaves.
		 * Empty with empty {@link ca_key_path} → self-signed leaf.
		 */
		public string ca_pem_path { get; construct default = ""; }

		/** Product CA private key PEM (server host only). */
		public string ca_key_path { get; construct default = ""; }

		/**
		 * Trust PEM basename under {@link dir} for {@link ensure_trust}.
		 * Default ''ollmrpc-ca.pem''.
		 */
		public string trust_pem { get; construct default = "ollmrpc-ca.pem"; }

		/**
		 * When true, {@link ensure_trust} extracts
		 * ''/ollmrpc/ollmrpc-ca.pem'' from GResource if the trust file is
		 * missing ({@link OLLMfilesd.Https.listen} pattern).
		 */
		public bool product_ca_resource { get; construct default = false; }

		/** Loaded/minted leaf after {@link ensure}. */
		public GLib.TlsCertificate certificate { get; private set; }

		/**
		 * Full path to the product CA PEM clients trust.
		 * Set by {@link ensure} ({@link ca_pem_path}) or {@link ensure_trust}.
		 */
		public string trust_pem_path { get; private set; default = ""; }

		/**
		 * Load existing leaf PEMs under {@link dir}, or mint, sign, persist.
		 *
		 * @throws GLib.Error mkdir, GnuTLS, or PEM I/O failure
		 */
		public void ensure() throws GLib.Error
		{
			if (!GLib.FileUtils.test(this.dir, GLib.FileTest.IS_DIR)) {
				if (GLib.DirUtils.create_with_parents(this.dir, 0700) != 0) {
					throw new GLib.IOError.FAILED("mkdir %s failed", this.dir);
				}
			}
			var cert_path = GLib.Path.build_filename(
				this.dir, this.cert_pem);
			var key_path = GLib.Path.build_filename(
				this.dir, this.key_pem);
			if (GLib.FileUtils.test(cert_path, GLib.FileTest.EXISTS)
				&& GLib.FileUtils.test(key_path, GLib.FileTest.EXISTS)) {
				this.certificate = new GLib.TlsCertificate.from_files(
					cert_path, key_path);
				if (this.ca_pem_path != "") {
					this.trust_pem_path = this.ca_pem_path;
				}
				return;
			}
			var init_ret = GnuTLS.global_init();
			if (init_ret < 0) {
				throw new GLib.IOError.FAILED("gnutls_global_init: %s",
					((GnuTLS.ErrorCode)init_ret).to_string());
			}
			var key = GnuTLS.X509.PrivateKey.create();
			var gen_ret = key.generate(GnuTLS.PKAlgorithm.RSA, 2048);
			if (gen_ret < 0) {
				throw new GLib.IOError.FAILED("privkey_generate: %s",
					((GnuTLS.ErrorCode)gen_ret).to_string());
			}
			var crt = GnuTLS.X509.Certificate.create();
			var dn_ret = crt.set_dn_by_oid(
				"2.5.4.3", 0, this.cn, this.cn.length);
			if (dn_ret < 0) {
				throw new GLib.IOError.FAILED("set_dn_by_oid: %s",
					((GnuTLS.ErrorCode)dn_ret).to_string());
			}
			var ver_ret = crt.set_version(3);
			if (ver_ret < 0) {
				throw new GLib.IOError.FAILED("set_version: %s",
					((GnuTLS.ErrorCode)ver_ret).to_string());
			}
			var serial = new uint8[16];
			for (var i = 0; i < serial.length; i++) {
				serial[i] = (uint8)GLib.Random.int_range(0, 256);
			}
			var ser_ret = crt.set_serial(serial, serial.length);
			if (ser_ret < 0) {
				throw new GLib.IOError.FAILED("set_serial: %s",
					((GnuTLS.ErrorCode)ser_ret).to_string());
			}
			var now = (time_t)(GLib.get_real_time() / 1000000);
			crt.set_activation_time(now);
			crt.set_expiration_time(now + (time_t)(3650 * 24 * 60 * 60));
			if (this.server_san) {
				/* GNUTLS_SAN_DNSNAME=1, GNUTLS_SAN_IPADDRESS=4 (vapi enum lacks cprefix). */
				var san_dns = crt.set_subject_alternative_name(
					(GnuTLS.X509.SubjectAltName)1, "localhost");
				if (san_dns < 0) {
					throw new GLib.IOError.FAILED("SAN DNS: %s",
						((GnuTLS.ErrorCode)san_dns).to_string());
				}
				var san_ip = crt.set_subject_alternative_name(
					(GnuTLS.X509.SubjectAltName)4, "\x7f\x00\x00\x01");
				if (san_ip < 0) {
					throw new GLib.IOError.FAILED("SAN IP: %s",
						((GnuTLS.ErrorCode)san_ip).to_string());
				}
			}
			var key_ret = crt.set_key(key);
			if (key_ret < 0) {
				throw new GLib.IOError.FAILED("set_key: %s",
					((GnuTLS.ErrorCode)key_ret).to_string());
			}
			if (this.ca_pem_path != "" && this.ca_key_path != "") {
				var ca_pem_text = "";
				var ca_key_text = "";
				GLib.FileUtils.get_contents(
					this.ca_pem_path, out ca_pem_text);
				GLib.FileUtils.get_contents(
					this.ca_key_path, out ca_key_text);
				var ca_pem_datum = GnuTLS.Datum() {
					data = ca_pem_text,
					size = ca_pem_text.length
				};
				var ca_key_datum = GnuTLS.Datum() {
					data = ca_key_text,
					size = ca_key_text.length
				};
				var ca_crt = GnuTLS.X509.Certificate.create();
				var ca_imp = ca_crt.import(
					ref ca_pem_datum, GnuTLS.X509.CertificateFormat.PEM);
				if (ca_imp < 0) {
					throw new GLib.IOError.FAILED("ca import: %s",
						((GnuTLS.ErrorCode)ca_imp).to_string());
				}
				var ca_key = GnuTLS.X509.PrivateKey.create();
				var ca_key_imp = ca_key.import(
					ref ca_key_datum, GnuTLS.X509.CertificateFormat.PEM);
				if (ca_key_imp < 0) {
					throw new GLib.IOError.FAILED("ca key import: %s",
						((GnuTLS.ErrorCode)ca_key_imp).to_string());
				}
				var sign_ret = crt.sign2(
					ca_crt, ca_key, GnuTLS.DigestAlgorithm.SHA256, 0);
				if (sign_ret < 0) {
					throw new GLib.IOError.FAILED("sign2: %s",
						((GnuTLS.ErrorCode)sign_ret).to_string());
				}
				this.trust_pem_path = this.ca_pem_path;
			} else {
				var sign_ret = crt.sign2(
					crt, key, GnuTLS.DigestAlgorithm.SHA256, 0);
				if (sign_ret < 0) {
					throw new GLib.IOError.FAILED("sign2: %s",
						((GnuTLS.ErrorCode)sign_ret).to_string());
				}
			}
			var key_pem_len = (size_t)0;
			key.export(GnuTLS.X509.CertificateFormat.PEM, null, ref key_pem_len);
			var key_pem = new uint8[key_pem_len];
			var key_exp = key.export(
				GnuTLS.X509.CertificateFormat.PEM, key_pem, ref key_pem_len);
			if (key_exp < 0) {
				throw new GLib.IOError.FAILED("privkey_export: %s",
					((GnuTLS.ErrorCode)key_exp).to_string());
			}
			var crt_pem_len = (size_t)0;
			crt.export(GnuTLS.X509.CertificateFormat.PEM, null, ref crt_pem_len);
			var crt_pem = new uint8[crt_pem_len];
			var crt_exp = crt.export(
				GnuTLS.X509.CertificateFormat.PEM, crt_pem, ref crt_pem_len);
			if (crt_exp < 0) {
				throw new GLib.IOError.FAILED("crt_export: %s",
					((GnuTLS.ErrorCode)crt_exp).to_string());
			}
			GLib.FileUtils.set_contents(key_path, (string)key_pem);
			GLib.FileUtils.set_contents(cert_path, (string)crt_pem);
			this.certificate = new GLib.TlsCertificate.from_files(
				cert_path, key_path);
		}

		/**
		 * Product CA trust store for {@link HttpClient.tls_database}.
		 *
		 * @return {@link GLib.TlsFileDatabase} for {@link trust_pem} under
		 *     {@link dir}
		 * @throws GLib.Error mkdir or PEM extract failure
		 */
		public GLib.TlsDatabase ensure_trust() throws GLib.Error
		{
			if (!GLib.FileUtils.test(this.dir, GLib.FileTest.IS_DIR)) {
				if (GLib.DirUtils.create_with_parents(this.dir, 0700) != 0) {
					throw new GLib.IOError.FAILED("mkdir %s failed", this.dir);
				}
			}
			this.trust_pem_path = GLib.Path.build_filename(
				this.dir, this.trust_pem);
			if (!GLib.FileUtils.test(
					this.trust_pem_path, GLib.FileTest.EXISTS)) {
				if (!this.product_ca_resource) {
					throw new GLib.IOError.NOT_FOUND(
						"missing trust PEM %s", this.trust_pem_path);
				}
				GLib.FileUtils.set_contents(this.trust_pem_path,
					(string) GLib.resources_lookup_data(
						"/ollmrpc/ollmrpc-ca.pem",
						GLib.ResourceLookupFlags.NONE).get_data());
			}
			return new GLib.TlsFileDatabase(this.trust_pem_path);
		}
	}
```

#### Replace — existing call sites (same Phase 1 PR as §4)

`ollmfilesd/Https.vala` (~line 98):

```vala
			var server_cert = new OLLMrpc.Transport.Cert() {
				dir = tls_dir,
				ca_pem_path = ca_pem,
				ca_key_path = ca_key,
				server_san = true,
			};
			server_cert.ensure();
			this.tls_certificate = server_cert.certificate;
```

`tests/rpc/http-https-test.vala` (~line 56):

```vala
			var cert = new OLLMrpc.Transport.Cert() {
				dir = tls_dir,
				ca_pem_path = ca_pem,
				ca_key_path = ca_key,
				server_san = true,
			};
			cert.ensure();
```

`libocrpc/Transport/HttpServer.vala` docblock example (~line 30): update to the `new Cert() { … }; cert.ensure();` pattern.

**🚫** Do not add `DeviceCert.vala`. **🚫** No static leaf/trust loaders on `Cert`.

### 5. `ollmapp/SettingsDialog/FileConnectionAdd.vala` — add dialog

**Why:** collect HTTPS URL; **Request** mints/loads client cert, calls `request_registration`, then fills `config.filesd_client` and saves.
**Where:** new file under `ollmapp/SettingsDialog/`.
**Depends on:** §1–§2, §4 (`Cert` construct + `ensure()` / `ensure_trust()`). **Requester** = `PRETTY_NAME` or `"unknown OS"` in `request()` (not libocrpc).

ℹ️ Unlike `ConnectionAdd` (staging `verified_connection`), this dialog owns `Config2` and writes `filesd_client` on successful Request. Uses `OLLMrpc.Transport.HttpClient` (`bin_body = true`, product CA + client cert) — same transport as `ollmfilesd` HTTPS gate.

#### Add

```vala
namespace OLLMapp.SettingsDialog
{
	/**
	 * Dialog for adding the single outbound file-server connection.
	 */
	public class FileConnectionAdd : Adw.PreferencesDialog
	{
		public OLLMchat.Settings.Config2 config { get; construct; }

		private Gtk.Entry url_entry;
		private Gtk.Button request_button;
		private Gtk.Spinner spinner;
		private Gtk.Box button_box;
		private Adw.PreferencesGroup group;

		public signal void error_occurred(string error_message);
		public signal void dialog_closed();

		public FileConnectionAdd(OLLMchat.Settings.Config2 config)
		{
			Object(config: config);
			this.title = "Add file connection";
			this.set_content_height(360);
			this.set_content_width(720);

			var page = new Adw.PreferencesPage();
			this.group = new Adw.PreferencesGroup() {
				description = "Connect to a remote OLLMchat file server over HTTPS. "
					+ "The desktop must Accept the registration request."
			};

			this.url_entry = new Gtk.Entry() {
				placeholder_text = "https://host:8443",
				width_request = 280,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			var url_suffix = new Gtk.Box(Gtk.Orientation.VERTICAL, 4) {
				halign = Gtk.Align.END
			};
			url_suffix.append(this.url_entry);
			url_suffix.append(new Gtk.Label(
				"HTTPS URL of the remote file server"
			) {
				wrap = true,
				wrap_mode = Pango.WrapMode.WORD,
				xalign = 1.0f,
				justify = Gtk.Justification.RIGHT,
				css_classes = {"dim-label"},
				max_width_chars = 40
			});
			var url_row = new Adw.ActionRow() {
				title = "URL"
			};
			url_row.add_suffix(url_suffix);
			this.group.add(url_row);

			page.add(this.group);

			this.button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
			this.spinner = new Gtk.Spinner() {
				spinning = false,
				visible = false
			};
			this.button_box.append(this.spinner);
			this.button_box.append(new Gtk.Label("Request"));
			this.request_button = new Gtk.Button() {
				child = this.button_box,
				css_classes = {"suggested-action"},
				sensitive = false
			};
			var footer = new Adw.PreferencesGroup();
			footer.add(this.request_button);
			page.add(footer);
			this.add(page);

			this.url_entry.changed.connect(() => {
				this.request_button.sensitive = this.url_entry.text.strip() != "";
			});
			this.request_button.clicked.connect(() => {
				this.request.begin();
			});
			this.closed.connect(() => {
				this.url_entry.text = "";
				this.request_button.sensitive = false;
				this.spinner.spinning = false;
				this.spinner.visible = false;
				this.dialog_closed();
			});
		}

		private async void request()
		{
			var url = this.url_entry.text.strip();
			if (url == "") {
				this.error_occurred("URL is required");
				return;
			}
			if (!url.has_prefix("https://")) {
				this.error_occurred("URL must start with https://");
				return;
			}

			this.request_button.sensitive = false;
			this.spinner.spinning = true;
			this.spinner.visible = true;

			try {
				var data_dir = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(), "ollmchat");
				var tls = new OLLMrpc.Transport.Cert() {
					dir = data_dir,
					cert_pem = "client.pem",
					key_pem = "client-key.pem",
					cn = "ollmchat-device",
					product_ca_resource = true,
				};
				tls.ensure();
				var http = new OLLMrpc.Transport.HttpClient(url) {
					bin_body = true,
					tls_certificate = tls.certificate,
					tls_database = tls.ensure_trust()
				};
				var os = GLib.Environment.get_os_info("PRETTY_NAME");
				var requester = (os != null && os != "") ? os : "unknown OS";
				yield http.call(new OLLMrpc.Request() {
					method = "RPC-ClientCert.request_registration",
					args = OLLMrpc.args("s", requester)
				});
			} catch (GLib.Error e) {
				this.request_button.sensitive = true;
				this.spinner.spinning = false;
				this.spinner.visible = false;
				this.error_occurred("Request failed: " + e.message);
				return;
			}

			this.config.filesd_client.url = url;
			this.config.filesd_client.approved = false;
			this.config.filesd_client.enabled = true;
			this.config.save();
			this.force_close();
		}
	}
}
```

ℹ️ `OLLMapp.ClientCert.rpc_register()` must run before the call (already in `Application` startup). Request failure leaves config unchanged (no partial URL write). **Requester** = `PRETTY_NAME` or `"unknown OS"` — good enough for banner/approved titles; no `Build.MODEL` / platform `#if`.

### 6. `ollmapp/SettingsDialog/FileConnectionRow.vala` — typed expander row

**Why:** single outbound row — hostname title, status subtitle, URL detail, Check / Enabled / Remove.
**Where:** new file under `ollmapp/SettingsDialog/`.
**Depends on:** §1.

ℹ️ Row exposes `check_button`; `ConnectionsPage.render_file_connection` wires `clicked` (no signal on the row). Check is `sensitive = false` until Phase 2.

#### Add

```vala
namespace OLLMapp.SettingsDialog
{
	/**
	 * Widget group for the single outbound file-server connection row.
	 */
	public class FileConnectionRow : Object
	{
		public signal void remove_requested();
		public signal void enabled_changed(bool enabled);

		public Adw.ExpanderRow expander { get; private set; }
		public Gtk.Button check_button { get; private set; }

		public FileConnectionRow(OLLMchat.Settings.FilesdClient client)
		{
			var subtitle = client.approved ? "Active" : "Requested";
			var title = client.url;
			try {
				title = GLib.Uri.parse(client.url, GLib.UriFlags.NONE).get_host();
			} catch (GLib.UriError e) {
			}
			this.expander = new Adw.ExpanderRow() {
				title = title,
				subtitle = subtitle,
				can_focus = false,
				focus_on_click = false
			};

			var url_row = new Adw.ActionRow() {
				title = "URL"
			};
			url_row.add_suffix(new Gtk.Label(client.url) {
				xalign = 1,
				selectable = true,
				ellipsize = Pango.EllipsizeMode.MIDDLE
			});
			this.expander.add_row(url_row);

			var status_row = new Adw.ActionRow() {
				title = "Status"
			};
			status_row.add_suffix(new Gtk.Label(subtitle) {
				xalign = 1
			});
			this.expander.add_row(status_row);

			var enabled_switch = new Gtk.Switch() {
				active = client.enabled,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			var enabled_row = new Adw.ActionRow() {
				title = "Enabled"
			};
			enabled_row.add_suffix(enabled_switch);
			enabled_switch.notify["active"].connect(() => {
				this.enabled_changed(enabled_switch.active);
			});
			this.expander.add_row(enabled_row);

			this.check_button = new Gtk.Button.with_label("Check") {
				sensitive = false,
				tooltip_text = "Check whether the desktop has approved this device (Phase 2)"
			};
			var check_row = new Adw.ActionRow() {
				title = "Registration"
			};
			check_row.add_suffix(this.check_button);
			this.expander.add_row(check_row);

			var remove_button = new Gtk.Button.with_label("Remove") {
				css_classes = {"destructive-action"}
			};
			remove_button.clicked.connect(() => {
				this.remove_requested();
			});
			var button_row = new Adw.ActionRow();
			button_row.add_suffix(remove_button);
			this.expander.add_row(button_row);
		}
	}
}
```

### 7. `ollmapp/SettingsDialog/ConnectionsPage.vala` — wire button, dialog, row

**Why:** **Add file connection** only when none configured; render one row between LLM connections and approved incoming clients.
**Where:** fields, constructor, new methods, constructor tail call order.
**Depends on:** §5–§6.

#### Add — fields (after `private ConnectionAdd add_dialog;`)

```vala
		private Gtk.Button add_file_btn;
		private FileConnectionAdd add_file_dialog;
		private FileConnectionRow? file_connection_row;
```

#### Add — constructor, after `this.add_btn.clicked.connect(this.add_connection);`

```vala
			this.add_file_btn = new Gtk.Button.with_label("Add file connection");
			this.add_file_btn.clicked.connect(() => {
				this.add_file_dialog.present(this.dialog);
			});
			this.action_widget.append(this.add_file_btn);
```

#### Add — constructor, after `this.add_dialog.dialog_closed.connect(this.on_add_closed);`

```vala
			this.add_file_dialog = new FileConnectionAdd(this.dialog.app.config);
			this.add_file_dialog.dialog_closed.connect(() => {
				this.render_file_connection();
			});
```

#### Replace — constructor tail

```vala
			// Initial render of connections
			this.render_connections();
			this.render_approved.begin();
```

#### Replace with

```vala
			this.render_connections();
			this.render_file_connection();
			this.render_approved.begin();
```

#### Add — new methods (before `apply_config()`)

```vala
		private void render_file_connection()
		{
			this.add_file_btn.visible =
				this.dialog.app.config.filesd_client.url.strip() == "";
			if (this.file_connection_row != null) {
				this.file_connection_row.expander.unparent();
				this.file_connection_row = null;
			}
			var client = this.dialog.app.config.filesd_client;
			if (client.url.strip() == "") {
				return;
			}
			this.file_connection_row = new FileConnectionRow(client);
			this.file_connection_row.remove_requested.connect(() => {
				this.dialog.app.config.filesd_client =
					new OLLMchat.Settings.FilesdClient();
				this.render_file_connection();
				this.dialog.app.config.save();
			});
			this.file_connection_row.check_button.clicked.connect(() => {
				GLib.critical("file connection check not implemented");
			});
			this.file_connection_row.enabled_changed.connect((enabled) => {
				this.dialog.app.config.filesd_client.enabled = enabled;
				this.dialog.app.config.save();
			});
			Adw.ExpanderRow? insert_after = null;
			foreach (var row in this.rows.values) {
				insert_after = row.expander;
			}
			if (insert_after != null) {
				this.boxed_list.insert_child_after(
					insert_after, this.file_connection_row.expander);
				return;
			}
			if (this.approved_rows.size > 0) {
				this.boxed_list.insert_child_after(
					null, this.file_connection_row.expander);
				return;
			}
			this.boxed_list.append(this.file_connection_row.expander);
		}
```

ℹ️ Add button calls `present()` inline — no `add_file_connection` method. Check stub lives in `render_file_connection` (`GLib.critical` until Phase 2 replaces that lambda body). Request writes `config.filesd_client` inside the dialog; `dialog_closed` re-renders the row.

### 8. `ollmapp/meson.build` — source list

**Why:** compile new SettingsDialog sources.
**Where:** desktop sources block (and android block if duplicated — same paths).
**Depends on:** §5–§6.

#### Add — after `'SettingsDialog/ConnectionRow.vala',`

```python
  'SettingsDialog/FileConnectionAdd.vala',
  'SettingsDialog/FileConnectionRow.vala',
```

ℹ️ If your tree has a second copy of the SettingsDialog list (android section ~line 112), add the same two lines there too.

### 9. `libocrpc/meson.build` — `Cert` on all platforms + GnuTLS on Android

**Why:** §4 refactors {@link Cert} for device `ensure()` (self-signed client mint on Android/Linux). GnuTLS and `Cert.vala` must build on every platform — not only desktop server hosts.
**Where:** GnuTLS dependency block (~line 43) and `ocrpc_core_src` list (~line 91–118).
**Depends on:** §4.

#### Replace — GnuTLS block

```python
# Product-CA leaf mint (Transport.Cert) needs GnuTLS. Android clients only
# trust the CA PEM from GResource — no mint, no GnuTLS wrap in pixiewood.
if not is_android
  ocrpc_deps += dependency('gnutls')
  ocrpc_vapi_pkgs += '--pkg=gnutls'
  ocrpc_vapi_gen_pkgs += ['--pkg', 'gnutls']
endif
```

#### Replace with

```python
# GnuTLS: Transport.Cert (server leaf + device client ensure).
ocrpc_deps += dependency('gnutls')
ocrpc_vapi_pkgs += '--pkg=gnutls'
ocrpc_vapi_gen_pkgs += ['--pkg', 'gnutls']
```

#### Move — `Transport/Cert.vala` into always-built `ocrpc_core_src`

Add `'Transport/Cert.vala'` to the main `files([...])` list (e.g. after `'Transport/HttpClient.vala'`).

#### Remove — Android gate

```python
if not is_android
  ocrpc_core_src += files(['Transport/Cert.vala'])
endif
```

ℹ️ Android ollmapp configures `Cert` for device leaf + product CA trust; server `ensure()` path is unused on device but harmless to compile.

---

## Phase 2 — Live connection + Agent Pi unlock

**➡️** [`RPC-8.2.8.4-filesd-remote-rpc-client.md`](RPC-8.2.8.4-filesd-remote-rpc-client.md) — `OLLMrpc.Client.http` bridge, `disconnect()` fix, `ProjectManager.replace_rpc` + `notification`.
**➡️** [`RPC-8.2.8.5-filesd-remote-takeover-connections-tab.md`](RPC-8.2.8.5-filesd-remote-takeover-connections-tab.md) — Linux takeover, Check probe, live `enabled` toggle, Agent Pi, Android design.

---

## Suggested order

1. **⏳** Phase 1 — apply §1–§9 (UI + `Cert.ensure()` + `request_registration`)
2. **⏳** Phase 2 — [`8.2.8.4`](RPC-8.2.8.4-filesd-remote-rpc-client.md) then [`8.2.8.5`](RPC-8.2.8.5-filesd-remote-takeover-connections-tab.md)

---

## LLM notes

- **ℹ️** Incoming `ApprovedClientRow` = server-side (desktop hosts); `FileConnectionRow` = client-side outbound.
- **ℹ️** `insert_child_after(null, …)` prepends when there are no LLM rows — file row still sits before approved incoming rows.
- **🚫** Showing **Add file connection** when `filesd_client.url` is already set.
- **🚫** `name` field, int `status` on client config (server DB keeps ints), `show_add`, `requested_filesd_client` staging, `add_file_connection` / `check_file_connection` methods, `check_requested` signal, `refresh()` on the row, TLS helpers under `ollmapp/` (belong in `libocrpc/Transport/Cert`), separate `DeviceCert` class, static `Cert.load_*` / `product_ca_*` methods, three-arg `Cert` constructor.
- **🚫** Multiple file-server URLs / list UI.
- **🚫** Unlocking Code Assistant or OC Coder in this plan.
