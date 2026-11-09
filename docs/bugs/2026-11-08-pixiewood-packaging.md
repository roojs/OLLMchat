# Pixiewood packaging

**Status:** ⏳ open. [pixiewood-pkgs](https://github.com/roojs/pixiewood-pkgs) is the distribution. This APK still compiles the GTK stack from source, and this tree does not publish Android library bundles. Stays open until both parts below are done.

**Pointer:** `docs/bug-fix-process.md`, `docs/android-build.md`

## Problem

- 🔷 The Android build uses the prebuilt packages from [roojs/pixiewood-pkgs](https://github.com/roojs/pixiewood-pkgs). It does not fetch and compile GTK, GLib, and the rest of that stack from source.
- 🔷 This tree publishes its own Android library bundles, so another project such as Argus can link the RPC layer without compiling OLLMchat.
- 🔷 Some dependencies this APK needs are not in that distribution yet. The bug stays open until those exist and both parts above are in place.

## Evidence

- ✔️ `android/pixiewood-chat-poc.xml` names glib, fontconfig, gtk, libadwaita, gtksourceview, libxml2, sqlite3, gee, json-glib, nghttp2, libsoup, openssl, and glib-networking as Pixiewood dependencies. Prepare writes wraps and compiles them. GTK is patched with `android/pixiewood-wraps/gtk/android-bugs.patch` (`<patch>android-bugs</patch>`). The wrap pin is `ae709f962a51f9108a1e6381bcfbd05bbaecc840`.
- ✔️ The Android POC (`-Dandroid_poc=true`) also builds `libocsqlite`, `libocrpc`, `libocfiles`, `libocmarkdown`, `libocmarkdowngtk`, `libollamaweb`, `libollmchat`, `libocwebkit`, `libollmchatgtk`, and `liboccoder`. `libocwebkit` uses the `webkitgtk-android` wrap. Nothing in the Android job uploads those libraries as a consumer package.
- ℹ️ pixiewood-pkgs `current.pins` (2026-11-08) names release `1.261108` for the `gnome` target, arm64-v8a, from openssl through glib-networking. The `gtk` line is the same commit as `gtk.wrap`. `packages/gtk/targets` is unpatched upstream GNOME (`patch` column `-`).
- ℹ️ That repository has no GitHub releases. The tarball URLs in `current.pins` have nowhere to download from.
- ℹ️ `docs/plans.md` there keeps the Android IME branch and webkitgtk-android out of this distribution. IME packages would be published from `Knowles/gtk` branch `android-ime`. webkitgtk-android would be published from `roojs/webkitgtk-android`.
- ℹ️ `docs/own-distribution.md` is the contract for a second distribution: clone one git repo, read `current.pins`, download one `.pixie` bundle per package, and point unchanged packages at `roojs/pixiewood-pkgs`. The publisher in that repo still writes `.tar.xz` URLs. `current.pins` does not use the `.pixie` columns yet.
- ℹ️ `docs/pixiewood-sysroot.md` is how an application build consumes a sysroot: `--sysroot` after `integration/0001-sysroot-prebuilt-dependencies.patch`, or `scripts/meson-wrapper.sh` plus `scripts/stage-runtime.sh` on stock Pixiewood.

## Root cause

- ✔️ The Android job is a from-source Pixiewood build. pixiewood-pkgs is the place that publishes the shared stack, and it has not published a release. This tree has no Android equivalent of the Windows library packages, so a consumer has nothing to download for the RPC layer.

## Proposed fix

### 1. Build the APK from the packages

- 🔷 When release `1.261108` (or the release that replaces it) has assets, the Android job downloads that sysroot and builds `ollmchat-android-poc` against it.
- 🔷 Dependencies listed in that sysroot's `MANIFEST.json` are not compiled from `android/pixiewood-wraps/`.
- ⏳ 🔷 The IME patch stays until a `Knowles.android-ime` bundle exists. Unpatched `gnome` GTK does not replace `android-bugs.patch`.
- ⏳ 🔷 `webkitgtk-android` stays a wrap until `roojs/webkitgtk-android` publishes its `.pixie`. The browser library is not in the gnome set.
- 🚫 Switch the APK to the gnome sysroot while those two dependencies are still missing.
- 🚫 Vendor another copy of the GTK sources inside this tree.

### 2. Export the libraries

- 🔷 This repository publishes Android bundles of the libraries a consumer links, following `docs/own-distribution.md` in pixiewood-pkgs. Argus downloads those bundles and links the RPC layer (`libocrpc`). It does not configure or compile this tree.
- 🔷 Pins for the shared stack stay on `roojs/pixiewood-pkgs`. This distribution uploads only the libraries built here.
- ℹ️ Which siblings of `libocrpc` Argus links on Android is outside this tree. The Android POC already builds the set in Evidence.
- 🚫 Teach the Argus workflow from this bug. Argus is not in this tree.

## Attempts / changelog

- ✔️ 2026-11-08. Read pixiewood-pkgs `README.md`, `current.pins`, `build-order.txt`, `docs/plans.md`, `docs/own-distribution.md`, and `docs/pixiewood-sysroot.md`. Confirmed zero GitHub releases.

## Next

- ⏳ 🔷 Wait until pixiewood-pkgs publishes the gnome bundles, and until the IME GTK and webkitgtk-android bundles exist.
- ⏳ 🔷 Then do part 1 (APK links the sysroot) and part 2 (this tree publishes the RPC libraries).
