# 8.2.3.5 — HTTPS server (TLS listen + private cert)

**Status:** **PROPOSED** — draft for review; implement after user approval

> **Do not update `docs/plans/RPC-1.0-summary.md` for this plan.**

**Parent:** [`RPC-8.2.3-http-server-rpc.md`](RPC-8.2.3-http-server-rpc.md) — Phase 4 HTTPS

**Depends on:** Phase 1 `HttpServer` ✔️; peer client [`RPC-8.2.3.6-https-client.md`](RPC-8.2.3.6-https-client.md)

**Related:** Parent Phases 5–6; [`RPC-8.2-full-rpc-system.md`](RPC-8.2-full-rpc-system.md) Phase 7

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Purpose

- **🔷** `⏳` TLS on `Soup.Server` for the real target: **Android client → Linux filesystem server**.
- **🔷** `⏳` **Product CA** (our PKI): clients trust one shipped CA PEM; servers mint **CA-signed** leaves — no Let’s Encrypt, no hand PEM copy per phone.
- **🔷** `⏳` **`new Transport.Cert(dir, ca_pem, ca_key)`** loads or mints the server leaf.
- **🔷** `⏳` Same RPC paths over **`https://`**.
- **🔷** `⏳` Plain HTTP when `tls_certificate` is null (existing smokes unchanged).
- **ℹ️** Phase 4 = encrypted transport + product CA trust. Not mTLS client certs (Phase 6), not RPC login (Phase 5).

---

## Trust model

- **🔷** Trust is **product PKI**, not the public Web PKI.
- **🔷** **`ollmrpc-ca.pem`** (CA **public**) — ship with **every** client (Android assets / Linux data). This is what `HttpClient.tls_database` trusts.
- **🔷** **`ollmrpc-ca-key.pem`** (CA **private**) — ship only with **Linux server** (and smoke fixtures). Used to sign leaves. **Not** in the Android APK.
- **🔷** On disk under server `dir`: `server.pem` + `server-key.pem` (**leaf** signed by product CA).
- **🔷** `Cert.trust_pem_path` = **`ca_pem_path`** (product CA), never the leaf.
- **🔷** Generation uses **GnuTLS library** APIs — no subprocess / openssl CLI.
- **ℹ️** Anyone with the CA private key can mint TLS identities Android will trust. Committing the key in-repo is intentional: TLS here is mainly **confidentiality for RPC/conversations**, not access control. **Phase 5** application auth (and later client certs) is the real gate.
- **🚫** Let’s Encrypt / ACME / public CA.
- **🚫** Shelling out to `openssl`.
- **🚫** Expecting users to copy `server.pem` onto the phone for normal use.
- **🚫** Self-signed leaf as the client trust anchor (breaks multi-device).

---

## Design

### Named APIs

- **🔷** `new OLLMrpc.Transport.Cert(string dir, string ca_pem_path, string ca_key_path)` — load or mint leaf (throws `GLib.Error`).
- **🔷** `Cert.certificate` — leaf `GLib.TlsCertificate` for `HttpServer.tls_certificate`.
- **🔷** `Cert.trust_pem_path` — product **CA** PEM path (for `TlsFileDatabase`).
- **🔷** `Cert.dir` — leaf directory.
- **🔷** `HttpServer.tls_certificate` — non-null → HTTPS listen.
- **🔷** Existing `start` / `stop` / `port` / `rpc_path`.

### `HttpServer` (Linux)

- **🔷** App: `var c = new Cert(tls_dir, ca_pem, ca_key); http.tls_certificate = c.certificate; http.start();`
- **🔷** Null cert → plain HTTP.
- **🔷** `TlsAuthenticationMode` stays default (no client cert required).

### Android client

- **🔷** Does **not** need `Cert` or the CA private key.
- **🔷** Bundles `ollmrpc-ca.pem` → `HttpClient.tls_database = TlsFileDatabase.@new(ca_pem_path)`.
- **🔷** Connects to `https://<linux-host>:<port>/…` (same JSON/bin/session as HTTP).

### Leaf identity (Phase 4 smoke)

- **🔷** CN `ollmrpc`; SAN DNS `localhost` + IP `127.0.0.1` (smoke uses `https://127.0.0.1`).
- **ℹ️** Configurable SAN for LAN hostnames/IPs — backlog if needed before device E2E.

### Out of scope

