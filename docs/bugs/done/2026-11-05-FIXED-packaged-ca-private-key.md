# Packaged CA private key

**Status:** ✔️ fixed and verified by automated tests

## Problem

- 🔴 `libocrpc` embedded `ollmrpc-ca-key.pem` in its GResource.
- 🔴 Clean servers extracted the same CA private key and certificate.
- 🔴 Anyone with an application package could mint certificates trusted by
  affected installations.

## Evidence and root cause

- ✔️ Commit `d2b6080d` added the private key to the GResource.
- ✔️ Release tags `v1.4.0` through `v1.4.4` contain that commit.
- ✔️ The packaged private key matches the bundled CA certificate.
- ✔️ PIN pairing required a generated per-server CA, but that certificate
  migration had not been implemented.

## Fix

- ✔️ Deleted the packaged CA certificate, private key, and GResource.
- ✔️ Removed the GResource from `libocrpc/meson.build`.
- ✔️ Each server now generates a CA with a critical `CA:TRUE` constraint.
- ✔️ Server CA files use `server-ca.pem` and `server-ca-key.pem`.
- ✔️ Server code never reads the legacy `ollmrpc-ca.pem` or
  `ollmrpc-ca-key.pem` paths.
- ✔️ When the renamed CA pair is absent, the old server leaf is removed and
  regenerated from the installation CA.
- ✔️ The generated CA private key is set to mode `0600`.
- ✔️ Pairing returns only the public CA certificate to clients.
- ✔️ Desktop GnuTLS and Android OpenSSL certificate generation expose the
  same CA behavior.

## Verification

- ✔️ `ninja -C build`
- ✔️ `ninja -C build docs/valadoc`
- ✔️ `test-rpc-http-https`
- ✔️ `test-rpc-filesd-pair-flow`
- ✔️ Two clean installations generated different CA certificates.
- ✔️ Reinitialization preserved an existing generated CA.
- ✔️ A server certificate from one installation failed verification against
  another installation's CA.
- ✔️ Built libraries and applications contain no private key or bundled
  product CA.
- ℹ️ The full RPC suite retains unrelated failures in `test-rpc-t1`,
  `test-rpc-t2`, and `test-rpc-gi`.

## Related design

- ℹ️ `docs/plans/RPC-1.11-URGENT-vpn-local-pin-pairing.md`
- ℹ️ `docs/plans/RPC-1.11.1-pin-registration-and-android.md`
