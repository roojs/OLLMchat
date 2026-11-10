# Pixiewood packaging

**Status:** ⏳ open. The Android job now links published `.pixie` files, including `webkitgtk-android` from its GitHub Pages pin list, and a version tag publishes this tree's libraries. Not verified in CI yet. The webkit pin list has to be live before that job can succeed.

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
- ✔️ 2026-11-10. `PIXIEWOOD_USE_PIXIE=1` on the GitHub Android job. `gtk` is `android/pixie-gtk.pins` (Knowles/gtk `4.25.1`). The other libraries come from `https://roojs.github.io/pixiewood-pkgs/release.pins`, plus `fontconfig` from `snapshot.pins` on that site.
- 🔷 Dependencies listed in that sysroot's `MANIFEST.json` are not compiled from `android/pixiewood-wraps/`.
- ✔️ 2026-11-10. `webkitgtk-android` is appended from `https://roojs.github.io/webkitgtk-android/release.pins`. The pixie job does not install that wrap. The from-source job still does.
- 🚫 Use the unpatched gnome `gtk` pin. The Android job uses the Knowles/gtk file in `android/pixie-gtk.pins`.
- 🚫 Vendor another copy of the GTK sources inside this tree.

### 2. Export the libraries

- ✔️ 2026-11-10. A version tag packs every Android library the build installed (`ocsqlite`, `ocrpc`, `ocmarkdown`, `ollamaweb`, `ochf`, `ocmarkdowngtk`, `ocfiles`, `ollmchat`, `ocwebkit`, `ocmcp`, `octools`, `occoder`, `ollmchatgtk` — whichever `.so` is present), uploads `<name>-arm-v31-<version>.pixie` on the version release, commits `release.pins` on `main`, and publishes that list at `https://roojs.github.io/OLLMchat/release.pins`.
- 🔷 Pins for the shared stack stay on `roojs/pixiewood-pkgs`. This distribution uploads only the libraries built here.
- ℹ️ Which siblings of `libocrpc` Argus links on Android is outside this tree. The Android POC already builds the set in Evidence.
- 🚫 Teach the Argus workflow from this bug. Argus is not in this tree.

## Attempts / changelog

- ✔️ 2026-11-08. Read pixiewood-pkgs `README.md`, `current.pins`, `build-order.txt`, `docs/plans.md`, `docs/own-distribution.md`, and `docs/pixiewood-sysroot.md`. Confirmed zero GitHub releases.
- ✔️ 2026-11-10. pixiewood-pkgs `release.pins` on `main` points at GitHub release `1.261109` (openssl through glib-networking, arm64-v8a). `fontconfig` is only on `snapshot.pins`. Knowles/gtk tag `4.25.1-20261110g-pixie` published `gtk-arm-v31-4.25.1.pixie` (17 108 844 bytes, sha256 `d3b5bbcfa75dd6dbbd467be435d6b94e774a58a80ae40b403bc8a02fa5b7cc6e`). The generic download by numeric project id returns 404; `projects/Knowles%2Fgtk/packages/generic/...` returns the file. The archive's `ImContext.java` has `syncEditableFromGtk`. `libgtk-4.so` does not contain `ollmchat-android-bugs-v16`.
- ✔️ 2026-11-10. Android CI sets `PIXIEWOOD_USE_PIXIE=1`. `scripts/android/fetch-pixie-deps.sh` merges the pixiewood-pkgs GitHub Pages release and snapshot pins, replaces `gtk` from `android/pixie-gtk.pins`, and appends `webkitgtk-android` from `https://roojs.github.io/webkitgtk-android/release.pins`. The APK manifest drops dependencies listed in the sysroot and points Java glue at the pixie tree. The pixie job removes the `webkitgtk-android` wrap and copies `WebViewHost` Java from the package. A tag release runs `scripts/android/pack-pixie-libs.sh`, uploads each library `.pixie` on the version release, commits `release.pins` on `main`, and deploys that file onto the existing Valadoc Pages site.
- ✔️ 2026-11-10. pixie-pkg reads `https://roojs.github.io/pixiewood-pkgs/release.pins` and `snapshot.pins`. `PIXIE_REPO` still reads a git branch, so consumers of this tree use `--pins https://roojs.github.io/OLLMchat/release.pins`.

## Next

- ✔️ 2026-11-10. Local `PIXIEWOOD_USE_PIXIE=1` build produced `app-arm64-v8a-debug.apk` (verify OK, runtime tag `pixie-gtk`). The 24 packages stay in `.pixiewood/pixie` (127 MB). A second fetch did not download them again. That pass still built `webkitgtk-android` from the wrap. The next fetch expects the published package and replaces that tree.
- ✔️ 2026-11-10. Release `v1.4.10` Android job `129764971985` configured the pixie sysroot (`webkitgtk-android-1` 0.1.6) and stopped in valac: `Package gee-0.8 not found`. The runner has no `libgee-dev`. The VAPI is `share/vala/vapi/gee-0.8.vapi` in the sysroot. `meson.build` adds that directory when gee is a pkg-config dependency.
- ⏳ 🔷 Run Release - Android again and confirm the APK links the pixie sysroot (runtime tag `pixie-gtk`, IME handlers still in `classes.dex`).
- ⏳ 🔷 On the next version tag, confirm `https://roojs.github.io/OLLMchat/release.pins` lists every library the Android build installed, each URL downloads, and `https://roojs.github.io/OLLMchat/ollmchat/index.htm` is still Valadoc.
