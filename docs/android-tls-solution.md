# Android TLS solution (GTK / GIO / libsoup)

Guide for HTTPS on GTK Android: what we fixed, where code belongs long-term, and how to ship it in an APK.

**Status:** 2026-06-17 — **TLS backend fixed and closed** for chat POC (`GTlsBackendOpenssl`, remote HTTPS works). Bundled CA trust store for arbitrary hosts (e.g. harness `GET https://roojs.com/`) is **optional follow-up**, not blocking boot/chat work.

**Related:** [`docs/android-port-status.md`](android-port-status.md) (current focus), [`docs/bugs/done/2026-06-17-FIXED-android-runtime-tls-ime-paste.md`](bugs/done/2026-06-17-FIXED-android-runtime-tls-ime-paste.md) (closed bug), [`docs/android-build.md`](android-build.md) (build commands).

---

## Problem in one sentence

On Android, a GTK app using libsoup/GIO needs (1) a **real TLS backend** (`libgioopenssl.so` registered before dummy is cached) and (2) a **trusted CA bundle** (Android has no desktop `/etc/ssl/certs/` for native code).

---

## Two layers (both required for HTTPS)

| Layer | Symptom if broken | Fix |
|-------|-------------------|-----|
| **TLS backend** | `GDummyTlsBackend`, “TLS support is not available” | Ship `libgioopenssl.so` in assets; scan after extension points exist; preload `libssl`/`libcrypto` |
| **CA trust store** | `UNKNOWN_CA`, “Unacceptable TLS certificate” | Ship `ca-certificates.crt` in assets; set `SSL_CERT_FILE` (or `GTlsFileDatabase`) at init |

Backend registration is **done** on device (`GTlsBackendOpenssl`). HTTPS failed with **`UNKNOWN_CA`** until the CA bundle ships.

---

## Where each fix should live (not stuck in OLLMchat forever)

```
┌─────────────────────────────────────────┐
│  GLib upstream                          │  ensure-before-scan in giomodule.c
│  (GNOME MR)                             │  (real bug, not Android-only)
├─────────────────────────────────────────┤
│  GTK Android runtime (gdkandroid…)      │  GIO module scan, OpenSSL preload,
│  (GNOME GTK MR / android-bugs.patch)  │  CA trust init alongside XDG paths
├─────────────────────────────────────────┤
│  Pixiewood / build                      │  Stage assets: gio/modules, ssl/certs,
│  (OLLMchat scripts today)               │  icons, openssl, glib-networking
├─────────────────────────────────────────┤
│  App (ollmapp/android-gio-tls.c)        │  Fallback init until GDK owns it all;
│                                         │  shrinks over time
└─────────────────────────────────────────┘
```

| Piece | Staging (build) | Runtime init | Long-term owner |
|-------|-----------------|----------------|-----------------|
| `libgioopenssl.so` | `assets/share/gio/modules/` | GDK + app scan | GTK Android |
| `libssl.so`, `libcrypto.so` | `lib/arm64-v8a/` (jniLibs) | Preload `RTLD_GLOBAL` | GTK Android |
| `ca-certificates.crt` | `assets/share/ssl/certs/` | `SSL_CERT_FILE` → extracted path | GTK Android (app fallback today) |
| GLib scan order | `tls-ensure-before-scan.patch` | — | **GLib upstream** |

**Pixiewood** packages files; it does not run TLS logic. **OLLMchat** `android/pixiewood-wraps/` pins deps (openssl, glib-networking, glib patch, gtk patch).

---

## APK layout (runtime)

After GTK extracts assets to `filesDir/share/`:

| Asset in APK | Runtime path |
|--------------|----------------|
| `assets/share/gio/modules/libgioopenssl.so` | `files/share/gio/modules/libgioopenssl.so` |
| `assets/share/ssl/certs/ca-certificates.crt` | `files/share/ssl/certs/ca-certificates.crt` |
| `lib/arm64-v8a/libssl.so`, `libcrypto.so` | Same (legacy jni packaging) |

GDK sets `g_set_user_dirs()` → `g_get_system_data_dirs()[0]` ≈ `files/share`.

---

## Startup sequence

1. **Java / GDK** — extract assets, set XDG data dirs, preload OpenSSL, set `GIO_MODULE_DIR`, scan GIO modules.
2. **App `main()`** — `ollmapp_configure_android_gio_tls_modules()`:
   - Set `SSL_CERT_FILE` to `$XDG_DATA/share/ssl/certs/ca-certificates.crt` if present
   - Confirm backend is not dummy; rescan if needed
3. **libsoup** — `Soup.Session` HTTPS uses OpenSSL backend + CA file.

---

## Build (harness or full app)

```bash
# GTK fixes harness (TLS probe)
scripts/android/build-gtk-fixes-poc-apk.sh
./scripts/android/adb-install-gtk-fixes-poc.sh

# Full OLLMchat chat POC (same TLS init + CA bundle)
scripts/android/build-chat-poc-apk.sh
```

Build host needs **`ca-certificates`** (Debian: `apt install ca-certificates`). The build copies `/etc/ssl/certs/ca-certificates.crt` into APK assets.

Verify:

```bash
scripts/android/verify-gtk-fixes-apk.sh   # harness
scripts/android/verify-apk.sh             # chat POC
```

Both check for `assets/share/ssl/certs/ca-certificates.crt`.

---

## Device test

1. Cold start → logcat: `GTlsBackendOpenssl`, `ready=true`
2. Tap **GET https://roojs.com/** → **HTTPS 200 OK**
3. Logcat: `OLLMchat TLS trust: SSL_CERT_FILE=.../files/share/ssl/certs/ca-certificates.crt`, no `UNKNOWN_CA`

```bash
./scripts/android/adb-gtk-fixes-logcat.sh --no-restart
```

---

## Patches and wraps (OLLMchat tree)

| Item | Path |
|------|------|
| GLib ensure-before-scan | `subprojects/packagefiles/glib/tls-ensure-before-scan.patch` |
| GLib pin | `android/pixiewood-wraps/glib/glib.wrap` @ 2.84.0 |
| GTK Android fixes | `gdk/android/gdkandroidgio.c`, `gdk/android/gdkandroidruntime.c` (branch `android-tls` @ `~/git/gtk`) |
| App TLS init | `ollmapp/android/android-gio-tls.c` |
| Harness | `ollmapp/android/AndroidGtkFixesPoc.vala` |
| Asset staging | `scripts/android/build-pixiewood-apk.sh` (`install_*_to_assets`) |

Regression: `scripts/android/regression/test-r13-glib-tls-ensure-before-scan.sh`

---

## Upstream contribution checklist (tomorrow+)

- [x] GLib MR: ensure extension points before module scan — [!5212](https://gitlab.gnome.org/GNOME/glib/-/merge_requests/5212)
- [ ] GTK MR: TLS module init in `gdkandroidruntime.c` (CA trust may follow separately)
- [ ] Document Android HTTPS requirements for GTK Android porters
- [ ] Optional: Pixiewood example manifest with `<openssl/>`, `<glib-networking/>`, CA asset note

---

## Dead ends (do not repeat)

- Do not put `libssl.so` / `libcrypto.so` under `assets/share/gio/modules/`
- Do not scan GIO modules before `_g_io_modules_ensure_extension_points_registered()`
- Do not call `g_tls_backend_get_default()` before a successful module scan
- Do not assume `example.com` or desktop CA paths work on Android without bundling
