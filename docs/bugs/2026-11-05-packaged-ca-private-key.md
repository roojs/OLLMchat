# Packaged CA private key

**Status:** ✔️ fixed and verified by automated tests

## Problem

- 🔴 `libocrpc/data/ollmrpc.gresource.xml` packages
  `ollmrpc-ca-key.pem`.
- 🔴 `ollmfilesd/SslListen.vala` copies that private key from the
  application resource into the server TLS directory.
- 🔴 Every installation therefore starts with the same CA private key.
- 🔴 A private key distributed in an application is public information.
  Filesystem permissions on the extracted copy cannot restore secrecy.

## Impact

- 🔴 Anyone who obtains the application package or source key can mint
  certificates signed by the CA trusted by affected installations.
- 🔴 An attacker can forge a trusted server certificate and impersonate a
  server to clients that trust the packaged CA.
- 🔴 Any authorization that relies only on the certificate chain is broken.
- ℹ️ Fingerprint registration may add a separate application-level check for
  client access, but it does not repair the compromised TLS trust boundary.

## Evidence

- ✔️ Commit `d2b6080d` added `ollmrpc-ca-key.pem` to the GResource on
  2026-09-21.
- ✔️ Release tags `v1.4.0` through `v1.4.4` contain that commit.
- ✔️ The private key matches the bundled CA certificate.
- ✔️ `libocrpc/meson.build` compiles the GResource into `libocrpc.so`.
- ✔️ `SslListen.listen()` extracts both bundled PEMs for a clean server.
- ✔️ The PIN-pairing plan required per-server CA generation on 2026-10-02,
  but its certificate section was not implemented.

## Root cause

- ✔️ The original HTTPS work kept the private key out of the GResource.
- ✔️ The key was later embedded to make server installation automatic.
- ✔️ PIN pairing replaced the shared-CA design, but only the pairing phases
  landed. The separate certificate migration remained open.

## Approved fix

- 🔷 Remove `ollmrpc-ca-key.pem` from
  `libocrpc/data/ollmrpc.gresource.xml` immediately.
- 🔷 Do not install, embed, or otherwise distribute a CA private key.
- 🔷 Generate a new CA key and self-signed CA certificate independently on
  each server installation.
- 🔷 Store the generated private key in the server state directory with mode
  `0600`.
- 🔷 Generate the server leaf certificate from that installation's CA.
- 🔷 Return only the public CA certificate to clients during pairing.

## Existing installations

- 🔷 Generate the installation CA as `server-ca.pem` and
  `server-ca-key.pem`.
- 🔷 Never read the legacy server-side `ollmrpc-ca.pem` or
  `ollmrpc-ca-key.pem` paths.
- 🔷 When the renamed CA pair is absent, replace the server leaf certificate
  at the same time.
- 🔷 Existing clients must pair again because continuing to trust the
  compromised CA is unsafe.

## Proposed code

### 1. `libocrpc/Transport/Cert.vala` — generate CA certificates

**Why:** The existing certificate writer owns key and certificate
generation. A CA needs a critical `CA:TRUE` basic constraint.

**Where:** `Cert` properties and `create_pem_files()`.

**Depends on:** none.

#### Add — declare the GnuTLS CA-constraint API inside `Cert`

```vala
		[CCode (cname = "gnutls_x509_crt_set_basic_constraints",
			cheader_filename = "gnutls/x509.h")]
		private static extern int gnutls_x509_crt_set_basic_constraints(
			GnuTLS.X509.Certificate crt,
			uint ca,
			int pathlen
		);
```

#### Add — expose the generation role after `server_san`

```vala
		/**
		 * Whether a newly generated self-signed certificate is a CA.
		 *
		 * Set only for a server installation's CA certificate.
		 */
		public bool certificate_authority { get; set; default = false; }
```

#### Add — mark a generated CA after setting X.509 version 3

```vala
			if (this.certificate_authority && gnutls_x509_crt_set_basic_constraints(crt, 1, -1) < 0) {
				GLib.error("set_basic_constraints");
			}
```

### 2. Android `Cert` and `cert-openssl.*` — keep API parity

**Why:** `Cert` has one public API on desktop and Android. OpenSSL must honor
the CA role if requested.

**Where:** the OpenSSL binding, property list, and certificate extension
creation.

**Depends on:** §1.

#### Add — expose the same property in Android `Cert`

```vala
		/**
		 * Whether a newly generated self-signed certificate is a CA.
		 *
		 * Set only for a server installation's CA certificate.
		 */
		public bool certificate_authority { get; set; default = false; }
```

#### Replace with — pass the CA role through the existing binding

```vala
				ocrpc_cert_create_pem_files(cert_path, key_path, this.cn,
					this.server_san, this.certificate_authority,
					this.ca_pem_path, this.ca_key_path);
```

#### Add — add `certificate_authority` after `server_san` in C

```c
                                      gboolean certificate_authority,
```

#### Add — create a critical `CA:TRUE` basic-constraints extension

```c
  if (certificate_authority)
    {
      X509_EXTENSION *extension = X509V3_EXT_conf_nid (
          NULL, NULL, NID_basic_constraints, "critical,CA:TRUE");
      if (extension == NULL || X509_add_ext (crt, extension, -1) != 1)
        {
          X509_EXTENSION_free (extension);
          set_openssl_error (error, "set_basic_constraints");
          goto out;
        }
      X509_EXTENSION_free (extension);
    }
```

