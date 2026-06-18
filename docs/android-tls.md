# Android TLS (GTK / GIO / libsoup)

How HTTPS works in the OLLMchat Android chat POC (`org.roojs.ollmchat.androidpoc`).

**Status:** Working on arm64 (2026-06-17). Remote Ollama over HTTPS verified on device.

**See also:** [`docs/android-build.md`](android-build.md) (build commands), [`docs/plans/done/9.2-DONE-android-tls-migration.md`](plans/done/9.2-DONE-android-tls-migration.md) (migration notes).

---

## The problem

A GTK app on Android that uses **libsoup** / **GIO** for HTTP needs two things desktop Linux gets for free:

1. A **real TLS backend** — not GIO’s placeholder `GDummyTlsBackend`.
2. A **trusted CA bundle** — Android has no `/etc/ssl/certs/` for native code.

Symptoms when either is missing: `TLS support is not available`, `UNKNOWN_CA`, or failed HTTPS to normal hosts.

---

## What works (current approach)

Follow [gtk-android-builder#20](https://github.com/sp1ritCS/gtk-android-builder/issues/20): **the app** registers TLS, not GDK.

| Layer | What we do |
|-------|------------|
| **TLS backend** | Static **glib-networking** OpenSSL: link `gioopenssl` into the app and call `g_io_openssl_load(NULL)` before any network I/O. |
| **CA trust** | Ship `ca-certificates.crt` in APK assets; set `GTlsFileDatabase` on each `Soup.Session` from the extracted path. |

No `libgioopenssl.so` in assets. No `GIO_MODULE_DIR`. No `g_setenv` for TLS or CA paths.

---

## Startup sequence

1. **GTK / Pixiewood** — extract `assets/share/` to app storage; set XDG data dirs (`g_get_system_data_dirs()[0]` ≈ `files/share`).
2. **App `main()`** — `ollmapp_configure_android_gio_tls_modules()` in `ollmapp/android/android-gio-tls.c`:
   - `g_io_openssl_load(NULL)`
   - confirm `g_tls_backend_get_default()` is `GTlsBackendOpenssl`
3. **Each connection** — `AndroidConnectionTls` applies bundled CA via `GTlsFileDatabase` on the libsoup session.

---

## Key files

| Piece | Location |
|-------|----------|
| TLS init (C) | `ollmapp/android/android-gio-tls.c` |
| Per-session CA (Vala) | `ollmapp/android/AndroidConnectionTls.vala` |
| Static `gioopenssl` link | `ollmapp/meson.build`, `android/pixiewood-extra.cross` (`default_library = 'static'` for glib-networking) |
| CA asset staging | `scripts/android/build-pixiewood-apk.sh` → `assets/share/ssl/certs/ca-certificates.crt` |
| OpenSSL runtimes | `lib/arm64-v8a/libssl.so`, `libcrypto.so` (jniLibs) |

---

## What not to do

These approaches were tried and rightly rejected by gtk-android-builder maintainers: (yeap it's LLM slop - but the tasty stuff)

- Put TLS init in **GDK** (`gdk_android_scan_gio_modules`, `g_setenv("GIO_MODULE_DIR")`) — TLS is the app’s job.
- Ship **`libgioopenssl.so`** under shared APK assets — breaks multi-arch / split APKs; use static load instead.
- Rely on **`g_setenv`** for `SSL_CERT_FILE` or `GIO_MODULE_DIR` after the process is multi-threaded.
- Assume **desktop CA paths** or Android’s system cert store without explicit wiring.

---

## Build and verify

```bash
scripts/android/build-chat-poc-apk.sh
./scripts/android/adb-install-chat-poc.sh
scripts/android/verify-apk.sh
```

**Logcat** (cold start):

```bash
adb logcat -s OLLMchat TLS GLib-GIO
```

Expect `GTlsBackendOpenssl`, `supports_tls=1`, and `Soup.Session tls_database=.../ca-certificates.crt`.

**APK must not contain** `assets/share/gio/modules/libgioopenssl.so`.

---

## Further reading

- [gtk-android-builder#20](https://github.com/sp1ritCS/gtk-android-builder/issues/20) — static `g_io_openssl_load()` pattern (Tuba, GStreamer on Android).
- [GLib #3449](https://gitlab.gnome.org/GNOME/glib/-/work_items/3449) — long-term Android platform glue in GLib (not urgent for this POC).
- Historical debug log (dynamic modules era): [`docs/bugs/done/2026-06-17-FIXED-android-runtime-tls-ime-paste.md`](bugs/done/2026-06-17-FIXED-android-runtime-tls-ime-paste.md).
