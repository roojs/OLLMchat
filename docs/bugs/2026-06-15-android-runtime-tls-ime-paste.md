# Android runtime: TLS, IME delete, nested-dialog paste (OPEN)

**Date:** 2026-06-15  
**Symptom:** CI green + `verify-apk.sh` pass on run 27614072148, but on device: HTTPS/TLS
still unavailable, hold-backspace deletes one character only, long-press paste in nested
dialogs still broken.

## Root cause (build vs runtime)

`verify-apk.sh` only proved patch **strings** were present in `libgtk-4.so` and
`classes.dex`. It did **not** prove those fixes work at runtime.

### TLS

`libgioopenssl.so` is extracted to `filesDir/share/gio/modules/`. `dlopen` of that path
does not resolve `libssl.so` / `libcrypto.so` from `lib/arm64-v8a/` (jniLibs). The GIO
module loads but the TLS backend never registers — libsoup HTTPS fails.

**Fix:** Copy OpenSSL runtimes beside `libgioopenssl.so` in APK assets; preload with
`RTLD_GLOBAL` before `g_io_modules_scan_all_in_directory` in `gdkandroidruntime.c` and
`ollmapp/android/android-gio-tls.c`.

### IME hold-delete / paste

Patches were present in APK artifacts but `syncEditableFromGtk` was not applied on all IME
paths (`setComposingText`, `finishComposingText`). Popup geometry patch did not sync
parent surface position before layout for nested Adw dialogs.

**Fix:** android-bugs.patch v2 — broader IME sync, parent surface position in
`gdk_android_popup_present`, runtime tag `ollmchat-android-bugs-v2`.

## Verification

After next CI build:

1. Install APK from that run (uninstall old app first if unsure).
2. Check `filesDir/share/ollmchat-android-runtime.tag` contains `v2` (or grep APK).
3. TLS: connection check should succeed for HTTPS Ollama endpoints.
4. IME: hold backspace in a text field; long-press paste in a nested dialog.

## Changelog

- `install_gio_modules_to_assets`: ship `libssl`/`libcrypto` beside GIO module; runtime tag file.
- `android-gio-tls.c`: preload OpenSSL before module scan.
- `android-bugs.patch`: v2 marker, runtime OpenSSL preload, parent popup sync, IME sync paths.
- `verify-apk.sh`: v2 tag, OpenSSL assets, popup comment string.
