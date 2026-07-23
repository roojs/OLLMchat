# 2026-07-23 — Android A11y dump must use refresh_async

**Status:** ✔️ applied in `libocwebkit/A11y.vala` — await device ✅

**Related:** webkitgtk-android [`docs/bugs/2026-07-23-a11y-walk-gtk-thread-anr.md`](../../subprojects/webkitgtk-android/docs/bugs/2026-07-23-a11y-walk-gtk-thread-anr.md) (**Report for OLLMchat**)

## Problem

- 🔷 Sync a11y walk from GTK caused ANR with IME `blockForMain` (library root cause).
- 🔷 Library fixed with async walk + `AndroidAtspi.refresh_async()`; OLLMchat still called `dump_sync` / `fill_sync` / `press_sync` directly on Android.

## Fix

- 🔷 Android `dump` / `fill` / `press`: `yield refresh_async()` then existing sync parse/action body against the refreshed facade tree.
- 🔷 Windows unchanged (COM UI thread). Linux unchanged (GLib worker).
- ✔️ Class docblock: Android is async handoff to Android UI, not “stay on JNI UI thread”.

## Next

- ⏳ Rebuild/install APK with updated webkitgtk-android; browser dump while entry focused — no ANR; logcat shows `walkAsync`, not `refusing sync`.
