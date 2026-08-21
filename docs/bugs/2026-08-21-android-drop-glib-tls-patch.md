# Android: drop leftover GLib TLS scan patch

**Status:** ⏳ device HTTPS test of APK built without `tls-ensure-before-scan.patch`

**Opened:** 2026-08-21

## Problem

- 🔷 GLib was frozen at 2.84.0 so a TLS patch on `g_io_modules_scan_all_in_directory_with_scope` would apply. That freeze then forced pango/libadwaita pins when `main` moved.
- 🔷 TLS on Android is already app-only: `g_io_openssl_load(NULL)` (`docs/plans/done/9.2-DONE-android-tls-migration.md`). The scan patch is leftover from the rejected GIO-module path.
- 🔷 Remove that patch, keep `hack.patch` (`g_set_user_dirs` visibility), build a test APK. HTTPS to the server should fail immediately if the scan patch was still required.

## Evidence

- ℹ️ `ollmapp/android/android-gio-tls.c` calls `g_io_openssl_load(NULL)` then `g_tls_backend_get_default()`.
- ℹ️ Plan 9.2 Keep vs drop: GLib ensure-before-scan listed as drop / optional follow-up, not the ship path.

## Proposed fix

- 🔷 Remove `tls-ensure-before-scan.patch` from `glib.wrap` `diff_files` and delete the patch file.
- 🔷 Revert local `subprojects/glib/gio/giomodule.c` so the APK is not still linking the patched object.
- 🚫 Do not bump glib / unpin pango in this APK — one variable: TLS scan patch gone.

## Attempts / changelog

- ✔️ 2026-08-21 — wrap no longer lists the TLS patch; R13 asserts the file is absent; `hack.patch` stays.
- ✔️ 2026-08-21 — APK: `.pixiewood/android/app/build/outputs/apk/debug/app-arm64-v8a-debug.apk` (glib 2.84.0, no scan patch).
- ⏳ Device: cold start logcat `OLLMchat TLS`, then connect to the server.
