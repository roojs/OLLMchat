# FIXED: Android — drop leftover GLib TLS scan patch

**Status:** ✅ FIXED — wrap no longer lists `tls-ensure-before-scan.patch`; R13 asserts it is absent. User closed.

---

## Problem

GLib was frozen at 2.84.0 so a TLS patch on `g_io_modules_scan_all_in_directory_with_scope` would apply. That freeze then forced pango/libadwaita pins when `main` moved. TLS on Android is already app-only: `g_io_openssl_load(NULL)` (plan 9.2). The scan patch was leftover from the rejected GIO-module path.

## Fix

Removed `tls-ensure-before-scan.patch` from `android/pixiewood-wraps/glib/glib.wrap` `diff_files`. `hack.patch` (`g_set_user_dirs` visibility) stays. R13 fails if the scan patch ships.

ℹ️ Device HTTPS cold-start was the leftover runtime check; compile / wrap side is done.
