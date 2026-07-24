# 2026-07-22 — Android browser globe toggle one-way

**Status:** ✅ FIXED — user verified 2026-07-24

## Problem

- 🔷 Globe toggle shows browser, but cannot return to chat.
- 🔷 Suspected: need hide / visibility forward on Android WebView host.

## Root cause

- ✔️ System WebView is an Android `View` via `addContentView`, not a GTK child. Gtk.Stack unmaps the Vala widget but **never** called `wka_host_put_is_visible(false)`, so the live WebView stays `VISIBLE` above the GTK `SurfaceView` and blocks the chat + toggle.
- ℹ️ API already exists (`WebViewHost.setVisible` / `wka_host_put_is_visible`); Vala never invoked it on map/unmap. Plan: sibling `1.0` “Forward show/hide”.

## Fix

- 🔷 On `host_area` **map** (after attach): `wka_host_put_is_visible(true)`.
- 🔷 On `host_area` **unmap**: `wka_host_put_is_visible(false)`.
- 🔷 Skip bounds tick updates while unmapped.
- ✔️ Implemented in `subprojects/webkitgtk-android/.../WebView.vala`; APK rebuilt/installed 2026-07-22.
- ✔️ Also added `web-browser-symbolic` to `android/icons/manifest` (Adwaita legacy).