### 3. `ollmfilesd/SslListen.vala` — initialize renamed CA files

**Why:** Server startup owns the TLS directory. It must remove the known
compromised trust root before loading any certificate. New server-only
filenames make the legacy packaged CA impossible to select.

**Where:** `listen()`, after creating `tls_dir` and before creating the
server leaf.

**Depends on:** §1.

#### Remove

```vala
			var ca_pem = GLib.Path.build_filename(tls_dir, "ollmrpc-ca.pem");
			var ca_key = GLib.Path.build_filename(tls_dir, "ollmrpc-ca-key.pem");
```

#### Replace with

```vala
			var ca_pem = GLib.Path.build_filename(tls_dir, "server-ca.pem");
			var ca_key = GLib.Path.build_filename(tls_dir, "server-ca-key.pem");
			if (!GLib.FileUtils.test(ca_pem, GLib.FileTest.EXISTS) ||
				!GLib.FileUtils.test(ca_key, GLib.FileTest.EXISTS)) {
				GLib.FileUtils.remove(ca_pem);
				GLib.FileUtils.remove(ca_key);
				GLib.FileUtils.remove(GLib.Path.build_filename(tls_dir, "server.pem"));
				GLib.FileUtils.remove(GLib.Path.build_filename(tls_dir, "server-key.pem"));
				GLib.FileUtils.remove(GLib.Path.build_filename(tls_dir, "server.csr"));
			}
			var ca = new OLLMrpc.Transport.Cert() {
				dir = tls_dir,
				cert_pem = "server-ca.pem",
				key_pem = "server-ca-key.pem",
				trust_pem = "server-ca.pem",
				cn = "OLLMrpc Server CA",
				certificate_authority = true,
			};
			ca.ensure();
			if (Posix.chmod(ca_key, 0600) != 0) {
				GLib.error("chmod %s failed", ca_key);
			}
```

### 4. `ollmfilesd/ClientCert.vala` — sign with renamed CA files

**Why:** Pairing must read the installation CA, never the legacy packaged
paths.

**Where:** `request_registration()`, where the CA PEM and key are read.

**Depends on:** §3.

#### Remove

```vala
					GLib.Path.build_filename(tls_dir, "ollmrpc-ca.pem"), out ca_pem);
				GLib.FileUtils.get_contents(
					GLib.Path.build_filename(tls_dir, "ollmrpc-ca-key.pem"), out ca_key_pem);
```

#### Replace with

```vala
					GLib.Path.build_filename(tls_dir, "server-ca.pem"), out ca_pem);
				GLib.FileUtils.get_contents(
					GLib.Path.build_filename(tls_dir, "server-ca-key.pem"), out ca_key_pem);
```

### 5. Build data — remove the packaged CA

- 🔷 Delete `libocrpc/data/ollmrpc-ca.pem`,
  `libocrpc/data/ollmrpc-ca-key.pem`, and
  `libocrpc/data/ollmrpc.gresource.xml`.
- 🔷 Remove `gnome.compile_resources()` and `ocrpc_resources` from
  `libocrpc/meson.build`.

### 6. Regression tests — generated, unique, persistent, and private

- 🔷 `http-https-test` generates its CA through `Cert` instead of source-tree
  PEMs.
- 🔷 `filesd-pair-flow-test` verifies the renamed daemon CA exists and that
  its private key mode is `0600`.
- 🔷 Tests verify repeated initialization preserves a generated CA and two
  clean directories produce different CAs.
- 🔷 Remove the source-tree CA environment variables from
  `tests/meson.build`.

### 7. Certificate API comments — remove the shared-product-CA contract

- 🔷 Update desktop and Android `Cert` comments to describe the configured
  installation CA.
- 🔷 Update `HttpClient.tls_database` to describe the server installation's
  CA instead of a bundled CA.

## Attempts / changelog

- ✔️ 2026-11-05: Confirmed the tracked key, GResource entry, extraction path,
  affected tags, matching key pair, and unfinished PIN-plan requirement.
- ✔️ Removed both packaged PEMs and the GResource from `libocrpc`.
- ✔️ Generated installation CAs use renamed server-only paths and mode
  `0600`.
- ✔️ `ninja -C build`, Valadoc, HTTPS, and filesd pairing tests pass.
- ℹ️ The full RPC suite still has unrelated existing failures in `test-rpc-t1`,
  `test-rpc-t2`, and `test-rpc-gi`; the two tests affected by this change pass
  in the targeted run.

## Verification

- ✔️ The built library and application contain no CA private key.
- ✔️ Two clean server installations generate different CA certificates and
  private keys.
- ✔️ The generated CA private key has mode `0600`.
- ✔️ Restarting a server preserves its generated CA.
- ✔️ An installation using the legacy filenames generates the renamed CA
  and replaces its server leaf on upgrade.
- ✔️ A client paired with one server does not trust a different server's
  certificate.

## Related design

- ℹ️ `docs/plans/RPC-1.11-URGENT-vpn-local-pin-pairing.md` already requires
  removal of the bundled CA and per-server CA generation.