- **🚫** Public CA / Let’s Encrypt.
- **🚫** Client certificate issue (Phase 6).
- **🚫** RPC `Auth.*` (Phase 5).
- **🚫** TLS on `TcpListen` (**8.2.7**).
- **🚫** Extra public methods on `Cert` (constructor + properties only).
- **🚫** Pairing UX to push leaf PEMs to the phone (product CA replaces that).

---

## Suggested implement order

1. **Phase 0** — product CA PEMs + `Transport/Cert.vala` + meson.
2. **Phase 1** — `HttpServer.tls_certificate` + HTTPS listen.
3. **Phase 2** — smoke with **8.2.3.6**.

---

## Phase 0 — Product CA + `Transport.Cert` — **⏳**

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 0. `libocrpc/data/` — product CA PEMs (once)

**Why:** Fixed product CA so Android can trust any leaf the Linux server mints.

**Where:** new files under `libocrpc/data/`.

**ℹ️** Implementer generates **once** (GnuTLS or openssl), then commits:

- `ollmrpc-ca.pem` — CA certificate (public)
- `ollmrpc-ca-key.pem` — CA private key (server/smoke only)

Example openssl one-liner (generation only; runtime still uses GnuTLS library):

```bash
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -subj '/CN=OLLMrpc Product CA' \
  -keyout libocrpc/data/ollmrpc-ca-key.pem \
  -out libocrpc/data/ollmrpc-ca.pem
```

**🚫** Do not put `ollmrpc-ca-key.pem` in the Android APK assets.

### 1. `libocrpc/Transport/Cert.vala` — new file

**Why:** Load-or-mint CA-signed server leaf for HTTPS RPC.

**Where:** new file under `libocrpc/Transport/`.

