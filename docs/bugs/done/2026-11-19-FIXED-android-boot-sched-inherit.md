# Android chat POC aborts during boot in g_thread_new

**Status:** ✅

**Started:** 2026-11-19

**Package:** `org.roojs.ollmchat.androidpoc` on SM-S9380 (`adb-R5CY134DA0W`), wireless debugging.

## Problem

- 🔷 Launching the pixie debug APK dies before the window. Expected: `ToplevelActivity` stays up.
- 🔷 Actual: process aborts in `RuntimeApplication.onCreate` while GTK starts its first worker.

## Evidence

- ✔️ 2026-11-19 09:11:15 and again 09:17:48, logcat `libc`: `pthread_create sched_setscheduler(1073741825, {1}) call failed: Operation not permitted`.
- ✔️ Same instant, `GLib`: `gthread-posix.c: line 774 (g_system_thread_new): error 'Operation not permitted' during 'pthread_create'`, then SIGABRT. Policy `1073741825` is `SCHED_FIFO | SCHED_RESET_ON_FORK`, priority 1.
- ✔️ Tombstone stack: `OllmApplication.onCreate` → `RuntimeApplication.onCreate` → `libgtk-4.so` → `g_thread_new`.
- ℹ️ Pixie GLib is 2.90. `subprojects/glib/glib/gthread-posix.c` calls `pthread_attr_setinheritsched(&attr, PTHREAD_INHERIT_SCHED)` before `pthread_create`. Bionic, on a parent with `SCHED_RESET_ON_FORK`, re-applies that policy to the new thread and returns EPERM. GLib treats every `pthread_create` error except EAGAIN as fatal.

## Attempts

- ✔️ `sched_setscheduler(0, SCHED_OTHER, …)` from `libandroid-sched.so` at the start of `OllmApplication.onCreate`, before `super.onCreate()`. Logcat showed the library loaded (`nativeloader` … `libandroid-sched.so` … `ok`) and the same `sched_setscheduler(1073741825, {1})` failure 180 ms later. The app cannot drop the realtime policy. That library and the Java call are being removed.

## Root cause

- ✔️ GLib 2.90 asks the new thread to inherit the main thread's scheduler. On this phone that inheritance is not permitted, and GLib aborts.
- ✔️ The APK's `libglib-2.0.so` is the pixie build from 2026-11-09 (same file as `.pixiewood/pixie/lib/arm64-v8a/libglib-2.0.so`). Editing the subproject does not change the library inside this APK. That so's JUMP_SLOT for `pthread_attr_setinheritsched` is at vaddr `0x295fc8`, in the RELRO GOT.

## Proposed fix

- 🚫 2026-11-19 — patching `gthread-posix.c`, and rewriting that symbol from the app, are not an acceptable fix. Both are removed. `glib.wrap` lists only `hack.patch`. `android-sched.c` is gone. Leftover `libandroid-sched.so` files under `.pixiewood` are deleted.
- 🔷 The published pixie GLib (`1.261109`, 2.90.1) was built without the gtk-android-builder pthread patch. Argus on this phone runs a 2.90.1 built with that patch and starts. Rebuild that pixie package. `scripts/android/fetch-pixie-deps.sh` now compares the published pin list with `share/pixiewood/pixie.pins` and downloads again when it differs.

- ✅ User closed this on 2026-11-26. The boot abort is fixed.

## Next

- ✔️ 2026-11-19 09:29, pid 19116: with the slot rewrite, logcat said `glib worker scheduler set to normal` and `ToplevelActivity` stayed resumed. That rewrite is no longer in the tree.
- ⏳ 🔷 After the patched glib is published, the next pixie build downloads it and the APK is installed again.
