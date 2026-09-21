# Android `libocrpc` configure fails: GnuTLS with no wrap

**Status:** ✔️ applied; APK rebuild in progress

**Started:** 2026-09-21

**Reporter:** Alan

**Component:** `libocrpc/meson.build`, `libocrpc/Transport/Cert.vala`

**Process:** Follow **`docs/bug-fix-process.md`**.

**Related:**

- ℹ️ [`RPC-8.2.8.2-DONE-filesd-android-file-connection.md`](../plans/done/RPC-8.2.8.2-DONE-filesd-android-file-connection.md) §9 required GnuTLS on Android
- ℹ️ `android/pixiewood-extra.cross` sets `gnutls = 'disabled'` for glib-networking
- ℹ️ Pixiewood deps already include `<openssl/>`

---

## Problem

🔷 `scripts/android/build-chat-poc-apk.sh` dies at Meson configure:

```text
Run-time dependency gnutls found: NO
libocrpc/meson.build:44:14: ERROR: Dependency lookup for gnutls ... failed
```

🔷 Expected: Android APK configure using the existing OpenSSL wrap.

---

## Root cause

✔️ `libocrpc/meson.build` always does `dependency('gnutls')` for `Transport.Cert` mint.

✔️ There is no GnuTLS Pixiewood wrap (Nettle/GMP). Android TLS is OpenSSL.

🚫 Install host `libgnutls28-dev` — that is not an Android cross pkg-config.

🚫 Add a GnuTLS wrap for this install — product TLS on device is already OpenSSL.

---

## Proposed fix

🔷 Skip GnuTLS on Android. Link the OpenSSL wrap and mint PEMs with a C helper compiled only on that host.

#### Replace — `libocrpc/meson.build` GnuTLS block

```meson
# GnuTLS: Transport.Cert (server leaf + device client ensure).
ocrpc_deps += dependency('gnutls')
ocrpc_vapi_pkgs += '--pkg=gnutls'
ocrpc_vapi_gen_pkgs += ['--pkg', 'gnutls']
```

#### Replace with

```meson
# GnuTLS mints Transport.Cert on desktop. Android has no GnuTLS wrap;
# pixiewood already builds OpenSSL (glib-networking backend).
if is_android
  ocrpc_deps += dependency('openssl')
else
  ocrpc_deps += dependency('gnutls')
  ocrpc_vapi_pkgs += '--pkg=gnutls'
  ocrpc_vapi_gen_pkgs += ['--pkg', 'gnutls']
endif
```

#### Add — `libocrpc/android/cert-openssl.c` + `libocrpc/android/cert-openssl.h`

OpenSSL mint of key+cert PEM (self-signed or CA-signed, optional DNS SAN `localhost`).

#### Add — `libocrpc/meson.build` library sources

C file on the `library()` sources only (not the Vala vapi `custom_target` input).

#### Add — `libocrpc/Transport/Cert.vala` `#if ANDROID` in `create_pem_files`

Call `ocrpc_cert_create_pem_files` then `GLib.TlsCertificate.from_files`.

---

## Attempts / changelog

- ✔️ 2026-09-21 — configure evidence from Pixiewood Meson log
- ✔️ 2026-09-21 — meson picks `android/Cert.vala` vs `Transport/Cert.vala` (no `#if`)

## Next

- ⏳ 🔷 APK configure past `libocrpc`; install on phone