#### Add — full file

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
	 * Server leaf TLS identity for HTTPS RPC (product CA, not public Web PKI).
	 *
	 * Files under {@link dir}: ''server.pem'' / ''server-key.pem'' (leaf).
	 * {@link trust_pem_path} is the product CA PEM path clients put in
	 * {@link GLib.TlsFileDatabase} — Android ships that CA; it never needs
	 * this class or the CA private key.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var cert = new OLLMrpc.Transport.Cert(tls_dir, ca_pem, ca_key);
	 * http.tls_certificate = cert.certificate;
	 * var db = GLib.TlsFileDatabase.@new(cert.trust_pem_path);
	 * }}}
	 */
	public class Cert : GLib.Object
	{
		public string dir { get; construct; }

		public GLib.TlsCertificate certificate { get; private set; }

		/** Product CA PEM path (what clients trust). */
		public string trust_pem_path { get; private set; default = ""; }

		/**
		 * Load existing leaf PEMs under {@link dir}, or mint a leaf signed
		 * by the product CA and load them.
		 *
		 * @param dir directory for ''server.pem'' / ''server-key.pem''
		 * @param ca_pem_path product CA certificate PEM
		 * @param ca_key_path product CA private key PEM (server-only)
		 * @throws GLib.Error mkdir, GnuTLS, or PEM load failure
		 */
		public Cert(string dir, string ca_pem_path, string ca_key_path) throws GLib.Error
		{
			GLib.Object(dir: dir);
			this.trust_pem_path = ca_pem_path;
			var cert_path = GLib.Path.build_filename(dir, "server.pem");
			var key_path = GLib.Path.build_filename(dir, "server-key.pem");
			if (!GLib.FileUtils.test(dir, GLib.FileTest.IS_DIR)) {
				if (GLib.DirUtils.create_with_parents(dir, 0700) != 0) {
					throw new GLib.IOError.FAILED("mkdir %s failed", dir);
				}
			}
			if (GLib.FileUtils.test(cert_path, GLib.FileTest.EXISTS)
				&& GLib.FileUtils.test(key_path, GLib.FileTest.EXISTS)) {
				this.certificate = new GLib.TlsCertificate.from_files(
					cert_path, key_path);
				return;
			}
			var init_ret = GnuTLS.global_init();
			if (init_ret < 0) {
				throw new GLib.IOError.FAILED(
					"gnutls_global_init: %s",
					((GnuTLS.ErrorCode)init_ret).to_string());
			}
			string ca_pem_text;
			string ca_key_text;
			GLib.FileUtils.get_contents(ca_pem_path, out ca_pem_text);
			GLib.FileUtils.get_contents(ca_key_path, out ca_key_text);
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
				throw new GLib.IOError.FAILED(
					"ca import: %s",
					((GnuTLS.ErrorCode)ca_imp).to_string());
			}
			var ca_key = GnuTLS.X509.PrivateKey.create();
			var ca_key_imp = ca_key.import(
				ref ca_key_datum, GnuTLS.X509.CertificateFormat.PEM);
			if (ca_key_imp < 0) {
				throw new GLib.IOError.FAILED(
					"ca key import: %s",
					((GnuTLS.ErrorCode)ca_key_imp).to_string());
			}
			var key = GnuTLS.X509.PrivateKey.create();
			var gen_ret = key.generate(GnuTLS.PKAlgorithm.RSA, 2048);
			if (gen_ret < 0) {
				throw new GLib.IOError.FAILED(
					"privkey_generate: %s",
					((GnuTLS.ErrorCode)gen_ret).to_string());
			}
			var crt = GnuTLS.X509.Certificate.create();
			var cn = "ollmrpc";
			var dn_ret = crt.set_dn_by_oid(
				GnuTLS.OID_X520_COMMON_NAME, 0, cn, cn.length);
			if (dn_ret < 0) {
				throw new GLib.IOError.FAILED(
					"set_dn_by_oid: %s",
					((GnuTLS.ErrorCode)dn_ret).to_string());
			}
			var ver_ret = crt.set_version(3);
			if (ver_ret < 0) {
				throw new GLib.IOError.FAILED(
					"set_version: %s",
					((GnuTLS.ErrorCode)ver_ret).to_string());
			}
			var serial = new uint8[16];
			for (var i = 0; i < serial.length; i++) {
				serial[i] = (uint8)GLib.Random.int_range(0, 256);
			}
			var ser_ret = crt.set_serial(serial, serial.length);
			if (ser_ret < 0) {
				throw new GLib.IOError.FAILED(
					"set_serial: %s",
					((GnuTLS.ErrorCode)ser_ret).to_string());
			}
			var now = (time_t)(GLib.get_real_time() / 1000000);
			crt.set_activation_time(now);
			crt.set_expiration_time(now + (time_t)(3650 * 24 * 60 * 60));
			var san_dns = crt.set_subject_alternative_name(
				GnuTLS.X509.SubjectAltName.DNSNAME, "localhost");
			if (san_dns < 0) {
				throw new GLib.IOError.FAILED(
					"SAN DNS: %s",
					((GnuTLS.ErrorCode)san_dns).to_string());
			}
			var san_ip = crt.set_subject_alternative_name(
				GnuTLS.X509.SubjectAltName.IPADDRESS, "127.0.0.1");
			if (san_ip < 0) {
				throw new GLib.IOError.FAILED(
					"SAN IP: %s",
					((GnuTLS.ErrorCode)san_ip).to_string());
			}
			var key_ret = crt.set_key(key);
			if (key_ret < 0) {
				throw new GLib.IOError.FAILED(
					"set_key: %s",
					((GnuTLS.ErrorCode)key_ret).to_string());
			}
			var sign_ret = crt.sign2(
				ca_crt, ca_key, GnuTLS.DigestAlgorithm.SHA256, 0);
			if (sign_ret < 0) {
				throw new GLib.IOError.FAILED(
					"sign2: %s",
					((GnuTLS.ErrorCode)sign_ret).to_string());
			}
			size_t key_pem_len = 0;
			key.export(GnuTLS.X509.CertificateFormat.PEM, null, ref key_pem_len);
			var key_pem = new uint8[key_pem_len];
			var key_exp = key.export(
				GnuTLS.X509.CertificateFormat.PEM, key_pem, ref key_pem_len);
			if (key_exp < 0) {
				throw new GLib.IOError.FAILED(
					"privkey_export: %s",
					((GnuTLS.ErrorCode)key_exp).to_string());
			}
			size_t crt_pem_len = 0;
			crt.export(GnuTLS.X509.CertificateFormat.PEM, null, ref crt_pem_len);
			var crt_pem = new uint8[crt_pem_len];
			var crt_exp = crt.export(
				GnuTLS.X509.CertificateFormat.PEM, crt_pem, ref crt_pem_len);
			if (crt_exp < 0) {
				throw new GLib.IOError.FAILED(
					"crt_export: %s",
					((GnuTLS.ErrorCode)crt_exp).to_string());
			}
			GLib.FileUtils.set_contents(key_path, (string)key_pem);
			GLib.FileUtils.set_contents(cert_path, (string)crt_pem);
			this.certificate = new GLib.TlsCertificate.from_files(
				cert_path, key_path);
		}
	}
}
```

### 2. `libocrpc/meson.build` — source, GnuTLS, install CA public

**Where (source):** inside `ocrpc_core_src` after `'Transport/HttpClient.vala',`.

#### Add

```meson
  'Transport/Cert.vala',
