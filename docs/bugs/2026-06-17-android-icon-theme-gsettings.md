# Android: icon theme set via `g_setenv` in TLS init (wrong place)

**Status:** OPEN  
**Opened:** 2026-06-17  
**Package:** `org.roojs.ollmchat.androidpoc` (chat POC); same pattern in any Android target using `ollmapp_configure_android_gio_tls_modules()`

**Related:** [`docs/android-build.md`](../android-build.md) (GTK icons / Adwaita manifest), [`docs/android-tls-solution.md`](../android-tls-solution.md) (TLS init — unrelated to icons)

---

## Problem

Android has no gsettings default for `gtk-icon-theme-name`. The chat POC ships a curated Adwaita subset under `assets/share/icons/Adwaita/` (see `android/icons/manifest`), but GTK still needs to know the theme name is `Adwaita`.

Today that is done inside `ollmapp_configure_android_gio_tls_modules()` in `ollmapp/android/android-gio-tls.c`:

```c
if (g_getenv ("GTK_ICON_THEME_NAME") == NULL)
  g_setenv ("GTK_ICON_THEME_NAME", "Adwaita", TRUE);
```

This runs on every success/failure path through TLS module configuration.

**Expected:** Icon theme is configured in application/GTK startup code (e.g. `Gtk.Settings` in `AndroidApplication`), not in TLS init.

**Actual:** Icon theme is piggybacked on TLS setup via `g_setenv`.

**Why it matters (not about icons per se):**

1. **Wrong layer** — TLS init should only register the GIO TLS backend and CA trust; icon theme is unrelated.
2. **`g_setenv` on Android** — gtk-android-builder maintainers advise against `g_setenv` after the process is multi-threaded (GDK Java thread + GTK thread). Icon-theme env mutation shares that risk even though it is not a TLS bug.
3. **Confusing maintenance** — reviewers and future readers assume `android-gio-tls.c` is networking/TLS only.

---

## Reproduction

1. Build and install chat POC APK.
2. Inspect `ollmapp/android/android-gio-tls.c` — `GTK_ICON_THEME_NAME` appears on multiple branches of `ollmapp_configure_android_gio_tls_modules()`.
3. Header bar / symbolic icons still work because env is set before `GtkApplication` runs; the issue is **where** and **how**, not missing icons today.

---

## What we tried

| Attempt | Result |
|---------|--------|
| Set `GTK_ICON_THEME_NAME` in `android-gio-tls.c` early in `main()` | Works on device; wrong responsibility |
| Ship icons via `android/icons/manifest` + Pixiewood asset staging | Works; does not remove need for theme **name** |

---

## Conclusions

- **Root cause:** Convenience — `main()` already calls TLS init first, so icon theme was added there instead of proper GTK settings.
- **Not a TLS regression** — removing `g_setenv` from `android-gio-tls.c` is safe once theme is set elsewhere.
- **Proposed fix (pending approval):** In `AndroidApplication` (or first window setup), set `Gtk.Settings.gtk_icon_theme_name = "Adwaita"` (or equivalent). Delete all `GTK_ICON_THEME_NAME` / `g_setenv` blocks from `android-gio-tls.c`. Update `docs/android-build.md` to point at Vala startup, not TLS C init.

---

## Open questions

- Should theme name live in a single Android startup helper used by chat POC (and any future Android target)?
- Does `Gtk.Settings` need to run before or after `Gtk.Application` construction? Verify on device after move.