```

**Where (dep):** after `dependency('libsoup-3.0'),` in `ocrpc_deps`.

#### Add

```meson
  dependency('gnutls'),
```

**Where (vapi pkg):** after `'--pkg', 'libsoup-3.0',` in `ocrpc_vapi_pkgs` (and the matching `add_project_arguments` pkg list if present).

#### Add

```meson
  '--pkg', 'gnutls',
```

**Where (install):** end of `libocrpc/meson.build`.

#### Add

```meson
install_data(
  'data/ollmrpc-ca.pem',
  install_dir: get_option('datadir') / 'ollmrpc',
)
# Server packages / smoke also need data/ollmrpc-ca-key.pem on disk;
# do not install the key into Android APK assets.
```

---

## Phase 1 — `HttpServer` HTTPS listen — **⏳**

### 3. `libocrpc/Transport/HttpServer.vala` — property

**Where:** after `rpc_path` property (before `private Soup.Server soup`).

#### Add

```vala
		/**
		 * Server TLS identity. Non-null → {@link start} listens with
		 * {@link Soup.ServerListenOptions.HTTPS}.
		 *
		 * Typical: ''new Cert(dir, ca_pem, ca_key)'' then assign {@link Cert.certificate}.
		 */
		public GLib.TlsCertificate? tls_certificate { get; set; default = null; }
```

### 4. `libocrpc/Transport/HttpServer.vala` — `start()` listen

**Where:** replace the `try { this.soup.listen_local(this.port, 0); } catch …` block inside `start()`.

#### Remove

```vala
			try {
				this.soup.listen_local(this.port, 0);
			} catch (GLib.Error e) {
				GLib.warning("failed to start HTTP server on port %u: %s",
					this.port, e.message);
				return false;
			}
```

#### Replace with

```vala
			try {
				var opts = (Soup.ServerListenOptions) 0;
				if (this.tls_certificate != null) {
					this.soup.set_tls_certificate(this.tls_certificate);
					opts = Soup.ServerListenOptions.HTTPS;
				}
				this.soup.listen_local(this.port, opts);
			} catch (GLib.Error e) {
				GLib.warning("failed to start HTTP server on port %u: %s",
					this.port, e.message);
				return false;
			}
```

### 5. `libocrpc/Transport/HttpServer.vala` — class docblock example

**Where:** `== Example ==` block at top of class.

#### Remove

```vala
	 * {{{
	 * var http = new OLLMrpc.Transport.HttpServer(8080);
	 * http.start();
	 * }}}
```

#### Replace with

```vala
	 * {{{
	 * var http = new OLLMrpc.Transport.HttpServer(8080);
	 * var cert = new OLLMrpc.Transport.Cert(tls_dir, ca_pem, ca_key);
	 * http.tls_certificate = cert.certificate;
	 * http.start();
	 * }}}
```

---

## Phase 2 — Smoke — **⏳**

Shared executable with **8.2.3.6** — full test body lives in that plan’s Phase 1 (uses `new Cert(dir, ca_pem, ca_key)` + client `TlsFileDatabase` on **CA** PEM). Meson target name: `test-rpc-http-https`.

---

## Backlog

- **🔷** `⏳` Implement Phases 0–2 with **8.2.3.6**.
- **🔷** `⏳` Wire `ollmrpc-ca.pem` into Android assets (alongside existing public CA bundle in [`docs/android-tls.md`](../android-tls.md) — **separate** trust DB for RPC vs Ollama HTTPS).
- **🔷** `⏳` Configurable leaf SAN for LAN IP/hostname (device E2E).
- **🔷** `⏳` Phase 5 — application auth over HTTPS.
- **🔷** `⏳` Phase 6 — issue client certs from the same product CA.
- **🚫** Let’s Encrypt / public CA.

---

## LLM notes

- **🚫** Do not implement until user approves.
- **ℹ️** GLib/`GTlsCertificate` only **loads** PEMs — minting is GnuTLS (`gnutls` pkg + `--pkg gnutls`).
- **ℹ️** Generate and commit `libocrpc/data/ollmrpc-ca.pem` + `ollmrpc-ca-key.pem` once before coding.
- **🚫** Do not spawn `openssl` at runtime; do not put the CA private key in the Android APK.
- **ℹ️** After implement, mark **✔️**; user promotes **✅**.
